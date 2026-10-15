use crate::{
    combat::{self, IndirectImpact, Shot},
    map::Coordinate,
    movement,
    scenario::{
        Depot, Direction, PlayerNumber, ResourceSettlement, Scenario, SpriteFacing, Unit, UnitId,
        UnitKind,
    },
    supplies::{self, CrateUnload, GroundSupplyCrate, SupplyOrder},
};
use juniper::{GraphQLEnum, GraphQLInputObject, GraphQLObject, graphql_object};
use std::collections::{BTreeMap, BTreeSet};

#[derive(GraphQLInputObject)]
pub struct CoordinateInput {
    x: i32,
    y: i32,
}

#[derive(GraphQLInputObject)]
pub struct MoveOrderInput {
    unit_id: String,
    /// Includes the starting square. A single square is an explicit hold order.
    path: Vec<CoordinateInput>,
    /// Facing for an in-place rotation order.
    direction: Option<Direction>,
    /// Stationary combat readiness, with direction selecting the firing line.
    ambush: Option<bool>,
    /// Stationary defensive readiness without firing.
    stand_ground: Option<bool>,
    /// Stationary field-gun shell aimed at a tile, independently of sight.
    indirect_fire: Option<CoordinateInput>,
    /// Move until contact, then fire at the encountered enemy.
    attack_move: Option<bool>,
    /// Passenger destinations after this truck moves.
    unloads: Option<Vec<UnloadOrderInput>>,
    load_crates: Option<i32>,
    crate_unloads: Option<Vec<CrateUnloadInput>>,
}

#[derive(Clone, Debug)]
pub struct MoveOrder {
    pub travel: TravelMode,
    pub facing: FacingOrder,
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
    pub unloads: Vec<UnloadOrder>,
    pub supply: SupplyOrder,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TravelMode {
    Normal,
    AttackMove,
}

/// Validated stationary action. Ambush owns a direction; indirect fire owns a tile.
#[derive(Clone, Copy, Debug)]
pub enum FacingOrder {
    Unchanged,
    Ambush(Direction),
    StandGround,
    IndirectFire(Coordinate),
}

impl FacingOrder {
    pub fn indirect_target(self) -> Option<Coordinate> {
        match self {
            Self::IndirectFire(target) => Some(target),
            Self::Unchanged | Self::Ambush(_) | Self::StandGround => None,
        }
    }

    pub fn direction(self) -> Option<Direction> {
        match self {
            Self::Unchanged | Self::StandGround | Self::IndirectFire(_) => None,
            Self::Ambush(direction) => Some(direction),
        }
    }

    pub fn is_standing_ground(self) -> bool {
        match self {
            Self::StandGround => true,
            Self::Unchanged | Self::Ambush(_) | Self::IndirectFire(_) => false,
        }
    }

    pub fn is_ambush(self) -> bool {
        match self {
            Self::Ambush(_) => true,
            Self::Unchanged | Self::StandGround | Self::IndirectFire(_) => false,
        }
    }
}

#[derive(GraphQLInputObject)]
pub struct UnloadOrderInput {
    unit_id: String,
    destination: CoordinateInput,
}

#[derive(GraphQLInputObject)]
pub struct CrateUnloadInput {
    cargo_index: i32,
    destination: CoordinateInput,
}

#[derive(Clone, Debug)]
pub struct UnloadOrder {
    pub unit_id: UnitId,
    pub destination: Coordinate,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum TurnEventKind {
    Move,
    Ambush,
    StandGround,
    Load,
    Unload,
    Hold,
    MovementStopped,
}

/// Ordered presentation events. Future attacks and interruptions belong here;
/// clients replay these outcomes rather than reimplementing resolution rules.
#[derive(Clone, Debug)]
pub struct TurnEvent {
    pub rotation_direction: Option<Direction>,
    pub initial_direction: Option<Direction>,
    pub initial_sprite_facing: SpriteFacing,
    pub initial_carrier: Option<UnitId>,
    pub carrier_id: Option<UnitId>,
    pub kind: TurnEventKind,
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
}

#[graphql_object]
impl TurnEvent {
    fn rotation_direction(&self) -> Option<Direction> {
        self.rotation_direction
    }
    fn initial_carrier(&self) -> Option<String> {
        self.initial_carrier.map(|id| id.to_string())
    }
    fn carrier_id(&self) -> Option<String> {
        self.carrier_id.map(|id| id.to_string())
    }
    fn initial_sprite_facing(&self) -> SpriteFacing {
        self.initial_sprite_facing
    }
    fn initial_direction(&self) -> Option<Direction> {
        self.initial_direction
    }
    fn kind(&self) -> TurnEventKind {
        self.kind
    }
    fn unit_id(&self) -> String {
        self.unit_id.to_string()
    }
    fn path(&self) -> Vec<Coordinate> {
        self.path.clone()
    }
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct TurnFrame {
    pub indirect_impacts: Vec<IndirectImpact>,
    pub shots: Vec<Shot>,
    pub depots: Vec<Depot>,
    pub supply_crates: Vec<GroundSupplyCrate>,
    /// Time from the preceding frame in milliseconds.
    pub duration_ms: i32,
    pub units: Vec<Unit>,
    pub visible_tiles: Vec<Coordinate>,
}

/// The visibility projection exposes only the viewer's report.
#[derive(Clone, Debug, GraphQLObject)]
pub struct TurnReport {
    pub player_number: PlayerNumber,
    pub units_lost: i32,
    pub enemy_units_destroyed: i32,
    /// Actual HP removed by the viewer's projected shots, capped at remaining health.
    pub damage_inflicted: i32,
    pub supplies_consumed: i32,
}

impl TurnReport {
    /// Capture movement/readiness/firing costs before sources refill units.
    /// Corpses retain supplies here; discarded stock is not consumption.
    fn before_replenishment(
        player_number: PlayerNumber,
        initial_units: &[Unit],
        units: &[Unit],
    ) -> Self {
        let supplies_consumed = initial_units
            .iter()
            .filter(|unit| unit.player_number() == player_number)
            .filter_map(|initial| {
                units
                    .iter()
                    .find(|unit| unit.unit_id() == initial.unit_id())
                    .map(|unit| initial.supplies().current() - unit.supplies().current())
            })
            .sum();
        Self {
            player_number,
            units_lost: 0,
            enemy_units_destroyed: 0,
            damage_inflicted: 0,
            supplies_consumed,
        }
    }

    fn finish(
        &mut self,
        initial_units: &[Unit],
        scenario: &Scenario,
        settlement: &ResourceSettlement,
    ) {
        self.units_lost = initial_units
            .iter()
            .filter(|unit| {
                unit.player_number() == self.player_number
                    && !scenario
                        .units
                        .iter()
                        .any(|survivor| survivor.unit_id() == unit.unit_id())
            })
            .count() as i32;
        self.supplies_consumed += settlement
            .upkeep
            .iter()
            .filter(|consumption| consumption.player_number == self.player_number)
            .map(|consumption| consumption.amount)
            .sum::<i32>();
    }
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct TurnResolution {
    pub reports: Vec<TurnReport>,
    pub turn_number: i32,
    pub events: Vec<TurnEvent>,
    /// Viewer-specific frames are populated when visibility projects the resolution.
    pub frames: Vec<TurnFrame>,
}

#[derive(Clone)]
pub struct Turns {
    pub number: i32,
    pub orders: [Option<Vec<MoveOrder>>; 2],
    pub last_resolution: Option<TurnResolution>,
}

impl Default for Turns {
    fn default() -> Self {
        Self {
            number: 1,
            orders: [None, None],
            last_resolution: None,
        }
    }
}

pub fn player_index(player_number: PlayerNumber) -> usize {
    match player_number {
        PlayerNumber::Player1 => 0,
        PlayerNumber::Player2 => 1,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct PlannedLoad {
    pub truck: UnitId,
    pub passenger: UnitId,
}

/// Boarding intent is determined by final destinations, independently of submission order.
/// Capacity is checked for the whole group during validation, before any unloading.
pub(crate) fn planned_loads(scenario: &Scenario, orders: &[MoveOrder]) -> Vec<PlannedLoad> {
    let permits_boarding = |order: &MoveOrder| {
        order.travel == TravelMode::Normal
            && match order.facing {
                FacingOrder::Unchanged => true,
                FacingOrder::Ambush(_)
                | FacingOrder::StandGround
                | FacingOrder::IndirectFire(_) => false,
            }
    };
    let mut loads = Vec::new();
    for truck_order in orders {
        if !permits_boarding(truck_order) {
            continue;
        }
        let Some(truck) = scenario.units.iter().find(|unit| {
            unit.unit_id() == truck_order.unit_id
                && unit.kind() == UnitKind::Truck
                && unit.carrier_id().is_none()
        }) else {
            continue;
        };
        for passenger_order in orders {
            if !permits_boarding(passenger_order)
                || truck_order.path.last() != passenger_order.path.last()
                || (truck_order.path.len() == 1 && passenger_order.path.len() == 1)
            {
                continue;
            }
            if let Some(passenger) = scenario
                .units
                .iter()
                .find(|unit| unit.unit_id() == passenger_order.unit_id)
                && let Some((truck, passenger)) = scenario.loading_pair(truck, passenger)
            {
                loads.push(PlannedLoad { truck, passenger });
            }
        }
    }
    loads
}

pub fn validate(
    scenario: &Scenario,
    player_number: PlayerNumber,
    inputs: Vec<MoveOrderInput>,
) -> Result<Vec<MoveOrder>, &'static str> {
    let visible = crate::visibility::visible_tiles(scenario, player_number);
    // Occupancy may reject a draft only when it is known to its owner. Resolution
    // still checks the complete board, including concealed enemies at unload exits.
    let planning_scenario = crate::visibility::observed_scenario(scenario, player_number, &visible);
    let own_count = scenario
        .units
        .iter()
        .filter(|unit| unit.player_number() == player_number)
        .count();
    if inputs.len() != own_count {
        return Err("set a move or hold order for every unit before submitting.");
    }
    // Inspect intended departures independently of submission order. Every path
    // still goes through full validation before any orders are locked.
    let departing: BTreeSet<_> = inputs
        .iter()
        .filter(|input| input.path.len() > 1)
        .filter_map(|input| UnitId::parse(&input.unit_id))
        .collect();
    let mut destination_scenario = planning_scenario.clone();
    destination_scenario.units.retain(|unit| {
        unit.player_number() != player_number || !departing.contains(&unit.unit_id())
    });
    let mut unit_ids = BTreeSet::new();
    let mut destinations = BTreeSet::new();
    let mut crate_destinations = BTreeSet::new();
    let mut orders = Vec::new();
    for input in inputs {
        let unit_id = UnitId::parse(&input.unit_id).ok_or("invalid unit id.")?;
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == unit_id && unit.player_number() == player_number)
            .ok_or("you can only submit orders for your own units.")?;
        if !unit_ids.insert(unit_id) {
            return Err("each unit must have exactly one order.");
        }
        let rule = movement::rules()
            .into_iter()
            .find(|rule| rule.kind == unit.kind())
            .ok_or("the unit has no movement rule.")?;
        if input.path.is_empty() || input.path.len() > (rule.budget + 1) as usize {
            return Err("invalid movement path length.");
        }
        let path: Vec<_> = input
            .path
            .into_iter()
            .map(|position| {
                let x = u16::try_from(position.x).map_err(|_| "movement is outside the map.")?;
                let y = u16::try_from(position.y).map_err(|_| "movement is outside the map.")?;
                let coordinate = Coordinate::new(x, y);
                scenario
                    .map
                    .tile_at(coordinate)
                    .ok_or("movement is outside the map.")?;
                Ok(coordinate)
            })
            .collect::<Result<_, &str>>()?;
        if Some(path[0]) != scenario.physical_position(unit) {
            return Err("movement must start at the unit's current position.");
        }
        let indirect_fire = if let Some(target) = input.indirect_fire {
            if unit.kind() != UnitKind::FieldGun || unit.carrier_id().is_some() {
                return Err("only on-map field guns can fire indirectly.");
            }
            if path.len() != 1
                || input.direction.is_some()
                || input.ambush == Some(true)
                || input.stand_ground == Some(true)
                || input.attack_move == Some(true)
                || !input.unloads.as_ref().is_none_or(Vec::is_empty)
                || input.load_crates.is_some_and(|count| count != 0)
                || !input.crate_unloads.as_ref().is_none_or(Vec::is_empty)
            {
                return Err("indirect fire must be an in-place order without other actions.");
            }
            let x = u16::try_from(target.x).map_err(|_| "target is outside the map.")?;
            let y = u16::try_from(target.y).map_err(|_| "target is outside the map.")?;
            let target = Coordinate::new(x, y);
            if scenario.map.tile_at(target).is_none() {
                return Err("target is outside the map.");
            }
            if !combat::within_indirect_range(
                path[0],
                target,
                combat::rules(unit.kind()).indirect_range,
            ) {
                return Err("target is outside indirect fire range.");
            }
            let rule = combat::rules(unit.kind());
            if unit.supplies().current()
                < unit.supplies().upkeep_per_turn() + rule.readiness_cost + rule.shot_cost
            {
                return Err("not enough supplies for indirect fire.");
            }
            Some(target)
        } else {
            None
        };
        let stand_ground = input.stand_ground == Some(true);
        if stand_ground {
            if unit.direction().is_none() || unit.carrier_id().is_some() {
                return Err("only on-map combat units can stand ground.");
            }
            if path.len() != 1
                || input.direction.is_some()
                || input.ambush == Some(true)
                || input.attack_move == Some(true)
                || !input.unloads.as_ref().is_none_or(Vec::is_empty)
            {
                return Err("stand ground must be an in-place order without other actions.");
            }
            let required =
                unit.supplies().upkeep_per_turn() + combat::rules(unit.kind()).readiness_cost;
            if unit.supplies().current() < required {
                return Err("not enough supplies to stand ground.");
            }
        }
        let attack_move = input.attack_move == Some(true);
        if attack_move {
            let combat_mover = match unit.kind() {
                UnitKind::Infantry | UnitKind::Tank => true,
                UnitKind::FieldGun | UnitKind::Truck => false,
            };
            if !combat_mover || unit.carrier_id().is_some() {
                return Err("only on-map infantry and tanks can attack move.");
            }
            if path.len() < 2
                || input.direction.is_some()
                || input.ambush == Some(true)
                || !input.unloads.as_ref().is_none_or(Vec::is_empty)
            {
                return Err("attack move requires a route without rotation, ambush, or unloading.");
            }
            let required = unit.supplies().upkeep_per_turn()
                + unit.supplies().movement_cost(&scenario.map, &path)
                + combat::rules(unit.kind()).readiness_cost
                + combat::rules(unit.kind()).shot_cost;
            if unit.supplies().current() < required {
                return Err("not enough supplies to attack after moving.");
            }
        }
        let ambush = input.ambush == Some(true);
        if ambush {
            if input.direction.is_none() {
                return Err("ambush requires a facing direction.");
            }
            let required =
                unit.supplies().upkeep_per_turn() + combat::rules(unit.kind()).readiness_cost;
            if unit.supplies().current() < required {
                return Err("not enough supplies to maintain ambush readiness.");
            }
        }
        if input.direction.is_some() {
            if !ambush {
                return Err("a facing direction requires an ambush order.");
            }
            if unit.direction().is_none() || unit.carrier_id().is_some() {
                return Err("only units on the map with a facing can ambush.");
            }
            if path.len() != 1 || !input.unloads.as_ref().is_none_or(Vec::is_empty) {
                return Err("ambush requires an in-place order without unloading.");
            }
        }
        let mut visited = BTreeSet::from([path[0]]);
        let mut cost = 0;
        for step in path.windows(2) {
            let adjacent =
                (step[0].x() - step[1].x()).abs() + (step[0].y() - step[1].y()).abs() == 1;
            if !adjacent || !visited.insert(step[1]) {
                return Err("movement must follow a path of distinct adjacent squares.");
            }
            let terrain = scenario
                .map
                .tile_at(step[1])
                .ok_or("movement is outside the map.")?;
            cost += rule
                .terrain_costs
                .iter()
                .find(|entry| entry.terrain == terrain && entry.cost > 0)
                .ok_or("this terrain cannot be crossed.")?
                .cost;
        }
        if cost > rule.budget {
            return Err("movement exceeds the unit's budget.");
        }
        if let Some(fuel) = unit.fuel()
            && (path.len() - 1) * fuel.movement_per_tile as usize > fuel.current as usize
        {
            return Err("movement exceeds the unit's available fuel.");
        }
        if !unit.supplies().can_afford_movement(&scenario.map, &path) {
            return Err("movement exceeds supplies available after upkeep.");
        }
        let destination = *path
            .last()
            .ok_or("movement requires a starting position.")?;
        if unit.carrier_id().is_some() {
            if path.len() > 2 {
                return Err("unloading must end on an adjacent square.");
            }
            if path.len() > 1
                && planning_scenario.units.iter().any(|other| {
                    other.carrier_id().is_none()
                        && other.board_position() == Some(destination)
                        && (other.player_number() != player_number
                            || !departing.contains(&other.unit_id()))
                })
            {
                return Err("unloading requires an empty square.");
            }
        } else if !attack_move
            && planning_scenario.units.iter().any(|other| {
                other.player_number() != player_number
                    && other.carrier_id().is_none()
                    && other.board_position() == Some(destination)
            })
        {
            return Err("occupied squares cannot be destinations.");
        }
        if path.len() > 1 {
            destinations.insert(destination);
        }
        let mut unloads: Vec<UnloadOrder> = Vec::new();
        for unload in input.unloads.unwrap_or_default() {
            let passenger_id = UnitId::parse(&unload.unit_id).ok_or("invalid passenger id.")?;
            if unloads.iter().any(|other| other.unit_id == passenger_id) {
                return Err("each passenger may only be unloaded once.");
            }
            let passenger = scenario
                .units
                .iter()
                .find(|passenger| {
                    passenger.unit_id() == passenger_id
                        && passenger.player_number() == player_number
                        && passenger.carrier_id() == Some(unit_id)
                })
                .ok_or("only passengers aboard this truck can be unloaded.")?;
            let x =
                u16::try_from(unload.destination.x).map_err(|_| "unloading is outside the map.")?;
            let y =
                u16::try_from(unload.destination.y).map_err(|_| "unloading is outside the map.")?;
            let exit = Coordinate::new(x, y);
            if (exit.x() - destination.x()).abs() + (exit.y() - destination.y()).abs() != 1 {
                return Err("unloading must end beside the truck's destination.");
            }
            if !legal_unload(&destination_scenario, passenger, exit, Some(unit_id)) {
                return Err("unloading requires an empty affordable adjacent square.");
            }
            if !destinations.insert(exit) {
                return Err("units must have different destinations.");
            }
            unloads.push(UnloadOrder {
                unit_id: passenger_id,
                destination: exit,
            });
        }
        let load_crates = usize::try_from(input.load_crates.unwrap_or_default())
            .map_err(|_| "crate count cannot be negative.")?;
        let crate_inputs = input.crate_unloads.unwrap_or_default();
        let supply_action = load_crates > 0 || !crate_inputs.is_empty();
        if supply_action
            && (unit.kind() != UnitKind::Truck
                || unit.carrier_id().is_some()
                || input.direction.is_some()
                || attack_move
                || ambush
                || stand_ground)
        {
            return Err("only on-map trucks can handle freight.");
        }
        if load_crates > 0 && !crate_inputs.is_empty() {
            return Err("choose loading or unloading crates for this turn.");
        }
        if load_crates > 0 {
            if load_crates + supplies::occupied_berths(scenario, unit)
                > unit.cargo_capacity() as usize
            {
                return Err("the truck has no room for these crates.");
            }
            let nearby: Vec<_> = planning_scenario
                .depots
                .iter()
                .filter(|depot| destination == depot.position)
                .collect();
            let unknown_stock = nearby.iter().any(|depot| !depot.stock_visible);
            let known_stock: i32 = nearby.iter().map(|depot| depot.stock.current).sum();
            let minimum_stock =
                (load_crates.saturating_sub(1) as i32) * supplies::rules().crate_capacity;
            if nearby.is_empty() || (!unknown_stock && known_stock <= minimum_stock) {
                return Err("loading cargo requires a stocked depot at the destination.");
            }
        }
        let mut crate_unloads: Vec<CrateUnload> = Vec::new();
        for unload in crate_inputs {
            let cargo_index =
                usize::try_from(unload.cargo_index).map_err(|_| "invalid crate slot.")?;
            if cargo_index >= unit.supply_cargo.len()
                || crate_unloads
                    .iter()
                    .any(|other| other.cargo_index == cargo_index)
            {
                return Err("choose each carried crate at most once.");
            }
            let x = u16::try_from(unload.destination.x)
                .map_err(|_| "crate unloading is outside the map.")?;
            let y = u16::try_from(unload.destination.y)
                .map_err(|_| "crate unloading is outside the map.")?;
            let exit = Coordinate::new(x, y);
            if !supplies::legal_crate_exit(&destination_scenario, player_number, destination, exit)
                || !crate_destinations.insert(exit)
            {
                return Err(
                    "crates require distinct squares beside the truck destination without enemies or crates.",
                );
            }
            crate_unloads.push(CrateUnload {
                cargo_index,
                destination: exit,
            });
        }
        orders.push(MoveOrder {
            supply: if load_crates > 0 {
                SupplyOrder::LoadCrates(load_crates)
            } else if !crate_unloads.is_empty() {
                SupplyOrder::UnloadCrates(crate_unloads)
            } else {
                SupplyOrder::None
            },
            travel: if attack_move {
                TravelMode::AttackMove
            } else {
                TravelMode::Normal
            },
            facing: if let Some(target) = indirect_fire {
                FacingOrder::IndirectFire(target)
            } else if stand_ground {
                FacingOrder::StandGround
            } else {
                match (ambush, input.direction) {
                    (true, Some(direction)) => FacingOrder::Ambush(direction),
                    (false, Some(_)) => return Err("a facing direction requires an ambush order."),
                    (false, None) => FacingOrder::Unchanged,
                    (true, None) => return Err("ambush requires a facing direction."),
                }
            },
            unit_id,
            path,
            unloads,
        });
    }
    for order in &orders {
        for unload in &order.unloads {
            if !orders
                .iter()
                .any(|other| other.unit_id == unload.unit_id && other.path.len() == 1)
            {
                return Err("passengers unloading with a truck must have hold orders.");
            }
        }
    }
    let loads = planned_loads(scenario, &orders);
    let mut arrivals: BTreeMap<Coordinate, Vec<UnitId>> = BTreeMap::new();
    for order in &orders {
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == order.unit_id)
            .ok_or("the order references a missing unit.")?;
        if let Some(carrier) = unit.carrier_id() {
            if order.path.len() > 1 {
                if orders
                    .iter()
                    .any(|other| other.unit_id == carrier && other.path.len() > 1)
                {
                    return Err("the truck must hold while unloading.");
                }
            } else {
                continue;
            }
        }
        let destination = *order
            .path
            .last()
            .ok_or("movement requires a starting position.")?;
        arrivals.entry(destination).or_default().push(order.unit_id);
    }
    for unload in orders.iter().flat_map(|order| &order.unloads) {
        if arrivals.contains_key(&unload.destination) {
            return Err("units must have different destinations.");
        }
    }
    for ids in arrivals.values().filter(|ids| ids.len() > 1) {
        let conflict_error = if orders
            .iter()
            .any(|order| ids.contains(&order.unit_id) && order.path.len() == 1)
        {
            "occupied squares cannot be destinations."
        } else {
            "units must have different destinations."
        };
        let truck = ids
            .iter()
            .find(|id| loads.iter().any(|load| load.truck == **id))
            .ok_or(conflict_error)?;
        if !ids.iter().all(|id| {
            id == truck
                || loads.contains(&PlannedLoad {
                    truck: *truck,
                    passenger: *id,
                })
        }) {
            return Err(conflict_error);
        }
    }
    for order in &orders {
        let truck = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == order.unit_id)
            .ok_or("the order references a missing unit.")?;
        let incoming = loads
            .iter()
            .filter(|load| load.truck == order.unit_id)
            .count();
        if incoming > 0
            && supplies::occupied_berths(scenario, truck) + incoming + order.supply.loading_count()
                > truck.cargo_capacity() as usize
        {
            return Err("the truck has no room for another unit.");
        }
    }
    Ok(orders)
}

/// Presentation order never determines outcomes. Complete routes alternate when
/// counts match and spread proportionally when counts differ. Initiative switches
/// each turn; both viewers replay the same schedule, regardless of submission order.
fn playback_order(
    scenario: &Scenario,
    turn_number: i32,
    events: Vec<TurnEvent>,
) -> Result<Vec<TurnEvent>, &'static str> {
    let player_indices: BTreeMap<_, _> = scenario
        .units
        .iter()
        .map(|unit| (unit.unit_id(), player_index(unit.player_number())))
        .collect();
    let events: Vec<_> = events
        .into_iter()
        .map(|event| {
            let player_index = *player_indices
                .get(&event.unit_id)
                .ok_or("playback references a missing unit.")?;
            Ok((event, player_index))
        })
        .collect::<Result<_, &str>>()?;
    let mut ordered = Vec::with_capacity(events.len());
    // Keep transport dependencies: complete movement before boarding/unloading.
    // Holds remain before loads so the first event still restores a unit's origin.
    for kinds in [
        &[TurnEventKind::Move, TurnEventKind::Ambush][..],
        &[
            TurnEventKind::Hold,
            TurnEventKind::StandGround,
            TurnEventKind::MovementStopped,
        ][..],
        &[TurnEventKind::Load][..],
        &[TurnEventKind::Unload][..],
    ] {
        let mut queues: [Vec<_>; 2] = std::array::from_fn(|player_index| {
            let mut queue: Vec<_> = events
                .iter()
                .filter(|(event, owner)| kinds.contains(&event.kind) && *owner == player_index)
                .map(|(event, _)| event.clone())
                .collect();
            queue.sort_by_key(|event| event.unit_id);
            queue
        });
        let counts = queues.each_ref().map(Vec::len);
        // Reverse for efficient removal while preserving stable within-player order.
        for queue in &mut queues {
            queue.reverse();
        }
        let mut emitted = [0usize; 2];
        let initiative = if turn_number % 2 == 1 { 0 } else { 1 };
        let mut preferred = initiative;
        while !queues.iter().all(Vec::is_empty) {
            let player_index = if queues[0].is_empty() {
                1
            } else if queues[1].is_empty() {
                0
            } else if emitted == [0, 0] {
                initiative
            } else {
                // Compare the next normalized midpoint without floating point.
                let next = [
                    (2 * emitted[0] + 1) * counts[1],
                    (2 * emitted[1] + 1) * counts[0],
                ];
                match next[0].cmp(&next[1]) {
                    std::cmp::Ordering::Less => 0,
                    std::cmp::Ordering::Greater => 1,
                    std::cmp::Ordering::Equal => preferred,
                }
            };
            if let Some(event) = queues[player_index].pop() {
                ordered.push(event);
                emitted[player_index] += 1;
                preferred = 1 - player_index;
            }
        }
    }
    Ok(ordered)
}

impl Turns {
    pub fn submit(
        &mut self,
        scenario: &mut Scenario,
        player_number: PlayerNumber,
        number: i32,
        inputs: Vec<MoveOrderInput>,
    ) -> Result<(), &'static str> {
        let mut next_turns = self.clone();
        let mut next_scenario = scenario.clone();
        next_turns.submit_pending(&mut next_scenario, player_number, number, inputs)?;
        *self = next_turns;
        *scenario = next_scenario;
        Ok(())
    }

    fn submit_pending(
        &mut self,
        scenario: &mut Scenario,
        player_number: PlayerNumber,
        number: i32,
        inputs: Vec<MoveOrderInput>,
    ) -> Result<(), &'static str> {
        if number != self.number {
            return Err("the turn has changed. refresh before submitting.");
        }
        let index = player_index(player_number);
        // A retry after a lost response cannot alter or duplicate locked orders.
        if self.orders[index].is_some() {
            return Ok(());
        }
        self.orders[index] = Some(validate(scenario, player_number, inputs)?);
        if self.orders.iter().all(Option::is_some) {
            let mut orders: Vec<_> = self
                .orders
                .iter_mut()
                .map(|orders| orders.take().ok_or("a player has no submitted orders."))
                .collect::<Result<Vec<_>, _>>()?
                .into_iter()
                .flatten()
                .collect();
            // Stable unit order, independent of which player's request arrives first.
            orders.sort_by_key(|order| order.unit_id);
            let initial_units = scenario.units.clone();
            let movement = crate::movement_resolution::resolve(scenario, &orders, self.number)
                .map_err(|error| error.message())?;
            let combat_units = movement
                .frames
                .last()
                .ok_or("missing movement frame")?
                .units
                .clone();
            let conflicts = &movement.stopped;
            let mut frames = movement.frames;
            let mut combat = movement.combat;
            let mut combat_stopped = BTreeSet::new();
            let mut events = Vec::new();
            let loads = planned_loads(scenario, &orders);
            for order in &orders {
                let unit = scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == order.unit_id)
                    .ok_or("the order references a missing unit.")?;
                let conflict = conflicts.contains(&order.unit_id);
                let kind = if conflict {
                    TurnEventKind::MovementStopped
                } else if order.facing.is_standing_ground() {
                    TurnEventKind::StandGround
                } else if order.facing.is_ambush() {
                    TurnEventKind::Ambush
                } else if order.path.len() == 1 {
                    TurnEventKind::Hold
                } else if unit.carrier_id().is_some() {
                    TurnEventKind::Unload
                } else {
                    TurnEventKind::Move
                };
                let path = movement
                    .paths
                    .get(&order.unit_id)
                    .ok_or("the unit has no resolved movement path.")?
                    .clone();
                events.push(TurnEvent {
                    rotation_direction: order.facing.direction(),
                    initial_direction: unit.direction(),
                    initial_sprite_facing: unit.sprite_facing(),
                    initial_carrier: unit.carrier_id(),
                    carrier_id: None,
                    kind,
                    unit_id: order.unit_id,
                    path,
                });
            }
            for event in &events {
                let unit = scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == event.unit_id)
                    .ok_or("the order references a missing unit.")?;
                unit.follow_terrain_path(&scenario.map, &event.path);
                let combat_unit = combat_units
                    .iter()
                    .find(|other| other.unit_id() == unit.unit_id())
                    .ok_or("the unit has no resolved combat outcome.")?;
                unit.apply_combat_outcome(combat_unit);
                if let Some(direction) = event.rotation_direction {
                    unit.rotate(direction);
                }
            }
            // Attach after movement, so stable event order cannot move cargo back
            // to its old hold position. The explicit event makes playback reversible.
            for PlannedLoad { truck, passenger } in loads {
                let carrier_alive = scenario
                    .units
                    .iter()
                    .any(|unit| unit.unit_id() == truck && unit.is_alive());
                let unit = scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == passenger)
                    .ok_or("the order references a missing unit.")?;
                let reached = orders
                    .iter()
                    .find(|order| order.unit_id == passenger)
                    .and_then(|order| order.path.last());
                let carrier_position = combat_units
                    .iter()
                    .find(|unit| unit.unit_id() == truck)
                    .and_then(Unit::board_position);
                if !unit.is_alive()
                    || !carrier_alive
                    || conflicts.contains(&truck)
                    || conflicts.contains(&passenger)
                    || unit.board_position() != carrier_position
                    || unit.board_position().as_ref() != reached
                {
                    continue;
                }
                events.push(TurnEvent {
                    rotation_direction: None,
                    initial_direction: unit.direction(),
                    initial_sprite_facing: unit.sprite_facing(),
                    initial_carrier: None,
                    carrier_id: Some(truck),
                    kind: TurnEventKind::Load,
                    unit_id: passenger,
                    path: vec![
                        unit.board_position()
                            .ok_or("loading requires a unit on the board.")?,
                    ],
                });
                unit.board(truck);
                frames.push(TurnFrame {
                    indirect_impacts: Vec::new(),
                    depots: scenario.depots.clone(),
                    supply_crates: scenario.supply_crates.clone(),
                    shots: Vec::new(),
                    units: scenario.units.clone(),
                    visible_tiles: Vec::new(),
                    duration_ms: 180,
                });
                combat.engage(scenario, &mut combat_stopped, &mut frames);
            }

            // Resolve unloading after all vehicle movement and loading. A blocked
            // truck or a passenger without a legal exit keeps its cargo aboard.
            for order in &orders {
                let truck_arrived = events.iter().any(|event| {
                    event.unit_id == order.unit_id && event.kind != TurnEventKind::MovementStopped
                });
                if !truck_arrived {
                    continue;
                }
                for unload in &order.unloads {
                    let passenger = scenario
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == unload.unit_id)
                        .ok_or("the order references a missing unit.")?;
                    let origin = scenario
                        .physical_position(passenger)
                        .ok_or("the passenger has no physical position.")?;
                    let destination = unload.destination;
                    if !passenger.is_alive()
                        || !scenario
                            .units
                            .iter()
                            .any(|unit| unit.unit_id() == order.unit_id && unit.is_alive())
                        || !legal_unload(scenario, passenger, destination, None)
                    {
                        continue;
                    }
                    let event = TurnEvent {
                        rotation_direction: None,
                        initial_direction: passenger.direction(),
                        initial_sprite_facing: passenger.sprite_facing(),
                        initial_carrier: Some(order.unit_id),
                        carrier_id: None,
                        kind: TurnEventKind::Unload,
                        unit_id: unload.unit_id,
                        path: vec![origin, destination],
                    };
                    scenario
                        .units
                        .iter_mut()
                        .find(|unit| unit.unit_id() == unload.unit_id)
                        .ok_or("the order references a missing unit.")?
                        .follow_terrain_path(&scenario.map, &event.path);
                    events.push(event);
                    frames.push(TurnFrame {
                        indirect_impacts: Vec::new(),
                        depots: scenario.depots.clone(),
                        supply_crates: scenario.supply_crates.clone(),
                        shots: Vec::new(),
                        units: scenario.units.clone(),
                        visible_tiles: Vec::new(),
                        duration_ms: 180,
                    });
                    combat.engage(scenario, &mut combat_stopped, &mut frames);
                }
            }

            combat.finish(scenario, &mut combat_stopped, &mut frames);
            for unit in &mut scenario.units {
                unit.finish_firing_reveal(combat.has_fired(unit.unit_id()));
            }
            let events = playback_order(scenario, self.number, events)?;
            let supply_orders: Vec<_> = orders
                .iter()
                .filter(|order| {
                    events.iter().any(|event| {
                        event.unit_id == order.unit_id
                            && event.kind != TurnEventKind::MovementStopped
                    })
                })
                .map(|order| (order.unit_id, order.supply.clone()))
                .collect();
            supplies::resolve_orders(scenario, &supply_orders, self.number);
            let mut reports: Vec<_> = [PlayerNumber::Player1, PlayerNumber::Player2]
                .into_iter()
                .map(|player_number| {
                    TurnReport::before_replenishment(player_number, &initial_units, &scenario.units)
                })
                .collect();
            let settlement = scenario.finish_turn_resources(self.number);
            for report in &mut reports {
                report.finish(&initial_units, scenario, &settlement);
            }
            let resource_snapshot = settlement.units;
            let deaths = resource_snapshot.len() != scenario.units.len();
            // Bombardments retain identical settlement timing for empty and unseen hits.
            let settlement_pause = deaths
                || frames
                    .iter()
                    .any(|frame| !frame.indirect_impacts.is_empty());
            if settlement_pause {
                frames.push(TurnFrame {
                    indirect_impacts: Vec::new(),
                    depots: scenario.depots.clone(),
                    supply_crates: scenario.supply_crates.clone(),
                    shots: Vec::new(),
                    units: resource_snapshot,
                    visible_tiles: Vec::new(),
                    duration_ms: 180,
                });
            }
            frames.push(TurnFrame {
                indirect_impacts: Vec::new(),
                depots: scenario.depots.clone(),
                supply_crates: scenario.supply_crates.clone(),
                shots: Vec::new(),
                units: scenario.units.clone(),
                visible_tiles: Vec::new(),
                duration_ms: if settlement_pause { 1400 } else { 180 },
            });
            self.last_resolution = Some(TurnResolution {
                reports,
                turn_number: self.number,
                events,
                frames,
            });
            self.number += 1;
        }
        Ok(())
    }
}

fn legal_unload(
    scenario: &Scenario,
    passenger: &Unit,
    destination: Coordinate,
    moving_truck: Option<UnitId>,
) -> bool {
    if !passenger
        .supplies()
        .can_afford_movement(&scenario.map, &[destination, destination])
    {
        return false;
    }
    let Some(rule) = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == passenger.kind())
    else {
        return false;
    };
    let Some(terrain) = scenario.map.tile_at(destination) else {
        return false;
    };
    let affordable = rule
        .terrain_costs
        .iter()
        .any(|entry| entry.terrain == terrain && entry.cost > 0 && entry.cost <= rule.budget);
    let occupied = scenario.units.iter().any(|unit| {
        unit.is_alive()
            && Some(unit.unit_id()) != moving_truck
            && unit.board_position() == Some(destination)
    });
    affordable && !occupied
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        combat::CombatKind,
        map::{Map, Terrain},
        scenario::DepotKind,
        test_support::{FixtureValue, TestResult},
        visibility,
    };

    fn playback_fixture(scenario: &Scenario, counts: [usize; 2]) -> TestResult<Vec<TurnEvent>> {
        Ok({
            [PlayerNumber::Player1, PlayerNumber::Player2]
                .into_iter()
                .flat_map(|player_number| {
                    scenario
                        .units
                        .iter()
                        .filter(move |unit| unit.player_number() == player_number)
                        .take(counts[player_index(player_number)])
                })
                .map(|unit| TurnEvent {
                    unit_id: unit.unit_id(),
                    kind: TurnEventKind::Move,
                    path: vec![Coordinate::new(0, 0), Coordinate::new(1, 0)],
                    initial_direction: unit.direction(),
                    initial_sprite_facing: unit.sprite_facing(),
                    rotation_direction: None,
                    initial_carrier: None,
                    carrier_id: None,
                })
                .collect()
        })
    }

    #[test]
    fn playback_interleaves_three_moves_and_two_moves_and_switches_initiative() -> TestResult<()> {
        let scenario = Scenario::supply_point().fixture()?;
        let events = playback_fixture(&scenario, [3, 2])?;
        let ids: Vec<_> = events.iter().map(|event| event.unit_id).collect();
        let order = |turn, events| -> TestResult<Vec<UnitId>> {
            Ok(playback_order(&scenario, turn, events)?
                .into_iter()
                .map(|event| event.unit_id)
                .collect::<Vec<_>>())
        };
        assert_eq!(
            order(1, events.clone())?,
            vec![ids[0], ids[3], ids[1], ids[4], ids[2]]
        );
        assert_eq!(
            order(2, events.clone())?,
            vec![ids[3], ids[0], ids[1], ids[4], ids[2]]
        );
        let mut reversed = events.clone();
        reversed.reverse();
        assert_eq!(order(1, events)?, order(1, reversed)?);

        Ok(())
    }

    #[test]
    fn playback_spreads_unequal_forces_and_handles_empty_player_numbers() -> TestResult<()> {
        let scenario = Scenario::supply_point().fixture()?;
        for counts in [[8, 3], [3, 8], [8, 8], [0, 3], [3, 0], [0, 0]] {
            for turn in [1, 2] {
                let events = playback_fixture(&scenario, counts)?;
                let ordered = playback_order(&scenario, turn, events.clone())?;
                assert_eq!(ordered.len(), counts.iter().sum::<usize>());
                assert_eq!(
                    ordered
                        .iter()
                        .map(|event| event.unit_id)
                        .collect::<BTreeSet<_>>(),
                    events.iter().map(|event| event.unit_id).collect()
                );
                let mut seen = [0usize; 2];
                for event in ordered {
                    let unit = scenario
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == event.unit_id)
                        .fixture()?;
                    seen[player_index(unit.player_number())] += 1;
                    let total = seen.iter().sum::<usize>();
                    let expected =
                        total as f64 * counts[0] as f64 / counts.iter().sum::<usize>() as f64;
                    assert!((seen[0] as f64 - expected).abs() <= 1.0);
                }
            }
        }

        Ok(())
    }

    #[test]
    fn playback_keeps_transport_after_all_movement() -> TestResult<()> {
        let scenario = Scenario::supply_point().fixture()?;
        let mut events = playback_fixture(&scenario, [2, 2])?;
        let mut load = events[0].clone();
        load.kind = TurnEventKind::Load;
        let mut unload = events[1].clone();
        unload.kind = TurnEventKind::Unload;
        events.insert(0, unload);
        events.insert(1, load);
        let ordered = playback_order(&scenario, 2, events)?;
        assert!(
            ordered[..4]
                .iter()
                .all(|event| event.kind == TurnEventKind::Move)
        );
        assert_eq!(ordered[4].kind, TurnEventKind::Load);
        assert_eq!(ordered[5].kind, TurnEventKind::Unload);

        Ok(())
    }

    fn holds(scenario: &Scenario, player_number: PlayerNumber) -> TestResult<Vec<MoveOrderInput>> {
        Ok({
            scenario
                .units
                .iter()
                .filter(|unit| unit.player_number() == player_number)
                .map(|unit| {
                    let position = scenario.physical_position(unit).fixture()?;
                    Ok(MoveOrderInput {
                        ambush: None,
                        stand_ground: None,
                        indirect_fire: None,
                        attack_move: None,
                        direction: None,
                        unit_id: unit.id(),
                        unloads: None,
                        load_crates: None,
                        crate_unloads: None,
                        path: vec![CoordinateInput {
                            x: position.x(),
                            y: position.y(),
                        }],
                    })
                })
                .collect::<TestResult<Vec<_>>>()?
        })
    }

    #[test]
    fn mountain_paths_validate_entry_budget_and_vehicle_impassability() -> TestResult<()> {
        for kind in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::Truck,
            UnitKind::FieldGun,
        ] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario.map = Map::from_ascii(".^.").fixture()?;
            scenario.units.retain(|unit| {
                unit.player_number() == PlayerNumber::Player1 && unit.kind() == kind
            });
            scenario.units.truncate(1);
            scenario.units[0].move_to(Coordinate::new(0, 0));
            let id = scenario.units[0].id();
            let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut inputs, &id, &[(0, 0), (1, 0)])?;
            let result = validate(&scenario, PlayerNumber::Player1, inputs);
            if kind == UnitKind::Infantry {
                let orders = result.fixture()?;
                assert_eq!(orders[0].path.last(), Some(&Coordinate::new(1, 0)));
                let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
                set_path(&mut inputs, &id, &[(0, 0), (1, 0), (2, 0)])?;
                assert_eq!(
                    validate(&scenario, PlayerNumber::Player1, inputs).err(),
                    Some("movement exceeds the unit's budget.")
                );
            } else {
                assert_eq!(result.err(), Some("this terrain cannot be crossed."));
                assert!(!legal_unload(
                    &scenario,
                    &scenario.units[0],
                    Coordinate::new(1, 0),
                    None
                ));
            }
        }
        Ok(())
    }

    #[test]
    fn turn_report_counts_spending_without_refills_or_discarded_cargo_stock() -> TestResult<()> {
        for replenished in [false, true] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario
                .units
                .retain(|unit| ["1", "4", "6"].contains(&unit.id().as_str()));
            let carrier = UnitId::parse("4").fixture()?;
            let depot = scenario.depots.first().fixture()?.position;
            for unit in &mut scenario.units {
                if unit.player_number() == PlayerNumber::Player1 {
                    unit.move_to(depot);
                    if unit.id() == "1" {
                        unit.board(carrier);
                    }
                    if unit.id() == "4" {
                        unit.set_supplies_for_test(4);
                    }
                }
            }
            if !replenished {
                scenario.depots.clear();
            }
            let mut turns = Turns::default();
            resolve_holds(&mut scenario, &mut turns)?;
            let resolution = turns.last_resolution.as_ref().fixture()?;
            let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            let observed = crate::visibility::observed_resolution(
                &scenario,
                PlayerNumber::Player1,
                &visible,
                resolution,
            );
            assert_eq!(observed.reports.len(), 1);
            let report = observed.reports.first().fixture()?;
            assert_eq!(report.player_number, PlayerNumber::Player1);
            assert_eq!(report.units_lost, if replenished { 0 } else { 2 });
            assert_eq!(report.supplies_consumed, 8);
            assert_eq!(report.damage_inflicted, 0);
            assert_eq!(report.enemy_units_destroyed, 0);
        }
        Ok(())
    }

    #[test]
    fn turn_report_caps_known_damage_and_withholds_unobserved_enemy_losses() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.map = Map::from_ascii(".##").fixture()?;
        scenario.depots.clear();
        scenario
            .units
            .retain(|unit| ["11", "9", "6"].contains(&unit.id().as_str()));
        for unit in &mut scenario.units {
            match unit.id().as_str() {
                "11" => {
                    unit.move_to(Coordinate::new(0, 0));
                    unit.rotate(Direction::East);
                }
                "9" => {
                    unit.move_to(Coordinate::new(1, 0));
                    unit.take_damage(15);
                }
                _ => {
                    unit.move_to(Coordinate::new(2, 0));
                    unit.set_supplies_for_test(4);
                }
            }
        }
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        let attack = player1.first_mut().fixture()?;
        attack.attack_move = Some(true);
        attack.path.push(CoordinateInput { x: 1, y: 0 });
        let mut turns = Turns::default();
        resolve_orders(&mut scenario, &mut turns, player1)?;
        let resolution = turns.last_resolution.as_ref().fixture()?;
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let visible = crate::visibility::visible_tiles(&scenario, player_number);
            let observed = crate::visibility::observed_resolution(
                &scenario,
                player_number,
                &visible,
                resolution,
            );
            assert_eq!(observed.reports.len(), 1);
            let report = observed.reports.first().fixture()?;
            assert_eq!(report.player_number, player_number);
            if player_number == PlayerNumber::Player1 {
                assert_eq!(report.units_lost, 0);
                assert_eq!(report.enemy_units_destroyed, 1);
                assert_eq!(report.damage_inflicted, 1);
                assert_eq!(report.supplies_consumed, 20);
            } else {
                assert_eq!(report.units_lost, 2);
                assert_eq!(report.enemy_units_destroyed, 0);
                assert_eq!(report.damage_inflicted, 0);
                assert_eq!(report.supplies_consumed, 8);
            }
        }
        Ok(())
    }

    #[test]
    fn attack_move_charges_readiness_each_turn_without_an_encounter() -> TestResult<()> {
        for (attacker_id, movement_cost) in [("1", 3), ("11", 0)] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario.map = Map::from_ascii(".....").fixture()?;
            scenario.depots.clear();
            scenario
                .units
                .retain(|unit| unit.id() == attacker_id || unit.id() == "6");
            for unit in &mut scenario.units {
                unit.move_to(Coordinate::new(
                    if unit.player_number() == PlayerNumber::Player1 {
                        0
                    } else {
                        4
                    },
                    0,
                ));
                unit.set_supplies_for_test(128);
            }
            let mut turns = Turns::default();
            for (turn, origin, destination) in [(1, 0, 1), (2, 1, 0)] {
                let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
                set_path(&mut inputs, attacker_id, &[(origin, 0), (destination, 0)])?;
                inputs.first_mut().fixture()?.attack_move = Some(true);
                let enemy = holds(&scenario, PlayerNumber::Player2)?;
                turns
                    .submit(&mut scenario, PlayerNumber::Player1, turn, inputs)
                    .fixture()?;
                turns
                    .submit(&mut scenario, PlayerNumber::Player2, turn, enemy)
                    .fixture()?;
                let attacker = scenario
                    .units
                    .iter()
                    .find(|unit| unit.id() == attacker_id)
                    .fixture()?;
                assert_eq!(
                    attacker.supplies().current(),
                    128 - turn * (4 + 8 + movement_cost * 4)
                );
                assert!(
                    turns
                        .last_resolution
                        .as_ref()
                        .fixture()?
                        .frames
                        .iter()
                        .all(|frame| frame.shots.is_empty())
                );
                let report = turns
                    .last_resolution
                    .as_ref()
                    .fixture()?
                    .reports
                    .iter()
                    .find(|report| report.player_number == PlayerNumber::Player1)
                    .fixture()?;
                assert_eq!(report.supplies_consumed, 4 + 8 + movement_cost * 4);
                let defender = scenario
                    .units
                    .iter()
                    .find(|unit| unit.id() == "6")
                    .fixture()?;
                assert_eq!(defender.supplies().current(), 128 - turn * 4);
            }
        }
        Ok(())
    }

    #[test]
    fn attack_move_validation_and_submission_preserve_combat_resources() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.map = Map::from_ascii("....").fixture()?;
        scenario
            .units
            .retain(|unit| unit.id() == "1" || unit.id() == "6");
        for unit in &mut scenario.units {
            unit.move_to(Coordinate::new(
                if unit.player_number() == PlayerNumber::Player1 {
                    0
                } else {
                    2
                },
                0,
            ));
        }
        let attack = |board: &Scenario| -> TestResult<Vec<MoveOrderInput>> {
            let mut inputs = holds(board, PlayerNumber::Player1)?;
            inputs[0].attack_move = Some(true);
            inputs[0].path.extend([
                CoordinateInput { x: 1, y: 0 },
                CoordinateInput { x: 2, y: 0 },
            ]);
            Ok(inputs)
        };
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, attack(&scenario)?)?[0].travel,
            TravelMode::AttackMove
        );
        let mut invalid = attack(&scenario)?;
        invalid[0].direction = Some(Direction::East);
        assert!(validate(&scenario, PlayerNumber::Player1, invalid).is_err());
        let mut invalid = attack(&scenario)?;
        invalid[0].path.truncate(1);
        assert!(validate(&scenario, PlayerNumber::Player1, invalid).is_err());
        let mut low_supplies = scenario.clone();
        low_supplies.units[0].spend_supplies(156);
        assert!(validate(&low_supplies, PlayerNumber::Player1, attack(&low_supplies)?).is_err());
        for (sketch, required) in [("....", 48), (".%%.", 56), (".##.", 56)] {
            let mut terrain_scenario = scenario.clone();
            terrain_scenario.map = Map::from_ascii(sketch).fixture()?;
            terrain_scenario.units[0].set_supplies_for_test(required - 1);
            assert!(
                validate(
                    &terrain_scenario,
                    PlayerNumber::Player1,
                    attack(&terrain_scenario)?
                )
                .is_err()
            );
            terrain_scenario.units[0].set_supplies_for_test(required);
            assert!(
                validate(
                    &terrain_scenario,
                    PlayerNumber::Player1,
                    attack(&terrain_scenario)?
                )
                .is_ok()
            );
        }
        for destination in [1, 2] {
            let mut scenario = scenario.clone();
            let enemy_holds = holds(&scenario, PlayerNumber::Player2)?;
            let mut attacks = attack(&scenario)?;
            attacks[0].path.truncate(destination + 1);
            let mut turns = Turns::default();
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, attacks)?;
            turns.submit(&mut scenario, PlayerNumber::Player2, 1, enemy_holds)?;
            let attacker = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .fixture()?;
            let target = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "6")
                .fixture()?;
            assert_eq!(attacker.board_position(), Some(Coordinate::new(1, 0)));
            assert_eq!(attacker.supplies().current(), 156);
            assert_eq!(target.hit_points().current(), 10);
            assert_eq!(target.supplies().current(), 188);
            assert_eq!(
                turns
                    .last_resolution
                    .as_ref()
                    .fixture()?
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .count(),
                1
            );
        }
        Ok(())
    }

    #[test]
    fn firing_field_guns_are_revealed_for_the_following_turn_only() -> TestResult<()> {
        for gun_player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            for terrain in ["............", "..#........."] {
                let enemy_player_number = if gun_player_number == PlayerNumber::Player1 {
                    PlayerNumber::Player2
                } else {
                    PlayerNumber::Player1
                };
                let mut scenario = Scenario::supply_point().fixture()?;
                scenario.map = Map::from_ascii(terrain).fixture()?;
                let mut gun = scenario
                    .units
                    .iter()
                    .find(|unit| {
                        unit.player_number() == gun_player_number
                            && unit.kind() == UnitKind::FieldGun
                    })
                    .fixture()?
                    .clone();
                gun.move_to(Coordinate::new(2, 0));
                gun.take_damage(7);
                let gun_id = gun.unit_id();
                let mut target = scenario
                    .units
                    .iter()
                    .find(|unit| {
                        unit.player_number() == enemy_player_number && unit.kind() == UnitKind::Tank
                    })
                    .fixture()?
                    .clone();
                target.move_to(Coordinate::new(5, 0));
                scenario.units = vec![gun, target];
                let projected = |board: &Scenario| {
                    let visible = crate::visibility::visible_tiles(board, enemy_player_number);
                    crate::visibility::observed_scenario(board, enemy_player_number, &visible)
                };
                assert!(
                    !projected(&scenario)
                        .units
                        .iter()
                        .any(|unit| unit.unit_id() == gun_id)
                );
                let mut turns = Turns::default();
                // A second shot renews the reveal, even when it kills the last observer.
                for number in [1, 2] {
                    let mut inputs = holds(&scenario, gun_player_number)?;
                    inputs[0].ambush = Some(true);
                    inputs[0].direction = Some(Direction::East);
                    let enemy_inputs = holds(&scenario, enemy_player_number)?;
                    turns.submit(&mut scenario, gun_player_number, number, inputs)?;
                    turns.submit(&mut scenario, enemy_player_number, number, enemy_inputs)?;
                    let observed = projected(&scenario);
                    let revealed = observed
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == gun_id)
                        .fixture()?;
                    assert_eq!(revealed.board_position(), Some(Coordinate::new(2, 0)));
                    assert!(revealed.resources().is_none());
                    let visible = crate::visibility::visible_tiles(&scenario, enemy_player_number);
                    assert!(visible.contains(&Coordinate::new(2, 0)));
                    assert!(!visible.contains(&Coordinate::new(1, 0)));
                    let resolution = crate::visibility::observed_resolution(
                        &scenario,
                        enemy_player_number,
                        &visible,
                        turns.last_resolution.as_ref().fixture()?,
                    );
                    assert_eq!(
                        resolution
                            .frames
                            .first()
                            .fixture()?
                            .units
                            .iter()
                            .any(|unit| unit.unit_id() == gun_id),
                        number == 2
                    );
                    assert!(
                        resolution
                            .frames
                            .last()
                            .fixture()?
                            .units
                            .iter()
                            .any(|unit| unit.unit_id() == gun_id)
                    );
                }
                resolve_holds(&mut scenario, &mut turns)?;
                assert!(
                    !projected(&scenario)
                        .units
                        .iter()
                        .any(|unit| unit.unit_id() == gun_id)
                );
                let visible = crate::visibility::visible_tiles(&scenario, enemy_player_number);
                let resolution = crate::visibility::observed_resolution(
                    &scenario,
                    enemy_player_number,
                    &visible,
                    turns.last_resolution.as_ref().fixture()?,
                );
                assert!(
                    resolution
                        .frames
                        .first()
                        .fixture()?
                        .units
                        .iter()
                        .any(|unit| unit.unit_id() == gun_id)
                );
                assert!(
                    !resolution
                        .frames
                        .last()
                        .fixture()?
                        .units
                        .iter()
                        .any(|unit| unit.unit_id() == gun_id)
                );
            }
        }
        Ok(())
    }

    #[test]
    fn ambush_submission_resolves_damage_costs_and_facing_in_both_submission_orders()
    -> TestResult<()> {
        for first in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario.depots.clear();
            scenario
                .units
                .retain(|unit| unit.id() == "1" || unit.id() == "6");
            scenario.units[0].move_to(Coordinate::new(7, 8));
            scenario.units[1].move_to(Coordinate::new(8, 8));
            let mut turns = Turns::default();
            for player_number in [
                first,
                if first == PlayerNumber::Player1 {
                    PlayerNumber::Player2
                } else {
                    PlayerNumber::Player1
                },
            ] {
                let mut inputs = holds(&scenario, player_number)?;
                if player_number == PlayerNumber::Player1 {
                    inputs[0].ambush = Some(true);
                    inputs[0].direction = Some(Direction::East);
                }
                turns.submit(&mut scenario, player_number, 1, inputs)?;
            }
            assert_eq!(turns.number, 2);
            assert_eq!(scenario.units[0].hit_points().current(), 16);
            assert_eq!(scenario.units[1].hit_points().current(), 10);
            assert_eq!(scenario.units[0].supplies().current(), 168);
            assert_eq!(scenario.units[1].supplies().current(), 188);
            assert_eq!(scenario.units[0].direction(), Some(Direction::East));
            let resolution = turns.last_resolution.as_ref().fixture()?;
            assert_eq!(
                resolution
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .count(),
                1
            );
            assert_eq!(
                resolution.frames.last().fixture()?.units[0].supplies(),
                scenario.units[0].supplies()
            );
            assert_eq!(
                resolution
                    .events
                    .iter()
                    .find(|event| event.unit_id == scenario.units[0].unit_id())
                    .fixture()?
                    .kind,
                TurnEventKind::Ambush
            );
            let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            let projected = crate::visibility::observed_resolution(
                &scenario,
                PlayerNumber::Player1,
                &visible,
                resolution,
            );
            assert_eq!(
                projected
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .count(),
                1
            );
        }
        Ok(())
    }

    #[test]
    fn ambush_initial_contacts_resolve_after_their_submitted_movement() -> TestResult<()> {
        for first in [PlayerNumber::Player1, PlayerNumber::Player2] {
            for (destinations, damage) in [
                (vec![], 9),
                (vec![(9, 8)], 9),
                (vec![(9, 8), (9, 7)], 9),
                (vec![(8, 7)], 0),
            ] {
                let mut scenario = Scenario::supply_point().fixture()?;
                scenario
                    .units
                    .retain(|unit| unit.id() == "12" || unit.id() == "6");
                scenario.map =
                    crate::map::Map::new(17, 17, crate::map::Terrain::GrassPlain, BTreeMap::new())
                        .fixture()?;
                for unit in &mut scenario.units {
                    unit.move_to(if unit.player_number() == PlayerNumber::Player1 {
                        Coordinate::new(7, 8)
                    } else {
                        Coordinate::new(8, 8)
                    });
                }
                scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.id() == "12")
                    .fixture()?
                    .take_damage(7);
                let mut turns = Turns::default();
                let second = if first == PlayerNumber::Player1 {
                    PlayerNumber::Player2
                } else {
                    PlayerNumber::Player1
                };
                for player_number in [first, second] {
                    let mut inputs = holds(&scenario, player_number)?;
                    let order = inputs.first_mut().fixture()?;
                    if player_number == PlayerNumber::Player1 {
                        order.ambush = Some(true);
                        order.direction = Some(Direction::East);
                    } else {
                        order.path.extend(
                            destinations
                                .iter()
                                .map(|(x, y)| CoordinateInput { x: *x, y: *y }),
                        );
                    }
                    turns.submit(&mut scenario, player_number, 1, inputs)?;
                }
                let target = scenario
                    .units
                    .iter()
                    .find(|unit| unit.id() == "6")
                    .fixture()?;
                assert_eq!(target.hit_points().current(), 16 - damage);
                let (x, y) = destinations.last().copied().unwrap_or((8, 8));
                assert_eq!(
                    target.board_position(),
                    Some(Coordinate::new(u16::try_from(x)?, u16::try_from(y)?))
                );
                let resolution = turns.last_resolution.as_ref().fixture()?;
                let movement = resolution
                    .events
                    .iter()
                    .find(|event| event.unit_id == target.unit_id())
                    .fixture()?;
                assert_eq!(movement.path.len(), destinations.len() + 1);
                if !destinations.is_empty() && damage > 0 {
                    let arrival = resolution
                        .frames
                        .iter()
                        .position(|frame| {
                            frame.units.iter().any(|unit| {
                                unit.unit_id() == target.unit_id()
                                    && unit.board_position() == target.board_position()
                            })
                        })
                        .fixture()?;
                    let shot = resolution
                        .frames
                        .iter()
                        .position(|frame| !frame.shots.is_empty())
                        .fixture()?;
                    assert!(shot > arrival);
                }
            }
        }
        Ok(())
    }

    #[test]
    fn ambush_engages_a_passenger_unloading_from_a_concealed_truck() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        scenario
            .units
            .retain(|unit| ["6", "9", "12"].contains(&unit.id().as_str()));
        scenario.map = crate::map::Map::new(
            17,
            17,
            crate::map::Terrain::GrassPlain,
            BTreeMap::from([(Coordinate::new(9, 8), crate::map::Terrain::Forest)]),
        )
        .fixture()?;
        let truck_id = UnitId::parse("9").fixture()?;
        for unit in &mut scenario.units {
            if unit.id() == "6" {
                unit.board(truck_id);
            } else if unit.id() == "9" {
                unit.move_to(Coordinate::new(9, 8));
            } else {
                unit.move_to(Coordinate::new(7, 8));
            }
        }
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "12")
            .fixture()?
            .take_damage(4);
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        player1[0].ambush = Some(true);
        player1[0].direction = Some(Direction::East);
        let mut player2 = holds(&scenario, PlayerNumber::Player2)?;
        player2
            .iter_mut()
            .find(|order| order.unit_id == "9")
            .fixture()?
            .unloads = Some(vec![UnloadOrderInput {
            unit_id: "6".into(),
            destination: CoordinateInput { x: 8, y: 8 },
        }]);
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, player1)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, player2)?;
        let passenger = scenario
            .units
            .iter()
            .find(|unit| unit.id() == "6")
            .fixture()?;
        assert_eq!(passenger.board_position(), Some(Coordinate::new(8, 8)));
        assert_eq!(passenger.hit_points().current(), 1);
        assert_eq!(passenger.supplies().current(), 176);
        let gun = scenario
            .units
            .iter()
            .find(|unit| unit.id() == "12")
            .fixture()?;
        assert_eq!(gun.hit_points().current(), 12);
        assert_eq!(gun.supplies().current(), 232);
        let resolution = turns.last_resolution.fixture()?;
        let unload_frame = resolution
            .frames
            .iter()
            .position(|frame| {
                frame
                    .units
                    .iter()
                    .any(|unit| unit.id() == "6" && unit.board_position().is_some())
            })
            .fixture()?;
        let shot_frame = resolution
            .frames
            .iter()
            .position(|frame| !frame.shots.is_empty())
            .fixture()?;
        assert!(shot_frame > unload_frame);
        assert_eq!(
            resolution
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .count(),
            1
        );
        Ok(())
    }

    #[test]
    fn stand_ground_validates_and_resolves_with_readiness_and_upkeep() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let original = scenario.units[0].clone();
        let mut turns = Turns::default();
        let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
        inputs[0].stand_ground = Some(true);
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, inputs)?;
        let other = holds(&scenario, PlayerNumber::Player2)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, other)?;
        assert_eq!(
            scenario.units[0].board_position(),
            original.board_position()
        );
        assert_eq!(scenario.units[0].direction(), original.direction());
        assert_eq!(
            scenario.units[0].supplies().current(),
            original.supplies().current() - 12
        );
        let resolution = turns.last_resolution.as_ref().fixture()?;
        assert!(resolution.frames.iter().all(|frame| frame.shots.is_empty()));
        assert_eq!(
            resolution
                .events
                .iter()
                .find(|event| event.unit_id == original.unit_id())
                .fixture()?
                .kind,
            TurnEventKind::StandGround
        );
        Ok(())
    }

    #[test]
    fn stand_ground_rejects_other_actions_trucks_and_low_supplies() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        for other in 0..6 {
            let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
            inputs[0].stand_ground = Some(true);
            match other {
                0 => inputs[0].path.push(CoordinateInput { x: 4, y: 7 }),
                1 => inputs[0].direction = Some(Direction::East),
                2 => inputs[0].ambush = Some(true),
                3 => inputs[0].attack_move = Some(true),
                4 => inputs[0].load_crates = Some(1),
                _ => {
                    inputs[0].stand_ground = None;
                    inputs[3].stand_ground = Some(true);
                }
            }
            assert!(validate(&scenario, PlayerNumber::Player1, inputs).is_err());
        }
        let carrier_id = scenario.units[3].unit_id();
        let mut aboard = scenario.clone();
        aboard.units[0].board(carrier_id);
        let mut inputs = holds(&aboard, PlayerNumber::Player1)?;
        inputs[0].stand_ground = Some(true);
        assert!(validate(&aboard, PlayerNumber::Player1, inputs).is_err());
        scenario.units[0].spend_supplies(184);
        let mut inputs = holds(&scenario, PlayerNumber::Player1)?;
        inputs[0].stand_ground = Some(true);
        let mut turns = Turns::default();
        assert!(
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, inputs)
                .is_err()
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(scenario.units[0].supplies().current(), 8);
        Ok(())
    }

    #[test]
    fn ambush_validation_rejects_missing_direction_trucks_movement_and_insufficient_readiness()
    -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].ambush = Some(true);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].ambush = Some(true);
        orders[0].direction = Some(Direction::East);
        orders[0].path.push(CoordinateInput { x: 4, y: 7 });
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[3].ambush = Some(true);
        orders[3].direction = Some(Direction::East);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        scenario.units[0].spend_supplies(184);
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].ambush = Some(true);
        orders[0].direction = Some(Direction::East);
        let mut turns = Turns::default();
        assert!(
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                .is_err()
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(scenario.units[0].supplies().current(), 8);
        Ok(())
    }

    #[test]
    fn standalone_rotation_is_rejected_without_changing_state() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let originals = scenario.units.clone();
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders.first_mut().fixture()?.direction = Some(Direction::West);
        let mut turns = Turns::default();
        assert_eq!(
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, orders),
            Err("a facing direction requires an ambush order.")
        );
        assert_eq!(turns.number, 1);
        assert!(turns.last_resolution.is_none());
        for (unit, original) in scenario.units.iter().zip(&originals) {
            assert_eq!(unit.direction(), original.direction());
            assert_eq!(unit.supplies(), original.supplies());
        }
        let holds = holds(&scenario, PlayerNumber::Player1)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, holds)
            .fixture()?;
        Ok(())
    }

    #[test]
    fn ambush_rejects_trucks_passengers_movement_and_load_receivers() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        let truck_order = orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?;
        truck_order.ambush = Some(true);
        truck_order.direction = Some(Direction::North);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders.first_mut().fixture()?.ambush = Some(true);
        orders[0].direction = Some(Direction::North);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        vehicle(&mut scenario, "1")?.board(UnitId::parse("4").fixture()?);
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders.first_mut().fixture()?.ambush = Some(true);
        orders[0].direction = Some(Direction::North);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        vehicle(&mut scenario, "1")?.move_to(Coordinate::new(3, 7));
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders.first_mut().fixture()?.ambush = Some(true);
        orders[0].direction = Some(Direction::North);
        set_path(&mut orders, "4", &[(2, 7), (3, 7)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());

        Ok(())
    }

    fn set_path(orders: &mut [MoveOrderInput], id: &str, path: &[(i32, i32)]) -> TestResult<()> {
        orders
            .iter_mut()
            .find(|order| order.unit_id == id)
            .fixture()?
            .path = path
            .iter()
            .map(|&(x, y)| CoordinateInput { x, y })
            .collect();

        Ok(())
    }

    fn vehicle<'a>(scenario: &'a mut Scenario, id: &str) -> TestResult<&'a mut Unit> {
        Ok({
            scenario
                .units
                .iter_mut()
                .find(|unit| unit.id() == id)
                .fixture()?
        })
    }

    fn resolve_holds(scenario: &mut Scenario, turns: &mut Turns) -> TestResult<()> {
        let player1 = holds(scenario, PlayerNumber::Player1)?;
        let player2 = holds(scenario, PlayerNumber::Player2)?;
        let number = turns.number;
        turns
            .submit(scenario, PlayerNumber::Player1, number, player1)
            .fixture()?;
        turns
            .submit(scenario, PlayerNumber::Player2, number, player2)
            .fixture()?;

        Ok(())
    }

    fn resolve_orders(
        scenario: &mut Scenario,
        turns: &mut Turns,
        player1: Vec<MoveOrderInput>,
    ) -> TestResult<()> {
        let player2 = holds(scenario, PlayerNumber::Player2)?;
        let number = turns.number;
        turns
            .submit(scenario, PlayerNumber::Player1, number, player1)
            .fixture()?;
        turns
            .submit(scenario, PlayerNumber::Player2, number, player2)
            .fixture()?;

        Ok(())
    }

    #[test]
    fn two_units_board_then_ride_and_unload_without_walking_costs() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(3, 7), (2, 7)])?;
        set_path(&mut player1, "2", &[(3, 8), (2, 8), (2, 7)])?;
        resolve_orders(&mut scenario, &mut turns, player1)?;
        let truck = UnitId::parse("4").fixture()?;
        for id in ["1", "2"] {
            assert_eq!(vehicle(&mut scenario, id)?.carrier_id(), Some(truck));
            assert_eq!(
                scenario
                    .physical_position(
                        scenario
                            .units
                            .iter()
                            .find(|unit| unit.id() == id)
                            .fixture()?
                    )
                    .fixture()?,
                Coordinate::new(2, 7)
            );
        }
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 176);
        assert_eq!(vehicle(&mut scenario, "2")?.supplies().current(), 164);
        assert_eq!(
            turns
                .last_resolution
                .as_ref()
                .fixture()?
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::Load)
                .count(),
            2
        );
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 8), (1, 8)])?;
        resolve_orders(&mut scenario, &mut turns, player1)?;
        for id in ["1", "2"] {
            assert_eq!(
                scenario
                    .physical_position(
                        scenario
                            .units
                            .iter()
                            .find(|unit| unit.id() == id)
                            .fixture()?
                    )
                    .fixture()?,
                Coordinate::new(1, 8)
            );
        }
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 172);
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 120);
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(1, 8), (0, 8)])?;
        set_path(&mut player1, "2", &[(1, 8), (1, 7)])?;
        resolve_orders(&mut scenario, &mut turns, player1)?;
        assert_eq!(vehicle(&mut scenario, "1")?.carrier_id(), None);
        assert_eq!(vehicle(&mut scenario, "2")?.carrier_id(), None);
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "1")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(0, 8)
        );
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "2")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(1, 7)
        );
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 156);

        Ok(())
    }

    #[test]
    fn truck_moves_then_unloads_selected_passengers_at_chosen_squares() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut turns = Turns::default();
        let truck = UnitId::parse("4").fixture()?;
        vehicle(&mut scenario, "1")?.board(truck);
        vehicle(&mut scenario, "2")?.board(truck);
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "4", &[(2, 7), (2, 8), (1, 8)])?;
        orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .unloads = Some(vec![UnloadOrderInput {
            unit_id: "1".into(),
            destination: CoordinateInput { x: 0, y: 8 },
        }]);
        resolve_orders(&mut scenario, &mut turns, orders)?;
        assert_eq!(
            vehicle(&mut scenario, "1")?.board_position(),
            Some(Coordinate::new(0, 8))
        );
        assert_eq!(vehicle(&mut scenario, "2")?.carrier_id(), Some(truck));
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 176);
        assert_eq!(vehicle(&mut scenario, "2")?.supplies().current(), 188);
        let events = &turns.last_resolution.as_ref().fixture()?.events;
        let movement_index = events
            .iter()
            .position(|event| event.unit_id == truck)
            .fixture()?;
        let unload_index = events
            .iter()
            .position(|event| event.kind == TurnEventKind::Unload)
            .fixture()?;
        assert!(unload_index > movement_index);
        assert_eq!(
            events[unload_index].path,
            vec![Coordinate::new(1, 8), Coordinate::new(0, 8)]
        );

        Ok(())
    }

    #[test]
    fn truck_unloads_validate_cargo_adjacency_and_reserved_destinations() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let truck = UnitId::parse("4").fixture()?;
        vehicle(&mut scenario, "1")?.board(truck);
        vehicle(&mut scenario, "2")?.board(truck);
        for (passenger, x, y) in [("3", 1, 8), ("1", 0, 8), ("1", 2, 9)] {
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "4", &[(2, 7), (2, 8)])?;
            orders
                .iter_mut()
                .find(|order| order.unit_id == "4")
                .fixture()?
                .unloads = Some(vec![UnloadOrderInput {
                unit_id: passenger.into(),
                destination: CoordinateInput { x, y },
            }]);
            if passenger == "1" && x == 2 {
                // Two passengers cannot share one exit.
                orders
                    .iter_mut()
                    .find(|order| order.unit_id == "4")
                    .fixture()?
                    .unloads
                    .as_mut()
                    .fixture()?
                    .push(UnloadOrderInput {
                        unit_id: "2".into(),
                        destination: CoordinateInput { x, y },
                    });
            }
            assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        }

        Ok(())
    }

    #[test]
    fn visible_enemy_unload_exits_still_reject_the_draft_atomically() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.map = Map::from_ascii("...\n...\n...").fixture()?;
        scenario
            .units
            .retain(|unit| ["1", "4", "6"].contains(&unit.id().as_str()));
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(1, 0));
        vehicle(&mut scenario, "1")?.board(UnitId::parse("4").fixture()?);
        vehicle(&mut scenario, "6")?.move_to(Coordinate::new(1, 1));
        let mut own = holds(&scenario, PlayerNumber::Player1)?;
        own.iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .unloads = Some(vec![UnloadOrderInput {
            unit_id: "1".into(),
            destination: CoordinateInput { x: 1, y: 1 },
        }]);
        let mut turns = Turns::default();
        assert_eq!(
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, own),
            Err("unloading requires an empty affordable adjacent square.")
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(turns.number, 1);
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 192);

        Ok(())
    }

    #[test]
    fn concealed_unload_exits_accept_orders_and_resolve_against_actual_occupancy() -> TestResult<()>
    {
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let (passenger_id, truck_id, enemy_id) = if player_number == PlayerNumber::Player1 {
                ("1", "4", "6")
            } else {
                ("6", "9", "1")
            };
            let opponent = if player_number == PlayerNumber::Player1 {
                PlayerNumber::Player2
            } else {
                PlayerNumber::Player1
            };
            for first in [player_number, opponent] {
                for moving_truck in [false, true] {
                    for direct_unload in [false, true] {
                        if moving_truck && direct_unload {
                            continue;
                        }
                        for enemy_leaves in [false, true] {
                            let mut scenario = Scenario::supply_point().fixture()?;
                            scenario.map = Map::from_ascii("...\n.#.\n...").fixture()?;
                            scenario.units.retain(|unit| {
                                [passenger_id, truck_id, enemy_id].contains(&unit.id().as_str())
                            });
                            let truck_origin = if moving_truck {
                                Coordinate::new(0, 0)
                            } else {
                                Coordinate::new(1, 0)
                            };
                            vehicle(&mut scenario, truck_id)?.move_to(truck_origin);
                            vehicle(&mut scenario, passenger_id)?
                                .board(UnitId::parse(truck_id).fixture()?);
                            vehicle(&mut scenario, enemy_id)?.move_to(Coordinate::new(1, 1));
                            let mut own = holds(&scenario, player_number)?;
                            if moving_truck {
                                set_path(&mut own, truck_id, &[(0, 0), (1, 0)])?;
                            }
                            if direct_unload {
                                set_path(&mut own, passenger_id, &[(1, 0), (1, 1)])?;
                            } else {
                                own.iter_mut()
                                    .find(|order| order.unit_id == truck_id)
                                    .fixture()?
                                    .unloads = Some(vec![UnloadOrderInput {
                                    unit_id: passenger_id.into(),
                                    destination: CoordinateInput { x: 1, y: 1 },
                                }]);
                            }
                            // A hidden blocker must not change submission acceptance.
                            let mut opposing = holds(&scenario, opponent)?;
                            if enemy_leaves {
                                set_path(&mut opposing, enemy_id, &[(1, 1), (2, 1)])?;
                            }
                            let submissions = if first == player_number {
                                [(player_number, own), (opponent, opposing)]
                            } else {
                                [(opponent, opposing), (player_number, own)]
                            };
                            let mut turns = Turns::default();
                            for (owner, orders) in submissions {
                                turns.submit(&mut scenario, owner, 1, orders).fixture()?;
                            }
                            assert_eq!(turns.number, 2);
                            assert_eq!(
                                vehicle(&mut scenario, truck_id)?.board_position(),
                                Some(Coordinate::new(1, 0))
                            );
                            assert_eq!(
                                vehicle(&mut scenario, truck_id)?.fuel().fixture()?.current,
                                if moving_truck { 124 } else { 128 }
                            );
                            let passenger = vehicle(&mut scenario, passenger_id)?;
                            if enemy_leaves {
                                assert_eq!(passenger.board_position(), Some(Coordinate::new(1, 1)));
                                assert_eq!(
                                    passenger.supplies().current(),
                                    188 - passenger.supplies().movement_per_tile()
                                        - passenger.supplies().rough_terrain_surcharge()
                                );
                            } else {
                                assert_eq!(passenger.carrier_id(), UnitId::parse(truck_id));
                                assert_eq!(passenger.supplies().current(), 188);
                                let visible =
                                    crate::visibility::visible_tiles(&scenario, player_number);
                                let projected = crate::visibility::observed_resolution(
                                    &scenario,
                                    player_number,
                                    &visible,
                                    turns.last_resolution.as_ref().fixture()?,
                                );
                                assert!(projected.frames.iter().all(|frame| {
                                    frame
                                        .units
                                        .iter()
                                        .all(|unit| unit.player_number() == player_number)
                                }));
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    #[test]
    fn blocked_truck_and_occupied_exit_keep_passengers_aboard() -> TestResult<()> {
        for block_truck in [false, true] {
            let mut scenario = Scenario::supply_point().fixture()?;
            let mut turns = Turns::default();
            let truck = UnitId::parse("4").fixture()?;
            vehicle(&mut scenario, "1")?.board(truck);
            vehicle(&mut scenario, "6")?.move_to(Coordinate::new(0, 9));
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "4", &[(2, 7), (2, 8), (1, 8)])?;
            orders
                .iter_mut()
                .find(|order| order.unit_id == "4")
                .fixture()?
                .unloads = Some(vec![UnloadOrderInput {
                unit_id: "1".into(),
                destination: CoordinateInput { x: 0, y: 8 },
            }]);
            let mut opponent = holds(&scenario, PlayerNumber::Player2)?;
            if block_truck {
                set_path(&mut opponent, "6", &[(0, 9), (1, 9), (1, 8)])?;
            } else {
                set_path(&mut opponent, "6", &[(0, 9), (0, 8)])?;
            }
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                .fixture()?;
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, opponent)
                .fixture()?;
            assert_eq!(vehicle(&mut scenario, "1")?.carrier_id(), Some(truck));
            assert!(
                !turns
                    .last_resolution
                    .as_ref()
                    .fixture()?
                    .events
                    .iter()
                    .any(|event| event.kind == TurnEventKind::Unload)
            );
        }

        Ok(())
    }

    #[test]
    fn trucks_collect_field_guns_and_can_fill_the_second_berth() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (3, 7), (4, 7)])?;
        resolve_orders(&mut scenario, &mut turns, player1)?;
        assert_eq!(
            vehicle(&mut scenario, "12")?.carrier_id(),
            UnitId::parse("4")
        );
        assert_eq!(vehicle(&mut scenario, "12")?.supplies().current(), 252);
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(4, 7), (3, 7)])?;
        resolve_orders(&mut scenario, &mut turns, player1)?;
        assert_eq!(
            vehicle(&mut scenario, "1")?.carrier_id(),
            UnitId::parse("4")
        );
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "12")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(3, 7)
        );
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "2", &[(3, 8), (3, 7)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, player1).is_err());

        Ok(())
    }

    #[test]
    fn transport_rejects_overcapacity_tanks_moving_receivers_and_invalid_unloads() -> TestResult<()>
    {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "3")?.move_to(Coordinate::new(2, 6));
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(3, 7), (2, 7)])?;
        set_path(&mut player1, "2", &[(3, 8), (2, 8), (2, 7)])?;
        set_path(&mut player1, "3", &[(2, 6), (2, 7)])?;
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, player1)
                .err()
                .fixture()?,
            "the truck has no room for another unit."
        );
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (3, 7), (4, 7), (4, 8)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, player1).is_err());
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(3, 7), (2, 7)])?;
        set_path(&mut player1, "4", &[(2, 7), (2, 8)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, player1).is_ok());
        vehicle(&mut scenario, "1")?.board(UnitId::parse("4").fixture()?);

        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(2, 7), (1, 7), (0, 7)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, player1).is_err());
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(2, 7), (1, 7)])?;
        set_path(&mut player1, "4", &[(2, 7), (2, 8)])?;
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, player1)
                .err()
                .fixture()?,
            "the truck must hold while unloading."
        );
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(2, 7), (2, 6)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, player1).is_err());

        Ok(())
    }

    #[test]
    fn supplies_charge_upkeep_once_and_walking_movement_only() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let mut turns = Turns::default();
        for unit in &mut scenario.units {
            let supplies = if unit.kind() == UnitKind::Infantry {
                28
            } else {
                12
            };
            unit.set_supplies_for_test(supplies);
        }
        let number = turns.number;
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)])?;
        set_path(&mut player1, "13", &[(4, 9), (4, 10)])?;
        set_path(&mut player1, "4", &[(2, 7), (2, 6)])?;
        set_path(&mut player1, "11", &[(4, 8), (5, 8)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, number, player1)
            .fixture()?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, number, vec![])
            .fixture()?;
        assert!(scenario.units.iter().all(|unit| unit.supplies().current()
            == if unit.kind() == UnitKind::Infantry {
                28
            } else {
                12
            }));
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, number, player2)
            .fixture()?;
        assert!(!scenario.units.iter().any(|unit| unit.id() == "1"));
        let resolution = turns.last_resolution.as_ref().fixture()?;
        let death_frame = &resolution.frames[resolution.frames.len() - 2];
        let dead = death_frame
            .units
            .iter()
            .find(|unit| unit.id() == "1")
            .fixture()?;
        assert_eq!(dead.supplies().current(), 0);
        assert_eq!(resolution.frames.last().fixture()?.duration_ms, 1400);
        let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
        let observed = crate::visibility::observed_resolution(
            &scenario,
            PlayerNumber::Player1,
            &visible,
            resolution,
        );
        assert!(
            observed
                .events
                .iter()
                .any(|event| event.unit_id == dead.unit_id())
        );
        assert!(
            observed.frames[observed.frames.len() - 2]
                .units
                .iter()
                .any(|unit| unit.id() == "1")
        );
        assert!(
            observed
                .frames
                .iter()
                .all(|frame| !frame.units.iter().any(|unit| unit.id() == "6"))
        );
        for id in ["2", "6"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 24);
        }
        assert_eq!(vehicle(&mut scenario, "13")?.supplies().current(), 4);
        for id in ["4", "11"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 8);
        }
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 124);
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 120);

        Ok(())
    }

    #[test]
    fn supplies_reserve_upkeep_reject_movement_and_die_at_zero() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        let mut turns = Turns::default();
        for unit in &mut scenario.units {
            unit.set_supplies_for_test(8);
        }
        resolve_holds(&mut scenario, &mut turns)?;
        let number = turns.number;
        for (id, path) in [("1", vec![(3, 7), (3, 6)]), ("12", vec![(4, 7), (4, 6)])] {
            let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut player1, id, &path)?;
            assert_eq!(
                turns.submit(&mut scenario, PlayerNumber::Player1, number, player1),
                Err("movement exceeds supplies available after upkeep.")
            );
            assert!(turns.orders[0].is_none());
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 4);
        }
        resolve_holds(&mut scenario, &mut turns)?;
        resolve_holds(&mut scenario, &mut turns)?;
        assert!(scenario.units.is_empty());
        assert!(
            turns
                .last_resolution
                .as_ref()
                .fixture()?
                .frames
                .last()
                .fixture()?
                .units
                .is_empty()
        );

        Ok(())
    }

    #[test]
    fn depots_replenish_supplies_before_upkeep() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(14, 8));
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "5")?.move_to(Coordinate::new(8, 8));
        for id in ["4", "5", "9"] {
            vehicle(&mut scenario, id)?.set_supplies_for_test(4);
        }
        let mut turns = Turns::default();
        resolve_holds(&mut scenario, &mut turns)?;
        for id in ["4", "5", "9"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 124);
        }
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns)?;
        for id in ["4", "9"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 124);
        }
        assert_eq!(vehicle(&mut scenario, "5")?.supplies().current(), 124);

        Ok(())
    }

    #[test]
    fn walking_encounters_charge_only_traversed_tiles() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "6")?.move_to(Coordinate::new(5, 6));
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        let mut player2 = holds(&scenario, PlayerNumber::Player2)?;
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)])?;
        set_path(&mut player2, "6", &[(5, 6), (4, 6)])?;
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 176);
        assert_eq!(vehicle(&mut scenario, "6")?.supplies().current(), 176);
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "1")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(3, 6)
        );
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "6")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(4, 6)
        );

        Ok(())
    }

    #[test]
    fn tank_chase_resolves_identically_in_either_submission_order() -> TestResult<()> {
        let mut initial = Scenario::supply_point().fixture()?;
        initial.map =
            crate::map::Map::new(17, 17, crate::map::Terrain::GrassPlain, BTreeMap::new())
                .fixture()?;
        initial
            .units
            .retain(|unit| ["11", "6"].contains(&unit.id().as_str()));
        vehicle(&mut initial, "11")?.move_to(Coordinate::new(0, 0));
        vehicle(&mut initial, "6")?.move_to(Coordinate::new(2, 0));
        let mut outcomes = Vec::new();
        for first in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let mut scenario = initial.clone();
            let mut p1 = holds(&scenario, PlayerNumber::Player1)?;
            let mut p2 = holds(&scenario, PlayerNumber::Player2)?;
            set_path(
                &mut p1,
                "11",
                &[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0)],
            )?;
            set_path(&mut p2, "6", &[(2, 0), (3, 0), (4, 0)])?;
            let submissions = if first == PlayerNumber::Player1 {
                [(PlayerNumber::Player1, p1), (PlayerNumber::Player2, p2)]
            } else {
                [(PlayerNumber::Player2, p2), (PlayerNumber::Player1, p1)]
            };
            let mut turns = Turns::default();
            for (player_number, orders) in submissions {
                turns
                    .submit(&mut scenario, player_number, 1, orders)
                    .fixture()?;
            }
            assert_eq!(
                vehicle(&mut scenario, "11")?.board_position(),
                Some(Coordinate::new(1, 0))
            );
            assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 120);
            assert_eq!(
                vehicle(&mut scenario, "6")?.board_position(),
                Some(Coordinate::new(2, 0))
            );
            assert_eq!(vehicle(&mut scenario, "6")?.supplies().current(), 188);
            assert_eq!(
                vehicle(&mut scenario, "6")?.direction(),
                vehicle(&mut initial, "6")?.direction()
            );
            let resolution = turns.last_resolution.as_ref().fixture()?;
            assert!(
                resolution
                    .events
                    .iter()
                    .all(|event| event.kind == TurnEventKind::MovementStopped)
            );
            // Projection must preserve the shared schedule, while withholding hidden units.
            let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            let observed = crate::visibility::observed_resolution(
                &scenario,
                PlayerNumber::Player1,
                &visible,
                resolution,
            );
            assert_eq!(
                observed
                    .frames
                    .iter()
                    .map(|frame| frame.duration_ms)
                    .collect::<Vec<_>>(),
                resolution
                    .frames
                    .iter()
                    .map(|frame| frame.duration_ms)
                    .collect::<Vec<_>>()
            );
            outcomes.push(
                resolution
                    .frames
                    .iter()
                    .map(|frame| {
                        frame
                            .units
                            .iter()
                            .map(|unit| (unit.unit_id(), unit.board_position(), unit.direction()))
                            .collect::<Vec<_>>()
                    })
                    .collect::<Vec<_>>(),
            );
        }
        assert_eq!(outcomes[0], outcomes[1]);

        Ok(())
    }

    #[test]
    fn concealed_enemy_destination_is_resolved_instead_of_rejected() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .units
            .retain(|unit| ["1", "6"].contains(&unit.id().as_str()));
        scenario.map = Map::from_ascii(".#").fixture()?;
        vehicle(&mut scenario, "1")?.move_to(Coordinate::new(0, 0));
        vehicle(&mut scenario, "6")?.move_to(Coordinate::new(1, 0));
        let mut p1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut p1, "1", &[(0, 0), (1, 0)])?;
        let p2 = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, p1)
            .fixture()?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, p2)
            .fixture()?;
        assert_eq!(
            vehicle(&mut scenario, "1")?.board_position(),
            Some(Coordinate::new(0, 0))
        );
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 188);
        let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
        let observed = crate::visibility::observed_resolution(
            &scenario,
            PlayerNumber::Player1,
            &visible,
            turns.last_resolution.as_ref().fixture()?,
        );
        assert!(observed.frames.iter().all(|frame| {
            frame
                .units
                .iter()
                .all(|unit| unit.player_number() == PlayerNumber::Player1)
        }));
        let id = UnitId::parse("1").fixture()?;
        assert!(observed.events.iter().all(|event| event.unit_id == id));

        Ok(())
    }

    #[test]
    fn fuel_is_vehicle_only_and_successful_tiles_consume_it_once() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        assert!(vehicle(&mut scenario, "1")?.fuel().is_none());
        assert!(vehicle(&mut scenario, "12")?.fuel().is_none());
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 128);
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 6), (3, 6)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 128);
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, vec![])
            .fixture()?;
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 120);
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 128);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 120);

        Ok(())
    }

    #[test]
    fn fuel_rejection_is_atomic_and_empty_vehicles_can_hold() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .depots
            .retain(|depot| depot.kind == DepotKind::Supply);
        for _ in 0..16 {
            vehicle(&mut scenario, "4")?.follow_path(&[
                Coordinate::new(2, 7),
                Coordinate::new(2, 6),
                Coordinate::new(2, 7),
            ]);
        }
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 6)])?;
        assert_eq!(
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, player1),
            Err("movement exceeds the unit's available fuel.")
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 0);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 0);
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 8));
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 0);

        Ok(())
    }

    #[test]
    fn tank_paths_must_fit_remaining_fuel_even_with_movement_points_left() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        for _ in 0..7 {
            vehicle(&mut scenario, "11")?.follow_path(&[
                Coordinate::new(4, 8),
                Coordinate::new(5, 8),
                Coordinate::new(4, 8),
            ]);
        }
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 16);
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "11", &[(4, 8), (5, 8), (6, 8), (7, 8)])?;
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, player1)
                .err()
                .fixture()?,
            "movement exceeds the unit's available fuel."
        );
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "11", &[(4, 8), (5, 8), (6, 8)])?;
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 0);
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "11")
                        .fixture()?
                )
                .fixture()?,
            Coordinate::new(6, 8)
        );

        Ok(())
    }

    #[test]
    fn arriving_and_holding_near_fuel_depots_refills_after_movement() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut fuel_depot = scenario.depots.first().fixture()?.clone();
        fuel_depot.kind = DepotKind::Fuel;
        fuel_depot.position = Coordinate::new(1, 8);
        scenario.depots.push(fuel_depot);
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 8)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 128);
        assert_eq!(
            scenario
                .depots
                .iter()
                .find(|depot| depot.kind == DepotKind::Fuel
                    && depot.position == Coordinate::new(1, 8))
                .fixture()?
                .stock
                .current,
            1020
        );
        vehicle(&mut scenario, "4")?.set_fuel_for_test(0);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 128);
        assert_eq!(
            scenario
                .depots
                .iter()
                .find(|depot| depot.kind == DepotKind::Fuel
                    && depot.position == Coordinate::new(1, 8))
                .fixture()?
                .stock
                .current,
            892
        );
        Ok(())
    }

    #[test]
    fn supply_depots_do_not_replenish_fuel_after_arrival_or_holding() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .depots
            .retain(|depot| depot.kind == DepotKind::Supply);
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 8)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 124);
        vehicle(&mut scenario, "4")?.follow_path(&[Coordinate::new(2, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5")?.follow_path(&[Coordinate::new(2, 9), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "9")?.follow_path(&[Coordinate::new(14, 7), Coordinate::new(2, 8)]);
        // Holding on the center or either starting depot preserves spent fuel.
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 120);
        assert_eq!(vehicle(&mut scenario, "5")?.fuel().fixture()?.current, 124);
        assert_eq!(vehicle(&mut scenario, "9")?.fuel().fixture()?.current, 124);
        vehicle(&mut scenario, "9")?.follow_path(&[Coordinate::new(2, 8), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "4")?.follow_path(&[Coordinate::new(14, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5")?.follow_path(&[Coordinate::new(8, 8), Coordinate::new(8, 7)]);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 116);
        assert_eq!(vehicle(&mut scenario, "9")?.fuel().fixture()?.current, 120);
        assert_eq!(vehicle(&mut scenario, "5")?.fuel().fixture()?.current, 120);

        Ok(())
    }

    #[test]
    fn vehicle_encounters_charge_only_successful_tiles() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(4, 6));
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        let mut player2 = holds(&scenario, PlayerNumber::Player2)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 6), (3, 6)])?;
        set_path(&mut player2, "9", &[(4, 6), (3, 6)])?;
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        for (id, position) in [("4", Coordinate::new(2, 6)), ("9", Coordinate::new(3, 6))] {
            let unit = vehicle(&mut scenario, id)?;
            assert_eq!(unit.board_position(), Some(position));
            assert_eq!(unit.fuel().fixture()?.current, 124);
            assert_eq!(unit.supplies().current(), 124);
        }

        Ok(())
    }

    #[test]
    fn locks_orders_resolves_once_and_rejects_stale_turns() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "1", &[(3, 7), (3, 6)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        assert_eq!(turns.number, 1);
        assert_eq!(
            scenario.units[0].board_position().fixture()?,
            Coordinate::new(3, 7)
        );
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, vec![])
            .fixture()?;
        assert!(turns.orders[1].is_none());
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(turns.number, 2);
        assert_eq!(
            scenario.units[0].board_position().fixture()?,
            Coordinate::new(3, 6)
        );
        assert_eq!(scenario.units[0].direction(), Some(Direction::North));
        assert_eq!(scenario.units[1].direction(), Some(Direction::East));
        assert!(turns.orders.iter().all(Option::is_none));
        let resolution = turns.last_resolution.as_ref().fixture()?;
        assert_eq!(resolution.events.len(), 16);
        assert_eq!(resolution.events[0].kind, TurnEventKind::Move);
        assert_eq!(
            resolution.events[0].initial_direction,
            Some(Direction::East)
        );
        assert_eq!(resolution.turn_number, 1);
        assert!(
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, vec![])
                .is_err()
        );

        Ok(())
    }

    #[test]
    fn rejects_missing_duplicate_foreign_illegal_and_over_budget_orders_atomically()
    -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        for path in [
            vec![],
            vec![(0, 0)],
            vec![(3, 7), (-1, 7)],
            vec![(3, 7), (17, 7)],
            vec![(3, 7), (5, 7)],
            vec![(3, 7), (4, 7)],
            vec![(3, 7), (3, 6), (3, 5), (3, 4)],
            vec![(3, 7), (3, 6), (3, 7)],
        ] {
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "1", &path)?;
            let mut turns = Turns::default();
            assert!(
                turns
                    .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                    .is_err()
            );
            assert!(turns.orders[0].is_none());
        }
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders.pop();
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[1].unit_id = "1".into();
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].unit_id = "6".into();
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());

        Ok(())
    }

    fn departure_fixture() -> TestResult<Scenario> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.map = Map::from_ascii(".....\n.....\n.....").fixture()?;
        scenario
            .units
            .retain(|unit| ["1", "2", "3", "4"].contains(&unit.id().as_str()));
        for (id, x) in [("1", 1), ("2", 2), ("3", 3), ("4", 4)] {
            vehicle(&mut scenario, id)?.move_to(Coordinate::new(x, 1));
        }
        Ok(scenario)
    }

    #[test]
    fn moving_truck_boards_two_arriving_units_independent_of_order() -> TestResult<()> {
        for reverse in [false, true] {
            let mut scenario = departure_fixture()?;
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "4", &[(4, 1), (4, 0), (3, 0), (2, 0)])?;
            set_path(&mut orders, "1", &[(1, 1), (1, 0), (2, 0)])?;
            set_path(&mut orders, "2", &[(2, 1), (2, 0)])?;
            if reverse {
                orders.reverse();
            }
            let mut turns = Turns::default();
            resolve_orders(&mut scenario, &mut turns, orders)?;
            let truck = UnitId::parse("4").fixture()?;
            for id in ["1", "2"] {
                assert_eq!(vehicle(&mut scenario, id)?.carrier_id(), Some(truck));
            }
            assert_eq!(
                vehicle(&mut scenario, "4")?.board_position(),
                Some(Coordinate::new(2, 0))
            );
            assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 116);
            assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 164);
            assert_eq!(vehicle(&mut scenario, "2")?.supplies().current(), 176);
            assert_eq!(
                turns
                    .last_resolution
                    .as_ref()
                    .fixture()?
                    .events
                    .iter()
                    .filter(|event| event.kind == TurnEventKind::Load)
                    .count(),
                2
            );
        }
        Ok(())
    }

    #[test]
    fn moving_truck_picks_up_waiting_and_arriving_passengers() -> TestResult<()> {
        let mut scenario = departure_fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "4", &[(4, 1), (4, 0), (3, 0), (2, 0), (2, 1)])?;
        set_path(&mut orders, "1", &[(1, 1), (2, 1)])?;
        let mut turns = Turns::default();
        resolve_orders(&mut scenario, &mut turns, orders)?;
        for id in ["1", "2"] {
            assert_eq!(vehicle(&mut scenario, id)?.carrier_id(), UnitId::parse("4"));
        }
        Ok(())
    }

    #[test]
    fn rendezvous_reserves_existing_cargo_and_rejects_attack_moves() -> TestResult<()> {
        #[derive(Debug)]
        enum Conflict {
            ExistingPassenger,
            ExistingFreight,
            UnloadingFreight,
            AttackMove,
            ThirdPassenger,
        }
        for conflict in [
            Conflict::ExistingPassenger,
            Conflict::ExistingFreight,
            Conflict::UnloadingFreight,
            Conflict::AttackMove,
            Conflict::ThirdPassenger,
        ] {
            let mut scenario = departure_fixture()?;
            match conflict {
                Conflict::ExistingPassenger => {
                    vehicle(&mut scenario, "3")?.board(UnitId::parse("4").fixture()?);
                }
                Conflict::ExistingFreight | Conflict::UnloadingFreight => {
                    vehicle(&mut scenario, "4")?
                        .supply_cargo
                        .push(supplies::CargoStock::new(DepotKind::Supply, 64));
                }
                Conflict::AttackMove | Conflict::ThirdPassenger => {}
            }
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "4", &[(4, 1), (4, 0), (3, 0), (2, 0)])?;
            set_path(&mut orders, "1", &[(1, 1), (1, 0), (2, 0)])?;
            set_path(&mut orders, "2", &[(2, 1), (2, 0)])?;
            match conflict {
                Conflict::UnloadingFreight => {
                    orders
                        .iter_mut()
                        .find(|order| order.unit_id == "4")
                        .fixture()?
                        .crate_unloads = Some(vec![CrateUnloadInput {
                        cargo_index: 0,
                        destination: CoordinateInput { x: 2, y: 1 },
                    }]);
                }
                Conflict::AttackMove => {
                    orders
                        .iter_mut()
                        .find(|order| order.unit_id == "1")
                        .fixture()?
                        .attack_move = Some(true);
                }
                Conflict::ThirdPassenger => {
                    set_path(&mut orders, "3", &[(3, 1), (3, 0), (2, 0)])?;
                }
                Conflict::ExistingPassenger | Conflict::ExistingFreight => {}
            }
            assert!(
                validate(&scenario, PlayerNumber::Player1, orders).is_err(),
                "{conflict:?} must prevent boarding"
            );
        }
        Ok(())
    }

    #[test]
    fn blocked_rendezvous_keeps_passengers_separate_and_does_not_load() -> TestResult<()> {
        for truck_blocked in [false, true] {
            let mut scenario = departure_fixture()?;
            let mut enemy = Scenario::supply_point()
                .fixture()?
                .units
                .into_iter()
                .find(|unit| unit.player_number() == PlayerNumber::Player2)
                .fixture()?;
            enemy.move_to(if truck_blocked {
                Coordinate::new(4, 0)
            } else {
                Coordinate::new(1, 0)
            });
            scenario.units.push(enemy);
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut orders, "4", &[(4, 1), (4, 0), (3, 0), (2, 0)])?;
            set_path(&mut orders, "1", &[(1, 1), (1, 0), (2, 0)])?;
            set_path(&mut orders, "2", &[(2, 1), (2, 0)])?;
            let mut turns = Turns::default();
            resolve_orders(&mut scenario, &mut turns, orders)?;
            let mut occupied = BTreeSet::new();
            for unit in scenario.units.iter().filter(|unit| unit.is_alive()) {
                if let Some(position) = unit.board_position() {
                    assert!(occupied.insert(position));
                }
                let expected_carrier = if !truck_blocked && unit.id() == "2" {
                    UnitId::parse("4")
                } else {
                    None
                };
                assert_eq!(unit.carrier_id(), expected_carrier);
            }
            let expected_position = if truck_blocked {
                Coordinate::new(4, 1)
            } else {
                Coordinate::new(2, 0)
            };
            assert_eq!(
                vehicle(&mut scenario, "4")?.board_position(),
                Some(expected_position)
            );
            let loads = turns
                .last_resolution
                .as_ref()
                .fixture()?
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::Load)
                .count();
            assert_eq!(loads, if truck_blocked { 0 } else { 1 });
        }
        Ok(())
    }

    #[test]
    fn allied_departures_allow_chains_and_swaps_in_either_order() -> TestResult<()> {
        for reverse in [false, true] {
            for swap in [false, true] {
                let mut scenario = departure_fixture()?;
                let mut turns = Turns::default();
                let mut orders = holds(&scenario, PlayerNumber::Player1)?;
                set_path(&mut orders, "1", &[(1, 1), (2, 1)])?;
                if swap {
                    set_path(&mut orders, "2", &[(2, 1), (1, 1)])?;
                } else {
                    set_path(&mut orders, "2", &[(2, 1), (3, 1)])?;
                    set_path(&mut orders, "3", &[(3, 1), (3, 0)])?;
                }
                if reverse {
                    orders.reverse();
                }
                resolve_orders(&mut scenario, &mut turns, orders)?;
                assert_eq!(
                    vehicle(&mut scenario, "1")?.board_position(),
                    Some(Coordinate::new(2, 1))
                );
                let second = if swap {
                    Coordinate::new(1, 1)
                } else {
                    Coordinate::new(3, 1)
                };
                assert_eq!(vehicle(&mut scenario, "2")?.board_position(), Some(second));
                let occupied: BTreeSet<_> = scenario
                    .units
                    .iter()
                    .filter_map(Unit::board_position)
                    .collect();
                assert_eq!(occupied.len(), scenario.units.len());
            }
        }
        Ok(())
    }

    #[test]
    fn entering_a_departing_trucks_square_does_not_load_or_share_destinations() -> TestResult<()> {
        let mut scenario = departure_fixture()?;
        let mut turns = Turns::default();
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "3", &[(3, 1), (4, 1)])?;
        set_path(&mut orders, "4", &[(4, 1), (4, 0)])?;
        resolve_orders(&mut scenario, &mut turns, orders)?;
        assert_eq!(
            vehicle(&mut scenario, "3")?.board_position(),
            Some(Coordinate::new(4, 1))
        );
        assert_eq!(vehicle(&mut scenario, "3")?.carrier_id(), None);
        assert!(
            !turns
                .last_resolution
                .as_ref()
                .fixture()?
                .events
                .iter()
                .any(|event| event.kind == TurnEventKind::Load)
        );

        let mut scenario = departure_fixture()?;
        let mut turns = Turns::default();
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "3", &[(3, 1), (3, 0)])?;
        set_path(&mut orders, "4", &[(4, 1), (3, 1)])?;
        resolve_orders(&mut scenario, &mut turns, orders)?;
        assert_eq!(
            vehicle(&mut scenario, "3")?.board_position(),
            Some(Coordinate::new(3, 0))
        );
        assert_eq!(
            vehicle(&mut scenario, "4")?.board_position(),
            Some(Coordinate::new(3, 1))
        );
        assert!(
            !turns
                .last_resolution
                .as_ref()
                .fixture()?
                .events
                .iter()
                .any(|event| event.kind == TurnEventKind::Load)
        );

        let scenario = departure_fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "2", &[(2, 1), (3, 1), (4, 1)])?;
        set_path(&mut orders, "3", &[(3, 1), (4, 1)])?;
        set_path(&mut orders, "4", &[(4, 1), (4, 0)])?;
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, orders)
                .err()
                .fixture()?,
            "units must have different destinations."
        );
        Ok(())
    }

    #[test]
    fn blocked_allied_departure_keeps_the_follower_on_a_free_square() -> TestResult<()> {
        let mut scenario = departure_fixture()?;
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.id() == "6")
            .fixture()?;
        enemy.move_to(Coordinate::new(2, 0));
        scenario.units.push(enemy);
        let mut turns = Turns::default();
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "1", &[(1, 1), (2, 1)])?;
        set_path(&mut orders, "2", &[(2, 1), (2, 0), (3, 0)])?;
        resolve_orders(&mut scenario, &mut turns, orders)?;
        assert_eq!(
            vehicle(&mut scenario, "1")?.board_position(),
            Some(Coordinate::new(1, 1))
        );
        assert_eq!(
            vehicle(&mut scenario, "2")?.board_position(),
            Some(Coordinate::new(2, 1))
        );
        let occupied: BTreeSet<_> = scenario
            .units
            .iter()
            .filter_map(Unit::board_position)
            .collect();
        assert_eq!(occupied.len(), scenario.units.len());
        Ok(())
    }

    #[test]
    fn allies_allow_passage_but_known_occupied_destinations_do_not() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_ok());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "1", &[(3, 7), (3, 6)])?;
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .fixture()?
            .move_to(Coordinate::new(3, 6));
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut orders, "1", &[(3, 7), (3, 6)])?;
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, orders)
                .err()
                .fixture()?,
            "occupied squares cannot be destinations."
        );

        Ok(())
    }

    #[test]
    fn direct_unloads_participate_in_timed_encounters() -> TestResult<()> {
        for both_aboard in [true, false] {
            for unloading_player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
                for first_player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
                    let mut scenario = Scenario::supply_point().fixture()?;
                    scenario.map = crate::map::Map::new(
                        17,
                        17,
                        crate::map::Terrain::GrassPlain,
                        BTreeMap::new(),
                    )
                    .fixture()?;
                    scenario
                        .units
                        .retain(|unit| ["1", "4", "6", "9"].contains(&unit.id().as_str()));
                    vehicle(&mut scenario, "4")?.move_to(Coordinate::new(5, 5));
                    vehicle(&mut scenario, "9")?.move_to(Coordinate::new(7, 5));
                    for (passenger, truck, origin, player_number) in [
                        ("1", "4", Coordinate::new(5, 6), PlayerNumber::Player1),
                        ("6", "9", Coordinate::new(7, 6), PlayerNumber::Player2),
                    ] {
                        let unit = vehicle(&mut scenario, passenger)?;
                        if both_aboard || player_number == unloading_player_number {
                            unit.board(UnitId::parse(truck).fixture()?);
                        } else {
                            unit.move_to(origin);
                        }
                    }
                    let initial = scenario.clone();
                    let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
                    let mut player2 = holds(&scenario, PlayerNumber::Player2)?;
                    set_path(&mut player1, "1", &[(5, 5), (6, 5)])?;
                    set_path(&mut player2, "6", &[(7, 5), (6, 5)])?;
                    if !both_aboard {
                        if unloading_player_number == PlayerNumber::Player1 {
                            set_path(&mut player2, "6", &[(7, 6), (6, 6), (6, 5)])?;
                        } else {
                            set_path(&mut player1, "1", &[(5, 6), (6, 6), (6, 5)])?;
                        }
                    }
                    let submissions = if first_player_number == PlayerNumber::Player1 {
                        [
                            (PlayerNumber::Player1, player1),
                            (PlayerNumber::Player2, player2),
                        ]
                    } else {
                        [
                            (PlayerNumber::Player2, player2),
                            (PlayerNumber::Player1, player1),
                        ]
                    };
                    let mut turns = Turns::default();
                    for (player_number, orders) in submissions {
                        turns
                            .submit(&mut scenario, player_number, 1, orders)
                            .fixture()?;
                    }
                    assert_eq!(turns.number, 2);
                    let events = &turns.last_resolution.as_ref().fixture()?.events;
                    assert_eq!(events.len(), 4);
                    let winner = if both_aboard {
                        PlayerNumber::Player1
                    } else {
                        unloading_player_number
                    };
                    for (unit, original) in scenario.units.iter().zip(&initial.units) {
                        let event = events
                            .iter()
                            .find(|event| event.unit_id == unit.unit_id())
                            .fixture()?;
                        assert_eq!(event.initial_carrier, original.carrier_id());
                        assert_eq!(unit.fuel(), original.fuel());
                        let traveled = event.path.len() - 1;
                        assert_eq!(
                            unit.supplies().current(),
                            original.supplies().current()
                                - 4
                                - traveled as i32 * unit.supplies().movement_per_tile()
                        );
                        if ["1", "6"].contains(&unit.id().as_str()) {
                            assert_eq!(event.kind, TurnEventKind::MovementStopped);
                            if unit.player_number() == winner {
                                assert_eq!(unit.board_position(), Some(Coordinate::new(6, 5)));
                            } else if original.carrier_id().is_some() {
                                assert_eq!(unit.carrier_id(), original.carrier_id());
                            } else {
                                assert_eq!(unit.board_position(), Some(Coordinate::new(6, 6)));
                            }
                        } else {
                            assert_eq!(unit.board_position(), original.board_position());
                            assert_eq!(event.kind, TurnEventKind::Hold);
                        }
                    }
                    let occupied: BTreeSet<_> = scenario
                        .units
                        .iter()
                        .filter_map(|unit| unit.board_position())
                        .collect();
                    assert_eq!(
                        occupied.len(),
                        scenario
                            .units
                            .iter()
                            .filter(|unit| unit.board_position().is_some())
                            .count()
                    );
                    assert!(occupied.contains(&Coordinate::new(6, 5)));
                }
            }
        }

        Ok(())
    }

    #[test]
    fn earlier_arrival_blocks_later_opposing_arrival() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .fixture()?
            .move_to(Coordinate::new(5, 6));
        let initial = scenario.clone();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        let mut player2 = holds(&scenario, PlayerNumber::Player2)?;
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)])?;
        set_path(&mut player2, "6", &[(5, 6), (4, 6)])?;
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        assert_eq!(
            turns
                .last_resolution
                .fixture()?
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::MovementStopped)
                .count(),
            2
        );
        for (unit, original) in scenario.units.iter().zip(&initial.units) {
            let (position, supplies) = match unit.id().as_str() {
                "1" => (Coordinate::new(3, 6), 176),
                "6" => (Coordinate::new(4, 6), 176),
                _ => (
                    original.board_position().fixture()?,
                    original.supplies().current() - 4,
                ),
            };
            assert_eq!(unit.board_position(), Some(position));
            assert_eq!(unit.fuel(), original.fuel());
            assert_eq!(unit.supplies().current(), supplies);
        }

        Ok(())
    }
    #[test]
    fn failed_resolution_preserves_board_and_pending_submission() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut turns = Turns::default();
        let first = holds(&scenario, PlayerNumber::Player1)?;
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        // Simulate inconsistent stored orders to exercise a resolution error,
        // rather than a draft validation failure.
        let first_orders = turns.orders[0].as_mut().fixture()?;
        first_orders.first_mut().fixture()?.path.clear();
        let pending_ids: Vec<_> = first_orders.iter().map(|order| order.unit_id).collect();
        let before = scenario.clone();
        let second = holds(&scenario, PlayerNumber::Player2)?;
        assert_eq!(
            turns.submit(&mut scenario, PlayerNumber::Player2, 1, second),
            Err("movement requires a starting position.")
        );
        assert_eq!(scenario, before);
        assert_eq!(turns.number, 1);
        assert!(turns.last_resolution.is_none());
        assert!(turns.orders[1].is_none());
        let retained = turns.orders[0].as_ref().fixture()?;
        assert_eq!(
            retained
                .iter()
                .map(|order| order.unit_id)
                .collect::<Vec<_>>(),
            pending_ids
        );
        assert!(retained.first().fixture()?.path.is_empty());
        Ok(())
    }
    #[test]
    fn truck_explicitly_loads_moves_and_unloads_a_finite_supply_crate() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .units
            .retain(|unit| unit.id() == "4" || unit.player_number() == PlayerNumber::Player2);
        let mut turns = Turns::default();
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 8));
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .load_crates = Some(1);
        let second = holds(&scenario, PlayerNumber::Player2)?;
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        assert_eq!(vehicle(&mut scenario, "4")?.supply_cargo.len(), 1);
        assert_eq!(
            vehicle(&mut scenario, "4")?
                .supply_cargo
                .first()
                .fixture()?
                .current,
            256
        );
        assert_eq!(scenario.depots.first().fixture()?.stock.current, 768);
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut first, "4", &[(2, 8), (3, 8)])?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .crate_unloads = Some(vec![CrateUnloadInput {
            cargo_index: 0,
            destination: CoordinateInput { x: 4, y: 8 },
        }]);
        let second = holds(&scenario, PlayerNumber::Player2)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 2, second)?;
        turns.submit(&mut scenario, PlayerNumber::Player1, 2, first)?;
        assert!(vehicle(&mut scenario, "4")?.supply_cargo.is_empty());
        let supply_crate = scenario.supply_crates.first().fixture()?;
        assert_eq!(supply_crate.position, Coordinate::new(4, 8));
        assert_eq!(supply_crate.stock.current, 256);
        let frames = &turns.last_resolution.as_ref().fixture()?.frames;
        assert!(frames.first().fixture()?.supply_crates.is_empty());
        assert_eq!(
            frames.last().fixture()?.supply_crates,
            scenario.supply_crates
        );
        Ok(())
    }

    #[test]
    fn crate_unloads_share_allied_stationary_arriving_and_passenger_destinations() -> TestResult<()>
    {
        for passenger in [false, true] {
            for arriving in [false, true] {
                for reverse in [false, true] {
                    let mut scenario = Scenario::supply_point().fixture()?;
                    scenario
                        .units
                        .retain(|unit| unit.id() == "1" || unit.id() == "4");
                    vehicle(&mut scenario, "4")?.move_to(Coordinate::new(1, 1));
                    vehicle(&mut scenario, "4")?
                        .supply_cargo
                        .push(supplies::CargoStock::new(DepotKind::Supply, 64));
                    if passenger {
                        vehicle(&mut scenario, "1")?.board(UnitId::parse("4").fixture()?);
                    } else {
                        vehicle(&mut scenario, "1")?
                            .move_to(Coordinate::new(if arriving { 3 } else { 2 }, 1));
                    }
                    let mut own = holds(&scenario, PlayerNumber::Player1)?;
                    if arriving && !passenger {
                        set_path(&mut own, "1", &[(3, 1), (2, 1)])?;
                    }
                    let truck = own
                        .iter_mut()
                        .find(|order| order.unit_id == "4")
                        .fixture()?;
                    truck.crate_unloads = Some(vec![CrateUnloadInput {
                        cargo_index: 0,
                        destination: CoordinateInput { x: 2, y: 1 },
                    }]);
                    if passenger {
                        truck.unloads = Some(vec![UnloadOrderInput {
                            unit_id: "1".into(),
                            destination: CoordinateInput { x: 2, y: 1 },
                        }]);
                    }
                    if reverse {
                        own.reverse();
                    }
                    let mut turns = Turns::default();
                    turns.submit(&mut scenario, PlayerNumber::Player1, 1, own)?;
                    turns.submit(&mut scenario, PlayerNumber::Player2, 1, Vec::new())?;
                    assert!(vehicle(&mut scenario, "4")?.supply_cargo.is_empty());
                    assert_eq!(
                        vehicle(&mut scenario, "1")?.board_position(),
                        Some(Coordinate::new(2, 1))
                    );
                    assert_eq!(
                        scenario.supply_crates.first().fixture()?.position,
                        Coordinate::new(2, 1)
                    );
                }
            }
        }
        Ok(())
    }

    #[test]
    fn two_crates_cannot_unload_onto_the_same_square() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.units.retain(|unit| unit.id() == "4");
        let truck = vehicle(&mut scenario, "4")?;
        truck.move_to(Coordinate::new(1, 1));
        truck.supply_cargo = vec![supplies::CargoStock::new(DepotKind::Supply, 64); 2];
        let mut own = holds(&scenario, PlayerNumber::Player1)?;
        own.first_mut().fixture()?.crate_unloads = Some(vec![
            CrateUnloadInput {
                cargo_index: 0,
                destination: CoordinateInput { x: 2, y: 1 },
            },
            CrateUnloadInput {
                cargo_index: 1,
                destination: CoordinateInput { x: 2, y: 1 },
            },
        ]);
        assert!(validate(&scenario, PlayerNumber::Player1, own).is_err());
        Ok(())
    }

    #[test]
    fn truck_moves_onto_ground_crate_and_collects_it_during_resolution() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario
            .units
            .retain(|unit| unit.id() == "4" || unit.player_number() == PlayerNumber::Player2);
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(3, 8));
        scenario.supply_crates.push(GroundSupplyCrate {
            position: Coordinate::new(4, 8),
            stock: supplies::CargoStock::new(DepotKind::Supply, 23),
        });
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut first, "4", &[(3, 8), (4, 8)])?;
        let second = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        assert!(scenario.supply_crates.is_empty());
        let truck = vehicle(&mut scenario, "4")?;
        assert_eq!(truck.board_position(), Some(Coordinate::new(4, 8)));
        assert_eq!(truck.supply_cargo.first().fixture()?.current, 23);
        Ok(())
    }

    #[test]
    fn fuel_depots_allow_fuel_drum_loading() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut fuel_depot = scenario.depots.first().fixture()?.clone();
        fuel_depot.kind = DepotKind::Fuel;
        fuel_depot.position = Coordinate::new(1, 8);
        scenario.depots.push(fuel_depot);
        let position = scenario
            .depots
            .iter()
            .find(|depot| depot.kind == DepotKind::Fuel)
            .fixture()?
            .position;
        vehicle(&mut scenario, "4")?.move_to(position);
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .load_crates = Some(1);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_ok());
        Ok(())
    }

    #[test]
    fn adjacent_depot_loading_is_rejected() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 7));
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .load_crates = Some(1);
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, first).err(),
            Some("loading cargo requires a stocked depot at the destination.")
        );
        Ok(())
    }

    #[test]
    fn supply_orders_reject_invalid_counts_slots_and_shared_berth_overflow() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 8));
        for count in [-1, 3] {
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            first
                .iter_mut()
                .find(|order| order.unit_id == "4")
                .fixture()?
                .load_crates = Some(count);
            assert!(validate(&scenario, PlayerNumber::Player1, first).is_err());
        }
        let truck_id = UnitId::parse("4").fixture()?;
        vehicle(&mut scenario, "1")?.board(truck_id);
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .load_crates = Some(2);
        assert!(validate(&scenario, PlayerNumber::Player1, first).is_err());
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .crate_unloads = Some(vec![CrateUnloadInput {
            cargo_index: 0,
            destination: CoordinateInput { x: 2, y: 9 },
        }]);
        assert!(validate(&scenario, PlayerNumber::Player1, first).is_err());
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first
            .iter_mut()
            .find(|order| order.unit_id == "2")
            .fixture()?
            .load_crates = Some(1);
        assert_eq!(
            validate(&scenario, PlayerNumber::Player1, first).err(),
            Some("only on-map trucks can handle freight.")
        );
        Ok(())
    }

    #[test]
    fn concealed_enemy_can_block_crate_unload_without_rejecting_submission() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        scenario.depots.clear();
        scenario.map = Map::from_ascii(".....\n..#..\n.....").fixture()?;
        scenario
            .units
            .retain(|unit| unit.id() == "4" || unit.id() == "9");
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 0));
        vehicle(&mut scenario, "4")?
            .supply_cargo
            .push(supplies::CargoStock::new(DepotKind::Supply, 64));
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(2, 1));
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.crate_unloads = Some(vec![CrateUnloadInput {
            cargo_index: 0,
            destination: CoordinateInput { x: 2, y: 1 },
        }]);
        let second = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        assert!(scenario.supply_crates.is_empty());
        assert_eq!(
            vehicle(&mut scenario, "4")?
                .supply_cargo
                .first()
                .fixture()?
                .current,
            64
        );
        Ok(())
    }

    fn bombardment_fixture() -> TestResult<Scenario> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let gun = scenario
            .units
            .iter()
            .find(|unit| {
                unit.player_number() == PlayerNumber::Player1 && unit.kind() == UnitKind::FieldGun
            })
            .cloned()
            .fixture()?;
        let target = scenario
            .units
            .iter()
            .find(|unit| {
                unit.player_number() == PlayerNumber::Player2 && unit.kind() == UnitKind::Infantry
            })
            .cloned()
            .fixture()?;
        scenario.units = vec![gun, target];
        scenario.map = Map::new(20, 3, Terrain::GrassPlain, BTreeMap::new()).fixture()?;
        scenario.depots.clear();
        scenario.supply_crates.clear();
        scenario
            .units
            .first_mut()
            .fixture()?
            .move_to(Coordinate::new(1, 1));
        scenario
            .units
            .last_mut()
            .fixture()?
            .move_to(Coordinate::new(9, 1));
        Ok(scenario)
    }

    #[test]
    fn indirect_fire_resolves_final_occupancy_and_spends_on_misses() -> TestResult<()> {
        for (aim_x, moves, hits) in [
            (9, false, true),
            (8, false, false),
            (9, true, false),
            (8, true, true),
        ] {
            let mut scenario = bombardment_fixture()?;
            let initial = scenario.units.first().fixture()?.supplies();
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: aim_x, y: 1 });
            let mut second = holds(&scenario, PlayerNumber::Player2)?;
            if moves {
                second
                    .first_mut()
                    .fixture()?
                    .path
                    .push(CoordinateInput { x: 8, y: 1 });
            }
            let mut turns = Turns::default();
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
            turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
            let resolution = turns.last_resolution.as_ref().fixture()?;
            let shots: Vec<_> = resolution
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .collect();
            assert_eq!(shots.len(), usize::from(hits));
            if hits {
                assert_eq!(shots.first().fixture()?.kind, CombatKind::IndirectFire);
            }
            assert_eq!(
                scenario.units.first().fixture()?.supplies().current(),
                initial.current() - initial.upkeep_per_turn() - 8 - 12
            );
        }
        Ok(())
    }

    #[test]
    fn indirect_fire_hidden_hits_stay_unconfirmed_for_shooter() -> TestResult<()> {
        let mut scenario = bombardment_fixture()?;
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 9, y: 1 });
        let second = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        let resolution = turns.last_resolution.as_ref().fixture()?;
        for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let visible = visibility::visible_tiles(&scenario, player);
            let projected =
                visibility::observed_resolution(&scenario, player, &visible, resolution);
            let shots: Vec<_> = projected
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .collect();
            if player == PlayerNumber::Player1 {
                assert!(shots.is_empty());
                assert!(projected.frames.iter().all(|frame| {
                    frame
                        .units
                        .iter()
                        .all(|unit| unit.player_number() == player)
                }));
                let report = projected.reports.first().fixture()?;
                assert_eq!(report.damage_inflicted, 0);
                assert_eq!(report.enemy_units_destroyed, 0);
            } else {
                assert_eq!(shots.len(), 1);
            }
        }
        Ok(())
    }

    #[test]
    fn indirect_fire_validation_checks_kind_bounds_range_and_exclusive_action() -> TestResult<()> {
        let scenario = bombardment_fixture()?;
        for target in [
            CoordinateInput { x: -1, y: 1 },
            CoordinateInput { x: 20, y: 1 },
            CoordinateInput { x: 14, y: 1 },
        ] {
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            first.first_mut().fixture()?.indirect_fire = Some(target);
            assert!(validate(&scenario, PlayerNumber::Player1, first).is_err());
        }
        let mut second = holds(&scenario, PlayerNumber::Player2)?;
        second.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 1, y: 1 });
        assert!(validate(&scenario, PlayerNumber::Player2, second).is_err());
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 13, y: 1 });
        assert!(validate(&scenario, PlayerNumber::Player1, first).is_ok());
        for action in 0..4 {
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            let order = first.first_mut().fixture()?;
            order.indirect_fire = Some(CoordinateInput { x: 9, y: 1 });
            match action {
                0 => order.path.push(CoordinateInput { x: 2, y: 1 }),
                1 => order.stand_ground = Some(true),
                2 => order.direction = Some(Direction::East),
                _ => order.load_crates = Some(1),
            }
            assert!(validate(&scenario, PlayerNumber::Player1, first).is_err());
        }
        let mut depleted = scenario.clone();
        depleted.units.first_mut().fixture()?.spend_supplies(240);
        let mut first = holds(&depleted, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 9, y: 1 });
        assert!(validate(&depleted, PlayerNumber::Player1, first).is_err());
        Ok(())
    }

    #[test]
    fn indirect_fire_can_hit_friendly_units() -> TestResult<()> {
        let mut scenario = bombardment_fixture()?;
        let mut friendly = scenario.units.first().cloned().fixture()?;
        // Target the firing gun itself: an allied occupied tile is still legal.
        friendly.rotate(Direction::West);
        *scenario.units.first_mut().fixture()? = friendly;
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 1, y: 1 });
        let second = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        let shot = turns
            .last_resolution
            .as_ref()
            .fixture()?
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .next()
            .fixture()?;
        assert_eq!(shot.attacker.unit_id(), shot.target.unit_id());
        assert!(shot.damage > 0);
        Ok(())
    }

    #[test]
    fn indirect_fire_hidden_hit_and_miss_have_identical_projected_timing() -> TestResult<()> {
        let mut timelines = Vec::new();
        for x in [8, 9] {
            let mut scenario = bombardment_fixture()?;
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x, y: 1 });
            let second = holds(&scenario, PlayerNumber::Player2)?;
            let mut turns = Turns::default();
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
            turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
            let visible = visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            let projected = visibility::observed_resolution(
                &scenario,
                PlayerNumber::Player1,
                &visible,
                turns.last_resolution.as_ref().fixture()?,
            );
            assert_eq!(
                projected
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.indirect_impacts)
                    .count(),
                1
            );
            assert!(projected.frames.iter().all(|frame| frame.shots.is_empty()));
            timelines.push(
                projected
                    .frames
                    .iter()
                    .map(|frame| frame.duration_ms)
                    .collect::<Vec<_>>(),
            );
        }
        assert_eq!(timelines.first().fixture()?, timelines.last().fixture()?);
        Ok(())
    }

    #[test]
    fn indirect_fire_ignores_obstructions_and_gun_facing() -> TestResult<()> {
        let mut damages = Vec::new();
        for direction in [Direction::East, Direction::West] {
            let mut scenario = bombardment_fixture()?;
            scenario.map =
                Map::from_ascii("....................\n....###.............\n....................")
                    .fixture()?;
            scenario.units.first_mut().fixture()?.rotate(direction);
            let mut first = holds(&scenario, PlayerNumber::Player1)?;
            first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 9, y: 1 });
            let second = holds(&scenario, PlayerNumber::Player2)?;
            let mut turns = Turns::default();
            turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
            turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
            let shot = turns
                .last_resolution
                .as_ref()
                .fixture()?
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .next()
                .fixture()?;
            damages.push(shot.damage);
        }
        assert_eq!(damages.first().fixture()?, damages.last().fixture()?);
        Ok(())
    }

    #[test]
    fn indirect_fire_surviving_guns_fire_simultaneously() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut selected = Vec::new();
        for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
            selected.push(
                scenario
                    .units
                    .iter()
                    .find(|unit| {
                        unit.kind() == UnitKind::FieldGun && unit.player_number() == player
                    })
                    .cloned()
                    .fixture()?,
            );
        }
        scenario.units = selected;
        scenario.map = Map::new(20, 3, Terrain::GrassPlain, BTreeMap::new()).fixture()?;
        scenario.depots.clear();
        scenario
            .units
            .first_mut()
            .fixture()?
            .move_to(Coordinate::new(1, 1));
        scenario
            .units
            .last_mut()
            .fixture()?
            .move_to(Coordinate::new(9, 1));
        let mut first = holds(&scenario, PlayerNumber::Player1)?;
        first.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 9, y: 1 });
        let mut second = holds(&scenario, PlayerNumber::Player2)?;
        second.first_mut().fixture()?.indirect_fire = Some(CoordinateInput { x: 1, y: 1 });
        let mut turns = Turns::default();
        turns.submit(&mut scenario, PlayerNumber::Player1, 1, first)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, second)?;
        let shots: Vec<_> = turns
            .last_resolution
            .as_ref()
            .fixture()?
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .collect();
        assert_eq!(shots.len(), 2);
        assert!(
            shots
                .iter()
                .all(|shot| shot.attacker_health.before.current() == 16
                    && shot.target_health.after.current() == 0)
        );
        assert!(scenario.units.is_empty());
        Ok(())
    }
}
