//! Validated identity shared by the game server and release supervisor.
use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct DeploymentId(String);

impl DeploymentId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for DeploymentId {
    type Error = String;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        if value.is_empty()
            || value.len() > 100
            || !value
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        {
            return Err(
                "deployment id must contain 1–100 lowercase letters, digits, or hyphens".into(),
            );
        }
        Ok(Self(value))
    }
}

impl From<DeploymentId> for String {
    fn from(value: DeploymentId) -> Self {
        value.0
    }
}

impl fmt::Display for DeploymentId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}
