use crate::map::{Coordinate, Map, MapError, MapTheme};
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
    Truck,
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
            UnitKind::Tank | UnitKind::Truck => Some(Self {
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
            UnitKind::Tank | UnitKind::Truck => 0,
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
            UnitKind::Truck => 2,
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
/// A neutral supply building, separate from terrain and units.
pub struct Depot {
    position: Coordinate,
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

    pub fn rotate(&mut self, direction: Direction) {
        if self.direction.is_some() {
            self.direction = Some(direction);
        }
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

/// One player's authored formation, mirrored horizontally for the opposing side.
struct StartingUnit {
    kind: UnitKind,
    position: Coordinate,
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
            (UnitKind::Truck, UnitKind::Infantry | UnitKind::FieldGun) => (mover, target),
            (UnitKind::Infantry | UnitKind::FieldGun, UnitKind::Truck) => (target, mover),
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
            let at_depot = self
                .depots
                .iter()
                .any(|depot| Some(depot.position) == unit.board_position());
            if at_depot && let Some(fuel) = &mut unit.fuel {
                fuel.current = fuel.maximum;
            }
        }
    }

    pub fn el_alamein() -> Result<Self, MapError> {
        // Two desert passes divide the ridge; the southern outpost has a plateau.
        let map = Map::from_ascii(concat!(
            "%.......................%\n",
            "%.......................%\n",
            "%........%..............%\n",
            "%........%%%............%\n",
            "%........%%%%...........%\n",
            "%........%%%%...........%\n",
            "%.......................%\n",
            "%........%%%%...........%\n",
            "%........%%%............%\n",
            "%........%%%.%..........%\n",
            "%............%..........%\n",
            "%........%%.%%..........%\n",
            "%........%%..%%.........%\n",
            "%........%%%.%%.........%\n",
            "%........%...%%.........%\n",
            "%........%...%%.........%\n",
            "%........%...%%.........%\n",
            "%.........%%%%%.........%\n",
            "%.........%%%%..........%\n",
            "%.......................%\n",
            "%.......%%%%%%%%%%%%%%%%%\n",
        ))?
        .with_theme(MapTheme::Desert);
        Self::with_deployment(
            map,
            vec![
                Depot {
                    position: Coordinate::new(11, 2),
                },
                Depot {
                    position: Coordinate::new(11, 15),
                },
                Depot {
                    position: Coordinate::new(16, 6),
                },
                Depot {
                    position: Coordinate::new(4, 8),
                },
                Depot {
                    position: Coordinate::new(4, 10),
                },
                Depot {
                    position: Coordinate::new(20, 11),
                },
                Depot {
                    position: Coordinate::new(20, 13),
                },
            ],
            &[
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 5),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(6, 5),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 7),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 11),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 13),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(6, 13),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 4),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 7),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 9),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 11),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 14),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(4, 6),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(4, 12),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 6),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 9),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 12),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 15),
                },
            ],
            3,
        )
    }

    pub fn blood_gulch() -> Result<Self, MapError> {
        // Broad, uneven canyon walls and winding shelves exaggerate the original
        // contours at tile scale while leaving both bases and the middle route open.
        // Forest patches (#) provide concealed hiding spots along the canyon walls.
        let map = Map::from_ascii(concat!(
            "%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%..#%%%%#.#%..%%%%%%%\n",
            "%%%%....#..#...#%..%..%%.\n",
            "%%%......%%......%#......\n",
            "%%......#...............%\n",
            "%......%%%..............%\n",
            "%......%%%%.............%\n",
            "%.......%%%%............%\n",
            "%........%%.............%\n",
            "%..............%%.......%\n",
            "%.............%%%%......%\n",
            "%............%%%%%......%\n",
            "%%.....................%%\n",
            "%%%...................%%%\n",
            "%%%%.............%%##%%%%\n",
            "%%%%%...%%%%%%..%%%%%%%%%\n",
            "%%%%%.%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%\n",
        ))?;
        Self::with_deployment(
            map,
            vec![
                Depot {
                    position: Coordinate::new(2, 10),
                },
                Depot {
                    position: Coordinate::new(22, 10),
                },
                // Flank objectives approximate the original teleporter exits.
                Depot {
                    position: Coordinate::new(15, 6),
                },
                Depot {
                    position: Coordinate::new(9, 14),
                },
            ],
            &[
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(5, 7),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(5, 9),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(5, 11),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 8),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 10),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 12),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(3, 10),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(3, 12),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 9),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(2, 11),
                },
            ],
            0,
        )
    }

    pub fn arabia() -> Result<Self, MapError> {
        let map = Map::from_ascii(concat!(
            ".........................\n",
            ".........................\n",
            ".....##....%%............\n",
            ".....#.....%....##.......\n",
            "..%%............#........\n",
            "..%..........#.......##..\n",
            "......#...##......#..#...\n",
            "..........#..............\n",
            ".........................\n",
            "...............%%........\n",
            "...............%.........\n",
            ".........................\n",
            "........%%..#............\n",
            "........%................\n",
            ".........................\n",
            ".........................\n",
            "..##.............##......\n",
            "..#....%%........#.......\n",
            ".......%..#....#.....%%..\n",
            ".....................%...\n",
            ".........................\n",
        ))?
        .with_theme(MapTheme::Desert);
        Self::with_deployment(
            map,
            vec![
                Depot {
                    position: Coordinate::new(2, 10),
                },
                Depot {
                    position: Coordinate::new(22, 10),
                },
            ],
            &[
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 8),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 10),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(4, 12),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(3, 9),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(3, 11),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 10),
                },
            ],
            0,
        )
    }

    /// Snowy horseshoe: a long open loop, wooded shortcut, and two deep rear depots.
    pub fn sidewinder() -> Result<Self, MapError> {
        let map = Map::from_ascii(concat!(
            "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%###################%%%%%%%\n",
            "%%%%%%%#..#############..#%%%%%%%\n",
            "%%%%%%%#..#############..#%%%%%%%\n",
            "%%%%%%%#..#############..#%%%%%%%\n",
            "%%%%%%%#..#############..#%%%%%%%\n",
            "%%%%%%%#..#############..#%%%%%%%\n",
            "%%%.......###.......###.......%%%\n",
            "%%%.......###.#####.###.......%%%\n",
            "%%%...........#####...........%%%\n",
            "%%%.......#############.......%%%\n",
            "%%%.......#############.......%%%\n",
            "%%%.......#############.......%%%\n",
            "%%%.......#############.......%%%\n",
            "%%%......###############......%%%\n",
            "%%%......###############......%%%\n",
            "%%%.......#############.......%%%\n",
            "%%%%.......###########.......%%%%\n",
            "%%%%.#....#############....#.%%%%\n",
            "%%%%%......###########......%%%%%\n",
            "%%%%%.......#########.......%%%%%\n",
            "%%%%%%.....#.%%%%%%%.#.....%%%%%%\n",
            "%%%%%%.....................%%%%%%\n",
            "%%%%%%.....................%%%%%%\n",
            "%%%%%%.....................%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n",
            "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\n",
        ))?
        .with_theme(MapTheme::Snow);
        Self::with_deployment(
            map,
            vec![
                Depot {
                    position: Coordinate::new(8, 3),
                },
                Depot {
                    position: Coordinate::new(24, 3),
                },
            ],
            &[
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 11),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(8, 12),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(7, 13),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(8, 14),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(6, 12),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(6, 14),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(4, 11),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(5, 15),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(5, 9),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 9),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(4, 8),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(6, 8),
                },
            ],
            0,
        )
    }

    /// Two large supplied clearings separated by thick forest and a single narrow passage.
    pub fn black_forest() -> Result<Self, MapError> {
        // Loose trees and grass pockets feather selected clearing edges for infiltration.
        let map = Map::from_ascii(concat!(
            "#################################\n",
            "#################################\n",
            "#####...#################...#####\n",
            "###......###############......###\n",
            "#####.....#############.....#####\n",
            "#####.####.###########.####.#####\n",
            "#####.####.#.#######.#.####.#####\n",
            "###........#..#####..#........###\n",
            "#..........###########..........#\n",
            "##.#...........###...........#.##\n",
            "#.#.........##.###.##.........#.#\n",
            ".##........###.###.###........##.\n",
            "#..........###.....###..........#\n",
            ".#............#####............#.\n",
            "##.#........#########........#.##\n",
            "#.#........##.#####.##........#.#\n",
            "##..........#########..........##\n",
            "##.#.......#.#######.#.......#.##\n",
            "##........#...#####...#........##\n",
            "###..#.....###########.....#..###\n",
            "####...#..#.#########.#..#...####\n",
            "#####....#.###########.#....#####\n",
            "########.###############.########\n",
            "#################################\n",
            "#################################\n",
        ))?
        .with_theme(MapTheme::GreenForest);
        Self::with_deployment(
            map,
            vec![
                Depot {
                    position: Coordinate::new(6, 3),
                },
                Depot {
                    position: Coordinate::new(4, 10),
                },
                Depot {
                    position: Coordinate::new(4, 16),
                },
                Depot {
                    position: Coordinate::new(10, 12),
                },
                Depot {
                    position: Coordinate::new(26, 3),
                },
                Depot {
                    position: Coordinate::new(28, 10),
                },
                Depot {
                    position: Coordinate::new(28, 16),
                },
                Depot {
                    position: Coordinate::new(22, 12),
                },
            ],
            &[
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 7),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 9),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 11),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 13),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 15),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(9, 17),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(10, 10),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(10, 14),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(8, 8),
                },
                StartingUnit {
                    kind: UnitKind::Infantry,
                    position: Coordinate::new(8, 16),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 7),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 9),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 11),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 13),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 15),
                },
                StartingUnit {
                    kind: UnitKind::FieldGun,
                    position: Coordinate::new(7, 17),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(5, 12),
                },
                StartingUnit {
                    kind: UnitKind::Truck,
                    position: Coordinate::new(5, 14),
                },
                StartingUnit {
                    kind: UnitKind::Tank,
                    position: Coordinate::new(8, 12),
                },
            ],
            0,
        )
    }

    /// Map-specific formations share initialization and face the opposing force.
    fn with_deployment(
        map: Map,
        depots: Vec<Depot>,
        formation: &[StartingUnit],
        player2_south_offset: u16,
    ) -> Result<Self, MapError> {
        for starting in formation {
            if !map.contains(starting.position) {
                return Err(MapError::PositionOutOfBounds(starting.position));
            }
        }
        let mut units = Vec::new();
        for side in [Side::Player1, Side::Player2] {
            for starting in formation {
                let position = match side {
                    Side::Player1 => starting.position,
                    Side::Player2 => Coordinate::new(
                        (map.width() - 1 - starting.position.x()) as u16,
                        starting.position.y() as u16 + player2_south_offset,
                    ),
                };
                units.push(Unit {
                    id: UnitId(units.len() as u16 + 1),
                    side,
                    kind: starting.kind,
                    hit_points: HitPoints::full(),
                    fuel: Fuel::for_kind(starting.kind),
                    supplies: Supplies::for_kind(starting.kind),
                    location: Location::OnMap(position),
                    direction: match starting.kind {
                        UnitKind::Truck => None,
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
            if !map.contains(position) {
                return Err(MapError::PositionOutOfBounds(position));
            }
        }
        Ok(Self { map, depots, units })
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
            },
            Depot {
                position: Coordinate::new(8, 8),
            },
            Depot {
                position: Coordinate::new(14, 8),
            },
        ];
        let mut units = Vec::new();
        for side in [Side::Player1, Side::Player2] {
            for (index, (kind, x, y)) in [
                (UnitKind::Infantry, 3, 7),
                (UnitKind::Infantry, 3, 8),
                (UnitKind::Infantry, 3, 9),
                (UnitKind::Truck, 2, 7),
                (UnitKind::Truck, 2, 9),
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
                        UnitKind::Truck => None,
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
                        UnitKind::Truck => None,
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
    fn map_themes_are_independent_of_base_terrain() {
        for map_type in [
            crate::map_type::MapType::SupplyPoint,
            crate::map_type::MapType::ElAlamein,
            crate::map_type::MapType::BloodGulch,
            crate::map_type::MapType::Arabia,
            crate::map_type::MapType::Sidewinder,
            crate::map_type::MapType::BlackForest,
        ] {
            let scenario = map_type.scenario().unwrap();
            let expected = match map_type {
                crate::map_type::MapType::ElAlamein | crate::map_type::MapType::Arabia => {
                    MapTheme::Desert
                }
                crate::map_type::MapType::SupplyPoint => MapTheme::GreenForest,
                crate::map_type::MapType::BloodGulch | crate::map_type::MapType::BlackForest => {
                    MapTheme::GreenForest
                }
                crate::map_type::MapType::Sidewinder => MapTheme::Snow,
            };
            assert_eq!(scenario.map.theme(), expected);
            let original_visibility = crate::visibility::visible_tiles(&scenario, Side::Player1);
            for theme in [MapTheme::GreenForest, MapTheme::Desert, MapTheme::Snow] {
                let mut themed = scenario.clone();
                themed.map = themed.map.with_theme(theme);
                assert_eq!(
                    crate::visibility::visible_tiles(&themed, Side::Player1),
                    original_visibility
                );
            }
        }
    }

    #[test]
    fn new_maps_have_supplied_clearings_and_valid_starting_forces() {
        for map_type in [
            crate::map_type::MapType::ElAlamein,
            crate::map_type::MapType::BloodGulch,
            crate::map_type::MapType::Arabia,
            crate::map_type::MapType::Sidewinder,
            crate::map_type::MapType::BlackForest,
        ] {
            let scenario = map_type.scenario().unwrap();
            let expected = match map_type {
                crate::map_type::MapType::ElAlamein => [5, 6, 2, 4],
                crate::map_type::MapType::BloodGulch => [6, 1, 1, 2],
                crate::map_type::MapType::Arabia => [3, 1, 2, 0],
                crate::map_type::MapType::Sidewinder => [6, 2, 2, 2],
                crate::map_type::MapType::BlackForest => [10, 1, 6, 2],
                crate::map_type::MapType::SupplyPoint => [3, 1, 2, 2],
            };
            let per_side: usize = expected.iter().sum();
            let dimensions = match map_type {
                crate::map_type::MapType::Sidewinder => (33, 29),
                crate::map_type::MapType::BlackForest => (33, 25),
                _ => (25, 21),
            };
            assert_eq!((scenario.map.width(), scenario.map.height()), dimensions);
            assert_eq!(scenario.units.len(), per_side * 2);
            assert_eq!(
                scenario
                    .units
                    .iter()
                    .map(|unit| unit.id)
                    .collect::<BTreeSet<_>>()
                    .len(),
                scenario.units.len()
            );
            assert_eq!(
                scenario
                    .units
                    .iter()
                    .filter_map(Unit::board_position)
                    .collect::<BTreeSet<_>>()
                    .len(),
                scenario.units.len()
            );
            for unit in &scenario.units {
                let position = unit.board_position().unwrap();
                assert_eq!(scenario.map.tile_at(position), Some(Terrain::GrassPlain));
                assert!(
                    !scenario
                        .depots
                        .iter()
                        .any(|depot| depot.position == position)
                );
                assert_eq!(unit.supplies, Supplies::for_kind(unit.kind));
                assert_eq!(unit.hit_points, HitPoints::full());
                assert_eq!(unit.fuel, Fuel::for_kind(unit.kind));
                let expected_direction = match unit.kind {
                    UnitKind::Truck => None,
                    _ => Some(Direction::starting(unit.side)),
                };
                assert_eq!(unit.direction, expected_direction);
            }
            for side in [Side::Player1, Side::Player2] {
                for (kind, count) in [
                    UnitKind::Infantry,
                    UnitKind::Tank,
                    UnitKind::FieldGun,
                    UnitKind::Truck,
                ]
                .into_iter()
                .zip(expected)
                {
                    assert_eq!(
                        scenario
                            .units
                            .iter()
                            .filter(|unit| unit.side == side && unit.kind == kind)
                            .count(),
                        count
                    );
                }
            }
            let player1 = scenario
                .units
                .iter()
                .filter(|unit| unit.side == Side::Player1);
            let player2 = scenario
                .units
                .iter()
                .filter(|unit| unit.side == Side::Player2);
            for (left, right) in player1.zip(player2) {
                assert_eq!(left.kind, right.kind);
                let left_position = left.board_position().unwrap();
                let right_position = right.board_position().unwrap();
                assert_eq!(
                    left_position.x() + right_position.x(),
                    scenario.map.width() - 1
                );
                let south_offset = match map_type {
                    crate::map_type::MapType::ElAlamein => 3,
                    _ => 0,
                };
                assert_eq!(left_position.y() + south_offset, right_position.y());
            }
            assert_eq!(scenario, map_type.scenario().unwrap());
        }
    }

    /// Cardinal open-ground distance ignores units, matching the map's route geometry.
    fn open_route_length(map: &Map, start: Coordinate, end: Coordinate) -> Option<usize> {
        let mut visited = BTreeSet::from([start]);
        let mut frontier = std::collections::VecDeque::from([(start, 0)]);
        while let Some((position, distance)) = frontier.pop_front() {
            if position == end {
                return Some(distance);
            }
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                let x = position.x() + dx;
                let y = position.y() + dy;
                if x < 0 || y < 0 {
                    continue;
                }
                let neighbor = Coordinate::new(x as u16, y as u16);
                if map.tile_at(neighbor) == Some(Terrain::GrassPlain) && visited.insert(neighbor) {
                    frontier.push_back((neighbor, distance + 1));
                }
            }
        }
        None
    }

    fn forest_at(map: &Map, blocked: Coordinate) -> Map {
        let mut sketch = String::new();
        for y in 0..map.height() {
            for x in 0..map.width() {
                let position = Coordinate::new(x as u16, y as u16);
                let symbol = if position == blocked {
                    '#'
                } else {
                    match map.tile_at(position).unwrap() {
                        Terrain::GrassPlain => '.',
                        Terrain::Forest => '#',
                        Terrain::Hills => '%',
                    }
                };
                sketch.push(symbol);
            }
            sketch.push('\n');
        }
        Map::from_ascii(&sketch).unwrap()
    }

    #[test]
    fn sidewinder_has_enclosed_depots_and_a_clear_winding_shortcut() {
        let scenario = Scenario::sidewinder().unwrap();
        let rear = Coordinate::new(8, 3);
        let opposing_rear = Coordinate::new(24, 3);
        assert_eq!(scenario.depots.len(), 2);
        assert_eq!(scenario.depots[0].position, rear);
        assert_eq!(scenario.depots[1].position, opposing_rear);
        for (left_edge, right_edge) in [(8, 9), (23, 24)] {
            for x in left_edge..=right_edge {
                assert_eq!(
                    scenario.map.tile_at(Coordinate::new(x, 2)),
                    Some(Terrain::Forest)
                );
            }
            for y in 3..8 {
                for x in left_edge..=right_edge {
                    assert_eq!(
                        scenario.map.tile_at(Coordinate::new(x, y)),
                        Some(Terrain::GrassPlain)
                    );
                }
                assert_eq!(
                    scenario.map.tile_at(Coordinate::new(left_edge - 1, y)),
                    Some(Terrain::Forest)
                );
                assert_eq!(
                    scenario.map.tile_at(Coordinate::new(right_edge + 1, y)),
                    Some(Terrain::Forest)
                );
            }
        }
        let shortcut = open_route_length(&scenario.map, rear, opposing_rear).unwrap();
        let closed_shortcut = forest_at(&scenario.map, Coordinate::new(16, 8));
        let outer_loop = open_route_length(&closed_shortcut, rear, opposing_rear).unwrap();
        assert_eq!(shortcut, 34);
        assert_eq!(outer_loop, 56);
        assert!(outer_loop >= shortcut * 3 / 2);
        // Even the shortcut needs a depot stop to complete a round trip on 64 fuel.
        assert!(shortcut * 2 > 64);
        for position in [
            Coordinate::new(13, 10),
            Coordinate::new(13, 8),
            Coordinate::new(19, 8),
            Coordinate::new(19, 10),
        ] {
            assert_eq!(scenario.map.tile_at(position), Some(Terrain::GrassPlain));
        }
        for y in [7, 9] {
            assert_eq!(
                scenario.map.tile_at(Coordinate::new(16, y)),
                Some(Terrain::Forest)
            );
        }
    }

    #[test]
    fn black_forest_has_a_winding_passage_and_separate_supply_glades() {
        let scenario = Scenario::black_forest().unwrap();
        assert_eq!(scenario.depots.len(), 8);
        assert_eq!(
            scenario
                .depots
                .iter()
                .map(|depot| depot.position)
                .collect::<BTreeSet<_>>()
                .len(),
            8
        );
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
        let left = Coordinate::new(4, 10);
        let right = Coordinate::new(28, 10);
        // The connecting passage bends, adding distance over a straight crossing.
        assert_eq!(open_route_length(&scenario.map, left, right), Some(32));
        let closed_passage = forest_at(&scenario.map, Coordinate::new(16, 12));
        assert_eq!(open_route_length(&closed_passage, left, right), None);
        for (pocket, main, neck) in [
            (Coordinate::new(6, 3), left, Coordinate::new(5, 5)),
            (Coordinate::new(26, 3), right, Coordinate::new(27, 5)),
        ] {
            assert!(scenario.depots.iter().any(|depot| depot.position == pocket));
            assert_eq!(open_route_length(&scenario.map, pocket, main), Some(9));
            let closed_neck = forest_at(&scenario.map, neck);
            assert_eq!(open_route_length(&closed_neck, pocket, main), None);
            assert_eq!(open_route_length(&closed_neck, left, right), Some(32));
        }
    }

    #[test]
    fn el_alamein_has_ridge_objectives_and_rear_supply_depots() {
        let scenario = Scenario::el_alamein().unwrap();
        assert_eq!(
            scenario
                .depots
                .iter()
                .map(|depot| depot.position)
                .collect::<Vec<_>>(),
            vec![
                Coordinate::new(11, 2),
                Coordinate::new(11, 15),
                Coordinate::new(16, 6),
                Coordinate::new(4, 8),
                Coordinate::new(4, 10),
                Coordinate::new(20, 11),
                Coordinate::new(20, 13),
            ]
        );
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
        for y in [4, 8, 12, 18] {
            assert_eq!(
                scenario.map.tile_at(Coordinate::new(10, y)),
                Some(Terrain::Hills)
            );
        }
        for y in [6, 10] {
            for x in 8..=14 {
                assert_eq!(
                    scenario.map.tile_at(Coordinate::new(x, y)),
                    Some(Terrain::GrassPlain)
                );
            }
        }
    }

    #[test]
    fn blood_gulch_has_base_and_flank_supply_depots() {
        let scenario = Scenario::blood_gulch().unwrap();
        assert_eq!(
            scenario
                .depots
                .iter()
                .map(|depot| depot.position)
                .collect::<Vec<_>>(),
            vec![
                Coordinate::new(2, 10),
                Coordinate::new(22, 10),
                Coordinate::new(15, 6),
                Coordinate::new(9, 14),
            ]
        );
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
    }

    #[test]
    fn blood_gulch_forests_provide_concealed_hiding_spots() {
        let mut scenario = Scenario::blood_gulch().unwrap();
        assert_eq!(scenario.map.theme(), MapTheme::GreenForest);
        let forest = (0..scenario.map.height())
            .flat_map(|y| {
                (0..scenario.map.width()).map(move |x| Coordinate::new(x as u16, y as u16))
            })
            .find(|position| scenario.map.tile_at(*position) == Some(Terrain::Forest))
            .unwrap();
        let observer = scenario
            .units
            .iter_mut()
            .find(|unit| unit.side == Side::Player1)
            .unwrap();
        observer.location =
            Location::OnMap(Coordinate::new(forest.x() as u16, (forest.y() + 1) as u16));
        let enemy = scenario
            .units
            .iter_mut()
            .find(|unit| unit.side == Side::Player2)
            .unwrap();
        let enemy_id = enemy.id;
        enemy.location = Location::OnMap(forest);
        let visible = crate::visibility::visible_tiles(&scenario, Side::Player1);
        assert!(!visible.contains(&forest));
        let observed = crate::visibility::observed_scenario(&scenario, Side::Player1, &visible);
        assert!(!observed.units.iter().any(|unit| unit.id == enemy_id));
    }

    #[test]
    fn blood_gulch_has_a_canyon_and_arabia_is_mostly_open() {
        let gulch = Scenario::blood_gulch().unwrap();
        for x in 0..25 {
            assert_eq!(
                gulch.map.tile_at(Coordinate::new(x, 0)),
                Some(Terrain::Hills)
            );
            assert_eq!(
                gulch.map.tile_at(Coordinate::new(x, 20)),
                Some(Terrain::Hills)
            );
        }
        assert_eq!(
            gulch.map.tile_at(Coordinate::new(12, 10)),
            Some(Terrain::GrassPlain)
        );
        let arabia = Scenario::arabia().unwrap();
        let tiles: Vec<_> = (0..21)
            .flat_map(|y| (0..25).map(move |x| Coordinate::new(x, y)))
            .filter_map(|position| arabia.map.tile_at(position))
            .collect();
        assert!(
            tiles
                .iter()
                .filter(|terrain| **terrain == Terrain::GrassPlain)
                .count()
                > 450
        );
        assert!(tiles.contains(&Terrain::Forest));
        assert!(tiles.contains(&Terrain::Hills));
        for center in [2, 22] {
            for y in 8..=12 {
                for x in center - 1..=center + 1 {
                    assert_eq!(
                        arabia.map.tile_at(Coordinate::new(x, y)),
                        Some(Terrain::GrassPlain)
                    );
                }
            }
        }
    }

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
                UnitKind::Tank | UnitKind::Truck => {
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
            .find(|unit| unit.kind == UnitKind::Truck)
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
                (UnitKind::Truck, 2),
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
                UnitKind::Truck => (None, None),
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
    fn depots_are_separate_from_terrain_and_include_the_center() {
        let scenario = Scenario::supply_point().unwrap();
        assert_eq!(scenario.depots.len(), 3);
        assert_eq!(scenario.depots[1].position, Coordinate::new(8, 8));
        for depot in &scenario.depots {
            assert_eq!(
                scenario.map.tile_at(depot.position),
                Some(Terrain::GrassPlain)
            );
        }
        assert_eq!(scenario, Scenario::supply_point().unwrap());
    }
}
