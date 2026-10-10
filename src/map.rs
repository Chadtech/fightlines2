use juniper::{GraphQLEnum, GraphQLObject, graphql_object};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Terrain {
    GrassPlain,
    Hills,
    Forest,
}

/// Appearance is independent of terrain movement and visibility rules.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, GraphQLEnum)]
pub enum MapTheme {
    #[default]
    GreenForest,
    Desert,
    Snow,
}

/// Only terrain exceptions are stored. Depots and units live separately.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Map {
    width: u16,
    height: u16,
    base_tile: Terrain,
    theme: MapTheme,
    features: BTreeMap<Coordinate, Terrain>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum MapError {
    EmptyDimensions,
    DimensionsTooLarge,
    UnequalRowWidth {
        row: usize,
        expected: usize,
        actual: usize,
    },
    UnknownTerrain {
        position: Coordinate,
        symbol: char,
    },
    PositionOutOfBounds(Coordinate),
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

    /// Parse a rectangular terrain sketch: space or `.` is grass, `#` forest,
    /// and `%` hills. Spaces are cells, so leading/trailing spaces are preserved.
    /// A final newline is optional; blank rows and unknown symbols are errors.
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
                    _ => return Err(MapError::UnknownTerrain { position, symbol }),
                };
                features.insert(position, terrain);
            }
        }
        Self::new(map_width, map_height, Terrain::GrassPlain, features)
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

    #[test]
    fn themes_preserve_terrain_and_bounds() {
        let original = Map::from_ascii(".#%\n...").unwrap();
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
    }

    #[test]
    fn ascii_preserves_spaces_and_parses_terrain_with_unix_or_windows_lines() {
        for sketch in [" # %\n.   ", " # %\r\n.   \r\n"] {
            let map = Map::from_ascii(sketch).unwrap();
            assert_eq!((map.width, map.height), (4, 2));
            assert_eq!(map.tile_at(Coordinate::new(1, 0)), Some(Terrain::Forest));
            assert_eq!(map.tile_at(Coordinate::new(3, 0)), Some(Terrain::Hills));
            assert_eq!(
                map.tile_at(Coordinate::new(0, 1)),
                Some(Terrain::GrassPlain)
            );
            assert_eq!(
                map.tile_at(Coordinate::new(3, 1)),
                Some(Terrain::GrassPlain)
            );
            assert_eq!(map.features.len(), 2);
        }
    }

    #[test]
    fn ascii_rejects_empty_ragged_unknown_and_oversized_maps() {
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
    }

    #[test]
    fn lookup_uses_overrides_and_fallback_only_inside_bounds() {
        let forest = Coordinate::new(1, 1);
        let map = Map::new(
            3,
            2,
            Terrain::GrassPlain,
            BTreeMap::from([(forest, Terrain::Forest)]),
        )
        .unwrap();
        assert_eq!(map.tile_at(forest), Some(Terrain::Forest));
        assert_eq!(
            map.tile_at(Coordinate::new(2, 1)),
            Some(Terrain::GrassPlain)
        );
        assert_eq!(map.tile_at(Coordinate::new(3, 1)), None);
        assert_eq!(map.tile_at(Coordinate::new(1, 2)), None);
        assert_eq!(map.features.len(), 1);
    }

    #[test]
    fn rejects_empty_maps_and_out_of_bounds_overrides() {
        assert_eq!(
            Map::new(0, 2, Terrain::GrassPlain, BTreeMap::new()),
            Err(MapError::EmptyDimensions)
        );
        assert_eq!(
            Map::new(2, 0, Terrain::GrassPlain, BTreeMap::new()),
            Err(MapError::EmptyDimensions)
        );
        let position = Coordinate::new(2, 0);
        assert_eq!(
            Map::new(
                2,
                2,
                Terrain::GrassPlain,
                BTreeMap::from([(position, Terrain::Hills)])
            ),
            Err(MapError::PositionOutOfBounds(position))
        );
    }
}
