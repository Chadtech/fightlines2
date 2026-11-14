//! Private, best-effort records of player-app events.
use crate::{
    app_version,
    deployment::{self, Deployment, StorageSource},
    graphql::Context,
    server_log,
};
use juniper::{FieldError, FieldResult, GraphQLInputObject, GraphQLObject};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{
    collections::HashSet,
    fs,
    io::{self, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};
use tracing_appender::rolling::{RollingFileAppender, Rotation};

const PAGE_SIZE: usize = 40;
const PAGE_READ_BYTES: u64 = 192 * 1024;
const DIRECTORY: &str = "analytics";

#[derive(GraphQLInputObject)]
pub struct AnalyticsEventInput {
    name: String,
    /// A JSON-encoded object to preserve the values supplied by the client.
    data: String,
}

#[derive(Deserialize, Serialize)]
struct Event {
    name: String,
    data: Map<String, Value>,
}

#[derive(Deserialize, Serialize)]
struct Record<Version> {
    received_at_unix_ms: u128,
    version: Version,
    #[serde(flatten)]
    event: Event,
}

pub struct Recorder {
    path: PathBuf,
    writer: Mutex<RollingFileAppender>,
}

#[derive(GraphQLObject)]
pub struct AnalyticsLog {
    id: String,
    day: String,
    source: String,
}

#[derive(GraphQLObject)]
pub struct AnalyticsRecord {
    name: String,
    page: Option<String>,
    data: String,
    version: String,
    received_at: String,
}

#[derive(GraphQLObject)]
pub struct AnalyticsPage {
    logs: Vec<AnalyticsLog>,
    selected_log: Option<String>,
    records: Vec<AnalyticsRecord>,
    unreadable: i32,
    older: Option<String>,
}

struct LogFile {
    log: AnalyticsLog,
    path: PathBuf,
    modified: SystemTime,
}

#[derive(Clone, Copy)]
struct LogCursor(u64);

impl LogCursor {
    fn parse(value: &str) -> Result<Self, &'static str> {
        let offset = value
            .parse::<u64>()
            .map_err(|_| "invalid analytics page cursor.")?;
        if offset == 0 {
            return Err("analytics page cursor must be a positive byte offset.");
        }
        Ok(Self(offset))
    }

    fn preceding(offset: u64) -> Option<Self> {
        (offset > 0).then_some(Self(offset))
    }
}

impl Recorder {
    pub fn open(log_root: &Path) -> io::Result<Self> {
        let path = log_root.canonicalize()?.join(DIRECTORY);
        let mut builder = fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        builder.create(&path)?;
        if !fs::symlink_metadata(&path)?.is_dir() {
            return Err(io::Error::other("analytics require a private directory"));
        }
        let writer = RollingFileAppender::builder()
            .rotation(Rotation::DAILY)
            .filename_prefix("analytics")
            .filename_suffix("jsonl")
            .max_log_files(30)
            .build(&path)
            .map_err(io::Error::other)?;
        Ok(Self {
            path,
            writer: Mutex::new(writer),
        })
    }

    fn record(&self, event: Event) -> io::Result<()> {
        let record = Record {
            received_at_unix_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(io::Error::other)?
                .as_millis(),
            version: app_version::current(),
            event,
        };
        let mut bytes = serde_json::to_vec(&record)?;
        bytes.push(b'\n');
        self.writer
            .lock()
            .map_err(|_| io::Error::other("analytics writer lock is poisoned"))?
            .write_all(&bytes)
    }

    fn logs(&self, deployment: Option<&Deployment>) -> io::Result<Vec<LogFile>> {
        let locations =
            deployment::storage_locations(&self.path, "server-logs/analytics", deployment)?;
        let mut files = Vec::new();
        let mut visited = HashSet::new();
        for location in locations {
            let Some(server_logs) = location.path.parent() else {
                continue;
            };
            if !is_directory(server_logs)? || !is_directory(&location.path)? {
                continue;
            }
            let root = match location.path.canonicalize() {
                Ok(root) => root,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error),
            };
            if !visited.insert(root.clone()) {
                continue;
            }
            discover_logs(&root, location.source, root == self.path, &mut files)?;
        }
        files.sort_by(|left, right| {
            right
                .log
                .day
                .cmp(&left.log.day)
                .then_with(|| right.modified.cmp(&left.modified))
                .then_with(|| right.log.id.cmp(&left.log.id))
        });
        Ok(files)
    }
}

fn is_directory(path: &Path) -> io::Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => Ok(metadata.is_dir()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

fn discover_logs(
    root: &Path,
    source: StorageSource,
    is_local: bool,
    files: &mut Vec<LogFile>,
) -> io::Result<()> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    let (label, key) = match source {
        StorageSource::Local => ("current server".to_owned(), "local".to_owned()),
        StorageSource::Release(id) => {
            let label = if is_local {
                "current server".to_owned()
            } else {
                id.to_string()
            };
            (label, format!("release/{id}"))
        }
        StorageSource::Legacy => ("legacy server".to_owned(), "legacy".to_owned()),
    };
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name();
        let Some(day) = name
            .to_str()
            .and_then(|name| name.strip_prefix("analytics."))
            .and_then(|name| name.strip_suffix(".jsonl"))
            .filter(|day| is_log_day(day))
        else {
            continue;
        };
        let metadata = match entry.metadata() {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error),
        };
        // The rolling appender opens today's file at startup, before any events.
        if metadata.is_file() && metadata.len() > 0 {
            files.push(LogFile {
                log: AnalyticsLog {
                    id: format!("{key}/{day}"),
                    day: day.to_owned(),
                    source: label.clone(),
                },
                path: entry.path(),
                modified: metadata.modified()?,
            });
        }
    }
    Ok(())
}

fn is_log_day(day: &str) -> bool {
    day.len() == 10
        && day.bytes().enumerate().all(|(index, byte)| match index {
            4 | 7 => byte == b'-',
            _ => byte.is_ascii_digit(),
        })
}

impl AnalyticsRecord {
    fn from_line(line: &[u8]) -> serde_json::Result<Self> {
        let record = serde_json::from_slice::<Record<String>>(line)?;
        Ok(Self {
            name: record.event.name,
            page: record
                .event
                .data
                .get("page")
                .and_then(Value::as_str)
                .map(str::to_owned),
            data: serde_json::to_string_pretty(&record.event.data)?,
            version: record.version,
            received_at: record.received_at_unix_ms.to_string(),
        })
    }
}

impl AnalyticsPage {
    fn read(&mut self, path: &Path, before: Option<LogCursor>) -> io::Result<()> {
        let mut file = fs::File::open(path)?;
        let length = file.metadata()?.len();
        let end = before.map_or(length, |LogCursor(offset)| offset.min(length));
        let start = end.saturating_sub(PAGE_READ_BYTES);
        // One lookbehind byte tells us whether the first line starts in
        // this window or belongs to an earlier page.
        let read_start = start.saturating_sub(1);
        file.seek(SeekFrom::Start(read_start))?;
        let mut bytes = Vec::new();
        file.take(end - read_start).read_to_end(&mut bytes)?;
        let (starts_in_record, bytes) = match bytes.split_first() {
            Some((&previous, window)) if start > 0 => (previous != b'\n', window),
            _ => (false, bytes.as_slice()),
        };

        // Omit an in-progress append or the rest of a previously counted
        // oversized line. The cursor always moves toward the start of the file.
        let Some(last_newline) = bytes.iter().rposition(|&byte| byte == b'\n') else {
            self.set_older(LogCursor::preceding(start));
            return Ok(());
        };
        let mut line_end = last_newline;
        let lines = bytes[..last_newline].rsplit(|&byte| byte == b'\n');
        for (index, line) in lines.enumerate() {
            let line_start = line_end - line.len();
            if line_start == 0 && starts_in_record {
                let record_end = start + line_end as u64 + 1;
                let offset = if record_end < end {
                    // Revisit a line that straddles this window from its end.
                    record_end
                } else {
                    // A complete window holds only part of this record.
                    self.unreadable += 1;
                    start
                };
                self.set_older(LogCursor::preceding(offset));
                break;
            }
            match AnalyticsRecord::from_line(line) {
                Ok(record) => self.records.push(record),
                Err(_) => self.unreadable += 1,
            }
            if index + 1 == PAGE_SIZE {
                self.set_older(LogCursor::preceding(start + line_start as u64));
                break;
            }
            line_end = line_start.saturating_sub(1);
        }
        Ok(())
    }

    fn set_older(&mut self, cursor: Option<LogCursor>) {
        self.older = cursor.map(|LogCursor(offset)| offset.to_string());
    }
}

pub fn list(
    context: &Context,
    log_id: Option<&str>,
    before: Option<&str>,
) -> FieldResult<AnalyticsPage> {
    context.require_admin()?;
    let before = before.map(LogCursor::parse).transpose()?;
    read_page(
        recorder(context)?,
        context.store.deployment.as_ref(),
        log_id,
        before,
    )
}

fn read_page(
    recorder: &Recorder,
    deployment: Option<&Deployment>,
    log_id: Option<&str>,
    before: Option<LogCursor>,
) -> FieldResult<AnalyticsPage> {
    let files = recorder.logs(deployment).map_err(read_failed)?;
    let selected = match log_id {
        Some(id) => Some(
            files
                .iter()
                .find(|file| file.log.id == id)
                .ok_or("this analytics log is no longer available.")?,
        ),
        None => files.first(),
    };
    let mut page = AnalyticsPage {
        logs: Vec::new(),
        selected_log: selected.map(|file| file.log.id.clone()),
        records: Vec::new(),
        unreadable: 0,
        older: None,
    };
    if let Some(file) = selected {
        page.read(&file.path, before).map_err(|error| {
            if error.kind() == io::ErrorKind::NotFound {
                "this analytics log is no longer available.".into()
            } else {
                read_failed(error)
            }
        })?;
    }
    page.logs = files.into_iter().map(|file| file.log).collect();
    Ok(page)
}

fn read_failed(error: io::Error) -> FieldError {
    tracing::error!(event = "analytics_read_failed", %error);
    server_log::internal_error("could not read analytics logs.")
}

impl AnalyticsEventInput {
    fn into_event(self) -> FieldResult<Event> {
        if self.name.trim().is_empty()
            || self.name.len() > 64
            || !self.name.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b' ' || byte == b'_'
            })
        {
            return Err("invalid analytics event name.".into());
        }
        if self.data.len() > 2048 {
            return Err("analytics event data is too large.".into());
        }
        let data: Value = serde_json::from_str(&self.data)
            .map_err(|_| "analytics event data must be a JSON object.")?;
        match data {
            Value::Object(data) => Ok(Event {
                name: self.name,
                data,
            }),
            _ => Err("analytics event data must be a JSON object.".into()),
        }
    }
}

pub fn submit(context: &Context, input: AnalyticsEventInput) -> FieldResult<bool> {
    let event = input.into_event()?;
    recorder(context)?.record(event).map_err(|error| {
        tracing::error!(event = "analytics_write_failed", %error);
        server_log::internal_error("could not record analytics.")
    })?;
    Ok(true)
}

fn recorder(context: &Context) -> FieldResult<&Recorder> {
    context
        .analytics
        .as_deref()
        .ok_or_else(|| server_log::internal_error("analytics storage is unavailable."))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};
    use crate::{
        deployment_id::DeploymentId, environment::Environment, graphql, seed::Seed, store::Store,
    };
    use actix_web::{App, test, web};
    use serde_json::json;

    #[actix_web::test]
    async fn pages_the_same_log_from_either_release() -> TestResult {
        let directory = std::env::temp_dir().join(format!(
            "fightlines-analytics-releases-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        let frontend = directory.join("public");
        let releases = directory.join("deployments");
        fs::create_dir_all(&frontend)?;
        let a = Deployment::open(
            DeploymentId::try_from("a".to_owned())?,
            releases.clone(),
            &frontend,
        )?;
        let b = Deployment::open(
            DeploymentId::try_from("b".to_owned())?,
            releases.clone(),
            &frontend,
        )?;
        let day = "2000-01-01";
        let open_log = |id: &str, initial_receipt: usize| -> TestResult<Recorder> {
            let server_logs = releases.join(id).join("server-logs");
            fs::create_dir(&server_logs)?;
            let recorder = Recorder::open(&server_logs)?;
            let path = recorder.path.join(format!("analytics.{day}.jsonl"));
            let mut file = fs::File::create(path)?;
            for index in 0..=PAGE_SIZE {
                writeln!(
                    file,
                    "{}",
                    json!({
                        "name": "page viewed",
                        "data": {},
                        "version": "24",
                        "received_at_unix_ms": initial_receipt + index,
                    })
                )?;
            }
            Ok(recorder)
        };
        let recorder_a = open_log("a", 0)?;
        let recorder_b = open_log("b", 100)?;

        let log_id = format!("release/a/{day}");
        let first = read_page(&recorder_a, Some(&a), Some(&log_id), None).fixture()?;
        let local_log = first.logs.iter().find(|log| log.id == log_id).fixture()?;
        assert_eq!(local_log.source, "current server");
        assert_eq!(first.records.len(), PAGE_SIZE);
        assert_eq!(first.records.last().fixture()?.received_at, "1");
        let older = LogCursor::parse(first.older.as_deref().fixture()?)?;
        drop(recorder_a);

        let next = read_page(&recorder_b, Some(&b), Some(&log_id), Some(older)).fixture()?;
        assert_eq!(next.selected_log.as_deref(), Some(log_id.as_str()));
        assert_eq!(next.records.len(), 1);
        assert_eq!(next.records.first().fixture()?.received_at, "0");
        assert_eq!(next.older, None);
        assert_eq!(next.logs.len(), 2);
        let retained = next.logs.iter().find(|log| log.id == log_id).fixture()?;
        assert_eq!(retained.source, "a");
        let b_id = format!("release/b/{day}");
        let local = next.logs.iter().find(|log| log.id == b_id).fixture()?;
        assert_eq!(local.source, "current server");
        drop(recorder_b);
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn pages_existing_records_newest_first_without_repeating_new_appends() -> TestResult<()> {
        let directory = std::env::temp_dir().join(format!(
            "fightlines-analytics-read-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir(&directory)?;
        let path = directory.join("analytics.2026-11-13.jsonl");
        let mut file = fs::File::create(&path)?;
        for index in 0..45 {
            writeln!(
                file,
                "{}",
                json!({
                    "name": "page viewed",
                    "data": { "page": "game", "sessionId": "example", "payload": "x".repeat(1800) },
                    "version": "24",
                    "received_at_unix_ms": index,
                })
            )?;
        }
        writeln!(file, "invalid record")?;
        write!(file, "partial record")?;
        let page = || AnalyticsPage {
            logs: Vec::new(),
            selected_log: None,
            records: Vec::new(),
            unreadable: 0,
            older: None,
        };
        let mut latest = page();
        latest.read(&path, None)?;
        assert_eq!(latest.records.len(), 39);
        assert_eq!(latest.unreadable, 1);
        let first = latest.records.first().fixture()?;
        assert_eq!(first.received_at, "44");
        assert_eq!(first.page.as_deref(), Some("game"));
        assert_eq!(first.version, "24");
        assert!(first.data.contains("\"sessionId\": \"example\""));
        writeln!(file)?;
        let mut older = page();
        older.read(
            &path,
            Some(LogCursor::parse(latest.older.as_deref().fixture()?)?),
        )?;
        assert_eq!(older.records.len(), 6);
        assert_eq!(older.records.first().fixture()?.received_at, "5");
        assert_eq!(older.records.last().fixture()?.received_at, "0");
        assert_eq!(older.older, None);

        let mut file = fs::File::create(&path)?;
        writeln!(
            file,
            "{}",
            json!({
                "name": "page viewed", "data": {}, "version": "24", "received_at_unix_ms": 0,
            })
        )?;
        writeln!(file, "{}", "x".repeat(PAGE_READ_BYTES as usize * 2))?;
        let mut before = None;
        let mut received = Vec::new();
        let mut unreadable = 0;
        for _ in 0..4 {
            let mut current = page();
            current.read(&path, before)?;
            unreadable += current.unreadable;
            received.extend(current.records.into_iter().map(|record| record.received_at));
            let Some(cursor) = current.older else {
                break;
            };
            let next = LogCursor::parse(&cursor)?;
            assert!(before.is_none_or(|previous| next.0 < previous.0));
            before = Some(next);
        }
        assert_eq!(received, ["0"]);
        assert_eq!(unreadable, 1);
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[actix_web::test]
    async fn writes_valid_events_and_rejects_invalid_or_oversized_events() -> TestResult<()> {
        let directory = std::env::temp_dir().join(format!(
            "fightlines-analytics-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir(&directory)?;
        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(Store::new(Seed::new([0; 32]))))
                .app_data(web::Data::new(graphql::endpoint(Environment::Development)))
                .app_data(web::Data::new(Recorder::open(&directory)?))
                .route("/graphql", web::post().to(graphql::handle)),
        )
        .await;
        let data = json!({
            "sessionId": "0123456789abcdef0123456789abcdef",
            "page": "new player page",
            "example": true,
        });
        let event = json!({
            "name": "page viewed",
            "data": data.to_string(),
        });
        let mut empty_data = event.clone();
        empty_data["data"] = json!("{}");
        let mut oversized_event = event.clone();
        oversized_event["data"] = json!("x".repeat(2049));
        let mut invalid_name = event.clone();
        invalid_name["name"] = json!("page\nviewed");
        let mut array_event = event.clone();
        array_event["data"] = json!("[]");
        for (input, expected_error) in [
            (event, None),
            (empty_data, None),
            (invalid_name, Some("invalid analytics event name.")),
            (oversized_event, Some("analytics event data is too large.")),
            (
                array_event,
                Some("analytics event data must be a JSON object."),
            ),
        ] {
            let request = test::TestRequest::post()
                .uri("/graphql")
                .set_json(json!({
                    "query": "mutation ($input: AnalyticsEventInput!) { recordAnalytics(input: $input) }",
                    "variables": { "input": input },
                }))
                .to_request();
            let response: Value = test::call_and_read_body_json(&app, request).await;
            match expected_error {
                Some(message) => assert_eq!(response["errors"][0]["message"], message),
                None => assert_eq!(response["data"]["recordAnalytics"], true),
            }
        }
        let path = fs::read_dir(directory.join("analytics"))?
            .next()
            .fixture()??
            .path();
        let records = fs::read_to_string(path)?;
        fs::remove_dir_all(directory)?;
        let records: Vec<Value> = records
            .lines()
            .map(serde_json::from_str)
            .collect::<Result<_, _>>()?;
        assert_eq!(records.len(), 2);
        for (record, expected_data) in records.iter().zip([data, json!({})]) {
            assert_eq!(record["name"], "page viewed");
            assert_eq!(record["data"], expected_data);
            assert!(record.get("session_id").is_none());
            assert!(record.get("page").is_none());
        }
        Ok(())
    }
}
