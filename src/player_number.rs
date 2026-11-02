//! Player ownership and the complete, ordered set of supported player numbers.
use juniper::GraphQLEnum;
use serde::{Deserialize, Serialize};

/// Player ownership, independent of starting position on a map.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum PlayerNumber {
    Player1,
    Player2,
}

impl PlayerNumber {
    /// All player numbers, in map-side order.
    pub const ALL: [Self; 2] = [Self::Player1, Self::Player2];

    /// Zero-based position in `ALL` for player-indexed state.
    pub const fn index(self) -> usize {
        match self {
            Self::Player1 => 0,
            Self::Player2 => 1,
        }
    }

    /// The opposing player in the current two-player game.
    pub const fn opponent(self) -> Self {
        match self {
            Self::Player1 => Self::Player2,
            Self::Player2 => Self::Player1,
        }
    }
}
