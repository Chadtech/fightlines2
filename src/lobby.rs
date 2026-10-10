use crate::graphql::Context;
use crate::{
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map::MapError,
    map_type::MapType,
    player_name::PlayerName,
    scenario::{Scenario, Side},
    seed::{self, Seed},
    session_token::SessionToken,
    turns::{MoveOrderInput, TurnResolution, Turns},
};
use juniper::{FieldError, FieldResult, GraphQLObject};

use std::{collections::BTreeMap, sync::Mutex};

//----------------------------------------------------------------
// TYPES
//----------------------------------------------------------------

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

    pub fn development(seed: Seed) -> Result<Self, MapError> {
        let mut state = State::new(seed);
        let host = SessionToken::from_token("development-player-1".into());
        let map_type = MapType::default();
        let mut game = Game::from_lobby(
            Lobby {
                id: LobbyId::from_token("00000000000000000000000000000000".into()),
                name: LobbyName::parse("Test game").expect("valid fixture name"),
                map_type,
                host: host.clone(),
                players: vec![
                    Player {
                        session: host,
                        name: PlayerName::parse("Test player 1").expect("valid fixture name"),
                    },
                    Player {
                        session: SessionToken::from_token("development-player-2".into()),
                        name: PlayerName::parse("Test player 2").expect("valid fixture name"),
                    },
                ],
            },
            map_type.scenario()?,
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

struct Player {
    session: SessionToken,
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
}

/// Public game response built for an authorized member's session.
/// Stored game state remains in `Game`; viewer-specific flags are computed here.
#[derive(GraphQLObject)]
pub struct GameSnapshot {
    turn_number: i32,
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
    side: Side,
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
                is_host: &player.session == source.host,
            })
            .collect(),
        is_host: session == Some(source.host),
        is_member: source
            .players
            .iter()
            .any(|player| Some(&player.session) == session),
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
    let side = if index == 0 {
        Side::Player1
    } else {
        Side::Player2
    };
    let visible = crate::visibility::visible_tiles(&game.scenario, side);
    GameSnapshot {
        turn_number: game.turns.number,
        submitted: game.turns.orders[index].is_some(),
        opponent_submitted: game.turns.orders[1 - index].is_some(),
        last_resolution: game.turns.last_resolution.as_ref().map(|resolution| {
            crate::visibility::observed_resolution(&game.scenario, side, &visible, resolution)
        }),
        id: game.source_lobby.to_string(),
        name: game.name.to_string(),
        map_type: game.map_type,
        players: game
            .players
            .iter()
            .zip([Side::Player1, Side::Player2])
            .map(|(player, side)| GamePlayerView {
                name: player.name.to_string(),
                is_host: player.session == game.host,
                is_you: &player.session == session,
                side,
            })
            .collect(),
        is_host: session == &game.host,
        is_member: true,
        game_url: Some(format!("/game/{}", game.source_lobby)),
        scenario: crate::visibility::observed_scenario(&game.scenario, side, &visible),
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
            session: identity.clone(),
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
    if lobby
        .players
        .iter()
        .any(|player| Some(&player.session) == identity.as_ref())
    {
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
    let lobby = state.lobbies.get_mut(&id).unwrap();
    lobby.players.push(Player {
        session: identity.clone(),
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
    let game = Game::from_lobby(state.lobbies.remove(&id).unwrap(), scenario);
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
    if !game.players.iter().any(|player| player.session == identity) {
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
        .position(|player| player.session == identity)
        .ok_or_else(|| {
            FieldError::new(
                "only joined players can submit turns.",
                juniper::Value::null(),
            )
        })?;
    let side = if index == 0 {
        Side::Player1
    } else {
        Side::Player2
    };
    game.turns
        .submit(&mut game.scenario, side, turn_number, orders)
        .map_err(|message| FieldError::new(message, juniper::Value::null()))?;
    Ok(game_view(game, &identity))
}

//----------------------------------------------------------------
// ERRORS
//----------------------------------------------------------------

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}
