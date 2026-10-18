use crate::graphql::Context;
use crate::{
    ai,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map::MapError,
    map_type::MapType,
    player_name::PlayerName,
    scenario::{PlayerNumber, Scenario},
    seed::{self, Seed},
    session_token::SessionToken,
    turns::{GameOutcome, MoveOrderInput, TurnResolution, Turns},
    visibility,
};
use juniper::{FieldError, FieldResult, GraphQLEnum, GraphQLObject};

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

pub struct Store(Mutex<State>);

struct State {
    seed: Seed,
    lobbies: BTreeMap<LobbyId, Lobby>,
    games: BTreeMap<LobbyId, Game>,
}

impl Store {
    pub fn new(seed: Seed) -> Self {
        Self(Mutex::new(State::new(seed)))
    }

    pub fn development(seed: Seed) -> Result<Self, DevelopmentError> {
        let mut state = State::new(seed);
        let host = SessionToken::from_token("development-player-1".into());
        let map_type = MapType::default();
        let mut game = Game::from_lobby(
            Lobby {
                id: LobbyId::from_token("00000000000000000000000000000000".into()),
                name: LobbyName::parse("Test game").ok_or(DevelopmentError::InvalidName)?,
                map_type,
                host: host.clone(),
                players: vec![
                    Player {
                        controller: PlayerController::Human(host),
                        name: PlayerName::parse("Test player 1")
                            .ok_or(DevelopmentError::InvalidName)?,
                    },
                    Player {
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
        Ok(Self(Mutex::new(state)))
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

struct Lobby {
    id: LobbyId,
    name: LobbyName,
    map_type: MapType,
    host: SessionToken,
    players: Vec<Player>,
}

/// Starting consumes the lobby. The source ID keeps existing invite URLs
/// resolvable for polling players and repeated start requests.
struct Game {
    turns: Turns,
    observations: [visibility::PlayerObservation; 2],
    access: GameAccess,
    scenario: Scenario,
    source_lobby: LobbyId,
    name: LobbyName,
    map_type: MapType,
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

enum PlayerController {
    Human(SessionToken),
    Ai,
}

impl PlayerController {
    fn session(&self) -> Option<&SessionToken> {
        match self {
            Self::Human(session) => Some(session),
            Self::Ai => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Opponent {
    Human,
    Ai,
}

struct Player {
    controller: PlayerController,
    name: PlayerName,
}

#[derive(GraphQLObject)]
pub struct Snapshot {
    id: String,
    name: String,
    map_type: MapType,
    players: Vec<PlayerView>,
    is_host: bool,
    is_member: bool,
    game_url: Option<String>,
}

#[derive(GraphQLObject)]
struct PlayerView {
    name: String,
    is_host: bool,
    is_ai: bool,
}

/// Public game response built for an authorized member's session.
/// Stored game state remains in `Game`; viewer-specific flags are computed here.
#[derive(GraphQLObject)]
pub struct GameSnapshot {
    turn_number: i32,
    outcome: Option<GameOutcome>,
    submitted: bool,
    opponent_submitted: bool,
    last_resolution: Option<TurnResolution>,
    id: String,
    name: String,
    map_type: MapType,
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
}

//----------------------------------------------------------------
// SNAPSHOTS
//----------------------------------------------------------------

struct SnapshotSource<'a> {
    id: &'a LobbyId,
    name: &'a LobbyName,
    map_type: MapType,
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
        map_type: source.map_type,
        players: source
            .players
            .iter()
            .map(|player| PlayerView {
                name: player.name.to_string(),
                is_host: player.controller.session() == Some(source.host),
                is_ai: player.controller.session().is_none(),
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
            map_type: lobby.map_type,
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
            map_type: game.map_type,
            host: &game.host,
            players: &game.players,
        },
        session,
        Some(format!("/game/{}", game.source_lobby)),
    )
}

fn game_view(game: &Game, session: &SessionToken) -> GameSnapshot {
    let index = usize::from(session != &game.host);
    let player_number = if index == 0 {
        PlayerNumber::Player1
    } else {
        PlayerNumber::Player2
    };
    let visible = visibility::visible_tiles(&game.scenario, player_number);
    let mut scenario = visibility::observed_scenario(&game.scenario, player_number, &visible);
    scenario.supply_crates = game.observations[index].supply_crates.clone();
    GameSnapshot {
        turn_number: game.turns.number,
        outcome: game.turns.outcome,
        submitted: game.turns.orders[index].is_some(),
        opponent_submitted: game.turns.orders[1 - index].is_some(),
        last_resolution: game.observations[index].last_resolution.clone(),
        id: game.source_lobby.to_string(),
        name: game.name.to_string(),
        map_type: game.map_type,
        players: game
            .players
            .iter()
            .zip([PlayerNumber::Player1, PlayerNumber::Player2])
            .map(|(player, player_number)| GamePlayerView {
                name: player.name.to_string(),
                is_host: player.controller.session() == Some(&game.host),
                is_you: player.controller.session() == Some(session),
                is_ai: player.controller.session().is_none(),
                player_number,
            })
            .collect(),
        is_host: session == &game.host,
        is_member: true,
        game_url: Some(format!("/game/{}", game.source_lobby)),
        scenario,
        visible_tiles: visible.into_iter().collect(),
        movement_rules: crate::movement::rules(),
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
    let mut state = context
        .store
        .0
        .lock()
        .or_else(|_| error("The server state is unavailable."))?;
    let identity = context
        .identity()
        .unwrap_or_else(|| SessionToken::from_token(state.next_token()));
    let id = LobbyId::from_token(state.next_token());
    let lobby = Lobby {
        id: id.clone(),
        name: lobby_name,
        map_type: MapType::default(),
        host: identity.clone(),
        players: vec![Player {
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
        .0
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
        .0
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
    lobby.players.push(Player {
        controller: PlayerController::Human(identity.clone()),
        name,
    });
    let result = lobby_snapshot(lobby, Some(&identity));
    context.set_identity(identity);
    Ok(result)
}

pub fn set_map_type(context: &Context, id: LobbyId, map_type: MapType) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .0
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
    lobby.map_type = map_type;
    Ok(lobby_snapshot(lobby, identity.as_ref()))
}

/// An occupied human slot cannot be replaced. Switching back opens the invite slot.
pub fn set_opponent(context: &Context, id: LobbyId, opponent: Opponent) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .0
        .lock()
        .or_else(|_| error("the server state is unavailable."))?;
    if state.games.contains_key(&id) {
        return error("the game has already started. its opponent cannot be changed.");
    }
    let lobby = state
        .lobbies
        .get_mut(&id)
        .ok_or_else(|| FieldError::from("this lobby no longer exists."))?;
    let identity = context.identity();
    if identity.as_ref() != Some(&lobby.host) {
        return error("only the host can change the opponent.");
    }
    if lobby
        .players
        .iter()
        .skip(1)
        .any(|player| player.controller.session().is_some())
    {
        return error("another player has joined. the opponent cannot be changed.");
    }
    let ai_name = PlayerName::parse("AI opponent")
        .ok_or_else(|| FieldError::from("the AI name is invalid."))?;
    lobby.players.truncate(1);
    if opponent == Opponent::Ai {
        lobby.players.push(Player {
            controller: PlayerController::Ai,
            name: ai_name,
        });
    }
    Ok(lobby_snapshot(lobby, identity.as_ref()))
}

pub fn start(context: &Context, id: LobbyId) -> FieldResult<Snapshot> {
    let mut state = context
        .store
        .0
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
    let lobby = state
        .lobbies
        .remove(&id)
        .ok_or_else(|| FieldError::from("This lobby no longer exists."))?;
    let game = Game::from_lobby(lobby, scenario);
    let result = game_snapshot(&game, identity.as_ref());
    state.games.insert(id, game);
    Ok(result)
}

pub fn game(context: &Context, id: LobbyId) -> FieldResult<GameSnapshot> {
    let state = context
        .store
        .0
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
        return Ok(game_view(game, &game.host));
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
    Ok(game_view(game, &identity))
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
        .0
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
    let index = game
        .players
        .iter()
        .position(|player| player.controller.session() == Some(&identity))
        .ok_or_else(|| {
            FieldError::new(
                "only joined players can submit turns.",
                juniper::Value::null(),
            )
        })?;
    let player_number = if index == 0 {
        PlayerNumber::Player1
    } else {
        PlayerNumber::Player2
    };
    if game
        .players
        .iter()
        .any(|player| player.controller.session().is_none())
    {
        let mut next_turns = game.turns.clone();
        let mut next_scenario = game.scenario.clone();
        // Planning sees only the AI's observation of the pre-turn board. It never
        // receives the human's draft or submitted orders.
        let ai_orders = ai::plan(&game.scenario, PlayerNumber::Player2)
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
        next_turns
            .submit(
                &mut next_scenario,
                PlayerNumber::Player2,
                turn_number,
                ai_orders,
            )
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
        next_turns
            .submit(&mut next_scenario, player_number, turn_number, orders)
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
        game.turns = next_turns;
        game.scenario = next_scenario;
    } else {
        game.turns
            .submit(&mut game.scenario, player_number, turn_number, orders)
            .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
    }
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
    Ok(game_view(game, &identity))
}

//----------------------------------------------------------------
// ERRORS
//----------------------------------------------------------------

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}
