//! Pregame setup and lobby membership.
use crate::{
    game::Game,
    graphql::Context,
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    lobby_snapshot::{Snapshot, SnapshotSource},
    map_id::{self, MapId},
    player::{Controller, Player, PlayerController},
    player_name::PlayerName,
    player_number::PlayerNumber,
    server_log,
    session_token::SessionToken,
    store::GameRegistry,
};
use juniper::{FieldError, FieldResult};

pub(crate) struct Lobby {
    id: LobbyId,
    name: LobbyName,
    map_type: MapId,
    host: SessionToken,
    players: Vec<Player>,
}

impl Lobby {
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
        let result = self.snapshot(Some(&identity));
        context.set_identity(identity);
        Ok(result)
    }

    fn set_map_type(
        &mut self,
        session: Option<&SessionToken>,
        map_type: MapId,
    ) -> FieldResult<Snapshot> {
        if session != Some(&self.host) {
            return error("Only the host can change the map.");
        }
        map_type
            .definition()
            .map_err(|error| error.to_string())?
            .scenario()
            .map_err(|error| error.to_string())?;
        self.map_type = map_type;
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
        Ok(self.snapshot(Some(identity)))
    }

    pub fn prepare_game(&self, session: Option<&SessionToken>) -> FieldResult<Game> {
        if session != Some(&self.host) {
            return error("Only the host can start a game, and only joined players can enter it.");
        }
        let required_players = self.map_type.player_count();
        if self.players.len() != required_players {
            return error(&format!(
                "this map requires {required_players} players before starting."
            ));
        }
        let scenario = self.map_type.scenario().map_err(|error| {
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
        ))
    }
}

pub fn create(context: &Context, input: &str, lobby_input: &str) -> FieldResult<Snapshot> {
    let Some(name) = PlayerName::parse(input) else {
        return error("Enter a name between 1 and 40 characters.");
    };
    let Some(lobby_name) = LobbyName::parse(lobby_input) else {
        return error("Enter a lobby name between 1 and 40 characters.");
    };
    let map_type = map_id::options()
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
        GameRegistry::Lobby(lobby) => lobby,
        GameRegistry::Game(_) => {
            return error("The game has already started. Its map cannot be changed.");
        }
    };
    lobby.set_map_type(context.identity().as_ref(), map_type)
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
