use crate::{
    combat,
    map::{Coordinate, Map, MapError, Terrain},
    map_definition::MapDefinition,
    movement,
    supplies::{self, CargoStock, GroundSupplyCrate, ResourceStock, SupplyRules},
};
use juniper::{GraphQLEnum, GraphQLObject, GraphQLUnion, graphql_object};
use serde::{Deserialize, Serialize};
use std::fmt;

/// Player ownership, independent of starting position on a map.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum PlayerNumber {
    Player1,
    Player2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum UnitKind {
    Infantry,
    Tank,
    FieldGun,
    Truck,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Direction {
    North,
    East,
    South,
    West,
}

/// Horizontal artwork orientation, retained across north/south movement.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum SpriteFacing {
    Left,
    Right,
}

impl SpriteFacing {
    fn starting(player_number: PlayerNumber) -> Self {
        match player_number {
            PlayerNumber::Player1 => Self::Right,
            PlayerNumber::Player2 => Self::Left,
        }
    }

    fn turned(self, direction: Direction) -> Self {
        match direction {
            Direction::West => Self::Left,
            Direction::East => Self::Right,
            Direction::North | Direction::South => self,
        }
    }
}

impl Direction {
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
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

/// Authoritative health; combat applies damage and healing remains future work.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject, Serialize, Deserialize)]
pub struct HitPoints {
    current: i32,
    maximum: i32,
}

impl HitPoints {
    pub fn current(&self) -> i32 {
        self.current
    }

    pub fn maximum(&self) -> i32 {
        self.maximum
    }

    fn full() -> Self {
        Self {
            current: 16,
            maximum: 16,
        }
    }
}

/// Vehicle fuel consumption per traversed tile, independent of movement points.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject, Serialize, Deserialize)]
pub struct Fuel {
    pub(crate) current: i32,
    pub(crate) maximum: i32,
    pub(crate) movement_per_tile: i32,
    pub(crate) movement_per_cargo_slot: i32,
}

impl Fuel {
    fn for_kind(kind: UnitKind) -> Option<Self> {
        match kind {
            UnitKind::Tank | UnitKind::Truck => Some(Self {
                current: 128,
                maximum: 128,
                movement_per_tile: match kind {
                    UnitKind::Tank => 7,
                    UnitKind::Truck => 2,
                    UnitKind::Infantry | UnitKind::FieldGun => 0,
                },
                movement_per_cargo_slot: if kind == UnitKind::Truck { 2 } else { 0 },
            }),
            UnitKind::Infantry | UnitKind::FieldGun => None,
        }
    }
}

/// Unit provisions, separate from fuel and finite supply-crate cargo.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Supplies {
    current: i32,
    maximum: i32,
    upkeep_per_turn: i32,
    movement_per_tile: i32,
    rough_terrain_surcharge: i32,
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
    pub fn rough_terrain_surcharge(&self) -> i32 {
        self.rough_terrain_surcharge
    }
    pub fn movement_per_tile(&self) -> i32 {
        self.movement_per_tile
    }
}

impl Supplies {
    fn for_kind(kind: UnitKind) -> Self {
        let movement_per_tile = match kind {
            UnitKind::Infantry => 9,
            UnitKind::FieldGun => 24,
            UnitKind::Tank => 0,
            UnitKind::Truck => 0,
        };
        let maximum = match kind {
            UnitKind::Tank => 128,
            UnitKind::Truck => 96,
            UnitKind::Infantry => 192,
            UnitKind::FieldGun => 196,
        };
        Self {
            current: maximum,
            maximum,
            upkeep_per_turn: 4,
            movement_per_tile,
            rough_terrain_surcharge: if kind == UnitKind::Infantry { 4 } else { 0 },
        }
    }

    pub fn movement_cost(&self, map: &Map, path: &[Coordinate]) -> i32 {
        path.iter()
            .skip(1)
            .map(|position| {
                let surcharge = match map.tile_at(*position) {
                    Some(Terrain::Hills | Terrain::Forest | Terrain::Mountains) => {
                        self.rough_terrain_surcharge
                    }
                    _ => 0,
                };
                self.movement_per_tile + surcharge
            })
            .sum()
    }

    pub fn can_afford_movement(&self, map: &Map, path: &[Coordinate]) -> bool {
        self.movement_cost(map, path) <= (self.current - self.upkeep_per_turn).max(0)
    }
}

/// A unit either occupies a board square or rides in a carrier.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
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

/// Resource details are disclosed together only for the observing player's units.
#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct UnitResources {
    hit_points: HitPoints,
    supplies: Supplies,
    fuel: Option<Fuel>,
    supply_cargo: Vec<CargoStock>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum Entrenchment {
    Exposed,
    Entrenched,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Unit {
    /// Response-only replay inspection; never changes saved authoritative state.
    #[serde(skip)]
    pub(crate) combat_state: Option<combat::CombatState>,
    entrenchment: Entrenchment,
    id: UnitId,
    player_number: PlayerNumber,
    kind: UnitKind,
    location: Location,
    direction: Option<Direction>,
    sprite_facing: SpriteFacing,
    hit_points: HitPoints,
    fuel: Option<Fuel>,
    supplies: Supplies,
    resources_visible: bool,
    firing_position_revealed: bool,
    pub(crate) supply_cargo: Vec<CargoStock>,
}

struct MovementCost {
    fuel: i32,
    supplies: i32,
}

#[graphql_object]
impl Unit {
    pub fn combat_state(&self) -> Option<combat::CombatState> {
        self.combat_state
    }
    pub fn entrenchment(&self) -> Entrenchment {
        self.entrenchment
    }

    pub fn id(&self) -> String {
        self.id.to_string()
    }

    pub fn player_number(&self) -> PlayerNumber {
        self.player_number
    }

    pub fn kind(&self) -> UnitKind {
        self.kind
    }

    #[graphql(ignore)]
    pub fn hit_points(&self) -> HitPoints {
        self.hit_points
    }

    #[graphql(ignore)]
    pub fn supplies(&self) -> Supplies {
        self.supplies
    }

    #[graphql(ignore)]
    pub fn fuel(&self) -> Option<Fuel> {
        self.fuel
    }

    pub fn resources(&self) -> Option<UnitResources> {
        self.resources_visible.then_some(UnitResources {
            hit_points: self.hit_points(),
            supplies: self.supplies(),
            fuel: self.fuel(),
            supply_cargo: self.supply_cargo.clone(),
        })
    }

    pub fn direction(&self) -> Option<Direction> {
        self.direction
    }

    pub fn sprite_facing(&self) -> SpriteFacing {
        self.sprite_facing
    }

    pub fn destroyed(&self) -> bool {
        !self.is_alive() || self.supplies.current == 0
    }

    pub fn combat_rules(&self) -> combat::CombatRules {
        combat::rules(self.kind)
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
/// Resource identity for ground freight, truck cargo, and replenishment.
pub enum ResourceKind {
    Supply,
    Fuel,
}

/// Neutral buildings share damage, fog memory, and sabotage rules.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum BuildingKind {
    Supply,
    Fuel,
    Fortress,
}

impl BuildingKind {
    pub fn resource_kind(self) -> Option<ResourceKind> {
        match self {
            Self::Supply => Some(ResourceKind::Supply),
            Self::Fuel => Some(ResourceKind::Fuel),
            Self::Fortress => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Depot {
    pub(crate) kind: BuildingKind,
    pub(crate) position: Coordinate,
    pub(crate) stock: ResourceStock,
    /// Fog projection gate: known depot positions remain visible, but unseen stock is withheld.
    pub(crate) stock_visible: bool,
    /// Structural shell hits, independent of unit combat damage. Old archives start intact.
    #[serde(default)]
    pub(crate) damage: i32,
}

#[derive(Clone, Copy, Debug, GraphQLObject, PartialEq, Eq, Serialize, Deserialize)]
pub struct DepotHp {
    pub current: i32,
    pub maximum: i32,
}

impl Depot {
    pub fn new(kind: BuildingKind, position: Coordinate) -> Self {
        let stock = match kind.resource_kind() {
            Some(_) => ResourceStock::depot(),
            None => ResourceStock {
                current: 0,
                maximum: 0,
            },
        };
        Self {
            kind,
            position,
            stock,
            stock_visible: true,
            damage: 0,
        }
    }

    pub fn hit_points(&self) -> DepotHp {
        let maximum = match self.kind {
            BuildingKind::Fuel => 1,
            BuildingKind::Supply => 3,
            BuildingKind::Fortress => 8,
        };
        DepotHp {
            current: (maximum - self.damage).max(0),
            maximum,
        }
    }

    pub fn is_destroyed(&self) -> bool {
        self.hit_points().current == 0
    }

    pub fn take_structural_hit(&mut self) {
        self.damage = (self.damage + 1).min(self.hit_points().maximum);
        if self.is_destroyed() {
            self.stock.current = 0;
        }
    }

    pub fn sabotage(&mut self) {
        self.damage = self.hit_points().maximum;
        self.stock.current = 0;
    }
}

/// Supplies actually charged during resource settlement, before casualty cleanup.
#[derive(Clone, Debug)]
pub struct SupplyConsumption {
    pub player_number: PlayerNumber,
    pub amount: i32,
}

pub struct ResourceSettlement {
    pub units: Vec<Unit>,
    pub upkeep: Vec<SupplyConsumption>,
}

/// Current board state, including hit points, fuel and supplies. Combat remains future work.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Scenario {
    pub(crate) map: Map,
    pub(crate) depots: Vec<Depot>,
    pub(crate) supply_crates: Vec<GroundSupplyCrate>,
    pub(crate) units: Vec<Unit>,
}

impl Unit {
    pub(crate) fn firing_position_revealed(&self) -> bool {
        self.firing_position_revealed
    }

    /// Direct fire reveals a unit's position for the following turn.
    pub(crate) fn finish_firing_reveal(&mut self, fired: bool) {
        self.firing_position_revealed = fired;
    }

    #[cfg(test)]
    pub(crate) fn set_fuel_for_test(&mut self, current: i32) {
        if let Some(fuel) = &mut self.fuel {
            fuel.current = current;
        }
    }

    #[cfg(test)]
    pub(crate) fn set_supplies_for_test(&mut self, current: i32) {
        self.supplies.current = current;
    }

    /// Conservative simulation assumption for an observed enemy whose gauges are
    /// private. Preserve public position, kind, facing and entrenchment only.
    pub(crate) fn assume_full_resources(&mut self) {
        self.hit_points = HitPoints::full();
        self.supplies = Supplies::for_kind(self.kind);
        self.fuel = Fuel::for_kind(self.kind);
        self.supply_cargo.clear();
    }

    /// Conceal private gauges on response copies, preserving authoritative resources.
    pub(crate) fn conceal_resources(&mut self) {
        self.resources_visible = false;
        self.combat_state = None;
    }

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

    pub fn dig_in(&mut self) {
        if self.kind == UnitKind::Infantry && self.is_alive() && self.board_position().is_some() {
            self.entrenchment = Entrenchment::Entrenched;
        }
    }

    pub fn board(&mut self, carrier: UnitId) {
        self.entrenchment = Entrenchment::Exposed;
        self.location = Location::Aboard(carrier);
    }

    pub fn unit_id(&self) -> UnitId {
        self.id
    }

    pub fn restore_sprite_facing(&mut self, facing: SpriteFacing) {
        self.sprite_facing = facing;
    }

    pub fn is_alive(&self) -> bool {
        self.hit_points.current() > 0
    }

    pub fn take_damage(&mut self, damage: i32) {
        self.hit_points.current = (self.hit_points.current - damage).max(0);
    }

    pub(crate) fn receive_fuel(&mut self, amount: i32) {
        if let Some(fuel) = &mut self.fuel {
            fuel.current = (fuel.current + amount).min(fuel.maximum);
        }
    }

    pub(crate) fn receive_supplies(&mut self, amount: i32) {
        self.supplies.current = (self.supplies.current + amount).min(self.supplies.maximum);
    }

    pub fn spend_supplies(&mut self, cost: i32) {
        self.supplies.current = (self.supplies.current - cost).max(0);
    }

    pub fn apply_combat_outcome(&mut self, outcome: &Unit) {
        self.entrenchment = outcome.entrenchment;
        self.hit_points = outcome.hit_points;
        self.supplies = outcome.supplies;
        self.direction = outcome.direction;
        self.sprite_facing = outcome.sprite_facing;
    }

    pub fn rotate(&mut self, direction: Direction) {
        if self.direction.is_some() {
            self.direction = Some(direction);
            self.sprite_facing = self.sprite_facing.turned(direction);
        }
    }

    /// Passengers are stored separately from their carrier; freight lives on the unit.
    pub fn fuel_movement_per_tile(&self, passenger_count: usize) -> i32 {
        self.fuel.map_or(0, |fuel| {
            fuel.movement_per_tile
                + (passenger_count + self.supply_cargo.len()) as i32 * fuel.movement_per_cargo_slot
        })
    }

    pub fn fuel_movement_cost(
        &self,
        map: &Map,
        path: &[Coordinate],
        passenger_count: usize,
    ) -> i32 {
        let ordinary_cost = self.fuel_movement_per_tile(passenger_count);
        let road_cost =
            movement::road_fuel_cost(self.kind, passenger_count + self.supply_cargo.len());
        path.iter()
            .skip(1)
            .map(|position| match map.tile_at(*position) {
                Some(terrain) if terrain.is_road() => road_cost,
                _ => ordinary_cost,
            })
            .sum()
    }

    pub fn follow_terrain_path(&mut self, map: &Map, path: &[Coordinate], passenger_count: usize) {
        let cost = MovementCost {
            fuel: self.fuel_movement_cost(map, path, passenger_count),
            supplies: self.supplies.movement_cost(map, path),
        };
        self.follow_path_with_costs(path, cost);
    }

    #[cfg(test)]
    pub fn follow_path(&mut self, path: &[Coordinate], passenger_count: usize) {
        let tiles = path.len().saturating_sub(1) as i32;
        self.follow_path_with_costs(
            path,
            MovementCost {
                fuel: tiles * self.fuel_movement_per_tile(passenger_count),
                supplies: tiles * self.supplies.movement_per_tile,
            },
        );
    }

    fn follow_path_with_costs(&mut self, path: &[Coordinate], cost: MovementCost) {
        for step in path.windows(2) {
            if let Some(direction) = Direction::between(step[0], step[1]) {
                if self.direction.is_some() {
                    self.direction = Some(direction);
                }
                self.sprite_facing = self.sprite_facing.turned(direction);
            }
        }
        if let Some(fuel) = &mut self.fuel {
            fuel.current -= cost.fuel;
        }
        self.supplies.current -= cost.supplies;
        if path.len() > 1
            && let Some(position) = path.last()
        {
            self.move_to(*position);
        }
    }

    /// End interrupted allied passage on its preceding free square. Keep combat
    /// losses, refund only discarded travel, and recover the retained route's facing.
    pub fn retract_movement(
        &mut self,
        retained_path: &[Coordinate],
        map: &Map,
        discarded_path: &[Coordinate],
        initial: &Unit,
        passenger_count: usize,
    ) {
        self.supplies.current += self.supplies.movement_cost(map, discarded_path);
        let refund = initial.fuel_movement_cost(map, discarded_path, passenger_count);
        if let Some(fuel) = &mut self.fuel {
            fuel.current += refund;
        }
        self.direction = initial.direction;
        self.sprite_facing = initial.sprite_facing;
        for step in retained_path.windows(2) {
            if let Some(direction) = Direction::between(step[0], step[1]) {
                self.rotate(direction);
            }
        }
        if let Some(position) = retained_path.last() {
            self.move_to(*position);
        }
    }

    pub fn move_to(&mut self, position: Coordinate) {
        if self.board_position() != Some(position) {
            self.entrenchment = Entrenchment::Exposed;
        }
        self.location = Location::OnMap(position);
    }
}

impl Scenario {
    pub fn passenger_count(&self, carrier: UnitId) -> usize {
        self.units
            .iter()
            .filter(|unit| unit.carrier_id() == Some(carrier))
            .count()
    }

    pub(crate) fn from_definition(definition: &MapDefinition) -> Result<Self, MapError> {
        let map = definition.terrain_map()?;
        let units = definition
            .units
            .iter()
            .map(|starting| Unit {
                combat_state: None,
                entrenchment: Entrenchment::Exposed,
                id: UnitId(starting.id),
                player_number: starting.player_number,
                sprite_facing: starting.direction.map_or(
                    SpriteFacing::starting(starting.player_number),
                    |direction| SpriteFacing::starting(starting.player_number).turned(direction),
                ),
                kind: starting.kind,
                resources_visible: true,
                firing_position_revealed: false,
                supply_cargo: Vec::new(),
                hit_points: HitPoints::full(),
                fuel: Fuel::for_kind(starting.kind),
                supplies: Supplies::for_kind(starting.kind),
                location: Location::OnMap(starting.position),
                direction: starting.direction,
            })
            .collect();
        let depots = definition
            .depots
            .iter()
            .map(|starting| Depot::new(starting.kind, starting.position))
            .collect();
        Ok(Self {
            map,
            units,
            depots,
            supply_crates: Vec::new(),
        })
    }

    /// A truck has two berths shared by passengers and supply crates.
    pub fn loading_pair(&self, mover: &Unit, target: &Unit) -> Option<(UnitId, UnitId)> {
        if mover.player_number != target.player_number
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
            + truck.supply_cargo.len()
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

    /// Replenish, charge upkeep, and remove exhausted units and their cargo.
    /// Return the last resource snapshot for death presentation and actual upkeep spending.
    pub fn finish_turn_resources(&mut self, turn_number: i32) -> ResourceSettlement {
        supplies::replenish(self, turn_number);
        let upkeep = [PlayerNumber::Player1, PlayerNumber::Player2]
            .into_iter()
            .map(|player_number| SupplyConsumption {
                player_number,
                amount: self
                    .units
                    .iter()
                    .filter(|unit| unit.player_number() == player_number)
                    .map(|unit| unit.supplies.current.min(unit.supplies.upkeep_per_turn))
                    .sum(),
            })
            .collect();
        for unit in &mut self.units {
            unit.supplies.current = (unit.supplies.current - unit.supplies.upkeep_per_turn).max(0);
        }
        let exhausted: Vec<_> = self
            .units
            .iter()
            .filter(|unit| unit.supplies.current == 0 || !unit.is_alive())
            .map(Unit::unit_id)
            .collect();
        for unit in &mut self.units {
            if unit
                .carrier_id()
                .is_some_and(|carrier| exhausted.contains(&carrier))
            {
                unit.supplies.current = 0;
            }
            if unit.supplies.current == 0 {
                unit.hit_points.current = 0;
            }
        }
        let resource_snapshot = self.units.clone();
        self.units
            .retain(|unit| unit.supplies.current > 0 && unit.is_alive());
        ResourceSettlement {
            units: resource_snapshot,
            upkeep,
        }
    }

    #[cfg(test)]
    pub fn el_alamein() -> Result<Self, MapError> {
        MapDefinition::parse(include_str!("../maps/el-alamein.json"))?.scenario()
    }

    #[cfg(test)]
    pub fn supply_point() -> Result<Self, MapError> {
        MapDefinition::parse(include_str!("../maps/supply-point.json"))?.scenario()
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::map::MapTheme;
    use crate::{
        map::RoadShape,
        test_support::{FixtureValue, TestResult},
    };

    #[test]
    fn road_fuel_counts_cargo_and_refunds_only_discarded_terrain() -> TestResult<()> {
        let fixture = MapDefinition::parse(r#"{
            "width": 4, "height": 2, "theme": "GreenForest", "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
                {"id": 2, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 3, "position": {"x": 3, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let path = [
            Coordinate::new(0, 0),
            Coordinate::new(1, 0),
            Coordinate::new(2, 0),
        ];
        for shape in RoadShape::ALL {
            let road = Terrain::Road(shape);
            let map =
                Map::new(4, 2, Terrain::Plain, BTreeMap::from([(path[1], road)])).fixture()?;
            for kind in [UnitKind::Tank, UnitKind::Truck] {
                for passengers in 0..=2 {
                    for freight in 0..=(2 - passengers) {
                        let mut unit = fixture
                            .units
                            .iter()
                            .find(|unit| unit.kind() == kind)
                            .fixture()?
                            .clone();
                        unit.move_to(path[0]);
                        unit.supply_cargo =
                            vec![CargoStock::new(ResourceKind::Supply, 256); freight];
                        let slots = (passengers + freight) as i32;
                        let (ordinary, road_cost) = match kind {
                            UnitKind::Tank => (7, 5),
                            UnitKind::Truck => (2 + 2 * slots, 1 + slots),
                            _ => return Err("invalid road fixture kind".into()),
                        };
                        let initial = unit.clone();
                        assert_eq!(unit.fuel_movement_cost(&map, &path[..1], passengers), 0);
                        assert_eq!(
                            unit.fuel_movement_cost(&map, &path, passengers),
                            ordinary + road_cost
                        );
                        unit.follow_terrain_path(&map, &path, passengers);
                        assert_eq!(unit.fuel().fixture()?.current, 128 - ordinary - road_cost);
                        unit.take_damage(3);
                        unit.retract_movement(&path[..2], &map, &path[1..], &initial, passengers);
                        assert_eq!(unit.fuel().fixture()?.current, 128 - road_cost);
                        assert_eq!(unit.hit_points().current(), 13);
                    }
                }
            }
        }
        Ok(())
    }

    #[test]
    fn entrenchment_survives_holds_and_rotation_but_not_movement_or_boarding() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut infantry = scenario.units.first().fixture()?.clone();
        let origin = infantry.board_position().fixture()?;
        infantry.dig_in();
        infantry.rotate(Direction::West);
        infantry.follow_terrain_path(&scenario.map, &[origin], 0);
        assert_eq!(infantry.entrenchment(), Entrenchment::Entrenched);
        infantry.follow_terrain_path(&scenario.map, &[origin, Coordinate::new(3, 3)], 0);
        assert_eq!(infantry.entrenchment(), Entrenchment::Exposed);
        infantry.dig_in();
        let truck = scenario
            .units
            .iter()
            .find(|unit| unit.kind() == UnitKind::Truck)
            .fixture()?
            .unit_id();
        infantry.board(truck);
        assert_eq!(infantry.entrenchment(), Entrenchment::Exposed);
        infantry.dig_in();
        assert_eq!(infantry.entrenchment(), Entrenchment::Exposed);
        let tank = scenario
            .units
            .iter_mut()
            .find(|unit| unit.kind() == UnitKind::Tank)
            .fixture()?;
        tank.dig_in();
        assert_eq!(tank.entrenchment(), Entrenchment::Exposed);
        Ok(())
    }

    #[test]
    fn walking_terrain_supply_costs_reserve_upkeep_and_charge_entered_tiles() -> TestResult<()> {
        for (kind, sketch, expected) in [
            (UnitKind::Infantry, "...", 18),
            (UnitKind::Infantry, ".::", 18),
            (UnitKind::Infantry, ".%%", 26),
            (UnitKind::Infantry, ".##", 26),
            (UnitKind::Infantry, ".^^", 26),
            (UnitKind::Infantry, ".%#", 26),
            (UnitKind::FieldGun, "...", 48),
            (UnitKind::FieldGun, ".%%", 48),
            (UnitKind::FieldGun, ".##", 48),
        ] {
            let map = Map::from_ascii(sketch).fixture()?;
            let path = [
                Coordinate::new(0, 0),
                Coordinate::new(1, 0),
                Coordinate::new(2, 0),
            ];
            let mut scenario = Scenario::supply_point().fixture()?;
            let unit = scenario
                .units
                .iter_mut()
                .find(|unit| unit.kind() == kind)
                .fixture()?;
            unit.move_to(path[0]);
            unit.set_supplies_for_test(expected + 3);
            assert!(!unit.supplies().can_afford_movement(&map, &path));
            unit.set_supplies_for_test(expected + 4);
            assert!(unit.supplies().can_afford_movement(&map, &path));
            unit.set_supplies_for_test(128);
            let initial = unit.clone();
            unit.follow_terrain_path(&map, &path, 0);
            assert_eq!(unit.supplies().current(), 128 - expected);
            assert_eq!(unit.board_position(), Some(path[2]));
            unit.spend_supplies(12);
            unit.retract_movement(&path[..2], &map, &path[1..], &initial, 0);
            assert_eq!(unit.supplies().current(), 116 - expected / 2);
            assert_eq!(unit.board_position(), Some(path[1]));
        }
        Ok(())
    }

    #[test]
    fn map_themes_are_independent_of_base_terrain() -> TestResult<()> {
        for map_type in [
            crate::map_type::MapType::SupplyPoint,
            crate::map_type::MapType::ElAlamein,
            crate::map_type::MapType::BloodGulch,
            crate::map_type::MapType::Sidewinder,
            crate::map_type::MapType::BlackForest,
            crate::map_type::MapType::Crossroads,
            crate::map_type::MapType::Ridgeway,
            crate::map_type::MapType::ThreeCrossings,
            crate::map_type::MapType::LakeOfPennsylvania,
            crate::map_type::MapType::ConvoyCountry,
            crate::map_type::MapType::Tobruk,
            crate::map_type::MapType::BastionPass,
            crate::map_type::MapType::WinterFront,
        ] {
            let scenario = map_type.scenario().fixture()?;
            let original_visibility =
                crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            for theme in [MapTheme::GreenForest, MapTheme::Desert, MapTheme::Snow] {
                let mut themed = scenario.clone();
                themed.map = themed.map.with_theme(theme);
                assert_eq!(
                    crate::visibility::visible_tiles(&themed, PlayerNumber::Player1),
                    original_visibility
                );
            }
        }

        Ok(())
    }

    #[test]
    fn passengers_derive_physical_position_without_board_occupancy() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let truck_id = UnitId::parse("4").fixture()?;
        let passenger_id = UnitId::parse("1").fixture()?;
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == passenger_id)
            .fixture()?
            .board(truck_id);
        let destination = Coordinate::new(1, 7);
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == truck_id)
            .fixture()?
            .move_to(destination);
        let passenger = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == passenger_id)
            .fixture()?;
        assert_eq!(passenger.location, Location::Aboard(truck_id));
        assert_eq!(passenger.board_position(), None);
        assert_eq!(scenario.physical_position(passenger), Some(destination));

        let mut missing_carrier = passenger.clone();
        missing_carrier.board(UnitId::parse("999").fixture()?);
        assert_eq!(scenario.physical_position(&missing_carrier), None);
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == truck_id)
            .fixture()?
            .board(passenger_id);
        assert_eq!(scenario.physical_position(&missing_carrier), None);
        assert_eq!(
            scenario.physical_position(
                scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == passenger_id)
                    .fixture()?
            ),
            None
        );

        Ok(())
    }

    #[test]
    fn exhausted_units_die_and_dead_carriers_leave_no_orphaned_cargo() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let truck_id = UnitId::parse("4").fixture()?;
        for unit in &mut scenario.units {
            match unit.id().as_str() {
                "1" => unit.board(truck_id),
                "2" | "4" | "12" => unit.supplies.current = 1,
                _ => {}
            }
        }
        let snapshot = scenario.finish_turn_resources(1);
        for id in ["1", "2", "4", "12"] {
            assert!(!scenario.units.iter().any(|unit| unit.id() == id));
            let dead = snapshot
                .units
                .iter()
                .find(|unit| unit.id() == id)
                .fixture()?;
            assert_eq!(dead.supplies.current, 0);
            assert_eq!(dead.hit_points.current, 0);
        }
        assert_eq!(scenario.units.len(), 12);
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.supplies.current == unit.supplies.maximum - 4)
        );
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.hit_points == HitPoints::full())
        );

        Ok(())
    }

    #[test]
    fn exhausted_passengers_die_without_destroying_their_carrier() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let passenger = &mut scenario.units[0];
        passenger.board(UnitId::parse("4").fixture()?);
        passenger.supplies.current = 1;
        scenario.finish_turn_resources(1);
        assert!(!scenario.units.iter().any(|unit| unit.id() == "1"));
        assert!(scenario.units.iter().any(|unit| unit.id() == "4"));
        assert_eq!(scenario.units.len(), 15);

        Ok(())
    }

    #[test]
    fn units_start_with_full_health_and_resources() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        for unit in &scenario.units {
            assert_eq!(
                unit.hit_points(),
                HitPoints {
                    current: 16,
                    maximum: 16
                }
            );
            let (maximum, movement_per_tile) = match unit.kind {
                UnitKind::Infantry => (192, 9),
                UnitKind::FieldGun => (196, 24),
                UnitKind::Tank => (128, 0),
                UnitKind::Truck => (96, 0),
            };
            assert_eq!(unit.supplies.current, maximum);
            assert_eq!(unit.supplies.maximum, maximum);
            assert_eq!(unit.supplies.movement_per_tile, movement_per_tile);
            assert_eq!(unit.supplies.upkeep_per_turn, 4);
            match unit.kind {
                UnitKind::Tank | UnitKind::Truck => {
                    assert_eq!(
                        unit.fuel(),
                        Some(Fuel {
                            current: 128,
                            maximum: 128,
                            movement_per_tile: if unit.kind == UnitKind::Tank { 7 } else { 2 },
                            movement_per_cargo_slot: if unit.kind == UnitKind::Truck {
                                2
                            } else {
                                0
                            },
                        })
                    );
                }
                UnitKind::Infantry | UnitKind::FieldGun => assert_eq!(unit.fuel(), None),
            }
        }
        scenario.units[0].follow_path(&[Coordinate::new(3, 7), Coordinate::new(3, 6)], 0);
        scenario.finish_turn_resources(1);
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.hit_points() == HitPoints::full())
        );

        Ok(())
    }

    #[test]
    fn following_paths_turns_units_and_keeps_facing_on_hold() -> TestResult<()> {
        let mut unit = Scenario::supply_point().fixture()?.units.remove(0);
        for (from, to, expected) in [
            ((3, 7), (3, 6), Direction::North),
            ((3, 6), (4, 6), Direction::East),
            ((4, 6), (4, 7), Direction::South),
            ((4, 7), (3, 7), Direction::West),
        ] {
            unit.follow_path(
                &[Coordinate::new(from.0, from.1), Coordinate::new(to.0, to.1)],
                0,
            );
            assert_eq!(unit.direction(), Some(expected));
            assert_eq!(
                unit.board_position().fixture()?,
                Coordinate::new(to.0, to.1)
            );
        }
        unit.follow_path(&[unit.board_position().fixture()?], 0);
        assert_eq!(unit.direction(), Some(Direction::West));
        unit.follow_path(
            &[
                Coordinate::new(3, 7),
                Coordinate::new(4, 7),
                Coordinate::new(5, 7),
                Coordinate::new(5, 8),
            ],
            0,
        );
        assert_eq!(unit.direction(), Some(Direction::South));

        Ok(())
    }

    #[test]
    fn sprite_facing_retains_last_horizontal_direction_across_vertical_moves() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
                let mut unit = Scenario::supply_point()
                    .fixture()?
                    .units
                    .into_iter()
                    .find(|unit| unit.kind == kind && unit.player_number == player_number)
                    .fixture()?;
                unit.follow_path(
                    &[
                        Coordinate::new(4, 8),
                        Coordinate::new(3, 8),
                        Coordinate::new(3, 7),
                    ],
                    0,
                );
                assert_eq!(unit.direction(), Some(Direction::North));
                assert_eq!(unit.sprite_facing(), SpriteFacing::Left);
                unit.follow_path(&[Coordinate::new(3, 7), Coordinate::new(3, 8)], 0);
                assert_eq!(unit.sprite_facing(), SpriteFacing::Left);
                unit.rotate(Direction::South);
                assert_eq!(unit.sprite_facing(), SpriteFacing::Left);
                unit.rotate(Direction::East);
                unit.follow_path(&[Coordinate::new(3, 8), Coordinate::new(3, 7)], 0);
                assert_eq!(unit.direction(), Some(Direction::North));
                assert_eq!(unit.sprite_facing(), SpriteFacing::Right);
                unit.follow_path(&[Coordinate::new(3, 7)], 0);
                assert_eq!(unit.sprite_facing(), SpriteFacing::Right);
            }
        }

        Ok(())
    }

    #[test]
    fn trucks_have_no_direction_after_moves_or_holds() -> TestResult<()> {
        let mut unit = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.kind == UnitKind::Truck)
            .fixture()?;
        assert_eq!(unit.direction(), None);
        unit.follow_path(
            &[
                unit.board_position().fixture()?,
                Coordinate::new(3, 7),
                Coordinate::new(3, 8),
            ],
            0,
        );
        assert_eq!(unit.board_position().fixture()?, Coordinate::new(3, 8));
        assert_eq!(unit.direction(), None);
        unit.follow_path(&[unit.board_position().fixture()?], 0);
        assert_eq!(unit.direction(), None);

        Ok(())
    }

    #[test]
    fn trucks_face_horizontal_travel_without_combat_direction() -> TestResult<()> {
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let mut unit = Scenario::supply_point()
                .fixture()?
                .units
                .into_iter()
                .find(|unit| unit.kind == UnitKind::Truck && unit.player_number == player_number)
                .fixture()?;
            for (from, to, facing) in [
                ((4, 8), (3, 8), SpriteFacing::Left),
                ((3, 8), (3, 7), SpriteFacing::Left),
                ((3, 7), (3, 8), SpriteFacing::Left),
                ((3, 8), (4, 8), SpriteFacing::Right),
                ((4, 8), (4, 7), SpriteFacing::Right),
            ] {
                unit.follow_path(
                    &[Coordinate::new(from.0, from.1), Coordinate::new(to.0, to.1)],
                    0,
                );
                assert_eq!(unit.direction(), None);
                assert_eq!(unit.sprite_facing(), facing);
            }
            unit.follow_path(&[Coordinate::new(4, 7)], 0);
            unit.rotate(Direction::West);
            assert_eq!(unit.direction(), None);
            assert_eq!(unit.sprite_facing(), SpriteFacing::Right);
        }

        Ok(())
    }
}

#[graphql_object]
impl Scenario {
    fn map(&self) -> &Map {
        &self.map
    }
    fn depots(&self) -> &[Depot] {
        &self.depots
    }
    fn units(&self) -> &[Unit] {
        &self.units
    }
    fn supply_crates(&self) -> &[GroundSupplyCrate] {
        &self.supply_crates
    }
    fn supply_rules(&self) -> SupplyRules {
        supplies::rules()
    }
}

#[graphql_object]
impl Depot {
    fn hp(&self) -> DepotHp {
        self.hit_points()
    }
    fn kind(&self) -> BuildingKind {
        self.kind
    }
    fn position(&self) -> Coordinate {
        self.position
    }
    fn stock(&self) -> Option<&ResourceStock> {
        (self.kind.resource_kind().is_some() && self.stock_visible).then_some(&self.stock)
    }
}
