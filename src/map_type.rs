use crate::{map::MapError, scenario::Scenario};
use juniper::GraphQLEnum;

/// Selects the fixed initial board and forces for a game.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum)]
pub enum MapType {
    #[default]
    SupplyPoint,
}

impl MapType {
    pub fn player_count(self) -> usize {
        match self {
            Self::SupplyPoint => 2,
        }
    }

    pub fn scenario(self) -> Result<Scenario, MapError> {
        match self {
            Self::SupplyPoint => Scenario::supply_point(),
        }
    }
}
