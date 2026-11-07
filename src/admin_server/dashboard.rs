//! Credential-free read models. They never grant player membership or change activity.
use crate::{
    app_version,
    graphql::Context,
    lobby_id::LobbyId,
    map_id::MapId,
    player::{Controller, Player},
    player_number::PlayerNumber,
    turns::GameOutcome,
};
use juniper::{FieldResult, GraphQLEnum, GraphQLObject};
use std::time::Instant;

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum EntryStatus {
    WaitingLobby,
    Planning,
    WaitingForPlayer,
    InactivityWarning,
    Finished,
}

#[derive(Clone, GraphQLObject)]
pub struct AdminPlayer {
    name: String,
    controller: Controller,
    player_number: PlayerNumber,
    orders_submitted: bool,
}

impl AdminPlayer {
    pub(crate) fn new(player: &Player, orders_submitted: bool) -> Self {
        Self {
            name: player.name.to_string(),
            controller: player.controller.kind(),
            player_number: player.player_number,
            orders_submitted,
        }
    }
}

/// A cached projection, updated while the owning entry is locked. Instants stay
/// internal so elapsed times can continue advancing without acquiring game locks.
#[derive(Clone)]
pub struct EntrySnapshot {
    pub id: LobbyId,
    pub name: String,
    pub map_type: MapId,
    pub status: EntryStatus,
    pub turn_number: Option<i32>,
    pub outcome: Option<GameOutcome>,
    pub players: Vec<AdminPlayer>,
    pub started_at: Option<Instant>,
    pub last_activity: Instant,
    pub warning_deadline: Option<Instant>,
}

#[derive(GraphQLObject)]
pub struct AdminEntry {
    id: String,
    name: String,
    map_type: MapId,
    status: EntryStatus,
    turn_number: Option<i32>,
    outcome: Option<GameOutcome>,
    players: Vec<AdminPlayer>,
    started_seconds_ago: Option<i32>,
    last_activity_seconds_ago: i32,
    warning_seconds_remaining: Option<i32>,
    busy: bool,
}

impl EntrySnapshot {
    pub fn project(self, busy: bool, now: Instant) -> AdminEntry {
        let elapsed = |at| {
            now.saturating_duration_since(at)
                .as_secs()
                .min(i32::MAX as u64) as i32
        };
        AdminEntry {
            id: self.id.to_string(),
            name: self.name,
            map_type: self.map_type,
            status: self.status,
            turn_number: self.turn_number,
            outcome: self.outcome,
            players: self.players,
            started_seconds_ago: self.started_at.map(elapsed),
            last_activity_seconds_ago: elapsed(self.last_activity),
            warning_seconds_remaining: self.warning_deadline.map(|deadline| {
                deadline
                    .saturating_duration_since(now)
                    .as_millis()
                    .div_ceil(1000)
                    .min(i32::MAX as u128) as i32
            }),
            busy,
        }
    }
}

#[derive(GraphQLObject)]
pub struct Dashboard {
    server_version: String,
    concurrent_games: i32,
    waiting_lobbies: i32,
    retained_finished_games: i32,
    entries: Vec<AdminEntry>,
}

pub fn get(context: &Context) -> FieldResult<Dashboard> {
    context.require_admin()?;
    let entries = context.store.admin_entries(Instant::now())?;
    Ok(Dashboard {
        server_version: app_version::current().into(),
        concurrent_games: entries
            .iter()
            .filter(|entry| {
                entry.status != EntryStatus::WaitingLobby && entry.status != EntryStatus::Finished
            })
            .count() as i32,
        waiting_lobbies: entries
            .iter()
            .filter(|entry| entry.status == EntryStatus::WaitingLobby)
            .count() as i32,
        retained_finished_games: entries
            .iter()
            .filter(|entry| entry.status == EntryStatus::Finished)
            .count() as i32,
        entries,
    })
}
