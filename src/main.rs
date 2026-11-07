#![deny(clippy::unwrap_used, clippy::expect_used)]

mod admin;
mod ai;
mod app_version;
mod backdrop_calibration;
mod chat;
mod combat;
mod environment;
mod feedback;
mod game;
mod game_activity;
mod game_archive;
mod game_log;
mod graphql;
mod lobby;
mod lobby_id;
mod lobby_name;
mod lobby_snapshot;
mod map;
mod map_definition;
mod map_editor;
mod map_id;
mod map_thumbnail;
mod match_making;
mod movement;
mod movement_resolution;
mod player;
mod player_name;
mod player_number;
mod scenario;
mod seed;
mod server_limits;
mod server_log;
mod session_token;
mod storage_budget;
mod store;
mod supplies;
mod turns;
mod unit_loss;
mod unit_order;
mod visibility;

use actix_files::{Files, NamedFile};
use actix_web::{
    App, Error, HttpResponse, HttpServer, Responder,
    dev::{self, ServiceRequest},
    http::header::{Accept, Header, Quality},
    middleware::{self, DefaultHeaders},
    web,
};
use environment::Environment;

use std::{
    env, io,
    net::TcpListener,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

fn main() -> io::Result<()> {
    if env::args().nth(1).as_deref() == Some("--hash-admin-password") {
        return admin::password_command();
    }
    if env::args().nth(1).as_deref() == Some("--export-schema") {
        return graphql::export_schema();
    }
    if env::args().nth(1).as_deref() == Some("--replay-game-log") {
        let directory = env::args_os().nth(2).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "usage: --replay-game-log <game-directory>",
            )
        })?;
        println!("{}", game_log::replay(std::path::Path::new(&directory))?);
        return Ok(());
    }
    let environment = dotenvy::from_path(".env");
    let frontend = env::var_os("FIGHTLINES_FRONTEND_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("public"));
    let _log_guard = server_log::init(&frontend)?;
    match environment {
        Ok(_) => {}
        Err(dotenvy::Error::Io(error)) if error.kind() == io::ErrorKind::NotFound => {}
        Err(_) => {
            // dotenv parse errors may contain entire lines, including secrets.
            tracing::error!(
                event = "environment_invalid",
                "could not load .env; check syntax and file permissions"
            );
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "could not load .env",
            ));
        }
    }
    let result = actix_web::rt::System::new().block_on(run(frontend));
    if let Err(error) = &result {
        tracing::error!(event = "server_failed", error = %error, "server stopped with an error");
    }
    result
}

async fn run(frontend: PathBuf) -> io::Result<()> {
    let environment = Environment::load()?;
    let admin_auth = admin::Auth::load()?;
    environment.validate_arguments(env::args().skip(1))?;
    let address = env::var("FIGHTLINES_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into());

    let seed_override = match env::var("FIGHTLINES_SEED") {
        Ok(value) => Some(value),
        Err(env::VarError::NotPresent) => None,
        Err(env::VarError::NotUnicode(_)) => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "FIGHTLINES_SEED must contain UTF-8 hexadecimal characters",
            ));
        }
    };
    let seed = seed::Seed::startup(seed_override.as_deref())?;
    let log_path = env::var_os("FIGHTLINES_GAME_LOG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("game-logs"));
    let logs = game_log::Directory::open(log_path.clone())?;
    if log_path
        .canonicalize()?
        .starts_with(frontend.canonicalize()?)
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "FIGHTLINES_GAME_LOG_DIR must be outside FIGHTLINES_FRONTEND_DIR",
        ));
    }
    tracing::info!(directory = %log_path.canonicalize()?.display(), "game archives enabled");
    let feedback_path = env::var_os("FIGHTLINES_FEEDBACK_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("feedback"));
    let feedback = web::Data::new(feedback::Directory::open(feedback_path, &frontend)?);
    let listener = TcpListener::bind(&address)?;
    let server_start = logs.record_server_start(seed)?;
    tracing::info!(record = %server_start.display(), "private server-start record saved");
    tracing::info!(address = %listener.local_addr()?, version = app_version::current(), "FightLines listening");

    let store = if env::args().any(|argument| argument == "--dev-game") {
        tracing::info!("development game enabled at /game/00000000000000000000000000000000");
        store::Store::development(seed)
            .map_err(|error| io::Error::other(format!("Development game failed: {error:?}")))?
    } else {
        store::Store::new(seed)
    };
    let store = store.with_game_logs(logs);
    let editor_enabled = env::args().any(|argument| argument == "--map-editor");
    let editor = web::Data::new(map_editor::Editor {
        directory: map_id::directory(),
        frontend: frontend.clone(),
        writes: std::sync::Mutex::new(()),
    });
    let archives_enabled = env::args().any(|argument| argument == "--game-logs");
    let archives = web::Data::new(game_archive::Browser {
        directory: log_path,
    });
    if frontend.join("dev-tools.html").is_file() {
        tracing::info!("development tools available at /dev");
    }
    let store = web::Data::new(store);
    let endpoint = web::Data::new(graphql::endpoint_with_admin(
        environment,
        admin_auth,
        game_archive::Browser {
            directory: archives.directory.clone(),
        },
    ));
    let cleanup_store = store.clone();
    let server = HttpServer::new(move || {
        let mut app = App::new()
            .wrap(DefaultHeaders::new().add(("Cache-Control", "no-cache")))
            .wrap(middleware::from_fn(server_log::request))
            .app_data(store.clone())
            .app_data(endpoint.clone())
            .app_data(feedback.clone())
            .route("/graphql", web::post().to(graphql::handle))
            .service(dev_tools(&frontend))
            .service(admin_frontend(&frontend));
        if archives_enabled {
            app = app.app_data(archives.clone());
        }
        if editor_enabled {
            app = app.app_data(editor.clone());
        }
        app.service(player_frontend(&frontend))
    })
    .listen(listener)?
    .run();
    let cleanup = actix_web::rt::spawn(cleanup_expired_entries(cleanup_store));
    let result = server.await;
    cleanup.abort();
    result
}

async fn cleanup_expired_entries(store: web::Data<store::Store>) {
    let dispatch = tracing::dispatcher::get_default(Clone::clone);
    loop {
        actix_web::rt::time::sleep(Duration::from_secs(1)).await;
        let store = store.clone();
        let dispatch = dispatch.clone();
        let result = web::block(move || {
            tracing::dispatcher::with_default(&dispatch, || {
                let removed = store.remove_expired_entries(Instant::now())?;
                if removed > 0 {
                    tracing::info!(
                        event = "expired_entries_removed",
                        removed,
                        "inactive lobbies and expired finished games removed from memory"
                    );
                }
                Ok::<_, juniper::FieldError>(())
            })
        })
        .await;
        if let Err(error) = result {
            tracing::error!(event = "game_cleanup_worker_failed", error = %error, "lobby and game cleanup worker failed");
        }
    }
}

#[cfg(test)]
mod test_support;

// Existing files take priority. Elm owns all remaining player-page routes.
fn player_frontend(frontend: &Path) -> Files {
    let index = frontend.join("index.html");
    Files::new("/", frontend)
        .index_file("index.html")
        .default_handler(dev::fn_service(move |request: ServiceRequest| {
            let index = index.clone();
            async move {
                let path = Path::new(request.path());
                let asset_path = path.extension().is_some()
                    || ["/assets", "/audio", "/map-thumbnails"]
                        .iter()
                        .any(|prefix| path.starts_with(prefix));
                let api_path = path.starts_with("/graphql");
                let accepts_html = Accept::parse(&request).is_ok_and(|accept| {
                    accept.iter().any(|item| {
                        item.item.essence_str() == "text/html" && item.quality > Quality::ZERO
                    })
                });
                let response = if accepts_html && !asset_path && !api_path {
                    match NamedFile::open(index) {
                        Ok(file) => file.into_response(request.request()),
                        Err(error) => Error::from(error).error_response(),
                    }
                } else {
                    HttpResponse::NotFound().finish()
                };
                Ok::<_, Error>(request.into_response(response))
            }
        }))
}

fn admin_frontend(frontend: &Path) -> actix_web::Scope {
    let index = frontend.join("admin.html");
    web::scope("/admin").default_service(web::get().to(move || {
        let index = index.clone();
        async move {
            NamedFile::open(index).map(|file| {
                file.customize()
                    .insert_header(("Cache-Control", "no-store"))
            })
        }
    }))
}

// Elm owns every route within the tools app, including unknown-page handling.
fn dev_tools(frontend: &Path) -> actix_web::Scope {
    let index = frontend.join("dev-tools.html");
    web::scope("/dev").default_service(web::get().to(move || {
        let index = index.clone();
        async move { NamedFile::open(index) }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;
    use actix_web::{http::StatusCode, test};
    use std::fs;

    #[actix_web::test]
    async fn admin_routes_keep_replay_navigation_in_the_admin_app() -> TestResult<()> {
        let directory =
            env::temp_dir().join(format!("fightlines-admin-routes-{}", std::process::id()));
        fs::create_dir_all(&directory)?;
        fs::write(directory.join("index.html"), "player app")?;
        fs::write(directory.join("admin.html"), "admin app")?;
        let app = test::init_service(
            App::new()
                .service(admin_frontend(&directory))
                .service(player_frontend(&directory)),
        )
        .await;
        for uri in ["/admin", "/admin/recordings/example", "/admin/unknown"] {
            let response =
                test::call_service(&app, test::TestRequest::get().uri(uri).to_request()).await;
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(
                response
                    .headers()
                    .get("Cache-Control")
                    .ok_or("missing cache control")?,
                "no-store"
            );
            assert_eq!(test::read_body(response).await, "admin app");
        }
        let response = test::call_service(
            &app,
            test::TestRequest::get()
                .uri("/administrator")
                .insert_header(("accept", "text/html"))
                .to_request(),
        )
        .await;
        assert_eq!(test::read_body(response).await, "player app");
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn player_navigation_falls_back_without_masking_assets_or_other_services()
    -> TestResult<()> {
        let directory =
            env::temp_dir().join(format!("fightlines-player-routes-{}", std::process::id()));
        fs::create_dir_all(directory.join("assets"))?;
        fs::write(directory.join("index.html"), "player app")?;
        fs::write(directory.join("dev-tools.html"), "development tools")?;
        fs::write(directory.join("elm.js"), "player script")?;
        fs::write(directory.join("assets/unit.svg"), "unit image")?;
        let app = test::init_service(
            App::new()
                .route(
                    "/graphql",
                    web::post().to(|| async { HttpResponse::Ok().body("api response") }),
                )
                .service(dev_tools(&directory))
                .service(player_frontend(&directory)),
        )
        .await;
        for uri in [
            "/",
            "/new",
            "/lobby/example",
            "/lobby/example/maps",
            "/game/example",
            "/future/player/page",
            "/developer",
        ] {
            let request = test::TestRequest::get()
                .uri(uri)
                .insert_header(("accept", "text/html,application/xhtml+xml,*/*;q=0.8"))
                .to_request();
            let response = test::call_service(&app, request).await;
            assert_eq!(response.status(), StatusCode::OK, "{uri}");
            assert_eq!(test::read_body(response).await, "player app");
        }
        for (uri, body) in [
            ("/elm.js", "player script"),
            ("/assets/unit.svg", "unit image"),
            ("/dev", "development tools"),
            ("/dev/future/tool", "development tools"),
        ] {
            let request = test::TestRequest::get()
                .uri(uri)
                .insert_header(("accept", "text/html"))
                .to_request();
            let response = test::call_service(&app, request).await;
            assert_eq!(response.status(), StatusCode::OK, "{uri}");
            assert_eq!(test::read_body(response).await, body);
        }
        for uri in [
            "/missing.js",
            "/missing.json",
            "/assets/missing.svg",
            "/assets/missing",
            "/audio/missing",
            "/map-thumbnails/missing",
            "/graphql",
            "/graphql/missing",
        ] {
            let request = test::TestRequest::get()
                .uri(uri)
                .insert_header(("accept", "text/html"))
                .to_request();
            let response = test::call_service(&app, request).await;
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{uri}");
        }
        for accept in [
            None,
            Some("*/*"),
            Some("application/json"),
            Some("text/html;q=0"),
        ] {
            let mut request = test::TestRequest::get().uri("/future/player/page");
            if let Some(accept) = accept {
                request = request.insert_header(("accept", accept));
            }
            let response = test::call_service(&app, request.to_request()).await;
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{accept:?}");
        }
        let response =
            test::call_service(&app, test::TestRequest::post().uri("/graphql").to_request()).await;
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(test::read_body(response).await, "api response");
        let request = test::TestRequest::post()
            .uri("/new")
            .insert_header(("accept", "text/html"))
            .to_request();
        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
        fs::remove_file(directory.join("dev-tools.html"))?;
        let request = test::TestRequest::get()
            .uri("/dev/map-editor")
            .insert_header(("accept", "text/html"))
            .to_request();
        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        fs::remove_file(directory.join("index.html"))?;
        let request = test::TestRequest::get()
            .uri("/new")
            .insert_header(("accept", "text/html"))
            .to_request();
        let response = test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn dev_prefix_serves_elm_routes_and_stays_within_its_boundary() -> TestResult<()> {
        let directory =
            env::temp_dir().join(format!("fightlines-dev-routes-{}", std::process::id()));
        fs::create_dir_all(&directory)?;
        fs::write(directory.join("dev-tools.html"), "development tools")?;
        let app = test::init_service(App::new().service(dev_tools(&directory))).await;
        for uri in [
            "/dev",
            "/dev/",
            "/dev/map-editor",
            "/dev/logged-games/example-archive",
            "/dev/backdrop-review",
            "/dev/future-tool/nested-page",
        ] {
            let response =
                test::call_service(&app, test::TestRequest::get().uri(uri).to_request()).await;
            assert_eq!(response.status(), StatusCode::OK, "{uri}");
            assert_eq!(test::read_body(response).await, "development tools");
        }
        for uri in [
            "/developer",
            "/map-editor",
            "/logged-games",
            "/backdrop-review",
        ] {
            let response =
                test::call_service(&app, test::TestRequest::get().uri(uri).to_request()).await;
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{uri}");
        }
        fs::remove_file(directory.join("dev-tools.html"))?;
        let response =
            test::call_service(&app, test::TestRequest::get().uri("/dev").to_request()).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        fs::remove_dir_all(directory)?;
        Ok(())
    }
}
