//! The entry lock owns state transitions and refreshes the operator projection.
use super::GameRegistry;
use crate::admin::dashboard::{AdminEntry, EntrySnapshot};
use juniper::FieldResult;
use std::{
    ops::{Deref, DerefMut},
    sync::{LockResult, Mutex, MutexGuard, PoisonError, TryLockError, TryLockResult},
    time::Instant,
};

pub(crate) struct Entry {
    state: Mutex<GameRegistry>,
    snapshot: Mutex<Option<EntrySnapshot>>,
}

pub(crate) struct Guard<'a> {
    state: MutexGuard<'a, GameRegistry>,
    snapshot: &'a Mutex<Option<EntrySnapshot>>,
}

fn snapshot(state: &GameRegistry) -> Option<EntrySnapshot> {
    match state {
        GameRegistry::Lobby(lobby) => Some(lobby.admin_snapshot()),
        GameRegistry::Game(game) => Some(game.admin_snapshot(Instant::now())),
        GameRegistry::Closed => None,
    }
}

impl Entry {
    pub fn new(state: GameRegistry) -> Self {
        Self {
            snapshot: Mutex::new(snapshot(&state)),
            state: Mutex::new(state),
        }
    }

    pub fn lock(&self) -> LockResult<Guard<'_>> {
        match self.state.lock() {
            Ok(state) => Ok(Guard {
                state,
                snapshot: &self.snapshot,
            }),
            Err(error) => Err(PoisonError::new(Guard {
                state: error.into_inner(),
                snapshot: &self.snapshot,
            })),
        }
    }

    pub fn try_lock(&self) -> TryLockResult<Guard<'_>> {
        match self.state.try_lock() {
            Ok(state) => Ok(Guard {
                state,
                snapshot: &self.snapshot,
            }),
            Err(TryLockError::WouldBlock) => Err(TryLockError::WouldBlock),
            Err(TryLockError::Poisoned(error)) => {
                Err(TryLockError::Poisoned(PoisonError::new(Guard {
                    state: error.into_inner(),
                    snapshot: &self.snapshot,
                })))
            }
        }
    }

    pub fn admin_snapshot(&self, now: Instant) -> FieldResult<Option<AdminEntry>> {
        let busy = match self.state.try_lock() {
            Ok(_) => false,
            Err(TryLockError::WouldBlock) => true,
            Err(TryLockError::Poisoned(_)) => {
                return Err("a game is unavailable because its state lock failed.".into());
            }
        };
        let snapshot = self
            .snapshot
            .lock()
            .map_err(|_| "game status is unavailable.")?
            .clone();
        Ok(snapshot.map(|snapshot| snapshot.project(busy, now)))
    }
}

impl Deref for Guard<'_> {
    type Target = GameRegistry;
    fn deref(&self) -> &Self::Target {
        &self.state
    }
}
impl DerefMut for Guard<'_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.state
    }
}
impl Drop for Guard<'_> {
    fn drop(&mut self) {
        // A poisoned state remains unavailable; never advertise a partial mutation.
        if std::thread::panicking() {
            return;
        }
        if let Ok(mut observed) = self.snapshot.lock() {
            *observed = snapshot(&self.state);
        }
    }
}
