//! Cheap admission checks before Juniper validation and resolver execution.
use super::Schema;
use juniper::{
    Definition, Selection,
    parser::{Lexer, Token, parse_document_source},
};
use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};

const MAX_NESTING: usize = 32;
const MAX_SELECTIONS: usize = 1024;
const MAX_ROOT_FIELDS: usize = 8;
const MAX_CONCURRENT_REQUESTS: usize = 16;

#[derive(Debug, PartialEq, Eq)]
pub(super) enum Rejection {
    Nesting,
    Selections,
    RootFields,
    Busy,
}

impl Rejection {
    pub fn message(&self) -> &'static str {
        match self {
            Self::Nesting => "GraphQL nesting exceeds the limit of 32.",
            Self::Selections => "GraphQL selections exceed the limit of 1024.",
            Self::RootFields => "GraphQL top-level fields exceed the limit of 8.",
            Self::Busy => "The server is busy. Try again shortly.",
        }
    }
}

#[derive(Default)]
pub(super) struct Requests {
    active: AtomicUsize,
}

pub(super) struct Permit(Arc<Requests>);

impl Requests {
    pub fn acquire(self: &Arc<Self>) -> Result<Permit, Rejection> {
        self.active
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |active| {
                (active < MAX_CONCURRENT_REQUESTS).then_some(active + 1)
            })
            .map_err(|_| Rejection::Busy)?;
        Ok(Permit(Arc::clone(self)))
    }
}

impl Drop for Permit {
    fn drop(&mut self) {
        self.0.active.fetch_sub(1, Ordering::Relaxed);
    }
}

pub(super) fn document(source: &str, schema: &Schema) -> Result<(), Rejection> {
    // Bound parser recursion too, including inline input objects, lists and types.
    // Juniper's lexer keeps punctuation inside strings/comments out of this count.
    let mut nesting = 0_usize;
    for token in Lexer::new(source) {
        let Ok(token) = token else {
            return Ok(());
        };
        match token.item {
            Token::CurlyOpen | Token::BracketOpen | Token::ParenOpen => {
                nesting += 1;
                if nesting > MAX_NESTING {
                    return Err(Rejection::Nesting);
                }
            }
            Token::CurlyClose | Token::BracketClose | Token::ParenClose => {
                nesting = nesting.saturating_sub(1);
            }
            _ => {}
        }
    }
    // Keep ordinary syntax and schema errors on Juniper's existing error path.
    let Ok(document) = parse_document_source(source, &schema.schema) else {
        return Ok(());
    };
    let fragments: BTreeMap<_, _> = document
        .iter()
        .filter_map(|definition| match definition {
            Definition::Fragment(fragment) => Some((
                fragment.item.name.item,
                fragment.item.selection_set.as_slice(),
            )),
            Definition::Operation(_) => None,
        })
        .collect();
    let mut selections = 0;
    let mut root_fields = 0;
    // Check unused definitions too: Juniper validates the entire document.
    for definition in &document {
        let (selection_set, root) = match definition {
            Definition::Operation(operation) => (&operation.item.selection_set, true),
            Definition::Fragment(fragment) => (&fragment.item.selection_set, false),
        };
        let mut pending = vec![(selection_set.as_slice(), 0, root)];
        while let Some((selection_set, depth, root)) = pending.pop() {
            if depth > MAX_NESTING {
                return Err(Rejection::Nesting);
            }
            for selection in selection_set {
                selections += 1;
                if selections > MAX_SELECTIONS {
                    return Err(Rejection::Selections);
                }
                match selection {
                    Selection::Field(field) => {
                        if root {
                            root_fields += 1;
                            if root_fields > MAX_ROOT_FIELDS {
                                return Err(Rejection::RootFields);
                            }
                        }
                        if let Some(children) = &field.item.selection_set {
                            pending.push((children, depth + 1, false));
                        }
                    }
                    Selection::InlineFragment(fragment) => {
                        pending.push((&fragment.item.selection_set, depth + 1, root));
                    }
                    Selection::FragmentSpread(spread) => {
                        if let Some(children) = fragments.get(spread.item.name.item) {
                            pending.push((children, depth + 1, root));
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        environment::Environment,
        graphql,
        seed::Seed,
        store::Store,
        test_support::{FixtureValue, TestResult},
    };
    use actix_web::{App, http::StatusCode, test as web_test, web};
    use serde_json::{Value, json};

    #[test]
    fn counts_aliases_and_fragment_expansion_before_execution() {
        let schema = graphql::schema();
        let aliases = (0..8)
            .map(|index| format!("a{index}: health "))
            .collect::<String>();
        assert_eq!(document(&format!("{{ {aliases} }}"), &schema), Ok(()));
        assert_eq!(
            document(&format!("{{ {aliases} health }}"), &schema),
            Err(Rejection::RootFields)
        );
        let fragments = (0..12)
            .map(|index| {
                format!(
                    "fragment F{index} on GameSnapshot {{ ...F{} ...F{} }} ",
                    index + 1,
                    index + 1
                )
            })
            .collect::<String>();
        assert_eq!(
            document(
                &format!(
                    "{{ game(id: \"x\") {{ ...F0 }} }} {fragments} fragment F12 on GameSnapshot {{ turnNumber }}"
                ),
                &schema
            ),
            Err(Rejection::Selections)
        );
        assert_eq!(
            document(
                "{ ...Root ...Root ...Root } fragment Root on Query { a: health b: health c: health }",
                &schema
            ),
            Err(Rejection::RootFields)
        );
        assert_eq!(
            document(
                "{ ... on Query { a: health b: health c: health d: health e: health f: health g: health h: health i: health } }",
                &schema
            ),
            Err(Rejection::RootFields)
        );
    }

    #[test]
    fn bounds_selections_and_recursion_without_counting_input_fields_or_strings() {
        let schema = graphql::schema();
        let fields = "turnNumber ".repeat(MAX_SELECTIONS - 1);
        assert_eq!(
            document(&format!("{{ game(id: \"x\") {{ {fields} }} }}"), &schema),
            Ok(())
        );
        assert_eq!(
            document(
                &format!("{{ game(id: \"x\") {{ {fields} name }} }}"),
                &schema
            ),
            Err(Rejection::Selections)
        );
        let deep = format!(
            "{}health{}",
            "{".repeat(MAX_NESTING + 1),
            "}".repeat(MAX_NESTING + 1)
        );
        assert_eq!(document(&deep, &schema), Err(Rejection::Nesting));
        let deep_input = format!(
            "query Q($x: {}Int{}) {{ health }}",
            "[".repeat(MAX_NESTING + 1),
            "]".repeat(MAX_NESTING + 1)
        );
        assert_eq!(document(&deep_input, &schema), Err(Rejection::Nesting));
        assert_eq!(
            document("{ ...Loop } fragment Loop on Query { ...Loop }", &schema),
            Err(Rejection::Nesting)
        );
        assert_eq!(
            document(
                &format!(
                    "mutation {{ createLobby(name: \"{}\", lobbyName: \"a\") {{ id }} }} # {}",
                    "{[(".repeat(1000),
                    "{[(".repeat(1000)
                ),
                &schema
            ),
            Ok(())
        );
        // Existing invalid-document errors remain Juniper's responsibility.
        assert_eq!(document("{ missingField }", &schema), Ok(()));
    }

    #[actix_web::test]
    async fn rejects_oversized_mutations_without_changes_and_recovers_after_saturation()
    -> TestResult<()> {
        let seed = Seed::new([17; 32]);
        let store = web::Data::new(Store::new(seed));
        let endpoint = web::Data::new(graphql::endpoint(Environment::Development));
        let app = web_test::init_service(
            App::new()
                .app_data(store.clone())
                .app_data(endpoint.clone())
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let mutations = (0..9)
            .map(|index| {
                format!("a{index}: createLobby(name: \"host\", lobbyName: \"game\") {{ id }} ")
            })
            .collect::<String>();
        let request = web_test::TestRequest::post()
            .uri("/graphql")
            .insert_header(("Cookie", "fightlines_session=known-session"))
            .set_json(json!({ "query": format!("mutation {{ {mutations} }}") }))
            .to_request();
        let response = web_test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response.headers().get("Cache-Control").fixture()?,
            "no-store"
        );
        assert!(response.headers().contains_key("X-Request-Id"));
        assert!(!response.headers().contains_key("Set-Cookie"));
        let body: Value = web_test::read_body_json(response).await;
        assert_eq!(
            body["errors"][0]["message"],
            Rejection::RootFields.message()
        );
        let (id, _) = crate::seed::token(seed);
        assert!(
            store
                .entry(&crate::lobby_id::LobbyId::from_token(id))
                .fixture()?
                .is_none()
        );

        let mut permits = (0..MAX_CONCURRENT_REQUESTS)
            .map(|_| {
                endpoint
                    .requests
                    .acquire()
                    .map_err(|rejection| rejection.message())
            })
            .collect::<Result<Vec<_>, _>>()?;
        let request = web_test::TestRequest::post()
            .uri("/graphql")
            .set_json(json!({ "query": "{ health }" }))
            .to_request();
        let response = web_test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(response.headers().get("Retry-After").fixture()?, "1");
        assert_eq!(
            response.headers().get("Cache-Control").fixture()?,
            "no-store"
        );
        assert!(response.headers().contains_key("X-Request-Id"));
        drop(permits.pop());
        let request = web_test::TestRequest::post()
            .uri("/graphql")
            .set_json(json!({ "query": "{ health }" }))
            .to_request();
        let response = web_test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value = web_test::read_body_json(response).await;
        assert_eq!(body["data"]["health"], true);
        assert!(endpoint.requests.acquire().is_ok());
        Ok(())
    }

    #[actix_web::test]
    async fn disconnected_request_keeps_its_slot_until_the_worker_finishes() -> TestResult<()> {
        use std::{
            future::{Future, poll_fn},
            sync::mpsc,
            task::Poll,
            thread,
            time::Duration,
        };

        let store = web::Data::new(Store::development(Seed::new([18; 32])).fixture()?);
        let endpoint = web::Data::new(graphql::endpoint(Environment::Development));
        let id = "0".repeat(32);
        let entry = store
            .entry(&crate::lobby_id::LobbyId::from_token(id.clone()))
            .fixture()?
            .fixture()?;
        let (locked_tx, locked_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let blocker = thread::spawn(move || -> Result<(), String> {
            let _guard = entry.lock().map_err(|error| error.to_string())?;
            locked_tx.send(()).map_err(|error| error.to_string())?;
            release_rx
                .recv_timeout(Duration::from_secs(5))
                .map_err(|error| error.to_string())?;
            Ok(())
        });
        locked_rx.recv_timeout(Duration::from_secs(3))?;
        let app = web_test::init_service(
            App::new()
                .app_data(store)
                .app_data(endpoint.clone())
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let _permits = (0..MAX_CONCURRENT_REQUESTS - 1)
            .map(|_| {
                endpoint
                    .requests
                    .acquire()
                    .map_err(|rejection| rejection.message())
            })
            .collect::<Result<Vec<_>, _>>()?;
        let request = web_test::TestRequest::post()
            .uri("/graphql")
            .set_json(json!({ "query": format!("{{ game(id: \"{id}\") {{ turnNumber }} }}") }))
            .to_request();
        let mut response = Box::pin(web_test::call_service(&app, request));
        assert!(poll_fn(|context| Poll::Ready(response.as_mut().poll(context).is_pending())).await);
        assert!(endpoint.requests.acquire().is_err());
        drop(response);
        assert!(endpoint.requests.acquire().is_err());
        release_tx.send(())?;
        blocker
            .join()
            .map_err(|_| "entry holder panicked")?
            .fixture()?;
        actix_web::rt::time::timeout(Duration::from_secs(3), async {
            loop {
                if let Ok(permit) = endpoint.requests.acquire() {
                    break permit;
                }
                actix_web::rt::task::yield_now().await;
            }
        })
        .await
        .fixture()?;
        Ok(())
    }
}
