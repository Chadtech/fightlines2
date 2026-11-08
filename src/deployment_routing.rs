//! Resolve stable session pages for Caddy. Game requests retain the release's
//! document base; no deployment selection belongs in public page URLs.
use crate::{deployment_id::DeploymentId, lobby_id::LobbyId, store::Store};
use actix_web::{
    HttpRequest, HttpResponse,
    http::header::{CACHE_CONTROL, HeaderValue},
    web,
};
use serde::Deserialize;
use std::{collections::BTreeMap, fs, io, path::Path};

#[derive(Deserialize)]
struct Registry {
    releases: BTreeMap<DeploymentId, Release>,
}

#[derive(Deserialize)]
struct Release {
    port: u16,
    running: bool,
}

#[derive(Debug, PartialEq, Eq)]
enum Destination {
    Running(u16),
    Retired,
    Unknown,
}

fn session_id(uri: &str) -> Option<LobbyId> {
    let path = uri.split('?').next()?;
    let parts: Vec<_> = path.split('/').collect();
    let id = match parts.as_slice() {
        ["", "lobby" | "game", id] | ["", "lobby", id, "maps"] => *id,
        _ => return None,
    };
    if id.len() != 32
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        return None;
    }
    Some(LobbyId::from_token(id.into()))
}

fn resolve(root: &Path, id: &LobbyId) -> io::Result<Destination> {
    let owner = match fs::read(root.join(".session-owners").join(id.to_string())) {
        Ok(bytes) => serde_json::from_slice::<DeploymentId>(&bytes)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Destination::Unknown),
        Err(error) => return Err(error),
    };
    let registry: Registry = serde_json::from_slice(&fs::read(root.join("registry.json"))?)?;
    match registry.releases.get(&owner) {
        Some(release) if release.running && release.port >= 1024 => {
            Ok(Destination::Running(release.port))
        }
        Some(release) if !release.running => Ok(Destination::Retired),
        _ => Err(io::Error::other(
            "session owner has no valid registered upstream",
        )),
    }
}

pub async fn route(request: HttpRequest, store: web::Data<Store>) -> HttpResponse {
    // Caddy blocks this endpoint publicly, including beneath private release
    // bases. Also refuse direct non-loopback connections to the process.
    if !request
        .peer_addr()
        .is_some_and(|peer| peer.ip().is_loopback())
    {
        return HttpResponse::NotFound().finish();
    }
    let Some(deployment) = &store.deployment else {
        return HttpResponse::NotFound().finish();
    };
    let id = request
        .headers()
        .get("X-Forwarded-Uri")
        .and_then(|value| value.to_str().ok())
        .and_then(session_id);
    let Some(id) = id else {
        return HttpResponse::NotFound().finish();
    };
    let root = deployment.routing_root().to_owned();
    let destination = match web::block(move || resolve(&root, &id)).await {
        Ok(destination) => destination,
        Err(error) => Err(io::Error::other(error)),
    };
    let mut response = match destination {
        Ok(Destination::Running(port)) => HttpResponse::Ok()
            .insert_header(("X-Fightlines-Upstream", format!("127.0.0.1:{port}")))
            .finish(),
        Ok(Destination::Retired) => HttpResponse::Gone().body("this session has ended."),
        Ok(Destination::Unknown) => HttpResponse::NotFound().body("this session does not exist."),
        Err(error) => {
            tracing::error!(event = "session_routing_failed", error = %error, "session ownership could not be resolved");
            HttpResponse::ServiceUnavailable().body("session routing is temporarily unavailable.")
        }
    };
    response
        .headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};
    use std::time::{SystemTime, UNIX_EPOCH};

    const ID: &str = "0123456789abcdef0123456789abcdef";

    #[test]
    fn stable_paths_validate_ids_without_accepting_filesystem_paths() -> TestResult {
        for path in [
            format!("/lobby/{ID}"),
            format!("/game/{ID}?view=1"),
            format!("/lobby/{ID}/maps"),
        ] {
            assert_eq!(session_id(&path).fixture()?.to_string(), ID);
        }
        for path in [
            "/lobby/../secret",
            "/game/%2e%2e",
            "/lobby/short",
            "/game/0123456789ABCDEF0123456789ABCDEF",
            "/admin",
            "/game/0123456789abcdef0123456789abcdef/other",
        ] {
            assert!(session_id(path).is_none(), "{path}");
        }
        Ok(())
    }

    #[test]
    fn lookup_never_falls_through_to_current_or_reused_ports() -> TestResult {
        let root = std::env::temp_dir().join(format!(
            "fightlines-session-routing-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir_all(root.join(".session-owners"))?;
        let id = session_id(&format!("/game/{ID}")).fixture()?;
        assert_eq!(resolve(&root, &id)?, Destination::Unknown);
        let owner = root.join(".session-owners").join(ID);
        fs::write(&owner, "\"a\"")?;
        let registry = root.join("registry.json");
        fs::write(
            &registry,
            r#"{"current":"b","releases":{"a":{"port":8101,"running":true},"b":{"port":8102,"running":true}}}"#,
        )?;
        assert_eq!(resolve(&root, &id)?, Destination::Running(8101));
        fs::write(
            &registry,
            r#"{"current":"b","releases":{"a":{"port":8101,"running":false},"b":{"port":8101,"running":true}}}"#,
        )?;
        assert_eq!(resolve(&root, &id)?, Destination::Retired);
        fs::write(
            &registry,
            r#"{"releases":{"b":{"port":8101,"running":true}}}"#,
        )?;
        assert!(resolve(&root, &id).is_err());
        fs::write(&registry, "invalid")?;
        assert!(resolve(&root, &id).is_err());
        fs::write(&owner, "\"../secret\"")?;
        assert!(resolve(&root, &id).is_err());
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
