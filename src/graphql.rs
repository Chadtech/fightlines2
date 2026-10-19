use crate::{
    lobby::{self, GameSnapshot, Snapshot, Store},
    lobby_id::LobbyId,
    map_editor,
    map_type::MapType,
    scenario::PlayerNumber,
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
    pub editor: map_editor::Access,
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
    fn maps(context: &Context) -> FieldResult<map_editor::MapCatalog> {
        map_editor::maps(context)
    }

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
    fn save_map(
        context: &Context,
        map_type: MapType,
        definition: map_editor::MapDefinitionInput,
    ) -> FieldResult<map_editor::NamedMap> {
        map_editor::save_map(context, map_type, definition)
    }

    fn create_lobby(context: &Context, name: String, lobby_name: String) -> FieldResult<Snapshot> {
        lobby::create(context, &name, &lobby_name)
    }

    fn join_lobby(context: &Context, id: String, name: String) -> FieldResult<Snapshot> {
        lobby::join(context, LobbyId::from_token(id), &name)
    }

    fn set_lobby_map(context: &Context, id: String, map_type: MapType) -> FieldResult<Snapshot> {
        lobby::set_map_type(context, LobbyId::from_token(id), map_type)
    }

    fn set_lobby_opponent(
        context: &Context,
        id: String,
        opponent: lobby::Opponent,
    ) -> FieldResult<Snapshot> {
        lobby::set_opponent(context, LobbyId::from_token(id), opponent)
    }

    fn set_lobby_side(
        context: &Context,
        id: String,
        player_number: PlayerNumber,
    ) -> FieldResult<Snapshot> {
        lobby::set_player_number(context, LobbyId::from_token(id), player_number)
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
    editor: Option<web::Data<map_editor::Editor>>,
    schema: web::Data<Schema>,
) -> HttpResponse {
    // Mutations in one document share the newly created browser identity.
    let original = SessionToken::from_request(&request);
    let context = Context {
        store: store.into_inner(),
        editor: map_editor::Access::from_request(editor, &request),
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
        editor: map_editor::Access::Disabled,
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
    use crate::{
        map::MapTheme,
        map_definition::MapDefinition,
        scenario::PlayerNumber,
        test_support::{FixtureValue, TestResult},
        visibility,
    };
    use actix_web::{App, http::StatusCode, test};
    use serde_json::{Value, json};

    const FIELDS: &str = "id name mapType players { name isHost } isHost isMember gameUrl";

    #[actix_web::test]
    async fn ai_lobby_authorization_and_turns_over_graphql() -> TestResult<()> {
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(crate::seed::Seed::new([19; 32]))))
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
                let cookie = response.response().cookies().next().map(|cookie| cookie.into_owned());
                let body: Value = test::read_body_json(response).await;
                (body, cookie)
            }};
        }
        let (created, host) = execute!(
            "mutation { createLobby(name: \"Host\", lobbyName: \"AI match\") { id } }",
            None
        );
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let ai = format!(
            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: AI) {{ players {{ name isAi }} isMember }} }}"
        );
        let (denied, _) = execute!(&ai, None);
        assert!(denied["errors"].is_array());
        let (selected, _) = execute!(&ai, host.clone());
        assert!(selected.get("errors").is_none(), "{selected}");
        assert_eq!(
            selected["data"]["setLobbyOpponent"]["players"][1]["isAi"],
            true
        );
        for (choice, expected) in [
            ("AI_MEDIUM", "AI_MEDIUM"),
            ("AI", "AI"),
            ("AI_MEDIUM", "AI_MEDIUM"),
        ] {
            let (updated, _) = execute!(
                format!(
                    "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: {choice}) {{ players {{ opponent isAi }} }} }}"
                ),
                host.clone()
            );
            assert!(updated.get("errors").is_none(), "{updated}");
            assert_eq!(
                updated["data"]["setLobbyOpponent"]["players"][0]["opponent"],
                "HUMAN"
            );
            assert_eq!(
                updated["data"]["setLobbyOpponent"]["players"][1]["opponent"],
                expected
            );
        }
        let (public, _) = execute!(
            format!("{{ lobby(id: \"{id}\") {{ isMember isHost }} }}"),
            None
        );
        assert_eq!(public["data"]["lobby"]["isMember"], false);
        let join = format!("mutation {{ joinLobby(id: \"{id}\", name: \"Guest\") {{ id }} }}");
        let (full, _) = execute!(&join, None);
        assert!(full["errors"].is_array());
        let human = format!(
            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: HUMAN) {{ players {{ isAi }} }} }}"
        );
        let (cleared, _) = execute!(&human, host.clone());
        assert_eq!(
            cleared["data"]["setLobbyOpponent"]["players"]
                .as_array()
                .fixture()?
                .len(),
            1
        );
        let medium = ai.replace("opponent: AI", "opponent: AI_MEDIUM");
        let (selected, _) = execute!(&medium, host.clone());
        assert!(selected.get("errors").is_none());
        let (started, _) = execute!(
            format!("mutation {{ startGame(id: \"{id}\") {{ gameUrl }} }}"),
            host.clone()
        );
        assert!(started.get("errors").is_none(), "{started}");
        let (late, _) = execute!(&human, host.clone());
        assert!(late["errors"].is_array());
        let game_query = format!(
            "{{ game(id: \"{id}\") {{ turnNumber submitted players {{ isYou isAi opponent }} scenario {{ units {{ id playerNumber location {{ ... on OnMap {{ position {{ x y }} }} }} }} }} }} }}"
        );
        let (game, _) = execute!(&game_query, host.clone());
        assert_eq!(game["data"]["game"]["players"][1]["isAi"], true);
        assert_eq!(game["data"]["game"]["players"][1]["opponent"], "AI_MEDIUM");
        assert_eq!(game["data"]["game"]["players"][1]["isYou"], false);
        for number in 1..=3 {
            let (game, _) = execute!(&game_query, host.clone());
            let orders: Vec<String> = game["data"]["game"]["scenario"]["units"]
                .as_array()
                .fixture()?
                .iter()
                .filter(|unit| unit["playerNumber"] == "PLAYER1")
                .filter_map(|unit| {
                    let id = unit["id"].as_str()?;
                    let position = &unit["location"]["position"];
                    Some(format!(
                        "{{ unitId: \"{id}\", path: [{{ x: {}, y: {} }}] }}",
                        position["x"], position["y"]
                    ))
                })
                .collect();
            if number == 1 {
                let (invalid, _) = execute!(
                    format!(
                        "mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: []) {{ turnNumber }} }}"
                    ),
                    host.clone()
                );
                assert!(invalid["errors"].is_array());
                let (unchanged, _) = execute!(&game_query, host.clone());
                assert_eq!(unchanged["data"]["game"]["turnNumber"], 1);
                assert_eq!(unchanged["data"]["game"]["submitted"], false);
            }
            let (result, _) = execute!(
                format!(
                    "mutation {{ submitTurn(id: \"{id}\", turnNumber: {number}, orders: [{}]) {{ turnNumber submitted lastResolution {{ turnNumber }} }} }}",
                    orders.join(",")
                ),
                host.clone()
            );
            assert!(result.get("errors").is_none(), "{result}");
            assert_eq!(result["data"]["submitTurn"]["turnNumber"], number + 1);
            assert_eq!(result["data"]["submitTurn"]["submitted"], false);
        }
        // A joined human retains the slot when the host attempts to select AI.
        let (created, _) = execute!(
            "mutation { createLobby(name: \"Host\", lobbyName: \"Human match\") { id } }",
            host.clone()
        );
        let other_id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        let (joined, guest) = execute!(
            format!("mutation {{ joinLobby(id: \"{other_id}\", name: \"Guest\") {{ id }} }}"),
            None
        );
        assert!(joined.get("errors").is_none());
        let change = format!(
            "mutation {{ setLobbyOpponent(id: \"{other_id}\", opponent: AI_MEDIUM) {{ id }} }}"
        );
        for cookie in [host, guest] {
            let (denied, _) = execute!(&change, cookie);
            assert!(denied["errors"].is_array());
        }
        Ok(())
    }

    #[actix_web::test]
    async fn side_selection_preserves_identity_fog_and_turn_ownership() -> TestResult<()> {
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(crate::seed::Seed::new([23; 32]))))
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
                let cookie = response.response().cookies().next().map(|cookie| cookie.into_owned());
                let body: Value = test::read_body_json(response).await;
                (body, cookie)
            }};
        }
        let roster = "players { name isHost isYou isAi playerNumber opponent } isHost isMember";
        let (outsider, outsider_cookie) = execute!(
            "mutation { createLobby(name: \"Outsider\", lobbyName: \"Other\") { id } }",
            None
        );
        assert!(outsider.get("errors").is_none());
        for ai in [false, true] {
            for host_side in [PlayerNumber::Player1, PlayerNumber::Player2] {
                let side = match host_side {
                    PlayerNumber::Player1 => "PLAYER1",
                    PlayerNumber::Player2 => "PLAYER2",
                };
                let other_side = match host_side {
                    PlayerNumber::Player1 => "PLAYER2",
                    PlayerNumber::Player2 => "PLAYER1",
                };
                let (created, host) = execute!(
                    "mutation { createLobby(name: \"Host\", lobbyName: \"Choose sides\") { id } }",
                    None
                );
                let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
                let choose = format!(
                    "mutation {{ setLobbySide(id: \"{id}\", playerNumber: {side}) {{ {roster} }} }}"
                );
                for cookie in [None, outsider_cookie.clone()] {
                    let (denied, _) = execute!(&choose, cookie);
                    assert!(denied["errors"].is_array(), "{denied}");
                }
                // Choosing before an opponent arrives leaves the opposite side open.
                let (chosen, _) = execute!(&choose, host.clone());
                assert!(chosen.get("errors").is_none(), "{chosen}");
                assert_eq!(
                    chosen["data"]["setLobbySide"]["players"][0]["playerNumber"],
                    side
                );
                assert_eq!(chosen["data"]["setLobbySide"]["players"][0]["isYou"], true);
                assert_eq!(chosen["data"]["setLobbySide"]["isHost"], true);
                let guest = if ai {
                    let (selected, _) = execute!(
                        format!(
                            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: AI_MEDIUM) {{ {roster} }} }}"
                        ),
                        host.clone()
                    );
                    assert!(selected.get("errors").is_none(), "{selected}");
                    assert_eq!(
                        selected["data"]["setLobbyOpponent"]["players"][1]["playerNumber"],
                        other_side
                    );
                    assert_eq!(
                        selected["data"]["setLobbyOpponent"]["players"][1]["isYou"],
                        false
                    );
                    assert_eq!(
                        selected["data"]["setLobbyOpponent"]["players"][1]["opponent"],
                        "AI_MEDIUM"
                    );
                    // AI removal and replacement must retain the host's chosen side.
                    let (removed, _) = execute!(
                        format!(
                            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: HUMAN) {{ {roster} }} }}"
                        ),
                        host.clone()
                    );
                    assert_eq!(
                        removed["data"]["setLobbyOpponent"]["players"][0]["playerNumber"],
                        side
                    );
                    assert_eq!(
                        removed["data"]["setLobbyOpponent"]["players"]
                            .as_array()
                            .fixture()?
                            .len(),
                        1
                    );
                    let (selected, _) = execute!(
                        format!(
                            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: AI_MEDIUM) {{ id }} }}"
                        ),
                        host.clone()
                    );
                    assert!(selected.get("errors").is_none(), "{selected}");
                    None
                } else {
                    let (joined, guest) = execute!(
                        format!(
                            "mutation {{ joinLobby(id: \"{id}\", name: \"Guest\") {{ {roster} }} }}"
                        ),
                        None
                    );
                    assert!(joined.get("errors").is_none(), "{joined}");
                    assert_eq!(
                        joined["data"]["joinLobby"]["players"][1]["playerNumber"],
                        other_side
                    );
                    assert_eq!(joined["data"]["joinLobby"]["players"][1]["isYou"], true);
                    // A guest can swap both occupied sides, without acquiring host rights.
                    let (swapped, _) = execute!(&choose, guest.clone());
                    assert!(swapped.get("errors").is_none(), "{swapped}");
                    assert_eq!(
                        swapped["data"]["setLobbySide"]["players"][0]["playerNumber"],
                        other_side
                    );
                    assert_eq!(
                        swapped["data"]["setLobbySide"]["players"][1]["playerNumber"],
                        side
                    );
                    assert_eq!(swapped["data"]["setLobbySide"]["isHost"], false);
                    let (rejoined, _) = execute!(
                        format!(
                            "mutation {{ joinLobby(id: \"{id}\", name: \"Guest\") {{ {roster} }} }}"
                        ),
                        guest.clone()
                    );
                    assert_eq!(
                        rejoined["data"]["joinLobby"]["players"][1]["playerNumber"],
                        side
                    );
                    for query in [
                        format!("mutation {{ startGame(id: \"{id}\") {{ id }} }}"),
                        format!(
                            "mutation {{ setLobbyMap(id: \"{id}\", mapType: SUPPLY_POINT) {{ id }} }}"
                        ),
                        format!(
                            "mutation {{ setLobbyOpponent(id: \"{id}\", opponent: AI_MEDIUM) {{ id }} }}"
                        ),
                    ] {
                        let (denied, _) = execute!(&query, guest.clone());
                        assert!(denied["errors"].is_array(), "{denied}");
                    }
                    guest
                };
                // Restore the requested assignment, then repeat to check idempotence.
                for _ in 0..2 {
                    let (chosen, _) = execute!(&choose, host.clone());
                    assert_eq!(
                        chosen["data"]["setLobbySide"]["players"][0]["playerNumber"],
                        side
                    );
                    assert_eq!(
                        chosen["data"]["setLobbySide"]["players"][1]["playerNumber"],
                        other_side
                    );
                    if ai {
                        assert_eq!(
                            chosen["data"]["setLobbySide"]["players"][1]["opponent"],
                            "AI_MEDIUM"
                        );
                    }
                }
                let (started, _) = execute!(
                    format!("mutation {{ startGame(id: \"{id}\") {{ gameUrl }} }}"),
                    host.clone()
                );
                assert!(started.get("errors").is_none(), "{started}");
                let (late, _) = execute!(&choose, host.clone());
                assert!(late["errors"].is_array());
                let game_query = format!(
                    "{{ game(id: \"{id}\") {{ turnNumber submitted opponentSubmitted {roster} visibleTiles {{ x y }} scenario {{ units {{ id playerNumber }} }} lastResolution {{ reports {{ playerNumber }} }} }} }}"
                );
                let expected = crate::map_type::MapType::default().scenario().fixture()?;
                let (game, _) = execute!(&game_query, host.clone());
                assert!(game.get("errors").is_none(), "{game}");
                assert_eq!(game["data"]["game"]["players"][0]["playerNumber"], side);
                assert_eq!(game["data"]["game"]["players"][0]["isYou"], true);
                let visible = visibility::visible_tiles(&expected, host_side);
                let expected_tiles: Vec<_> = visible
                    .iter()
                    .map(|position| json!({"x":position.x(),"y":position.y()}))
                    .collect();
                assert_eq!(game["data"]["game"]["visibleTiles"], json!(expected_tiles));
                let observed = visibility::observed_scenario(&expected, host_side, &visible);
                let expected_ids: Vec<_> =
                    observed.units.iter().map(|unit| json!(unit.id())).collect();
                let actual_ids: Vec<_> = game["data"]["game"]["scenario"]["units"]
                    .as_array()
                    .fixture()?
                    .iter()
                    .map(|unit| unit["id"].clone())
                    .collect();
                assert_eq!(actual_ids, expected_ids);
                let hold_orders = |player: PlayerNumber| -> TestResult<String> {
                    expected
                        .units
                        .iter()
                        .filter(|unit| unit.player_number() == player)
                        .map(|unit| {
                            let position = unit.board_position().fixture()?;
                            Ok(format!(
                                "{{ unitId: \"{}\", path: [{{x: {}, y: {}}}] }}",
                                unit.id(),
                                position.x(),
                                position.y()
                            ))
                        })
                        .collect::<TestResult<Vec<_>>>()
                        .map(|orders| orders.join(","))
                };
                let opponent_side = match host_side {
                    PlayerNumber::Player1 => PlayerNumber::Player2,
                    PlayerNumber::Player2 => PlayerNumber::Player1,
                };
                let submit = |orders: &str| {
                    format!(
                        "mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: [{orders}]) {{ turnNumber submitted opponentSubmitted }} }}"
                    )
                };
                let (foreign, _) = execute!(submit(&hold_orders(opponent_side)?), host.clone());
                assert!(foreign["errors"].is_array());
                let (unchanged, _) = execute!(&game_query, host.clone());
                assert_eq!(unchanged["data"]["game"]["submitted"], false);
                assert_eq!(unchanged["data"]["game"]["opponentSubmitted"], false);
                let (submitted, _) = execute!(submit(&hold_orders(host_side)?), host.clone());
                assert!(submitted.get("errors").is_none(), "{submitted}");
                if !ai {
                    assert_eq!(submitted["data"]["submitTurn"]["submitted"], true);
                    let (waiting, _) = execute!(&game_query, guest.clone());
                    assert_eq!(waiting["data"]["game"]["submitted"], false);
                    assert_eq!(waiting["data"]["game"]["opponentSubmitted"], true);
                    let (resolved, _) =
                        execute!(submit(&hold_orders(opponent_side)?), guest.clone());
                    assert!(resolved.get("errors").is_none(), "{resolved}");
                    assert_eq!(resolved["data"]["submitTurn"]["turnNumber"], 2);
                } else {
                    assert_eq!(submitted["data"]["submitTurn"]["turnNumber"], 2);
                }
                let (reconnected, _) = execute!(&game_query, host.clone());
                assert_eq!(reconnected["data"]["game"]["turnNumber"], 2);
                assert_eq!(reconnected["data"]["game"]["submitted"], false);
                assert_eq!(
                    reconnected["data"]["game"]["players"][0]["playerNumber"],
                    side
                );
                let reports = reconnected["data"]["game"]["lastResolution"]["reports"]
                    .as_array()
                    .fixture()?;
                assert_eq!(reports.len(), 1);
                assert_eq!(reports[0]["playerNumber"], side);
            }
        }
        Ok(())
    }

    #[actix_web::test]
    async fn development_game_is_opt_in_and_does_not_replace_identity() -> TestResult<()> {
        let query = "{ game(id: \"00000000000000000000000000000000\") { id name isHost players { playerNumber isYou } movementRules { kind budget terrainCosts { terrain cost } } visibleTiles { x y } scenario { units { id playerNumber } depots { position { x y } } } } }";
        for development in [false, true] {
            let seed = crate::seed::Seed::new([7; 32]);
            let store = if development {
                Store::development(seed).fixture()?
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
                    assert_eq!(game["movementRules"].as_array().fixture()?.len(), 4);
                    assert_eq!(game["movementRules"][0]["budget"], 4);
                    assert_eq!(game["name"], "Test game");
                    assert_eq!(game["players"][0]["playerNumber"], "PLAYER1");
                    assert_eq!(game["players"][0]["isYou"], true);
                    assert_eq!(game["players"][1]["playerNumber"], "PLAYER2");
                    assert_eq!(game["players"][1]["isYou"], false);
                    assert_eq!(game["scenario"]["units"].as_array().fixture()?.len(), 8);
                    assert!(
                        game["scenario"]["units"]
                            .as_array()
                            .fixture()?
                            .iter()
                            .all(|unit| unit["playerNumber"] == "PLAYER1")
                    );
                    assert!(!game["visibleTiles"].as_array().fixture()?.is_empty());
                    assert_eq!(game["scenario"]["depots"].as_array().fixture()?.len(), 3);
                } else {
                    assert!(body["errors"].is_array());
                }
            }
        }

        Ok(())
    }

    #[actix_web::test]
    async fn lifecycle_and_authorization_over_graphql() -> TestResult<()> {
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
                assert_eq!(response.headers().get("Cache-Control").fixture()?, "no-store");
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
                .fixture()?
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
                    .fixture()?
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
        let host = host.fixture()?;
        assert_eq!(host.http_only(), Some(true));
        assert_eq!(created["data"]["createLobby"]["players"][0]["name"], "Chad");
        assert_eq!(created["data"]["createLobby"]["isHost"], true);
        assert_eq!(created["data"]["createLobby"]["name"], "Friday Night");
        assert!(created["data"]["createLobby"]["gameUrl"].is_null());
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
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
                .fixture()?
                .contains("not started")
        );
        let (solo, _) = execute!(
            format!("mutation {{ startGame(id: \"{id}\") {{ id }} }}"),
            Some(host.clone())
        );
        assert!(
            solo["errors"][0]["message"]
                .as_str()
                .fixture()?
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
        let guest = guest.fixture()?;
        assert_eq!(
            joined["data"]["joinLobby"]["players"]
                .as_array()
                .fixture()?
                .len(),
            2
        );
        assert_eq!(joined["data"]["joinLobby"]["isHost"], false);
        let (rejoined, _) = execute!(&join, Some(guest.clone()));
        assert_eq!(
            rejoined["data"]["joinLobby"]["players"]
                .as_array()
                .fixture()?
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
                .fixture()?
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
                    .fixture()?
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
                .fixture()?
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
                .fixture()?
                .contains("already started")
        );
        let game = format!(
            "{{ game(id: \"{id}\") {{ {FIELDS} visibleTiles {{ x y }} players {{ playerNumber isYou }} scenario {{ map {{ width height baseTile theme features {{ position {{ x y }} terrain }} }} depots {{ position {{ x y }} }} units {{ id playerNumber kind location {{ __typename ... on OnMap {{ position {{ x y }} }} ... on Aboard {{ carrierId }} }} }} }} }} }}"
        );
        let (member, _) = execute!(&game, Some(guest.clone()));
        assert_eq!(member["data"]["game"]["name"], "Friday Night");
        assert_eq!(member["data"]["game"]["mapType"], "SUPPLY_POINT");
        assert_eq!(member["data"]["game"]["isMember"], true);
        let scenario = &member["data"]["game"]["scenario"];
        let definition =
            MapDefinition::parse(include_str!("../maps/supply-point.json")).fixture()?;
        let expected = definition.scenario().fixture()?;
        let expected_theme = match definition.theme {
            MapTheme::GreenForest => "GREEN_FOREST",
            MapTheme::Desert => "DESERT",
            MapTheme::Snow => "SNOW",
        };
        assert_eq!(scenario["map"]["width"], definition.width);
        assert_eq!(scenario["map"]["height"], definition.height);
        assert_eq!(scenario["map"]["baseTile"], "PLAIN");
        assert_eq!(scenario["map"]["theme"], expected_theme);
        assert_eq!(
            scenario["map"]["features"].as_array().fixture()?.len(),
            definition.features.len()
        );
        assert_eq!(
            scenario["depots"].as_array().fixture()?.len(),
            definition.depots.len()
        );
        assert!(scenario["units"].as_array().fixture()?.iter().all(|unit| {
            unit["location"]["__typename"] == "OnMap"
                && unit["location"]["position"]["x"].is_number()
                && unit["location"].get("carrierId").is_none()
        }));
        assert_eq!(
            member["data"]["game"]["players"][0]["playerNumber"],
            "PLAYER1"
        );
        assert_eq!(
            member["data"]["game"]["players"][1]["playerNumber"],
            "PLAYER2"
        );
        assert_eq!(member["data"]["game"]["players"][1]["isYou"], true);
        let (host_view, _) = execute!(&game, Some(host.clone()));
        let host_scenario = &host_view["data"]["game"]["scenario"];
        assert_eq!(host_scenario["map"], scenario["map"]);
        for (response, player) in [
            (&member, PlayerNumber::Player2),
            (&host_view, PlayerNumber::Player1),
        ] {
            let visible = visibility::visible_tiles(&expected, player);
            let observed = visibility::observed_scenario(&expected, player, &visible);
            let unit_ids: Vec<_> = response["data"]["game"]["scenario"]["units"]
                .as_array()
                .fixture()?
                .iter()
                .map(|unit| unit["id"].as_str().fixture())
                .collect::<TestResult<_>>()?;
            let expected_ids: Vec<_> = observed.units.iter().map(|unit| unit.id()).collect();
            assert_eq!(unit_ids, expected_ids);
            let visible_tiles: Vec<_> = response["data"]["game"]["visibleTiles"]
                .as_array()
                .fixture()?
                .iter()
                .map(|position| json!({"x":position["x"],"y":position["y"]}))
                .collect();
            let expected_tiles: Vec<_> = visible
                .iter()
                .map(|position| json!({"x":position.x(),"y":position.y()}))
                .collect();
            assert_eq!(visible_tiles, expected_tiles);
        }
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
        let cookie = cookie.fixture()?;
        for alias in ["a", "b"] {
            let id = multiple["data"][alias]["id"].as_str().fixture()?;
            let (owner, _) = execute!(
                format!("{{ lobby(id: \"{id}\") {{ isHost }} }}"),
                Some(cookie.clone())
            );
            assert_eq!(owner["data"]["lobby"]["isHost"], true);
        }
        let submit = |player_number: &str| -> TestResult<String> {
            let own_scenario = if player_number == "PLAYER1" {
                host_scenario
            } else {
                scenario
            };
            let orders = own_scenario["units"]
                .as_array()
                .fixture()?
                .iter()
                .filter(|unit| unit["playerNumber"] == player_number)
                .map(|unit| {
                    Ok(format!(
                        "{{unitId: \"{}\", path: [{{x: {}, y: {}}}]}}",
                        unit["id"].as_str().fixture()?,
                        unit["location"]["position"]["x"],
                        unit["location"]["position"]["y"]
                    ))
                })
                .collect::<TestResult<Vec<_>>>()?
                .join(",");
            Ok(format!(
                "mutation {{ submitTurn(id: \"{id}\", turnNumber: 1, orders: [{orders}]) {{ turnNumber submitted opponentSubmitted lastResolution {{ turnNumber reports {{ playerNumber unitsLost enemyUnitsDestroyed damageInflicted suppliesConsumed }} events {{ kind unitId }} frames {{ units {{ id playerNumber }} visibleTiles {{ x y }} }} }} }} }}"
            ))
        };
        for identity in [None, Some(cookie.clone())] {
            let (denied, _) = execute!(submit("PLAYER1")?, identity);
            assert!(denied["errors"].is_array());
        }
        let (foreign, _) = execute!(submit("PLAYER2")?, Some(host.clone()));
        assert!(foreign["errors"].is_array());
        let (submitted, _) = execute!(submit("PLAYER1")?, Some(host.clone()));
        assert_eq!(submitted["data"]["submitTurn"]["turnNumber"], 1);
        assert_eq!(submitted["data"]["submitTurn"]["submitted"], true);
        let turn_query =
            format!("{{ game(id: \"{id}\") {{ turnNumber submitted opponentSubmitted }} }}");
        let (waiting, _) = execute!(&turn_query, Some(guest.clone()));
        assert_eq!(waiting["data"]["game"]["opponentSubmitted"], true);
        assert_eq!(waiting["data"]["game"]["submitted"], false);
        let (retry, _) = execute!(submit("PLAYER1")?, Some(host.clone()));
        assert_eq!(retry["data"]["submitTurn"]["turnNumber"], 1);
        let (resolved, _) = execute!(submit("PLAYER2")?, Some(guest));
        assert_eq!(resolved["data"]["submitTurn"]["turnNumber"], 2);
        assert_eq!(resolved["data"]["submitTurn"]["submitted"], false);
        let reports = resolved["data"]["submitTurn"]["lastResolution"]["reports"]
            .as_array()
            .fixture()?;
        assert_eq!(reports.len(), 1);
        let report = reports.first().fixture()?;
        assert_eq!(report["playerNumber"], "PLAYER2");
        assert_eq!(report["unitsLost"], 0);
        assert_eq!(report["enemyUnitsDestroyed"], 0);
        assert_eq!(report["damageInflicted"], 0);
        assert_eq!(report["suppliesConsumed"], 32);
        let frames = resolved["data"]["submitTurn"]["lastResolution"]["frames"]
            .as_array()
            .fixture()?;
        assert_eq!(frames.len(), 2);
        assert!(!frames[0]["visibleTiles"].as_array().fixture()?.is_empty());
        assert!(
            frames[0]["units"]
                .as_array()
                .fixture()?
                .iter()
                .all(|unit| unit["playerNumber"] == "PLAYER2")
        );

        assert_eq!(
            resolved["data"]["submitTurn"]["lastResolution"]["events"]
                .as_array()
                .fixture()?
                .len(),
            8
        );
        let (stale, _) = execute!(submit("PLAYER1")?, Some(host));
        assert!(stale["errors"].is_array());
        let old = test::TestRequest::get().uri("/api/health").to_request();
        assert_eq!(
            test::call_service(&app, old).await.status(),
            StatusCode::NOT_FOUND
        );

        Ok(())
    }
}
