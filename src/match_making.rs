//! Session-owned, first-in-first-out pairing. A ticket identifies one queue visit,
//! so a delayed poll or cancellation cannot alter a later visit.
use crate::{
    game::Game,
    graphql::Context,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map_definition::NamedMap,
    map_id::CatalogAccess,
    player::{Player, PlayerController},
    player_name::PlayerName,
    player_number::PlayerNumber,
    server_log,
    session_token::SessionToken,
    store::{GameRegistry, Store},
};
use juniper::{FieldResult, GraphQLUnion, graphql_object};
use std::{
    collections::BTreeMap,
    num::NonZeroUsize,
    sync::{MutexGuard, TryLockError},
    time::{Duration, Instant},
};

const PRESENCE_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Clone, PartialEq, Eq)]
struct Ticket(String);

struct WaitingPlayer {
    session: SessionToken,
    ticket: Ticket,
    name: PlayerName,
    last_seen: Instant,
}

struct Match {
    ticket: Ticket,
    game_id: LobbyId,
}

#[derive(Default)]
pub(crate) struct Queue {
    // A single two-player queue can have at most one unmatched player.
    waiting: Option<WaitingPlayer>,
    matches: BTreeMap<SessionToken, Match>,
    last_game_started: Option<Instant>,
}

/// Each GraphQL variant requires exactly the fields belonging to its queue state.
#[derive(GraphQLUnion)]
#[graphql(name = "MatchMakingSnapshot")]
pub enum Snapshot {
    Idle(IdleSnapshot),
    Waiting(WaitingSnapshot),
    Matched(MatchedSnapshot),
}

#[derive(Clone, Copy)]
struct RecentActivity {
    last_game_started: Option<Instant>,
    observed_at: Instant,
}

impl RecentActivity {
    fn seconds_ago(&self) -> Option<i32> {
        self.last_game_started.map(|started| {
            self.observed_at
                .saturating_duration_since(started)
                .as_secs()
                .min(i32::MAX as u64) as i32
        })
    }
}

pub struct IdleSnapshot {
    activity: RecentActivity,
}

#[graphql_object(name = "MatchMakingIdle")]
impl IdleSnapshot {
    fn last_game_started_seconds_ago(&self) -> Option<i32> {
        self.activity.seconds_ago()
    }
}

pub struct WaitingSnapshot {
    ticket: Ticket,
    activity: RecentActivity,
}

#[graphql_object(name = "MatchMakingWaiting")]
impl WaitingSnapshot {
    fn ticket(&self) -> &str {
        &self.ticket.0
    }

    fn last_game_started_seconds_ago(&self) -> Option<i32> {
        self.activity.seconds_ago()
    }
}

pub struct MatchedSnapshot {
    result: Match,
    activity: RecentActivity,
}

#[graphql_object(name = "MatchMakingMatched")]
impl MatchedSnapshot {
    fn ticket(&self) -> &str {
        &self.result.ticket.0
    }

    fn game_id(&self) -> String {
        self.result.game_id.to_string()
    }

    fn last_game_started_seconds_ago(&self) -> Option<i32> {
        self.activity.seconds_ago()
    }
}

impl Queue {
    pub(crate) fn remove_absent_players(&mut self, now: Instant) {
        if self.waiting.as_ref().is_some_and(|player| {
            now.saturating_duration_since(player.last_seen) >= PRESENCE_TIMEOUT
        }) {
            self.waiting = None;
        }
    }

    pub(crate) fn remove_games(&mut self, removed: &[LobbyId]) {
        self.matches
            .retain(|_, found| !removed.contains(&found.game_id));
    }

    fn snapshot(
        &self,
        session: Option<&SessionToken>,
        ticket: Option<&Ticket>,
        now: Instant,
    ) -> Snapshot {
        let activity = RecentActivity {
            last_game_started: self.last_game_started,
            observed_at: now,
        };
        if let Some(session) = session {
            if let Some(found) = self.matches.get(session)
                && ticket.is_none_or(|ticket| ticket == &found.ticket)
            {
                return Snapshot::Matched(MatchedSnapshot {
                    result: Match {
                        ticket: found.ticket.clone(),
                        game_id: found.game_id.clone(),
                    },
                    activity,
                });
            }
            if let Some(player) = self
                .waiting
                .iter()
                .find(|player| &player.session == session)
                && ticket.is_none_or(|ticket| ticket == &player.ticket)
            {
                return Snapshot::Waiting(WaitingSnapshot {
                    ticket: player.ticket.clone(),
                    activity,
                });
            }
        }
        Snapshot::Idle(IdleSnapshot { activity })
    }

    /// Only initial loads and explicit joins retire completed match receipts.
    /// Poll/cancel retries still recover the game, even if it just ended.
    fn retire_finished_match(&mut self, store: &Store, session: &SessionToken) -> FieldResult<()> {
        let Some(found) = self.matches.get(session) else {
            return Ok(());
        };
        let finished = match store.entry(&found.game_id)? {
            None => true,
            Some(entry) => match entry.try_lock() {
                Ok(game) => match &*game {
                    GameRegistry::Game(game) => game.has_ended(),
                    _ => true,
                },
                Err(TryLockError::WouldBlock) => false,
                Err(TryLockError::Poisoned(_)) => {
                    tracing::error!(event = "server_state_lock_unavailable", game_id = %found.game_id, "game state lock is poisoned");
                    return Err(server_log::internal_error("the game is unavailable."));
                }
            },
        };
        if finished {
            self.matches.remove(session);
        }
        Ok(())
    }

    fn join(
        &mut self,
        store: &Store,
        session: SessionToken,
        name: PlayerName,
        maps: Vec<NamedMap>,
        now: Instant,
    ) -> FieldResult<Snapshot> {
        self.remove_absent_players(now);
        self.retire_finished_match(store, &session)?;
        if self.matches.contains_key(&session) {
            return Ok(self.snapshot(Some(&session), None, now));
        }
        if let Some(waiting) = self
            .waiting
            .iter_mut()
            .find(|player| player.session == session)
        {
            waiting.last_seen = now;
            return Ok(self.snapshot(Some(&session), None, now));
        }
        let length =
            NonZeroUsize::new(maps.len()).ok_or("no maps are available for match making.")?;
        let ticket = Ticket(store.next_token()?);
        if let Some(opponent) = self.waiting.as_ref() {
            if name.matches(&opponent.name) {
                return Err(
                    "another waiting player has that name. choose a different user name.".into(),
                );
            }
            let map_index = store.choose_index(length)?;
            let map = maps
                .into_iter()
                .nth(map_index)
                .ok_or("the match making map is unavailable.")?;
            let side_count = NonZeroUsize::new(PlayerNumber::ALL.len())
                .ok_or("no player sides are available.")?;
            let side_index = store.choose_index(side_count)?;
            let side = PlayerNumber::ALL
                .get(side_index)
                .copied()
                .ok_or("the player side is unavailable.")?;
            let id = LobbyId::from_token(store.next_token()?);
            let game = Game::new(
                id.clone(),
                LobbyName::parse("match making").ok_or("invalid match making name")?,
                map.map_type,
                opponent.session.clone(),
                vec![
                    Player {
                        player_number: side,
                        controller: PlayerController::Human(opponent.session.clone()),
                        name: opponent.name.clone(),
                    },
                    Player {
                        player_number: side.opponent(),
                        controller: PlayerController::Human(session.clone()),
                        name,
                    },
                ],
                map.definition
                    .scenario()
                    .map_err(|error| error.to_string())?,
            );
            // Keep the waiting player and both receipts unchanged if recording fails.
            store.insert_match(id.clone(), game)?;
            self.matches.insert(
                opponent.session.clone(),
                Match {
                    ticket: opponent.ticket.clone(),
                    game_id: id.clone(),
                },
            );
            self.matches.insert(
                session.clone(),
                Match {
                    ticket,
                    game_id: id,
                },
            );
            self.waiting = None;
            self.last_game_started = Some(Instant::now());
        } else {
            self.waiting = Some(WaitingPlayer {
                session: session.clone(),
                ticket,
                name,
                last_seen: now,
            });
        }
        Ok(self.snapshot(Some(&session), None, Instant::now()))
    }

    fn poll(&mut self, session: &SessionToken, ticket: &Ticket, now: Instant) -> Snapshot {
        self.remove_absent_players(now);
        if let Some(player) = self
            .waiting
            .iter_mut()
            .find(|player| &player.session == session && &player.ticket == ticket)
        {
            player.last_seen = now;
        }
        self.snapshot(Some(session), Some(ticket), now)
    }

    fn leave(&mut self, session: &SessionToken, ticket: &Ticket, now: Instant) -> Snapshot {
        self.remove_absent_players(now);
        if self
            .waiting
            .as_ref()
            .is_some_and(|player| &player.session == session && &player.ticket == ticket)
        {
            self.waiting = None;
        }
        self.snapshot(Some(session), Some(ticket), now)
    }
}

fn queue(context: &Context) -> FieldResult<MutexGuard<'_, Queue>> {
    context.store.match_making.lock().map_err(|_| {
        tracing::error!(
            event = "match_making_unavailable",
            "match making lock is poisoned"
        );
        server_log::internal_error("match making is unavailable.")
    })
}

pub fn get(context: &Context) -> FieldResult<Snapshot> {
    let mut queue = queue(context)?;
    let session = context.identity();
    let now = Instant::now();
    queue.remove_absent_players(now);
    if let Some(session) = &session {
        queue.retire_finished_match(&context.store, session)?;
    }
    Ok(queue.snapshot(session.as_ref(), None, now))
}

pub fn join(context: &Context, input: &str) -> FieldResult<Snapshot> {
    let name = PlayerName::parse(input).ok_or("enter a name between 1 and 40 characters.")?;
    // Always use the public pool, including when the caller has local editor access.
    let maps = CatalogAccess::Public.catalog().map_err(|error| {
        tracing::error!(event = "match_making_maps_unavailable", error = %error, "could not read match making maps");
        server_log::internal_error("the match making maps are unavailable.")
    })?.into_iter().filter(|map| map.definition.match_making).collect();
    let session = match context.identity() {
        Some(session) => session,
        None => SessionToken::from_token(context.store.next_token()?),
    };
    let result =
        queue(context)?.join(&context.store, session.clone(), name, maps, Instant::now())?;
    context.set_identity(session);
    Ok(result)
}

pub fn poll(context: &Context, ticket: String) -> FieldResult<Snapshot> {
    let session = context.identity().ok_or("join match making first.")?;
    Ok(queue(context)?.poll(&session, &Ticket(ticket), Instant::now()))
}

pub fn leave(context: &Context, ticket: String) -> FieldResult<Snapshot> {
    let session = context.identity().ok_or("join match making first.")?;
    Ok(queue(context)?.leave(&session, &Ticket(ticket), Instant::now()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        environment::Environment,
        game_log::Directory,
        graphql,
        map_definition::MapDefinition,
        map_id::MapId,
        seed::Seed,
        test_support::{FixtureValue, TestResult},
    };
    use actix_web::{App, test as web_test, web};
    use serde_json::{Value, json};
    use std::{
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    fn pool() -> TestResult<Vec<NamedMap>> {
        let definition = MapDefinition::parse(r#"{
            "width":2,"height":2,"theme":"GreenForest","features":[],"depots":[],
            "units":[
                {"id":1,"position":{"x":0,"y":0},"playerNumber":"Player1","kind":"Infantry","direction":"East"},
                {"id":2,"position":{"x":1,"y":1},"playerNumber":"Player2","kind":"Infantry","direction":"West"}
            ]
        }"#).map_err(|error| error.to_string())?;
        ["fixture-a", "fixture-b"]
            .into_iter()
            .map(|name| {
                Ok(NamedMap {
                    map_type: MapId::parse(name.into())?,
                    definition: definition.clone(),
                })
            })
            .collect::<TestResult<_>>()
    }

    fn name(value: &str) -> TestResult<PlayerName> {
        PlayerName::parse(value).fixture()
    }

    fn ticket(snapshot: Snapshot) -> TestResult<Ticket> {
        match snapshot {
            Snapshot::Waiting(waiting) => Ok(waiting.ticket),
            _ => Err("expected a waiting player".into()),
        }
    }

    fn game_id(snapshot: Snapshot) -> TestResult<LobbyId> {
        match snapshot {
            Snapshot::Matched(matched) => Ok(matched.result.game_id),
            _ => Err("expected a matched game".into()),
        }
    }

    fn assert_idle(snapshot: Snapshot) -> TestResult {
        match snapshot {
            Snapshot::Idle(_) => Ok(()),
            _ => Err("expected an idle queue".into()),
        }
    }

    #[test]
    fn concurrent_duplicate_joins_create_exactly_one_game_per_pair() -> TestResult {
        let store = Store::new(Seed::new([94; 32]));
        std::thread::scope(|scope| -> TestResult {
            let mut handles = Vec::new();
            for index in 0..8 {
                let store = &store;
                handles.push(scope.spawn(move || -> Result<(), String> {
                    let session = SessionToken::from_token(format!("player-{}", index / 2));
                    let name = PlayerName::parse(&format!("player-{}", index / 2))
                        .ok_or("invalid test name")?;
                    let maps = pool().map_err(|error| error.to_string())?;
                    store
                        .match_making
                        .lock()
                        .map_err(|_| "queue lock unavailable")?
                        .join(store, session, name, maps, Instant::now())
                        .map_err(|error| format!("{error:?}"))?;
                    Ok(())
                }));
            }
            for handle in handles {
                handle.join().fixture()?.fixture()?;
            }
            Ok(())
        })?;
        let queue = store.match_making.lock().fixture()?;
        assert!(queue.waiting.is_none());
        assert_eq!(queue.matches.len(), 4);
        let mut participants = BTreeMap::new();
        for found in queue.matches.values() {
            *participants.entry(found.game_id.clone()).or_insert(0) += 1;
        }
        assert_eq!(participants.len(), 2);
        assert!(participants.values().all(|count| *count == 2));
        Ok(())
    }

    #[test]
    fn presence_tickets_and_cancellation_preserve_later_visits() -> TestResult {
        let store = Store::new(Seed::new([90; 32]));
        let mut queue = Queue::default();
        let session = SessionToken::from_token("first".into());
        let stranger = SessionToken::from_token("stranger".into());
        let now = Instant::now();
        let first = ticket(
            queue
                .join(&store, session.clone(), name("first")?, pool()?, now)
                .fixture()?,
        )?;
        let duplicate = ticket(
            queue
                .join(&store, session.clone(), name("first")?, pool()?, now)
                .fixture()?,
        )?;
        assert!(first == duplicate);
        assert!(queue.waiting.is_some());
        assert_idle(queue.leave(&stranger, &first, now))?;
        assert!(queue.waiting.is_some());
        assert_idle(queue.poll(&stranger, &first, now))?;
        let refreshed = now + Duration::from_secs(25);
        queue.poll(&session, &first, refreshed);
        queue.remove_absent_players(now + PRESENCE_TIMEOUT);
        assert!(
            queue.waiting.is_some(),
            "heartbeats keep the player eligible"
        );
        queue.remove_absent_players(refreshed + PRESENCE_TIMEOUT);
        assert!(queue.waiting.is_none());
        assert_idle(queue.poll(&session, &first, refreshed + PRESENCE_TIMEOUT))?;
        let second = ticket(
            queue
                .join(&store, session.clone(), name("first")?, pool()?, now)
                .fixture()?,
        )?;
        assert!(first != second);
        queue.leave(&session, &first, now);
        assert!(
            queue.waiting.is_some(),
            "a stale cancellation cannot remove a new visit"
        );
        queue.leave(&session, &second, now);
        assert!(queue.waiting.is_none());
        Ok(())
    }

    #[actix_web::test]
    async fn pairing_is_atomic_recovers_retries_and_randomizes_maps_and_sides() -> TestResult {
        let store = web::Data::new(Store::new(Seed::new([91; 32])));
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let mut queue = Queue::default();
        let mut observed_maps = std::collections::BTreeSet::new();
        let mut observed_sides = std::collections::BTreeSet::new();
        for index in 0..24 {
            let first = SessionToken::from_token(format!("first-{index}"));
            let second = SessionToken::from_token(format!("second-{index}"));
            let now = Instant::now();
            let first_ticket = ticket(
                queue
                    .join(&store, first.clone(), name("first")?, pool()?, now)
                    .fixture()?,
            )?;
            let second_snapshot = queue
                .join(&store, second.clone(), name("second")?, pool()?, now)
                .fixture()?;
            let id = game_id(second_snapshot)?;
            assert_eq!(game_id(queue.poll(&first, &first_ticket, now))?, id);
            assert_eq!(
                game_id(queue.leave(&first, &first_ticket, now))?,
                id,
                "a match wins a cancellation race"
            );
            assert_eq!(
                game_id(
                    queue
                        .join(&store, second.clone(), name("second")?, pool()?, now)
                        .fixture()?
                )?,
                id
            );
            assert!(queue.waiting.is_none());
            let response = web_test::call_service(&app, web_test::TestRequest::post().uri("/graphql")
                .cookie(first.cookie(Environment::Development))
                .set_json(json!({"query": format!("{{ game(id: {:?}) {{ mapType players {{ name playerNumber isYou }} }} }}", id.to_string())})).to_request()).await;
            let snapshot: Value = web_test::read_body_json(response).await;
            assert!(snapshot.get("errors").is_none(), "{snapshot}");
            let snapshot = &snapshot["data"]["game"];
            observed_maps.insert(snapshot["mapType"].as_str().fixture()?.to_owned());
            let players = snapshot["players"].as_array().fixture()?;
            assert_eq!(players.len(), 2);
            let own = players
                .iter()
                .find(|player| player["isYou"] == true)
                .fixture()?;
            observed_sides.insert(own["playerNumber"].as_str().fixture()?.to_owned());
            let entry = store.entry(&id).fixture()?.fixture()?;
            let mut entry = entry.lock().fixture()?;
            let game = match &mut *entry {
                GameRegistry::Game(game) => game,
                _ => return Err("expected a game without a lobby".into()),
            };
            assert!(
                game.resign(Some(&SessionToken::from_token("outsider".into())))
                    .is_err()
            );
            game.resign(Some(&first)).fixture()?;
            drop(entry);
            queue.retire_finished_match(&store, &first).fixture()?;
            assert_idle(queue.snapshot(Some(&first), None, now))?;
        }
        assert_eq!(observed_maps.len(), 2);
        assert_eq!(observed_sides.len(), 2);
        assert!(queue.last_game_started.is_some());
        Ok(())
    }

    #[test]
    fn invalid_pool_names_and_failed_recording_leave_the_opponent_waiting() -> TestResult {
        let root = std::env::temp_dir().join(format!(
            "fightlines-match-failure-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let directory = Directory::open(root.clone())?;
        let store = Store::new(Seed::new([92; 32])).with_game_logs(directory);
        let mut queue = Queue::default();
        let first = SessionToken::from_token("first".into());
        let second = SessionToken::from_token("second".into());
        let now = Instant::now();
        assert!(
            queue
                .join(&store, first.clone(), name("first")?, Vec::new(), now)
                .is_err()
        );
        assert!(queue.waiting.is_none());
        let original = ticket(
            queue
                .join(&store, first.clone(), name("first")?, pool()?, now)
                .fixture()?,
        )?;
        assert!(
            queue
                .join(&store, second.clone(), name("FIRST")?, pool()?, now)
                .is_err()
        );
        fs::remove_dir_all(&root)?;
        fs::write(&root, "block archive creation")?;
        assert!(
            queue
                .join(&store, second.clone(), name("second")?, pool()?, now)
                .is_err()
        );
        assert!(ticket(queue.snapshot(Some(&first), None, now))? == original);
        assert!(queue.matches.is_empty());
        assert!(queue.last_game_started.is_none());
        fs::remove_file(&root)?;
        Ok(())
    }

    macro_rules! execute {
        ($app:expr, $query:expr, $cookie:expr) => {{
            let mut request=web_test::TestRequest::post().uri("/graphql").set_json(json!({"query":$query}));
            if let Some(cookie)=$cookie {request=request.cookie(cookie);}
            let response=web_test::call_service($app,request.to_request()).await;
            let cookie=response.response().cookies().next().map(|cookie|cookie.into_owned());
            let body:Value=web_test::read_body_json(response).await;
            (body,cookie)
        }};
    }

    #[actix_web::test]
    async fn graphql_pairs_sessions_privately_and_excludes_unmarked_and_draft_maps() -> TestResult {
        let store = web::Data::new(Store::new(Seed::new([93; 32])));
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let fields = "__typename
            ... on MatchMakingIdle { lastGameStartedSecondsAgo }
            ... on MatchMakingWaiting { ticket lastGameStartedSecondsAgo }
            ... on MatchMakingMatched { ticket gameId lastGameStartedSecondsAgo }";
        let (idle, _) = execute!(&app, format!("{{ matchMaking {{ {fields} }} }}"), None);
        assert_eq!(
            idle["data"]["matchMaking"],
            json!({"__typename": "MatchMakingIdle", "lastGameStartedSecondsAgo": null}),
            "{idle}"
        );
        let (joined, first) = execute!(
            &app,
            format!("mutation {{ joinMatchMaking(name: \"First\") {{ {fields} }} }}"),
            None
        );
        assert!(joined.get("errors").is_none(), "{joined}");
        let first = first.fixture()?;
        let ticket = joined["data"]["joinMatchMaking"]["ticket"]
            .as_str()
            .fixture()?;
        assert_eq!(
            joined["data"]["joinMatchMaking"],
            json!({
                "__typename": "MatchMakingWaiting",
                "ticket": ticket,
                "lastGameStartedSecondsAgo": null
            }),
            "{joined}"
        );
        let (anonymous, _) = execute!(&app, format!("{{ matchMaking {{ {fields} }} }}"), None);
        assert_eq!(
            anonymous["data"]["matchMaking"],
            idle["data"]["matchMaking"]
        );
        let (recovered, _) = execute!(
            &app,
            format!("{{ matchMaking {{ {fields} }} }}"),
            Some(first.clone())
        );
        assert_eq!(recovered["data"]["matchMaking"]["ticket"], ticket);
        let (paired, second) = execute!(
            &app,
            format!("mutation {{ joinMatchMaking(name: \"Second\") {{ {fields} }} }}"),
            None
        );
        assert!(paired.get("errors").is_none(), "{paired}");
        let second = second.fixture()?;
        assert_eq!(
            paired["data"]["joinMatchMaking"]["__typename"],
            "MatchMakingMatched"
        );
        assert!(paired["data"]["joinMatchMaking"]["ticket"].is_string());
        let id = paired["data"]["joinMatchMaking"]["gameId"]
            .as_str()
            .fixture()?;
        for cookie in [first.clone(), second] {
            let (snapshot, _) = execute!(
                &app,
                format!(
                    "{{ game(id: {id:?}) {{ turnNumber mapType players {{ name playerNumber isYou isAi }} }} }}"
                ),
                Some(cookie)
            );
            assert!(snapshot.get("errors").is_none(), "{snapshot}");
            assert_eq!(snapshot["data"]["game"]["turnNumber"], 1);
            let map_id = MapId::parse(
                snapshot["data"]["game"]["mapType"]
                    .as_str()
                    .fixture()?
                    .into(),
            )?;
            let definition = CatalogAccess::Public
                .definition(&map_id)
                .map_err(|error| error.to_string())?;
            assert!(definition.match_making);
        }
        let (poll, _) = execute!(
            &app,
            format!("mutation {{ pollMatchMaking(ticket: {ticket:?}) {{ {fields} }} }}"),
            Some(first)
        );
        assert_eq!(poll["data"]["pollMatchMaking"]["gameId"], id);
        let (activity, _) = execute!(&app, format!("{{ matchMaking {{ {fields} }} }}"), None);
        assert_eq!(
            activity["data"]["matchMaking"]["__typename"],
            "MatchMakingIdle"
        );
        assert!(activity["data"]["matchMaking"].get("gameId").is_none());
        assert!(activity["data"]["matchMaking"].get("ticket").is_none());
        assert!(activity["data"]["matchMaking"]["lastGameStartedSecondsAgo"].is_number());
        Ok(())
    }
}
