//! Host-side process operations; lifecycle policy remains in the controller.
use crate::{
    Result,
    control::{Candidate, Host, PrivatePort, ProcessId},
    deployment_id::DeploymentId,
};
use serde::Deserialize;
use std::{
    io,
    net::TcpListener,
    path::PathBuf,
    process::{Command, Output, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum ProcessMode {
    Systemd,
    Local,
}

pub(crate) struct Settings {
    pub(crate) caddy: PathBuf,
    pub(crate) caddy_config: PathBuf,
    pub(crate) processes: ProcessMode,
}

pub(crate) struct SystemHost {
    settings: Settings,
}

impl SystemHost {
    pub(crate) fn new(settings: Settings) -> Self {
        Self { settings }
    }

    fn systemctl(&self, action: &str, id: &DeploymentId) -> Result {
        run_command(
            Command::new("systemctl").args([action, "--now", &format!("fightlines@{id}.service")]),
            Duration::from_secs(30),
        )?;
        Ok(())
    }
}

impl Host for SystemHost {
    fn now_unix_ms(&self) -> Result<u64> {
        Ok(SystemTime::now()
            .duration_since(UNIX_EPOCH)?
            .as_millis()
            .try_into()?)
    }

    fn start(&mut self, id: &DeploymentId) -> Result {
        match self.settings.processes {
            ProcessMode::Systemd => self.systemctl("enable", id),
            // The local rehearsal owns and waits for its child processes.
            ProcessMode::Local => Ok(()),
        }
    }

    fn healthy(&mut self, port: PrivatePort) -> Result {
        #[derive(Deserialize)]
        struct HealthData {
            health: bool,
        }
        #[derive(Deserialize)]
        struct HealthResponse {
            data: Option<HealthData>,
        }
        // curl is already required by production deployment. Keep health probes
        // on loopback even when the host has outbound proxy configuration.
        let output = run_command(
            Command::new("curl").args([
                "--fail",
                "--silent",
                "--show-error",
                "--max-time",
                "3",
                "--noproxy",
                "*",
                "-H",
                "Content-Type: application/json",
                "--data",
                "{\"query\":\"{ health }\"}",
                &format!("http://127.0.0.1:{}/graphql", port.number()),
            ]),
            Duration::from_secs(4),
        )?;
        let response: HealthResponse = serde_json::from_slice(&output.stdout)?;
        if !response.data.is_some_and(|data| data.health) {
            return Err("candidate health check failed".into());
        }
        Ok(())
    }

    fn discard_candidate(&mut self, candidate: &Candidate) -> Result {
        self.stop(&candidate.id, candidate.pid)?;
        if self.settings.processes == ProcessMode::Local {
            // SIGTERM returns before the child closes its listener. The harness
            // owns reaping, so wait for the port instead of the process id.
            let deadline = Instant::now() + Duration::from_secs(15);
            loop {
                match TcpListener::bind(("127.0.0.1", candidate.port.number())) {
                    Ok(_) => break,
                    Err(error) if error.kind() == io::ErrorKind::AddrInUse => {
                        if Instant::now() >= deadline {
                            return Err("candidate did not release its private port".into());
                        }
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => return Err(error.into()),
                }
            }
        }
        Ok(())
    }

    fn stop(&mut self, id: &DeploymentId, pid: Option<ProcessId>) -> Result {
        match self.settings.processes {
            ProcessMode::Systemd => self.systemctl("disable", id),
            ProcessMode::Local => {
                let pid = pid.ok_or("local deployment has no child process id")?;
                let pid: libc::pid_t = pid.number().try_into()?;
                // SAFETY: ProcessId excludes zero, one, negative process groups,
                // and values outside pid_t. kill accepts no borrowed memory.
                if unsafe { libc::kill(pid, libc::SIGTERM) } != 0 {
                    let error = io::Error::last_os_error();
                    if error.raw_os_error() != Some(libc::ESRCH) {
                        return Err(error.into());
                    }
                }
                Ok(())
            }
        }
    }

    fn reload(&mut self) -> Result {
        run_command(
            Command::new(&self.settings.caddy)
                .arg("reload")
                .arg("--config")
                .arg(&self.settings.caddy_config)
                .args(["--adapter", "caddyfile"]),
            Duration::from_secs(10),
        )?;
        Ok(())
    }
}

fn run_command(command: &mut Command, timeout: Duration) -> Result<Output> {
    let description = command.get_program().to_string_lossy().into_owned();
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let deadline = Instant::now() + timeout;
    loop {
        if child.try_wait()?.is_some() {
            let output = child.wait_with_output()?;
            if !output.status.success() {
                return Err(format!(
                    "{description} failed ({}): {}",
                    output.status,
                    String::from_utf8_lossy(&output.stderr).trim()
                )
                .into());
            }
            return Ok(output);
        }
        if Instant::now() >= deadline {
            if let Err(error) = child.kill()
                && child.try_wait()?.is_none()
            {
                return Err(error.into());
            }
            child.wait()?;
            return Err(format!(
                "{description} timed out after {} seconds",
                timeout.as_secs()
            )
            .into());
        }
        thread::sleep(Duration::from_millis(10));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn commands_report_failures_and_terminate_on_timeout() -> Result {
        let failed = run_command(
            Command::new("sh").args(["-c", "printf failure >&2; exit 7"]),
            Duration::from_secs(1),
        );
        assert!(failed.is_err_and(|error| error.to_string().contains("failure")));
        let timed_out = run_command(
            Command::new("sh").args(["-c", "exec sleep 5"]),
            Duration::from_millis(20),
        );
        assert!(timed_out.is_err_and(|error| error.to_string().contains("timed out")));
        Ok(())
    }
}
