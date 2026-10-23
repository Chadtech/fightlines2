use juniper::GraphQLEnum;
use serde::{Deserialize, Serialize};

/// Stored road geometry is independent of the rules shared by every road.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoadShape {
    NorthSouth,
    EastWest,
    NorthEast,
    SouthEast,
    SouthWest,
    NorthWest,
    NorthEastSouth,
    EastSouthWest,
    NorthSouthWest,
    NorthEastWest,
    Crossroads,
}

impl RoadShape {
    pub const ALL: [Self; 11] = [
        Self::NorthSouth,
        Self::EastWest,
        Self::NorthEast,
        Self::SouthEast,
        Self::SouthWest,
        Self::NorthWest,
        Self::NorthEastSouth,
        Self::EastSouthWest,
        Self::NorthSouthWest,
        Self::NorthEastWest,
        Self::Crossroads,
    ];
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "TerrainValue", into = "TerrainValue")]
pub enum Terrain {
    Plain,
    Hills,
    Forest,
    Mountains,
    Water,
    Beach,
    Road(RoadShape),
}

impl Terrain {
    pub fn is_road(self) -> bool {
        match self {
            Self::Road(_) => true,
            Self::Plain
            | Self::Hills
            | Self::Forest
            | Self::Mountains
            | Self::Water
            | Self::Beach => false,
        }
    }
}

// Preserve the flat GraphQL enum and existing map/archive JSON strings.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
#[graphql(name = "Terrain")]
pub(crate) enum TerrainValue {
    Plain,
    Hills,
    Forest,
    Mountains,
    Water,
    Beach,
    RoadNorthSouth,
    RoadEastWest,
    RoadNorthEast,
    RoadSouthEast,
    RoadSouthWest,
    RoadNorthWest,
    RoadNorthEastSouth,
    RoadEastSouthWest,
    RoadNorthSouthWest,
    RoadNorthEastWest,
    RoadCrossroads,
}

impl From<TerrainValue> for Terrain {
    fn from(value: TerrainValue) -> Self {
        match value {
            TerrainValue::Plain => Self::Plain,
            TerrainValue::Hills => Self::Hills,
            TerrainValue::Forest => Self::Forest,
            TerrainValue::Mountains => Self::Mountains,
            TerrainValue::Water => Self::Water,
            TerrainValue::Beach => Self::Beach,
            TerrainValue::RoadNorthSouth => Self::Road(RoadShape::NorthSouth),
            TerrainValue::RoadEastWest => Self::Road(RoadShape::EastWest),
            TerrainValue::RoadNorthEast => Self::Road(RoadShape::NorthEast),
            TerrainValue::RoadSouthEast => Self::Road(RoadShape::SouthEast),
            TerrainValue::RoadSouthWest => Self::Road(RoadShape::SouthWest),
            TerrainValue::RoadNorthWest => Self::Road(RoadShape::NorthWest),
            TerrainValue::RoadNorthEastSouth => Self::Road(RoadShape::NorthEastSouth),
            TerrainValue::RoadEastSouthWest => Self::Road(RoadShape::EastSouthWest),
            TerrainValue::RoadNorthSouthWest => Self::Road(RoadShape::NorthSouthWest),
            TerrainValue::RoadNorthEastWest => Self::Road(RoadShape::NorthEastWest),
            TerrainValue::RoadCrossroads => Self::Road(RoadShape::Crossroads),
        }
    }
}

impl From<Terrain> for TerrainValue {
    fn from(terrain: Terrain) -> Self {
        match terrain {
            Terrain::Plain => Self::Plain,
            Terrain::Hills => Self::Hills,
            Terrain::Forest => Self::Forest,
            Terrain::Mountains => Self::Mountains,
            Terrain::Water => Self::Water,
            Terrain::Beach => Self::Beach,
            Terrain::Road(RoadShape::NorthSouth) => Self::RoadNorthSouth,
            Terrain::Road(RoadShape::EastWest) => Self::RoadEastWest,
            Terrain::Road(RoadShape::NorthEast) => Self::RoadNorthEast,
            Terrain::Road(RoadShape::SouthEast) => Self::RoadSouthEast,
            Terrain::Road(RoadShape::SouthWest) => Self::RoadSouthWest,
            Terrain::Road(RoadShape::NorthWest) => Self::RoadNorthWest,
            Terrain::Road(RoadShape::NorthEastSouth) => Self::RoadNorthEastSouth,
            Terrain::Road(RoadShape::EastSouthWest) => Self::RoadEastSouthWest,
            Terrain::Road(RoadShape::NorthSouthWest) => Self::RoadNorthSouthWest,
            Terrain::Road(RoadShape::NorthEastWest) => Self::RoadNorthEastWest,
            Terrain::Road(RoadShape::Crossroads) => Self::RoadCrossroads,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{RoadShape, Terrain};
    use crate::test_support::TestResult;

    #[test]
    fn terrain_keeps_existing_map_and_archive_json_values() -> TestResult {
        let cases = [
            (Terrain::Plain, "Plain"),
            (Terrain::Hills, "Hills"),
            (Terrain::Forest, "Forest"),
            (Terrain::Mountains, "Mountains"),
            (Terrain::Water, "Water"),
            (Terrain::Beach, "Beach"),
            (Terrain::Road(RoadShape::NorthSouth), "RoadNorthSouth"),
            (Terrain::Road(RoadShape::EastWest), "RoadEastWest"),
            (Terrain::Road(RoadShape::NorthEast), "RoadNorthEast"),
            (Terrain::Road(RoadShape::SouthEast), "RoadSouthEast"),
            (Terrain::Road(RoadShape::SouthWest), "RoadSouthWest"),
            (Terrain::Road(RoadShape::NorthWest), "RoadNorthWest"),
            (
                Terrain::Road(RoadShape::NorthEastSouth),
                "RoadNorthEastSouth",
            ),
            (Terrain::Road(RoadShape::EastSouthWest), "RoadEastSouthWest"),
            (
                Terrain::Road(RoadShape::NorthSouthWest),
                "RoadNorthSouthWest",
            ),
            (Terrain::Road(RoadShape::NorthEastWest), "RoadNorthEastWest"),
            (Terrain::Road(RoadShape::Crossroads), "RoadCrossroads"),
        ];
        for (terrain, name) in cases {
            let json = serde_json::json!(name);
            assert_eq!(serde_json::to_value(terrain)?, json);
            assert_eq!(serde_json::from_value::<Terrain>(json)?, terrain);
        }
        Ok(())
    }
}
