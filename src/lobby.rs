//! Pregame setup and lobby membership.
use crate::{
    chat::{self, ChatMessage, Draft, Sender, Submission, Transcript},
    game::Game,
    game_log::GameLog,
    graphql::Context,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    lobby_snapshot::{Snapshot, SnapshotSource},
    map_id::{CatalogAccess, MapId},
    player::{Controller, Player, PlayerController},
    player_name::PlayerName,
    player_number::PlayerNumber,
    server_log,
    session_token::SessionToken,
    store::GameRegistry,
};
use juniper::{FieldError, FieldResult};
use std::time::{Duration, Instant};

const INACTIVITY_TIMEOUT: Duration = Duration::from_secs(30 * 60);

pub(crate) struct Lobby {
    last_activity: Instant,
    chat: Transcript,
    chat_log: Option<GameLog>,
    id: LobbyId,
    name: LobbyName,
    map_type: MapId,
    host: SessionToken,
    players: Vec<Player>,
}

impl Lobby {
    pub fn is_expired(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.last_activity) >= INACTIVITY_TIMEOUT
    }

    pub fn authorize_close(&self, session: Option<&SessionToken>) -> FieldResult<()> {
        if session != Some(&self.host) {
            return error("only the host can close the lobby.");
        }
        Ok(())
    }

    pub fn chat_messages(&self, after: i32) -> Vec<ChatMessage> {
        self.chat.messages(after)
    }

    pub fn send_chat(
        &mut self,
        context: &Context,
        session: SessionToken,
        draft: Draft,
    ) -> FieldResult<ChatMessage> {
        if self.chat_log.is_none() {
            self.chat_log = Some(context.store.start_chat_log(&self.id)?);
        }
        let submission = Submission {
            sender: Sender::for_session(&self.players, &session),
            session,
            turn_number: 0,
            draft,
        };
        let message = self.chat.send(submission, |message| {
            self.chat_log
                .as_mut()
                .ok_or("chat recording is unavailable.")?
                .chat(message)
                .map_err(chat::recording_error)
        })?;
        self.last_activity = Instant::now();
        Ok(message)
    }

    pub fn id(&self) -> &LobbyId {
        &self.id
    }

    pub fn snapshot(&self, session: Option<&SessionToken>) -> Snapshot {
        Snapshot::new(
            SnapshotSource {
                id: &self.id,
                name: &self.name,
                map_type: &self.map_type,
                host: &self.host,
                players: &self.players,
            },
            session,
            None,
        )
    }

    fn join(&mut self, context: &Context, name: PlayerName) -> FieldResult<Snapshot> {
        let identity = context.identity();
        if self.players.iter().any(|player| {
            player.controller.session().is_some()
                && player.controller.session() == identity.as_ref()
        }) {
            self.last_activity = Instant::now();
            return Ok(self.snapshot(identity.as_ref()));
        }
        if self.players.iter().any(|player| player.name.matches(&name)) {
            return error("That name is already in this lobby. Choose another name.");
        }
        let player_count = self.map_type.player_count();
        if self.players.len() >= player_count {
            return error(&format!(
                "this map supports {player_count} players. the lobby is full."
            ));
        }
        let identity = match identity {
            Some(identity) => identity,
            None => SessionToken::from_token(context.store.next_token()?),
        };
        let player_number = vacant_side(&self.players)?;
        self.players.push(Player {
            player_number,
            controller: PlayerController::Human(identity.clone()),
            name,
        });
        self.last_activity = Instant::now();
        let result = self.snapshot(Some(&identity));
        context.set_identity(identity);
        Ok(result)
    }

    fn set_map_type(
        &mut self,
        session: Option<&SessionToken>,
        map_type: MapId,
        access: CatalogAccess,
    ) -> FieldResult<Snapshot> {
        if session != Some(&self.host) {
            return error("Only the host can change the map.");
        }
        access
            .definition(&map_type)
            .map_err(|error| error.to_string())?
            .scenario()
            .map_err(|error| error.to_string())?;
        self.map_type = map_type;
        self.last_activity = Instant::now();
        Ok(self.snapshot(session))
    }

    fn set_controller(
        &mut self,
        session: Option<&SessionToken>,
        controller: Controller,
    ) -> FieldResult<Snapshot> {
        if session != Some(&self.host) {
            return error("only the host can change the controller.");
        }
        if self.players.iter().any(|player| {
            player.controller.session().is_some() && player.controller.session() != Some(&self.host)
        }) {
            return error("another player has joined. the controller cannot be changed.");
        }
        let ai_name = PlayerName::parse("AI player")
            .ok_or_else(|| FieldError::from("the AI name is invalid."))?;
        self.players
            .retain(|player| player.controller.session().is_some());
        if controller == Controller::Ai {
            let player_number = vacant_side(&self.players)?;
            self.players.push(Player {
                player_number,
                controller: PlayerController::Ai,
                name: ai_name,
            });
        }
        self.last_activity = Instant::now();
        Ok(self.snapshot(session))
    }

    fn set_player_number(
        &mut self,
        session: Option<&SessionToken>,
        player_number: PlayerNumber,
    ) -> FieldResult<Snapshot> {
        let identity =
            session.ok_or_else(|| FieldError::from("only joined players can choose a side."))?;
        let previous = self
            .players
            .iter()
            .find(|player| player.controller.session() == Some(identity))
            .map(|player| player.player_number)
            .ok_or_else(|| FieldError::from("only joined players can choose a side."))?;
        for player in &mut self.players {
            if player.controller.session() == Some(identity) {
                player.player_number = player_number;
            } else if player.player_number == player_number {
                player.player_number = previous;
            }
        }
        self.last_activity = Instant::now();
        Ok(self.snapshot(Some(identity)))
    }

    pub fn prepare_game(
        &self,
        session: Option<&SessionToken>,
        access: CatalogAccess,
    ) -> FieldResult<Game> {
        if session != Some(&self.host) {
            return error("Only the host can start a game, and only joined players can enter it.");
        }
        let required_players = self.map_type.player_count();
        if self.players.len() != required_players {
            return error(&format!(
                "this map requires {required_players} players before starting."
            ));
        }
        let definition = access
            .definition(&self.map_type)
            .map_err(|error| error.to_string())?;
        let scenario = definition.scenario().map_err(|error| {
            tracing::error!(
                event = "map_initialization_failed",
                game_id = %self.id,
                error = %error,
                "could not initialize game map"
            );
            server_log::internal_error("The map could not be initialized.")
        })?;
        Ok(Game::new(
            self.id.clone(),
            self.name.clone(),
            self.map_type.clone(),
            self.host.clone(),
            self.players.clone(),
            scenario,
        )
        .with_chat(self.chat.clone()))
    }
}

pub fn create(context: &Context, input: &str, lobby_input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
    };
    let Some(lobby_name) = LobbyName::parse(lobby_input) else {
        return error("Enter a lobby name between 1 and 40 characters.");
    };
    let map_type = context.editor.catalog_access().options()
        .map_err(|error| {
            tracing::error!(event = "lobby_maps_load_failed", error = %error, "could not load maps for lobby creation");
            server_log::internal_error(error)
        })?
        .into_iter()
        .next()
        .ok_or("map catalog is empty")?;
    let identity = match context.identity() {
        Some(identity) => identity,
        None => SessionToken::from_token(context.store.next_token()?),
    };
    let id = LobbyId::from_token(context.store.next_token()?);
    let lobby = Lobby {
        last_activity: Instant::now(),
        chat: Transcript::default(),
        chat_log: None,
        id,
        name: lobby_name,
        map_type,
        host: identity.clone(),
        players: vec![Player {
            player_number: PlayerNumber::Player1,
            controller: PlayerController::Human(identity.clone()),
            name,
        }],
    };
    let result = lobby.snapshot(Some(&identity));
    context.store.insert_lobby(lobby)?;
    context.set_identity(identity);
    Ok(result)
}

pub fn get(context: &Context, id: LobbyId) -> FieldResult<Snapshot> {
    let entry = context.store.entry(&id)?.ok_or_else(|| {
        FieldError::from("This lobby no longer exists. Create a new lobby from the home page.")
    })?;
    let entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("The server state is unavailable.")
    })?;
    let identity = context.identity();
    let result = match &*entry {
        GameRegistry::Closed => return error("this lobby no longer exists."),
        GameRegistry::Lobby(lobby) => lobby.snapshot(identity.as_ref()),
        GameRegistry::Game(game) => game.lobby_snapshot(identity.as_ref()),
    };
    Ok(result)
}

pub fn join(context: &Context, id: LobbyId, input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
    };
    let entry = context.store.entry(&id)?.ok_or_else(|| {
        FieldError::from("This lobby no longer exists. Create a new lobby from the home page.")
    })?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("The server state is unavailable.")
    })?;
    let identity = context.identity();
    let lobby = match &mut *entry {
        GameRegistry::Game(game) => {
            let result = game.lobby_snapshot(identity.as_ref());
            return if result.is_member() {
                Ok(result)
            } else {
                error("The game has already started.")
            };
        }
        GameRegistry::Closed => return error("this lobby no longer exists."),
        GameRegistry::Lobby(lobby) => lobby,
    };
    lobby.join(context, name)
}

pub fn set_map_type(context: &Context, id: LobbyId, map_type: MapId) -> FieldResult<Snapshot> {
    let entry = context.store.entry(&id)?.ok_or_else(|| {
        FieldError::from("This lobby no longer exists. Create a new lobby from the home page.")
    })?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("The server state is unavailable.")
    })?;
    let lobby = match &mut *entry {
        GameRegistry::Closed => return error("this lobby no longer exists."),
        GameRegistry::Lobby(lobby) => lobby,
        GameRegistry::Game(_) => {
            return error("The game has already started. Its map cannot be changed.");
        }
    };
    lobby.set_map_type(
        context.identity().as_ref(),
        map_type,
        context.editor.catalog_access(),
    )
}

pub fn set_controller(
    context: &Context,
    id: LobbyId,
    controller: Controller,
) -> FieldResult<Snapshot> {
    let entry = context
        .store
        .entry(&id)?
        .ok_or_else(|| FieldError::from("this lobby no longer exists."))?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("the server state is unavailable.")
    })?;
    let lobby = match &mut *entry {
        GameRegistry::Closed => return error("this lobby no longer exists."),
        GameRegistry::Lobby(lobby) => lobby,
        GameRegistry::Game(_) => {
            return error("player controllers cannot be changed after the game has started.");
        }
    };
    lobby.set_controller(context.identity().as_ref(), controller)
}

pub fn set_player_number(
    context: &Context,
    id: LobbyId,
    player_number: PlayerNumber,
) -> FieldResult<Snapshot> {
    let entry = context
        .store
        .entry(&id)?
        .ok_or_else(|| FieldError::from("this lobby no longer exists."))?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("the server state is unavailable.")
    })?;
    let lobby = match &mut *entry {
        GameRegistry::Closed => return error("this lobby no longer exists."),
        GameRegistry::Lobby(lobby) => lobby,
        GameRegistry::Game(_) => {
            return error("the game has already started. its sides cannot be changed.");
        }
    };
    lobby.set_player_number(context.identity().as_ref(), player_number)
}

fn vacant_side(players: &[Player]) -> FieldResult<PlayerNumber> {
    PlayerNumber::ALL
        .into_iter()
        .find(|number| players.iter().all(|player| player.player_number != *number))
        .ok_or_else(|| FieldError::from("this lobby has no open side."))
}

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        environment::Environment,
        game_log::Directory,
        graphql,
        seed::Seed,
        store::Store,
        test_support::{FixtureValue, TestResult},
    };
    use actix_web::{App, test as web_test, web};
    use serde_json::{Value, json};
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

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

    #[actix_web::test]
    async fn closing_requires_host_and_invalidates_waiting_handles_without_closing_games()
    -> TestResult {
        let store = web::Data::new(Store::new(Seed::new([83; 32])));
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let (created, host) = execute!(
            &app,
            "mutation { createLobby(name: \"Host\", lobbyName: \"Close test\") { id } }",
            None
        );
        assert!(created.get("errors").is_none(), "{created}");
        let host = host.fixture()?;
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let lobby_id = LobbyId::from_token(id.into());
        let (joined, guest) = execute!(
            &app,
            format!("mutation {{ joinLobby(id: {id:?}, name: \"Guest\") {{ id }} }}"),
            None
        );
        assert!(joined.get("errors").is_none(), "{joined}");
        for cookie in [None, guest] {
            let (denied, _) = execute!(
                &app,
                format!("mutation {{ closeLobby(id: {id:?}) }}"),
                cookie
            );
            assert!(
                denied["errors"][0]["message"]
                    .as_str()
                    .fixture()?
                    .contains("only the host"),
                "{denied}"
            );
            assert!(store.entry(&lobby_id).fixture()?.is_some());
        }
        let waiting = store.entry(&lobby_id).fixture()?.fixture()?;
        let (closed, _) = execute!(
            &app,
            format!("mutation {{ closeLobby(id: {id:?}) }}"),
            Some(host.clone())
        );
        assert_eq!(closed["data"]["closeLobby"], true, "{closed}");
        assert!(store.entry(&lobby_id).fixture()?.is_none());
        match &*waiting.lock().fixture()? {
            GameRegistry::Closed => {}
            _ => return Err("a queued handle retained a closed lobby".into()),
        }
        for query in [
            format!("{{ lobby(id: {id:?}) {{ id }} }}"),
            format!("{{ chat(id: {id:?}) {{ sequence }} }}"),
            format!("mutation {{ startGame(id: {id:?}) {{ id }} }}"),
            format!("mutation {{ joinLobby(id: {id:?}, name: \"Late\") {{ id }} }}"),
            format!("mutation {{ closeLobby(id: {id:?}) }}"),
        ] {
            let (missing, _) = execute!(&app, query, Some(host.clone()));
            assert!(missing.get("errors").is_some(), "{missing}");
        }
        let (created, _) = execute!(
            &app,
            "mutation { createLobby(name: \"Host\", lobbyName: \"Started test\") { id } }",
            Some(host.clone())
        );
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        for query in [
            format!("mutation {{ setLobbyController(id: {id:?}, controller: AI) {{ id }} }}"),
            format!("mutation {{ startGame(id: {id:?}) {{ id }} }}"),
        ] {
            let (result, _) = execute!(&app, query, Some(host.clone()));
            assert!(result.get("errors").is_none(), "{result}");
        }
        let (denied, _) = execute!(
            &app,
            format!("mutation {{ closeLobby(id: {id:?}) }}"),
            Some(host.clone())
        );
        assert!(
            denied["errors"][0]["message"]
                .as_str()
                .fixture()?
                .contains("already started")
        );
        let (game, _) = execute!(
            &app,
            format!("{{ game(id: {id:?}) {{ turnNumber }} }}"),
            Some(host)
        );
        assert_eq!(game["data"]["game"]["turnNumber"], 1);
        assert_eq!(
            store
                .remove_expired_entries(Instant::now() + INACTIVITY_TIMEOUT)
                .fixture()?,
            0
        );
        Ok(())
    }

    #[actix_web::test]
    async fn inactivity_tracks_successful_actions_but_not_polling_or_rejections() -> TestResult {
        let root = std::env::temp_dir().join(format!(
            "fightlines-lobby-expiry-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let store = web::Data::new(
            Store::new(Seed::new([84; 32])).with_game_logs(Directory::open(root.clone())?),
        );
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let before = Instant::now();
        let (created, host) = execute!(
            &app,
            "mutation { createLobby(name: \"Host\", lobbyName: \"Expiry test\") { id mapType } }",
            None
        );
        assert!(created.get("errors").is_none(), "{created}");
        let host = host.fixture()?;
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let map = created["data"]["createLobby"]["mapType"]
            .as_str()
            .fixture()?;
        let waiting = store
            .entry(&LobbyId::from_token(id.into()))
            .fixture()?
            .fixture()?;
        assert_eq!(
            store
                .remove_expired_entries(before + INACTIVITY_TIMEOUT - Duration::from_secs(1))
                .fixture()?,
            0
        );
        for query in [
            format!("mutation {{ joinLobby(id: {id:?}, name: \"Host\") {{ id }} }}"),
            format!("mutation {{ setLobbyMap(id: {id:?}, mapType: {map:?}) {{ id }} }}"),
            format!("mutation {{ setLobbyController(id: {id:?}, controller: AI) {{ id }} }}"),
            format!("mutation {{ setLobbySide(id: {id:?}, playerNumber: PLAYER2) {{ id }} }}"),
            format!(
                "mutation {{ sendChat(input: {{id: {id:?}, messageId: \"expiry-message\", text: \"hello\"}}) {{ sequence }} }}"
            ),
            format!("mutation {{ setLobbyController(id: {id:?}, controller: HUMAN) {{ id }} }}"),
        ] {
            let stale = Instant::now() - INACTIVITY_TIMEOUT;
            {
                let mut state = waiting.lock().fixture()?;
                match &mut *state {
                    GameRegistry::Lobby(lobby) => lobby.last_activity = stale,
                    _ => return Err("expected an unstarted lobby".into()),
                }
            }
            let (result, _) = execute!(&app, query, Some(host.clone()));
            assert!(result.get("errors").is_none(), "{result}");
            let state = waiting.lock().fixture()?;
            match &*state {
                GameRegistry::Lobby(lobby) => assert!(lobby.last_activity > stale),
                _ => return Err("expected an unstarted lobby".into()),
            }
        }
        let joining_at = Instant::now();
        let (joined, _) = execute!(
            &app,
            format!("mutation {{ joinLobby(id: {id:?}, name: \"Guest\") {{ id }} }}"),
            None
        );
        assert!(joined.get("errors").is_none(), "{joined}");
        {
            let state = waiting.lock().fixture()?;
            match &*state {
                GameRegistry::Lobby(lobby) => assert!(lobby.last_activity >= joining_at),
                _ => return Err("expected an unstarted lobby".into()),
            }
        }
        let last_activity = Instant::now() - INACTIVITY_TIMEOUT;
        {
            let mut state = waiting.lock().fixture()?;
            match &mut *state {
                GameRegistry::Lobby(lobby) => lobby.last_activity = last_activity,
                _ => return Err("expected an unstarted lobby".into()),
            }
            // Busy entries are skipped; the next sweep retries them.
            assert_eq!(store.remove_expired_entries(Instant::now()).fixture()?, 0);
        }
        for (query, succeeds) in [
            (
                format!("{{ lobby(id: {id:?}) {{ id }} chat(id: {id:?}) {{ sequence }} }}"),
                true,
            ),
            (
                format!(
                    "mutation {{ setLobbyController(id: {id:?}, controller: HUMAN) {{ id }} }}"
                ),
                false,
            ),
            (
                format!("mutation {{ joinLobby(id: {id:?}, name: \"Guest\") {{ id }} }}"),
                false,
            ),
        ] {
            let (result, _) = execute!(&app, query, None);
            assert_eq!(result.get("errors").is_none(), succeeds, "{result}");
        }
        assert_eq!(
            store
                .remove_expired_entries(
                    last_activity + INACTIVITY_TIMEOUT - Duration::from_nanos(1)
                )
                .fixture()?,
            0
        );
        assert_eq!(
            store
                .remove_expired_entries(last_activity + INACTIVITY_TIMEOUT)
                .fixture()?,
            1
        );
        assert_eq!(store.remove_expired_entries(Instant::now()).fixture()?, 0);
        match &*waiting.lock().fixture()? {
            GameRegistry::Closed => {}
            _ => return Err("an expired lobby retained its data".into()),
        }
        assert!(
            fs::read_dir(&root)?.next().is_some(),
            "cleanup must retain chat journals"
        );
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
