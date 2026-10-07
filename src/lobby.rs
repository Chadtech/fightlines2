use crate::graphql::Context;
use crate::{
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map_type::MapType,
    player_name::PlayerName,
    scenario::{Scenario, Side},
    seed::{self, Seed},
    session_token::SessionToken,
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
        Self(Mutex::new(State {
            seed,
            lobbies: BTreeMap::new(),
            games: BTreeMap::new(),
        }))
    }
}

impl State {
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
    scenario: Scenario,
    source_lobby: LobbyId,
    name: LobbyName,
    map_type: MapType,
    host: SessionToken,
    players: Vec<Player>,
}

impl Game {
    fn from_lobby(lobby: Lobby, scenario: Scenario) -> Self {
        Self {
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
    id: String,
    name: String,
    map_type: MapType,
    players: Vec<GamePlayerView>,
    is_host: bool,
    is_member: bool,
    game_url: Option<String>,
    scenario: Scenario,
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
    GameSnapshot {
        id: game.source_lobby.to_string(),
        name: game.name.to_string(),
        map_type: game.map_type,
        players: game
            .players
            .iter()
            .zip([Side::West, Side::East])
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
        scenario: game.scenario.clone(),
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
    let Some(identity) = context.identity() else {
        return error("Only the host can start a game, and only joined players can enter it.");
    };
    if !game.players.iter().any(|player| player.session == identity) {
        return error("Only the host can start a game, and only joined players can enter it.");
    }
    Ok(game_view(game, &identity))
}

//----------------------------------------------------------------
// ERRORS
//----------------------------------------------------------------

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}
