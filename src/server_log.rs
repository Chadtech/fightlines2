//! Private operational diagnostics, separate from authoritative game archives.
use crate::app_version;
use actix_web::{
    Error, HttpMessage, HttpRequest,
    body::MessageBody,
    dev::{ServiceRequest, ServiceResponse},
    error,
    http::header::{HeaderName, HeaderValue},
    middleware::Next,
};
use juniper::{
    DefaultScalarValue, ExecutionError, FieldError, GraphQLError, ScalarValue, Value, graphql_value,
};
use std::{
    backtrace::Backtrace,
    env, fmt, fs, io, panic,
    path::Path,
    process,
    sync::atomic::{AtomicU64, Ordering},
};
use tracing::{Event, Instrument, Level, Subscriber};
use tracing_appender::{
    non_blocking::{NonBlockingBuilder, WorkerGuard},
    rolling::{RollingFileAppender, Rotation},
};
use tracing_subscriber::{
    filter,
    fmt::{
        FmtContext,
        format::{Format, FormatEvent, FormatFields, Json, Writer},
        writer::MakeWriterExt,
    },
    prelude::*,
    registry::LookupSpan,
};

const INTERNAL_ERROR: &str = "INTERNAL_ERROR";
const RETAINED_FILES: usize = 30;
static NEXT_REQUEST: AtomicU64 = AtomicU64::new(1);

struct RequestTracing(tracing::Dispatch);

/// Add build identity to every event, including events outside request spans.
struct VersionedJson(Format<Json>);

impl<S, N> FormatEvent<S, N> for VersionedJson
where
    S: Subscriber + for<'lookup> LookupSpan<'lookup>,
    N: for<'writer> FormatFields<'writer> + 'static,
{
    fn format_event(
        &self,
        context: &FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &Event<'_>,
    ) -> fmt::Result {
        let mut json = String::new();
        self.0
            .format_event(context, Writer::new(&mut json), event)?;
        let fields = json.strip_prefix('{').ok_or(fmt::Error)?;
        let version = serde_json::to_string(app_version::current()).map_err(|_| fmt::Error)?;
        write!(writer, "{{\"version\":{version},{fields}")
    }
}

pub fn dispatch(request: &HttpRequest) -> tracing::Dispatch {
    request
        .extensions()
        .get::<RequestTracing>()
        .map(|tracing| tracing.0.clone())
        .unwrap_or_else(|| tracing::dispatcher::get_default(Clone::clone))
}

/// Correlates diagnostics and responses within this server process. It is never
/// taken from a client header or generated from the credential seed.
#[derive(Clone, Copy)]
pub struct RequestId(u64);

impl RequestId {
    pub fn from_request(request: &HttpRequest) -> Self {
        request
            .extensions()
            .get::<Self>()
            .copied()
            .unwrap_or_else(Self::new)
    }

    fn new() -> Self {
        Self(NEXT_REQUEST.fetch_add(1, Ordering::Relaxed))
    }
}

impl fmt::Display for RequestId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}-{}", process::id(), self.0)
    }
}

pub fn init(frontend: &Path) -> io::Result<WorkerGuard> {
    let directory = env::var_os("FIGHTLINES_SERVER_LOG_DIR")
        .map(Into::into)
        .unwrap_or_else(|| Path::new("server-logs").to_path_buf());
    init_in(&directory, frontend)
}

fn init_in(directory: &Path, frontend: &Path) -> io::Result<WorkerGuard> {
    let appender = open(directory, frontend)?;
    // Apply backpressure rather than silently dropping errors when the queue fills.
    let (writer, guard) = NonBlockingBuilder::default().lossy(false).finish(appender);
    let output = tracing_subscriber::fmt::layer()
        .json()
        .with_ansi(false)
        .event_format(VersionedJson(
            tracing_subscriber::fmt::format()
                .json()
                .with_span_list(false),
        ))
        .with_writer(writer.and(io::stderr))
        // Keep third-party diagnostics from echoing request data behind our
        // explicit redaction boundary. HTTP failures are recorded by middleware.
        .with_filter(filter::filter_fn(|metadata| {
            metadata.target().starts_with("fightlines_server") && *metadata.level() <= Level::INFO
        }));
    tracing_subscriber::registry()
        .with(output)
        .try_init()
        .map_err(|error| io::Error::other(error.to_string()))?;
    panic::set_hook(Box::new(|information| {
        let location = information.location();
        // Panic payloads can contain request data. Keep code location and stack,
        // without copying the payload or delegating to the payload-printing hook.
        tracing::error!(
            event = "server_panic",
            file = location.map(|location| location.file()),
            line = location.map(|location| location.line()),
            backtrace = %Backtrace::force_capture(),
            "server thread panicked"
        );
    }));
    tracing::info!(
        event = "logging_started",
        directory = %directory.display(),
        retained_files = RETAINED_FILES,
        "server diagnostics enabled"
    );
    Ok(guard)
}

fn open(directory: &Path, frontend: &Path) -> io::Result<RollingFileAppender> {
    // Validate the closest existing ancestor before creating any directory, so
    // a bad configuration cannot create log files under the public frontend.
    let frontend = frontend.canonicalize()?;
    let mut ancestor = directory.to_path_buf();
    while !ancestor.exists() {
        if !ancestor.pop() || ancestor.as_os_str().is_empty() {
            ancestor = env::current_dir()?;
            break;
        }
    }
    if ancestor.canonicalize()?.starts_with(&frontend) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "FIGHTLINES_SERVER_LOG_DIR must be outside FIGHTLINES_FRONTEND_DIR",
        ));
    }
    let mut builder = fs::DirBuilder::new();
    builder.recursive(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(0o700);
    }
    builder.create(directory)?;
    if directory.canonicalize()?.starts_with(&frontend) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "FIGHTLINES_SERVER_LOG_DIR must be outside FIGHTLINES_FRONTEND_DIR",
        ));
    }
    RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix("fightlines")
        .filename_suffix("jsonl")
        .max_log_files(RETAINED_FILES)
        .build(directory)
        .map_err(|error| io::Error::other(error.to_string()))
}

/// Constructs a client-facing operational error. Callers must log the failure
/// at its source; the GraphQL boundary skips these errors to avoid duplicate logs.
/// Private details belong only in the source event, not in this message.
pub fn internal_error(message: impl fmt::Display) -> FieldError {
    FieldError::new(message, graphql_value!({ "code": INTERNAL_ERROR }))
}

pub fn graphql_errors(
    result: &Result<(Value, Vec<ExecutionError<DefaultScalarValue>>), GraphQLError>,
) {
    match result {
        Ok((_, errors)) => {
            for error in errors {
                let field_error = error.error();
                let internal = field_error
                    .extensions()
                    .as_object_value()
                    .and_then(|object| object.get_field_value("code"))
                    .and_then(Value::as_scalar)
                    .and_then(ScalarValue::try_as_str)
                    .is_some_and(|code| code == INTERNAL_ERROR);
                if internal {
                    continue;
                }
                // Response paths contain client-chosen aliases. Only log the
                // client-facing resolver message and numeric query location.
                tracing::warn!(
                    event = "graphql_rejected",
                    reason = field_error.message(),
                    line = error.location().line() + 1,
                    column = error.location().column() + 1,
                    "GraphQL action rejected"
                );
            }
        }
        Err(error) => {
            let kind = match error {
                GraphQLError::ParseError(_) => "parse",
                GraphQLError::ValidationError(_) => "validation",
                GraphQLError::NoOperationProvided => "no_operation",
                GraphQLError::MultipleOperationsProvided => "multiple_operations",
                GraphQLError::UnknownOperationName => "unknown_operation",
                GraphQLError::IsSubscription | GraphQLError::NotSubscription => "operation_kind",
            };
            // Parse/validation messages can echo query text and variable values.
            tracing::warn!(event = "graphql_invalid", kind, "invalid GraphQL request");
        }
    }
}

/// Covers HTTP failures, including rejected JSON bodies that never reach GraphQL.
pub async fn request(
    request: ServiceRequest,
    next: Next<impl MessageBody>,
) -> Result<ServiceResponse<impl MessageBody>, Error> {
    let id = RequestId::new();
    request.extensions_mut().insert(id);
    request
        .extensions_mut()
        .insert(RequestTracing(tracing::dispatcher::get_default(
            Clone::clone,
        )));
    let span = tracing::info_span!("http_request", request_id = %id);
    let result = next.call(request).instrument(span.clone()).await;
    span.in_scope(|| match &result {
        Ok(response) => {
            let status = response.status();
            let route = response.request().match_pattern();
            if status.is_server_error() {
                tracing::error!(
                    event = "http_failed",
                    status = status.as_u16(),
                    route,
                    "HTTP request failed"
                );
            } else if status.is_client_error() {
                tracing::warn!(
                    event = "http_rejected",
                    status = status.as_u16(),
                    route,
                    "HTTP request rejected"
                );
            }
        }
        Err(error) => {
            let status = error.as_response_error().status_code();
            if status.is_server_error() {
                tracing::error!(
                    event = "http_failed",
                    status = status.as_u16(),
                    "HTTP service failed"
                );
            } else {
                tracing::warn!(
                    event = "http_rejected",
                    status = status.as_u16(),
                    "HTTP service rejected request"
                );
            }
        }
    });
    let value = HeaderValue::from_str(&id.to_string()).map_err(error::ErrorInternalServerError)?;
    let mut response = result.map_err(|cause| {
        let mut response = cause.error_response();
        response
            .headers_mut()
            .insert(HeaderName::from_static("x-request-id"), value.clone());
        response.headers_mut().insert(
            HeaderName::from_static("cache-control"),
            HeaderValue::from_static("no-store"),
        );
        Error::from(error::InternalError::from_response(cause, response))
    })?;
    response
        .headers_mut()
        .insert(HeaderName::from_static("x-request-id"), value);
    if response.status().is_client_error() || response.status().is_server_error() {
        response.headers_mut().insert(
            HeaderName::from_static("cache-control"),
            HeaderValue::from_static("no-store"),
        );
    }
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        environment::Environment,
        game_archive, game_log, graphql,
        seed::Seed,
        store::Store,
        test_support::{FixtureValue, TestResult},
    };
    use actix_web::{App, HttpResponse, http::StatusCode, middleware, test as web_test, web};
    use serde_json::{Value as JsonValue, json};
    use std::{
        io::Write,
        path::PathBuf,
        thread,
        time::{SystemTime, UNIX_EPOCH},
    };

    fn directory(label: &str) -> TestResult<PathBuf> {
        let directory = env::temp_dir().join(format!(
            "fightlines-server-log-{label}-{}-{}",
            process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir_all(directory.join("public"))?;
        Ok(directory)
    }

    #[test]
    fn appends_private_diagnostics_and_bounds_retention_without_removing_other_files()
    -> TestResult<()> {
        let root = directory("retention")?;
        let directory = root.join("diagnostics");
        fs::create_dir(&directory)?;
        fs::write(directory.join("keep.txt"), "operator notes")?;
        for day in 1..=31 {
            fs::write(
                directory.join(format!("fightlines.2000-01-{day:02}.jsonl")),
                "old\n",
            )?;
        }
        let frontend = root.join("public");
        let mut first = open(&directory, &frontend)?;
        first.write_all(b"{\"event\":\"first\"}\n")?;
        first.flush()?;
        drop(first);
        let mut second = open(&directory, &frontend)?;
        second.write_all(b"{\"event\":\"second\"}\n")?;
        second.flush()?;
        drop(second);
        let paths = fs::read_dir(&directory)?
            .map(|entry| entry.map(|entry| entry.path()))
            .collect::<io::Result<Vec<_>>>()?;
        let logs: Vec<_> = paths
            .iter()
            .filter(|path| {
                path.extension()
                    .is_some_and(|extension| extension == "jsonl")
            })
            .collect();
        assert!(logs.len() <= RETAINED_FILES);
        let contents = logs
            .iter()
            .map(fs::read_to_string)
            .collect::<io::Result<Vec<_>>>()?;
        assert!(
            contents
                .iter()
                .any(|contents| contents.contains("first") && contents.contains("second"))
        );
        assert_eq!(
            fs::read_to_string(directory.join("keep.txt"))?,
            "operator notes"
        );
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn refuses_public_log_directories_before_creating_them() -> TestResult<()> {
        let root = directory("public")?;
        let frontend = root.join("public");
        let unsafe_path = frontend.join("logs/nested");
        assert_eq!(
            open(&unsafe_path, &frontend).err().fixture()?.kind(),
            io::ErrorKind::InvalidInput
        );
        assert!(!frontend.join("logs").exists());
        #[cfg(unix)]
        {
            let link = root.join("linked-public");
            std::os::unix::fs::symlink(&frontend, &link)?;
            assert!(open(&link.join("logs"), &frontend).is_err());
            assert!(!frontend.join("logs").exists());
            let private = root.join("private-logs");
            drop(open(&private, &frontend)?);
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(fs::metadata(private)?.permissions().mode() & 0o777, 0o700);
        }
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[actix_web::test]
    async fn records_graphql_and_http_failures_with_correlated_ids_without_request_payloads()
    -> TestResult<()> {
        // Production uses a global subscriber. Isolate its installation and panic
        // hook from the parallel test harness, and exercise the real writer/flush.
        const CHILD: &str = "FIGHTLINES_DIAGNOSTICS_TEST_CHILD";
        if env::var_os(CHILD).is_none() {
            let test_name = thread::current().name().fixture()?.to_owned();
            let output = process::Command::new(env::current_exe()?)
                .args(["--exact", &test_name, "--nocapture"])
                .env(CHILD, "1")
                .output()?;
            assert!(
                output.status.success(),
                "diagnostic integration test failed: {}{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(String::from_utf8_lossy(&output.stdout).contains("1 passed"));
            return Ok(());
        }
        let root = directory("requests")?;
        let logs = root.join("diagnostics");
        let archive_path = root.join("archives");
        let guard = init_in(&logs, &root.join("public"))?;
        let store = Store::new(Seed::new([51; 32]))
            .with_game_logs(game_log::Directory::open(archive_path.clone())?);
        let app = web_test::init_service(
            App::new()
                .wrap(middleware::from_fn(request))
                .app_data(web::Data::new(store))
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .app_data(web::Data::new(game_archive::Browser {
                    directory: archive_path.clone(),
                }))
                .route("/graphql", web::post().to(graphql::handle))
                .route(
                    "/failure",
                    web::get().to(|| async {
                        Err::<HttpResponse, _>(error::ErrorInternalServerError("secret-http-cause"))
                    }),
                ),
        )
        .await;
        macro_rules! execute {
            ($body:expr, $cookie:expr) => {{
                let mut request = web_test::TestRequest::post()
                    .uri("/graphql")
                    .insert_header(("x-request-id", "untrusted-client-id"))
                    .set_json($body);
                if let Some(cookie) = $cookie {
                    request = request.cookie(cookie);
                }
                let response = web_test::call_service(&app, request.to_request()).await;
                assert_eq!(response.status(), StatusCode::OK);
                let id = response
                    .headers()
                    .get("x-request-id")
                    .fixture()?
                    .to_str()?
                    .to_owned();
                assert_ne!(id, "untrusted-client-id");
                let cookie = response
                    .response()
                    .cookies()
                    .next()
                    .map(|cookie| cookie.into_owned());
                let body: JsonValue = web_test::read_body_json(response).await;
                (body, cookie, id)
            }};
        }
        let (rejected, _, rejected_id) = execute!(
            &json!({
                "query": "mutation PrivateOperation($name: String!, $lobby: String!) { PrivateAlias: createLobby(name: $name, lobbyName: $lobby) { id } }",
                "variables": { "name": " ", "lobby": "secret-variable-value" },
                "operationName": "PrivateOperation"
            }),
            None
        );
        assert!(rejected["errors"].is_array());
        let (invalid, _, invalid_id) = execute!(
            &json!({"query": "{ SensitiveAlias: unknownPrivateField }"}),
            None
        );
        assert!(invalid["errors"].is_array());
        let request = web_test::TestRequest::post()
            .uri("/graphql?private=secret-query-string")
            .insert_header(("content-type", "application/json"))
            .insert_header(("cookie", "fightlines-session=secret-session-cookie"))
            .set_payload("{not json secret-body")
            .to_request();
        let response = web_test::call_service(&app, request).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let http_id = response
            .headers()
            .get("x-request-id")
            .fixture()?
            .to_str()?
            .to_owned();
        let response = web_test::call_service(
            &app,
            web_test::TestRequest::get().uri("/failure").to_request(),
        )
        .await;
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        let http_failure_id = response
            .headers()
            .get("x-request-id")
            .fixture()?
            .to_str()?
            .to_owned();
        let (created, host, _) = execute!(
            &json!({ "query": "mutation { createLobby(name: \"private-player-name\", lobbyName: \"private-lobby-name\") { id } }" }),
            None
        );
        let host = host.fixture()?;
        let id = created["data"]["createLobby"]["id"].as_str().fixture()?;
        execute!(
            &json!({ "query": format!("mutation {{ setLobbyController(id: \"{id}\", controller: AI) {{ id }} }}") }),
            Some(host.clone())
        );
        // A real persistence failure exercises both private detail logging and
        // the client-facing INTERNAL_ERROR classification without changing state.
        fs::rename(&archive_path, root.join("offline-archives"))?;
        let (failed, _, failure_id) = execute!(
            &json!({ "query": format!("mutation {{ startGame(id: \"{id}\") {{ id }} }}") }),
            Some(host.clone())
        );
        assert_eq!(failed["errors"][0]["extensions"]["code"], INTERNAL_ERROR);
        assert_eq!(
            failed["errors"][0]["message"],
            "the game could not be recorded. please retry after the server storage is available."
        );
        // Archive listing previously relied entirely on boundary logging. It
        // must now emit its own diagnostic while preserving the API error.
        let (unlisted, _, list_failure_id) =
            execute!(&json!({ "query": "{ loggedGames { __typename } }" }), None);
        assert_eq!(unlisted["errors"][0]["extensions"]["code"], INTERNAL_ERROR);
        drop(guard);
        let mut contents = String::new();
        for entry in fs::read_dir(&logs)? {
            contents.push_str(&fs::read_to_string(entry?.path())?);
        }
        for secret in [
            "untrusted-client-id",
            "PrivateOperation",
            "PrivateAlias",
            "SensitiveAlias",
            "unknownPrivateField",
            "secret-variable-value",
            "secret-session-cookie",
            "secret-query-string",
            "secret-body",
            "secret-http-cause",
            "private-player-name",
            "private-lobby-name",
            host.value(),
        ] {
            assert!(
                !contents.contains(secret),
                "diagnostics must not contain {secret}"
            );
        }
        let records = contents
            .lines()
            .map(serde_json::from_str::<JsonValue>)
            .collect::<Result<Vec<_>, _>>()?;
        assert!(!records.is_empty());
        for record in &records {
            assert_eq!(record["version"], app_version::current());
        }
        for (event, level, id) in [
            ("graphql_rejected", "WARN", rejected_id),
            ("graphql_invalid", "WARN", invalid_id),
            ("http_rejected", "WARN", http_id),
            ("http_failed", "ERROR", http_failure_id),
            ("game_archive_write_failed", "ERROR", failure_id.clone()),
            ("game_archive_list_failed", "ERROR", list_failure_id.clone()),
        ] {
            assert!(
                records
                    .iter()
                    .any(|record| record["fields"]["event"] == event
                        && record["level"] == level
                        && record["span"]["request_id"] == id),
                "missing correlated {event}: {contents}"
            );
        }
        for id in [failure_id, list_failure_id] {
            let errors = records
                .iter()
                .filter(|record| record["level"] == "ERROR" && record["span"]["request_id"] == id)
                .count();
            assert_eq!(errors, 1, "expected one ERROR for request {id}: {contents}");
            assert!(
                !records.iter().any(|record| {
                    record["fields"]["event"] == "graphql_rejected"
                        && record["span"]["request_id"] == id
                }),
                "internal failures must not also log a rejection: {contents}"
            );
        }
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
