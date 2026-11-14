use super::*;
use crate::{
    game_archive, game_log, graphql,
    seed::Seed,
    store::Store,
    test_support::{FixtureValue, TestResult},
};
use actix_web::{App, http::header, test as web_test, web};
use serde_json::{Value, json};
use std::fs;

const PASSWORD: &str = "test-only admin passphrase";

#[test]
fn passwords_sessions_expiry_rotation_and_restart() -> TestResult {
    let encoded = hash_password(PASSWORD)?;
    let auth = Auth::from_hash(Some(encoded.clone()))?;
    let now = Instant::now();
    assert!(auth.login("incorrect password", None, now).is_err());
    let token = auth.login(PASSWORD, None, now).fixture()?;
    assert_eq!(
        auth.status(Some(&token), now).fixture()?,
        SessionStatus::SignedIn
    );
    assert_eq!(
        auth.status(Some(&Token("forged".into())), now).fixture()?,
        SessionStatus::SignedOut
    );
    let rotated = auth.login(PASSWORD, Some(&token), now).fixture()?;
    assert!(token != rotated);
    assert_eq!(
        auth.status(Some(&token), now).fixture()?,
        SessionStatus::SignedOut
    );
    assert_eq!(
        Auth::from_hash(Some(encoded))?
            .status(Some(&rotated), now)
            .fixture()?,
        SessionStatus::SignedOut
    );
    assert_eq!(
        auth.status(
            Some(&rotated),
            now + SESSION_LIFETIME - Duration::from_secs(1)
        )
        .fixture()?,
        SessionStatus::SignedIn
    );
    assert_eq!(
        auth.status(Some(&rotated), now + SESSION_LIFETIME)
            .fixture()?,
        SessionStatus::SignedOut
    );
    assert!(hash_password("short").is_err());
    assert!(Auth::from_hash(Some(String::new())).is_err());
    assert_eq!(
        Auth::from_hash(None)?.status(None, now).fixture()?,
        SessionStatus::Disabled
    );
    assert!(
        Auth::from_hash(Some(
            "$argon2id$v=19$m=1,t=1,p=1$c2FsdHNhbHQ$aGFzaGhhc2g".into()
        ))
        .is_err()
    );
    Ok(())
}

#[test]
fn global_login_budget_and_verification_admission_are_bounded() -> TestResult {
    let auth = Auth::from_hash(Some(hash_password(PASSWORD)?))?;
    let now = Instant::now();
    *auth.attempts.lock().fixture()? = VecDeque::from(vec![now; 20]);
    assert!(auth.login(PASSWORD, None, now).is_err());
    let token = auth
        .login(PASSWORD, None, now + Duration::from_secs(60))
        .fixture()?;
    auth.logout(Some(&token)).fixture()?;
    assert_eq!(
        auth.status(Some(&token), now + Duration::from_secs(60))
            .fixture()?,
        SessionStatus::SignedOut
    );
    auth.verifying.store(true, Ordering::Release);
    assert!(
        auth.login(PASSWORD, None, now + Duration::from_secs(61))
            .is_err()
    );
    auth.verifying.store(false, Ordering::Release);
    Ok(())
}

#[test]
fn cookies_and_origin_checks_use_runtime_hosting_policy() -> TestResult {
    let change = CookieChange::Set(Token("a".repeat(43)));
    let production = change.cookie(Environment::Production);
    assert_eq!(production.secure(), Some(true));
    assert_eq!(production.http_only(), Some(true));
    assert_eq!(production.same_site(), Some(SameSite::Strict));
    assert_eq!(production.path(), Some("/"));
    assert_eq!(
        production.max_age().fixture()?.whole_seconds(),
        SESSION_LIFETIME.as_secs() as i64
    );
    assert_eq!(
        change.cookie(Environment::Development).secure(),
        Some(false)
    );
    assert_eq!(
        CookieChange::Remove
            .cookie(Environment::Production)
            .max_age()
            .fixture()?
            .whole_seconds(),
        0
    );
    for (origin, expected) in [
        ("https://fightlines.test", true),
        ("https://attacker.test", false),
        ("http://fightlines.test", false),
        ("null", false),
    ] {
        let request = web_test::TestRequest::post()
            .insert_header((header::HOST, "fightlines.test"))
            .insert_header((header::ORIGIN, origin))
            .to_http_request();
        assert_eq!(same_origin(&request, Environment::Production), expected);
    }
    let missing = web_test::TestRequest::post()
        .insert_header((header::HOST, "fightlines.test"))
        .to_http_request();
    assert!(!same_origin(&missing, Environment::Production));
    Ok(())
}

#[actix_web::test]
async fn endpoints_protect_private_data_and_keep_player_identity_separate() -> TestResult {
    let root = env::temp_dir().join(format!(
        "fightlines-admin-{}",
        URL_SAFE_NO_PAD.encode(rand::random::<[u8; 16]>())
    ));
    fs::create_dir_all(root.join("public"))?;
    let logs = root.join("logs");
    let server_logs = root.join("server-logs");
    fs::create_dir_all(&server_logs)?;
    let auth = Auth::from_hash(Some(hash_password(PASSWORD)?))?;
    let store = web::Data::new(
        Store::new(Seed::new([92; 32])).with_game_logs(game_log::Directory::open(logs.clone())?),
    );
    let app = web_test::init_service(
        App::new()
            .app_data(store.clone())
            .app_data(web::Data::new(graphql::endpoint_with_admin(
                Environment::Production,
                auth,
                game_archive::Browser { directory: logs },
            )))
            .app_data(web::Data::new(crate::feedback::Directory::open(
                root.join("feedback"),
                &root.join("public"),
            )?))
            .app_data(web::Data::new(crate::planning_error::Directory::open(
                &server_logs,
                &root.join("public"),
            )?))
            .route("/graphql", web::post().to(graphql::handle)),
    )
    .await;
    macro_rules! send {
        ($query:expr, $cookie:expr, $origin:expr) => {{
            let mut request = web_test::TestRequest::post().uri("/graphql")
                .insert_header((header::HOST, "fightlines.test"))
                .insert_header((header::ORIGIN, $origin))
                .set_json(json!({"query": $query}));
            let cookie: Option<Cookie<'static>> = $cookie;
            if let Some(cookie) = cookie { request = request.cookie(cookie); }
            web_test::call_service(&app, request.to_request()).await
        }};
    }
    for query in [
        "{ adminDashboard { concurrentGames } }",
        "{ adminFeedback(offset:0) { total } }",
        "{ adminRecordings(offset:0) { total } }",
        "{ adminPlanningErrors(offset:0) { total } }",
        "{ loggedGames { __typename } }",
        "{ loggedGame(id:\"bad\") { id } }",
        "{ loggedTurn(id:\"bad\",turnNumber:0,playerNumber:PLAYER1) { id } }",
    ] {
        let body: Value =
            web_test::read_body_json(send!(query, None, "https://fightlines.test")).await;
        assert_eq!(
            body["errors"][0]["extensions"]["code"], "ADMIN_LOGIN_REQUIRED",
            "{body}"
        );
    }
    let login = format!(
        "mutation {{ adminLogin(password: {}) }}",
        serde_json::to_string(PASSWORD)?
    );
    let wrong_origin: Value =
        web_test::read_body_json(send!(&login, None, "https://attacker.test")).await;
    assert!(wrong_origin.get("errors").is_some());
    let player = Cookie::new("fightlines_session", "existing-player");
    let response = send!(&login, Some(player), "https://fightlines.test");
    let cookies: Vec<_> = response
        .response()
        .cookies()
        .map(|cookie| cookie.into_owned())
        .collect();
    assert_eq!(cookies.len(), 1);
    let cookie = cookies.first().fixture()?.clone();
    assert_eq!(cookie.name(), COOKIE);
    assert_eq!(cookie.secure(), Some(true));
    let body: Value = web_test::read_body_json(response).await;
    assert_eq!(body["data"]["adminLogin"], "SIGNED_IN");
    assert!(!body.to_string().contains(PASSWORD));
    let overview = "{ adminDashboard { concurrentGames waitingLobbies retainedFinishedGames entries { id busy } } adminFeedback(offset:0) { total } adminRecordings(offset:0) { total } }";
    let body: Value = web_test::read_body_json(send!(
        overview,
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert!(body.get("errors").is_none(), "{body}");
    assert_eq!(body["data"]["adminDashboard"]["concurrentGames"], 0);
    // Use the public game workflow to verify lobby -> game -> terminal counts.
    let response = send!(
        "mutation { createLobby(name:\"host\",lobbyName:\"admin test\") { id } }",
        None,
        "https://fightlines.test"
    );
    let host = response.response().cookies().next().fixture()?.into_owned();
    let body: Value = web_test::read_body_json(response).await;
    let id = body["data"]["createLobby"]["id"].as_str().fixture()?;
    let body: Value = web_test::read_body_json(send!(
        overview,
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert_eq!(body["data"]["adminDashboard"]["waitingLobbies"], 1);
    for query in [
        format!("mutation {{ setLobbyController(id:\"{id}\",controller:AI) {{ id }} }}"),
        format!("mutation {{ startGame(id:\"{id}\") {{ id }} }}"),
    ] {
        let body: Value =
            web_test::read_body_json(send!(query, Some(host.clone()), "https://fightlines.test"))
                .await;
        assert!(body.get("errors").is_none(), "{body}");
    }
    let report = format!(
        "mutation {{ reportPlanningErrors(input: {{ gameId: \"{id}\", clientVersion: \"12\", errors: [{{ turnNumber: 1, details: \"planning unit not found: 2\" }}, {{ turnNumber: 2, details: \"order unit has no position: 3\" }}] }}) }}"
    );
    let denied: Value =
        web_test::read_body_json(send!(&report, None, "https://fightlines.test")).await;
    assert!(denied.get("errors").is_some(), "{denied}");
    let invalid = report.replace("turnNumber: 2", "turnNumber: 0");
    let rejected: Value = web_test::read_body_json(send!(
        &invalid,
        Some(host.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert!(rejected.get("errors").is_some(), "{rejected}");
    let accepted: Value = web_test::read_body_json(send!(
        &report,
        Some(host.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert_eq!(accepted["data"]["reportPlanningErrors"], true);
    let reports: Value = web_test::read_body_json(send!(
        "{ adminPlanningErrors(offset:0) { total unreadable nextOffset reports { gameId turnNumber clientVersion serverVersion details receivedAt } } }",
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    let page = &reports["data"]["adminPlanningErrors"];
    assert_eq!(page["total"], 2);
    assert_eq!(page["unreadable"], 0);
    assert!(page["nextOffset"].is_null());
    let saved = page["reports"]
        .as_array()
        .fixture()?
        .iter()
        .find(|report| report["turnNumber"] == 1)
        .fixture()?;
    assert_eq!(saved["gameId"], id);
    assert_eq!(saved["turnNumber"], 1);
    assert_eq!(saved["clientVersion"], "12");
    assert_eq!(saved["serverVersion"], crate::app_version::current());
    assert_eq!(saved["details"], "planning unit not found: 2");
    assert!(page["reports"].as_array().fixture()?.iter().any(|report| {
        report["turnNumber"] == 2 && report["details"] == "order unit has no position: 3"
    }));
    assert!(saved["receivedAt"].as_str().fixture()?.parse::<u128>()? > 0);
    assert!(!reports.to_string().contains(host.value()));
    let entry = store
        .entry(&crate::lobby_id::LobbyId::from_token(id.into()))
        .fixture()?
        .fixture()?;
    let held = entry.lock().fixture()?;
    let body: Value = web_test::read_body_json(send!(
        overview,
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert_eq!(body["data"]["adminDashboard"]["concurrentGames"], 1);
    assert_eq!(body["data"]["adminDashboard"]["entries"][0]["busy"], true);
    drop(held);
    let resigned: Value = web_test::read_body_json(send!(
        format!("mutation {{ resignGame(id:\"{id}\") {{ id }} }}"),
        Some(host),
        "https://fightlines.test"
    ))
    .await;
    assert!(resigned.get("errors").is_none(), "{resigned}");
    let body: Value = web_test::read_body_json(send!(
        overview,
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert_eq!(body["data"]["adminDashboard"]["concurrentGames"], 0);
    assert_eq!(body["data"]["adminDashboard"]["retainedFinishedGames"], 1);
    assert_eq!(body["data"]["adminRecordings"]["total"], 1);
    let logged_out: Value = web_test::read_body_json(send!(
        "mutation { adminLogout }",
        Some(cookie.clone()),
        "https://fightlines.test"
    ))
    .await;
    assert_eq!(logged_out["data"]["adminLogout"], true);
    let denied: Value =
        web_test::read_body_json(send!(overview, Some(cookie), "https://fightlines.test")).await;
    assert_eq!(
        denied["errors"][0]["extensions"]["code"],
        "ADMIN_LOGIN_REQUIRED"
    );
    // Existing player cookies and rotations cannot bypass the common IP budget.
    let mut limited = Value::Null;
    for _ in 0..6 {
        limited = web_test::read_body_json(send!(
            "mutation { adminLogin(password:\"incorrect\") }",
            None,
            "https://fightlines.test"
        ))
        .await;
    }
    assert_eq!(limited["errors"][0]["extensions"]["code"], "RATE_LIMITED");
    fs::remove_dir_all(root)?;
    Ok(())
}
