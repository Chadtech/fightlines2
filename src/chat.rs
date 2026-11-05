//! URL-accessible conversation state, independent of battlefield authorization.
use crate::{
    graphql::Context, lobby_id::LobbyId, player::Player, player_number::PlayerNumber, server_log,
    session_token::SessionToken, storage_budget, store::GameRegistry,
};
use juniper::{FieldResult, GraphQLInputObject, GraphQLObject};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_MESSAGES: usize = 1000;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, GraphQLObject)]
pub struct ChatMessage {
    pub sequence: i32,
    pub sent_at: String,
    /// Zero denotes the lobby; positive numbers denote the current planning turn.
    pub turn_number: i32,
    pub sender: String,
    pub player_number: Option<PlayerNumber>,
    pub text: String,
}

#[derive(GraphQLInputObject)]
pub struct SendChatInput {
    pub id: String,
    pub message_id: String,
    pub text: String,
}

#[derive(Clone, PartialEq)]
struct MessageId(String);

pub struct Draft {
    id: MessageId,
    text: MessageText,
}

struct MessageText(String);

#[derive(Clone)]
struct AcceptedMessage {
    message: ChatMessage,
    session: SessionToken,
    id: MessageId,
}

#[derive(Clone, Default)]
pub struct Transcript {
    accepted: Vec<AcceptedMessage>,
}

pub struct Sender {
    name: String,
    player_number: Option<PlayerNumber>,
}

pub struct Submission {
    pub session: SessionToken,
    pub sender: Sender,
    pub turn_number: i32,
    pub draft: Draft,
}

impl Draft {
    pub fn parse(input: &SendChatInput) -> FieldResult<Self> {
        Ok(Self {
            id: MessageId::parse(input.message_id.clone())?,
            text: MessageText::parse(&input.text)?,
        })
    }
}

impl MessageText {
    fn parse(value: &str) -> FieldResult<Self> {
        let text = value.trim();
        if text.is_empty() || text.chars().count() > 500 || text.chars().any(char::is_control) {
            return Err("enter a message between 1 and 500 characters on one line.".into());
        }
        Ok(Self(text.into()))
    }
}

impl Sender {
    pub fn for_session(players: &[Player], session: &SessionToken) -> Self {
        match players
            .iter()
            .find(|player| player.controller.session() == Some(session))
        {
            Some(player) => Self {
                name: player.name.to_string(),
                player_number: Some(player.player_number),
            },
            None => Self {
                name: "visitor".into(),
                player_number: None,
            },
        }
    }
}

impl Transcript {
    pub fn messages(&self, after: i32) -> Vec<ChatMessage> {
        self.accepted
            .iter()
            .filter(|entry| entry.message.sequence > after)
            .map(|entry| entry.message.clone())
            .collect()
    }

    /// Publish on disk before acknowledging or changing memory. A browser retry
    /// uses the same ID even if the turn or the sender's lobby side has changed.
    pub fn send(
        &mut self,
        submission: Submission,
        persist: impl FnOnce(&ChatMessage) -> FieldResult<()>,
    ) -> FieldResult<ChatMessage> {
        let Draft { id, text } = submission.draft;
        if let Some(previous) = self
            .accepted
            .iter()
            .find(|entry| entry.session == submission.session && entry.id == id)
        {
            if previous.message.text != text.0 {
                return Err("this message id was already used for different text.".into());
            }
            return Ok(previous.message.clone());
        }
        if self.accepted.len() >= MAX_MESSAGES {
            return Err(storage_budget::full(
                "this conversation has reached its 1000-message limit.",
            ));
        }
        let sequence = i32::try_from(self.accepted.len())
            .ok()
            .and_then(|count| count.checked_add(1))
            .ok_or("the conversation is full.")?;
        let sent_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| {
                tracing::error!(event = "chat_clock_failed", error = %error, "could not timestamp chat");
                server_log::internal_error("chat is temporarily unavailable.")
            })?
            .as_millis()
            .to_string();
        let message = ChatMessage {
            sequence,
            sent_at,
            turn_number: submission.turn_number,
            sender: submission.sender.name,
            player_number: submission.sender.player_number,
            text: text.0,
        };
        persist(&message)?;
        self.accepted.push(AcceptedMessage {
            message: message.clone(),
            session: submission.session,
            id,
        });
        Ok(message)
    }
}

impl MessageId {
    fn parse(value: String) -> FieldResult<Self> {
        if value.is_empty()
            || value.len() > 64
            || !value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
        {
            return Err("invalid chat message id.".into());
        }
        Ok(Self(value))
    }
}

pub fn messages(context: &Context, id: LobbyId, after: i32) -> FieldResult<Vec<ChatMessage>> {
    if after < 0 {
        return Err("invalid chat sequence.".into());
    }
    let entry = context
        .store
        .entry(&id)?
        .ok_or("this conversation no longer exists.")?;
    let entry = entry.lock().map_err(|_| unavailable())?;
    Ok(match &*entry {
        GameRegistry::Closed => return Err("this conversation no longer exists.".into()),
        GameRegistry::Lobby(lobby) => lobby.chat_messages(after),
        GameRegistry::Game(game) => game.chat_messages(after),
    })
}

pub fn send(context: &Context, input: SendChatInput) -> FieldResult<ChatMessage> {
    let draft = Draft::parse(&input)?;
    let id = LobbyId::from_token(input.id);
    let entry = context
        .store
        .entry(&id)?
        .ok_or("this conversation no longer exists.")?;
    let session = match context.identity() {
        Some(session) => session,
        None => {
            let session = SessionToken::from_token(context.store.next_token()?);
            // Persist the visitor's identity even on rejection, so retries remain
            // scoped to the same browser without granting game membership.
            context.set_identity(session.clone());
            session
        }
    };
    let mut entry = entry.lock().map_err(|_| unavailable())?;
    match &mut *entry {
        GameRegistry::Closed => Err("this conversation no longer exists.".into()),
        GameRegistry::Lobby(lobby) => lobby.send_chat(context, session, draft),
        GameRegistry::Game(game) => game.send_chat(session, draft),
    }
}

pub fn recording_error(error: std::io::Error) -> juniper::FieldError {
    if error.kind() == std::io::ErrorKind::StorageFull {
        return storage_budget::full("chat storage is full. new messages cannot be saved.");
    }
    tracing::error!(event = "chat_record_failed", error = %error, "could not record chat");
    server_log::internal_error("message not sent. please try again.")
}

fn unavailable() -> juniper::FieldError {
    tracing::error!(
        event = "server_state_lock_unavailable",
        "chat state lock is poisoned"
    );
    server_log::internal_error("chat is temporarily unavailable.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};
    use crate::{
        environment::Environment, game_archive, game_log, graphql, seed::Seed, store::Store,
    };
    use actix_web::{App, test as web_test, web};
    use serde_json::{Value, json};
    use std::fs;

    macro_rules! execute {
        ($app:expr, $query:expr, $cookie:expr) => {{
            let mut request = web_test::TestRequest::post().uri("/graphql")
                .set_json(json!({ "query": $query }));
            if let Some(cookie) = $cookie { request = request.cookie(cookie); }
            let response = web_test::call_service($app, request.to_request()).await;
            let cookie = response.response().cookies().next().map(|cookie| cookie.into_owned());
            let body: Value = web_test::read_body_json(response).await;
            (body, cookie)
        }};
    }

    fn send_query(id: &str, message_id: &str, text: &str) -> String {
        format!(
            "mutation {{ sendChat(input: {{id: {id:?}, messageId: {message_id:?}, text: {text:?}}}) {{ sequence turnNumber sender playerNumber text sentAt }} }}"
        )
    }

    #[actix_web::test]
    async fn chat_survives_start_is_url_accessible_and_is_durable_before_acknowledgment()
    -> TestResult {
        let root = std::env::temp_dir().join(format!(
            "fightlines-chat-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let store = web::Data::new(
            Store::new(Seed::new([57; 32]))
                .with_game_logs(game_log::Directory::open(root.clone())?),
        );
        let app = web_test::init_service(
            App::new()
                .app_data(store)
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .app_data(web::Data::new(game_archive::Browser {
                    directory: root.clone(),
                }))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let (created, host) = execute!(
            &app,
            "mutation { createLobby(name: \"Alice\", lobbyName: \"Chat test\") { id } }",
            None
        );
        let host = host.fixture()?;
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let (invalid, identity) = execute!(&app, send_query(id, "invalid", ""), None);
        assert!(invalid.get("errors").is_some(), "{invalid}");
        assert!(identity.is_none());
        assert!(fs::read_dir(&root)?.next().is_none());
        let (first, _) = execute!(
            &app,
            send_query(id, "lobby-first", "hello <b>world</b>"),
            Some(host.clone())
        );
        assert!(first.get("errors").is_none(), "{first}");
        assert_eq!(first["data"]["sendChat"]["turnNumber"], 0);
        let (joined, guest) = execute!(
            &app,
            format!("mutation {{ joinLobby(id: {id:?}, name: \"Bob\") {{ id }} }}"),
            None
        );
        assert!(joined.get("errors").is_none(), "{joined}");
        let guest = guest.fixture()?;
        let (second, _) = execute!(
            &app,
            send_query(id, "guest-lobby", "ready"),
            Some(guest.clone())
        );
        assert_eq!(second["data"]["sendChat"]["sequence"], 2);
        let (started, _) = execute!(
            &app,
            format!("mutation {{ startGame(id: {id:?}) {{ gameUrl }} }}"),
            Some(host.clone())
        );
        assert!(started.get("errors").is_none(), "{started}");
        let (retry, _) = execute!(
            &app,
            send_query(id, "lobby-first", "hello <b>world</b>"),
            Some(host.clone())
        );
        assert_eq!(retry["data"], first["data"]);
        let (host_message, _) = execute!(
            &app,
            send_query(id, "host-first-in-game", "welcome to the game"),
            Some(host.clone())
        );
        assert_eq!(host_message["data"]["sendChat"]["sequence"], 3);
        let (guest_entry, _) = execute!(
            &app,
            format!(
                "{{ game(id: {id:?}) {{ turnNumber }} chat(id: {id:?}, after: 0) {{ sequence turnNumber text }} }}"
            ),
            Some(guest.clone())
        );
        assert!(guest_entry.get("errors").is_none(), "{guest_entry}");
        let entry_message = guest_entry["data"]["chat"]
            .as_array()
            .fixture()?
            .last()
            .fixture()?;
        assert_eq!(entry_message["text"], "welcome to the game");
        assert_eq!(entry_message["turnNumber"], 1);
        let (visitor, visitor_cookie) =
            execute!(&app, send_query(id, "visitor-first", "hello"), None);
        assert!(visitor.get("errors").is_none(), "{visitor}");
        assert_eq!(visitor["data"]["sendChat"]["sequence"], 4);
        assert_eq!(visitor["data"]["sendChat"]["sender"], "visitor");
        assert!(visitor["data"]["sendChat"]["playerNumber"].is_null());
        let (hidden, _) = execute!(
            &app,
            format!("{{ game(id: {id:?}) {{ turnNumber }} }}"),
            visitor_cookie
        );
        assert!(hidden.get("errors").is_some());
        let (history, _) = execute!(
            &app,
            format!("{{ chat(id: {id:?}, after: 0) {{ sequence text }} }}"),
            None
        );
        assert_eq!(history["data"]["chat"].as_array().fixture()?.len(), 4);
        let path = fs::read_dir(&root)?
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .find(|entry| entry.file_name().to_string_lossy().starts_with(id))
            .fixture()?
            .path();
        let archived = game_log::Archive::read(&path)?;
        assert_eq!(archived.chat.len(), 4);
        assert_eq!(archived.chat.first().fixture()?.text, "hello <b>world</b>");
        assert!(archived.submissions.is_empty());
        // A missing storage directory makes publication fail. Neither memory nor
        // sequence numbers advance, and the same request succeeds after repair.
        let offline = root.join("offline");
        fs::rename(&path, &offline)?;
        let (failed, _) = execute!(
            &app,
            send_query(id, "disk-retry", "keep this draft"),
            Some(guest.clone())
        );
        assert!(failed.get("errors").is_some());
        let (empty, _) = execute!(
            &app,
            format!("{{ chat(id: {id:?}, after: 4) {{ sequence }} }}"),
            None
        );
        assert_eq!(empty["data"]["chat"], json!([]));
        fs::rename(&offline, &path)?;
        let (repaired, _) = execute!(
            &app,
            send_query(id, "disk-retry", "keep this draft"),
            Some(guest.clone())
        );
        assert_eq!(repaired["data"]["sendChat"]["sequence"], 5);
        assert_eq!(repaired["data"]["sendChat"]["sender"], "Bob");
        let (resigned, _) = execute!(
            &app,
            format!("mutation {{ resignGame(id: {id:?}) {{ turnNumber }} }}"),
            Some(host.clone())
        );
        assert!(resigned.get("errors").is_none(), "{resigned}");
        let (after_game, _) = execute!(&app, send_query(id, "after-game", "gg"), Some(guest));
        assert_eq!(after_game["data"]["sendChat"]["sequence"], 6);
        let archive_id = path.file_name().fixture()?.to_str().fixture()?;
        let (replay, _) = execute!(
            &app,
            format!(
                "{{ loggedGame(id: {archive_id:?}) {{ chat {{ sequence turnNumber text }} }} }}"
            ),
            None
        );
        assert_eq!(
            replay["data"]["loggedGame"]["chat"]
                .as_array()
                .fixture()?
                .len(),
            6
        );
        assert!(game_log::replay(&path)?.contains("Verified 1 submission"));
        let serialized = fs::read_dir(&path)?
            .map(|entry| fs::read_to_string(entry?.path()))
            .collect::<Result<Vec<_>, _>>()?
            .join("");
        assert!(!serialized.contains(host.value()));
        fs::remove_dir_all(root)?;
        Ok(())
    }

    fn submission(id: &str, text: &str) -> FieldResult<Submission> {
        Ok(Submission {
            session: SessionToken::from_token("private-cookie".into()),
            sender: Sender {
                name: "Alice".into(),
                player_number: Some(PlayerNumber::Player1),
            },
            turn_number: 1,
            draft: Draft::parse(&SendChatInput {
                id: "test".into(),
                message_id: id.into(),
                text: text.into(),
            })?,
        })
    }

    #[test]
    fn validation_durability_and_idempotent_retries() -> TestResult<()> {
        let mut transcript = Transcript::default();
        for text in ["".into(), " \t ".into(), "a\nb".into(), "a".repeat(501)] {
            assert!(submission("invalid", &text).is_err());
        }
        assert!(submission("bad/id", "hello").is_err());
        assert!(
            transcript
                .send(submission("first", "hello").fixture()?, |_| Err(
                    "disk failed".into()
                ))
                .is_err()
        );
        assert!(transcript.messages(0).is_empty());
        let first = transcript
            .send(submission("first", " hello ").fixture()?, |_| Ok(()))
            .fixture()?;
        assert_eq!(first.sequence, 1);
        assert_eq!(first.text, "hello");
        let mut retry = submission("first", "hello").fixture()?;
        retry.turn_number = 2;
        assert_eq!(
            transcript
                .send(retry, |_| Err("must not write again".into()))
                .fixture()?,
            first
        );
        assert!(
            transcript
                .send(submission("first", "different").fixture()?, |_| Ok(()))
                .is_err()
        );
        let second = transcript
            .send(
                submission("second", "😀".repeat(500).as_str()).fixture()?,
                |_| Ok(()),
            )
            .fixture()?;
        assert_eq!(transcript.messages(1), vec![second]);
        assert!(!serde_json::to_string(&first)?.contains("private-cookie"));
        Ok(())
    }

    #[test]
    fn full_conversation_rejects_new_messages_but_accepts_retries() -> TestResult<()> {
        let mut transcript = Transcript::default();
        for index in 0..MAX_MESSAGES {
            transcript
                .send(
                    submission(&format!("message-{index}"), "hello").fixture()?,
                    |_| Ok(()),
                )
                .fixture()?;
        }
        assert!(
            transcript
                .send(submission("overflow", "hello").fixture()?, |_| Err(
                    "must not write".into()
                ))
                .is_err()
        );
        let retry = transcript
            .send(submission("message-0", "hello").fixture()?, |_| {
                Err("must not write".into())
            })
            .fixture()?;
        assert_eq!(retry.sequence, 1);
        assert_eq!(transcript.messages(0).len(), MAX_MESSAGES);
        Ok(())
    }
}
