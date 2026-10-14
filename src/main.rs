#![deny(clippy::unwrap_used, clippy::expect_used)]

mod combat;
mod graphql;
mod lobby;
mod lobby_id;
mod lobby_name;
mod map;
mod map_definition;
mod map_editor;
mod map_type;
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

    let seed = match env::var("FIGHTLINES_SEED") {
        Ok(value) => seed::Seed::from_hex(&value).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "FIGHTLINES_SEED must contain 64 hexadecimal characters",
            )
        })?,
        Err(env::VarError::NotPresent) => seed::Seed::new([0; 32]),
        Err(error) => return Err(io::Error::new(io::ErrorKind::InvalidInput, error)),
    };
    let listener = TcpListener::bind(&address)?;
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
    let editor_enabled = env::args().any(|argument| argument == "--map-editor");
    let editor = web::Data::new(map_editor::Editor {
        directory: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("maps"),
        index: frontend.join("index.html"),
        writes: std::sync::Mutex::new(()),
    });
    if editor_enabled {
        println!("Map editor: http://{}/map-editor", listener.local_addr()?);
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
                "/game/{id}",
                web::get().to(move || {
                    let index = index.clone();
                    async move { NamedFile::open(index) }
                }),
            );
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
