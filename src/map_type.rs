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
    Sidewinder,
    BlackForest,
    Crossroads,
    Ridgeway,
    ThreeCrossings,
    LakeOfPennsylvania,
    ConvoyCountry,
    Tobruk,
    BastionPass,
    WinterFront,
}

pub const MAPS: [(MapType, &str); 13] = [
    (MapType::SupplyPoint, "supply-point"),
    (MapType::ElAlamein, "el-alamein"),
    (MapType::BloodGulch, "blood-gulch"),
    (MapType::Sidewinder, "sidewinder"),
    (MapType::BlackForest, "black-forest"),
    (MapType::Crossroads, "crossroads"),
    (MapType::Ridgeway, "ridgeway"),
    (MapType::ThreeCrossings, "three-crossings"),
    (MapType::LakeOfPennsylvania, "lake-of-pennsylvania"),
    (MapType::ConvoyCountry, "convoy-country"),
    (MapType::Tobruk, "tobruk"),
    (MapType::BastionPass, "bastion-pass"),
    (MapType::WinterFront, "winter-front"),
];

impl MapType {
    pub fn player_count(self) -> usize {
        match self {
            Self::SupplyPoint
            | Self::ElAlamein
            | Self::BloodGulch
            | Self::Sidewinder
            | Self::BlackForest
            | Self::Crossroads
            | Self::Ridgeway
            | Self::ThreeCrossings
            | Self::LakeOfPennsylvania
            | Self::ConvoyCountry
            | Self::Tobruk
            | Self::BastionPass
            | Self::WinterFront => 2,
        }
    }

    pub fn definition(self) -> Result<MapDefinition, MapError> {
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
            return MapDefinition::parse(&json);
        }
        let json = match self {
            Self::SupplyPoint => include_str!("../maps/supply-point.json"),
            Self::ElAlamein => include_str!("../maps/el-alamein.json"),
            Self::BloodGulch => include_str!("../maps/blood-gulch.json"),
            Self::Sidewinder => include_str!("../maps/sidewinder.json"),
            Self::BlackForest => include_str!("../maps/black-forest.json"),
            Self::Crossroads => include_str!("../maps/crossroads.json"),
            Self::Ridgeway => include_str!("../maps/ridgeway.json"),
            Self::ThreeCrossings => include_str!("../maps/three-crossings.json"),
            Self::LakeOfPennsylvania => include_str!("../maps/lake-of-pennsylvania.json"),
            Self::ConvoyCountry => include_str!("../maps/convoy-country.json"),
            Self::Tobruk => include_str!("../maps/tobruk.json"),
            Self::BastionPass => include_str!("../maps/bastion-pass.json"),
            Self::WinterFront => include_str!("../maps/winter-front.json"),
        };
        MapDefinition::parse(json)
    }

    pub fn scenario(self) -> Result<Scenario, MapError> {
        self.definition()?.scenario()
    }
}
