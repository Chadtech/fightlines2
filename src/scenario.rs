use crate::map::{Coordinate, Map, MapError};
use juniper::{GraphQLEnum, GraphQLObject, graphql_object};

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Side {
    West,
    East,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum UnitKind {
    Infantry,
    Tank,
    FieldGun,
    SupplyTruck,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct UnitId(u16);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unit {
    id: UnitId,
    side: Side,
    kind: UnitKind,
    position: Coordinate,
}

#[graphql_object]
impl Unit {
    fn id(&self) -> String {
        self.id.0.to_string()
    }

    fn side(&self) -> Side {
        self.side
    }

    fn kind(&self) -> UnitKind {
        self.kind
    }

    fn position(&self) -> Coordinate {
        self.position
    }
}

#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
/// A supply building, separate from terrain and units; ownership is optional.
pub struct Depot {
    position: Coordinate,
    owner: Option<Side>,
}

/// Initial board state. Resource quantities and turn rules are not defined yet.
#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct Scenario {
    map: Map,
    depots: Vec<Depot>,
    units: Vec<Unit>,
}

impl Scenario {
    pub fn supply_point() -> Result<Self, MapError> {
        // Space = grass, # = forest, % = hills. Each row is 17 cells.
        let map = Map::from_ascii(concat!(
            "                 \n",
            " ###   % %   ### \n",
            " ##  ##%%%##  ## \n",
            "   % ##%%%## %   \n",
            "   %% #%%%# %%   \n",
            " #  %       %  # \n",
            " #   ##% %##   # \n",
            "     #     #     \n",
            "                 \n",
            "     #     #     \n",
            " #   ##% %##   # \n",
            " #  %       %  # \n",
            "   %% #%%%# %%   \n",
            "   % ##%%%## %   \n",
            " ##  ##%%%##  ## \n",
            " ###   % %   ### \n",
            "                 \n",
        ))?;
        let depots = vec![
            Depot {
                position: Coordinate::new(2, 8),
                owner: Some(Side::West),
            },
            Depot {
                position: Coordinate::new(8, 8),
                owner: None,
            },
            Depot {
                position: Coordinate::new(14, 8),
                owner: Some(Side::East),
            },
        ];
        let mut units = Vec::new();
        for side in [Side::West, Side::East] {
            for (index, (kind, x, y)) in [
                (UnitKind::Infantry, 3, 7),
                (UnitKind::Infantry, 3, 8),
                (UnitKind::Infantry, 3, 9),
                (UnitKind::SupplyTruck, 2, 7),
                (UnitKind::SupplyTruck, 2, 9),
            ]
            .into_iter()
            .enumerate()
            {
                let (offset, x) = match side {
                    Side::West => (0, x),
                    Side::East => (5, 16 - x),
                };
                units.push(Unit {
                    id: UnitId(offset + index as u16 + 1),
                    side,
                    kind,
                    position: Coordinate::new(x, y),
                });
            }
        }
        for (side, first_id, x) in [(Side::West, 11, 4), (Side::East, 14, 12)] {
            for (index, (kind, y)) in [
                (UnitKind::Tank, 8),
                (UnitKind::FieldGun, 7),
                (UnitKind::FieldGun, 9),
            ]
            .into_iter()
            .enumerate()
            {
                units.push(Unit {
                    id: UnitId(first_id + index as u16),
                    side,
                    kind,
                    position: Coordinate::new(x, y),
                });
            }
        }
        for position in units
            .iter()
            .map(|unit| unit.position)
            .chain(depots.iter().map(|depot| depot.position))
        {
            if map.tile_at(position).is_none() {
                return Err(MapError::PositionOutOfBounds(position));
            }
        }
        Ok(Self { map, depots, units })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map::Terrain;
    use std::collections::BTreeSet;

    #[test]
    fn starting_forces_are_unique_in_bounds_and_mirrored() {
        let scenario = Scenario::supply_point().unwrap();
        assert_eq!(scenario.units.len(), 16);
        assert_eq!(
            scenario
                .units
                .iter()
                .map(|unit| unit.id)
                .collect::<BTreeSet<_>>()
                .len(),
            16
        );
        assert_eq!(
            scenario
                .units
                .iter()
                .map(|unit| unit.position)
                .collect::<BTreeSet<_>>()
                .len(),
            16
        );
        for side in [Side::West, Side::East] {
            for (kind, expected) in [
                (UnitKind::Infantry, 3),
                (UnitKind::SupplyTruck, 2),
                (UnitKind::Tank, 1),
                (UnitKind::FieldGun, 2),
            ] {
                assert_eq!(
                    scenario
                        .units
                        .iter()
                        .filter(|unit| unit.side == side && unit.kind == kind)
                        .count(),
                    expected
                );
            }
        }
        for unit in &scenario.units {
            assert_eq!(
                scenario.map.tile_at(unit.position),
                Some(Terrain::GrassPlain)
            );
            assert!(
                !scenario
                    .depots
                    .iter()
                    .any(|depot| depot.position == unit.position)
            );
        }
        let west_units = scenario.units.iter().filter(|unit| unit.side == Side::West);
        let east_units = scenario.units.iter().filter(|unit| unit.side == Side::East);
        for (west, east) in west_units.zip(east_units) {
            assert_eq!(west.kind, east.kind);
            assert_eq!(west.position.y(), east.position.y());
            assert_eq!(west.position.x() + east.position.x(), 16);
        }
        for y in 0..17 {
            for x in 0..17 {
                assert_eq!(
                    scenario.map.tile_at(Coordinate::new(x, y)),
                    scenario.map.tile_at(Coordinate::new(16 - x, y))
                );
            }
        }
    }

    #[test]
    fn supply_point_has_a_centered_depot_and_abundant_terrain() {
        let scenario = Scenario::supply_point().unwrap();
        assert!(scenario.map.contains(Coordinate::new(16, 16)));
        assert!(!scenario.map.contains(Coordinate::new(17, 16)));
        assert!(!scenario.map.contains(Coordinate::new(16, 17)));
        let center = Coordinate::new(8, 8);
        assert_eq!(scenario.depots[1].position, center);
        assert_eq!(scenario.depots[0].position.y(), center.y());
        assert_eq!(scenario.depots[2].position.y(), center.y());
        assert_eq!(
            center.x() - scenario.depots[0].position.x(),
            scenario.depots[2].position.x() - center.x()
        );
        for (terrain, minimum) in [(Terrain::Forest, 60), (Terrain::Hills, 40)] {
            let count = (0..17)
                .flat_map(|y| (0..17).map(move |x| Coordinate::new(x, y)))
                .filter(|position| scenario.map.tile_at(*position) == Some(terrain))
                .count();
            assert!(count >= minimum);
        }
        for x in 0..17 {
            assert_eq!(
                scenario.map.tile_at(Coordinate::new(x, 8)),
                Some(Terrain::GrassPlain)
            );
        }
    }

    #[test]
    fn depots_are_separate_from_terrain_and_include_a_neutral_center() {
        let scenario = Scenario::supply_point().unwrap();
        assert_eq!(scenario.depots.len(), 3);
        assert_eq!(scenario.depots[0].owner, Some(Side::West));
        assert_eq!(scenario.depots[1].owner, None);
        assert_eq!(scenario.depots[1].position, Coordinate::new(8, 8));
        assert_eq!(scenario.depots[2].owner, Some(Side::East));
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
        assert_eq!(scenario, Scenario::supply_point().unwrap());
    }
}
