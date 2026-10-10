use crate::map::{Coordinate, Map, MapError};
use juniper::{GraphQLEnum, GraphQLObject, GraphQLUnion, graphql_object};
use std::fmt;

/// Player ownership, independent of starting position on a map.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum Side {
    Player1,
    Player2,
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
            Side::Player1 => Self::East,
            Side::Player2 => Self::West,
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

/// Authoritative health; damage and healing rules remain future work.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject)]
pub struct HitPoints {
    current: i32,
    maximum: i32,
}

impl HitPoints {
    fn full() -> Self {
        Self {
            current: 16,
            maximum: 16,
        }
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
                current: 64,
                maximum: 64,
            }),
            UnitKind::Infantry | UnitKind::FieldGun => None,
        }
    }
}

/// Unit provisions, separate from fuel and any future truck delivery cargo.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Supplies {
    current: i32,
    maximum: i32,
    upkeep_per_turn: i32,
    movement_per_tile: i32,
}

#[graphql_object]
impl Supplies {
    pub fn current(&self) -> i32 {
        self.current
    }
    pub fn maximum(&self) -> i32 {
        self.maximum
    }
    pub fn upkeep_per_turn(&self) -> i32 {
        self.upkeep_per_turn
    }
    pub fn movement_per_tile(&self) -> i32 {
        self.movement_per_tile
    }
}

impl Supplies {
    fn for_kind(kind: UnitKind) -> Self {
        let movement_per_tile = match kind {
            UnitKind::Infantry | UnitKind::FieldGun => 1,
            UnitKind::Tank | UnitKind::SupplyTruck => 0,
        };
        Self {
            current: 64,
            maximum: 64,
            upkeep_per_turn: 1,
            movement_per_tile,
        }
    }

    pub fn can_move(&self, tiles: usize) -> bool {
        let available = (self.current - self.upkeep_per_turn).max(0);
        tiles as i32 * self.movement_per_tile <= available
    }
}

/// A unit either occupies a board square or rides in a carrier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Location {
    OnMap(Coordinate),
    Aboard(UnitId),
}

#[derive(Clone, Copy, GraphQLObject)]
pub struct OnMap {
    position: Coordinate,
}

#[derive(Clone, Copy)]
pub struct Aboard {
    carrier_id: UnitId,
}

#[graphql_object]
impl Aboard {
    fn carrier_id(&self) -> String {
        self.carrier_id.to_string()
    }
}

#[derive(Clone, Copy, GraphQLUnion)]
pub enum UnitLocation {
    OnMap(OnMap),
    Aboard(Aboard),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Unit {
    id: UnitId,
    side: Side,
    kind: UnitKind,
    location: Location,
    direction: Option<Direction>,
    hit_points: HitPoints,
    fuel: Option<Fuel>,
    supplies: Supplies,
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

    pub fn hit_points(&self) -> HitPoints {
        self.hit_points
    }

    pub fn supplies(&self) -> Supplies {
        self.supplies
    }

    pub fn fuel(&self) -> Option<Fuel> {
        self.fuel
    }

    pub fn direction(&self) -> Option<Direction> {
        self.direction
    }

    pub fn cargo_capacity(&self) -> i32 {
        match self.kind {
            UnitKind::SupplyTruck => 2,
            _ => 0,
        }
    }

    pub fn location(&self) -> UnitLocation {
        match self.location {
            Location::OnMap(position) => UnitLocation::OnMap(OnMap { position }),
            Location::Aboard(carrier_id) => UnitLocation::Aboard(Aboard { carrier_id }),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
/// A supply building, separate from terrain and units; ownership is optional.
pub struct Depot {
    position: Coordinate,
    owner: Option<Side>,
}

/// Current board state, including hit points, fuel and supplies. Combat remains future work.
#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct Scenario {
    pub(crate) map: Map,
    depots: Vec<Depot>,
    pub(crate) units: Vec<Unit>,
}

impl Unit {
    pub fn carrier_id(&self) -> Option<UnitId> {
        match self.location {
            Location::OnMap(_) => None,
            Location::Aboard(carrier) => Some(carrier),
        }
    }

    pub fn board_position(&self) -> Option<Coordinate> {
        match self.location {
            Location::OnMap(position) => Some(position),
            Location::Aboard(_) => None,
        }
    }

    pub fn board(&mut self, carrier: UnitId) {
        self.location = Location::Aboard(carrier);
    }

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
        self.supplies.current -=
            path.len().saturating_sub(1) as i32 * self.supplies.movement_per_tile;
        if path.len() > 1
            && let Some(position) = path.last()
        {
            self.move_to(*position);
        }
    }

    pub fn move_to(&mut self, position: Coordinate) {
        self.location = Location::OnMap(position);
    }
}

impl Scenario {
    /// A truck has two unit berths. Unit provisions are independent of cargo.
    pub fn loading_pair(&self, mover: &Unit, target: &Unit) -> Option<(UnitId, UnitId)> {
        if mover.side != target.side
            || mover.carrier_id().is_some()
            || target.carrier_id().is_some()
        {
            return None;
        }
        let (truck, passenger) = match (mover.kind, target.kind) {
            (UnitKind::SupplyTruck, UnitKind::Infantry | UnitKind::FieldGun) => (mover, target),
            (UnitKind::Infantry | UnitKind::FieldGun, UnitKind::SupplyTruck) => (target, mover),
            _ => return None,
        };
        if self
            .units
            .iter()
            .filter(|unit| unit.carrier_id() == Some(truck.id))
            .count()
            >= truck.cargo_capacity() as usize
        {
            None
        } else {
            Some((truck.id, passenger.id))
        }
    }

    /// Resolve physical location without assigning passengers board occupancy.
    /// Missing carriers and carriers that are themselves aboard have no position.
    pub fn physical_position(&self, unit: &Unit) -> Option<Coordinate> {
        match unit.location {
            Location::OnMap(position) => Some(position),
            Location::Aboard(carrier) => self
                .units
                .iter()
                .find(|truck| truck.id == carrier)
                .and_then(Unit::board_position),
        }
    }

    pub fn finish_turn_resources(&mut self) {
        for unit in &mut self.units {
            unit.supplies.current = (unit.supplies.current - unit.supplies.upkeep_per_turn).max(0);
            let at_home_depot = self.depots.iter().any(|depot| {
                depot.owner == Some(unit.side) && Some(depot.position) == unit.board_position()
            });
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
                owner: Some(Side::Player1),
            },
            Depot {
                position: Coordinate::new(8, 8),
                owner: None,
            },
            Depot {
                position: Coordinate::new(14, 8),
                owner: Some(Side::Player2),
            },
        ];
        let mut units = Vec::new();
        for side in [Side::Player1, Side::Player2] {
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
                    Side::Player1 => (0, x),
                    Side::Player2 => (5, 16 - x),
                };
                units.push(Unit {
                    id: UnitId(offset + index as u16 + 1),
                    side,
                    kind,
                    hit_points: HitPoints::full(),
                    fuel: Fuel::for_kind(kind),
                    supplies: Supplies::for_kind(kind),
                    location: Location::OnMap(Coordinate::new(x, y)),
                    direction: match kind {
                        UnitKind::SupplyTruck => None,
                        _ => Some(Direction::starting(side)),
                    },
                });
            }
        }
        for (side, first_id, x) in [(Side::Player1, 11, 4), (Side::Player2, 14, 12)] {
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
                    hit_points: HitPoints::full(),
                    fuel: Fuel::for_kind(kind),
                    supplies: Supplies::for_kind(kind),
                    location: Location::OnMap(Coordinate::new(x, y)),
                    direction: match kind {
                        UnitKind::SupplyTruck => None,
                        _ => Some(Direction::starting(side)),
                    },
                });
            }
        }
        for position in units
            .iter()
            .filter_map(Unit::board_position)
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
    fn passengers_derive_physical_position_without_board_occupancy() {
        let mut scenario = Scenario::supply_point().unwrap();
        let truck_id = UnitId::parse("4").unwrap();
        let passenger_id = UnitId::parse("1").unwrap();
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == passenger_id)
            .unwrap()
            .board(truck_id);
        let destination = Coordinate::new(1, 7);
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == truck_id)
            .unwrap()
            .move_to(destination);
        let passenger = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == passenger_id)
            .unwrap();
        assert_eq!(passenger.location, Location::Aboard(truck_id));
        assert_eq!(passenger.board_position(), None);
        assert_eq!(scenario.physical_position(passenger), Some(destination));

        let mut missing_carrier = passenger.clone();
        missing_carrier.board(UnitId::parse("999").unwrap());
        assert_eq!(scenario.physical_position(&missing_carrier), None);
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == truck_id)
            .unwrap()
            .board(passenger_id);
        assert_eq!(scenario.physical_position(&missing_carrier), None);
        assert_eq!(
            scenario.physical_position(
                scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == passenger_id)
                    .unwrap()
            ),
            None
        );
    }

    #[test]
    fn units_start_with_full_health_and_resources() {
        let mut scenario = Scenario::supply_point().unwrap();
        for unit in &scenario.units {
            assert_eq!(
                unit.hit_points(),
                HitPoints {
                    current: 16,
                    maximum: 16
                }
            );
            assert_eq!(unit.supplies.current, 64);
            assert_eq!(unit.supplies.maximum, 64);
            match unit.kind {
                UnitKind::Tank | UnitKind::SupplyTruck => {
                    assert_eq!(
                        unit.fuel(),
                        Some(Fuel {
                            current: 64,
                            maximum: 64
                        })
                    );
                }
                UnitKind::Infantry | UnitKind::FieldGun => assert_eq!(unit.fuel(), None),
            }
        }
        scenario.units[0].follow_path(&[Coordinate::new(3, 7), Coordinate::new(3, 6)]);
        scenario.finish_turn_resources();
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.hit_points() == HitPoints::full())
        );
    }

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
            assert_eq!(unit.board_position().unwrap(), Coordinate::new(to.0, to.1));
        }
        unit.follow_path(&[unit.board_position().unwrap()]);
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
            unit.board_position().unwrap(),
            Coordinate::new(3, 7),
            Coordinate::new(3, 8),
        ]);
        assert_eq!(unit.board_position().unwrap(), Coordinate::new(3, 8));
        assert_eq!(unit.direction(), None);
        unit.follow_path(&[unit.board_position().unwrap()]);
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
                .filter_map(Unit::board_position)
                .collect::<BTreeSet<_>>()
                .len(),
            16
        );
        for side in [Side::Player1, Side::Player2] {
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
                scenario.map.tile_at(unit.board_position().unwrap()),
                Some(Terrain::GrassPlain)
            );
            assert!(
                !scenario
                    .depots
                    .iter()
                    .any(|depot| Some(depot.position) == unit.board_position())
            );
        }
        let player1_units = scenario
            .units
            .iter()
            .filter(|unit| unit.side == Side::Player1);
        let player2_units = scenario
            .units
            .iter()
            .filter(|unit| unit.side == Side::Player2);
        for (player1, player2) in player1_units.zip(player2_units) {
            let (player1_direction, player2_direction) = match player1.kind {
                UnitKind::SupplyTruck => (None, None),
                _ => (Some(Direction::East), Some(Direction::West)),
            };
            assert_eq!(player1.direction(), player1_direction);
            assert_eq!(player2.direction(), player2_direction);
            assert_eq!(player1.kind, player2.kind);
            assert_eq!(
                player1.board_position().unwrap().y(),
                player2.board_position().unwrap().y()
            );
            assert_eq!(
                player1.board_position().unwrap().x() + player2.board_position().unwrap().x(),
                16
            );
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
        assert_eq!(scenario.depots[0].owner, Some(Side::Player1));
        assert_eq!(scenario.depots[1].owner, None);
        assert_eq!(scenario.depots[1].position, Coordinate::new(8, 8));
        assert_eq!(scenario.depots[2].owner, Some(Side::Player2));
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
        assert_eq!(scenario, Scenario::supply_point().unwrap());
    }
}
