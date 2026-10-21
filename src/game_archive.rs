//! Read-only archive browsing, enabled explicitly with --game-logs.
use crate::{
    game_log::{Archive, RecordedPlayer},
    graphql::Context,
    lobby::{Controller, GameSnapshot},
    map_type::MapType,
    scenario::PlayerNumber,
    turns::GameOutcome,
    visibility::PlayerObservation,
};
use actix_files::NamedFile;
use actix_web::web;
use juniper::{FieldResult, GraphQLEnum, GraphQLObject, GraphQLUnion, graphql_object};
use std::{fs, io, path::PathBuf, sync::Arc};

pub struct Browser {
    pub directory: PathBuf,
    pub index: PathBuf,
}

pub enum Access {
    Disabled,
    Enabled(Arc<Browser>),
}

impl Access {
    pub fn from_browser(browser: Option<web::Data<Browser>>) -> Self {
        match browser {
            None => Self::Disabled,
            Some(browser) => Self::Enabled(browser.into_inner()),
        }
    }

    fn browser(&self) -> FieldResult<&Browser> {
        match self {
            Self::Disabled => {
                Err("logged games are disabled. start the server with --game-logs.".into())
            }
            Self::Enabled(browser) => Ok(browser),
        }
    }
}

/// A directory basename, distinct from a live LobbyId (which may be reused).
struct ArchiveId(String);

impl ArchiveId {
    fn parse(value: String) -> io::Result<Self> {
        let valid = value.split_once('-').is_some_and(|(id, timestamp)| {
            id.len() == 32
                && id
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
                && !timestamp.is_empty()
                && timestamp.bytes().all(|byte| byte.is_ascii_digit())
        });
        if !valid {
            return Err(io::Error::other("invalid logged game id"));
        }
        Ok(Self(value))
    }

    fn read(&self, browser: &Browser) -> io::Result<Archive> {
        let path = browser.directory.join(&self.0);
        // Operator-controlled archives still must not follow links outside the root.
        if fs::symlink_metadata(&path)?.file_type().is_symlink() {
            return Err(io::Error::other(
                "logged game directories cannot be symbolic links",
            ));
        }
        Archive::read(&path)
    }
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct ArchivePlayer {
    name: String,
    player_number: PlayerNumber,
    controller: Controller,
}

impl From<&RecordedPlayer> for ArchivePlayer {
    fn from(player: &RecordedPlayer) -> Self {
        Self {
            name: player.name.clone(),
            player_number: player.player_number,
            controller: player.controller,
        }
    }
}

#[derive(Clone, Copy)]
pub enum LoggedGameStatus {
    Unfinished,
    PlayerWon(PlayerNumber),
    Draw,
}

#[derive(Clone, Copy, GraphQLEnum)]
enum LoggedGameStatusKind {
    Unfinished,
    PlayerWon,
    Draw,
}

#[graphql_object]
impl LoggedGameStatus {
    fn kind(&self) -> LoggedGameStatusKind {
        match self {
            Self::Unfinished => LoggedGameStatusKind::Unfinished,
            Self::PlayerWon(_) => LoggedGameStatusKind::PlayerWon,
            Self::Draw => LoggedGameStatusKind::Draw,
        }
    }

    fn winner(&self) -> Option<PlayerNumber> {
        match self {
            Self::PlayerWon(player) => Some(*player),
            Self::Unfinished | Self::Draw => None,
        }
    }
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct LoggedGame {
    id: String,
    name: String,
    map_type: MapType,
    started_at: String,
    players: Vec<ArchivePlayer>,
    turn_count: i32,
    status: LoggedGameStatus,
}

impl LoggedGame {
    fn from_archive(id: ArchiveId, archive: &Archive) -> Self {
        let status = match archive
            .submissions
            .last()
            .and_then(|submission| submission.outcome)
        {
            Some(GameOutcome::Victory(player)) => LoggedGameStatus::PlayerWon(player),
            Some(GameOutcome::Draw) => LoggedGameStatus::Draw,
            None => LoggedGameStatus::Unfinished,
        };
        Self {
            id: id.0,
            name: archive.started.name.clone(),
            map_type: archive.started.map_type,
            started_at: archive.recorded_at_unix_ms.to_string(),
            players: archive
                .started
                .players
                .iter()
                .map(ArchivePlayer::from)
                .collect(),
            turn_count: archive.turn_count(),
            status,
        }
    }
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct ArchiveReadError {
    id: String,
    message: String,
}

#[derive(GraphQLUnion)]
#[graphql(context = Context)]
pub enum LoggedGameEntry {
    Game(LoggedGame),
    Unreadable(ArchiveReadError),
}

impl LoggedGameEntry {
    fn id(&self) -> &str {
        match self {
            Self::Game(game) => &game.id,
            Self::Unreadable(error) => &error.id,
        }
    }

    fn started_at(&self) -> Option<&str> {
        match self {
            Self::Game(game) => Some(&game.started_at),
            Self::Unreadable(_) => None,
        }
    }
}

pub fn games(context: &Context) -> FieldResult<Vec<LoggedGameEntry>> {
    let browser = context.archives.browser()?;
    let mut games = Vec::new();
    for entry in fs::read_dir(&browser.directory)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        let Ok(id) = ArchiveId::parse(name) else {
            continue;
        };
        match id.read(browser) {
            Ok(archive) => games.push(LoggedGameEntry::Game(LoggedGame::from_archive(
                id, &archive,
            ))),
            Err(error) => games.push(LoggedGameEntry::Unreadable(ArchiveReadError {
                id: id.0,
                message: error.to_string(),
            })),
        }
    }
    games.sort_by(|left, right| {
        right
            .started_at()
            .map(|time| (time.len(), time))
            .cmp(&left.started_at().map(|time| (time.len(), time)))
            .then_with(|| left.id().cmp(right.id()))
    });
    Ok(games)
}

pub fn game(context: &Context, id: String) -> FieldResult<LoggedGame> {
    let browser = context.archives.browser()?;
    let id = ArchiveId::parse(id)?;
    let archive = id.read(browser)?;
    Ok(LoggedGame::from_archive(id, &archive))
}

pub fn turn(
    context: &Context,
    id: String,
    turn_number: i32,
    player: PlayerNumber,
) -> FieldResult<GameSnapshot> {
    let browser = context.archives.browser()?;
    let archive = ArchiveId::parse(id)?.read(browser)?;
    if turn_number < 0 || turn_number > archive.turn_count() {
        return Err("this logged turn does not exist".into());
    }
    let mut observation = PlayerObservation::new(&archive.started.scenario, player);
    let mut scenario = &archive.started.scenario;
    let mut outcome = None;
    for submission in &archive.submissions {
        if let Some(resolution) = &submission.resolution {
            if resolution.turn_number > turn_number {
                break;
            }
            observation.resolve(&submission.scenario, player, resolution);
            scenario = &submission.scenario;
            outcome = submission.outcome;
        }
    }
    Ok(GameSnapshot::archived(
        &archive.started,
        scenario,
        observation,
        outcome,
        player,
        turn_number + 1,
    ))
}

pub async fn page(browser: web::Data<Browser>) -> actix_web::Result<NamedFile> {
    Ok(NamedFile::open(&browser.index)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        game_log::{Directory, GameStarted, Submission, SubmissionResult},
        graphql,
        lobby::Store,
        lobby_id::LobbyId,
        map_definition::MapDefinition,
        seed::Seed,
        test_support::{FixtureValue, TestResult},
        turns::Turns,
    };
    use actix_web::{App, test};
    use serde_json::{Value, json};
    use std::net::SocketAddr;

    #[actix_web::test]
    async fn status_graphql_preserves_winning_player_and_other_states() -> TestResult<()> {
        #[derive(GraphQLObject)]
        struct StatusQuery {
            status: LoggedGameStatus,
        }

        for (status, expected) in [
            (
                LoggedGameStatus::Unfinished,
                json!({ "kind": "UNFINISHED", "winner": null }),
            ),
            (
                LoggedGameStatus::PlayerWon(PlayerNumber::Player1),
                json!({ "kind": "PLAYER_WON", "winner": "PLAYER1" }),
            ),
            (
                LoggedGameStatus::PlayerWon(PlayerNumber::Player2),
                json!({ "kind": "PLAYER_WON", "winner": "PLAYER2" }),
            ),
            (
                LoggedGameStatus::Draw,
                json!({ "kind": "DRAW", "winner": null }),
            ),
        ] {
            let schema = juniper::RootNode::new(
                StatusQuery { status },
                juniper::EmptyMutation::<()>::new(),
                juniper::EmptySubscription::<()>::new(),
            );
            let (data, errors) = juniper::execute_sync(
                "{ status { kind winner } }",
                None,
                &schema,
                &juniper::Variables::new(),
                &(),
            )?;
            assert!(errors.is_empty(), "{errors:?}");
            assert_eq!(serde_json::to_value(data)?["status"], expected);
        }
        Ok(())
    }

    #[actix_web::test]
    async fn access_requires_opt_in() -> TestResult<()> {
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(Seed::new([0; 32]))))
                .app_data(web::Data::new(graphql::schema()))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let request = test::TestRequest::post()
            .uri("/graphql")
            .peer_addr(SocketAddr::from(([192, 0, 2, 1], 1234)))
            .insert_header(("host", "fightlines.example"))
            .set_json(json!({"query":"{ loggedGames { __typename } }"}))
            .to_request();
        let result: Value = test::call_and_read_body_json(&app, request).await;
        assert!(
            result["errors"][0]["message"]
                .as_str()
                .fixture()?
                .contains("--game-logs")
        );
        for id in [
            "../private",
            "/tmp/game",
            "abcd-123",
            "00000000000000000000000000000000-../1",
            "server-start-123-456.json",
        ] {
            assert!(ArchiveId::parse(id.into()).is_err());
        }
        Ok(())
    }

    #[actix_web::test]
    async fn remote_replay_preserves_fog_and_survives_a_broken_neighbor() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!(
            "fightlines-archive-ui-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_nanos()
        ));
        let directory = Directory::open(root.clone())?;
        let mut scenario = MapDefinition::parse(r#"{
            "width": 7, "height": 3, "theme": "GreenForest",
            "features": [{"position": {"x": 4, "y": 1}, "terrain": "Forest"}],
            "depots": [], "units": [
                {"id":1,"position":{"x":0,"y":1},"playerNumber":"Player1","kind":"Infantry","direction":"East"},
                {"id":2,"position":{"x":4,"y":1},"playerNumber":"Player2","kind":"Infantry","direction":"West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let mut log = directory.start(GameStarted {
            game_id: LobbyId::from_token("01".repeat(16)),
            name: "Archive fixture".into(),
            map_type: MapType::SupplyPoint,
            players: vec![
                RecordedPlayer {
                    player_number: PlayerNumber::Player1,
                    name: "Red".into(),
                    controller: Controller::Human,
                },
                RecordedPlayer {
                    player_number: PlayerNumber::Player2,
                    name: "Blue".into(),
                    controller: Controller::Ai,
                },
            ],
            scenario: scenario.clone(),
            server_version: "test".into(),
            build_revision: None,
        })?;
        let entry = fs::read_dir(&root)?.next().fixture()??;
        let id = entry.file_name().to_str().fixture()?.to_owned();
        directory.record_server_start(Seed::new([42; 32]))?;
        let mut turns = Turns::default();
        for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let unit_id = if player == PlayerNumber::Player1 {
                "1"
            } else {
                "2"
            };
            let x = if player == PlayerNumber::Player1 {
                0
            } else {
                4
            };
            let orders = vec![serde_json::from_value(
                json!({ "unit_id": unit_id, "path": [{ "x": x, "y": 1 }] }),
            )?];
            turns
                .submit(&mut scenario, player, 1, orders.clone())
                .fixture()?;
            log.submitted(SubmissionResult::new(
                1,
                vec![Submission {
                    player_number: player,
                    orders,
                }],
                &scenario,
                &turns,
            ))?;
            let archive = Archive::read(&entry.path())?;
            let expected = if player == PlayerNumber::Player1 {
                0
            } else {
                1
            };
            assert_eq!(archive.turn_count(), expected);
        }
        fs::write(entry.path().join("00000003.pending"), b"{")?;
        let broken = root.join(format!("{}-1", "02".repeat(16)));
        fs::create_dir(&broken)?;
        fs::write(broken.join("00000000.json"), b"{")?;
        let index = root.join("index.html");
        fs::write(&index, "<html>archive replay</html>")?;
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(Seed::new([0; 32]))))
                .app_data(web::Data::new(graphql::schema()))
                .app_data(web::Data::new(Browser {
                    directory: root.clone(),
                    index,
                }))
                .route("/graphql", web::post().to(graphql::handle))
                .route("/logged-games", web::get().to(page))
                .route("/logged-games/{id}", web::get().to(page)),
        )
        .await;
        for uri in ["/logged-games".to_owned(), format!("/logged-games/{id}")] {
            let request = test::TestRequest::get()
                .uri(&uri)
                .peer_addr(SocketAddr::from(([192, 0, 2, 1], 1234)))
                .insert_header(("host", "fightlines.example"))
                .insert_header(("origin", "https://fightlines.example"))
                .to_request();
            let response = test::call_service(&app, request).await;
            assert!(response.status().is_success());
            assert_eq!(
                test::read_body(response).await,
                "<html>archive replay</html>"
            );
        }
        for (turn, player, expected_units) in [
            (0, "PLAYER1", 1),
            (0, "PLAYER2", 1),
            (1, "PLAYER1", 1),
            (1, "PLAYER2", 1),
        ] {
            let query = format!(
                r#"{{ loggedGames {{ __typename ... on LoggedGame {{ id name mapType startedAt players {{ name playerNumber controller }} turnCount status {{ kind winner }} }} ... on ArchiveReadError {{ id message }} }} loggedTurn(id: "{id}", turnNumber: {turn}, playerNumber: {player}) {{ isMember submitted players {{ name playerNumber isAi controller }} scenario {{ units {{ id }} }} lastResolution {{ turnNumber frames {{ units {{ id }} }} }} }} }}"#
            );
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::from(([192, 0, 2, 1], 1234)))
                .insert_header(("host", "fightlines.example"))
                .insert_header(("origin", "https://fightlines.example"))
                .set_json(json!({"query":query}))
                .to_request();
            let result: Value = test::call_and_read_body_json(&app, request).await;
            assert!(result.get("errors").is_none(), "{result}");
            let entries = result["data"]["loggedGames"].as_array().fixture()?;
            assert_eq!(entries.len(), 2);
            let game = entries.first().fixture()?;
            assert_eq!(game["__typename"], "LoggedGame");
            assert_eq!(game["id"], id);
            assert_eq!(game["name"], "Archive fixture");
            assert_eq!(game["mapType"], "SUPPLY_POINT");
            assert_eq!(
                game["players"],
                json!([
                    { "name": "Red", "playerNumber": "PLAYER1", "controller": "HUMAN" },
                    { "name": "Blue", "playerNumber": "PLAYER2", "controller": "AI" },
                ])
            );
            assert_eq!(
                result["data"]["loggedTurn"]["players"],
                json!([
                    { "name": "Red", "playerNumber": "PLAYER1", "isAi": false, "controller": "HUMAN" },
                    { "name": "Blue", "playerNumber": "PLAYER2", "isAi": true, "controller": "AI" },
                ])
            );
            assert!(!game["startedAt"].as_str().fixture()?.is_empty());
            assert_eq!(game["turnCount"], 1);
            assert_eq!(
                game["status"],
                json!({ "kind": "UNFINISHED", "winner": null })
            );
            let error = entries.get(1).fixture()?;
            assert_eq!(error["__typename"], "ArchiveReadError");
            assert_eq!(error["id"], format!("{}-1", "02".repeat(16)));
            assert!(!error["message"].as_str().fixture()?.is_empty());
            assert_eq!(error.as_object().fixture()?.len(), 3);
            assert_eq!(result["data"]["loggedTurn"]["isMember"], false);
            assert_eq!(result["data"]["loggedTurn"]["submitted"], true);
            assert_eq!(
                result["data"]["loggedTurn"]["scenario"]["units"]
                    .as_array()
                    .fixture()?
                    .len(),
                expected_units
            );
            if turn == 1 {
                let frames = result["data"]["loggedTurn"]["lastResolution"]["frames"]
                    .as_array()
                    .fixture()?;
                assert!(frames.len() >= 2);
                assert!(frames.iter().all(|frame| {
                    frame["units"]
                        .as_array()
                        .is_some_and(|units| units.len() == 1)
                }));
            }
        }
        let request = test::TestRequest::post()
            .uri("/graphql")
            .peer_addr(SocketAddr::from(([127, 0, 0, 1], 1234)))
            .insert_header(("host", "localhost:8080"))
            .set_json(json!({"query": format!(
                r#"{{ loggedGame(id: "{}-1") {{ id name }} }}"#, "02".repeat(16)
            )}))
            .to_request();
        let result: Value = test::call_and_read_body_json(&app, request).await;
        assert!(!result["errors"].as_array().fixture()?.is_empty());
        assert!(result["data"].is_null());
        let original = fs::read(entry.path().join("00000002.json"))?;
        fs::remove_file(entry.path().join("00000001.json"))?;
        assert!(Archive::read(&entry.path()).is_err());
        assert_eq!(fs::read(entry.path().join("00000002.json"))?, original);
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
