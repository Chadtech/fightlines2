use crate::{map::MapError, map_definition::MapDefinition, scenario::Scenario};
use juniper::GraphQLEnum;
use serde::{Deserialize, Serialize};

/// Selects the fixed initial board and forces for a game.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum MapType {
    #[default]
    SupplyPoint,
    ElAlamein,
    BloodGulch,
    Arabia,
    Sidewinder,
    BlackForest,
    Crossroads,
    Ridgeway,
    ThreeCrossings,
    LakeOfPennsylvania,
    ConvoyCountry,
}

pub const MAPS: [(MapType, &str); 11] = [
    (MapType::SupplyPoint, "supply-point"),
    (MapType::ElAlamein, "el-alamein"),
    (MapType::BloodGulch, "blood-gulch"),
    (MapType::Arabia, "arabia"),
    (MapType::Sidewinder, "sidewinder"),
    (MapType::BlackForest, "black-forest"),
    (MapType::Crossroads, "crossroads"),
    (MapType::Ridgeway, "ridgeway"),
    (MapType::ThreeCrossings, "three-crossings"),
    (MapType::LakeOfPennsylvania, "lake-of-pennsylvania"),
    (MapType::ConvoyCountry, "convoy-country"),
];

impl MapType {
    pub fn player_count(self) -> usize {
        match self {
            Self::SupplyPoint
            | Self::ElAlamein
            | Self::BloodGulch
            | Self::Arabia
            | Self::Sidewinder
            | Self::BlackForest
            | Self::Crossroads
            | Self::Ridgeway
            | Self::ThreeCrossings
            | Self::LakeOfPennsylvania
            | Self::ConvoyCountry => 2,
        }
    }

    pub fn scenario(self) -> Result<Scenario, MapError> {
        if std::env::args().any(|argument| argument == "--map-editor") {
            let name = MAPS
                .iter()
                .find(|(kind, _)| *kind == self)
                .map(|(_, name)| *name)
                .ok_or_else(|| MapError::InvalidDefinition("unknown map".into()))?;
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("maps")
                .join(format!("{name}.json"));
            let json = std::fs::read_to_string(path)
                .map_err(|error| MapError::InvalidDefinition(error.to_string()))?;
            return MapDefinition::parse(&json)?.scenario();
        }
        match self {
            Self::SupplyPoint => Scenario::supply_point(),
            Self::ElAlamein => Scenario::el_alamein(),
            Self::BloodGulch => Scenario::blood_gulch(),
            Self::Arabia => Scenario::arabia(),
            Self::Sidewinder => Scenario::sidewinder(),
            Self::BlackForest => Scenario::black_forest(),
            Self::Crossroads => Scenario::crossroads(),
            Self::Ridgeway => Scenario::ridgeway(),
            Self::ThreeCrossings => Scenario::three_crossings(),
            Self::LakeOfPennsylvania => Scenario::lake_of_pennsylvania(),
            Self::ConvoyCountry => Scenario::convoy_country(),
        }
    }
}
