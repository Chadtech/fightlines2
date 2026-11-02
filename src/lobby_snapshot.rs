//! Invite-link responses shared by pregame lobbies and started games.
use crate::{
    lobby_id::LobbyId,
    lobby_name::LobbyName,
    map_id::MapId,
    player::{Controller, Player},
    player_number::PlayerNumber,
    session_token::SessionToken,
};
use juniper::GraphQLObject;

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

pub(crate) struct SnapshotSource<'a> {
    pub id: &'a LobbyId,
    pub name: &'a LobbyName,
    pub map_type: &'a MapId,
    pub host: &'a SessionToken,
    pub players: &'a [Player],
}

impl Snapshot {
    pub(crate) fn new(
        source: SnapshotSource<'_>,
        session: Option<&SessionToken>,
        game_url: Option<String>,
    ) -> Self {
        Self {
            id: source.id.to_string(),
            name: source.name.to_string(),
            map_type: source.map_type.clone(),
            players: source
                .players
                .iter()
                .map(|player| PlayerView::new(player, source.host, session))
                .collect(),
            is_host: session == Some(source.host),
            is_member: source.players.iter().any(|player| {
                player.controller.session().is_some() && player.controller.session() == session
            }),
            game_url,
        }
    }

    pub(crate) fn is_member(&self) -> bool {
        self.is_member
    }
}

impl PlayerView {
    fn new(player: &Player, host: &SessionToken, session: Option<&SessionToken>) -> Self {
        Self {
            name: player.name.to_string(),
            player_number: player.player_number,
            is_you: player.controller.session().is_some() && player.controller.session() == session,
            is_host: player.controller.session() == Some(host),
            is_ai: player.controller.session().is_none(),
            controller: player.controller.kind(),
        }
    }
}
