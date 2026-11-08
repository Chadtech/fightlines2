//! Owns the durable registry, drain deadlines, routing, and release transitions.
use crate::{Result, deployment_id::DeploymentId};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File, OpenOptions, Permissions},
    io::{self, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "u16", into = "u16")]
pub(crate) struct PrivatePort(u16);

impl PrivatePort {
    pub(crate) fn number(self) -> u16 {
        self.0
    }
}

impl TryFrom<u16> for PrivatePort {
    type Error = &'static str;

    fn try_from(value: u16) -> std::result::Result<Self, Self::Error> {
        if value < 1024 {
            return Err("private port must be between 1024 and 65535");
        }
        Ok(Self(value))
    }
}

impl From<PrivatePort> for u16 {
    fn from(value: PrivatePort) -> Self {
        value.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "u32", into = "u32")]
pub(crate) struct ProcessId(u32);

impl ProcessId {
    pub(crate) fn number(self) -> u32 {
        self.0
    }
}

impl TryFrom<u32> for ProcessId {
    type Error = &'static str;

    fn try_from(value: u32) -> std::result::Result<Self, Self::Error> {
        if value <= 1 || value > i32::MAX as u32 {
            return Err("local activation requires a child process id between 2 and 2147483647");
        }
        Ok(Self(value))
    }
}

impl From<ProcessId> for u32 {
    fn from(value: ProcessId) -> Self {
        value.0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum ReleaseState {
    Preparing,
    Running,
    AwaitingRouteRemoval,
    Retired,
}

/// Keep the server-facing lifecycle flags and read older registry entries.
#[derive(Clone, Serialize, Deserialize)]
struct StoredRelease {
    port: PrivatePort,
    pid: Option<ProcessId>,
    running: bool,
    #[serde(default)]
    port_reusable: bool,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    preparing: bool,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(try_from = "StoredRelease", into = "StoredRelease")]
struct Release {
    port: PrivatePort,
    pid: Option<ProcessId>,
    state: ReleaseState,
}

impl TryFrom<StoredRelease> for Release {
    type Error = &'static str;

    fn try_from(stored: StoredRelease) -> std::result::Result<Self, Self::Error> {
        let state = match (stored.preparing, stored.running, stored.port_reusable) {
            (true, false, false) => ReleaseState::Preparing,
            (false, true, false) => ReleaseState::Running,
            (false, false, true) => ReleaseState::Retired,
            (false, false, false) => ReleaseState::AwaitingRouteRemoval,
            _ => return Err("release lifecycle flags are inconsistent"),
        };
        Ok(Self {
            port: stored.port,
            pid: stored.pid,
            state,
        })
    }
}

impl From<Release> for StoredRelease {
    fn from(release: Release) -> Self {
        Self {
            port: release.port,
            pid: release.pid,
            running: release.state == ReleaseState::Running,
            port_reusable: release.state == ReleaseState::Retired,
            preparing: release.state == ReleaseState::Preparing,
        }
    }
}

#[derive(Clone, Default, Serialize, Deserialize)]
pub(crate) struct Registry {
    current: Option<DeploymentId>,
    releases: BTreeMap<DeploymentId, Release>,
}

impl Registry {
    pub(crate) fn read(root: &Path) -> Result<Self> {
        let registry: Self = match fs::read(root.join("registry.json")) {
            Ok(bytes) => serde_json::from_slice(&bytes)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => Self::default(),
            Err(error) => return Err(error.into()),
        };
        match &registry.current {
            Some(current) => match registry.releases.get(current) {
                Some(release) if release.state == ReleaseState::Running => {}
                _ => return Err("current deployment has no running registered release".into()),
            },
            None => {
                let requires_current =
                    registry
                        .releases
                        .values()
                        .any(|release| match release.state {
                            ReleaseState::Preparing | ReleaseState::Retired => false,
                            ReleaseState::Running | ReleaseState::AwaitingRouteRemoval => true,
                        });
                if requires_current {
                    return Err("registered releases require a current deployment".into());
                }
            }
        }
        Ok(registry)
    }

    pub(crate) fn reserved_ports(&self) -> BTreeSet<PrivatePort> {
        self.releases
            .values()
            .filter(|release| release.state != ReleaseState::Retired)
            .map(|release| release.port)
            .collect()
    }

    pub(crate) fn available_port(&self) -> Result<PrivatePort> {
        let reserved = self.reserved_ports();
        (8100..9000)
            .map(PrivatePort)
            .find(|port| !reserved.contains(port))
            .ok_or_else(|| "no deployment ports are available".into())
    }

    fn routes(&self) -> Result<String> {
        let current = self.current.as_ref().ok_or("no current deployment")?;
        let release = self
            .releases
            .get(current)
            .ok_or("current deployment is not registered")?;
        if release.state != ReleaseState::Running {
            return Err("current deployment is not running".into());
        }
        // Hide the resolver before any release prefix can proxy it.
        let mut routes = String::from(
            "route {
    @resolver path_regexp ^(/_releases/[^/]+)?/_routing(/|$)
    handle @resolver {
        respond 404
    }
",
        );
        for (id, release) in &self.releases {
            if release.state == ReleaseState::Running {
                routes.push_str(&format!(
                    "    handle_path /_releases/{id}/* {{
        reverse_proxy 127.0.0.1:{} {{
            header_up -X-Forwarded-Uri
        }}
    }}
",
                    release.port.number()
                ));
            }
        }
        routes.push_str(&format!(
            "    handle /_releases/* {{
        respond \"this session has ended\" 410
    }}
    @session path /lobby/* /game/*
    handle @session {{
        route {{
            request_header -X-Fightlines-Upstream
            forward_auth 127.0.0.1:{} {{
                uri /_routing
                copy_headers X-Fightlines-Upstream
            }}
            reverse_proxy {{http.request.header.X-Fightlines-Upstream}} {{
                header_up -X-Forwarded-Uri
            }}
        }}
    }}
    handle {{
        reverse_proxy 127.0.0.1:{} {{
            header_up -X-Forwarded-Uri
        }}
    }}
}}
",
            release.port.number(),
            release.port.number()
        ));
        Ok(routes)
    }
}

#[derive(Clone, Serialize, Deserialize)]
struct DrainDeadline {
    started_at_unix_ms: u64,
    deadline_unix_ms: u64,
}

#[derive(Deserialize)]
struct Status {
    id: DeploymentId,
    observed_at: String,
    draining: bool,
    #[serde(default)]
    safe_to_stop: bool,
    shutdown_at: Option<String>,
}

impl Status {
    fn fresh(&self, id: &DeploymentId, now_unix_ms: u64) -> bool {
        let age = self
            .observed_at
            .parse::<u64>()
            .ok()
            .and_then(|observed| now_unix_ms.checked_sub(observed));
        self.id == *id && age.is_some_and(|age| age < 15000)
    }
}

pub(crate) struct Candidate {
    pub(crate) id: DeploymentId,
    pub(crate) port: PrivatePort,
    pub(crate) pid: Option<ProcessId>,
}

pub(crate) struct Settings {
    pub(crate) root: PathBuf,
    pub(crate) routes: PathBuf,
    pub(crate) max_drain: Duration,
}

pub(crate) trait Host {
    fn now_unix_ms(&self) -> Result<u64>;
    fn start(&mut self, id: &DeploymentId) -> Result;
    fn healthy(&mut self, port: PrivatePort) -> Result;
    fn discard_candidate(&mut self, candidate: &Candidate) -> Result;
    fn stop(&mut self, id: &DeploymentId, pid: Option<ProcessId>) -> Result;
    fn reload(&mut self) -> Result;
    fn wait_for_candidate(&mut self) {
        thread::sleep(Duration::from_millis(200));
    }
}

pub(crate) struct Supervisor<H> {
    settings: Settings,
    registry: Registry,
    host: H,
}

impl<H: Host> Supervisor<H> {
    pub(crate) fn load(settings: Settings, host: H) -> Result<Self> {
        let registry = Registry::read(&settings.root)?;
        Ok(Self {
            settings,
            registry,
            host,
        })
    }

    fn persist_registry(&self) -> Result {
        atomic_json(&self.settings.root.join("registry.json"), &self.registry)
    }

    fn reconcile_routes(&mut self) -> Result {
        let routes = self.registry.routes()?;
        let previous = match fs::read(&self.settings.routes) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(error) => return Err(error.into()),
        };
        atomic_write(&self.settings.routes, routes.as_bytes())?;
        if let Err(error) = self.host.reload() {
            atomic_write(&self.settings.routes, &previous)?;
            return Err(error);
        }
        let mut changed = false;
        for release in self.registry.releases.values_mut() {
            if release.state == ReleaseState::AwaitingRouteRemoval {
                release.state = ReleaseState::Retired;
                changed = true;
            }
        }
        if changed {
            // A stopped port is reusable only after Caddy confirms removal.
            self.persist_registry()?;
        }
        Ok(())
    }

    fn prepare_candidate(&mut self, candidate: &Candidate) -> Result {
        self.host.start(&candidate.id)?;
        for attempt in 0..30 {
            let result = self.host.healthy(candidate.port).and_then(|()| {
                let status: Status = read_json(
                    &self
                        .settings
                        .root
                        .join(candidate.id.as_str())
                        .join("status.json"),
                )?;
                if !status.fresh(&candidate.id, self.host.now_unix_ms()?) || status.draining {
                    return Err("candidate has no fresh accepting deployment status".into());
                }
                Ok(())
            });
            match result {
                Ok(()) => return Ok(()),
                Err(error) if attempt == 29 => return Err(error),
                Err(_) => self.host.wait_for_candidate(),
            }
        }
        Err("candidate readiness was not confirmed".into())
    }

    /// Preparing releases have never been routed, so stopping them cannot
    /// interrupt an admitted session. Keep their ports reserved until cleanup
    /// succeeds, including when the previous supervisor was interrupted.
    fn discard_preparing(&mut self) -> Result {
        let candidates: Vec<Candidate> = self
            .registry
            .releases
            .iter()
            .filter(|(_, release)| release.state == ReleaseState::Preparing)
            .map(|(id, release)| Candidate {
                id: id.clone(),
                port: release.port,
                pid: release.pid,
            })
            .collect();
        for candidate in candidates {
            self.host.discard_candidate(&candidate)?;
            match fs::remove_file(
                self.settings
                    .root
                    .join(candidate.id.as_str())
                    .join("running"),
            ) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
            self.registry
                .releases
                .get_mut(&candidate.id)
                .ok_or("preparing deployment disappeared during cleanup")?
                .state = ReleaseState::Retired;
            self.persist_registry()?;
        }
        Ok(())
    }

    pub(crate) fn activate(&mut self, candidate: Candidate) -> Result {
        self.discard_preparing()?;
        if self.registry.releases.contains_key(&candidate.id) {
            return Err("deployment ids cannot be reused".into());
        }
        if self.registry.reserved_ports().contains(&candidate.port) {
            return Err("port is reserved by a deployment or pending route removal".into());
        }
        let directory = self.settings.root.join(candidate.id.as_str());
        fs::create_dir_all(&directory)?;
        if directory.join("drain.json").exists() {
            return Err("a retired deployment cannot be reactivated".into());
        }
        // Reserve the identity and port durably before the host can start a
        // service. A later invocation can safely clean up this unrouted state.
        self.registry.releases.insert(
            candidate.id.clone(),
            Release {
                port: candidate.port,
                pid: candidate.pid,
                state: ReleaseState::Preparing,
            },
        );
        self.persist_registry()?;
        let prepared = self.prepare_candidate(&candidate).and_then(|()| {
            File::create(directory.join("running"))?;
            Ok(())
        });
        if let Err(error) = prepared {
            if let Err(cleanup) = self.discard_preparing() {
                return Err(format!("candidate failed: {error}; cleanup failed: {cleanup}").into());
            }
            return Err(error);
        }
        self.registry
            .releases
            .get_mut(&candidate.id)
            .ok_or("prepared deployment disappeared before activation")?
            .state = ReleaseState::Running;
        self.registry.current = Some(candidate.id);
        // Persist intent before routing. Once cutover might have succeeded, keep
        // the candidate alive because it could already own admitted sessions.
        self.persist_registry()?;
        self.sweep()
    }

    pub(crate) fn sweep(&mut self) -> Result {
        let preparing_error = self.discard_preparing().err();
        let now_unix_ms = self.host.now_unix_ms()?;
        let routing_error = if self.registry.current.is_some() {
            self.reconcile_routes().err()
        } else {
            None
        };
        let candidates: Vec<DeploymentId> = self
            .registry
            .releases
            .iter()
            .filter(|(id, release)| {
                release.state == ReleaseState::Running
                    && Some(*id) != self.registry.current.as_ref()
            })
            .map(|(id, _)| id.clone())
            .collect();
        let mut retired = false;
        let mut errors: Vec<String> = preparing_error
            .into_iter()
            .map(|error| error.to_string())
            .collect();
        for id in candidates {
            let directory = self.settings.root.join(id.as_str());
            let drain_path = directory.join("drain.json");
            let drain: DrainDeadline = match fs::read(&drain_path) {
                Ok(bytes) => serde_json::from_slice(&bytes)?,
                Err(error) if error.kind() == io::ErrorKind::NotFound => {
                    if routing_error.is_some() {
                        continue;
                    }
                    let duration_ms: u64 = self.settings.max_drain.as_millis().try_into()?;
                    let deadline_unix_ms = now_unix_ms
                        .checked_add(duration_ms)
                        .ok_or("drain deadline exceeds supported time range")?;
                    let drain = DrainDeadline {
                        started_at_unix_ms: now_unix_ms,
                        deadline_unix_ms,
                    };
                    atomic_json(&drain_path, &drain)?;
                    drain
                }
                Err(error) => return Err(error.into()),
            };
            if drain.deadline_unix_ms < drain.started_at_unix_ms {
                return Err(format!("deployment {id} has an invalid drain deadline").into());
            }
            let empty = read_json::<Status>(&directory.join("status.json"))
                .ok()
                .is_some_and(|status| {
                    status.fresh(&id, now_unix_ms)
                        && status.safe_to_stop
                        && status.shutdown_at == Some(drain.deadline_unix_ms.to_string())
                });
            if empty || now_unix_ms >= drain.deadline_unix_ms {
                let release = self
                    .registry
                    .releases
                    .get_mut(&id)
                    .ok_or("deployment disappeared during retirement")?;
                if let Err(error) = self.host.stop(&id, release.pid) {
                    errors.push(format!("could not stop deployment {id}: {error}"));
                    continue;
                }
                release.state = ReleaseState::AwaitingRouteRemoval;
                // Persist each stop before another fallible operation; its port
                // stays reserved across errors and supervisor restarts.
                self.persist_registry()?;
                match fs::remove_file(directory.join("running")) {
                    Ok(()) => {}
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
                retired = true;
            }
        }
        if retired {
            if let Err(error) = self.reconcile_routes() {
                errors.push(error.to_string());
            }
        } else if let Some(error) = routing_error {
            errors.push(error.to_string());
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.join("; ").into())
        }
    }
}

pub(crate) fn lock(root: &Path) -> Result<File> {
    fs::create_dir_all(root)?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(root.join(".supervisor.lock"))?;
    file.lock()?;
    Ok(file)
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

fn atomic_json(path: &Path, value: &impl Serialize) -> Result {
    let mut bytes = serde_json::to_vec(value)?;
    bytes.push(b'\n');
    atomic_write(path, &bytes)
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result {
    let parent = path
        .parent()
        .ok_or("control file has no parent directory")?;
    fs::create_dir_all(parent)?;
    let temporary = path.with_extension("tmp");
    let mut file = File::create(&temporary)?;
    file.write_all(bytes)?;
    file.set_permissions(Permissions::from_mode(0o644))?;
    file.sync_all()?;
    fs::rename(&temporary, path)?;
    File::open(parent)?.sync_all()?;
    Ok(())
}

#[cfg(test)]
#[path = "tests.rs"]
mod tests;
