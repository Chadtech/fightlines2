//! Process-wide storage admission, rebuilt from durable records at startup.
use juniper::{FieldError, graphql_value};
use std::{
    fs::{self, Metadata},
    io,
    path::Path,
    sync::{Mutex, MutexGuard},
};

const BLOCK_BYTES: u64 = 4096;

/// Only operator-owned directories are scanned. Never follow symbolic links.
pub fn scan(
    directory: &Path,
    charge: &impl Fn(&Path, &Metadata) -> io::Result<Usage>,
) -> io::Result<Usage> {
    let mut used = Usage::default();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            return Err(io::Error::other(
                "storage directories cannot contain symbolic links",
            ));
        }
        used.add(charge(&path, &metadata)?);
        if metadata.is_dir() {
            used.add(scan(&path, charge)?);
        }
    }
    Ok(used)
}

#[derive(Clone, Copy, Default)]
pub struct Usage {
    bytes: u64,
    entries: u64,
}

impl Usage {
    /// Round data to 4 KiB and allow another block for filesystem metadata.
    /// Entry limits also bound inode use on filesystems with other block sizes.
    pub fn file(bytes: u64) -> Self {
        Self {
            bytes: bytes
                .div_ceil(BLOCK_BYTES)
                .saturating_add(1)
                .saturating_mul(BLOCK_BYTES),
            entries: 1,
        }
    }

    pub fn directory() -> Self {
        Self {
            bytes: BLOCK_BYTES,
            entries: 1,
        }
    }

    pub fn add(&mut self, other: Self) {
        self.bytes = self.bytes.saturating_add(other.bytes);
        self.entries = self.entries.saturating_add(other.entries);
    }
}

pub struct Capacity {
    pub bytes: u64,
    pub entries: u64,
}

pub struct Budget {
    maximum: Capacity,
    used: Mutex<Usage>,
}

impl Budget {
    pub fn new(maximum: Capacity, used: Usage) -> Self {
        Self {
            maximum,
            used: Mutex::new(used),
        }
    }

    /// Serialize admission and publication so concurrent workers cannot overshoot.
    pub fn reserve(&self, charge: Usage) -> io::Result<Reservation<'_>> {
        let mut used = self
            .used
            .lock()
            .map_err(|_| io::Error::other("storage budget lock is poisoned"))?;
        let before = *used;
        let mut next = before;
        next.add(charge);
        if next.bytes > self.maximum.bytes || next.entries > self.maximum.entries {
            return Err(io::Error::new(
                io::ErrorKind::StorageFull,
                "storage budget reached",
            ));
        }
        *used = next;
        Ok(Reservation {
            used,
            before,
            retained: false,
        })
    }
}

pub struct Reservation<'a> {
    used: MutexGuard<'a, Usage>,
    before: Usage,
    retained: bool,
}

impl Reservation<'_> {
    /// Keep the charge for published records and any files left by failed cleanup.
    pub fn retain(mut self) {
        self.retained = true;
    }
}

impl Drop for Reservation<'_> {
    fn drop(&mut self) {
        if !self.retained {
            *self.used = self.before;
        }
    }
}

pub fn full(message: &str) -> FieldError {
    FieldError::new(message, graphql_value!({ "code": "STORAGE_FULL" }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;
    use std::sync::Arc;

    #[test]
    fn enforces_bytes_and_entries_and_releases_failed_reservations() -> TestResult {
        let budget = Budget::new(
            Capacity {
                bytes: 16384,
                entries: 2,
            },
            Usage::default(),
        );
        drop(budget.reserve(Usage::file(1))?);
        budget.reserve(Usage::file(1))?.retain();
        assert!(budget.reserve(Usage::file(5000)).is_err());
        budget.reserve(Usage::file(1))?.retain();
        assert!(budget.reserve(Usage::file(0)).is_err());
        let entries = Budget::new(
            Capacity {
                bytes: u64::MAX,
                entries: 1,
            },
            Usage::default(),
        );
        entries.reserve(Usage::file(1))?.retain();
        assert!(entries.reserve(Usage::file(1)).is_err());
        Ok(())
    }

    #[test]
    fn workers_share_one_hard_limit() -> TestResult {
        let budget = Arc::new(Budget::new(
            Capacity {
                bytes: 8192,
                entries: 1,
            },
            Usage::default(),
        ));
        let workers: Vec<_> = (0..8)
            .map(|_| {
                let budget = budget.clone();
                std::thread::spawn(move || match budget.reserve(Usage::file(1)) {
                    Ok(reservation) => {
                        reservation.retain();
                        true
                    }
                    Err(_) => false,
                })
            })
            .collect();
        let mut accepted = 0;
        for worker in workers {
            accepted += usize::from(worker.join().map_err(|_| "budget worker panicked")?);
        }
        assert_eq!(accepted, 1);
        Ok(())
    }
}
