//! Private, best-effort records of player-app events.
use crate::{app_version, graphql::Context, server_log};
use juniper::{FieldResult, GraphQLInputObject};
use serde::Serialize;
use serde_json::{Map, Value};
use std::{
    fs,
    io::{self, Write},
    path::Path,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};
use tracing_appender::rolling::{RollingFileAppender, Rotation};

#[derive(GraphQLInputObject)]
pub struct AnalyticsEventInput {
    name: String,
    /// A JSON-encoded object to preserve the values supplied by the client.
    data: String,
}

#[derive(Serialize)]
struct Event {
    name: String,
    data: Map<String, Value>,
}

#[derive(Serialize)]
struct Record {
    received_at_unix_ms: u128,
    version: &'static str,
    #[serde(flatten)]
    event: Event,
}

pub struct Recorder {
    writer: Mutex<RollingFileAppender>,
}

impl Recorder {
    pub fn open(log_root: &Path) -> io::Result<Self> {
        let path = log_root.canonicalize()?.join("analytics");
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
            .build(path)
            .map_err(io::Error::other)?;
        Ok(Self {
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
    let recorder = context
        .analytics
        .as_deref()
        .ok_or_else(|| server_log::internal_error("analytics storage is unavailable."))?;
    recorder.record(event).map_err(|error| {
        tracing::error!(event = "analytics_write_failed", %error);
        server_log::internal_error("could not record analytics.")
    })?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};
    use crate::{environment::Environment, graphql, seed::Seed, store::Store};
    use actix_web::{App, test, web};
    use serde_json::json;

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
