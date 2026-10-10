use crate::{
    lobby::{self, GameSnapshot, Snapshot, Store},
    lobby_id::LobbyId,
    map_type::MapType,
    session_token::SessionToken,
};
use actix_web::{HttpRequest, HttpResponse, web};
use juniper::{EmptySubscription, FieldResult, RootNode, graphql_object, http::GraphQLRequest};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

//----------------------------------------------------------------
// CONTEXT
//----------------------------------------------------------------

pub struct Context {
    pub store: Arc<Store>,
    identity: Mutex<Option<SessionToken>>,
    persist_identity: AtomicBool,
}

impl juniper::Context for Context {}

impl Context {
    pub fn identity(&self) -> Option<SessionToken> {
        self.identity
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone()
    }

    pub fn set_identity(&self, identity: SessionToken) {
        self.persist_identity.store(true, Ordering::Relaxed);
        *self
            .identity
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(identity);
    }
}

//----------------------------------------------------------------
// QUERIES
//----------------------------------------------------------------

pub struct Query;

#[graphql_object(context = Context)]
impl Query {
    fn health() -> bool {
        true
    }

    fn lobby(context: &Context, id: String) -> FieldResult<Snapshot> {
        lobby::get(context, LobbyId::from_token(id))
    }

    fn game(context: &Context, id: String) -> FieldResult<GameSnapshot> {
        lobby::game(context, LobbyId::from_token(id))
    }
}

//----------------------------------------------------------------
// MUTATIONS
//----------------------------------------------------------------

pub struct Mutation;

#[graphql_object(context = Context)]
impl Mutation {
    fn create_lobby(context: &Context, name: String, lobby_name: String) -> FieldResult<Snapshot> {
        lobby::create(context, &name, &lobby_name)
    }

    fn join_lobby(context: &Context, id: String, name: String) -> FieldResult<Snapshot> {
        lobby::join(context, LobbyId::from_token(id), &name)
    }

    fn set_lobby_map(context: &Context, id: String, map_type: MapType) -> FieldResult<Snapshot> {
        lobby::set_map_type(context, LobbyId::from_token(id), map_type)
    }

    fn submit_turn(
        context: &Context,
        id: String,
        turn_number: i32,
        orders: Vec<crate::turns::MoveOrderInput>,
    ) -> FieldResult<GameSnapshot> {
        lobby::submit_turn(context, LobbyId::from_token(id), turn_number, orders)
    }

    fn start_game(context: &Context, id: String) -> FieldResult<Snapshot> {
        lobby::start(context, LobbyId::from_token(id))
    }
}

//----------------------------------------------------------------
// SCHEMA
//----------------------------------------------------------------

pub type Schema = RootNode<Query, Mutation, EmptySubscription<Context>>;

pub fn schema() -> Schema {
    Schema::new(Query, Mutation, EmptySubscription::new())
}

//----------------------------------------------------------------
// HTTP
//----------------------------------------------------------------

pub async fn handle(
    request: HttpRequest,
    input: web::Json<GraphQLRequest>,
    store: web::Data<Store>,
    schema: web::Data<Schema>,
) -> HttpResponse {
    // Mutations in one document share the newly created browser identity.
    let original = SessionToken::from_request(&request);
    let context = Context {
        store: store.into_inner(),
        identity: Mutex::new(original),
        persist_identity: AtomicBool::new(false),
    };
    let result = input.execute_sync(&schema, &context);
    let mut response = HttpResponse::Ok();
    response.insert_header(("Cache-Control", "no-store"));
    if let Some(identity) = context
        .identity()
        .filter(|_| context.persist_identity.load(Ordering::Relaxed))
    {
        response.cookie(identity.cookie());
    }
    response.json(result)
}

//----------------------------------------------------------------
// SCHEMA EXPORT
//----------------------------------------------------------------

/// Export the real resolver schema without starting a server or mutating game state.
pub fn export_schema() -> std::io::Result<()> {
    let context = Context {
        store: Arc::new(Store::new(crate::seed::Seed::new([0; 32]))),
        identity: Mutex::new(None),
        persist_identity: AtomicBool::new(false),
    };
    let (data, errors) =
        juniper::introspect(&schema(), &context, juniper::IntrospectionFormat::All)
            .map_err(std::io::Error::other)?;
    if !errors.is_empty() {
        return Err(std::io::Error::other("Schema introspection failed"));
    }
    println!("{}", serde_json::json!({ "data": data }));
    Ok(())
}

//----------------------------------------------------------------
// TESTS
//----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{App, http::StatusCode, test};
    use serde_json::{Value, json};

    const FIELDS: &str = "id name mapType players { name isHost } isHost isMember gameUrl";

    #[actix_web::test]
    async fn development_game_is_opt_in_and_does_not_replace_identity() {
        let query = "{ game(id: \"00000000000000000000000000000000\") { id name isHost players { side isYou } movementRules { kind budget terrainCosts { terrain cost } } visibleTiles { x y } scenario { units { id side } depots { owner } } } }";
        for development in [false, true] {
            let seed = crate::seed::Seed::new([7; 32]);
            let store = if development {
                Store::development(seed).unwrap()
            } else {
                Store::new(seed)
            };
            let app = test::init_service(
                App::new()
                    .app_data(web::Data::new(store))
                    .app_data(web::Data::new(schema()))
                    .route("/graphql", web::post().to(handle)),
            )
            .await;
            for identity in [
                None,
                Some(SessionToken::from_token("existing-player".into())),
            ] {
                let mut request = test::TestRequest::post()
                    .uri("/graphql")
                    .set_json(json!({ "query": query }));
                if let Some(identity) = identity {
                    request = request.cookie(identity.cookie());
                }
                let response = test::call_service(&app, request.to_request()).await;
                assert!(response.response().cookies().next().is_none());
                let body: Value = test::read_body_json(response).await;
                if development {
                    assert!(body["errors"].is_null(), "{body}");
                    let game = &body["data"]["game"];
                    assert_eq!(game["movementRules"].as_array().unwrap().len(), 4);
                    assert_eq!(game["movementRules"][0]["budget"], 4);
                    assert_eq!(game["name"], "Test game");
                    assert_eq!(game["players"][0]["side"], "WEST");
                    assert_eq!(game["players"][0]["isYou"], true);
                    assert_eq!(game["players"][1]["side"], "EAST");
                    assert_eq!(game["players"][1]["isYou"], false);
                    assert_eq!(game["scenario"]["units"].as_array().unwrap().len(), 8);
                    assert!(
                        game["scenario"]["units"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .all(|unit| unit["side"] == "WEST")
                    );
                    assert!(!game["visibleTiles"].as_array().unwrap().is_empty());
                    assert_eq!(game["scenario"]["depots"].as_array().unwrap().len(), 3);
                } else {
                    assert!(body["errors"].is_array());
                }
            }
        }
    }

    #[actix_web::test]
    async fn lifecycle_and_authorization_over_graphql() {
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(crate::seed::Seed::new([7; 32]))))
                .app_data(web::Data::new(schema()))
                .route("/graphql", web::post().to(handle)),
        )
        .await;
        macro_rules! execute {
            ($query:expr, $cookie:expr) => {{
                let mut request = test::TestRequest::post().uri("/graphql")
                    .set_json(json!({ "query": $query }));
                if let Some(cookie) = $cookie { request = request.cookie(cookie); }
                let response = test::call_service(&app, request.to_request()).await;
                assert_eq!(response.status(), StatusCode::OK);
                assert_eq!(response.headers().get("Cache-Control").unwrap(), "no-store");
                let cookie = response.response().cookies().next().map(|cookie| cookie.into_owned());
                let body: Value = test::read_body_json(response).await;
                (body, cookie)
            }};
        }
        let (invalid, cookie) = execute!(
            format!(
                "mutation {{ createLobby(name: \"   \", lobbyName: \" Friday Night \" ) {{ {FIELDS} }} }}"
            ),
            None
        );
        assert!(
            invalid["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("40")
        );
        assert!(cookie.is_none());
        for lobby_name in ["   ".to_owned(), "x".repeat(41)] {
            let (invalid, cookie) = execute!(
                format!(
                    "mutation {{ createLobby(name: \"Chad\", lobbyName: \"{lobby_name}\") {{ {FIELDS} }} }}"
                ),
                None
            );
            assert!(
                invalid["errors"][0]["message"]
                    .as_str()
                    .unwrap()
                    .contains("lobby name")
            );
            assert!(cookie.is_none());
        }
        let (created, host) = execute!(
            format!(
                "mutation {{ createLobby(name: \" Chad \", lobbyName: \" Friday Night \" ) {{ {FIELDS} }} }}"
            ),
            None
        );
        let host = host.unwrap();
        assert_eq!(host.http_only(), Some(true));
        assert_eq!(created["data"]["createLobby"]["players"][0]["name"], "Chad");
        assert_eq!(created["data"]["createLobby"]["isHost"], true);
        assert_eq!(created["data"]["createLobby"]["name"], "Friday Night");
        assert!(created["data"]["createLobby"]["gameUrl"].is_null());
        let id = created["data"]["createLobby"]["id"].as_str().unwrap();
        let (visitor, _) = execute!(
            format!("{{ lobby(id: \"{id}\") {{ {FIELDS} }} health }}"),
            None
        );
        assert_eq!(visitor["data"]["lobby"]["name"], "Friday Night");
        assert_eq!(visitor["data"]["lobby"]["isMember"], false);
        assert_eq!(visitor["data"]["health"], true);
        let (early, _) = execute!(
            format!("{{ game(id: \"{id}\") {{ {FIELDS} }} }}"),
            Some(host.clone())
        );
        assert!(
            early["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("not started")
        );
        let (solo, _) = execute!(
            format!("mutation {{ startGame(id: \"{id}\") {{ id }} }}"),
            Some(host.clone())
        );
        assert!(
            solo["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("requires two players")
        );
        let (duplicate, _) = execute!(
            format!("mutation {{ joinLobby(id: \"{id}\", name: \"chad\") {{ {FIELDS} }} }}"),
            None
        );
        assert!(duplicate["errors"].is_array());
        let join =
            format!("mutation {{ joinLobby(id: \"{id}\", name: \"Walter\") {{ {FIELDS} }} }}");
        let (joined, guest) = execute!(&join, None);
        let guest = guest.unwrap();
        assert_eq!(
            joined["data"]["joinLobby"]["players"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(joined["data"]["joinLobby"]["isHost"], false);
        let (rejoined, _) = execute!(&join, Some(guest.clone()));
        assert_eq!(
            rejoined["data"]["joinLobby"]["players"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        let (full, cookie) = execute!(
            format!("mutation {{ joinLobby(id: \"{id}\", name: \"Third\") {{ id }} }}"),
            None
        );
        assert!(
            full["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("full")
        );
        assert!(cookie.is_none());
        let set_map = format!(
            "mutation {{ setLobbyMap(id: \"{id}\", mapType: SUPPLY_POINT) {{ {FIELDS} }} }}"
        );
        assert_eq!(created["data"]["createLobby"]["mapType"], "SUPPLY_POINT");
        for identity in [None, Some(guest.clone())] {
            let (denied, _) = execute!(&set_map, identity);
            assert!(
                denied["errors"][0]["message"]
                    .as_str()
                    .unwrap()
                    .contains("Only the host")
            );
        }
        let (configured, _) = execute!(&set_map, Some(host.clone()));
        assert_eq!(configured["data"]["setLobbyMap"]["mapType"], "SUPPLY_POINT");
        let (observed, _) = execute!(
            format!("{{ lobby(id: \"{id}\") {{ mapType }} }}"),
            Some(guest.clone())
        );
        assert_eq!(observed["data"]["lobby"]["mapType"], "SUPPLY_POINT");
        let (invalid_map, _) = execute!(
            format!("mutation {{ setLobbyMap(id: \"{id}\", mapType: UNKNOWN) {{ id }} }}"),
            Some(host.clone())
        );
        assert!(invalid_map["errors"].is_array());
        let (missing_map, _) = execute!(
            "mutation { setLobbyMap(id: \"missing\", mapType: SUPPLY_POINT) { id } }",
            Some(host.clone())
        );
        assert!(missing_map["errors"].is_array());
        let start = format!("mutation {{ startGame(id: \"{id}\") {{ {FIELDS} }} }}");
        for identity in [None, Some(guest.clone())] {
            let (denied, _) = execute!(&start, identity);
            assert!(denied["errors"].is_array());
        }
        for _ in 0..2 {
            let (started, _) = execute!(&start, Some(host.clone()));
            assert_eq!(
                started["data"]["startGame"]["gameUrl"],
                format!("/game/{id}")
            );
        }
        let (locked, _) = execute!(&set_map, Some(host.clone()));
        assert!(
            locked["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("already started")
        );
        let (polled, _) = execute!(
            format!("{{ lobby(id: \"{id}\") {{ {FIELDS} }} }}"),
            Some(host.clone())
        );
        assert_eq!(polled["data"]["lobby"]["gameUrl"], format!("/game/{id}"));
        let (late, _) = execute!(&join, None);
        assert!(
            late["errors"][0]["message"]
                .as_str()
                .unwrap()
                .contains("already started")
        );
        let game = format!(
            "{{ game(id: \"{id}\") {{ {FIELDS} visibleTiles {{ x y }} players {{ side isYou }} scenario {{ map {{ width height baseTile features {{ position {{ x y }} terrain }} }} depots {{ position {{ x y }} owner }} units {{ id side kind position {{ x y }} }} }} }} }}"
        );
        let (member, _) = execute!(&game, Some(guest.clone()));
        assert_eq!(member["data"]["game"]["name"], "Friday Night");
        assert_eq!(member["data"]["game"]["mapType"], "SUPPLY_POINT");
        assert_eq!(member["data"]["game"]["isMember"], true);
        let scenario = &member["data"]["game"]["scenario"];
        assert_eq!(scenario["map"]["width"], 17);
        assert_eq!(scenario["map"]["height"], 17);
        assert_eq!(scenario["map"]["baseTile"], "GRASS_PLAIN");
        assert_eq!(scenario["map"]["features"].as_array().unwrap().len(), 102);
        assert_eq!(scenario["depots"].as_array().unwrap().len(), 3);
        assert_eq!(scenario["units"].as_array().unwrap().len(), 8);
        assert_eq!(member["data"]["game"]["players"][0]["side"], "WEST");
        assert_eq!(member["data"]["game"]["players"][1]["side"], "EAST");
        assert_eq!(member["data"]["game"]["players"][1]["isYou"], true);
        let (host_view, _) = execute!(&game, Some(host.clone()));
        let host_scenario = &host_view["data"]["game"]["scenario"];
        assert_eq!(host_scenario["map"], scenario["map"]);
        assert!(
            scenario["units"]
                .as_array()
                .unwrap()
                .iter()
                .all(|unit| unit["side"] == "EAST")
        );
        assert!(
            host_scenario["units"]
                .as_array()
                .unwrap()
                .iter()
                .all(|unit| unit["side"] == "WEST")
        );
        assert_ne!(
            host_view["data"]["game"]["visibleTiles"],
            member["data"]["game"]["visibleTiles"]
        );
        assert_eq!(host_view["data"]["game"]["players"][0]["isYou"], true);
        let (outsider, _) = execute!(&game, None);
        assert!(outsider["errors"].is_array());
        let (reconnected, _) = execute!(&join, Some(guest.clone()));
        assert_eq!(
            reconnected["data"]["joinLobby"]["gameUrl"],
            format!("/game/{id}")
        );
        let (missing, _) = execute!("{ lobby(id: \"missing\") { id } }", None);
        assert!(missing["errors"].is_array());
        let (unknown, cookie) = execute!(
            "mutation { createLobby(name: \"Other\", lobbyName: \" Friday Night \" ) { unknownField } }",
            None
        );
        assert!(unknown["errors"].is_array());
        assert!(cookie.is_none());
        let (multiple, cookie) = execute!(
            "mutation { a: createLobby(name: \"One\", lobbyName: \" Friday Night \" ) { id isHost } b: createLobby(name: \"Two\", lobbyName: \" Friday Night \" ) { id isHost } }",
            None
        );
        let cookie = cookie.unwrap();
        for alias in ["a", "b"] {
            let id = multiple["data"][alias]["id"].as_str().unwrap();
            let (owner, _) = execute!(
                format!("{{ lobby(id: \"{id}\") {{ isHost }} }}"),
                Some(cookie.clone())
            );
            assert_eq!(owner["data"]["lobby"]["isHost"], true);
        }
        let submit = |side: &str| {
            let own_scenario = if side == "WEST" {
                host_scenario
            } else {
                scenario
            };
            let orders = own_scenario["units"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|unit| unit["side"] == side)
                .map(|unit| {
                    format!(
                        "{{unitId: \"{}\", path: [{{x: {}, y: {}}}]}}",
                        unit["id"].as_str().unwrap(),
                        unit["position"]["x"],
                        unit["position"]["y"]
                    )
                })
                .collect::<Vec<_>>()
                .join(",");
            format!(
                "mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: [{orders}]) {{ turnNumber submitted opponentSubmitted lastResolution {{ turnNumber events {{ kind unitId }} }} }} }}"
            )
        };
        for identity in [None, Some(cookie.clone())] {
            let (denied, _) = execute!(submit("WEST"), identity);
            assert!(denied["errors"].is_array());
        }
        let (foreign, _) = execute!(submit("EAST"), Some(host.clone()));
        assert!(foreign["errors"].is_array());
        let (submitted, _) = execute!(submit("WEST"), Some(host.clone()));
        assert_eq!(submitted["data"]["submitTurn"]["turnNumber"], 1);
        assert_eq!(submitted["data"]["submitTurn"]["submitted"], true);
        let turn_query =
            format!("{{ game(id: \"{id}\") {{ turnNumber submitted opponentSubmitted }} }}");
        let (waiting, _) = execute!(&turn_query, Some(guest.clone()));
        assert_eq!(waiting["data"]["game"]["opponentSubmitted"], true);
        assert_eq!(waiting["data"]["game"]["submitted"], false);
        let (retry, _) = execute!(submit("WEST"), Some(host.clone()));
        assert_eq!(retry["data"]["submitTurn"]["turnNumber"], 1);
        let (resolved, _) = execute!(submit("EAST"), Some(guest));
        assert_eq!(resolved["data"]["submitTurn"]["turnNumber"], 2);
        assert_eq!(resolved["data"]["submitTurn"]["submitted"], false);
        assert_eq!(
            resolved["data"]["submitTurn"]["lastResolution"]["events"]
                .as_array()
                .unwrap()
                .len(),
            8
        );
        let (stale, _) = execute!(submit("WEST"), Some(host));
        assert!(stale["errors"].is_array());
        let old = test::TestRequest::get().uri("/api/health").to_request();
        assert_eq!(
            test::call_service(&app, old).await.status(),
            StatusCode::NOT_FOUND
        );
    }
}
