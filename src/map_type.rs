use crate::{map::MapError, scenario::Scenario};
use juniper::GraphQLEnum;

/// Selects the fixed initial board and forces for a game.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum)]
pub enum MapType {
    #[default]
    SupplyPoint,
    ElAlamein,
    BloodGulch,
    Arabia,
    Sidewinder,
    BlackForest,
}

impl MapType {
    pub fn player_count(self) -> usize {
        match self {
            Self::SupplyPoint
            | Self::ElAlamein
            | Self::BloodGulch
            | Self::Arabia
            | Self::Sidewinder
            | Self::BlackForest => 2,
        }
    }

    pub fn scenario(self) -> Result<Scenario, MapError> {
        match self {
            Self::SupplyPoint => Scenario::supply_point(),
            Self::ElAlamein => Scenario::el_alamein(),
            Self::BloodGulch => Scenario::blood_gulch(),
            Self::Arabia => Scenario::arabia(),
            Self::Sidewinder => Scenario::sidewinder(),
            Self::BlackForest => Scenario::black_forest(),
        }
    }
}
