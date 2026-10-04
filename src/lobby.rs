use crate::graphql::Context;
use crate::{
    lobby_id::LobbyId,
    player_name::PlayerName,
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
    host: SessionToken,
    players: Vec<Player>,
}

/// Starting consumes the lobby. The source ID keeps existing invite URLs
/// resolvable for polling players and repeated start requests.
struct Game {
    source_lobby: LobbyId,
    host: SessionToken,
    players: Vec<Player>,
}

impl From<Lobby> for Game {
    fn from(lobby: Lobby) -> Self {
        Self {
            source_lobby: lobby.id,
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

//----------------------------------------------------------------
// SNAPSHOTS
//----------------------------------------------------------------

fn snapshot(
    id: &LobbyId,
    host: &SessionToken,
    players: &[Player],
    session: Option<&SessionToken>,
    game_url: Option<String>,
) -> Snapshot {
    Snapshot {
        id: id.to_string(),
        players: players
            .iter()
            .map(|player| PlayerView {
                name: player.name.to_string(),
                is_host: &player.session == host,
            })
            .collect(),
        is_host: session == Some(host),
        is_member: players
            .iter()
            .any(|player| Some(&player.session) == session),
        game_url,
    }
}

fn lobby_snapshot(lobby: &Lobby, session: Option<&SessionToken>) -> Snapshot {
    snapshot(&lobby.id, &lobby.host, &lobby.players, session, None)
}

fn game_snapshot(game: &Game, session: Option<&SessionToken>) -> Snapshot {
    snapshot(
        &game.source_lobby,
        &game.host,
        &game.players,
        session,
        Some(format!("/game/{}", game.source_lobby)),
    )
}

//----------------------------------------------------------------
// API
//----------------------------------------------------------------

pub fn create(context: &Context, input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
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
    let game = Game::from(state.lobbies.remove(&id).unwrap());
    let result = game_snapshot(&game, identity.as_ref());
    state.games.insert(id, game);
    Ok(result)
}

pub fn game(context: &Context, id: LobbyId) -> FieldResult<Snapshot> {
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
    let identity = context.identity();
    let result = game_snapshot(game, identity.as_ref());
    if !result.is_member {
        return error("Only the host can start a game, and only joined players can enter it.");
    }
    Ok(result)
}

//----------------------------------------------------------------
// ERRORS
//----------------------------------------------------------------

fn error<T>(message: &str) -> FieldResult<T> {
    Err(FieldError::new(message, juniper::Value::null()))
}
