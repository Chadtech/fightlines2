//! Map authoring resolvers. Filesystem access is enabled only with --map-editor.
use crate::{
    graphql::Context,
    map::{Coordinate, MapTheme, TerrainValue},
    map_definition::{DepotPlacement, MapDefinition, TerrainPlacement, UnitPlacement},
    map_type::{MAPS, MapType},
    scenario::{DepotKind, Direction, PlayerNumber, UnitKind},
};
use actix_files::NamedFile;
use actix_web::{HttpRequest, web};
use juniper::{FieldResult, GraphQLInputObject, GraphQLObject, graphql_object};
use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
};

pub struct Editor {
    pub directory: PathBuf,
    pub index: PathBuf,
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

    fn write(&self) -> FieldResult<&Editor> {
        let editor = self.read()?;
        match self {
            Self::Writable(_) => Ok(editor),
            _ => Err("save maps from the localhost editor".into()),
        }
    }
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct NamedMap {
    map_type: MapType,
    definition: MapDefinition,
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct MapCatalog {
    first: NamedMap,
    rest: Vec<NamedMap>,
}

#[graphql_object(context = Context)]
impl MapDefinition {
    fn width(&self) -> i32 {
        i32::from(self.width)
    }
    fn height(&self) -> i32 {
        i32::from(self.height)
    }
    fn theme(&self) -> MapTheme {
        self.theme
    }
    fn features(&self) -> &[TerrainPlacement] {
        &self.features
    }
    fn depots(&self) -> &[DepotPlacement] {
        &self.depots
    }
    fn units(&self) -> &[UnitPlacement] {
        &self.units
    }
}

#[graphql_object(context = Context)]
impl TerrainPlacement {
    fn position(&self) -> Coordinate {
        self.position
    }
    fn terrain(&self) -> TerrainValue {
        self.terrain.into()
    }
}
#[graphql_object(context = Context)]
impl DepotPlacement {
    fn position(&self) -> Coordinate {
        self.position
    }
    fn kind(&self) -> DepotKind {
        self.kind
    }
}
#[graphql_object(context = Context)]
impl UnitPlacement {
    fn id(&self) -> i32 {
        i32::from(self.id)
    }
    fn position(&self) -> Coordinate {
        self.position
    }
    fn player_number(&self) -> PlayerNumber {
        self.player_number
    }
    fn kind(&self) -> UnitKind {
        self.kind
    }
    fn direction(&self) -> Option<Direction> {
        self.direction
    }
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
    kind: DepotKind,
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
    let mut maps = Vec::new();
    for (map_type, name) in MAPS {
        let json = fs::read_to_string(editor.directory.join(format!("{name}.json")))?;
        let definition = MapDefinition::parse(&json).map_err(|error| error.to_string())?;
        maps.push(NamedMap {
            map_type,
            definition,
        });
    }
    let mut maps = maps.into_iter();
    let first = maps.next().ok_or("no editable maps were returned")?;
    Ok(MapCatalog {
        first,
        rest: maps.collect(),
    })
}

pub fn save_map(
    context: &Context,
    map_type: MapType,
    definition: MapDefinitionInput,
) -> FieldResult<NamedMap> {
    let editor = context.editor.write()?;
    let name = MAPS
        .iter()
        .find(|(kind, _)| *kind == map_type)
        .map(|(_, name)| *name)
        .ok_or("unknown map")?;
    let definition = definition.definition()?;
    definition
        .scenario()
        .map_err(|error| format!("invalid map: {error}"))?;
    let json = serde_json::to_string_pretty(&definition)? + "\n";
    let _guard = editor.writes.lock().map_err(|error| error.to_string())?;
    let destination = editor.directory.join(format!("{name}.json"));
    let temporary = destination.with_extension("json.tmp");
    fs::write(&temporary, json)?;
    fs::rename(&temporary, &destination)?;
    Ok(NamedMap {
        map_type,
        definition,
    })
}

pub fn configure(config: &mut web::ServiceConfig, enabled: bool) {
    if enabled {
        config.route("/map-editor", web::get().to(page));
    }
}

fn local_request(request: &HttpRequest) -> bool {
    request
        .peer_addr()
        .is_some_and(|peer| peer.ip().is_loopback())
}
pub async fn page(request: HttpRequest, editor: web::Data<Editor>) -> actix_web::Result<NamedFile> {
    if !local_request(&request) {
        return Err(actix_web::error::ErrorForbidden(
            "map editing requires localhost",
        ));
    }
    Ok(NamedFile::open(&editor.index)?)
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

    const SAVE: &str = "mutation Save($definition: MapDefinitionInput!, $kind: MapType!) { saveMap(mapType: $kind, definition: $definition) { mapType definition { theme width } } }";

    fn store() -> web::Data<crate::lobby::Store> {
        web::Data::new(crate::lobby::Store::new(crate::seed::Seed::new([0; 32])))
    }
    fn editor(directory: PathBuf) -> web::Data<Editor> {
        web::Data::new(Editor {
            directory,
            index: PathBuf::new(),
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
                .route("/graphql", web::post().to(crate::graphql::handle))
                .configure(|config| configure(config, false)),
        )
        .await;
        let valid = graphql_definition()?;
        for query in ["{ maps { first { mapType } } }", SAVE] {
            let request = test::TestRequest::post()
                .uri("/graphql")
                .peer_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
                .insert_header(("host", "localhost:8080"))
                .insert_header(("origin", "http://localhost:8080"))
                .set_json(
                    json!({"query":query,"variables":{"kind":"SUPPLY_POINT","definition":valid}}),
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
        let request = test::TestRequest::get().uri("/map-editor").to_request();
        assert_eq!(
            test::call_service(&app, request).await.status(),
            StatusCode::NOT_FOUND
        );
        Ok(())
    }

    #[actix_web::test]
    async fn shared_endpoint_keeps_game_queries_available_and_checks_editor_reads() {
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
                "{ health maps { first { mapType definition { width units { playerNumber direction } } } rest { mapType } } }",
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
                    Some(MAPS.len() - 1)
                );
                assert_eq!(body["data"]["health"], json!(true));
            } else if !success {
                assert_eq!(
                    body["errors"][0]["message"],
                    json!("map editing requires localhost")
                );
            }
        }
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
            let mut kind = "SUPPLY_POINT";
            match failure {
                "width" => definition["width"] = json!(-1),
                "negative-position" => definition["units"][0]["position"]["x"] = json!(-1),
                "id" => definition["units"][0]["id"] = json!(0),
                "direction" => definition["units"][0]["direction"] = Value::Null,
                "unknown-map" => kind = "UNKNOWN",
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
        definition["theme"] = json!("SNOW");
        let request = test::TestRequest::post()
            .uri("/graphql")
            .peer_addr(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1234))
            .insert_header(("host", "localhost:8080"))
            .insert_header(("origin", "http://localhost:8080"))
            .set_json(
                json!({"query":SAVE,"variables":{"kind":"SUPPLY_POINT","definition":definition}}),
            )
            .to_request();
        let body: Value = test::call_and_read_body_json(&app, request).await;
        assert!(body.get("errors").is_none(), "{body}");
        let saved: Value = serde_json::from_str(&fs::read_to_string(&destination)?)?;
        assert_eq!(saved["theme"], json!("Snow"));
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
}
