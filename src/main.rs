#![deny(clippy::unwrap_used, clippy::expect_used)]

mod ai;
mod backdrop_calibration;
mod combat;
mod game_archive;
mod game_log;
mod graphql;
mod lobby;
mod lobby_id;
mod lobby_name;
mod map;
mod map_definition;
mod map_editor;
mod map_id;
mod map_thumbnail;
mod movement;
mod movement_resolution;
mod player_name;
mod scenario;
mod seed;
mod session_token;
mod supplies;
mod turns;
mod visibility;

use actix_files::{Files, NamedFile};
use actix_web::{App, HttpServer, middleware::DefaultHeaders, web};

use std::{env, io, net::TcpListener, path::PathBuf};

fn main() -> io::Result<()> {
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
    match dotenvy::from_path(".env") {
        Ok(()) => {}
        Err(dotenvy::Error::Io(error)) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(io::Error::new(io::ErrorKind::InvalidInput, error)),
    }
    actix_web::rt::System::new().block_on(run())
}

async fn run() -> io::Result<()> {
    let address = env::var("FIGHTLINES_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into());
    let frontend = env::var_os("FIGHTLINES_FRONTEND_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("public"));

    let seed_override = match env::var("FIGHTLINES_SEED") {
        Ok(value) => Some(value),
        Err(env::VarError::NotPresent) => None,
        Err(error) => return Err(io::Error::new(io::ErrorKind::InvalidInput, error)),
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
    println!("Game archives: {}", log_path.canonicalize()?.display());
    let listener = TcpListener::bind(&address)?;
    let server_start = logs.record_server_start(seed)?;
    println!("Private server-start record: {}", server_start.display());
    println!("FightLines listening on http://{}", listener.local_addr()?);

    let store = if env::args().any(|argument| argument == "--dev-game") {
        println!(
            "Development game: http://{}/game/00000000000000000000000000000000",
            listener.local_addr()?
        );
        lobby::Store::development(seed)
            .map_err(|error| io::Error::other(format!("Development game failed: {error:?}")))?
    } else {
        lobby::Store::new(seed)
    };
    let store = store.with_game_logs(logs);
    let editor_enabled = env::args().any(|argument| argument == "--map-editor");
    let editor = web::Data::new(map_editor::Editor {
        directory: map_id::directory(),
        index: frontend.join("dev-tools.html"),
        writes: std::sync::Mutex::new(()),
    });
    if editor_enabled {
        println!("Map editor: http://{}/map-editor", listener.local_addr()?);
    }
    let archives_enabled = env::args().any(|argument| argument == "--game-logs");
    let archives = web::Data::new(game_archive::Browser {
        directory: log_path,
        index: frontend.join("dev-tools.html"),
    });
    if archives_enabled {
        println!(
            "Logged games: http://{}/logged-games",
            listener.local_addr()?
        );
    }
    let store = web::Data::new(store);
    let schema = web::Data::new(graphql::schema());
    HttpServer::new(move || {
        let index = frontend.join("index.html");
        let mut app = App::new()
            .wrap(DefaultHeaders::new().add(("Cache-Control", "no-cache")))
            .app_data(store.clone())
            .app_data(schema.clone())
            .route("/graphql", web::post().to(graphql::handle))
            .route(
                "/backdrop-review",
                web::get().to({
                    let index = frontend.join("dev-tools.html");
                    move || {
                        let index = index.clone();
                        async move { NamedFile::open(index) }
                    }
                }),
            )
            .route(
                "/new",
                web::get().to({
                    let index = index.clone();
                    move || {
                        let index = index.clone();
                        async move { NamedFile::open(index) }
                    }
                }),
            )
            .route(
                "/lobby/{id}",
                web::get().to({
                    let index = index.clone();
                    move || {
                        let index = index.clone();
                        async move { NamedFile::open(index) }
                    }
                }),
            )
            .route(
                "/lobby/{id}/maps",
                web::get().to({
                    let index = index.clone();
                    move || {
                        let index = index.clone();
                        async move { NamedFile::open(index) }
                    }
                }),
            )
            .route(
                "/game/{id}",
                web::get().to(move || {
                    let index = index.clone();
                    async move { NamedFile::open(index) }
                }),
            );
        if archives_enabled {
            app = app
                .app_data(archives.clone())
                .route("/logged-games", web::get().to(game_archive::page))
                .route("/logged-games/{id}", web::get().to(game_archive::page));
        }
        if editor_enabled {
            app = app
                .app_data(editor.clone())
                .configure(|config| map_editor::configure(config, true));
        }
        app.service(Files::new("/", &frontend).index_file("index.html"))
    })
    .listen(listener)?
    .run()
    .await
}

#[cfg(test)]
mod test_support;
