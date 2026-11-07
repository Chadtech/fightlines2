//! Running games, durable turn transitions, and live/replay projections.
use crate::{
    admin::dashboard::{AdminPlayer, EntrySnapshot, EntryStatus},
    ai, app_version,
    chat::{self, ChatMessage, Draft, Sender, Submission as ChatSubmission, Transcript},
    game_activity::{ActivityClock, EnabledInactivity, InactivityRenewalReason},
    game_archive::review::RecordedOrder,
    game_log::{Directory, GameLog, GameStarted, RecordedPlayer, Submission, SubmissionResult},
    graphql::Context,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    lobby_snapshot::{Snapshot, SnapshotSource},
    map::Coordinate,
    map_id::MapId,
    movement::{self, MovementRule},
    player::{Controller, Player, PlayerController},
    player_number::PlayerNumber,
    scenario::Scenario,
    server_limits::{Limits, Rejection},
    server_log,
    session_token::SessionToken,
    store::GameRegistry,
    turns::{GameOutcome, TurnFrame, TurnResolution, Turns, UnitOrderInput},
    visibility,
};
use juniper::{FieldError, FieldResult, GraphQLObject};
use std::{
    collections::BTreeMap,
    sync::TryLockError,
    time::{Duration, Instant},
};

const FINISHED_GAME_RETENTION: Duration = Duration::from_secs(16 * 60);

/// Starting consumes the lobby. The source ID keeps existing invite URLs
/// resolvable for polling players and repeated start requests.
pub(crate) struct Game {
    started_at: Instant,
    last_activity: Instant,
    chat: Transcript,
    log: Option<GameLog>,
    turns: Turns,
    finished_at: Option<Instant>,
    activity: Option<[ActivityClock; 2]>,
    observations: [visibility::PlayerObservation; 2],
    access: GameAccess,
    scenario: Scenario,
    source_lobby: LobbyId,
    name: LobbyName,
    map_type: MapId,
    host: SessionToken,
    players: Vec<Player>,
}

enum GameAccess {
    Members,
    DevelopmentPreview,
}

/// Public game response built for an authorized member's session.
/// Stored game state remains in `Game`; viewer-specific flags are computed here.
#[derive(GraphQLObject)]
pub struct GameSnapshot {
    inactivity: Option<EnabledInactivity>,
    replay_orders: Vec<RecordedOrder>,
    turn_number: i32,
    outcome: Option<GameOutcome>,
    submitted: bool,
    opponent_submitted: bool,
    last_resolution: Option<TurnResolution>,
    id: String,
    name: String,
    map_type: MapId,
    players: Vec<GamePlayerView>,
    is_host: bool,
    is_member: bool,
    game_url: Option<String>,
    scenario: Scenario,
    movement_rules: Vec<MovementRule>,
    visible_tiles: Vec<Coordinate>,
}

/// Public roster entry; `is_you` compares the player with the requesting session.
/// Session credentials are never included in this response.
#[derive(GraphQLObject)]
struct GamePlayerView {
    name: String,
    is_host: bool,
    is_you: bool,
    player_number: PlayerNumber,
    is_ai: bool,
    controller: Controller,
}

impl Game {
    pub fn new(
        source_lobby: LobbyId,
        name: LobbyName,
        map_type: MapId,
        host: SessionToken,
        players: Vec<Player>,
        scenario: Scenario,
    ) -> Self {
        let activity = if players.len() == 2
            && players
                .iter()
                .all(|player| player.controller.session().is_some())
        {
            Some([ActivityClock::new(Instant::now()); 2])
        } else {
            None
        };
        Self {
            started_at: Instant::now(),
            last_activity: Instant::now(),
            activity,
            chat: Transcript::default(),
            log: None,
            observations: PlayerNumber::ALL
                .map(|player| visibility::PlayerObservation::new(&scenario, player)),
            turns: Turns::default(),
            finished_at: None,
            access: GameAccess::Members,
            scenario,
            source_lobby,
            name,
            map_type,
            host,
            players,
        }
    }

    pub fn admin_snapshot(&self, now: Instant) -> EntrySnapshot {
        let warning_deadline = self.activity.as_ref().and_then(|clocks| {
            PlayerNumber::ALL
                .into_iter()
                .filter(|player| self.turns.orders[player.index()].is_none())
                .filter_map(|player| {
                    clocks[player.index()]
                        .countdown_seconds(now)
                        .map(|_| clocks[player.index()].deadline())
                })
                .min()
        });
        let status = if self.turns.outcome.is_some() {
            EntryStatus::Finished
        } else if warning_deadline.is_some() {
            EntryStatus::InactivityWarning
        } else if self.turns.orders.iter().any(Option::is_some) {
            EntryStatus::WaitingForPlayer
        } else {
            EntryStatus::Planning
        };
        EntrySnapshot {
            id: self.source_lobby.clone(),
            name: self.name.to_string(),
            map_type: self.map_type.clone(),
            status,
            turn_number: Some(self.turns.number),
            outcome: self.turns.outcome,
            players: self
                .players
                .iter()
                .map(|player| {
                    AdminPlayer::new(
                        player,
                        self.turns.orders[player.player_number.index()].is_some(),
                    )
                })
                .collect(),
            started_at: Some(self.started_at),
            last_activity: self.last_activity,
            warning_deadline,
        }
    }

    pub fn into_development_preview(mut self) -> Self {
        self.access = GameAccess::DevelopmentPreview;
        self.activity = None;
        self
    }

    pub fn with_chat(mut self, chat: Transcript) -> Self {
        self.chat = chat;
        self
    }

    pub fn chat_messages(&self, after: i32) -> Vec<ChatMessage> {
        self.chat.messages(after)
    }

    pub fn send_chat(&mut self, session: SessionToken, draft: Draft) -> FieldResult<ChatMessage> {
        let submission = ChatSubmission {
            sender: Sender::for_session(&self.players, &session),
            session,
            turn_number: self.turns.number,
            draft,
        };
        let message = self.chat.send(submission, |message| {
            self.log
                .as_mut()
                .ok_or("chat is unavailable in this preview.")?
                .chat(message)
                .map_err(chat::recording_error)
        })?;
        self.last_activity = Instant::now();
        Ok(message)
    }

    /// Reads and repeated resignations never extend the final-results window.
    pub fn is_expired(&self, now: Instant) -> bool {
        self.finished_at.is_some_and(|finished_at| {
            now.saturating_duration_since(finished_at) >= FINISHED_GAME_RETENTION
        })
    }

    pub(crate) fn has_ended(&self) -> bool {
        self.finished_at.is_some()
    }

    /// Record the initial board before the store replaces its lobby entry.
    pub fn record_start(&mut self, directory: &Directory) -> FieldResult<()> {
        self.log = Some(
            directory
                .start(GameStarted {
                    chat: self.chat.messages(0),
                    game_id: self.source_lobby.clone(),
                    name: self.name.to_string(),
                    map_type: self.map_type.clone(),
                    players: self
                        .players
                        .iter()
                        .map(|player| RecordedPlayer {
                            player_number: player.player_number,
                            name: player.name.to_string(),
                            controller: player.controller.kind(),
                        })
                        .collect(),
                    scenario: self.scenario.clone(),
                    server_version: app_version::current().into(),
                    build_revision: option_env!("FIGHTLINES_BUILD_REVISION").map(String::from),
                })
                .map_err(|error| log_error(&self.source_lobby, error))?,
        );
        Ok(())
    }

    pub fn lobby_snapshot(&self, session: Option<&SessionToken>) -> Snapshot {
        Snapshot::new(
            SnapshotSource {
                id: &self.source_lobby,
                name: &self.name,
                map_type: &self.map_type,
                host: &self.host,
                players: &self.players,
            },
            session,
            Some(format!("/game/{}", self.source_lobby)),
        )
    }

    pub fn view(&self, session: Option<&SessionToken>) -> FieldResult<GameSnapshot> {
        // The opt-in fixture previews Player1 without changing browser identity.
        if let GameAccess::DevelopmentPreview = self.access {
            return self.player_view(&self.host);
        }
        let identity = session.ok_or_else(|| {
            FieldError::from(
                "Only the host can start a game, and only joined players can enter it.",
            )
        })?;
        if !self
            .players
            .iter()
            .any(|player| player.controller.session() == Some(identity))
        {
            return error("Only the host can start a game, and only joined players can enter it.");
        }
        self.player_view(identity)
    }

    pub fn start_snapshot(&self, session: Option<&SessionToken>) -> FieldResult<Snapshot> {
        if session != Some(&self.host) {
            return error("Only the host can start a game, and only joined players can enter it.");
        }
        Ok(self.lobby_snapshot(session))
    }

    fn player_view(&self, session: &SessionToken) -> FieldResult<GameSnapshot> {
        let player_number = self
            .players
            .iter()
            .find(|player| player.controller.session() == Some(session))
            .map(|player| player.player_number)
            .ok_or_else(|| FieldError::from("only joined players can enter the game."))?;
        // Observation and turn arrays are indexed by map side, never roster order.
        let index = player_number.index();
        let ObservedBoard {
            scenario,
            visible,
            last_resolution,
        } = observed_board(
            &self.scenario,
            &self.observations[index],
            self.turns.outcome,
            player_number,
        );
        Ok(GameSnapshot {
            inactivity: self.activity.as_ref().map(|activity| EnabledInactivity {
                warning_seconds_remaining: if self.turns.outcome.is_none()
                    && self.turns.orders[index].is_none()
                {
                    activity[index].countdown_seconds(Instant::now())
                } else {
                    None
                },
            }),
            replay_orders: Vec::new(),
            turn_number: self.turns.number,
            outcome: self.turns.outcome,
            submitted: self.turns.orders[index].is_some(),
            opponent_submitted: self.turns.orders[player_number.opponent().index()].is_some(),
            last_resolution,
            id: self.source_lobby.to_string(),
            name: self.name.to_string(),
            map_type: self.map_type.clone(),
            players: self
                .players
                .iter()
                .map(|player| GamePlayerView {
                    name: player.name.to_string(),
                    is_host: player.controller.session() == Some(&self.host),
                    is_you: player.controller.session() == Some(session),
                    is_ai: player.controller.session().is_none(),
                    controller: player.controller.kind(),
                    player_number: player.player_number,
                })
                .collect(),
            is_host: session == &self.host,
            is_member: true,
            game_url: Some(format!("/game/{}", self.source_lobby)),
            scenario,
            visible_tiles: visible,
            movement_rules: movement::rules(),
        })
    }

    /// The earliest expired unsubmitted player loses. Equal deadlines with both
    /// players absent end in a draw, rather than arbitrarily awarding one side.
    pub fn expire_inactive(&mut self, now: Instant) -> FieldResult<bool> {
        if self.turns.outcome.is_some() {
            return Ok(false);
        }
        let Some(activity) = &self.activity else {
            return Ok(false);
        };
        let deadlines = PlayerNumber::ALL.map(|player| {
            let index = player.index();
            let deadline = activity[index].deadline();
            (self.turns.orders[index].is_none() && now >= deadline).then_some(deadline)
        });
        let winner = match deadlines {
            [None, None] => return Ok(false),
            [Some(_), None] => Some(PlayerNumber::Player2),
            [None, Some(_)] => Some(PlayerNumber::Player1),
            [Some(first), Some(second)] => match first.cmp(&second) {
                std::cmp::Ordering::Less => Some(PlayerNumber::Player2),
                std::cmp::Ordering::Greater => Some(PlayerNumber::Player1),
                std::cmp::Ordering::Equal => None,
            },
        };
        let mut turns = self.turns.clone();
        turns.end_by_inactivity(winner);
        if let Some(log) = &mut self.log {
            log.submitted(SubmissionResult::new(
                turns.number,
                Vec::new(),
                &self.scenario,
                &turns,
            ))
            .map_err(|error| log_error(&self.source_lobby, error))?;
        }
        self.turns = turns;
        self.finished_at = Some(now);
        Ok(true)
    }

    pub fn renew_inactivity_timer(
        &mut self,
        session: Option<&SessionToken>,
        turn_number: i32,
        reason: InactivityRenewalReason,
        now: Instant,
    ) -> FieldResult<GameSnapshot> {
        let identity = session.ok_or_else(|| {
            FieldError::from("only joined players can renew the inactivity timer.")
        })?;
        let player = self
            .players
            .iter()
            .find(|player| player.controller.session() == Some(identity))
            .map(|player| player.player_number)
            .ok_or_else(|| {
                FieldError::from("only joined players can renew the inactivity timer.")
            })?;
        if self.turns.number != turn_number {
            return self.player_view(identity);
        }
        self.expire_inactive(now)?;
        let renewal_allowed = match reason {
            InactivityRenewalReason::UserInteraction => true,
            InactivityRenewalReason::PlaybackAllowance => self.turns.last_resolution.is_some(),
            InactivityRenewalReason::BriefingAllowance => self.turns.number == 1,
        };
        if renewal_allowed
            && self.turns.outcome.is_none()
            && self.turns.orders[player.index()].is_none()
            && let Some(clocks) = &mut self.activity
        {
            clocks[player.index()].observe(reason, now);
            if let InactivityRenewalReason::UserInteraction = reason {
                self.last_activity = now;
            }
        }
        self.player_view(identity)
    }

    pub fn resign(&mut self, session: Option<&SessionToken>) -> FieldResult<GameSnapshot> {
        if let GameAccess::DevelopmentPreview = self.access {
            return error("the development preview is read-only. create a game to resign.");
        }
        let identity =
            session.ok_or_else(|| FieldError::from("only joined players can resign."))?;
        let player = self
            .players
            .iter()
            .find(|player| player.controller.session() == Some(identity))
            .map(|player| player.player_number)
            .ok_or_else(|| FieldError::from("only joined players can resign."))?;
        self.expire_inactive(Instant::now())?;
        if self.turns.outcome.is_some() {
            return self.player_view(identity);
        }
        let mut next_turns = self.turns.clone();
        next_turns.resign(player);
        if let Some(log) = &mut self.log {
            let mut result =
                SubmissionResult::new(next_turns.number, Vec::new(), &self.scenario, &next_turns);
            result.resigned_player = Some(player);
            log.submitted(result)
                .map_err(|error| log_error(&self.source_lobby, error))?;
        }
        self.last_activity = Instant::now();
        self.turns = next_turns;
        self.finished_at = Some(Instant::now());
        self.player_view(identity)
    }

    pub fn submit_turn(
        &mut self,
        session: Option<&SessionToken>,
        turn_number: i32,
        orders: Vec<UnitOrderInput>,
        limits: &Limits,
    ) -> FieldResult<GameSnapshot> {
        if let GameAccess::DevelopmentPreview = self.access {
            return error(
                "the development preview is read-only. create a two-player game to submit turns.",
            );
        }
        let identity = session.ok_or_else(|| {
            FieldError::new(
                "only joined players can submit turns.",
                juniper::Value::null(),
            )
        })?;
        let player_number = self
            .players
            .iter()
            .find(|player| player.controller.session() == Some(identity))
            .map(|player| player.player_number)
            .ok_or_else(|| FieldError::from("only joined players can submit turns."))?;
        if self.expire_inactive(Instant::now())? {
            return self.player_view(identity);
        }
        // Lost-response retries keep the already accepted orders and create no new
        // archive entry. Stale turn numbers still follow normal validation below.
        if self.turns.number == turn_number
            && self.turns.outcome.is_none()
            && self.turns.orders[player_number.index()].is_some()
        {
            return self.player_view(identity);
        }
        let ai_player = self
            .players
            .iter()
            .find_map(|player| match player.controller {
                PlayerController::Ai => Some(player.player_number),
                PlayerController::Human(_) => None,
            });
        let mut next_turns = self.turns.clone();
        let mut next_scenario = self.scenario.clone();
        // Reject stale, terminal and invalid human submissions before AI planning.
        // Preparing on copies keeps both pending orders and the board intact on error.
        next_turns
            .submit(
                &mut next_scenario,
                player_number,
                turn_number,
                orders.clone(),
            )
            .map_err(FieldError::from)?;
        // Admission happens after validation, before any authoritative change.
        // Keep the permit through resolution and recording on this worker.
        let _ai_permit = ai_player
            .map(|_| limits.acquire_ai())
            .transpose()
            .map_err(Rejection::into_field_error)?;
        let mut submissions = vec![Submission {
            player_number,
            orders,
        }];
        if let Some(ai_player) = ai_player {
            // Planning sees only the AI's observation of the pre-turn board. It never
            // receives the human's draft or submitted orders.
            let ai_orders = ai::plan(&self.scenario, ai_player).map_err(|error| {
                tracing::error!(
                    event = "ai_planning_failed",
                    game_id = %self.source_lobby,
                    turn_number,
                    error,
                    "could not plan AI orders"
                );
                server_log::internal_error(error)
            })?;
            next_turns
                .submit(
                    &mut next_scenario,
                    ai_player,
                    turn_number,
                    ai_orders.clone(),
                )
                .map_err(|error| {
                    tracing::error!(
                        event = "ai_submission_failed",
                        game_id = %self.source_lobby,
                        turn_number,
                        error,
                        "could not submit AI orders"
                    );
                    server_log::internal_error(error)
                })?;
            submissions.push(Submission {
                player_number: ai_player,
                orders: ai_orders,
            });
        }
        if let Some(log) = &mut self.log {
            log.submitted(SubmissionResult::new(
                turn_number,
                submissions,
                &next_scenario,
                &next_turns,
            ))
            .map_err(|error| log_error(&self.source_lobby, error))?;
        }
        // Commit only after both validation/resolution and the durable write succeed.
        self.last_activity = Instant::now();
        self.turns = next_turns;
        self.scenario = next_scenario;
        if self.turns.outcome.is_some() {
            self.finished_at = Some(Instant::now());
        }
        if self.turns.number != turn_number
            && let Some(activity) = &mut self.activity
        {
            *activity = [ActivityClock::new(Instant::now()); 2];
        }
        if self.turns.number != turn_number
            && let Some(resolution) = &self.turns.last_resolution
        {
            for (observation, player) in self.observations.iter_mut().zip(PlayerNumber::ALL) {
                observation.resolve(&self.scenario, player, resolution);
            }
        }
        self.player_view(identity)
    }
}

struct ObservedBoard {
    scenario: Scenario,
    visible: Vec<Coordinate>,
    last_resolution: Option<TurnResolution>,
}

/// Replay can use the player's historical observation or the authoritative record.
pub enum ArchivedView {
    Player(visibility::PlayerObservation),
    Revealed(Option<TurnResolution>),
}

fn all_tiles(source: &Scenario) -> Vec<Coordinate> {
    (0..source.map.height())
        .flat_map(|y| (0..source.map.width()).map(move |x| Coordinate::new(x as u16, y as u16)))
        .collect()
}

/// Shared terminal reveal and fog projection for live and recorded boards.
fn observed_board(
    source: &Scenario,
    observation: &visibility::PlayerObservation,
    outcome: Option<GameOutcome>,
    player_number: PlayerNumber,
) -> ObservedBoard {
    let (scenario, visible) = if outcome.is_some() {
        let visible = all_tiles(source);
        (source.clone(), visible)
    } else {
        let visible = visibility::visible_tiles(source, player_number);
        let mut scenario = visibility::observed_scenario(source, player_number, &visible);
        scenario.supply_crates = observation.supply_crates.clone();
        observation.apply_depot_memory(&mut scenario.depots);
        (scenario, visible.into_iter().collect())
    };
    let mut last_resolution = observation.last_resolution.clone();
    if outcome.is_some()
        && let Some(resolution) = &mut last_resolution
    {
        // Lift fog only after the original, viewer-specific final turn has played.
        resolution.frames.push(TurnFrame {
            losses: Vec::new(),
            sabotages: Vec::new(),
            departures: Vec::new(),
            indirect_impacts: Vec::new(),
            depots: scenario.depots.clone(),
            supply_crates: scenario.supply_crates.clone(),
            shots: Vec::new(),
            units: scenario.units.clone(),
            visible_tiles: visible.clone(),
            duration_ms: 180,
        });
    }
    ObservedBoard {
        scenario,
        visible,
        last_resolution,
    }
}

impl GameSnapshot {
    pub fn set_replay_orders(&mut self, orders: Vec<RecordedOrder>) {
        self.replay_orders = orders;
        if let Some(resolution) = &mut self.last_resolution {
            let mut states = BTreeMap::new();
            for frame in &mut resolution.frames {
                for unit in &mut frame.units {
                    if let Some(state) = unit.combat_state {
                        states.insert(unit.unit_id(), state);
                    } else {
                        unit.combat_state = states.get(&unit.unit_id()).copied();
                    }
                }
            }
            for unit in &mut self.scenario.units {
                unit.combat_state = states.get(&unit.unit_id()).copied();
            }
        }
    }

    pub fn archived(
        started: &GameStarted,
        source: &Scenario,
        view: ArchivedView,
        outcome: Option<GameOutcome>,
        player: PlayerNumber,
        turn_number: i32,
    ) -> Self {
        let ObservedBoard {
            scenario,
            visible: visible_tiles,
            last_resolution,
        } = match view {
            ArchivedView::Player(observation) => {
                observed_board(source, &observation, outcome, player)
            }
            ArchivedView::Revealed(mut last_resolution) => {
                let visible = all_tiles(source);
                if let Some(resolution) = &mut last_resolution {
                    // The report remains viewer-specific even when the battlefield is revealed.
                    resolution
                        .reports
                        .retain(|report| report.player_number == player);
                    for frame in &mut resolution.frames {
                        frame.visible_tiles = visible.clone();
                    }
                }
                ObservedBoard {
                    scenario: source.clone(),
                    visible,
                    last_resolution,
                }
            }
        };
        Self {
            inactivity: None,
            replay_orders: Vec::new(),
            turn_number,
            outcome,
            submitted: true,
            opponent_submitted: true,
            last_resolution,
            id: started.game_id.to_string(),
            name: started.name.clone(),
            map_type: started.map_type.clone(),
            players: started
                .players
                .iter()
                .map(|entry| GamePlayerView {
                    name: entry.name.clone(),
                    is_host: false,
                    is_you: entry.player_number == player,
                    player_number: entry.player_number,
                    is_ai: entry.controller != Controller::Human,
                    controller: entry.controller,
                })
                .collect(),
            is_host: false,
            is_member: false,
            game_url: None,
            scenario,
            movement_rules: movement::rules(),
            visible_tiles,
        }
    }
}

pub fn get(context: &Context, id: LobbyId) -> FieldResult<GameSnapshot> {
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
    let game = match &mut *entry {
        GameRegistry::Closed => return error("this game no longer exists."),
        GameRegistry::Lobby(_) => return error("The host has not started the game yet."),
        GameRegistry::Game(game) => game,
    };
    game.expire_inactive(Instant::now())?;
    game.view(context.identity().as_ref())
}

pub fn resign(context: &Context, id: LobbyId) -> FieldResult<GameSnapshot> {
    let entry = context
        .store
        .entry(&id)?
        .ok_or_else(|| FieldError::from("this game no longer exists."))?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("the server state is unavailable.")
    })?;
    let game = match &mut *entry {
        GameRegistry::Closed => return error("this game no longer exists."),
        GameRegistry::Lobby(_) => return error("this game no longer exists."),
        GameRegistry::Game(game) => game,
    };
    game.resign(context.identity().as_ref())
}

pub fn renew_inactivity_timer(
    context: &Context,
    id: LobbyId,
    turn_number: i32,
    reason: InactivityRenewalReason,
) -> FieldResult<GameSnapshot> {
    let entry = context
        .store
        .entry(&id)?
        .ok_or_else(|| FieldError::from("this game no longer exists."))?;
    let mut entry = entry.lock().map_err(|_| {
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("the server state is unavailable.")
    })?;
    let game = match &mut *entry {
        GameRegistry::Closed => return error("this game no longer exists."),
        GameRegistry::Lobby(_) => return error("this game no longer exists."),
        GameRegistry::Game(game) => game,
    };
    game.renew_inactivity_timer(
        context.identity().as_ref(),
        turn_number,
        reason,
        Instant::now(),
    )
}

pub fn submit_turn(
    context: &Context,
    id: LobbyId,
    turn_number: i32,
    orders: Vec<UnitOrderInput>,
) -> FieldResult<GameSnapshot> {
    let entry = context
        .store
        .entry(&id)?
        .ok_or_else(|| FieldError::from("this game no longer exists."))?;
    let mut entry = entry.try_lock().map_err(|error| {
        if let TryLockError::WouldBlock = error {
            return FieldError::new(
                "this game is busy. please try again shortly.",
                juniper::graphql_value!({ "code": "GAME_BUSY", "retryAfterSeconds": 1 }),
            );
        }
        tracing::error!(
            event = "server_state_lock_unavailable",
            game_id = %id,
            "game state lock is poisoned"
        );
        server_log::internal_error("the server state is unavailable.")
    })?;
    let game = match &mut *entry {
        GameRegistry::Closed => return error("this game no longer exists."),
        GameRegistry::Lobby(_) => return error("this game no longer exists."),
        GameRegistry::Game(game) => game,
    };
    game.submit_turn(
        context.identity().as_ref(),
        turn_number,
        orders,
        &context.mutation_limits,
    )
}

fn log_error(id: &LobbyId, error: std::io::Error) -> FieldError {
    tracing::error!(event = "game_archive_write_failed", game_id = %id, error = %error, "could not record game transition");
    server_log::internal_error(
        "the game could not be recorded. please retry after the server storage is available.",
    )
}

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map_definition::MapDefinition,
        player_name::PlayerName,
        scenario::{ResourceKind, UnitKind},
        supplies::{CargoStock, GroundSupplyCrate},
        test_support::{FixtureValue, TestResult},
        turns::CoordinateInput,
    };

    fn inactivity_fixture(now: Instant) -> TestResult<Game> {
        let scenario = MapDefinition::parse(r#"{
            "width": 9, "height": 3, "theme": "GreenForest",
            "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 8, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let players = PlayerNumber::ALL
            .into_iter()
            .map(|player_number| {
                let name = format!("{player_number:?}");
                Ok(Player {
                    player_number,
                    controller: PlayerController::Human(SessionToken::from_token(name.clone())),
                    name: PlayerName::parse(&name).fixture()?,
                })
            })
            .collect::<TestResult<Vec<_>>>()?;
        let mut game = Game::new(
            LobbyId::from_token("a1".repeat(16)),
            LobbyName::parse("Inactivity test").fixture()?,
            MapId::default(),
            SessionToken::from_token("Player1".to_owned()),
            players,
            scenario,
        );
        game.activity = Some([ActivityClock::new(now); 2]);
        Ok(game)
    }

    #[test]
    fn inactivity_graphql_preserves_disabled_enabled_and_warning_states() -> TestResult<()> {
        use juniper::{EmptyMutation, EmptySubscription, RootNode, Variables};
        use serde_json::json;

        #[derive(GraphQLObject)]
        struct Query {
            snapshot: GameSnapshot,
        }

        let now = Instant::now();
        let host = SessionToken::from_token("Player1".to_owned());
        let mut game = inactivity_fixture(now)?;
        for (clock, expected) in [
            (
                Some(ActivityClock::new(now)),
                json!({ "warningSecondsRemaining": null }),
            ),
            (
                Some(ActivityClock::new(now - Duration::from_secs(121))),
                json!({ "warningSecondsRemaining": 59 }),
            ),
            (None, serde_json::Value::Null),
        ] {
            game.activity = clock.map(|clock| [clock; 2]);
            let schema = RootNode::new(
                Query {
                    snapshot: game.view(Some(&host)).fixture()?,
                },
                EmptyMutation::<()>::new(),
                EmptySubscription::<()>::new(),
            );
            let (data, errors) = juniper::execute_sync(
                "{ snapshot { inactivity { warningSecondsRemaining } } }",
                None,
                &schema,
                &Variables::new(),
                &(),
            )
            .fixture()?;
            assert!(errors.is_empty(), "{errors:?}");
            let data = serde_json::to_value(data)?;
            assert_eq!(data["snapshot"]["inactivity"], expected);
        }
        Ok(())
    }

    #[test]
    fn inactivity_is_private_and_only_current_member_interactions_renew_it() -> TestResult<()> {
        let now = Instant::now();
        let mut game = inactivity_fixture(now)?;
        let host = SessionToken::from_token("Player1".to_owned());
        let guest = SessionToken::from_token("Player2".to_owned());
        let outsider = SessionToken::from_token("outsider".into());
        let stale = now - Duration::from_secs(121);
        game.activity.as_mut().fixture()?[0] = ActivityClock::new(stale);
        let deadline = game.activity.as_ref().fixture()?[0].deadline();
        let own = game.view(Some(&host)).fixture()?;
        assert!(
            own.inactivity
                .as_ref()
                .fixture()?
                .warning_seconds_remaining
                .is_some_and(|seconds| seconds > 0 && seconds <= 60)
        );
        assert_eq!(
            game.view(Some(&guest))
                .fixture()?
                .inactivity
                .fixture()?
                .warning_seconds_remaining,
            None
        );
        assert!(
            game.renew_inactivity_timer(None, 1, InactivityRenewalReason::UserInteraction, now)
                .is_err()
        );
        assert!(
            game.renew_inactivity_timer(
                Some(&outsider),
                1,
                InactivityRenewalReason::UserInteraction,
                now
            )
            .is_err()
        );
        game.renew_inactivity_timer(
            Some(&host),
            0,
            InactivityRenewalReason::UserInteraction,
            now,
        )
        .fixture()?;
        // Playback cannot manufacture an allowance before a turn has resolved.
        game.renew_inactivity_timer(
            Some(&host),
            1,
            InactivityRenewalReason::PlaybackAllowance,
            now,
        )
        .fixture()?;
        assert_eq!(game.activity.as_ref().fixture()?[0].deadline(), deadline);
        // Reads and the other player's activity never renew this player's clock.
        game.view(Some(&host)).fixture()?;
        game.renew_inactivity_timer(
            Some(&guest),
            1,
            InactivityRenewalReason::UserInteraction,
            now,
        )
        .fixture()?;
        assert_eq!(game.activity.as_ref().fixture()?[0].deadline(), deadline);
        let renewed = game
            .renew_inactivity_timer(
                Some(&host),
                1,
                InactivityRenewalReason::UserInteraction,
                now,
            )
            .fixture()?;
        assert_eq!(
            renewed.inactivity,
            Some(EnabledInactivity {
                warning_seconds_remaining: None
            })
        );
        assert!(game.activity.as_ref().fixture()?[0].deadline() > deadline);
        Ok(())
    }

    #[test]
    fn inactivity_awards_the_waiting_player_and_cannot_be_undone() -> TestResult<()> {
        let now = Instant::now();
        let mut game = inactivity_fixture(now)?;
        let host = SessionToken::from_token("Player1".to_owned());
        let guest = SessionToken::from_token("Player2".to_owned());
        // A submitted player is safe even if their own activity is older.
        game.turns.orders[0] = Some(Vec::new());
        let board = serde_json::to_value(&game.scenario)?;
        let deadline = game.activity.as_ref().fixture()?[1].deadline();
        assert!(
            !game
                .expire_inactive(deadline - Duration::from_nanos(1))
                .fixture()?
        );
        let last_activity = game.admin_snapshot(now).last_activity;
        assert!(game.expire_inactive(deadline).fixture()?);
        assert_eq!(game.admin_snapshot(deadline).last_activity, last_activity);
        assert_eq!(
            game.turns.outcome,
            Some(GameOutcome::Inactivity(Some(PlayerNumber::Player1)))
        );
        assert_eq!(game.turns.number, 1);
        assert!(game.turns.orders.iter().all(Option::is_none));
        assert_eq!(serde_json::to_value(&game.scenario)?, board);
        let final_view = game.view(Some(&host)).fixture()?;
        assert_eq!(final_view.scenario.units.len(), game.scenario.units.len());
        assert_eq!(final_view.visible_tiles.len(), 9 * 3);
        game.renew_inactivity_timer(
            Some(&guest),
            1,
            InactivityRenewalReason::UserInteraction,
            deadline,
        )
        .fixture()?;
        game.resign(Some(&host)).fixture()?;
        assert!(
            !game
                .expire_inactive(deadline + Duration::from_secs(1))
                .fixture()?
        );
        assert_eq!(game.finished_at, Some(deadline));
        assert_eq!(
            game.turns.outcome,
            Some(GameOutcome::Inactivity(Some(PlayerNumber::Player1)))
        );
        assert!(
            game.view(Some(&host))
                .fixture()?
                .inactivity
                .fixture()?
                .warning_seconds_remaining
                .is_none()
        );
        Ok(())
    }

    #[test]
    fn inactivity_uses_the_earliest_deadline_and_draws_only_on_a_tie() -> TestResult<()> {
        let now = Instant::now();
        for (delay, winner) in [(0, None), (1, Some(PlayerNumber::Player2))] {
            let mut game = inactivity_fixture(now)?;
            game.activity.as_mut().fixture()?[1] =
                ActivityClock::new(now + Duration::from_secs(delay));
            game.expire_inactive(now + Duration::from_secs(200))
                .fixture()?;
            assert_eq!(game.turns.outcome, Some(GameOutcome::Inactivity(winner)));
        }
        let mut late_submission = inactivity_fixture(now - Duration::from_secs(181))?;
        let host = SessionToken::from_token("Player1".to_owned());
        late_submission.activity.as_mut().fixture()?[1] = ActivityClock::new(now);
        let snapshot = late_submission
            .submit_turn(Some(&host), 1, Vec::new(), &Limits::default())
            .fixture()?;
        assert_eq!(
            snapshot.outcome,
            Some(GameOutcome::Inactivity(Some(PlayerNumber::Player2)))
        );
        Ok(())
    }

    #[test]
    fn inactivity_exempts_ai_and_preview_and_resets_after_resolution() -> TestResult<()> {
        let now = Instant::now();
        let mut game = inactivity_fixture(now)?;
        let host = SessionToken::from_token("Player1".to_owned());
        let guest = SessionToken::from_token("Player2".to_owned());
        // Actual valid submissions advance the turn and renew both clocks.
        for (player, session) in [
            (PlayerNumber::Player1, &host),
            (PlayerNumber::Player2, &guest),
        ] {
            let orders = game
                .scenario
                .units
                .iter()
                .filter(|unit| unit.player_number() == player)
                .map(|unit| {
                    let position = unit.board_position().fixture()?;
                    Ok(serde_json::from_value(serde_json::json!({
                        "unit_id": unit.id(), "path": [{"x": position.x(), "y": position.y()}]
                    }))?)
                })
                .collect::<TestResult<Vec<UnitOrderInput>>>()?;
            game.submit_turn(Some(session), 1, orders, &Limits::default())
                .fixture()?;
        }
        assert_eq!(game.turns.number, 2);
        let deadline = game.activity.as_ref().fixture()?[0].deadline();
        game.renew_inactivity_timer(
            Some(&host),
            2,
            InactivityRenewalReason::BriefingAllowance,
            now + Duration::from_secs(10),
        )
        .fixture()?;
        assert_eq!(game.activity.as_ref().fixture()?[0].deadline(), deadline);
        game.renew_inactivity_timer(
            Some(&host),
            2,
            InactivityRenewalReason::PlaybackAllowance,
            now + Duration::from_secs(10),
        )
        .fixture()?;
        assert!(game.activity.as_ref().fixture()?[0].deadline() > deadline);
        let mut preview = game.into_development_preview();
        assert!(
            !preview
                .expire_inactive(now + Duration::from_secs(10000))
                .fixture()?
        );
        let mut ai = inactivity_fixture(now)?;
        ai.players.get_mut(1).fixture()?.controller = PlayerController::Ai;
        let mut ai = Game::new(
            ai.source_lobby,
            ai.name,
            ai.map_type,
            ai.host,
            ai.players,
            ai.scenario,
        );
        assert!(ai.activity.is_none());
        assert_eq!(ai.view(Some(&host)).fixture()?.inactivity, None);
        assert!(
            !ai.expire_inactive(now + Duration::from_secs(10000))
                .fixture()?
        );
        Ok(())
    }

    #[test]
    fn inactivity_finish_is_durable_replayable_and_retries_after_storage_failure() -> TestResult<()>
    {
        use crate::game_log::{self, Archive};
        use std::{
            fs,
            time::{SystemTime, UNIX_EPOCH},
        };
        let directory = std::env::temp_dir().join(format!(
            "fightlines-inactivity-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let logs = Directory::open(directory.clone())?;
        let now = Instant::now();
        let mut game = inactivity_fixture(now)?;
        game.turns.orders[0] = Some(Vec::new());
        game.record_start(&logs).fixture()?;
        let deadline = game.activity.as_ref().fixture()?[1].deadline();
        let offline = directory.with_extension("offline");
        fs::rename(&directory, &offline)?;
        assert!(game.expire_inactive(deadline).is_err());
        assert_eq!(game.turns.outcome, None);
        assert!(game.turns.orders[0].is_some());
        assert_eq!(game.finished_at, None);
        fs::rename(&offline, &directory)?;
        game.expire_inactive(deadline).fixture()?;
        let archive_path = fs::read_dir(&directory)?.next().fixture()??.path();
        let archive = Archive::read(&archive_path)?;
        assert_eq!(archive.submissions.len(), 1);
        assert_eq!(
            archive.submissions.first().fixture()?.outcome,
            Some(GameOutcome::Inactivity(Some(PlayerNumber::Player1)))
        );
        assert!(game_log::replay(&archive_path)?.contains("Inactivity(Some(Player1))"));
        game.expire_inactive(deadline).fixture()?;
        assert_eq!(Archive::read(&archive_path)?.submissions.len(), 1);
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[test]
    fn ai_busy_preserves_the_turn_and_human_games_can_continue() -> TestResult<()> {
        let scenario = MapDefinition::parse(r#"{
            "width": 9, "height": 3, "theme": "GreenForest",
            "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 8, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let host = SessionToken::from_token("host".into());
        let guest = SessionToken::from_token("guest".into());
        let mut game = Game::new(
            LobbyId::from_token("1".repeat(32)),
            LobbyName::parse("Admission test").fixture()?,
            MapId::default(),
            host.clone(),
            vec![
                Player {
                    player_number: PlayerNumber::Player1,
                    controller: PlayerController::Human(host.clone()),
                    name: PlayerName::parse("Host").fixture()?,
                },
                Player {
                    player_number: PlayerNumber::Player2,
                    controller: PlayerController::Ai,
                    name: PlayerName::parse("AI").fixture()?,
                },
            ],
            scenario.clone(),
        );
        let orders: Vec<UnitOrderInput> = serde_json::from_value(serde_json::json!([
            { "unit_id": "1", "path": [{ "x": 0, "y": 1 }] }
        ]))?;
        let limits = Limits::default();
        let permit = limits.acquire_ai().fixture()?;
        // Invalid requests are rejected before AI admission.
        let invalid = game
            .submit_turn(Some(&host), 1, vec![], &limits)
            .err()
            .fixture()?;
        assert!(!invalid.message().contains("ai is busy"));
        let busy = game
            .submit_turn(Some(&host), 1, orders.clone(), &limits)
            .err()
            .fixture()?;
        assert!(busy.message().contains("ai is busy"));
        assert_eq!(game.scenario, scenario);
        assert_eq!(game.turns.number, 1);
        assert!(game.turns.orders.iter().all(Option::is_none));
        assert!(game.finished_at.is_none());
        // A human-only game uses no AI permit, even while another game owns it.
        game.players.get_mut(1).fixture()?.controller = PlayerController::Human(guest);
        game.submit_turn(Some(&host), 1, orders.clone(), &limits)
            .fixture()?;
        assert!(game.turns.orders.first().fixture()?.is_some());
        game.turns = Turns::default();
        game.players.get_mut(1).fixture()?.controller = PlayerController::Ai;
        drop(permit);
        game.submit_turn(Some(&host), 1, orders, &limits)
            .fixture()?;
        assert_eq!(game.turns.number, 2);
        assert!(limits.acquire_ai().is_ok());
        Ok(())
    }

    #[test]
    fn resignation_retention_is_fixed_and_only_starts_after_a_durable_finish() -> TestResult<()> {
        use std::{
            fs,
            time::{SystemTime, UNIX_EPOCH},
        };

        let directory = std::env::temp_dir().join(format!(
            "fightlines-finished-retention-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let logs = Directory::open(directory.clone())?;
        let scenario = MapDefinition::parse(r#"{
            "width": 9, "height": 3, "theme": "GreenForest",
            "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 8, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let host = SessionToken::from_token("retention-host".into());
        let mut game = Game::new(
            LobbyId::from_token("1".repeat(32)),
            LobbyName::parse("Retention test").fixture()?,
            MapId::default(),
            host.clone(),
            vec![Player {
                player_number: PlayerNumber::Player1,
                controller: PlayerController::Human(host.clone()),
                name: PlayerName::parse("Host").fixture()?,
            }],
            scenario,
        );
        game.record_start(&logs).fixture()?;
        assert!(!game.is_expired(Instant::now() + FINISHED_GAME_RETENTION));
        assert!(game.resign(None).is_err());
        assert!(game.finished_at.is_none());

        let offline = directory.with_extension("offline");
        fs::rename(&directory, &offline)?;
        assert!(game.resign(Some(&host)).is_err());
        assert!(game.finished_at.is_none());
        assert!(game.turns.outcome.is_none());
        fs::rename(&offline, &directory)?;

        game.resign(Some(&host)).fixture()?;
        let finished_at = game.finished_at.fixture()?;
        assert!(!game.is_expired(finished_at + FINISHED_GAME_RETENTION - Duration::from_nanos(1)));
        assert!(game.is_expired(finished_at + FINISHED_GAME_RETENTION));
        game.view(Some(&host)).fixture()?;
        game.resign(Some(&host)).fixture()?;
        assert_eq!(game.finished_at, Some(finished_at));
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[test]
    fn terminal_snapshots_lift_fog_after_projected_playback_for_both_players() -> TestResult<()> {
        for outcome in [
            GameOutcome::Victory(PlayerNumber::Player1),
            GameOutcome::Victory(PlayerNumber::Player2),
            GameOutcome::Draw,
        ] {
            let scenario = MapDefinition::parse(r#"{
                "width": 9, "height": 3, "theme": "GreenForest",
                "features": [{"position": {"x": 8, "y": 2}, "terrain": "Forest"}],
                "depots": [{"position": {"x": 4, "y": 1}, "kind": "Supply"}],
                "units": [
                    {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                    {"id": 2, "position": {"x": 0, "y": 2}, "playerNumber": "Player1", "kind": "Truck", "direction": null},
                    {"id": 3, "position": {"x": 8, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"},
                    {"id": 4, "position": {"x": 8, "y": 2}, "playerNumber": "Player2", "kind": "Truck", "direction": null}
                ]
            }"#).fixture()?.scenario().fixture()?;
            let host = SessionToken::from_token("development-player-1".into());
            let mut game = Game::new(
                LobbyId::from_token("0".repeat(32)),
                LobbyName::parse("Test game").fixture()?,
                MapId::default(),
                host.clone(),
                vec![
                    Player {
                        player_number: PlayerNumber::Player1,
                        controller: PlayerController::Human(host),
                        name: PlayerName::parse("Test player 1").fixture()?,
                    },
                    Player {
                        player_number: PlayerNumber::Player2,
                        controller: PlayerController::Human(SessionToken::from_token(
                            "development-player-2".into(),
                        )),
                        name: PlayerName::parse("Test player 2").fixture()?,
                    },
                ],
                scenario,
            );
            // A remote depot and freight remain outside both armies' sight.
            let hidden = Coordinate::new(4, 1);
            game.scenario.supply_crates = vec![GroundSupplyCrate {
                position: hidden,
                stock: CargoStock::new(ResourceKind::Fuel, 100),
            }];
            for unit in &mut game.scenario.units {
                let survives = match outcome {
                    GameOutcome::Victory(winner)
                    | GameOutcome::Resignation(winner)
                    | GameOutcome::Inactivity(Some(winner)) => unit.player_number() == winner,
                    GameOutcome::Draw | GameOutcome::Inactivity(None) => false,
                };
                if !survives && unit.kind() != UnitKind::Truck {
                    unit.set_supplies_for_test(4);
                    unit.set_exhaustion_for_test(1);
                }
            }
            for (observation, player) in game
                .observations
                .iter_mut()
                .zip([PlayerNumber::Player1, PlayerNumber::Player2])
            {
                *observation = visibility::PlayerObservation::new(&game.scenario, player);
            }
            let sessions = [
                game.host.clone(),
                game.players
                    .get(1)
                    .fixture()?
                    .controller
                    .session()
                    .fixture()?
                    .clone(),
            ];
            for session in &sessions {
                let ongoing = game.player_view(session).fixture()?;
                assert!(!ongoing.visible_tiles.contains(&hidden));
                assert!(ongoing.scenario.supply_crates.is_empty());
                assert!(ongoing.scenario.units.len() < game.scenario.units.len());
            }
            for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                let orders = game
                    .scenario
                    .units
                    .iter()
                    .filter(|unit| unit.player_number() == player)
                    .map(|unit| {
                        let position = unit.board_position().fixture()?;
                        Ok(UnitOrderInput {
                            unit_id: unit.id(),
                            path: vec![CoordinateInput {
                                x: position.x(),
                                y: position.y(),
                            }],
                            direction: None,
                            ambush: None,
                            stand_ground: None,
                            dig_in: None,
                            sabotage: None,
                            indirect_fire: None,
                            attack_move: None,
                            unloads: None,
                            load_crates: None,
                            pickup_ground_freight: None,
                            crate_unloads: None,
                        })
                    })
                    .collect::<TestResult<Vec<_>>>()?;
                game.submit_turn(
                    Some(sessions.get(player.index()).fixture()?),
                    1,
                    orders,
                    &Limits::default(),
                )
                .fixture()?;
            }
            assert_eq!(game.turns.outcome, Some(outcome));
            let finished_at = game.finished_at.fixture()?;
            assert!(
                !game.is_expired(finished_at + FINISHED_GAME_RETENTION - Duration::from_nanos(1))
            );
            assert!(game.is_expired(finished_at + FINISHED_GAME_RETENTION));
            for (index, session) in sessions.iter().enumerate() {
                let observation = game.observations.get(index).fixture()?;
                let original = observation.last_resolution.as_ref().fixture()?.clone();
                let snapshot = game.player_view(session).fixture()?;
                assert_eq!(snapshot.scenario, game.scenario);
                let tile_count = (game.scenario.map.width() * game.scenario.map.height()) as usize;
                assert_eq!(snapshot.visible_tiles.len(), tile_count);
                assert!(snapshot.visible_tiles.contains(&hidden));
                let frames = &snapshot.last_resolution.as_ref().fixture()?.frames;
                assert_eq!(frames.len(), original.frames.len() + 1);
                for (frame, projected) in frames.iter().zip(&original.frames) {
                    assert_eq!(frame.units, projected.units);
                    assert_eq!(frame.visible_tiles, projected.visible_tiles);
                    assert_eq!(frame.supply_crates, projected.supply_crates);
                    assert!(!frame.visible_tiles.contains(&hidden));
                }
                let revealed = frames.last().fixture()?;
                assert_eq!(revealed.units, game.scenario.units);
                assert_eq!(revealed.depots, game.scenario.depots);
                assert_eq!(revealed.supply_crates, game.scenario.supply_crates);
                assert_eq!(revealed.visible_tiles, snapshot.visible_tiles);
                assert!(revealed.shots.is_empty());
                assert!(revealed.departures.is_empty());
                assert!(revealed.indirect_impacts.is_empty());
                // Repeated queries/reconnects reveal once without changing stored observations.
                let refreshed = game.player_view(session).fixture()?;
                assert_eq!(refreshed.scenario, snapshot.scenario);
                assert_eq!(
                    refreshed.last_resolution.as_ref().fixture()?.frames.len(),
                    frames.len()
                );
                assert_eq!(
                    game.observations
                        .get(index)
                        .fixture()?
                        .last_resolution
                        .as_ref()
                        .fixture()?
                        .frames
                        .len(),
                    original.frames.len()
                );
            }
        }
        Ok(())
    }
}
