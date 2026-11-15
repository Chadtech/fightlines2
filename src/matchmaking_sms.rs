//! Operator-only SMS alerts for a newly waiting player.
use juniper::FieldError;
use serde::Deserialize;
use std::{
    env,
    io::{self, Write},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

const RECIPIENT: &str = "FIGHTLINES_MATCHMAKING_SMS_PHONE";
const API_KEY: &str = "FIGHTLINES_TEXTBELT_KEY";
const COOLDOWN: Duration = Duration::from_secs(10);

pub struct Alerts {
    phone: String,
    key: String,
    last_attempt: Mutex<Option<Instant>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Cooldown,
    Transport,
    OutOfQuota,
    Rejected,
}

impl From<Error> for FieldError {
    fn from(error: Error) -> Self {
        match error {
            Error::Cooldown => "an sms was requested recently. try again in a few seconds.",
            Error::Transport => "could not reach the sms provider. try again.",
            Error::OutOfQuota => "textbelt has no sms quota remaining.",
            Error::Rejected => {
                "textbelt rejected the sms. check the number, api key, and daily quota."
            }
        }
        .into()
    }
}

impl Alerts {
    pub fn load() -> io::Result<Option<Self>> {
        let phone = match env::var(RECIPIENT) {
            Ok(phone) => phone,
            Err(env::VarError::NotPresent) => return Ok(None),
            Err(env::VarError::NotUnicode(_)) => return Err(invalid_phone()),
        };
        let digits = phone.strip_prefix('+').ok_or_else(invalid_phone)?;
        if !(2..=15).contains(&digits.len())
            || digits.starts_with('0')
            || !digits.bytes().all(|digit| digit.is_ascii_digit())
        {
            return Err(invalid_phone());
        }
        let key = match env::var(API_KEY) {
            Ok(key) if !key.trim().is_empty() => key,
            Err(env::VarError::NotPresent) => String::from("textbelt"),
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "FIGHTLINES_TEXTBELT_KEY must be nonempty UTF-8",
                ));
            }
        };
        Ok(Some(Self {
            phone,
            key,
            last_attempt: Mutex::new(None),
        }))
    }

    pub fn player_waiting(self: &Arc<Self>) {
        match self.reserve(Instant::now()) {
            Ok(()) => {}
            Err(Error::Cooldown) => return,
            Err(error) => {
                log_failure(error);
                return;
            }
        }
        let alerts = self.clone();
        if thread::Builder::new()
            .name("matchmaking-sms".into())
            .spawn(move || {
                if let Err(error) = alerts.send("FightLines: someone is waiting for a match.") {
                    log_failure(error);
                }
            })
            .is_err()
        {
            log_failure(Error::Transport);
        }
    }

    pub fn send_test(&self) -> Result<(), Error> {
        self.reserve(Instant::now())?;
        self.send("FightLines: matchmaking SMS test.")
    }

    fn reserve(&self, now: Instant) -> Result<(), Error> {
        let mut last_attempt = self.last_attempt.lock().map_err(|_| Error::Transport)?;
        if last_attempt.is_some_and(|at| now.saturating_duration_since(at) < COOLDOWN) {
            return Err(Error::Cooldown);
        }
        *last_attempt = Some(now);
        Ok(())
    }

    fn send(&self, message: &str) -> Result<(), Error> {
        let body = serde_json::to_vec(&serde_json::json!({
            "phone": self.phone,
            "key": self.key,
            "sender": "FightLines",
            "message": message,
        }))
        .map_err(|_| Error::Transport)?;
        // curl is already installed on the deployment host. Pass the private
        // fields through stdin so they never appear in the process arguments.
        let mut child = Command::new("curl")
            .args([
                "--disable",
                "--silent",
                "--fail",
                "--max-time",
                "5",
                "--header",
                "Content-Type: application/json",
                "--data-binary",
                "@-",
                "https://textbelt.com/text",
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| Error::Transport)?;
        let written = child
            .stdin
            .take()
            .ok_or(Error::Transport)
            .and_then(|mut stdin| stdin.write_all(&body).map_err(|_| Error::Transport));
        let output = child.wait_with_output().map_err(|_| Error::Transport)?;
        written?;
        if !output.status.success() {
            return Err(Error::Transport);
        }
        textbelt_result(&output.stdout)
    }
}

fn invalid_phone() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "FIGHTLINES_MATCHMAKING_SMS_PHONE must be a phone number with a + country code",
    )
}

fn log_failure(error: Error) {
    tracing::warn!(
        event = "matchmaking_sms_failed",
        reason = ?error,
        "could not send a matchmaking sms"
    );
}

fn textbelt_result(body: &[u8]) -> Result<(), Error> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Response {
        success: bool,
        quota_remaining: Option<u32>,
    }
    let response: Response = serde_json::from_slice(body).map_err(|_| Error::Transport)?;
    if response.success {
        Ok(())
    } else if response.quota_remaining == Some(0) {
        Err(Error::OutOfQuota)
    } else {
        Err(Error::Rejected)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinguishes_acceptance_quota_and_other_failures() {
        assert_eq!(
            textbelt_result(br#"{"success":true,"quotaRemaining":0}"#),
            Ok(())
        );
        assert_eq!(
            textbelt_result(br#"{"success":false,"quotaRemaining":0}"#),
            Err(Error::OutOfQuota)
        );
        assert_eq!(
            textbelt_result(br#"{"success":false,"error":"rejected"}"#),
            Err(Error::Rejected)
        );
        assert_eq!(textbelt_result(b"unexpected body"), Err(Error::Transport));
    }

    #[test]
    fn rate_limit_is_shared_and_resets() {
        let alerts = Alerts {
            phone: String::new(),
            key: String::new(),
            last_attempt: Mutex::new(None),
        };
        let now = Instant::now();
        assert_eq!(alerts.reserve(now), Ok(()));
        assert_eq!(alerts.send_test(), Err(Error::Cooldown));
        assert_eq!(alerts.reserve(now + COOLDOWN), Ok(()));
    }
}
