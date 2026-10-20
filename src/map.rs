use juniper::{GraphQLEnum, GraphQLObject, graphql_object};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Coordinate {
    x: u16,
    y: u16,
}

impl Coordinate {
    pub const fn new(x: u16, y: u16) -> Self {
        Self { x, y }
    }
}

#[graphql_object]
impl Coordinate {
    pub fn x(&self) -> i32 {
        i32::from(self.x)
    }

    pub fn y(&self) -> i32 {
        i32::from(self.y)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Terrain {
    Plain,
    Hills,
    Forest,
    Mountains,
}

/// Appearance is independent of terrain movement and visibility rules.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum MapTheme {
    #[default]
    GreenForest,
    Desert,
    Snow,
}

/// Only terrain exceptions are stored. Depots and units live separately.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Map {
    width: u16,
    height: u16,
    base_tile: Terrain,
    theme: MapTheme,
    #[serde(with = "terrain_features")]
    features: BTreeMap<Coordinate, Terrain>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum MapError {
    InvalidDefinition(String),
    EmptyDimensions,
    #[cfg(test)]
    DimensionsTooLarge,
    #[cfg(test)]
    UnequalRowWidth {
        row: usize,
        expected: usize,
        actual: usize,
    },
    #[cfg(test)]
    UnknownTerrain {
        position: Coordinate,
        symbol: char,
    },
    PositionOutOfBounds(Coordinate),
}

impl std::fmt::Display for MapError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidDefinition(message) => formatter.write_str(message),
            Self::EmptyDimensions => formatter.write_str("map dimensions must be positive"),
            Self::PositionOutOfBounds(position) => write!(
                formatter,
                "tile ({}, {}) lies outside the map",
                position.x(),
                position.y()
            ),
            #[cfg(test)]
            Self::DimensionsTooLarge => formatter.write_str("map dimensions are too large"),
            #[cfg(test)]
            Self::UnequalRowWidth {
                row,
                expected,
                actual,
            } => write!(
                formatter,
                "row {row} has {actual} tiles; expected {expected}"
            ),
            #[cfg(test)]
            Self::UnknownTerrain { position, symbol } => write!(
                formatter,
                "unknown terrain '{symbol}' at ({}, {})",
                position.x(),
                position.y()
            ),
        }
    }
}

impl Map {
    pub fn new(
        width: u16,
        height: u16,
        base_tile: Terrain,
        features: BTreeMap<Coordinate, Terrain>,
    ) -> Result<Self, MapError> {
        if width == 0 || height == 0 {
            return Err(MapError::EmptyDimensions);
        }
        let map = Self {
            width,
            height,
            base_tile,
            theme: MapTheme::default(),
            features,
        };
        if let Some(position) = map
            .features
            .keys()
            .find(|position| !map.contains(**position))
        {
            return Err(MapError::PositionOutOfBounds(*position));
        }
        Ok(map)
    }

    /// Parse a rectangular terrain sketch: space or `.` is plain, `#` forest,
    /// `%` hills, and `^` mountains. Spaces are cells, so leading/trailing spaces are preserved.
    /// A final newline is optional; blank rows and unknown symbols are errors.
    #[cfg(test)]
    pub fn from_ascii(sketch: &str) -> Result<Self, MapError> {
        let rows: Vec<&str> = sketch.lines().collect();
        let width = rows.first().map_or(0, |row| row.chars().count());
        if width == 0 || rows.is_empty() {
            return Err(MapError::EmptyDimensions);
        }
        let map_width = u16::try_from(width).map_err(|_| MapError::DimensionsTooLarge)?;
        let map_height = u16::try_from(rows.len()).map_err(|_| MapError::DimensionsTooLarge)?;
        let mut features = BTreeMap::new();
        for (y, row) in rows.iter().enumerate() {
            let actual = row.chars().count();
            if actual != width {
                return Err(MapError::UnequalRowWidth {
                    row: y,
                    expected: width,
                    actual,
                });
            }
            for (x, symbol) in row.chars().enumerate() {
                let position = Coordinate::new(x as u16, y as u16);
                let terrain = match symbol {
                    ' ' | '.' => continue,
                    '#' => Terrain::Forest,
                    '%' => Terrain::Hills,
                    '^' => Terrain::Mountains,
                    _ => return Err(MapError::UnknownTerrain { position, symbol }),
                };
                features.insert(position, terrain);
            }
        }
        Self::new(map_width, map_height, Terrain::Plain, features)
    }

    pub fn with_theme(mut self, theme: MapTheme) -> Self {
        self.theme = theme;
        self
    }

    pub fn contains(&self, position: Coordinate) -> bool {
        position.x < self.width && position.y < self.height
    }

    pub fn tile_at(&self, position: Coordinate) -> Option<Terrain> {
        self.contains(position).then(|| {
            self.features
                .get(&position)
                .copied()
                .unwrap_or(self.base_tile)
        })
    }
}

#[derive(GraphQLObject)]
struct TerrainFeature {
    position: Coordinate,
    terrain: Terrain,
}

#[graphql_object]
impl Map {
    pub fn width(&self) -> i32 {
        i32::from(self.width)
    }

    pub fn height(&self) -> i32 {
        i32::from(self.height)
    }

    pub fn theme(&self) -> MapTheme {
        self.theme
    }

    fn base_tile(&self) -> Terrain {
        self.base_tile
    }

    fn features(&self) -> Vec<TerrainFeature> {
        self.features
            .iter()
            .map(|(position, terrain)| TerrainFeature {
                position: *position,
                terrain: *terrain,
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};

    #[test]
    fn themes_preserve_terrain_and_bounds() -> TestResult<()> {
        let original = Map::from_ascii(".#%\n...").fixture()?;
        assert_eq!(original.theme(), MapTheme::GreenForest);
        for theme in [MapTheme::GreenForest, MapTheme::Desert, MapTheme::Snow] {
            let themed = original.clone().with_theme(theme);
            assert_eq!(themed.theme(), theme);
            assert_eq!(themed.width(), original.width());
            assert_eq!(themed.height(), original.height());
            for y in 0..3 {
                for x in 0..4 {
                    let position = Coordinate::new(x, y);
                    assert_eq!(themed.tile_at(position), original.tile_at(position));
                }
            }
        }

        Ok(())
    }

    #[test]
    fn ascii_preserves_spaces_and_parses_terrain_with_unix_or_windows_lines() -> TestResult<()> {
        for sketch in [" # %\n.   ", " # %\r\n.   \r\n"] {
            let map = Map::from_ascii(sketch).fixture()?;
            assert_eq!((map.width, map.height), (4, 2));
            assert_eq!(map.tile_at(Coordinate::new(1, 0)), Some(Terrain::Forest));
            assert_eq!(map.tile_at(Coordinate::new(3, 0)), Some(Terrain::Hills));
            assert_eq!(map.tile_at(Coordinate::new(0, 1)), Some(Terrain::Plain));
            assert_eq!(map.tile_at(Coordinate::new(3, 1)), Some(Terrain::Plain));
            assert_eq!(map.features.len(), 2);
        }

        Ok(())
    }

    #[test]
    fn ascii_parses_mountains() -> TestResult<()> {
        let map = Map::from_ascii(".^.").fixture()?;
        assert_eq!(map.tile_at(Coordinate::new(1, 0)), Some(Terrain::Mountains));
        Ok(())
    }

    #[test]
    fn ascii_rejects_empty_ragged_unknown_and_oversized_maps() -> TestResult<()> {
        assert_eq!(Map::from_ascii(""), Err(MapError::EmptyDimensions));
        assert_eq!(Map::from_ascii("\n"), Err(MapError::EmptyDimensions));
        assert_eq!(
            Map::from_ascii("..\n."),
            Err(MapError::UnequalRowWidth {
                row: 1,
                expected: 2,
                actual: 1
            })
        );
        assert_eq!(
            Map::from_ascii("..\n\n"),
            Err(MapError::UnequalRowWidth {
                row: 1,
                expected: 2,
                actual: 0
            })
        );
        assert_eq!(
            Map::from_ascii(".x"),
            Err(MapError::UnknownTerrain {
                position: Coordinate::new(1, 0),
                symbol: 'x'
            })
        );
        assert_eq!(
            Map::from_ascii(&".".repeat(65536)),
            Err(MapError::DimensionsTooLarge)
        );

        Ok(())
    }

    #[test]
    fn lookup_uses_overrides_and_fallback_only_inside_bounds() -> TestResult<()> {
        let forest = Coordinate::new(1, 1);
        let map = Map::new(
            3,
            2,
            Terrain::Plain,
            BTreeMap::from([(forest, Terrain::Forest)]),
        )
        .fixture()?;
        assert_eq!(map.tile_at(forest), Some(Terrain::Forest));
        assert_eq!(map.tile_at(Coordinate::new(2, 1)), Some(Terrain::Plain));
        assert_eq!(map.tile_at(Coordinate::new(3, 1)), None);
        assert_eq!(map.tile_at(Coordinate::new(1, 2)), None);
        assert_eq!(map.features.len(), 1);

        Ok(())
    }

    #[test]
    fn rejects_empty_maps_and_out_of_bounds_overrides() -> TestResult<()> {
        assert_eq!(
            Map::new(0, 2, Terrain::Plain, BTreeMap::new()),
            Err(MapError::EmptyDimensions)
        );
        assert_eq!(
            Map::new(2, 0, Terrain::Plain, BTreeMap::new()),
            Err(MapError::EmptyDimensions)
        );
        let position = Coordinate::new(2, 0);
        assert_eq!(
            Map::new(
                2,
                2,
                Terrain::Plain,
                BTreeMap::from([(position, Terrain::Hills)])
            ),
            Err(MapError::PositionOutOfBounds(position))
        );

        Ok(())
    }
}

// JSON object keys cannot represent coordinates. Store sparse terrain as pairs.
mod terrain_features {
    use super::{Coordinate, Terrain};
    use serde::{Deserialize, Deserializer, Serialize, Serializer, de::Error};
    use std::collections::BTreeMap;

    pub fn serialize<S: Serializer>(
        features: &BTreeMap<Coordinate, Terrain>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        features.iter().collect::<Vec<_>>().serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<BTreeMap<Coordinate, Terrain>, D::Error> {
        let pairs = Vec::<(Coordinate, Terrain)>::deserialize(deserializer)?;
        let mut features = BTreeMap::new();
        for (coordinate, terrain) in pairs {
            if features.insert(coordinate, terrain).is_some() {
                return Err(D::Error::custom("duplicate terrain coordinate"));
            }
        }
        Ok(features)
    }
}
