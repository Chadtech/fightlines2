//! Shared in-memory registry and coordinated lobby-to-game transitions.
mod entry;
use entry::Entry;

use crate::{
    admin::dashboard::AdminEntry,
    chat,
    deployment::{Admission, Deployment, ShutdownNotice},
    game::Game,
    game_log::{Directory, GameLog},
    lobby::Lobby,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    lobby_snapshot::Snapshot,
    map::MapError,
    map_id::{self, CatalogAccess},
    match_making::Queue,
    player::{Player, PlayerController},
    player_name::PlayerName,
    player_number::PlayerNumber,
    seed::{self, Seed},
    server_log,
    session_token::SessionToken,
};
use juniper::{FieldError, FieldResult};
use std::{
    collections::BTreeMap,
    num::NonZeroUsize,
    sync::{Arc, Mutex, TryLockError},
    time::Instant,
};

#[derive(Debug)]
pub enum DevelopmentError {
    InvalidName,
    Map(MapError),
}

impl std::fmt::Display for DevelopmentError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidName => formatter.write_str("invalid development player or lobby name"),
            Self::Map(error) => write!(formatter, "development map failed: {error:?}"),
        }
    }
}

pub struct Store {
    pub deployment: Option<Deployment>,
    pub(crate) match_making: Mutex<Queue>,
    seed: Mutex<Seed>,
    registry: Mutex<BTreeMap<LobbyId, Arc<Entry>>>,
    game_logs: Option<Directory>,
}

/// One stable entry owns the transition from lobby to game and all later mutations.
pub(crate) enum GameRegistry {
    Lobby(Lobby),
    /// Detached handles must reject requests that were queued before removal.
    Closed,
    Game(Box<Game>),
}

impl Store {
    pub fn with_deployment(mut self, deployment: Option<Deployment>) -> Self {
        self.deployment = deployment;
        self
    }

    pub fn admit_session(&self) -> FieldResult<Option<Admission<'_>>> {
        self.deployment
            .as_ref()
            .map(|deployment| deployment.admission())
            .transpose()
    }

    pub fn is_draining(&self) -> FieldResult<bool> {
        self.deployment
            .as_ref()
            .map(|deployment| deployment.player_status().map(|status| status.draining))
            .unwrap_or(Ok(false))
    }

    pub fn admin_entries(&self, now: Instant) -> FieldResult<Vec<AdminEntry>> {
        let entries: Vec<_> = self
            .registry
            .lock()
            .map_err(|_| server_log::internal_error("game registry is unavailable."))?
            .values()
            .cloned()
            .collect();
        entries
            .into_iter()
            .filter_map(|entry| entry.admin_snapshot(now).transpose())
            .collect()
    }

    pub fn start_chat_log(&self, id: &LobbyId) -> FieldResult<GameLog> {
        self.game_logs
            .as_ref()
            .ok_or("chat recording is unavailable.")?
            .start_chat(id)
            .map_err(chat::recording_error)
    }

    /// Skip busy entries and retry next sweep without renewing player activity.
    pub(crate) fn announce_shutdown(&self, notice: ShutdownNotice) -> FieldResult<()> {
        let entries: Vec<_> = self
            .registry
            .lock()
            .map_err(|_| server_log::internal_error("game registry is unavailable."))?
            .iter()
            .map(|(id, entry)| (id.clone(), Arc::clone(entry)))
            .collect();
        for (id, entry) in entries {
            let mut state = match entry.try_lock() {
                Ok(state) => state,
                Err(TryLockError::WouldBlock) => continue,
                Err(TryLockError::Poisoned(_)) => {
                    tracing::error!(event = "server_state_lock_unavailable", game_id = %id, "shutdown chat state lock is poisoned");
                    continue;
                }
            };
            let result = match &mut *state {
                GameRegistry::Lobby(lobby) => lobby.announce_shutdown(self, notice),
                GameRegistry::Game(game) => game.announce_shutdown(notice),
                GameRegistry::Closed => Ok(()),
            };
            if let Err(error) = result {
                tracing::error!(event = "shutdown_chat_failed", game_id = %id, error = ?error, "could not announce session shutdown");
            }
        }
        Ok(())
    }

    pub fn new(seed: Seed) -> Self {
        Self {
            deployment: None,
            match_making: Mutex::new(Queue::default()),
            seed: Mutex::new(seed),
            registry: Mutex::new(BTreeMap::new()),
            game_logs: None,
        }
    }

    pub fn with_game_logs(mut self, directory: Directory) -> Self {
        self.game_logs = Some(directory);
        self
    }

    pub fn development(seed: Seed) -> Result<Self, DevelopmentError> {
        let mut registry = BTreeMap::new();
        let host = SessionToken::from_token("development-player-1".into());
        let map_type = map_id::options()
            .map_err(DevelopmentError::Map)?
            .into_iter()
            .next()
            .ok_or_else(|| {
                DevelopmentError::Map(MapError::InvalidDefinition("map catalog is empty".into()))
            })?;
        let id = LobbyId::from_token("00000000000000000000000000000000".into());
        let game = Game::new(
            id.clone(),
            LobbyName::parse("Test game").ok_or(DevelopmentError::InvalidName)?,
            map_type.clone(),
            host.clone(),
            vec![
                Player {
                    player_number: PlayerNumber::Player1,
                    controller: PlayerController::Human(host),
                    name: PlayerName::parse("Test player 1")
                        .ok_or(DevelopmentError::InvalidName)?,
                },
                Player {
                    player_number: PlayerNumber::Player2,
                    controller: PlayerController::Human(SessionToken::from_token(
                        "development-player-2".into(),
                    )),
                    name: PlayerName::parse("Test player 2")
                        .ok_or(DevelopmentError::InvalidName)?,
                },
            ],
            map_type.scenario().map_err(DevelopmentError::Map)?,
        )
        .into_development_preview();
        registry.insert(id, Arc::new(Entry::new(GameRegistry::Game(Box::new(game)))));
        Ok(Self {
            deployment: None,
            match_making: Mutex::new(Queue::default()),
            seed: Mutex::new(seed),
            registry: Mutex::new(registry),
            game_logs: None,
        })
    }

    /// Never acquire an entry lock while holding the registry lock. Callers own
    /// the cloned handle before waiting for that lobby or game's operation.
    pub(crate) fn entry(&self, id: &LobbyId) -> FieldResult<Option<Arc<Entry>>> {
        let registry = self.registry.lock().map_err(|_| {
            tracing::error!(
                event = "server_state_lock_unavailable",
                state = "lobby_registry",
                "server state lock is poisoned"
            );
            server_log::internal_error("The server state is unavailable.")
        })?;
        Ok(registry.get(id).cloned())
    }

    pub fn next_token(&self) -> FieldResult<String> {
        let mut seed = self.seed.lock().map_err(|_| {
            tracing::error!(
                event = "server_state_lock_unavailable",
                state = "token_generator",
                "server state lock is poisoned"
            );
            server_log::internal_error("The server state is unavailable.")
        })?;
        let (token, next_seed) = seed::token(*seed);
        *seed = next_seed;
        Ok(token)
    }

    pub(crate) fn choose_index(&self, length: NonZeroUsize) -> FieldResult<usize> {
        let mut seed = self.seed.lock().map_err(|_| {
            tracing::error!(
                event = "server_state_lock_unavailable",
                state = "token_generator",
                "random generator lock is poisoned"
            );
            server_log::internal_error("the random generator is unavailable.")
        })?;
        let (index, next) = seed::index(*seed, length);
        *seed = next;
        Ok(index)
    }

    /// Match making publishes a fully recorded game without an intermediate lobby.
    pub(crate) fn insert_match(&self, id: LobbyId, mut game: Game) -> FieldResult<()> {
        if let Some(directory) = &self.game_logs {
            game.record_start(directory)?;
        }
        if let Some(deployment) = &self.deployment {
            deployment
                .claim_session(&id)
                .map_err(server_log::internal_error)?;
        }
        self.registry
            .lock()
            .map_err(|_| {
                tracing::error!(
                    event = "server_state_lock_unavailable",
                    state = "lobby_registry",
                    "game registry lock is poisoned"
                );
                server_log::internal_error("the game registry is unavailable.")
            })?
            .insert(id, Arc::new(Entry::new(GameRegistry::Game(Box::new(game)))));
        Ok(())
    }

    /// Snapshot handles before inspecting games, and skip busy entries so cleanup
    /// never queues behind AI planning, disk writes, or player requests.
    pub fn remove_expired_entries(&self, now: Instant) -> FieldResult<usize> {
        // Release the queue before inspecting registry entries.
        self.match_making
            .lock()
            .map_err(|_| server_log::internal_error("match making is unavailable."))?
            .remove_absent_players(now);
        let entries = self
            .registry
            .lock()
            .map_err(|_| {
                tracing::error!(
                    event = "server_state_lock_unavailable",
                    state = "lobby_registry",
                    "server state lock is poisoned"
                );
                server_log::internal_error("The server state is unavailable.")
            })?
            .clone();
        let mut removed = 0;
        let mut removed_ids = Vec::new();
        for (id, entry) in entries {
            let mut game = match entry.try_lock() {
                Ok(game) => game,
                Err(TryLockError::WouldBlock) => continue,
                Err(TryLockError::Poisoned(_)) => {
                    tracing::error!(event = "server_state_lock_unavailable", game_id = %id, "game state lock is poisoned");
                    continue;
                }
            };
            if let GameRegistry::Game(game) = &mut *game
                && let Err(error) = game.expire_inactive(now)
            {
                tracing::error!(event = "game_inactivity_finish_failed", game_id = %id, error = ?error, "could not finish inactive game");
                continue;
            }
            let expired = match &*game {
                GameRegistry::Lobby(lobby) => lobby.is_expired(now),
                GameRegistry::Closed => false,
                GameRegistry::Game(game) => game.is_expired(now),
            };
            if !expired {
                continue;
            }
            let mut registry = self.registry.lock().map_err(|_| {
                tracing::error!(
                    event = "server_state_lock_unavailable",
                    state = "lobby_registry",
                    "server state lock is poisoned"
                );
                server_log::internal_error("The server state is unavailable.")
            })?;
            // Do not remove a replacement entry or double-count another sweep.
            if registry
                .get(&id)
                .is_some_and(|stored| Arc::ptr_eq(stored, &entry))
            {
                registry.remove(&id);
                *game = GameRegistry::Closed;
                removed += 1;
                removed_ids.push(id);
            }
        }
        if !removed_ids.is_empty() {
            // Entry and registry guards are gone before acquiring the queue.
            self.match_making
                .lock()
                .map_err(|_| server_log::internal_error("match making is unavailable."))?
                .remove_games(&removed_ids);
        }
        Ok(removed)
    }

    /// Close under the entry lock so a concurrent start cannot survive teardown.
    pub fn close_lobby(&self, id: LobbyId, session: Option<&SessionToken>) -> FieldResult<bool> {
        let entry = self.entry(&id)?.ok_or("this lobby no longer exists.")?;
        let mut state = entry.lock().map_err(|_| {
            tracing::error!(event = "server_state_lock_unavailable", game_id = %id, "game state lock is poisoned");
            server_log::internal_error("the server state is unavailable.")
        })?;
        match &*state {
            GameRegistry::Lobby(lobby) => lobby.authorize_close(session)?,
            GameRegistry::Game(_) => {
                return Err("the game has already started. its lobby cannot be closed.".into());
            }
            GameRegistry::Closed => return Err("this lobby no longer exists.".into()),
        }
        let mut registry = self.registry.lock().map_err(|_| {
            tracing::error!(
                event = "server_state_lock_unavailable",
                state = "lobby_registry",
                "server state lock is poisoned"
            );
            server_log::internal_error("the server state is unavailable.")
        })?;
        if registry
            .get(&id)
            .is_some_and(|stored| Arc::ptr_eq(stored, &entry))
        {
            registry.remove(&id);
            *state = GameRegistry::Closed;
            Ok(true)
        } else {
            Err("this lobby no longer exists.".into())
        }
    }

    pub(crate) fn insert_lobby(&self, lobby: Lobby) -> FieldResult<()> {
        if let Some(deployment) = &self.deployment {
            deployment
                .claim_session(lobby.id())
                .map_err(server_log::internal_error)?;
        }
        self.registry
            .lock()
            .map_err(|_| {
                tracing::error!(
                    event = "server_state_lock_unavailable",
                    state = "lobby_registry",
                    "server state lock is poisoned"
                );
                server_log::internal_error("The server state is unavailable.")
            })?
            .insert(
                lobby.id().clone(),
                Arc::new(Entry::new(GameRegistry::Lobby(lobby))),
            );
        Ok(())
    }

    /// Prepare and record the game under the same entry lock before replacing its lobby.
    pub fn start(
        &self,
        id: LobbyId,
        session: Option<&SessionToken>,
        access: CatalogAccess,
    ) -> FieldResult<Snapshot> {
        let entry = self.entry(&id)?.ok_or_else(|| {
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
        let lobby = match &*entry {
            GameRegistry::Closed => return Err("this lobby no longer exists.".into()),
            GameRegistry::Lobby(lobby) => lobby,
            GameRegistry::Game(game) => return game.start_snapshot(session),
        };
        let mut game = lobby.prepare_game(session, access)?;
        if let Some(directory) = &self.game_logs {
            game.record_start(directory)?;
        }
        let result = game.lobby_snapshot(session);
        *entry = GameRegistry::Game(Box::new(game));
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        environment::Environment,
        game_log, graphql,
        map_definition::MapDefinition,
        map_id::MapId,
        scenario::Scenario,
        test_support::{FixtureValue, TestResult},
    };
    use actix_web::{App, http::StatusCode, rt, test as web_test, web};
    use serde_json::{Value, json};
    use std::{error::Error, time::Duration};

    macro_rules! execute {
        ($app:expr, $query:expr, $cookie:expr) => {
            execute!($app, $query, $cookie, false)
        };
        ($app:expr, $query:expr, $cookie:expr, $allow_busy:expr) => {{
            let mut request = web_test::TestRequest::post()
                .uri("/graphql")
                .set_json(json!({ "query": $query }));
            if let Some(cookie) = $cookie {
                request = request.cookie(cookie);
            }
            let response = rt::time::timeout(
                Duration::from_secs(5),
                web_test::call_service($app, request.to_request()),
            )
            .await
            .fixture()?;
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(response.headers().get("Cache-Control").fixture()?, "no-store");
            let cookie = response
                .response()
                .cookies()
                .next()
                .map(|cookie| cookie.into_owned());
            let body: Value = web_test::read_body_json(response).await;
            assert!(body.get("errors").is_none()
                || ($allow_busy && body["errors"][0]["extensions"]["code"] == "GAME_BUSY"), "{body}");
            (body, cookie)
        }};
    }

    fn hold_orders(scenario: &Scenario, player: PlayerNumber) -> TestResult<String> {
        scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() == player)
            .map(|unit| {
                let position = unit.board_position().fixture()?;
                Ok(format!(
                    "{{ unitId: \"{}\", path: [{{ x: {}, y: {} }}] }}",
                    unit.id(),
                    position.x(),
                    position.y()
                ))
            })
            .collect::<TestResult<Vec<_>>>()
            .map(|orders| orders.join(","))
    }

    #[actix_web::test]
    async fn cleanup_removes_only_expired_finished_games_and_preserves_archives() -> TestResult<()>
    {
        use std::{
            fs,
            time::{SystemTime, UNIX_EPOCH},
        };

        let directory = std::env::temp_dir().join(format!(
            "fightlines-game-cleanup-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let store = web::Data::new(
            Store::development(Seed::new([29; 32]))
                .fixture()?
                .with_game_logs(Directory::open(directory.clone())?),
        );
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let mut ids = Vec::new();
        let mut finished_host = None;
        for name in ["Finished", "Active", "Waiting"] {
            let (created, host) = execute!(
                &app,
                format!(
                    "mutation {{ createLobby(name: \"Host\", lobbyName: \"{name}\") {{ id }} }}"
                ),
                None
            );
            let host = host.fixture()?;
            let id = created["data"]["createLobby"]["id"]
                .as_str()
                .fixture()?
                .to_owned();
            if name != "Waiting" {
                execute!(
                    &app,
                    format!(
                        "mutation {{ setLobbyController(id: \"{id}\", controller: AI) {{ id }} }}"
                    ),
                    Some(host.clone())
                );
                execute!(
                    &app,
                    format!("mutation {{ startGame(id: \"{id}\") {{ id }} }}"),
                    Some(host.clone())
                );
            }
            if name == "Finished" {
                finished_host = Some(host);
            }
            ids.push(LobbyId::from_token(id));
        }
        let finished = ids.first().fixture()?;
        let host = finished_host.fixture()?;
        let before = Instant::now();
        execute!(
            &app,
            format!("mutation {{ resignGame(id: \"{finished}\") {{ id }} }}"),
            Some(host.clone())
        );
        let after = Instant::now();
        let retention = Duration::from_secs(16 * 60);
        assert_eq!(
            store
                .remove_expired_entries(before + retention - Duration::from_secs(1))
                .fixture()?,
            0
        );
        execute!(
            &app,
            format!("{{ game(id: \"{finished}\") {{ id }} }}"),
            Some(host)
        );
        let entry = store.entry(finished).fixture()?.fixture()?;
        let weak = Arc::downgrade(&entry);
        // A busy finished game is skipped rather than blocking unrelated cleanup.
        {
            let _guard = entry.lock().fixture()?;
            assert_eq!(
                store.remove_expired_entries(after + retention).fixture()?,
                0
            );
        }
        drop(entry);
        assert_eq!(
            store.remove_expired_entries(after + retention).fixture()?,
            1
        );
        assert!(store.entry(finished).fixture()?.is_none());
        assert!(weak.upgrade().is_none());
        assert_eq!(
            store.remove_expired_entries(after + retention).fixture()?,
            0
        );
        for id in ids
            .iter()
            .skip(1)
            .chain(std::iter::once(&LobbyId::from_token("0".repeat(32))))
        {
            assert!(store.entry(id).fixture()?.is_some());
        }
        let request = web_test::TestRequest::post().uri("/graphql")
            .set_json(json!({"query": format!("{{ game(id: \"{finished}\") {{ id }} lobby(id: \"{finished}\") {{ id }} }}")}))
            .to_request();
        let response = web_test::call_service(&app, request).await;
        let body: Value = web_test::read_body_json(response).await;
        assert!(body["errors"].is_array(), "{body}");
        let archives = fs::read_dir(&directory)?.collect::<Result<Vec<_>, _>>()?;
        assert_eq!(archives.len(), 2);
        for archive in archives {
            game_log::replay(&archive.path())?;
        }
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn locked_game_keeps_other_games_and_the_request_worker_available() -> TestResult<()> {
        use std::{
            future::{Future, poll_fn},
            sync::mpsc,
            task::Poll,
            thread,
        };

        let store = web::Data::new(Store::development(Seed::new([10; 32])).fixture()?);
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let id = "0".repeat(32);
        let entry = store
            .entry(&LobbyId::from_token(id.clone()))
            .fixture()?
            .fixture()?;
        let (locked_tx, locked_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        // A separate thread owns the guard so the test never holds it across an
        // await. The bounded wait also releases it if request dispatch regresses.
        let blocker = thread::spawn(move || -> Result<(), String> {
            let _guard = entry.lock().map_err(|error| error.to_string())?;
            locked_tx.send(()).map_err(|error| error.to_string())?;
            release_rx
                .recv_timeout(Duration::from_secs(10))
                .map_err(|error| error.to_string())?;
            Ok(())
        });
        locked_rx.recv_timeout(Duration::from_secs(3))?;
        let request = web_test::TestRequest::post()
            .uri("/graphql")
            .set_json(json!({ "query": format!("{{ game(id: \"{id}\") {{ turnNumber }} }}") }))
            .to_request();
        let mut blocked = Box::pin(web_test::call_service(&app, request));
        let pending =
            poll_fn(|context| Poll::Ready(blocked.as_mut().poll(context).is_pending())).await;
        assert!(
            pending,
            "the locked game's response must wait for its entry"
        );

        let progress = rt::time::timeout(Duration::from_secs(3), async {
            let (busy, _) = execute!(
                &app,
                format!("mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: []) {{ turnNumber }} }}"),
                None,
                true
            );
            assert_eq!(busy["errors"][0]["extensions"]["code"], "GAME_BUSY");
            let (health, _) = execute!(&app, "{ health }", None);
            assert_eq!(health["data"]["health"], true);
            let (created, host) = execute!(
                &app,
                "mutation { createLobby(name: \"Independent host\", lobbyName: \"Independent game\") { id } }",
                None
            );
            let host = host.fixture()?;
            let other_id = created["data"]["createLobby"]["id"].as_str().fixture()?;
            execute!(
                &app,
                format!("mutation {{ setLobbyController(id: \"{other_id}\", controller: AI) {{ id }} }}"),
                Some(host.clone())
            );
            execute!(
                &app,
                format!("mutation {{ startGame(id: \"{other_id}\") {{ gameUrl }} }}"),
                Some(host.clone())
            );
            // Bound tactical planning with an explicit battlefield, independently
            // of the freely editable catalog map used to exercise game creation.
            let source = MapDefinition::parse(r#"{
                "width": 9, "height": 3, "theme": "GreenForest",
                "features": [], "depots": [],
                "units": [
                    {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                    {"id": 2, "position": {"x": 8, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
                ]
            }"#).fixture()?.scenario().fixture()?;
            {
                let other = store.entry(&LobbyId::from_token(other_id.into())).fixture()?.fixture()?;
                let mut other = other.lock().fixture()?;
                let game = match &mut *other {
                    GameRegistry::Game(game) => game,
                    GameRegistry::Lobby(_) | GameRegistry::Closed => return Err("independent entry must have started".into()),
                };
                **game = Game::new(
                    LobbyId::from_token(other_id.into()),
                    LobbyName::parse("Independent game").fixture()?,
                    MapId::default(),
                    SessionToken::from_token(host.value().into()),
                    vec![
                        Player {
                            player_number: PlayerNumber::Player1,
                            controller: PlayerController::Human(SessionToken::from_token(host.value().into())),
                            name: PlayerName::parse("Independent host").fixture()?,
                        },
                        Player {
                            player_number: PlayerNumber::Player2,
                            controller: PlayerController::Ai,
                            name: PlayerName::parse("AI player").fixture()?,
                        },
                    ],
                    source.clone(),
                );
            }
            let orders = hold_orders(&source, PlayerNumber::Player1)?;
            let (submitted, _) = execute!(
                &app,
                format!("mutation {{ submitTurn(id: \"{other_id}\", turnNumber: 1, orders: [{orders}]) {{ turnNumber }} }}"),
                Some(host.clone())
            );
            assert_eq!(submitted["data"]["submitTurn"]["turnNumber"], 2);
            let (polled, _) = execute!(
                &app,
                format!("{{ game(id: \"{other_id}\") {{ turnNumber }} }}"),
                Some(host)
            );
            assert_eq!(polled["data"]["game"]["turnNumber"], 2);
            Ok::<(), Box<dyn Error>>(())
        })
        .await;
        release_tx.send(())?;
        blocker
            .join()
            .map_err(|_| "entry holder panicked")?
            .fixture()?;
        progress.fixture()??;
        let response = rt::time::timeout(Duration::from_secs(3), blocked)
            .await
            .fixture()?;
        let body: Value = web_test::read_body_json(response).await;
        assert_eq!(body["data"]["game"]["turnNumber"], 1);
        Ok(())
    }

    #[actix_web::test]
    async fn concurrent_start_submit_and_resign_publish_each_transition_once() -> TestResult<()> {
        use std::{
            fs,
            rc::Rc,
            time::{SystemTime, UNIX_EPOCH},
        };

        let directory = std::env::temp_dir().join(format!(
            "fightlines-concurrent-game-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let store =
            Store::new(Seed::new([11; 32])).with_game_logs(Directory::open(directory.clone())?);
        let app = Rc::new(
            web_test::init_service(
                App::new()
                    .app_data(web::Data::new(store))
                    .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                    .route("/graphql", web::post().to(graphql::handle)),
            )
            .await,
        );
        let (created, host) = execute!(
            app.as_ref(),
            "mutation { createLobby(name: \"Concurrent host\", lobbyName: \"Concurrent game\") { id mapType } }",
            None
        );
        let host = host.fixture()?;
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let (_, guest) = execute!(
            app.as_ref(),
            format!("mutation {{ joinLobby(id: \"{id}\", name: \"Concurrent guest\") {{ id }} }}"),
            None
        );
        let guest = guest.fixture()?;
        let start = format!("mutation {{ startGame(id: \"{id}\") {{ gameUrl }} }}");
        let first_app = Rc::clone(&app);
        let first_host = host.clone();
        let first_start = start.clone();
        let first = rt::spawn(async move {
            Ok::<_, Box<dyn Error>>(execute!(first_app.as_ref(), first_start, Some(first_host)).0)
        });
        let (second, _) = execute!(app.as_ref(), start, Some(host.clone()));
        assert_eq!(first.await.fixture()??, second);
        let archives = fs::read_dir(&directory)?.collect::<Result<Vec<_>, _>>()?;
        assert_eq!(archives.len(), 1);
        let archive = archives.first().fixture()?.path();
        assert_eq!(fs::read_dir(&archive)?.count(), 1);

        let map = MapId::parse(
            created["data"]["createLobby"]["mapType"]
                .as_str()
                .fixture()?
                .into(),
        )
        .fixture()?;
        let source = map.scenario().fixture()?;
        let host_orders = hold_orders(&source, PlayerNumber::Player1)?;
        let guest_orders = hold_orders(&source, PlayerNumber::Player2)?;
        let submit = |orders: &str| {
            format!(
                "mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: [{orders}]) {{ turnNumber }} }}"
            )
        };
        let first_app = Rc::clone(&app);
        let first_host = host.clone();
        let host_submit = submit(&host_orders);
        let first = rt::spawn(async move {
            Ok::<_, Box<dyn Error>>(
                execute!(first_app.as_ref(), host_submit, Some(first_host), true).0,
            )
        });
        let (mut guest_result, _) = execute!(
            app.as_ref(),
            submit(&guest_orders),
            Some(guest.clone()),
            true
        );
        let mut host_result = first.await.fixture()??;
        // Contending submissions fail promptly; retry after the winning worker
        // completes and verify each transition is still published exactly once.
        if host_result.get("errors").is_some() {
            host_result = execute!(app.as_ref(), submit(&host_orders), Some(host.clone())).0;
        }
        if guest_result.get("errors").is_some() {
            guest_result = execute!(app.as_ref(), submit(&guest_orders), Some(guest.clone())).0;
        }
        let numbers = [
            host_result["data"]["submitTurn"]["turnNumber"]
                .as_i64()
                .fixture()?,
            guest_result["data"]["submitTurn"]["turnNumber"]
                .as_i64()
                .fixture()?,
        ];
        assert!(numbers.contains(&1));
        assert!(numbers.contains(&2));
        assert_eq!(fs::read_dir(&archive)?.count(), 3);
        assert!(game_log::replay(&archive)?.contains("Verified 2 submission records; next turn 2"));

        let (before_resign, _) = execute!(
            app.as_ref(),
            format!("{{ game(id: \"{id}\") {{ outcome {{ resigned winner }} }} }}"),
            Some(host.clone())
        );
        let previous_outcome = &before_resign["data"]["game"]["outcome"];
        let resign =
            format!("mutation {{ resignGame(id: \"{id}\") {{ outcome {{ resigned winner }} }} }}");
        let first_app = Rc::clone(&app);
        let first_resign = resign.clone();
        let first = rt::spawn(async move {
            Ok::<_, Box<dyn Error>>(execute!(first_app.as_ref(), first_resign, Some(host)).0)
        });
        let (second, _) = execute!(app.as_ref(), resign, Some(guest));
        assert_eq!(first.await.fixture()??, second);
        // A catalog map may legally contain only trucks on one or both sides.
        // Preserve an existing outcome; otherwise exactly one resignation wins.
        let submission_count = if previous_outcome.is_null() {
            assert_eq!(second["data"]["resignGame"]["outcome"]["resigned"], true);
            3
        } else {
            assert_eq!(&second["data"]["resignGame"]["outcome"], previous_outcome);
            2
        };
        assert_eq!(fs::read_dir(&archive)?.count(), submission_count + 1);
        assert!(game_log::replay(&archive)?.contains(&format!(
            "Verified {submission_count} submission records; next turn 2"
        )));
        fs::remove_dir_all(directory)?;
        Ok(())
    }
}
