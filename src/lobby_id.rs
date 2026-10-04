use serde::{Deserialize, Serialize};
use std::fmt;

/// A lobby's public identifier, distinct from browser identity tokens.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Deserialize, Serialize)]
#[serde(transparent)]
pub struct LobbyId(String);

impl LobbyId {
    pub fn from_token(token: String) -> Self {
        Self(token)
    }
}

impl fmt::Display for LobbyId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}
