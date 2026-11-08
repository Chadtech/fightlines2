//! Per-process admission and private operator snapshots. Only the deployment
//! supervisor writes control files; browser activity cannot extend retirement.
use crate::{
    admin::dashboard::{self, AdminEntry},
    app_version,
    deployment_id::DeploymentId,
    lobby_id::LobbyId,
    server_log,
    store::Store,
};
use juniper::{FieldError, FieldResult, GraphQLObject};
use serde::{Deserialize, Serialize};
use std::{
    env, fs, io,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Serialize, Deserialize)]
struct Drain {
    pub started_at_unix_ms: u64,
    pub deadline_unix_ms: u64,
}

pub struct Deployment {
    id: DeploymentId,
    root: PathBuf,
    started_at: u64,
    phase: Mutex<Phase>,
}

enum Phase {
    AcceptingNewGames,
    Draining(Drain),
}

impl Phase {
    fn deadline(&self) -> Option<String> {
        match self {
            Self::AcceptingNewGames => None,
            Self::Draining(drain) => Some(drain.deadline_unix_ms.to_string()),
        }
    }
}

/// A creation transaction keeps retirement from overtaking its publication.
pub struct Admission<'a> {
    _guard: MutexGuard<'a, Phase>,
}

#[derive(Clone, Serialize, Deserialize, GraphQLObject)]
pub struct DeploymentStatus {
    pub id: String,
    pub version: String,
    pub started_at: String,
    pub observed_at: String,
    pub draining: bool,
    pub shutdown_at: Option<String>,
    pub safe_to_stop: bool,
    pub concurrent_games: i32,
    pub waiting_lobbies: i32,
    pub retained_finished_games: i32,
    pub entries: Vec<AdminEntry>,
}

#[derive(GraphQLObject)]
pub struct DeploymentObservation {
    pub id: String,
    pub available: bool,
    pub status: Option<DeploymentStatus>,
}

#[derive(GraphQLObject)]
pub struct PlayerDeploymentStatus {
    pub draining: bool,
    pub shutdown_at: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum ShutdownReminder {
    TenMinutes,
    FiveMinutes,
    OneMinute,
    ThirtySeconds,
}

#[derive(Clone, Copy)]
pub(crate) struct ShutdownNotice {
    pub reminder: ShutdownReminder,
    remaining_seconds: u64,
}

impl ShutdownNotice {
    /// Select only the most urgent reminder when a sweep misses earlier ones.
    pub fn at(deadline_unix_ms: u64, now_unix_ms: u64) -> Option<Self> {
        let remaining_seconds = deadline_unix_ms.saturating_sub(now_unix_ms).div_ceil(1000);
        if remaining_seconds == 0 {
            return None;
        }
        [
            (30, ShutdownReminder::ThirtySeconds),
            (60, ShutdownReminder::OneMinute),
            (300, ShutdownReminder::FiveMinutes),
            (600, ShutdownReminder::TenMinutes),
        ]
        .into_iter()
        .find(|(seconds, _)| remaining_seconds <= *seconds)
        .map(|(_, reminder)| Self {
            reminder,
            remaining_seconds,
        })
    }

    pub fn text(self) -> String {
        let (amount, unit) = if self.remaining_seconds >= 60 {
            (self.remaining_seconds.div_ceil(60), "minute")
        } else {
            (self.remaining_seconds, "second")
        };
        let plural = if amount == 1 { "" } else { "s" };
        format!("this session closes in {amount} {unit}{plural} for a server update.")
    }
}

pub fn unix_ms() -> io::Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_millis()
        .try_into()
        .map_err(io::Error::other)
}

impl Deployment {
    pub fn load(frontend: &Path) -> io::Result<Option<Self>> {
        let Some(id) = env::var_os("FIGHTLINES_DEPLOYMENT_ID") else {
            return Ok(None);
        };
        let id = DeploymentId::try_from(
            id.into_string()
                .map_err(|_| io::Error::other("invalid deployment id"))?,
        )
        .map_err(io::Error::other)?;
        let root = PathBuf::from(
            env::var_os("FIGHTLINES_DEPLOYMENTS_DIR")
                .ok_or_else(|| io::Error::other("FIGHTLINES_DEPLOYMENTS_DIR is required"))?,
        );
        fs::create_dir_all(root.join(id.as_str()))?;
        if root.canonicalize()?.starts_with(frontend.canonicalize()?) {
            return Err(io::Error::other(
                "deployment state must be outside the frontend",
            ));
        }
        Ok(Some(Self {
            id,
            root,
            started_at: unix_ms()?,
            phase: Mutex::new(Phase::AcceptingNewGames),
        }))
    }

    pub fn base_path(&self) -> String {
        format!("/_releases/{}/", self.id)
    }

    /// Publish ownership before returning a new session to a browser. Keep the
    /// record after retirement so old links cannot resolve to a newer release.
    pub fn claim_session(&self, id: &LobbyId) -> io::Result<()> {
        let directory = self.root.join(".session-owners");
        fs::create_dir_all(&directory)?;
        // Linking a fully written file publishes atomically without replacing
        // another release's claim, even in the event of an ID collision.
        let candidate = self.root.join(self.id.as_str()).join(format!("{id}.owner"));
        fs::write(&candidate, serde_json::to_vec(&self.id)?)?;
        let result = fs::hard_link(&candidate, directory.join(id.to_string()));
        fs::remove_file(candidate)?;
        result
    }

    pub(crate) fn routing_root(&self) -> &Path {
        &self.root
    }

    // Hold this guard through publication of a new lobby/match. Snapshotting
    // takes the same lock, so ready-to-stop cannot overtake admitted creation.
    pub fn admission(&self) -> FieldResult<Admission<'_>> {
        let guard = self.control()?;
        match &*guard {
            Phase::AcceptingNewGames => Ok(Admission { _guard: guard }),
            Phase::Draining(_) => Err(draining_error()),
        }
    }

    fn control(&self) -> FieldResult<MutexGuard<'_, Phase>> {
        let mut guard = self
            .phase
            .lock()
            .map_err(|_| server_log::internal_error("deployment state is unavailable."))?;
        if let Phase::AcceptingNewGames = *guard {
            let path = self.root.join(self.id.as_str()).join("drain.json");
            match fs::read(path) {
                Ok(bytes) => {
                    let drain: Drain = serde_json::from_slice(&bytes).map_err(|_| {
                        server_log::internal_error("deployment control is invalid.")
                    })?;
                    if drain.deadline_unix_ms < drain.started_at_unix_ms {
                        return Err(server_log::internal_error(
                            "deployment deadline is invalid.",
                        ));
                    }
                    *guard = Phase::Draining(drain);
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(_) => {
                    return Err(server_log::internal_error(
                        "deployment control is unavailable.",
                    ));
                }
            }
        }
        Ok(guard)
    }

    pub fn player_status(&self) -> FieldResult<PlayerDeploymentStatus> {
        let drain = self.control()?;
        Ok(PlayerDeploymentStatus {
            draining: drain.deadline().is_some(),
            shutdown_at: drain.deadline(),
        })
    }

    pub(crate) fn shutdown_notice(&self, now_unix_ms: u64) -> FieldResult<Option<ShutdownNotice>> {
        Ok(match &*self.control()? {
            Phase::AcceptingNewGames => None,
            Phase::Draining(drain) => ShutdownNotice::at(drain.deadline_unix_ms, now_unix_ms),
        })
    }

    pub fn publish(&self, store: &Store) -> FieldResult<()> {
        let drain = self.control()?;
        let entries = store.admin_entries(Instant::now())?;
        let counts = dashboard::counts(&entries);
        let status = DeploymentStatus {
            id: self.id.to_string(),
            version: app_version::current().into(),
            started_at: self.started_at.to_string(),
            observed_at: unix_ms().map_err(server_log::internal_error)?.to_string(),
            draining: drain.deadline().is_some(),
            shutdown_at: drain.deadline(),
            safe_to_stop: drain.deadline().is_some() && entries.is_empty(),
            concurrent_games: counts.concurrent_games,
            waiting_lobbies: counts.waiting_lobbies,
            retained_finished_games: counts.retained_finished_games,
            entries,
        };
        let directory = self.root.join(self.id.as_str());
        let bytes = serde_json::to_vec(&status).map_err(server_log::internal_error)?;
        fs::write(directory.join("status.tmp"), bytes)
            .and_then(|()| fs::rename(directory.join("status.tmp"), directory.join("status.json")))
            .map_err(server_log::internal_error)
    }

    pub fn observations(&self) -> FieldResult<Vec<DeploymentObservation>> {
        let now = unix_ms().map_err(server_log::internal_error)?;
        let mut observations = Vec::new();
        for entry in fs::read_dir(&self.root).map_err(server_log::internal_error)? {
            let entry = entry.map_err(server_log::internal_error)?;
            if !entry
                .file_type()
                .map_err(server_log::internal_error)?
                .is_dir()
            {
                continue;
            }
            let Ok(id) = DeploymentId::try_from(entry.file_name().to_string_lossy().into_owned())
            else {
                continue;
            };
            // Supervisor maintains this marker; stopped releases remain on disk.
            if !entry.path().join("running").exists() {
                continue;
            }
            let status = fs::read(entry.path().join("status.json"))
                .ok()
                .and_then(|bytes| serde_json::from_slice::<DeploymentStatus>(&bytes).ok())
                .filter(|status| status.id == id.as_str());
            let available = status
                .as_ref()
                .and_then(|status| status.observed_at.parse::<u64>().ok())
                .is_some_and(|observed| observed <= now && now - observed < 15000);
            observations.push(DeploymentObservation {
                id: id.to_string(),
                available,
                status,
            });
        }
        observations.sort_by(|a, b| b.id.cmp(&a.id));
        Ok(observations)
    }
}

pub fn draining_error() -> FieldError {
    FieldError::new(
        "this deployment is draining. continue on the current deployment.",
        juniper::graphql_value!({"code": "DEPLOYMENT_DRAINING"}),
    )
}

/// Read-only discovery includes retired releases and the legacy single-process directory.
pub fn storage_roots(local: &Path, leaf: &str) -> io::Result<Vec<PathBuf>> {
    let Some(root) = env::var_os("FIGHTLINES_DEPLOYMENTS_DIR") else {
        return Ok(vec![local.to_owned()]);
    };
    let root = PathBuf::from(root);
    let mut roots = vec![local.to_owned()];
    for entry in fs::read_dir(&root)? {
        let entry = entry?;
        if entry.file_type()?.is_dir()
            && DeploymentId::try_from(entry.file_name().to_string_lossy().into_owned()).is_ok()
        {
            let path = entry.path().join(leaf);
            if path.is_dir() && !roots.contains(&path) {
                roots.push(path);
            }
        }
    }
    if let Some(parent) = root.parent() {
        let legacy = parent.join(leaf);
        if legacy.is_dir() && !roots.contains(&legacy) {
            roots.push(legacy);
        }
    }
    Ok(roots)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        seed::Seed,
        test_support::{FixtureValue, TestResult},
    };

    fn fixture() -> TestResult<(PathBuf, Store)> {
        let root = env::temp_dir().join(format!(
            "fightlines-deployment-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir_all(root.join("a"))?;
        let deployment = Deployment {
            id: DeploymentId::try_from("a".to_owned())?,
            root: root.clone(),
            started_at: unix_ms()?,
            phase: Mutex::new(Phase::AcceptingNewGames),
        };
        Ok((
            root,
            Store::new(Seed::new([37; 32])).with_deployment(Some(deployment)),
        ))
    }

    #[test]
    fn drain_is_monotonic_and_shares_creation_publication_lock() -> TestResult {
        let (root, store) = fixture()?;
        let deployment = store.deployment.as_ref().fixture()?;
        let admitted = deployment.admission().fixture()?;
        let now = unix_ms()?;
        let drain = serde_json::to_vec(&Drain {
            started_at_unix_ms: now,
            deadline_unix_ms: now + 60000,
        })?;
        fs::write(root.join("a/drain.json"), drain)?;
        // A pending creation still owns the gate, so retirement cannot inspect an
        // empty registry until publication completes.
        assert!(deployment.phase.try_lock().is_err());
        drop(admitted);
        assert!(deployment.admission().is_err());
        deployment.publish(&store).fixture()?;
        let status: DeploymentStatus =
            serde_json::from_slice(&fs::read(root.join("a/status.json"))?)?;
        assert!(status.safe_to_stop);
        fs::remove_file(root.join("a/drain.json"))?;
        assert!(deployment.player_status().fixture()?.draining);
        assert!(deployment.admission().is_err());
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn invalid_control_blocks_admission_and_missing_heartbeat_is_visible() -> TestResult {
        let (root, store) = fixture()?;
        let deployment = store.deployment.as_ref().fixture()?;
        fs::write(root.join("a/drain.json"), "invalid")?;
        assert!(deployment.admission().is_err());
        fs::write(root.join("a/running"), "")?;
        let observations = deployment.observations().fixture()?;
        assert_eq!(observations.len(), 1);
        assert!(!observations.first().fixture()?.available);
        assert!(observations.first().fixture()?.status.is_none());
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn session_claim_is_atomic_and_never_reassigned() -> TestResult {
        let (root, store) = fixture()?;
        let deployment = store.deployment.as_ref().fixture()?;
        let id = LobbyId::from_token("0123456789abcdef0123456789abcdef".into());
        deployment.claim_session(&id)?;
        let owner = root.join(".session-owners").join(id.to_string());
        assert_eq!(
            serde_json::from_slice::<DeploymentId>(&fs::read(&owner)?)?,
            deployment.id
        );
        assert_eq!(
            deployment.claim_session(&id).err().fixture()?.kind(),
            io::ErrorKind::AlreadyExists
        );
        assert!(!root.join("a").join(format!("{id}.owner")).exists());
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn shutdown_reminders_use_the_fixed_deadline_and_current_remaining_time() -> TestResult {
        let deadline = 30_000_000;
        for remaining in [21_600_000, 600_001, 0] {
            assert!(ShutdownNotice::at(deadline, deadline - remaining).is_none());
        }
        for (remaining, reminder, text) in [
            (600_000, ShutdownReminder::TenMinutes, "10 minutes"),
            (599_999, ShutdownReminder::TenMinutes, "10 minutes"),
            (420_000, ShutdownReminder::TenMinutes, "7 minutes"),
            (300_000, ShutdownReminder::FiveMinutes, "5 minutes"),
            (60_000, ShutdownReminder::OneMinute, "1 minute"),
            (30_000, ShutdownReminder::ThirtySeconds, "30 seconds"),
            (15_000, ShutdownReminder::ThirtySeconds, "15 seconds"),
        ] {
            let notice = ShutdownNotice::at(deadline, deadline - remaining).fixture()?;
            assert_eq!(notice.reminder, reminder);
            assert_eq!(
                notice.text(),
                format!("this session closes in {text} for a server update.")
            );
        }
        assert!(ShutdownNotice::at(deadline, deadline + 1).is_none());
        Ok(())
    }

    #[test]
    fn deployment_ids_cannot_escape_their_namespace() {
        for invalid in ["", "../secret", "/a", "A", "a\nb", "a.b"] {
            assert!(DeploymentId::try_from(invalid.to_owned()).is_err());
        }
    }
}
