use crate::{
    Result,
    control::{self, Candidate, PrivatePort, ProcessId, Registry, Supervisor},
    deployment_id::DeploymentId,
    runtime::{self, ProcessMode, SystemHost},
};
use std::{ffi::OsString, path::PathBuf, time::Duration};

enum Operation {
    ValidateId(DeploymentId),
    AvailablePort(PathBuf),
    ReservedPorts(PathBuf),
    Activate {
        settings: control::Settings,
        host: runtime::Settings,
        candidate: Candidate,
    },
    Sweep {
        settings: control::Settings,
        host: runtime::Settings,
    },
}

enum RequestedOperation {
    ValidateId(DeploymentId),
    AvailablePort,
    ReservedPorts,
    Activate(DeploymentId),
    Sweep,
}

fn value(arguments: &mut impl Iterator<Item = OsString>, flag: &str) -> Result<OsString> {
    arguments
        .next()
        .ok_or_else(|| format!("missing value for {flag}").into())
}

fn text(value: OsString) -> Result<String> {
    value
        .into_string()
        .map_err(|_| "command arguments must contain valid UTF-8".into())
}

fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<Operation> {
    let mut arguments = arguments.into_iter();
    let mut root = None;
    let mut routes = None;
    let mut caddy_config = None;
    let mut caddy = PathBuf::from("caddy");
    let mut max_drain_seconds = 21600_u64;
    let mut processes = ProcessMode::Systemd;
    let mut operation = None;
    let mut port = None;
    let mut pid = None;
    while let Some(argument) = arguments.next() {
        let argument = text(argument)?;
        match argument.as_str() {
            "--root" => root = Some(PathBuf::from(value(&mut arguments, "--root")?)),
            "--routes" => routes = Some(PathBuf::from(value(&mut arguments, "--routes")?)),
            "--caddy-config" => {
                caddy_config = Some(PathBuf::from(value(&mut arguments, "--caddy-config")?));
            }
            "--caddy" => caddy = PathBuf::from(value(&mut arguments, "--caddy")?),
            "--max-drain-seconds" => {
                max_drain_seconds = text(value(&mut arguments, "--max-drain-seconds")?)?.parse()?;
            }
            "--local" => processes = ProcessMode::Local,
            "--port" => {
                port = Some(PrivatePort::try_from(
                    text(value(&mut arguments, "--port")?)?.parse::<u16>()?,
                )?);
            }
            "--pid" => {
                pid = Some(ProcessId::try_from(
                    text(value(&mut arguments, "--pid")?)?.parse::<u32>()?,
                )?);
            }
            "activate" | "sweep" | "available-port" | "reserved-ports" | "validate-id" => {
                if operation.is_some() {
                    return Err("choose exactly one supervisor command".into());
                }
                operation = Some(match argument.as_str() {
                    "activate" => RequestedOperation::Activate(DeploymentId::try_from(text(
                        value(&mut arguments, "activate")?,
                    )?)?),
                    "validate-id" => RequestedOperation::ValidateId(DeploymentId::try_from(text(
                        value(&mut arguments, "validate-id")?,
                    )?)?),
                    "available-port" => RequestedOperation::AvailablePort,
                    "reserved-ports" => RequestedOperation::ReservedPorts,
                    _ => RequestedOperation::Sweep,
                });
            }
            _ => return Err(format!("unknown supervisor argument: {argument}").into()),
        }
    }
    if max_drain_seconds == 0 || max_drain_seconds.checked_mul(1000).is_none() {
        return Err("maximum drain duration must be a positive supported number of seconds".into());
    }
    let operation = operation.ok_or(
        "usage: fightlines-supervisor [options] activate <id> | sweep | available-port | reserved-ports | validate-id <id>",
    )?;
    if let RequestedOperation::ValidateId(id) = operation {
        return Ok(Operation::ValidateId(id));
    }
    let root = root.ok_or("--root is required")?;
    match operation {
        RequestedOperation::AvailablePort => return Ok(Operation::AvailablePort(root)),
        RequestedOperation::ReservedPorts => return Ok(Operation::ReservedPorts(root)),
        _ => {}
    }
    let settings = control::Settings {
        root,
        routes: routes.ok_or("--routes is required")?,
        max_drain: Duration::from_secs(max_drain_seconds),
    };
    let host = runtime::Settings {
        caddy,
        caddy_config: caddy_config.ok_or("--caddy-config is required")?,
        processes,
    };
    match operation {
        RequestedOperation::Activate(id) => {
            if processes == ProcessMode::Local && pid.is_none() {
                return Err("local activation requires --pid".into());
            }
            Ok(Operation::Activate {
                settings,
                host,
                candidate: Candidate {
                    id,
                    port: port.ok_or("activation requires --port")?,
                    pid,
                },
            })
        }
        RequestedOperation::Sweep => Ok(Operation::Sweep { settings, host }),
        _ => Err("invalid supervisor operation".into()),
    }
}

pub(crate) fn run(arguments: impl IntoIterator<Item = OsString>) -> Result {
    match parse(arguments)? {
        Operation::ValidateId(id) => println!("{id}"),
        Operation::AvailablePort(root) => {
            let _lock = control::lock(&root)?;
            println!("{}", Registry::read(&root)?.available_port()?.number());
        }
        Operation::ReservedPorts(root) => {
            let _lock = control::lock(&root)?;
            println!(
                "{}",
                serde_json::to_string(&Registry::read(&root)?.reserved_ports())?
            );
        }
        Operation::Activate {
            settings,
            host,
            candidate,
        } => {
            let _lock = control::lock(&settings.root)?;
            Supervisor::load(settings, SystemHost::new(host))?.activate(candidate)?;
        }
        Operation::Sweep { settings, host } => {
            let _lock = control::lock(&settings.root)?;
            Supervisor::load(settings, SystemHost::new(host))?.sweep()?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arguments(arguments: &[&str]) -> Vec<OsString> {
        arguments.iter().map(OsString::from).collect()
    }

    #[test]
    fn validation_precedes_control_file_or_process_changes() -> Result {
        for invalid in ["", "../secret", "UPPERCASE", "a/b"] {
            assert!(parse(arguments(&["validate-id", invalid])).is_err());
        }
        assert!(
            parse(arguments(&[
                "validate-id",
                "release-20261107t123456z-0123456789ab"
            ]))
            .is_ok()
        );
        assert!(parse(arguments(&["--root", "/tmp/unused", "available-port"])).is_ok());
        let base = [
            "--root",
            "/tmp/unused",
            "--routes",
            "/tmp/routes",
            "--caddy-config",
            "/tmp/Caddyfile",
            "--local",
            "activate",
            "a",
            "--port",
            "8100",
        ];
        assert!(parse(arguments(&base)).is_err());
        for pid in ["0", "1", "-1", "2147483648"] {
            let mut input = arguments(&base);
            input.extend(arguments(&["--pid", pid]));
            assert!(parse(input).is_err());
        }
        let mut input = arguments(&base);
        input.extend(arguments(&["--pid", "123"]));
        assert!(parse(input).is_ok());
        for duration in ["0", "-1", "18446744073709551615"] {
            assert!(
                parse(arguments(&[
                    "--max-drain-seconds",
                    duration,
                    "validate-id",
                    "a"
                ]))
                .is_err()
            );
        }
        Ok(())
    }
}
