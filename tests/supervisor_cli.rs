use std::{
    fs::{self, File, OpenOptions},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Result<Self> {
        let root = std::env::temp_dir().join(format!(
            "fightlines-supervisor-cli-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir(&root)?;
        Ok(Self(root))
    }

    fn command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_fightlines-supervisor"));
        command.arg("--root").arg(&self.0);
        command
    }

    fn lock(&self) -> Result<File> {
        Ok(OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.0.join(".supervisor.lock"))?)
    }
}

#[test]
fn interrupted_start_keeps_its_port_reserved_until_a_later_sweep() -> Result {
    let fixture = Fixture::new()?;
    let bin = fixture.0.join("bin");
    fs::create_dir(&bin)?;
    let systemctl = bin.join("systemctl");
    // Interrupt only the supervisor child launched by this test, after its
    // service start is issued. No real systemd or game processes are involved.
    fs::write(
        &systemctl,
        r#"#!/bin/sh
printf '%s\n' "$*" >> "$FIGHTLINES_TEST_HOST_CALLS"
if [ "$1" = enable ]; then
    kill -KILL "$PPID"
fi
"#,
    )?;
    fs::set_permissions(&systemctl, fs::Permissions::from_mode(0o755))?;
    let mut path = vec![bin];
    if let Some(existing) = std::env::var_os("PATH") {
        path.extend(std::env::split_paths(&existing));
    }
    let path = std::env::join_paths(path)?;
    let calls = fixture.0.join("host-calls");
    let mut activation = fixture.command();
    activation
        .args([
            "--routes",
            "unused-routes",
            "--caddy-config",
            "unused-config",
        ])
        .args(["activate", "a", "--port", "8100"])
        .env("PATH", &path)
        .env("FIGHTLINES_TEST_HOST_CALLS", &calls);
    assert!(!activation.output()?.status.success());
    assert_eq!(
        fs::read_to_string(&calls)?.trim(),
        "enable --now fightlines@a.service"
    );
    let reserved = fixture.command().arg("reserved-ports").output()?;
    assert!(reserved.status.success());
    assert_eq!(String::from_utf8(reserved.stdout)?.trim(), "[8100]");
    let available = fixture.command().arg("available-port").output()?;
    assert!(available.status.success());
    assert_eq!(String::from_utf8(available.stdout)?.trim(), "8101");

    let mut recovery = fixture.command();
    recovery
        .args([
            "--routes",
            "unused-routes",
            "--caddy-config",
            "unused-config",
            "sweep",
        ])
        .env("PATH", &path)
        .env("FIGHTLINES_TEST_HOST_CALLS", &calls);
    let recovered = recovery.output()?;
    assert!(
        recovered.status.success(),
        "{}",
        String::from_utf8_lossy(&recovered.stderr)
    );
    assert_eq!(
        fs::read_to_string(&calls)?.lines().last(),
        Some("disable --now fightlines@a.service")
    );
    let available = fixture.command().arg("available-port").output()?;
    assert!(available.status.success());
    assert_eq!(String::from_utf8(available.stdout)?.trim(), "8100");
    Ok(())
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn port_queries_use_the_durable_compatible_registry() -> Result {
    let fixture = Fixture::new()?;
    fs::write(
        fixture.0.join("registry.json"),
        r#"{"current":"b","releases":{"a":{"port":8100,"running":false},"b":{"port":8101,"running":true}}}"#,
    )?;
    let reserved = fixture.command().arg("reserved-ports").output()?;
    assert!(reserved.status.success());
    assert_eq!(String::from_utf8(reserved.stdout)?.trim(), "[8100,8101]");
    let available = fixture.command().arg("available-port").output()?;
    assert!(available.status.success());
    assert_eq!(String::from_utf8(available.stdout)?.trim(), "8102");
    fs::write(fixture.0.join("registry.json"), "invalid")?;
    assert!(
        !fixture
            .command()
            .arg("available-port")
            .output()?
            .status
            .success()
    );
    assert_eq!(
        fs::read_to_string(fixture.0.join("registry.json"))?,
        "invalid"
    );
    Ok(())
}

#[test]
fn independent_invocations_share_the_os_lock() -> Result {
    let fixture = Fixture::new()?;
    let lock = fixture.lock()?;
    lock.lock()?;
    let mut child = fixture
        .command()
        .arg("available-port")
        .stdout(Stdio::piped())
        .spawn()?;
    thread::sleep(Duration::from_millis(50));
    assert!(child.try_wait()?.is_none());
    drop(lock);
    let output = child.wait_with_output()?;
    assert!(output.status.success());
    assert_eq!(String::from_utf8(output.stdout)?.trim(), "8100");
    Ok(())
}
