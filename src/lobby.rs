use crate::graphql::Context;
use crate::{
    ai,
    game_archive::review::RecordedOrder,
    game_log::{Directory, GameLog, GameStarted, RecordedPlayer, Submission, SubmissionResult},
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map::{Coordinate, MapError},
    map_id::{self, MapId},
    player_name::PlayerName,
    scenario::{PlayerNumber, Scenario},
    seed::{self, Seed},
    session_token::SessionToken,
    turns::{self, GameOutcome, MoveOrderInput, TurnFrame, TurnResolution, Turns},
    visibility,
};
use juniper::{FieldError, FieldResult, GraphQLEnum, GraphQLObject};

use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::Mutex};

//----------------------------------------------------------------
// TYPES
//----------------------------------------------------------------

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
    state: Mutex<State>,
    game_logs: Option<Directory>,
}

struct State {
    seed: Seed,
    lobbies: BTreeMap<LobbyId, Lobby>,
    games: BTreeMap<LobbyId, Game>,
}

impl Store {
    pub fn new(seed: Seed) -> Self {
        Self {
            state: Mutex::new(State::new(seed)),
            game_logs: None,
        }
    }

    pub fn with_game_logs(mut self, directory: Directory) -> Self {
        self.game_logs = Some(directory);
        self
    }

    pub fn development(seed: Seed) -> Result<Self, DevelopmentError> {
        let mut state = State::new(seed);
        let host = SessionToken::from_token("development-player-1".into());
        let map_type = map_id::options()
            .map_err(DevelopmentError::Map)?
            .into_iter()
            .next()
            .ok_or_else(|| {
                DevelopmentError::Map(MapError::InvalidDefinition("map catalog is empty".into()))
            })?;
        let mut game = Game::from_lobby(
            Lobby {
                id: LobbyId::from_token("00000000000000000000000000000000".into()),
                name: LobbyName::parse("Test game").ok_or(DevelopmentError::InvalidName)?,
                map_type: map_type.clone(),
                host: host.clone(),
                players: vec![
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
            },
            map_type.scenario().map_err(DevelopmentError::Map)?,
        );
        game.access = GameAccess::DevelopmentPreview;
        state.games.insert(game.source_lobby.clone(), game);
        Ok(Self {
            state: Mutex::new(state),
            game_logs: None,
        })
    }
}

impl State {
    fn new(seed: Seed) -> Self {
        Self {
            seed,
            lobbies: BTreeMap::new(),
            games: BTreeMap::new(),
        }
    }

    fn next_token(&mut self) -> String {
        let (token, next_seed) = seed::token(self.seed);
        self.seed = next_seed;
        token
    }
}

#[derive(Clone)]
struct Lobby {
    id: LobbyId,
    name: LobbyName,
    map_type: MapId,
    host: SessionToken,
    players: Vec<Player>,
}

/// Starting consumes the lobby. The source ID keeps existing invite URLs
/// resolvable for polling players and repeated start requests.
struct Game {
    log: Option<GameLog>,
    turns: Turns,
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

impl Game {
    fn from_lobby(lobby: Lobby, scenario: Scenario) -> Self {
        Self {
            log: None,
            observations: [PlayerNumber::Player1, PlayerNumber::Player2]
                .map(|player| visibility::PlayerObservation::new(&scenario, player)),
            turns: Turns::default(),
            access: GameAccess::Members,
            scenario,
            source_lobby: lobby.id,
            name: lobby.name,
            map_type: lobby.map_type,
            host: lobby.host,
            players: lobby.players,
        }
    }
}

#[derive(Clone)]
enum PlayerController {
    Human(SessionToken),
    Ai,
}

impl PlayerController {
    fn kind(&self) -> Controller {
        match self {
            Self::Human(_) => Controller::Human,
            Self::Ai => Controller::Ai,
        }
    }

    fn session(&self) -> Option<&SessionToken> {
        match self {
            Self::Human(session) => Some(session),
            Self::Ai => None,
        }
    }
}

/// A player's public control kind, without human session credentials.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Controller {
    Human,
    #[serde(alias = "AiMedium", alias = "AiHard")]
    Ai,
}

#[derive(Clone)]
struct Player {
    player_number: PlayerNumber,
    controller: PlayerController,
    name: PlayerName,
}

#[derive(GraphQLObject)]
pub struct Snapshot {
    id: String,
    name: String,
    map_type: MapId,
    players: Vec<PlayerView>,
    is_host: bool,
    is_member: bool,
    game_url: Option<String>,
}

#[derive(GraphQLObject)]
struct PlayerView {
    name: String,
    player_number: PlayerNumber,
    is_you: bool,
    is_host: bool,
    is_ai: bool,
    controller: Controller,
}

/// Public game response built for an authorized member's session.
/// Stored game state remains in `Game`; viewer-specific flags are computed here.
#[derive(GraphQLObject)]
pub struct GameSnapshot {
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
    movement_rules: Vec<crate::movement::MovementRule>,
    visible_tiles: Vec<crate::map::Coordinate>,
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

//----------------------------------------------------------------
// SNAPSHOTS
//----------------------------------------------------------------

struct SnapshotSource<'a> {
    id: &'a LobbyId,
    name: &'a LobbyName,
    map_type: &'a MapId,
    host: &'a SessionToken,
    players: &'a [Player],
}

fn snapshot(
    source: SnapshotSource<'_>,
    session: Option<&SessionToken>,
    game_url: Option<String>,
) -> Snapshot {
    Snapshot {
        id: source.id.to_string(),
        name: source.name.to_string(),
        map_type: source.map_type.clone(),
        players: source
            .players
            .iter()
            .map(|player| PlayerView {
                name: player.name.to_string(),
                player_number: player.player_number,
                is_you: player.controller.session().is_some()
                    && player.controller.session() == session,
                is_host: player.controller.session() == Some(source.host),
                is_ai: player.controller.session().is_none(),
                controller: player.controller.kind(),
            })
            .collect(),
        is_host: session == Some(source.host),
        is_member: source.players.iter().any(|player| {
            player.controller.session().is_some() && player.controller.session() == session
        }),
        game_url,
    }
}

fn lobby_snapshot(lobby: &Lobby, session: Option<&SessionToken>) -> Snapshot {
    snapshot(
        SnapshotSource {
            id: &lobby.id,
            name: &lobby.name,
            map_type: &lobby.map_type,
            host: &lobby.host,
            players: &lobby.players,
        },
        session,
        None,
    )
}

fn game_snapshot(game: &Game, session: Option<&SessionToken>) -> Snapshot {
    snapshot(
        SnapshotSource {
            id: &game.source_lobby,
            name: &game.name,
            map_type: &game.map_type,
            host: &game.host,
            players: &game.players,
        },
        session,
        Some(format!("/game/{}", game.source_lobby)),
    )
}

fn game_view(game: &Game, session: &SessionToken) -> FieldResult<GameSnapshot> {
    let player_number = game
        .players
        .iter()
        .find(|player| player.controller.session() == Some(session))
        .map(|player| player.player_number)
        .ok_or_else(|| FieldError::from("only joined players can enter the game."))?;
    // Observation and turn arrays are indexed by map side, never roster order.
    let index = match player_number {
        PlayerNumber::Player1 => 0,
        PlayerNumber::Player2 => 1,
    };
    let ObservedBoard {
        scenario,
        visible,
        last_resolution,
    } = observed_board(
        &game.scenario,
        &game.observations[index],
        game.turns.outcome,
        player_number,
    );
    Ok(GameSnapshot {
        replay_orders: Vec::new(),
        turn_number: game.turns.number,
        outcome: game.turns.outcome,
        submitted: game.turns.orders[index].is_some(),
        opponent_submitted: game.turns.orders[1 - index].is_some(),
        last_resolution,
        id: game.source_lobby.to_string(),
        name: game.name.to_string(),
        map_type: game.map_type.clone(),
        players: game
            .players
            .iter()
            .map(|player| GamePlayerView {
                name: player.name.to_string(),
                is_host: player.controller.session() == Some(&game.host),
                is_you: player.controller.session() == Some(session),
                is_ai: player.controller.session().is_none(),
                controller: player.controller.kind(),
                player_number: player.player_number,
            })
            .collect(),
        is_host: session == &game.host,
        is_member: true,
        game_url: Some(format!("/game/{}", game.source_lobby)),
        scenario,
        visible_tiles: visible,
        movement_rules: crate::movement::rules(),
    })
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
            movement_rules: crate::movement::rules(),
            visible_tiles,
        }
    }
}

//----------------------------------------------------------------
// API
//----------------------------------------------------------------

pub fn create(context: &Context, input: &str, lobby_input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
    };
    let Some(lobby_name) = LobbyName::parse(lobby_input) else {
        return error("Enter a lobby name between 1 and 40 characters.");
    };
    let map_type = map_id::options()
        .map_err(|error| error.to_string())?
        .into_iter()
        .next()
        .ok_or("map catalog is empty")?;
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let identity = context
        .identity()
        .unwrap_or_else(|| SessionToken::from_token(state.next_token()));
    let id = LobbyId::from_token(state.next_token());
    let lobby = Lobby {
        id: id.clone(),
        name: lobby_name,
        map_type,
        host: identity.clone(),
        players: vec![Player {
            player_number: PlayerNumber::Player1,
            controller: PlayerController::Human(identity.clone()),
            name,
        }],
    };
    let result = lobby_snapshot(&lobby, Some(&identity));
    state.lobbies.insert(id, lobby);
    context.set_identity(identity);
    Ok(result)
}

pub fn get(context: &Context, id: LobbyId) -> FieldResult<Snapshot> {
    let state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let identity = context.identity();
    let result = if let Some(lobby) = state.lobbies.get(&id) {
        lobby_snapshot(lobby, identity.as_ref())
    } else if let Some(game) = state.games.get(&id) {
        game_snapshot(game, identity.as_ref())
    } else {
        return error("This lobby no longer exists. Create a new lobby from the home page.");
    };
    Ok(result)
}

pub fn join(context: &Context, id: LobbyId, input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
    };
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let identity = context.identity();
    if let Some(game) = state.games.get(&id) {
        let result = game_snapshot(game, identity.as_ref());
        return if result.is_member {
            Ok(result)
        } else {
            error("The game has already started.")
        };
    }
    let Some(lobby) = state.lobbies.get(&id) else {
        return error("This lobby no longer exists. Create a new lobby from the home page.");
    };
    if lobby.players.iter().any(|player| {
        player.controller.session().is_some() && player.controller.session() == identity.as_ref()
    }) {
        return Ok(lobby_snapshot(lobby, identity.as_ref()));
    }
    if lobby
        .players
        .iter()
        .any(|player| player.name.matches(&name))
    {
        return error("That name is already in this lobby. Choose another name.");
    }
    if lobby.players.len() >= lobby.map_type.player_count() {
        return error("This map supports two players. The lobby is full.");
    }
    let identity = identity.unwrap_or_else(|| SessionToken::from_token(state.next_token()));
    let lobby = state
        .lobbies
        .get_mut(&id)
        .ok_or_else(|| FieldError::from("This lobby no longer exists."))?;
    let player_number = vacant_side(&lobby.players)?;
    lobby.players.push(Player {
        player_number,
        controller: PlayerController::Human(identity.clone()),
        name,
    });
    let result = lobby_snapshot(lobby, Some(&identity));
    context.set_identity(identity);
    Ok(result)
}

pub fn set_map_type(context: &Context, id: LobbyId, map_type: MapId) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    if state.games.contains_key(&id) {
        return error("The game has already started. Its map cannot be changed.");
    }
    let Some(lobby) = state.lobbies.get_mut(&id) else {
        return error("This lobby no longer exists. Create a new lobby from the home page.");
    };
    let identity = context.identity();
    if identity.as_ref() != Some(&lobby.host) {
        return error("Only the host can change the map.");
    }
    map_type
        .definition()
        .map_err(|error| error.to_string())?
        .scenario()
        .map_err(|error| error.to_string())?;
    lobby.map_type = map_type;
    Ok(lobby_snapshot(lobby, identity.as_ref()))
}

/// An occupied human slot cannot be replaced. Switching back opens the invite slot.
pub fn set_controller(
    context: &Context,
    id: LobbyId,
    controller: Controller,
) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("the server state is unavailable."))?;
    if state.games.contains_key(&id) {
        return error("player controllers cannot be changed after the game has started.");
    }
    let lobby = state
        .lobbies
        .get_mut(&id)
        .ok_or_else(|| FieldError::from("this lobby no longer exists."))?;
    let identity = context.identity();
    if identity.as_ref() != Some(&lobby.host) {
        return error("only the host can change the controller.");
    }
    if lobby.players.iter().any(|player| {
        player.controller.session().is_some() && player.controller.session() != Some(&lobby.host)
    }) {
        return error("another player has joined. the controller cannot be changed.");
    }
    let ai_name = PlayerName::parse("AI player")
        .ok_or_else(|| FieldError::from("the AI name is invalid."))?;
    lobby
        .players
        .retain(|player| player.controller.session().is_some());
    if controller == Controller::Ai {
        let player_number = vacant_side(&lobby.players)?;
        lobby.players.push(Player {
            player_number,
            controller: PlayerController::Ai,
            name: ai_name,
        });
    }
    Ok(lobby_snapshot(lobby, identity.as_ref()))
}

/// Each participant chooses their own map side. Taking an occupied side swaps
/// assignments, preserving the other participant and the host's permissions.
pub fn set_player_number(
    context: &Context,
    id: LobbyId,
    player_number: PlayerNumber,
) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("the server state is unavailable."))?;
    if state.games.contains_key(&id) {
        return error("the game has already started. its sides cannot be changed.");
    }
    let lobby = state
        .lobbies
        .get_mut(&id)
        .ok_or_else(|| FieldError::from("this lobby no longer exists."))?;
    let identity = context
        .identity()
        .ok_or_else(|| FieldError::from("only joined players can choose a side."))?;
    let previous = lobby
        .players
        .iter()
        .find(|player| player.controller.session() == Some(&identity))
        .map(|player| player.player_number)
        .ok_or_else(|| FieldError::from("only joined players can choose a side."))?;
    for player in &mut lobby.players {
        if player.controller.session() == Some(&identity) {
            player.player_number = player_number;
        } else if player.player_number == player_number {
            player.player_number = previous;
        }
    }
    Ok(lobby_snapshot(lobby, Some(&identity)))
}

fn vacant_side(players: &[Player]) -> FieldResult<PlayerNumber> {
    [PlayerNumber::Player1, PlayerNumber::Player2]
        .into_iter()
        .find(|number| players.iter().all(|player| player.player_number != *number))
        .ok_or_else(|| FieldError::from("this lobby has no open side."))
}

pub fn start(context: &Context, id: LobbyId) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let identity = context.identity();
    if let Some(game) = state.games.get(&id) {
        if identity.as_ref() != Some(&game.host) {
            return error("Only the host can start a game, and only joined players can enter it.");
        }
        return Ok(game_snapshot(game, identity.as_ref()));
    }
    let Some(lobby) = state.lobbies.get(&id) else {
        return error("This lobby no longer exists. Create a new lobby from the home page.");
    };
    if identity.as_ref() != Some(&lobby.host) {
        return error("Only the host can start a game, and only joined players can enter it.");
    }
    if lobby.players.len() != lobby.map_type.player_count() {
        return error("This map requires two players. Invite another player before starting.");
    }
    let scenario = lobby
        .map_type
        .scenario()
        .or_else(|_| error("The map could not be initialized."))?;
    // Persist the initial board before consuming the lobby. A disk failure leaves
    // it available for the host to retry.
    let mut game = Game::from_lobby(lobby.clone(), scenario);
    if let Some(directory) = &context.store.game_logs {
        game.log = Some(
            directory
                .start(GameStarted {
                    game_id: id.clone(),
                    name: game.name.to_string(),
                    map_type: game.map_type.clone(),
                    players: game
                        .players
                        .iter()
                        .map(|player| RecordedPlayer {
                            player_number: player.player_number,
                            name: player.name.to_string(),
                            controller: player.controller.kind(),
                        })
                        .collect(),
                    scenario: game.scenario.clone(),
                    server_version: env!("CARGO_PKG_VERSION").into(),
                    build_revision: option_env!("FIGHTLINES_BUILD_REVISION").map(String::from),
                })
                .map_err(|error| log_error(&id, error))?,
        );
    }
    let result = game_snapshot(&game, identity.as_ref());
    state.lobbies.remove(&id);
    state.games.insert(id, game);
    Ok(result)
}

pub fn game(context: &Context, id: LobbyId) -> FieldResult<GameSnapshot> {
    let state = context
        .store
        .state
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let Some(game) = state.games.get(&id) else {
        return if state.lobbies.contains_key(&id) {
            error("The host has not started the game yet.")
        } else {
            error("This lobby no longer exists. Create a new lobby from the home page.")
        };
    };
    // The opt-in fixture always previews Player1, without changing browser identity.
    if matches!(game.access, GameAccess::DevelopmentPreview) {
        return game_view(game, &game.host);
    }
    let Some(identity) = context.identity() else {
        return error("Only the host can start a game, and only joined players can enter it.");
    };
    if !game
        .players
        .iter()
        .any(|player| player.controller.session() == Some(&identity))
    {
        return error("Only the host can start a game, and only joined players can enter it.");
    }
    game_view(game, &identity)
}

/// Publish the terminal result under the submission lock, after durable recording.
pub fn resign_game(context: &Context, id: LobbyId) -> FieldResult<GameSnapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("the server state is unavailable."))?;
    let game = state
        .games
        .get_mut(&id)
        .ok_or_else(|| FieldError::from("this game no longer exists."))?;
    if let GameAccess::DevelopmentPreview = game.access {
        return error("the development preview is read-only. create a game to resign.");
    }
    let identity = context
        .identity()
        .ok_or_else(|| FieldError::from("only joined players can resign."))?;
    let player = game
        .players
        .iter()
        .find(|player| player.controller.session() == Some(&identity))
        .map(|player| player.player_number)
        .ok_or_else(|| FieldError::from("only joined players can resign."))?;
    if game.turns.outcome.is_some() {
        return game_view(game, &identity);
    }
    let mut next_turns = game.turns.clone();
    next_turns.resign(player);
    if let Some(log) = &mut game.log {
        let mut result =
            SubmissionResult::new(next_turns.number, Vec::new(), &game.scenario, &next_turns);
        result.resigned_player = Some(player);
        log.submitted(result)
            .map_err(|error| log_error(&id, error))?;
    }
    game.turns = next_turns;
    game_view(game, &identity)
}

/// Submit under the same lock as validation and resolution so concurrent players
/// cannot resolve against different boards. Development preview stays read-only.
pub fn submit_turn(
    context: &Context,
    id: LobbyId,
    turn_number: i32,
    orders: Vec<MoveOrderInput>,
) -> FieldResult<GameSnapshot> {
    let mut state = context
        .store
        .state
        .lock()
        .or_else(|_| error("the server state is unavailable."))?;
    let game = state
        .games
        .get_mut(&id)
        .ok_or_else(|| FieldError::new("this game no longer exists.", juniper::Value::null()))?;
    if matches!(game.access, GameAccess::DevelopmentPreview) {
        return error(
            "the development preview is read-only. create a two-player game to submit turns.",
        );
    }
    let identity = context.identity().ok_or_else(|| {
        FieldError::new(
            "only joined players can submit turns.",
            juniper::Value::null(),
        )
    })?;
    let player_number = game
        .players
        .iter()
        .find(|player| player.controller.session() == Some(&identity))
        .map(|player| player.player_number)
        .ok_or_else(|| FieldError::from("only joined players can submit turns."))?;
    // Lost-response retries keep the already accepted orders and create no new
    // archive entry. Stale turn numbers still follow normal validation below.
    if game.turns.number == turn_number
        && game.turns.outcome.is_none()
        && game.turns.orders[turns::player_index(player_number)].is_some()
    {
        return game_view(game, &identity);
    }
    let ai_player = game
        .players
        .iter()
        .find_map(|player| match player.controller {
            PlayerController::Ai => Some(player.player_number),
            PlayerController::Human(_) => None,
        });
    let mut next_turns = game.turns.clone();
    let mut next_scenario = game.scenario.clone();
    let mut submissions = Vec::new();
    if let Some(ai_player) = ai_player {
        // Planning sees only the AI's observation of the pre-turn board. It never
        // receives the human's draft or submitted orders.
        let ai_orders = ai::plan(&game.scenario, ai_player)
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
        submissions.push(Submission {
            player_number: ai_player,
            orders: ai_orders,
        });
    }
    submissions.push(Submission {
        player_number,
        orders,
    });
    for submission in &submissions {
        next_turns
            .submit(
                &mut next_scenario,
                submission.player_number,
                turn_number,
                submission.orders.clone(),
            )
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
    }
    if let Some(log) = &mut game.log {
        log.submitted(SubmissionResult::new(
            turn_number,
            submissions,
            &next_scenario,
            &next_turns,
        ))
        .map_err(|error| log_error(&id, error))?;
    }
    // Commit only after both validation/resolution and the durable write succeed.
    game.turns = next_turns;
    game.scenario = next_scenario;
    if game.turns.number != turn_number
        && let Some(resolution) = &game.turns.last_resolution
    {
        for (observation, player) in game
            .observations
            .iter_mut()
            .zip([PlayerNumber::Player1, PlayerNumber::Player2])
        {
            observation.resolve(&game.scenario, player, resolution);
        }
    }
    game_view(game, &identity)
}

//----------------------------------------------------------------
// ERRORS
//----------------------------------------------------------------

fn log_error(id: &LobbyId, error: std::io::Error) -> FieldError {
    eprintln!("Game archive write failed for game {id}: {error}");
    FieldError::from(
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
        scenario::{ResourceKind, UnitKind},
        supplies::{CargoStock, GroundSupplyCrate},
        test_support::{FixtureValue, TestResult},
        turns::CoordinateInput,
    };

    #[test]
    fn terminal_snapshots_lift_fog_after_projected_playback_for_both_players() -> TestResult<()> {
        for outcome in [
            GameOutcome::Victory(PlayerNumber::Player1),
            GameOutcome::Victory(PlayerNumber::Player2),
            GameOutcome::Draw,
        ] {
            let store = Store::development(Seed::new([0; 32])).fixture()?;
            let mut state = store.state.lock().fixture()?;
            let game = state.games.values_mut().next().fixture()?;
            game.scenario = MapDefinition::parse(r#"{
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
            // A remote depot and freight remain outside both armies' sight.
            let hidden = Coordinate::new(4, 1);
            game.scenario.supply_crates = vec![GroundSupplyCrate {
                position: hidden,
                stock: CargoStock::new(ResourceKind::Fuel, 100),
            }];
            for unit in &mut game.scenario.units {
                let survives = match outcome {
                    GameOutcome::Victory(winner) | GameOutcome::Resignation(winner) => {
                        unit.player_number() == winner
                    }
                    GameOutcome::Draw => false,
                };
                if !survives && unit.kind() != UnitKind::Truck {
                    unit.set_supplies_for_test(4);
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
                let ongoing = game_view(game, session).fixture()?;
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
                        Ok(MoveOrderInput {
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
                game.turns
                    .submit(&mut game.scenario, player, 1, orders)
                    .fixture()?;
            }
            assert_eq!(game.turns.outcome, Some(outcome));
            for (index, player) in [PlayerNumber::Player1, PlayerNumber::Player2]
                .into_iter()
                .enumerate()
            {
                let observation = game.observations.get_mut(index).fixture()?;
                observation.resolve(
                    &game.scenario,
                    player,
                    game.turns.last_resolution.as_ref().fixture()?,
                );
                let original = observation.last_resolution.as_ref().fixture()?.clone();
                let snapshot = game_view(game, sessions.get(index).fixture()?).fixture()?;
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
                let refreshed = game_view(game, sessions.get(index).fixture()?).fixture()?;
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
