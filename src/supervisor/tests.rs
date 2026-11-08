use super::*;
use serde_json::json;
use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

static NEXT_FIXTURE_ID: AtomicU64 = AtomicU64::new(0);

struct Fixture {
    root: PathBuf,
}

impl Fixture {
    fn new() -> Result<Self> {
        let root = std::env::temp_dir().join(format!(
            "fightlines-supervisor-{}-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos(),
            NEXT_FIXTURE_ID.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&root)?;
        for name in ["a", "b"] {
            fs::create_dir(root.join(name))?;
            fs::write(root.join(name).join("running"), [])?;
        }
        atomic_json(
            &root.join("registry.json"),
            &json!({"current":"b", "releases":{
                "a":{"port":8100,"running":true,"pid":null},
                "b":{"port":8101,"running":true,"pid":null}
            }}),
        )?;
        fs::write(root.join("routes.caddy"), "previous routes")?;
        Ok(Self { root })
    }

    fn supervisor(&self) -> Result<Supervisor<FakeHost>> {
        Supervisor::load(
            Settings {
                root: self.root.clone(),
                routes: self.root.join("routes.caddy"),
                max_drain: Duration::from_secs(60),
            },
            FakeHost::default(),
        )
    }

    fn supervisor_with_current_c(&self) -> Result<Supervisor<FakeHost>> {
        let mut supervisor = self.supervisor()?;
        fs::create_dir(self.root.join("c"))?;
        supervisor.registry.current = Some(id("c")?);
        supervisor.registry.releases.insert(
            id("c")?,
            Release {
                port: PrivatePort::try_from(8102)?,
                pid: None,
                state: ReleaseState::Running,
            },
        );
        supervisor.persist_registry()?;
        Ok(supervisor)
    }

    fn drain(&self, id: &str, deadline_unix_ms: u64) -> Result {
        atomic_json(
            &self.root.join(id).join("drain.json"),
            &DrainDeadline {
                started_at_unix_ms: 90000,
                deadline_unix_ms,
            },
        )
    }

    fn status(&self, id: &str, observed: u64, empty: bool, deadline: u64) -> Result {
        fs::create_dir_all(self.root.join(id))?;
        atomic_json(
            &self.root.join(id).join("status.json"),
            &json!({"id":id, "observed_at":observed.to_string(), "draining":false,
                "safe_to_stop":empty,"shutdown_at":deadline.to_string()}),
        )
    }

    fn preparing(&self, candidate: Candidate) -> Result {
        let mut registry = Registry::read(&self.root)?;
        registry.releases.insert(
            candidate.id,
            Release {
                port: candidate.port,
                pid: candidate.pid,
                state: ReleaseState::Preparing,
            },
        );
        atomic_json(&self.root.join("registry.json"), &registry)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

struct FakeHost {
    now: u64,
    started: Vec<DeploymentId>,
    discarded: Vec<DeploymentId>,
    stopped: Vec<DeploymentId>,
    fail_reload: bool,
    fail_health: bool,
    fail_discards: BTreeSet<DeploymentId>,
    fail_stops: BTreeSet<DeploymentId>,
}

impl Default for FakeHost {
    fn default() -> Self {
        Self {
            now: 100000,
            started: Vec::new(),
            discarded: Vec::new(),
            stopped: Vec::new(),
            fail_reload: false,
            fail_health: false,
            fail_discards: BTreeSet::new(),
            fail_stops: BTreeSet::new(),
        }
    }
}

impl Host for FakeHost {
    fn now_unix_ms(&self) -> Result<u64> {
        Ok(self.now)
    }

    fn start(&mut self, id: &DeploymentId) -> Result {
        self.started.push(id.clone());
        Ok(())
    }

    fn healthy(&mut self, _: PrivatePort) -> Result {
        if self.fail_health {
            Err("candidate is not healthy".into())
        } else {
            Ok(())
        }
    }

    fn discard_candidate(&mut self, candidate: &Candidate) -> Result {
        if self.fail_discards.contains(&candidate.id) {
            return Err("could not discard candidate".into());
        }
        self.discarded.push(candidate.id.clone());
        Ok(())
    }

    fn stop(&mut self, id: &DeploymentId, _: Option<ProcessId>) -> Result {
        if self.fail_stops.contains(id) {
            return Err("could not stop deployment".into());
        }
        self.stopped.push(id.clone());
        Ok(())
    }

    fn reload(&mut self) -> Result {
        if self.fail_reload {
            Err("Caddy reload failed".into())
        } else {
            Ok(())
        }
    }

    fn wait_for_candidate(&mut self) {}
}

fn id(value: &str) -> Result<DeploymentId> {
    Ok(DeploymentId::try_from(value.to_owned())?)
}

fn candidate(value: &str, port: u16) -> Result<Candidate> {
    Ok(Candidate {
        id: id(value)?,
        port: PrivatePort::try_from(port)?,
        pid: None,
    })
}

fn state(registry: &Registry, name: &str) -> Result<ReleaseState> {
    Ok(registry
        .releases
        .get(&id(name)?)
        .ok_or("missing release fixture")?
        .state
        .clone())
}

#[test]
fn only_fresh_confirmed_empty_deployments_retire_early() -> Result {
    let fixture = Fixture::new()?;
    fixture.drain("a", 110000)?;
    let mut supervisor = fixture.supervisor()?;
    for (observed, empty, deadline) in [
        (80000, true, 110000),
        (100001, true, 110000),
        (100000, false, 110000),
        (100000, true, 120000),
    ] {
        fixture.status("a", observed, empty, deadline)?;
        supervisor.sweep()?;
        assert!(supervisor.host.stopped.is_empty());
    }
    fixture.status("a", 100000, true, 110000)?;
    supervisor.sweep()?;
    assert_eq!(supervisor.host.stopped, vec![id("a")?]);
    assert_eq!(state(&supervisor.registry, "a")?, ReleaseState::Retired);
    assert_eq!(state(&supervisor.registry, "b")?, ReleaseState::Running);
    Ok(())
}

#[test]
fn deadlines_are_fixed_and_enforced_without_status_or_routing() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.sweep()?;
    let drain_path = fixture.root.join("a/drain.json");
    assert_eq!(
        read_json::<DrainDeadline>(&drain_path)?.deadline_unix_ms,
        160000
    );
    supervisor.settings.max_drain = Duration::from_secs(99999);
    supervisor.sweep()?;
    assert_eq!(
        read_json::<DrainDeadline>(&drain_path)?.deadline_unix_ms,
        160000
    );
    supervisor.host.now = 161000;
    supervisor.host.fail_reload = true;
    assert!(supervisor.sweep().is_err());
    assert_eq!(supervisor.host.stopped, vec![id("a")?]);
    assert_eq!(
        state(&Registry::read(&fixture.root)?, "a")?,
        ReleaseState::AwaitingRouteRemoval
    );
    Ok(())
}

#[test]
fn failed_routing_preserves_old_admission_and_previous_config() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.host.fail_reload = true;
    assert!(supervisor.sweep().is_err());
    assert!(!fixture.root.join("a/drain.json").exists());
    assert!(supervisor.host.stopped.is_empty());
    assert_eq!(
        fs::read_to_string(&supervisor.settings.routes)?,
        "previous routes"
    );
    Ok(())
}

#[test]
fn retired_ports_stay_reserved_across_failed_reload_and_restart() -> Result {
    let fixture = Fixture::new()?;
    fixture.drain("a", 99000)?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.host.fail_reload = true;
    assert!(supervisor.sweep().is_err());
    let persisted = Registry::read(&fixture.root)?;
    assert_eq!(state(&persisted, "a")?, ReleaseState::AwaitingRouteRemoval);
    assert_eq!(persisted.available_port()?.number(), 8102);
    let mut restarted = fixture.supervisor()?;
    assert!(restarted.activate(candidate("c", 8100)?).is_err());
    assert!(restarted.host.started.is_empty());
    restarted.sweep()?;
    let confirmed = Registry::read(&fixture.root)?;
    assert_eq!(state(&confirmed, "a")?, ReleaseState::Retired);
    assert_eq!(confirmed.available_port()?.number(), 8100);
    Ok(())
}

#[test]
fn legacy_retired_ports_require_routing_confirmation() -> Result {
    let fixture = Fixture::new()?;
    atomic_json(
        &fixture.root.join("registry.json"),
        &json!({"current":"b", "releases":{
            "a":{"port":8100,"running":false,"pid":null},
            "b":{"port":8101,"running":true,"pid":null}
        }}),
    )?;
    let mut supervisor = fixture.supervisor()?;
    assert_eq!(supervisor.registry.available_port()?.number(), 8102);
    supervisor.sweep()?;
    assert_eq!(
        Registry::read(&fixture.root)?.available_port()?.number(),
        8100
    );
    Ok(())
}

#[test]
fn confirmed_retired_ports_can_host_new_deployments() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    supervisor
        .registry
        .releases
        .get_mut(&id("a")?)
        .ok_or("missing release")?
        .state = ReleaseState::Retired;
    fixture.status("c", 100000, false, 110000)?;
    supervisor.activate(candidate("c", 8100)?)?;
    assert_eq!(supervisor.host.started, vec![id("c")?]);
    let routes = supervisor.registry.routes()?;
    assert!(!routes.contains("/_releases/a/*"));
    assert!(routes.contains("/_releases/c/*"));
    assert_eq!(
        state(&Registry::read(&fixture.root)?, "c")?,
        ReleaseState::Running
    );
    Ok(())
}

fn retain_only_a(supervisor: &mut Supervisor<FakeHost>) -> Result {
    supervisor.registry.current = Some(id("a")?);
    supervisor.registry.releases.remove(&id("b")?);
    supervisor.persist_registry()
}

#[test]
fn healthy_candidate_survives_uncertain_cutover_reply() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    retain_only_a(&mut supervisor)?;
    fixture.status("b", 100000, false, 110000)?;
    supervisor.host.fail_reload = true;
    assert!(supervisor.activate(candidate("b", 8101)?).is_err());
    let persisted = Registry::read(&fixture.root)?;
    assert_eq!(persisted.current, Some(id("b")?));
    assert_eq!(state(&persisted, "b")?, ReleaseState::Running);
    assert!(supervisor.host.discarded.is_empty());
    assert!(!fixture.root.join("a/drain.json").exists());
    Ok(())
}

#[test]
fn unhealthy_candidate_does_not_change_current_release() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    retain_only_a(&mut supervisor)?;
    supervisor.host.fail_health = true;
    assert!(supervisor.activate(candidate("b", 8101)?).is_err());
    assert_eq!(Registry::read(&fixture.root)?.current, Some(id("a")?));
    assert_eq!(supervisor.host.discarded, vec![id("b")?]);
    assert_eq!(
        state(&Registry::read(&fixture.root)?, "b")?,
        ReleaseState::Retired
    );
    assert!(supervisor.host.stopped.is_empty());
    assert!(!fixture.root.join("a/drain.json").exists());
    Ok(())
}

#[test]
fn preparing_ports_stay_reserved_until_recovery_succeeds() -> Result {
    let fixture = Fixture::new()?;
    fixture.preparing(candidate("c", 8102)?)?;
    let mut supervisor = fixture.supervisor()?;
    assert_eq!(supervisor.registry.available_port()?.number(), 8103);
    assert!(!supervisor.registry.routes()?.contains("/_releases/c/*"));
    supervisor.host.fail_discards.insert(id("c")?);
    assert!(supervisor.sweep().is_err());
    let pending = Registry::read(&fixture.root)?;
    assert_eq!(state(&pending, "c")?, ReleaseState::Preparing);
    assert_eq!(pending.available_port()?.number(), 8103);

    let mut restarted = fixture.supervisor()?;
    restarted.sweep()?;
    assert_eq!(restarted.host.discarded, vec![id("c")?]);
    let recovered = Registry::read(&fixture.root)?;
    assert_eq!(recovered.current, Some(id("b")?));
    assert_eq!(state(&recovered, "c")?, ReleaseState::Retired);
    assert_eq!(recovered.available_port()?.number(), 8102);
    assert!(restarted.host.stopped.is_empty());
    Ok(())
}

#[test]
fn activation_recovers_an_interrupted_candidate_before_starting_a_fresh_release() -> Result {
    let fixture = Fixture::new()?;
    fixture.preparing(candidate("c", 8102)?)?;
    fixture.status("d", 100000, false, 110000)?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.activate(candidate("d", 8103)?)?;
    assert_eq!(supervisor.host.discarded, vec![id("c")?]);
    assert_eq!(supervisor.host.started, vec![id("d")?]);
    let recovered = Registry::read(&fixture.root)?;
    assert_eq!(recovered.current, Some(id("d")?));
    assert_eq!(state(&recovered, "c")?, ReleaseState::Retired);
    assert_eq!(state(&recovered, "d")?, ReleaseState::Running);
    assert_eq!(recovered.available_port()?.number(), 8102);
    Ok(())
}

#[test]
fn candidate_cleanup_failure_does_not_extend_an_existing_drain_deadline() -> Result {
    let fixture = Fixture::new()?;
    fixture.preparing(candidate("c", 8102)?)?;
    fixture.drain("a", 99000)?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.host.fail_discards.insert(id("c")?);
    assert!(supervisor.sweep().is_err());
    assert_eq!(supervisor.host.stopped, vec![id("a")?]);
    let registry = Registry::read(&fixture.root)?;
    assert_eq!(state(&registry, "a")?, ReleaseState::Retired);
    assert_eq!(state(&registry, "c")?, ReleaseState::Preparing);
    assert!(
        registry
            .reserved_ports()
            .contains(&PrivatePort::try_from(8102)?)
    );
    Ok(())
}

#[test]
fn failed_first_activation_releases_its_port_after_cleanup() -> Result {
    let fixture = Fixture::new()?;
    atomic_json(&fixture.root.join("registry.json"), &Registry::default())?;
    let mut supervisor = fixture.supervisor()?;
    supervisor.host.fail_health = true;
    assert!(supervisor.activate(candidate("c", 8100)?).is_err());
    let failed = Registry::read(&fixture.root)?;
    assert_eq!(failed.current, None);
    assert_eq!(state(&failed, "c")?, ReleaseState::Retired);
    assert_eq!(failed.available_port()?.number(), 8100);
    assert_eq!(supervisor.host.discarded, vec![id("c")?]);
    assert_eq!(
        fs::read_to_string(&supervisor.settings.routes)?,
        "previous routes"
    );

    fixture.status("d", 100000, false, 110000)?;
    let mut restarted = fixture.supervisor()?;
    restarted.activate(candidate("d", 8100)?)?;
    assert_eq!(Registry::read(&fixture.root)?.current, Some(id("d")?));
    Ok(())
}

#[test]
fn candidate_requires_its_own_fresh_accepting_status() -> Result {
    for invalid in [
        json!({"id":"b", "observed_at":"100000"}),
        json!({"id":"b", "observed_at":"80000", "draining":false}),
        json!({"id":"b", "observed_at":"100001", "draining":false}),
        json!({"id":"a", "observed_at":"100000", "draining":false}),
        json!({"id":"b", "observed_at":"100000", "draining":true}),
    ] {
        let fixture = Fixture::new()?;
        let mut supervisor = fixture.supervisor()?;
        retain_only_a(&mut supervisor)?;
        atomic_json(&fixture.root.join("b/status.json"), &invalid)?;
        assert!(supervisor.activate(candidate("b", 8101)?).is_err());
        assert_eq!(Registry::read(&fixture.root)?.current, Some(id("a")?));
        assert_eq!(supervisor.host.discarded, vec![id("b")?]);
        assert!(!fixture.root.join("a/drain.json").exists());
    }
    Ok(())
}

#[test]
fn failed_stops_preserve_running_state_and_already_stopped_ports() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor_with_current_c()?;
    fixture.drain("a", 99000)?;
    fixture.drain("b", 99000)?;
    supervisor.host.fail_stops.insert(id("b")?);
    supervisor.host.fail_reload = true;
    let error = supervisor.sweep().err().ok_or("sweep should fail")?;
    assert!(error.to_string().contains("deployment b"));
    assert!(error.to_string().contains("Caddy reload failed"));
    let persisted = Registry::read(&fixture.root)?;
    assert_eq!(state(&persisted, "a")?, ReleaseState::AwaitingRouteRemoval);
    assert_eq!(state(&persisted, "b")?, ReleaseState::Running);
    assert_eq!(persisted.available_port()?.number(), 8103);
    Ok(())
}

#[test]
fn failed_stop_does_not_block_other_expired_releases() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor_with_current_c()?;
    fixture.drain("a", 99000)?;
    fixture.drain("b", 99000)?;
    supervisor.host.fail_stops.insert(id("a")?);
    let error = supervisor
        .sweep()
        .err()
        .ok_or("sweep should report the failed stop")?;
    assert!(error.to_string().contains("deployment a"));
    assert_eq!(supervisor.host.stopped, vec![id("b")?]);
    let persisted = Registry::read(&fixture.root)?;
    assert_eq!(state(&persisted, "a")?, ReleaseState::Running);
    assert_eq!(state(&persisted, "b")?, ReleaseState::Retired);
    assert_eq!(state(&persisted, "c")?, ReleaseState::Running);
    assert_eq!(persisted.available_port()?.number(), 8101);

    supervisor.host.fail_stops.clear();
    supervisor.sweep()?;
    assert_eq!(supervisor.host.stopped, vec![id("b")?, id("a")?]);
    assert_eq!(
        state(&Registry::read(&fixture.root)?, "a")?,
        ReleaseState::Retired
    );
    Ok(())
}

#[test]
fn routing_tombstones_and_private_resolver_survive_retirement() -> Result {
    let fixture = Fixture::new()?;
    let mut supervisor = fixture.supervisor()?;
    supervisor
        .registry
        .releases
        .get_mut(&id("a")?)
        .ok_or("missing release")?
        .state = ReleaseState::AwaitingRouteRemoval;
    let routes = supervisor.registry.routes()?;
    assert!(!routes.contains("/_releases/a/*"));
    assert!(routes.contains("respond \"this session has ended\" 410"));
    assert!(!routes.contains("redir"));
    assert!(routes.contains("forward_auth 127.0.0.1:8101"));
    assert!(routes.contains("request_header -X-Fightlines-Upstream"));
    assert!(routes.contains("reverse_proxy {http.request.header.X-Fightlines-Upstream}"));
    assert!(
        routes.find("@resolver").ok_or("missing resolver")?
            < routes.find("handle_path").ok_or("missing release route")?
    );
    Ok(())
}

#[test]
fn controls_remain_readable_and_invalid_registries_fail_closed() -> Result {
    let fixture = Fixture::new()?;
    assert_eq!(
        fs::metadata(fixture.root.join("registry.json"))?
            .permissions()
            .mode()
            & 0o777,
        0o644
    );
    for invalid in [
        json!({"current":"../secret","releases":{}}),
        json!({"current":"a","releases":{"a":{"port":80,"running":true}}}),
        json!({"current":"a","releases":{"a":{"port":8100,"running":false}}}),
        json!({"current":null,"releases":{"a":{"port":8100,"running":true}}}),
        json!({"current":null,"releases":{"a":{"port":8100,"running":true,"preparing":true}}}),
        json!({"current":null,"releases":{"a":{"port":8100,"running":false,"preparing":true,"port_reusable":true}}}),
    ] {
        atomic_json(&fixture.root.join("registry.json"), &invalid)?;
        assert!(Registry::read(&fixture.root).is_err());
    }
    Ok(())
}
