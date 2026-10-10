use crate::map::{Coordinate, Map, MapError};
use juniper::{GraphQLEnum, GraphQLObject, graphql_object};
use std::fmt;

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

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Direction {
    North,
    East,
    South,
    West,
}

impl Direction {
    fn starting(side: Side) -> Self {
        match side {
            Side::West => Self::East,
            Side::East => Self::West,
        }
    }

    pub fn between(from: Coordinate, to: Coordinate) -> Option<Self> {
        match (to.x() - from.x(), to.y() - from.y()) {
            (0, -1) => Some(Self::North),
            (1, 0) => Some(Self::East),
            (0, 1) => Some(Self::South),
            (-1, 0) => Some(Self::West),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct UnitId(u16);

impl UnitId {
    pub fn parse(value: &str) -> Option<Self> {
        value.parse::<u16>().ok().filter(|id| *id > 0).map(Self)
    }
}

impl fmt::Display for UnitId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

/// One fuel unit powers one traversed tile, independently of movement points.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject)]
pub struct Fuel {
    pub(crate) current: i32,
    maximum: i32,
}

impl Fuel {
    fn for_kind(kind: UnitKind) -> Option<Self> {
        match kind {
            UnitKind::Tank | UnitKind::SupplyTruck => Some(Self {
                current: 16,
                maximum: 16,
            }),
            UnitKind::Infantry | UnitKind::FieldGun => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unit {
    id: UnitId,
    side: Side,
    kind: UnitKind,
    position: Coordinate,
    direction: Option<Direction>,
    fuel: Option<Fuel>,
}

#[graphql_object]
impl Unit {
    pub fn id(&self) -> String {
        self.id.to_string()
    }

    pub fn side(&self) -> Side {
        self.side
    }

    pub fn kind(&self) -> UnitKind {
        self.kind
    }

    pub fn fuel(&self) -> Option<Fuel> {
        self.fuel
    }

    pub fn direction(&self) -> Option<Direction> {
        self.direction
    }

    pub fn position(&self) -> Coordinate {
        self.position
    }
}

#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
/// A supply building, separate from terrain and units; ownership is optional.
pub struct Depot {
    position: Coordinate,
    owner: Option<Side>,
}

/// Current board state, including vehicle fuel. Supplies and combat remain future work.
#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct Scenario {
    pub(crate) map: Map,
    depots: Vec<Depot>,
    pub(crate) units: Vec<Unit>,
}

impl Unit {
    pub fn unit_id(&self) -> UnitId {
        self.id
    }

    pub fn follow_path(&mut self, path: &[Coordinate]) {
        for step in path.windows(2) {
            if self.direction.is_some()
                && let Some(direction) = Direction::between(step[0], step[1])
            {
                self.direction = Some(direction);
            }
        }
        if let Some(fuel) = &mut self.fuel {
            fuel.current -= path.len().saturating_sub(1) as i32;
        }
        if let Some(position) = path.last() {
            self.move_to(*position);
        }
    }

    pub fn move_to(&mut self, position: Coordinate) {
        self.position = position;
    }
}

impl Scenario {
    pub fn refuel_at_home_depots(&mut self) {
        for unit in &mut self.units {
            let at_home_depot = self
                .depots
                .iter()
                .any(|depot| depot.owner == Some(unit.side) && depot.position == unit.position);
            if at_home_depot && let Some(fuel) = &mut unit.fuel {
                fuel.current = fuel.maximum;
            }
        }
    }

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
                    fuel: Fuel::for_kind(kind),
                    position: Coordinate::new(x, y),
                    direction: match kind {
                        UnitKind::SupplyTruck => None,
                        _ => Some(Direction::starting(side)),
                    },
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
                    fuel: Fuel::for_kind(kind),
                    position: Coordinate::new(x, y),
                    direction: match kind {
                        UnitKind::SupplyTruck => None,
                        _ => Some(Direction::starting(side)),
                    },
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
    fn following_paths_turns_units_and_keeps_facing_on_hold() {
        let mut unit = Scenario::supply_point().unwrap().units.remove(0);
        for (from, to, expected) in [
            ((3, 7), (3, 6), Direction::North),
            ((3, 6), (4, 6), Direction::East),
            ((4, 6), (4, 7), Direction::South),
            ((4, 7), (3, 7), Direction::West),
        ] {
            unit.follow_path(&[Coordinate::new(from.0, from.1), Coordinate::new(to.0, to.1)]);
            assert_eq!(unit.direction(), Some(expected));
            assert_eq!(unit.position(), Coordinate::new(to.0, to.1));
        }
        unit.follow_path(&[unit.position()]);
        assert_eq!(unit.direction(), Some(Direction::West));
        unit.follow_path(&[
            Coordinate::new(3, 7),
            Coordinate::new(4, 7),
            Coordinate::new(5, 7),
            Coordinate::new(5, 8),
        ]);
        assert_eq!(unit.direction(), Some(Direction::South));
    }

    #[test]
    fn trucks_have_no_direction_after_moves_or_holds() {
        let mut unit = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.kind == UnitKind::SupplyTruck)
            .unwrap();
        assert_eq!(unit.direction(), None);
        unit.follow_path(&[
            unit.position(),
            Coordinate::new(3, 7),
            Coordinate::new(3, 8),
        ]);
        assert_eq!(unit.position(), Coordinate::new(3, 8));
        assert_eq!(unit.direction(), None);
        unit.follow_path(&[unit.position()]);
        assert_eq!(unit.direction(), None);
    }

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
            let (west_direction, east_direction) = match west.kind {
                UnitKind::SupplyTruck => (None, None),
                _ => (Some(Direction::East), Some(Direction::West)),
            };
            assert_eq!(west.direction(), west_direction);
            assert_eq!(east.direction(), east_direction);
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
