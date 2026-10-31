//! Map authoring resolvers. Filesystem access is enabled only with --map-editor.
use crate::{
    graphql::Context,
    map::{Coordinate, MapTheme, TerrainValue},
    map_definition::{DepotPlacement, MapDefinition, NamedMap, TerrainPlacement, UnitPlacement},
    map_id::{self, MapId},
    map_thumbnail,
    scenario::{BuildingKind, Direction, PlayerNumber, UnitKind},
};
use actix_web::{HttpRequest, web};
use juniper::{FieldResult, GraphQLInputObject, GraphQLObject};
use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
};

pub struct Editor {
    pub directory: PathBuf,
    pub frontend: PathBuf,
    pub writes: Mutex<()>,
}

pub enum Access {
    Disabled,
    Denied,
    ReadOnly(Arc<Editor>),
    Writable(Arc<Editor>),
}

impl Access {
    pub fn from_request(editor: Option<web::Data<Editor>>, request: &HttpRequest) -> Self {
        match editor {
            None => Self::Disabled,
            Some(_) if !local_request(request) => Self::Denied,
            Some(editor) if same_origin(request) => Self::Writable(editor.into_inner()),
            Some(editor) => Self::ReadOnly(editor.into_inner()),
        }
    }

    fn read(&self) -> FieldResult<&Editor> {
        match self {
            Self::Disabled => {
                Err("map editing is disabled. start the server with --map-editor.".into())
            }
            Self::Denied => Err("map editing requires localhost".into()),
            Self::ReadOnly(editor) | Self::Writable(editor) => Ok(editor),
        }
    }

    pub(crate) fn write(&self) -> FieldResult<&Editor> {
        let editor = self.read()?;
        match self {
            Self::Writable(_) => Ok(editor),
            _ => Err("save maps from the localhost editor".into()),
        }
    }
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct MapCatalog {
    first: NamedMap,
    rest: Vec<NamedMap>,
}

#[derive(GraphQLInputObject)]
struct PositionInput {
    x: i32,
    y: i32,
}
#[derive(GraphQLInputObject)]
struct TerrainPlacementInput {
    position: PositionInput,
    terrain: TerrainValue,
}
#[derive(GraphQLInputObject)]
struct DepotPlacementInput {
    position: PositionInput,
    kind: BuildingKind,
}
#[derive(GraphQLInputObject)]
struct UnitPlacementInput {
    id: i32,
    position: PositionInput,
    player_number: PlayerNumber,
    kind: UnitKind,
    direction: Option<Direction>,
}
#[derive(GraphQLInputObject)]
pub struct MapDefinitionInput {
    description: String,
    width: i32,
    height: i32,
    theme: MapTheme,
    features: Vec<TerrainPlacementInput>,
    depots: Vec<DepotPlacementInput>,
    units: Vec<UnitPlacementInput>,
}

fn unsigned(value: i32, field: &str) -> FieldResult<u16> {
    u16::try_from(value)
        .map_err(|_| format!("invalid map: {field} must be between 0 and 65535").into())
}
impl PositionInput {
    fn coordinate(self) -> FieldResult<Coordinate> {
        Ok(Coordinate::new(
            unsigned(self.x, "x")?,
            unsigned(self.y, "y")?,
        ))
    }
}
impl MapDefinitionInput {
    fn definition(self) -> FieldResult<MapDefinition> {
        Ok(MapDefinition {
            description: self.description,
            width: unsigned(self.width, "width")?,
            height: unsigned(self.height, "height")?,
            theme: self.theme,
            features: self
                .features
                .into_iter()
                .map(|feature| {
                    Ok(TerrainPlacement {
                        position: feature.position.coordinate()?,
                        terrain: feature.terrain.into(),
                    })
                })
                .collect::<FieldResult<_>>()?,
            depots: self
                .depots
                .into_iter()
                .map(|depot| {
                    Ok(DepotPlacement {
                        position: depot.position.coordinate()?,
                        kind: depot.kind,
                    })
                })
                .collect::<FieldResult<_>>()?,
            units: self
                .units
                .into_iter()
                .map(|unit| {
                    Ok(UnitPlacement {
                        id: unsigned(unit.id, "unit id")?,
                        position: unit.position.coordinate()?,
                        player_number: unit.player_number,
                        kind: unit.kind,
                        direction: unit.direction,
                    })
                })
                .collect::<FieldResult<_>>()?,
        })
    }
}

pub fn maps(context: &Context) -> FieldResult<MapCatalog> {
    let editor = context.editor.read()?;
    let mut maps = map_id::catalog_in(&editor.directory)
        .map_err(|error| error.to_string())?
        .into_iter();
    let first = maps.next().ok_or("no editable maps were returned")?;
    Ok(MapCatalog {
        first,
        rest: maps.collect(),
    })
}

pub fn save_map(
    context: &Context,
    map_type: MapId,
    definition: MapDefinitionInput,
    thumbnail: Option<String>,
) -> FieldResult<NamedMap> {
    write_map(context, map_type, definition, thumbnail, WriteMode::Update)
}

pub fn create_map(
    context: &Context,
    map_type: MapId,
    definition: MapDefinitionInput,
    thumbnail: Option<String>,
) -> FieldResult<NamedMap> {
    write_map(context, map_type, definition, thumbnail, WriteMode::Create)
}

enum WriteMode {
    Create,
    Update,
}

fn write_map(
    context: &Context,
    map_type: MapId,
    definition: MapDefinitionInput,
    thumbnail: Option<String>,
    mode: WriteMode,
) -> FieldResult<NamedMap> {
    let editor = context.editor.write()?;
    let name = map_type.as_str();
    let definition = definition.definition()?;
    definition
        .scenario()
        .map_err(|error| format!("invalid map: {error}"))?;
    let json = serde_json::to_string_pretty(&definition)? + "\n";
    let _guard = editor.writes.lock().map_err(|error| error.to_string())?;
    let destination = editor.directory.join(format!("{name}.json"));
    match mode {
        WriteMode::Create if destination.exists() => {
            return Err("a map with this name already exists".into());
        }
        WriteMode::Update if !destination.is_file() => return Err("unknown map".into()),
        WriteMode::Create | WriteMode::Update => {}
    }
    if let Some(thumbnail) = thumbnail {
        map_thumbnail::save(&editor.frontend, &definition, &thumbnail)?;
    }
    let temporary = destination.with_extension("json.tmp");
    fs::write(&temporary, json)?;
    fs::rename(&temporary, &destination)?;
    Ok(NamedMap {
        map_type,
        definition,
    })
}

fn local_request(request: &HttpRequest) -> bool {
    request
        .peer_addr()
        .is_some_and(|peer| peer.ip().is_loopback())
}
fn same_origin(request: &HttpRequest) -> bool {
    let connection = request.connection_info();
    let host = connection.host();
    let local_host = host.starts_with("127.0.0.1:")
        || host.starts_with("localhost:")
        || host.starts_with("[::1]:");
    local_host
        && request
            .headers()
            .get("origin")
            .and_then(|value| value.to_str().ok())
            == Some(format!("http://{host}").as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;
    use actix_web::{App, http::StatusCode, test};
    use serde_json::{Value, json};
    use std::net::{IpAddr, Ipv4Addr, SocketAddr};

    const SAVE: &str = "mutation Save($definition: MapDefinitionInput!, $kind: MapId!) { saveMap(mapType: $kind, definition: $definition) { mapType definition { description theme width depots { kind } } } }";
    const CREATE: &str = "mutation Create($definition: MapDefinitionInput!, $kind: MapId!) { createMap(mapType: $kind, definition: $definition) { mapType } }";

    fn store() -> web::Data<crate::lobby::Store> {
        web::Data::new(crate::lobby::Store::new(crate::seed::Seed::new([0; 32])))
    }
    fn editor(directory: PathBuf) -> web::Data<Editor> {
        web::Data::new(Editor {
            directory,
            frontend: PathBuf::new(),
            writes: Mutex::new(()),
        })
    }

    // GraphQL enums use their schema names independently of map-file Serde names.
    fn graphql_definition() -> TestResult<Value> {
        let definition = MapDefinition::parse(include_str!("../maps/supply-point.json"))
            .map_err(|error| error.to_string())?;
        let position = |coordinate: Coordinate| PositionInput {
            x: coordinate.x(),
            y: coordinate.y(),
        };
        let input = MapDefinitionInput {
            description: definition.description,
            width: i32::from(definition.width),
            height: i32::from(definition.height),
            theme: definition.theme,
            features: definition
                .features
                .into_iter()
                .map(|feature| TerrainPlacementInput {
                    position: position(feature.position),
                    terrain: feature.terrain.into(),
                })
                .collect(),
            depots: definition
                .depots
                .into_iter()
                .map(|depot| DepotPlacementInput {
                    position: position(depot.position),
                    kind: depot.kind,
                })
                .collect(),
            units: definition
                .units
                .into_iter()
                .map(|unit| UnitPlacementInput {
                    id: i32::from(unit.id),
                    position: position(unit.position),
                    player_number: unit.player_number,
                    kind: unit.kind,
                    direction: unit.direction,
                })
                .collect(),
        };
        let value: juniper::InputValue = juniper::ToInputValue::to_input_value(&input);
        Ok(serde_json::to_value(value)?)
    }

    #[actix_web::test]
    async fn editor_operations_reject_requests_without_editor_mode() -> TestResult<()> {
        let app = test::init_service(
            App::new()
                .app_data(store())
                .app_data(web::Data::new(crate::graphql::schema()))
                .route("/graphql", web::post().to(crate::graphql::handle)),
        )
        .await;
        let valid = graphql_definition()?;
        for query in ["{ maps { first { mapType } } }", SAVE, CREATE] {
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
                .insert_header(("host", "localhost:8080"))
                .insert_header(("origin", "http://localhost:8080"))
                .set_json(
                    json!({"query":query,"variables":{"kind":"supply-point","definition":valid}}),
                )
                .to_request();
            let body: Value = test::call_and_read_body_json(&app, request).await;
            assert_eq!(
                body["errors"][0]["message"],
                json!("map editing is disabled. start the server with --map-editor.")
            );
        }
        let request = test::TestRequest::post()
            .uri("/graphql")
            .set_json(json!({"query":"{ health }"}))
            .to_request();
        let body: Value = test::call_and_read_body_json(&app, request).await;
        assert_eq!(body["data"]["health"], json!(true));
        for route in ["/editor/graphql", "/dev/maps", "/dev/maps/supply-point"] {
            let request = test::TestRequest::post()
                .uri(route)
                .set_json(json!({"query":"{ health }"}))
                .to_request();
            assert_eq!(
                test::call_service(&app, request).await.status(),
                StatusCode::NOT_FOUND
            );
        }
        Ok(())
    }

    #[actix_web::test]
    async fn shared_endpoint_keeps_game_queries_available_and_checks_editor_reads() -> TestResult<()>
    {
        let app = test::init_service(
            App::new()
                .app_data(store())
                .app_data(editor(
                    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("maps"),
                ))
                .app_data(web::Data::new(crate::graphql::schema()))
                .route("/graphql", web::post().to(crate::graphql::handle)),
        )
        .await;
        for (query, peer, success) in [
            (
                "{ health maps { first { mapType definition { description width units { playerNumber direction } } } rest { mapType definition { description } } } }",
                Ipv4Addr::LOCALHOST,
                true,
            ),
            (
                "{ maps { first { mapType } } }",
                Ipv4Addr::new(192, 168, 1, 2),
                false,
            ),
            ("{ health }", Ipv4Addr::new(192, 168, 1, 2), true),
        ] {
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(peer), 1234))
                .set_json(json!({"query":query}))
                .to_request();
            let response = test::call_service(&app, request).await;
            assert_eq!(
                response
                    .headers()
                    .get("cache-control")
                    .and_then(|value| value.to_str().ok()),
                Some("no-store")
            );
            let body: Value = test::read_body_json(response).await;
            assert_eq!(body.get("errors").is_none(), success, "{body}");
            if peer == Ipv4Addr::LOCALHOST {
                assert_eq!(
                    body["data"]["maps"]["rest"].as_array().map(Vec::len),
                    Some(map_id::options().map_err(|error| error.to_string())?.len() - 1)
                );
                assert_eq!(body["data"]["health"], json!(true));
                let maps = &body["data"]["maps"];
                let rest = maps["rest"].as_array().ok_or("missing map catalog")?;
                for map in std::iter::once(&maps["first"]).chain(rest) {
                    let description = map["definition"]["description"]
                        .as_str()
                        .ok_or("missing map description")?;
                    assert!(!description.trim().is_empty(), "{map}");
                }
            } else if !success {
                assert_eq!(
                    body["errors"][0]["message"],
                    json!("map editing requires localhost")
                );
            }
        }
        Ok(())
    }

    #[actix_web::test]
    async fn graphql_saves_validate_input_and_preserve_files_on_rejection() -> TestResult<()> {
        let directory =
            std::env::temp_dir().join(format!("fightlines-editor-unified-{}", std::process::id()));
        fs::create_dir_all(&directory)?;
        let destination = directory.join("supply-point.json");
        let original = include_str!("../maps/supply-point.json");
        fs::write(&destination, original)?;
        let app = test::init_service(
            App::new()
                .app_data(store())
                .app_data(editor(directory.clone()))
                .app_data(web::Data::new(crate::graphql::schema()))
                .route("/graphql", web::post().to(crate::graphql::handle)),
        )
        .await;
        let valid = graphql_definition()?;
        for failure in [
            "remote",
            "origin",
            "missing-origin",
            "width",
            "negative-position",
            "id",
            "direction",
            "unknown-map",
        ] {
            let mut definition = valid.clone();
            let mut kind = "supply-point";
            match failure {
                "width" => definition["width"] = json!(-1),
                "negative-position" => definition["units"][0]["position"]["x"] = json!(-1),
                "id" => definition["units"][0]["id"] = json!(0),
                "direction" => definition["units"][0]["direction"] = Value::Null,
                "unknown-map" => kind = "unknown",
                _ => {}
            }
            let peer = if failure == "remote" {
                Ipv4Addr::new(192, 168, 1, 2)
            } else {
                Ipv4Addr::LOCALHOST
            };
            let mut request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(peer), 1234))
                .insert_header(("host", "localhost:8080"));
            if failure != "missing-origin" {
                request = request.insert_header((
                    "origin",
                    if failure == "origin" {
                        "http://example.com"
                    } else {
                        "http://localhost:8080"
                    },
                ));
            }
            let request = request
                .set_json(json!({"query":SAVE,"variables":{"kind":kind,"definition":definition}}))
                .to_request();
            let body: Value = test::call_and_read_body_json(&app, request).await;
            assert!(body.get("errors").is_some(), "{failure}: {body}");
            assert_eq!(fs::read_to_string(&destination)?, original);
        }
        let mut definition = valid;
        definition["depots"] = json!([{"position": {"x": 0, "y": 0}, "kind": "FORTRESS"}]);
        definition["description"] = json!("a custom battlefield description");
        definition["theme"] = json!("SNOW");
        let request = test::TestRequest::post()
            .uri("/graphql")
            .peer_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
            .insert_header(("host", "localhost:8080"))
            .insert_header(("origin", "http://localhost:8080"))
            .set_json(
                json!({"query":SAVE,"variables":{"kind":"supply-point","definition":definition}}),
            )
            .to_request();
        let body: Value = test::call_and_read_body_json(&app, request).await;
        assert!(body.get("errors").is_none(), "{body}");
        let saved: Value = serde_json::from_str(&fs::read_to_string(&destination)?)?;
        assert_eq!(saved["theme"], json!("Snow"));
        assert_eq!(
            body["data"]["saveMap"]["definition"]["depots"],
            json!([{ "kind": "FORTRESS" }])
        );
        assert_eq!(
            saved["depots"],
            json!([{"position": {"x": 0, "y": 0}, "kind": "Fortress"}])
        );
        assert_eq!(saved["description"], definition["description"]);
        assert_eq!(
            body["data"]["saveMap"]["definition"]["description"],
            definition["description"]
        );
        assert_eq!(
            body["data"]["saveMap"]["definition"]["theme"],
            json!("SNOW")
        );
        let original_data: Value = serde_json::from_str(original)?;
        assert_eq!(saved["units"], original_data["units"]);
        assert!(!destination.with_extension("json.tmp").exists());
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn creates_maps_without_overwriting_and_rejects_invalid_or_unauthorized_creation()
    -> TestResult<()> {
        let directory =
            std::env::temp_dir().join(format!("fightlines-create-map-{}", std::process::id()));
        fs::create_dir_all(&directory)?;
        let destination = directory.join("new-battlefield.json");
        let app = test::init_service(
            App::new()
                .app_data(store())
                .app_data(editor(directory.clone()))
                .app_data(web::Data::new(crate::graphql::schema()))
                .route("/graphql", web::post().to(crate::graphql::handle)),
        )
        .await;
        let valid = json!({
            "description": "creation fixture", "width": 2, "height": 2,
            "theme": "GREEN_FOREST", "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "PLAYER1", "kind": "INFANTRY", "direction": "EAST"},
                {"id": 2, "position": {"x": 1, "y": 1}, "playerNumber": "PLAYER2", "kind": "INFANTRY", "direction": "WEST"}
            ]
        });
        let mut original = None;
        for attempt in [
            "remote",
            "origin",
            "empty-forces",
            "invalid-name",
            "create",
            "duplicate",
        ] {
            let mut definition = valid.clone();
            if attempt == "empty-forces" {
                definition["units"] = json!([]);
            }
            if attempt == "duplicate" {
                definition["description"] = json!("must not replace the original");
            }
            let kind = if attempt == "invalid-name" {
                "../new-battlefield"
            } else {
                "new-battlefield"
            };
            let peer = if attempt == "remote" {
                Ipv4Addr::new(192, 168, 1, 2)
            } else {
                Ipv4Addr::LOCALHOST
            };
            let origin = if attempt == "origin" {
                "http://example.com"
            } else {
                "http://localhost:8080"
            };
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(peer), 1234))
                .insert_header(("host", "localhost:8080"))
                .insert_header(("origin", origin))
                .set_json(
                    json!({"query": CREATE, "variables": {"kind": kind, "definition": definition}}),
                )
                .to_request();
            let body: Value = test::call_and_read_body_json(&app, request).await;
            if attempt == "create" {
                assert!(body.get("errors").is_none(), "{body}");
                assert_eq!(body["data"]["createMap"]["mapType"], json!(kind));
                let saved = fs::read_to_string(&destination)?;
                MapDefinition::parse(&saved)
                    .map_err(|error| error.to_string())?
                    .scenario()
                    .map_err(|error| error.to_string())?;
                let catalog = map_id::catalog_in(&directory).map_err(|error| error.to_string())?;
                assert_eq!(catalog.len(), 1);
                assert_eq!(
                    catalog
                        .first()
                        .ok_or("missing created map")?
                        .map_type
                        .as_str(),
                    kind
                );
                original = Some(saved);
            } else {
                assert!(body.get("errors").is_some(), "{attempt}: {body}");
                match &original {
                    Some(saved) => assert_eq!(&fs::read_to_string(&destination)?, saved),
                    None => assert!(!destination.exists()),
                }
            }
        }
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn saves_thumbnail_with_its_map_and_rejects_invalid_image_before_map_write()
    -> TestResult<()> {
        use base64::{Engine, engine::general_purpose::STANDARD};
        let root =
            std::env::temp_dir().join(format!("fightlines-map-image-{}", std::process::id()));
        let maps = root.join("maps");
        let frontend = root.join("public");
        fs::create_dir_all(&maps)?;
        fs::write(
            maps.join("custom-thumbnail.json"),
            include_str!("../maps/supply-point.json"),
        )?;
        fs::create_dir_all(&frontend)?;
        let app = test::init_service(
            App::new()
                .app_data(store())
                .app_data(web::Data::new(Editor {
                    directory: maps.clone(),
                    frontend: frontend.clone(),
                    writes: Mutex::new(()),
                }))
                .app_data(web::Data::new(crate::graphql::schema()))
                .route("/graphql", web::post().to(crate::graphql::handle)),
        )
        .await;
        let mut definition = json!({
            "description": "thumbnail fixture", "width": 2, "height": 2,
            "theme": "GREEN_FOREST", "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "PLAYER1", "kind": "INFANTRY", "direction": "EAST"},
                {"id": 2, "position": {"x": 1, "y": 1}, "playerNumber": "PLAYER2", "kind": "INFANTRY", "direction": "WEST"}
            ]
        });
        let query = "mutation Save($definition: MapDefinitionInput!, $thumbnail: String) { saveMap(mapType: \"custom-thumbnail\", definition: $definition, thumbnail: $thumbnail) { thumbnailUrl } }";
        let png = include_bytes!("../tests/fixtures/map-thumbnail.png");
        let mut saved_json = None;
        for valid in [true, false] {
            let thumbnail = if valid {
                STANDARD.encode(png)
            } else {
                STANDARD.encode(b"invalid PNG")
            };
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
                .insert_header(("host", "localhost:8080"))
                .insert_header(("origin", "http://localhost:8080"))
                .set_json(json!({"query": query, "variables": {"definition": definition, "thumbnail": thumbnail}}))
                .to_request();
            let body: Value = test::call_and_read_body_json(&app, request).await;
            if valid {
                assert!(body.get("errors").is_none(), "{body}");
                let path = body["data"]["saveMap"]["thumbnailUrl"]
                    .as_str()
                    .ok_or("missing thumbnail URL")?;
                assert_eq!(fs::read(frontend.join(path.trim_start_matches('/')))?, png);
                saved_json = Some(fs::read_to_string(maps.join("custom-thumbnail.json"))?);
                definition["description"] = json!("must not be saved");
            } else {
                assert!(body.get("errors").is_some(), "{body}");
                assert_eq!(
                    fs::read_to_string(maps.join("custom-thumbnail.json"))?,
                    saved_json.as_deref().ok_or("missing successful save")?
                );
            }
        }
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
