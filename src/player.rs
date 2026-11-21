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
    ScreenedBattery,
    FindTheBlindSide,
    ArtillerySpotters,
}

impl PlayerController {
    pub fn kind(&self) -> Controller {
        match self {
            Self::Human(_) => Controller::Human,
            Self::Ai(AiOpponent::Easy) => Controller::Ai,
            Self::Ai(AiOpponent::ScreenedBattery) => Controller::ScreenedBattery,
            Self::Ai(AiOpponent::FindTheBlindSide) => Controller::FindTheBlindSide,
            Self::Ai(AiOpponent::ArtillerySpotters) => Controller::ArtillerySpotters,
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
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Controller {
    Human,
    Ai,
    #[graphql(name = "AI_MEDIUM")]
    ScreenedBattery,
    #[graphql(name = "AI_HARD")]
    FindTheBlindSide,
    #[graphql(name = "AI_VERY_HARD")]
    ArtillerySpotters,
}

impl Controller {
    pub(crate) fn ai_opponent(self) -> Option<AiOpponent> {
        match self {
            Self::Human => None,
            Self::Ai => Some(AiOpponent::Easy),
            Self::ScreenedBattery => Some(AiOpponent::ScreenedBattery),
            Self::FindTheBlindSide => Some(AiOpponent::FindTheBlindSide),
            Self::ArtillerySpotters => Some(AiOpponent::ArtillerySpotters),
        }
    }
}

/// Archive and deployment records keep opponent identities across difficulty changes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum RecordedController {
    Human,
    #[serde(alias = "AiMedium", alias = "AiHard", alias = "ScreenLateralSkirmish")]
    Ai,
    BreakContact,
    ScreenedBattery,
    FindTheBlindSide,
    ArtillerySpotters,
}

impl RecordedController {
    pub(crate) fn current_controller(self) -> Option<Controller> {
        match self {
            Self::Human => Some(Controller::Human),
            Self::Ai => Some(Controller::Ai),
            Self::BreakContact => None,
            Self::ScreenedBattery => Some(Controller::ScreenedBattery),
            Self::FindTheBlindSide => Some(Controller::FindTheBlindSide),
            Self::ArtillerySpotters => Some(Controller::ArtillerySpotters),
        }
    }
}

impl From<Controller> for RecordedController {
    fn from(controller: Controller) -> Self {
        match controller {
            Controller::Human => Self::Human,
            Controller::Ai => Self::Ai,
            Controller::ScreenedBattery => Self::ScreenedBattery,
            Controller::FindTheBlindSide => Self::FindTheBlindSide,
            Controller::ArtillerySpotters => Self::ArtillerySpotters,
        }
    }
}

#[derive(Clone)]
pub(crate) struct Player {
    pub player_number: PlayerNumber,
    pub controller: PlayerController,
    pub name: PlayerName,
}
