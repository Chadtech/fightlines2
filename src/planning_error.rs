//! Browser planning invariant reports for the authenticated Admin dashboard.
use crate::{
    app_version, deployment, game,
    graphql::Context,
    lobby_id::LobbyId,
    server_log,
    storage_budget::{self, Budget, Capacity, Usage},
};
use juniper::{FieldError, FieldResult, GraphQLInputObject, GraphQLObject};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

const DIRECTORY: &str = "planning-errors";
const PAGE_SIZE: i32 = 20;
const MAX_BATCH_SIZE: usize = 8;
static NEXT_REPORT: AtomicU64 = AtomicU64::new(0);

#[derive(GraphQLInputObject)]
pub struct PlanningErrorBatchInput {
    game_id: String,
    client_version: String,
    errors: Vec<PlanningErrorInput>,
}

#[derive(GraphQLInputObject)]
struct PlanningErrorInput {
    turn_number: i32,
    details: String,
}

#[derive(Deserialize, Serialize)]
struct Report {
    game_id: LobbyId,
    turn_number: i32,
    client_version: u64,
    details: String,
    server_version: String,
    received_at_unix_ms: u128,
}

#[derive(GraphQLObject)]
struct PlanningErrorRecord {
    game_id: String,
    turn_number: i32,
    client_version: String,
    details: String,
    server_version: String,
    received_at: String,
}

#[derive(GraphQLObject)]
pub struct PlanningErrorPage {
    reports: Vec<PlanningErrorRecord>,
    unreadable: i32,
    total: i32,
    next_offset: Option<i32>,
}

pub struct Directory {
    path: PathBuf,
    budget: Budget,
}

impl Directory {
    // The server log root was already opened and checked against the frontend.
    pub fn open(log_root: &Path, frontend: &Path) -> io::Result<Self> {
        let path = log_root.canonicalize()?.join(DIRECTORY);
        let mut builder = fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        builder.create(&path)?;
        if fs::symlink_metadata(&path)?.file_type().is_symlink()
            || path.canonicalize()?.starts_with(frontend.canonicalize()?)
        {
            return Err(io::Error::other(
                "planning errors require a private directory",
            ));
        }
        let used = storage_budget::scan(&path, &|_, metadata| Ok(Usage::file(metadata.len())))?;
        Ok(Self {
            path,
            budget: Budget::new(
                Capacity {
                    bytes: 32 * 1024 * 1024,
                    entries: 4096,
                },
                used,
            ),
        })
    }

    fn save(&self, report: &Report, timestamp_ns: u128) -> io::Result<()> {
        let id = format!(
            "{timestamp_ns:020}-{}-{}",
            std::process::id(),
            NEXT_REPORT.fetch_add(1, Ordering::Relaxed)
        );
        let pending = self.path.join(format!(".{id}.pending"));
        let published = self.path.join(format!("{id}.json"));
        let bytes = serde_json::to_vec(report)?;
        let reservation = self.budget.reserve(Usage::file(bytes.len() as u64))?;
        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&pending)?;
        let written = file
            .write_all(&bytes)
            .and_then(|()| file.sync_all())
            .and_then(|()| fs::hard_link(&pending, &published))
            .and_then(|()| self.sync_publication(&published));
        drop(file);
        if let Err(error) = fs::remove_file(&pending) {
            tracing::error!(event = "planning_error_cleanup_failed", %error);
        }
        if published.exists() || pending.exists() {
            reservation.retain();
        }
        written
    }

    fn sync_publication(&self, published: &Path) -> io::Result<()> {
        #[cfg(unix)]
        if let Err(error) = fs::File::open(&self.path).and_then(|directory| directory.sync_all()) {
            if let Err(cleanup) = fs::remove_file(published) {
                tracing::error!(event = "planning_error_rollback_failed", error = %cleanup);
            }
            return Err(error);
        }
        Ok(())
    }

    fn list(&self, offset: i32) -> FieldResult<PlanningErrorPage> {
        if offset < 0 {
            return Err("planning error offset must be nonnegative.".into());
        }
        self.read_page(offset).map_err(|error| {
            tracing::error!(event = "planning_errors_list_failed", %error);
            server_log::internal_error("could not list planning errors.")
        })
    }

    fn read_page(&self, offset: i32) -> io::Result<PlanningErrorPage> {
        let log_root = self
            .path
            .parent()
            .ok_or_else(|| io::Error::other("missing log root"))?;
        let mut files = Vec::new();
        for root in deployment::storage_roots(log_root, "server-logs")? {
            let path = root.join(DIRECTORY);
            match fs::symlink_metadata(&path) {
                Ok(metadata) if metadata.is_dir() => {}
                Ok(_) => continue,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            }
            for entry in fs::read_dir(path)? {
                let entry = entry?;
                if entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "json")
                {
                    files.push(entry);
                }
            }
        }
        files.sort_by_key(|entry| std::cmp::Reverse(entry.file_name()));
        let total = files.len() as i32;
        let mut reports = Vec::new();
        let mut unreadable = 0;
        for entry in files
            .into_iter()
            .skip(offset as usize)
            .take(PAGE_SIZE as usize)
        {
            let path = entry.path();
            let report = fs::symlink_metadata(&path).and_then(|metadata| {
                if !metadata.is_file() || metadata.len() > 4096 {
                    return Err(io::Error::other("invalid planning error file"));
                }
                serde_json::from_slice::<Report>(&fs::read(path)?).map_err(io::Error::other)
            });
            match report {
                Ok(report) => reports.push(PlanningErrorRecord {
                    game_id: report.game_id.to_string(),
                    turn_number: report.turn_number,
                    client_version: report.client_version.to_string(),
                    details: report.details,
                    server_version: report.server_version,
                    received_at: report.received_at_unix_ms.to_string(),
                }),
                Err(_) => unreadable += 1,
            }
        }
        let next = offset.saturating_add(PAGE_SIZE);
        Ok(PlanningErrorPage {
            reports,
            unreadable,
            total,
            next_offset: (next < total).then_some(next),
        })
    }
}

pub fn list(context: &Context, offset: i32) -> FieldResult<PlanningErrorPage> {
    context.require_admin()?;
    directory(context)?.list(offset)
}

fn directory(context: &Context) -> FieldResult<&Directory> {
    context
        .planning_errors
        .as_deref()
        .ok_or_else(|| server_log::internal_error("planning error storage is unavailable."))
}

pub fn submit(context: &Context, input: PlanningErrorBatchInput) -> FieldResult<bool> {
    if input.game_id.len() != 32
        || !input
            .game_id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        || input.errors.is_empty()
        || input.errors.len() > MAX_BATCH_SIZE
        || input.errors.iter().any(|error| {
            let details = error.details.trim();
            error.turn_number < 1
                || details.is_empty()
                || details.len() > 512
                || details.chars().any(char::is_control)
        })
    {
        return Err("invalid planning error report.".into());
    }
    let client_version = input
        .client_version
        .parse::<u64>()
        .ok()
        .filter(|version| *version > 0)
        .ok_or_else(|| FieldError::from("invalid planning error client version."))?;
    let game_id = LobbyId::from_token(input.game_id);
    game::require_player_view(context, &game_id)?;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| {
            tracing::error!(event = "planning_error_clock_failed", %error);
            server_log::internal_error("could not timestamp planning error.")
        })?;
    let directory = directory(context)?;
    for error in input.errors {
        let report = Report {
            game_id: game_id.clone(),
            turn_number: error.turn_number,
            client_version,
            details: error.details.trim().to_owned(),
            server_version: app_version::current().to_owned(),
            received_at_unix_ms: now.as_millis(),
        };
        directory.save(&report, now.as_nanos()).map_err(|error| {
            if error.kind() == io::ErrorKind::StorageFull {
                return storage_budget::full("planning error storage is full.");
            }
            tracing::error!(event = "planning_error_save_failed", %error);
            server_log::internal_error("could not save planning error.")
        })?;
    }
    Ok(true)
}
