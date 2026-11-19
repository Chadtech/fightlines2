//! Shared roster values and controller identity for lobbies, games, and archives.
use crate::{player_name::PlayerName, player_number::PlayerNumber, session_token::SessionToken};
use juniper::GraphQLEnum;
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub(crate) enum PlayerController {
    Human(SessionToken),
    Ai(AiOpponent),
}

#[derive(Clone, Copy)]
pub(crate) enum AiOpponent {
    Easy,
    BreakContact,
    ScreenedBattery,
    FindTheBlindSide,
}

impl PlayerController {
    pub fn kind(&self) -> Controller {
        match self {
            Self::Human(_) => Controller::Human,
            Self::Ai(AiOpponent::Easy) => Controller::Ai,
            Self::Ai(AiOpponent::BreakContact) => Controller::BreakContact,
            Self::Ai(AiOpponent::ScreenedBattery) => Controller::ScreenedBattery,
            Self::Ai(AiOpponent::FindTheBlindSide) => Controller::FindTheBlindSide,
        }
    }

    pub fn session(&self) -> Option<&SessionToken> {
        match self {
            Self::Human(session) => Some(session),
            Self::Ai(_) => None,
        }
    }
}

/// A player's public control kind, without human session credentials.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Controller {
    Human,
    #[serde(alias = "AiMedium", alias = "AiHard", alias = "ScreenLateralSkirmish")]
    Ai,
    // Stored opponents have stable names even when their lobby difficulty changes.
    #[graphql(name = "AI_MEDIUM")]
    BreakContact,
    #[graphql(name = "AI_HARD")]
    ScreenedBattery,
    #[graphql(name = "AI_VERY_HARD")]
    FindTheBlindSide,
}

impl Controller {
    pub(crate) fn ai_opponent(self) -> Option<AiOpponent> {
        match self {
            Self::Human => None,
            Self::Ai => Some(AiOpponent::Easy),
            Self::BreakContact => Some(AiOpponent::BreakContact),
            Self::ScreenedBattery => Some(AiOpponent::ScreenedBattery),
            Self::FindTheBlindSide => Some(AiOpponent::FindTheBlindSide),
        }
    }
}

#[derive(Clone)]
pub(crate) struct Player {
    pub player_number: PlayerNumber,
    pub controller: PlayerController,
    pub name: PlayerName,
}
