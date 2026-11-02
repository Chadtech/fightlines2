//! Shared roster values and controller identity for lobbies, games, and archives.
use crate::{player_name::PlayerName, player_number::PlayerNumber, session_token::SessionToken};
use juniper::GraphQLEnum;
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub(crate) enum PlayerController {
    Human(SessionToken),
    Ai,
}

impl PlayerController {
    pub fn kind(&self) -> Controller {
        match self {
            Self::Human(_) => Controller::Human,
            Self::Ai => Controller::Ai,
        }
    }

    pub fn session(&self) -> Option<&SessionToken> {
        match self {
            Self::Human(session) => Some(session),
            Self::Ai => None,
        }
    }
}

/// A player's public control kind, without human session credentials.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Controller {
    Human,
    #[serde(alias = "AiMedium", alias = "AiHard")]
    Ai,
}

#[derive(Clone)]
pub(crate) struct Player {
    pub player_number: PlayerNumber,
    pub controller: PlayerController,
    pub name: PlayerName,
}
