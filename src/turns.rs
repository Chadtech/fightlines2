use crate::{
    map::Coordinate,
    movement,
    scenario::{Direction, PlayerNumber, Scenario, SpriteFacing, Unit, UnitId},
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
    /// Passenger destinations after this truck moves.
    unloads: Option<Vec<UnloadOrderInput>>,
}

#[derive(Clone, Debug)]
pub struct MoveOrder {
    pub facing: FacingOrder,
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
    pub unloads: Vec<UnloadOrder>,
}

/// Validated stationary facing action. An ambush always owns its direction.
#[derive(Clone, Copy, Debug)]
pub enum FacingOrder {
    Unchanged,
    Rotate(Direction),
    Ambush(Direction),
}

impl FacingOrder {
    pub fn direction(self) -> Option<Direction> {
        match self {
            Self::Unchanged => None,
            Self::Rotate(direction) | Self::Ambush(direction) => Some(direction),
        }
    }

    pub fn is_ambush(self) -> bool {
        match self {
            Self::Ambush(_) => true,
            Self::Unchanged | Self::Rotate(_) => false,
        }
    }
}

#[derive(GraphQLInputObject)]
pub struct UnloadOrderInput {
    unit_id: String,
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
    Rotate,
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
    pub shots: Vec<crate::combat::Shot>,
    /// Time from the preceding frame in milliseconds.
    pub duration_ms: i32,
    pub units: Vec<Unit>,
    pub visible_tiles: Vec<Coordinate>,
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct TurnResolution {
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

pub fn side_index(side: PlayerNumber) -> usize {
    match side {
        PlayerNumber::Player1 => 0,
        PlayerNumber::Player2 => 1,
    }
}

pub fn validate(
    scenario: &Scenario,
    side: PlayerNumber,
    inputs: Vec<MoveOrderInput>,
) -> Result<Vec<MoveOrder>, &'static str> {
    let visible = crate::visibility::visible_tiles(scenario, side);
    // Occupancy may reject a draft only when it is known to its owner. Resolution
    // still checks the complete board, including concealed enemies at unload exits.
    let planning_scenario = crate::visibility::observed_scenario(scenario, side, &visible);
    let own_count = scenario
        .units
        .iter()
        .filter(|unit| unit.side() == side)
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
    destination_scenario
        .units
        .retain(|unit| unit.side() != side || !departing.contains(&unit.unit_id()));
    let mut unit_ids = BTreeSet::new();
    let mut destinations = BTreeSet::new();
    let mut orders = Vec::new();
    for input in inputs {
        let unit_id = UnitId::parse(&input.unit_id).ok_or("invalid unit id.")?;
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == unit_id && unit.side() == side)
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
        let ambush = input.ambush == Some(true);
        if ambush {
            if input.direction.is_none() {
                return Err("ambush requires a facing direction.");
            }
            let required = unit.supplies().upkeep_per_turn()
                + crate::combat::rules(unit.kind()).readiness_cost;
            if unit.supplies().current() < required {
                return Err("not enough supplies to maintain ambush readiness.");
            }
        }
        if input.direction.is_some() {
            if unit.direction().is_none() || unit.carrier_id().is_some() {
                return Err("only units on the map with a facing can rotate or ambush.");
            }
            if path.len() != 1 || !input.unloads.as_ref().is_none_or(Vec::is_empty) {
                return Err("rotation and ambush must be in-place orders without unloading.");
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
                .find(|entry| entry.terrain == terrain)
                .ok_or("this terrain cannot be crossed.")?
                .cost;
        }
        if cost > rule.budget {
            return Err("movement exceeds the unit's budget.");
        }
        if let Some(fuel) = unit.fuel()
            && path.len() - 1 > fuel.current as usize
        {
            return Err("movement exceeds the unit's available fuel.");
        }
        if !unit.supplies().can_move(path.len() - 1) {
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
                        && (other.side() != side || !departing.contains(&other.unit_id()))
                })
            {
                return Err("unloading requires an empty square.");
            }
        } else if let Some(target) = planning_scenario.units.iter().find(|other| {
            other.unit_id() != unit.unit_id()
                && other.carrier_id().is_none()
                && other.board_position() == Some(destination)
        }) && (target.side() != side || !departing.contains(&target.unit_id()))
            && scenario.loading_pair(unit, target).is_none()
        {
            return Err("occupied squares cannot be destinations.");
        }
        // A stationary loading target may share its destination with the mover.
        // Validate those pairs together after all individual paths are checked.
        if path.len() > 1
            && !destinations.insert(destination)
            && !scenario.units.iter().any(|target| {
                target.board_position() == Some(destination)
                    && !departing.contains(&target.unit_id())
                    && scenario.loading_pair(unit, target).is_some()
            })
        {
            return Err("units must have different destinations.");
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
                        && passenger.side() == side
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
        orders.push(MoveOrder {
            facing: match (ambush, input.direction) {
                (true, Some(direction)) => FacingOrder::Ambush(direction),
                (false, Some(direction)) => FacingOrder::Rotate(direction),
                (false, None) => FacingOrder::Unchanged,
                (true, None) => return Err("ambush requires a facing direction."),
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
    let mut loading_passengers = BTreeSet::new();
    let mut loading_counts = BTreeMap::new();
    for order in orders.iter().filter(|order| order.path.len() > 1) {
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == order.unit_id)
            .ok_or("the order references a missing unit.")?;
        if let Some(carrier) = unit.carrier_id() {
            let carrier_order = orders
                .iter()
                .find(|order| order.unit_id == carrier)
                .ok_or("the carrier has no submitted order.")?;
            if carrier_order.path.len() != 1 {
                return Err("the truck must hold while unloading.");
            }
            continue;
        }
        let destination = *order
            .path
            .last()
            .ok_or("movement requires a starting position.")?;
        if let Some(target) = scenario.units.iter().find(|target| {
            target.side() == side
                && target.carrier_id().is_none()
                && target.board_position() == Some(destination)
                && target.unit_id() != unit.unit_id()
        }) {
            let target_order = orders
                .iter()
                .find(|order| order.unit_id == target.unit_id())
                .ok_or("the receiving unit has no submitted order.")?;
            if target_order.path.len() > 1 {
                continue;
            }
            if target_order.facing.direction().is_some() {
                return Err("the receiving unit must hold while loading.");
            }
            let (truck, passenger) = scenario
                .loading_pair(unit, target)
                .ok_or("the units cannot load together.")?;
            if !loading_passengers.insert(passenger) {
                return Err("a unit cannot board two trucks.");
            }
            let count = loading_counts.entry(truck).or_insert_with(|| {
                scenario
                    .units
                    .iter()
                    .filter(|unit| unit.carrier_id() == Some(truck))
                    .count()
            });
            *count += 1;
            let truck_unit = scenario
                .units
                .iter()
                .find(|unit| unit.unit_id() == truck)
                .ok_or("the order references a missing unit.")?;
            if *count > truck_unit.cargo_capacity() as usize {
                return Err("the truck has no room for another unit.");
            }
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
    let sides: BTreeMap<_, _> = scenario
        .units
        .iter()
        .map(|unit| (unit.unit_id(), side_index(unit.side())))
        .collect();
    let events: Vec<_> = events
        .into_iter()
        .map(|event| {
            let side = *sides
                .get(&event.unit_id)
                .ok_or("playback references a missing unit.")?;
            Ok((event, side))
        })
        .collect::<Result<_, &str>>()?;
    let mut ordered = Vec::with_capacity(events.len());
    // Keep transport dependencies: complete movement before boarding/unloading.
    // Holds remain before loads so the first event still restores a unit's origin.
    for kinds in [
        &[
            TurnEventKind::Move,
            TurnEventKind::Rotate,
            TurnEventKind::Ambush,
        ][..],
        &[TurnEventKind::Hold, TurnEventKind::MovementStopped][..],
        &[TurnEventKind::Load][..],
        &[TurnEventKind::Unload][..],
    ] {
        let mut queues: [Vec<_>; 2] = std::array::from_fn(|side| {
            let mut queue: Vec<_> = events
                .iter()
                .filter(|(event, owner)| kinds.contains(&event.kind) && *owner == side)
                .map(|(event, _)| event.clone())
                .collect();
            queue.sort_by_key(|event| event.unit_id);
            queue
        });
        let counts = queues.each_ref().map(Vec::len);
        // Reverse for efficient removal while preserving stable within-side order.
        for queue in &mut queues {
            queue.reverse();
        }
        let mut emitted = [0usize; 2];
        let initiative = if turn_number % 2 == 1 { 0 } else { 1 };
        let mut preferred = initiative;
        while !queues.iter().all(Vec::is_empty) {
            let side = if queues[0].is_empty() {
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
            if let Some(event) = queues[side].pop() {
                ordered.push(event);
                emitted[side] += 1;
                preferred = 1 - side;
            }
        }
    }
    Ok(ordered)
}

impl Turns {
    pub fn submit(
        &mut self,
        scenario: &mut Scenario,
        side: PlayerNumber,
        number: i32,
        inputs: Vec<MoveOrderInput>,
    ) -> Result<(), &'static str> {
        let mut next_turns = self.clone();
        let mut next_scenario = scenario.clone();
        next_turns.submit_pending(&mut next_scenario, side, number, inputs)?;
        *self = next_turns;
        *scenario = next_scenario;
        Ok(())
    }

    fn submit_pending(
        &mut self,
        scenario: &mut Scenario,
        side: PlayerNumber,
        number: i32,
        inputs: Vec<MoveOrderInput>,
    ) -> Result<(), &'static str> {
        if number != self.number {
            return Err("the turn has changed. refresh before submitting.");
        }
        let index = side_index(side);
        // A retry after a lost response cannot alter or duplicate locked orders.
        if self.orders[index].is_some() {
            return Ok(());
        }
        self.orders[index] = Some(validate(scenario, side, inputs)?);
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
            let mut loads = Vec::new();
            for order in &orders {
                let unit = scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == order.unit_id)
                    .ok_or("the order references a missing unit.")?;
                let destination = *order
                    .path
                    .last()
                    .ok_or("movement requires a starting position.")?;
                let conflict = conflicts.contains(&order.unit_id);
                let kind = if conflict {
                    TurnEventKind::MovementStopped
                } else if order.facing.is_ambush() {
                    TurnEventKind::Ambush
                } else if order.facing.direction().is_some() {
                    TurnEventKind::Rotate
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
                if !conflict
                    && order.path.len() > 1
                    && unit.carrier_id().is_none()
                    && let Some(target) = scenario.units.iter().find(|target| {
                        target.carrier_id().is_none()
                            && target.board_position() == Some(destination)
                            && target.unit_id() != unit.unit_id()
                    })
                    && orders.iter().any(|receiver| {
                        receiver.unit_id == target.unit_id() && receiver.path.len() == 1
                    })
                    && let Some(pair) = scenario.loading_pair(unit, target)
                {
                    loads.push(pair);
                }
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
                unit.follow_path(&event.path);
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
            for (truck, passenger) in loads {
                let carrier_alive = scenario
                    .units
                    .iter()
                    .any(|unit| unit.unit_id() == truck && unit.is_alive());
                let unit = scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == passenger)
                    .ok_or("the order references a missing unit.")?;
                if !unit.is_alive() || !carrier_alive {
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
                        .follow_path(&event.path);
                    events.push(event);
                    frames.push(TurnFrame {
                        shots: Vec::new(),
                        units: scenario.units.clone(),
                        visible_tiles: Vec::new(),
                        duration_ms: 180,
                    });
                    combat.engage(scenario, &mut combat_stopped, &mut frames);
                }
            }

            let events = playback_order(scenario, self.number, events)?;
            let resource_snapshot = scenario.finish_turn_resources();
            let deaths = resource_snapshot.len() != scenario.units.len();
            if deaths {
                frames.push(TurnFrame {
                    shots: Vec::new(),
                    units: resource_snapshot,
                    visible_tiles: Vec::new(),
                    duration_ms: 180,
                });
            }
            frames.push(TurnFrame {
                shots: Vec::new(),
                units: scenario.units.clone(),
                visible_tiles: Vec::new(),
                duration_ms: if deaths { 600 } else { 180 },
            });
            self.last_resolution = Some(TurnResolution {
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
    passenger: &crate::scenario::Unit,
    destination: Coordinate,
    moving_truck: Option<UnitId>,
) -> bool {
    if !passenger.supplies().can_move(1) {
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
        .any(|entry| entry.terrain == terrain && entry.cost <= rule.budget);
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
    use crate::scenario::UnitKind;
    use crate::test_support::{FixtureValue, TestResult};

    fn playback_fixture(scenario: &Scenario, counts: [usize; 2]) -> TestResult<Vec<TurnEvent>> {
        Ok({
            [PlayerNumber::Player1, PlayerNumber::Player2]
                .into_iter()
                .flat_map(|side| {
                    scenario
                        .units
                        .iter()
                        .filter(move |unit| unit.side() == side)
                        .take(counts[side_index(side)])
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
    fn playback_spreads_unequal_forces_and_handles_empty_sides() -> TestResult<()> {
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
                    seen[side_index(unit.side())] += 1;
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

    fn holds(scenario: &Scenario, side: PlayerNumber) -> TestResult<Vec<MoveOrderInput>> {
        Ok({
            scenario
                .units
                .iter()
                .filter(|unit| unit.side() == side)
                .map(|unit| {
                    let position = scenario.physical_position(unit).fixture()?;
                    Ok(MoveOrderInput {
                        ambush: None,
                        direction: None,
                        unit_id: unit.id(),
                        unloads: None,
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
    fn ambush_submission_resolves_damage_costs_and_facing_in_both_submission_orders()
    -> TestResult<()> {
        for first in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario
                .units
                .retain(|unit| unit.id() == "1" || unit.id() == "6");
            scenario.units[0].move_to(Coordinate::new(7, 8));
            scenario.units[1].move_to(Coordinate::new(8, 8));
            let mut turns = Turns::default();
            for side in [
                first,
                if first == PlayerNumber::Player1 {
                    PlayerNumber::Player2
                } else {
                    PlayerNumber::Player1
                },
            ] {
                let mut inputs = holds(&scenario, side)?;
                if side == PlayerNumber::Player1 {
                    inputs[0].ambush = Some(true);
                    inputs[0].direction = Some(Direction::East);
                }
                turns.submit(&mut scenario, side, 1, inputs)?;
            }
            assert_eq!(turns.number, 2);
            assert_eq!(scenario.units[0].hit_points().current(), 12);
            assert_eq!(scenario.units[1].hit_points().current(), 12);
            assert_eq!(scenario.units[0].supplies().current(), 59);
            assert_eq!(scenario.units[1].supplies().current(), 61);
            assert_eq!(scenario.units[0].direction(), Some(Direction::East));
            let resolution = turns.last_resolution.as_ref().fixture()?;
            assert_eq!(
                resolution
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .count(),
                2
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
                2
            );
        }
        Ok(())
    }

    #[test]
    fn ambush_engages_a_passenger_unloading_from_a_concealed_truck() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
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
        assert_eq!(passenger.hit_points().current(), 4);
        assert_eq!(passenger.supplies().current(), 57);
        let gun = scenario
            .units
            .iter()
            .find(|unit| unit.id() == "12")
            .fixture()?;
        assert_eq!(gun.hit_points().current(), 12);
        assert_eq!(gun.supplies().current(), 59);
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
            2
        );
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
        scenario.units[0].spend_supplies(62);
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
        assert_eq!(scenario.units[0].supplies().current(), 2);
        Ok(())
    }

    #[test]
    fn rotations_resolve_in_place_with_only_upkeep_and_preserve_health_and_fuel() -> TestResult<()>
    {
        for direction in [
            Direction::North,
            Direction::East,
            Direction::South,
            Direction::West,
        ] {
            let mut scenario = Scenario::supply_point().fixture()?;
            let originals = scenario.units.clone();
            let mut orders = holds(&scenario, PlayerNumber::Player1)?;
            for order in &mut orders {
                let unit = originals
                    .iter()
                    .find(|unit| unit.id() == order.unit_id)
                    .fixture()?;
                if unit.direction().is_some() {
                    order.direction = Some(direction);
                }
            }
            let mut turns = Turns::default();
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                .fixture()?;
            assert_eq!(scenario.units[0].direction(), originals[0].direction());
            let opposing = holds(&scenario, PlayerNumber::Player2)?;
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, opposing)
                .fixture()?;
            for (unit, original) in scenario.units.iter().zip(&originals) {
                assert_eq!(unit.board_position(), original.board_position());
                assert_eq!(unit.fuel(), original.fuel());
                assert_eq!(unit.hit_points(), original.hit_points());
                assert_eq!(unit.supplies().current(), original.supplies().current() - 1);
                let expected =
                    if unit.side() == PlayerNumber::Player1 && original.direction().is_some() {
                        Some(direction)
                    } else {
                        original.direction()
                    };
                assert_eq!(unit.direction(), expected);
            }
            let event = &turns.last_resolution.as_ref().fixture()?.events[0];
            assert_eq!(event.kind, TurnEventKind::Rotate);
            assert_eq!(event.rotation_direction, Some(direction));
            assert_eq!(event.initial_direction, originals[0].direction());
        }

        Ok(())
    }

    #[test]
    fn rotation_rejects_trucks_passengers_movement_and_rotating_load_receivers() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .fixture()?
            .direction = Some(Direction::North);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].direction = Some(Direction::North);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)])?;
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        vehicle(&mut scenario, "1")?.board(UnitId::parse("4").fixture()?);
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
        orders[0].direction = Some(Direction::North);
        assert!(validate(&scenario, PlayerNumber::Player1, orders).is_err());
        vehicle(&mut scenario, "1")?.move_to(Coordinate::new(3, 7));
        let mut orders = holds(&scenario, PlayerNumber::Player1)?;
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

    fn vehicle<'a>(
        scenario: &'a mut Scenario,
        id: &str,
    ) -> TestResult<&'a mut crate::scenario::Unit> {
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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 59);
        assert_eq!(vehicle(&mut scenario, "2")?.supplies().current(), 55);
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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 58);
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 30);
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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 53);

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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 59);
        assert_eq!(vehicle(&mut scenario, "2")?.supplies().current(), 63);
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
        scenario.map = crate::map::Map::from_ascii("...\n...\n...").fixture()?;
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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 64);

        Ok(())
    }

    #[test]
    fn concealed_unload_exits_accept_orders_and_resolve_against_actual_occupancy() -> TestResult<()>
    {
        for side in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let (passenger_id, truck_id, enemy_id) = if side == PlayerNumber::Player1 {
                ("1", "4", "6")
            } else {
                ("6", "9", "1")
            };
            let opponent = if side == PlayerNumber::Player1 {
                PlayerNumber::Player2
            } else {
                PlayerNumber::Player1
            };
            for first in [side, opponent] {
                for moving_truck in [false, true] {
                    for direct_unload in [false, true] {
                        if moving_truck && direct_unload {
                            continue;
                        }
                        for enemy_leaves in [false, true] {
                            let mut scenario = Scenario::supply_point().fixture()?;
                            scenario.map =
                                crate::map::Map::from_ascii("...\n.#.\n...").fixture()?;
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
                            let mut own = holds(&scenario, side)?;
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
                            let submissions = if first == side {
                                [(side, own), (opponent, opposing)]
                            } else {
                                [(opponent, opposing), (side, own)]
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
                                if moving_truck { 31 } else { 32 }
                            );
                            let passenger = vehicle(&mut scenario, passenger_id)?;
                            if enemy_leaves {
                                assert_eq!(passenger.board_position(), Some(Coordinate::new(1, 1)));
                                assert_eq!(
                                    passenger.supplies().current(),
                                    63 - passenger.supplies().movement_per_tile()
                                );
                            } else {
                                assert_eq!(passenger.carrier_id(), UnitId::parse(truck_id));
                                assert_eq!(passenger.supplies().current(), 63);
                                let visible = crate::visibility::visible_tiles(&scenario, side);
                                let projected = crate::visibility::observed_resolution(
                                    &scenario,
                                    side,
                                    &visible,
                                    turns.last_resolution.as_ref().fixture()?,
                                );
                                assert!(projected.frames.iter().all(|frame| {
                                    frame.units.iter().all(|unit| unit.side() == side)
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
        assert_eq!(vehicle(&mut scenario, "12")?.supplies().current(), 63);
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
        let mut turns = Turns::default();
        for unit in &mut scenario.units {
            let supplies = if unit.kind() == UnitKind::Infantry {
                9
            } else {
                3
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
                9
            } else {
                3
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
        assert_eq!(resolution.frames.last().fixture()?.duration_ms, 600);
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
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 8);
        }
        assert_eq!(vehicle(&mut scenario, "13")?.supplies().current(), 1);
        for id in ["4", "11"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 2);
        }
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 31);
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 31);

        Ok(())
    }

    #[test]
    fn supplies_reserve_upkeep_reject_movement_and_die_at_zero() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        let mut turns = Turns::default();
        for _ in 0..63 {
            resolve_holds(&mut scenario, &mut turns)?;
        }
        let number = turns.number;
        for (id, path) in [("1", vec![(3, 7), (3, 6)]), ("12", vec![(4, 7), (4, 6)])] {
            let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
            set_path(&mut player1, id, &path)?;
            assert_eq!(
                turns.submit(&mut scenario, PlayerNumber::Player1, number, player1),
                Err("movement exceeds supplies available after upkeep.")
            );
            assert!(turns.orders[0].is_none());
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 1);
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
    fn depots_do_not_replenish_supplies() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(14, 8));
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "5")?.move_to(Coordinate::new(8, 8));
        let mut turns = Turns::default();
        resolve_holds(&mut scenario, &mut turns)?;
        for id in ["4", "5", "9"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 31);
        }
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "9")?.move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns)?;
        for id in ["4", "9"] {
            assert_eq!(vehicle(&mut scenario, id)?.supplies().current(), 30);
        }
        assert_eq!(vehicle(&mut scenario, "5")?.supplies().current(), 30);

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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 59);
        assert_eq!(vehicle(&mut scenario, "6")?.supplies().current(), 59);
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
            for (side, orders) in submissions {
                turns.submit(&mut scenario, side, 1, orders).fixture()?;
            }
            assert_eq!(
                vehicle(&mut scenario, "11")?.board_position(),
                Some(Coordinate::new(1, 0))
            );
            assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 31);
            assert_eq!(
                vehicle(&mut scenario, "6")?.board_position(),
                Some(Coordinate::new(2, 0))
            );
            assert_eq!(vehicle(&mut scenario, "6")?.supplies().current(), 63);
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
        scenario.map = crate::map::Map::from_ascii(".#").fixture()?;
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
        assert_eq!(vehicle(&mut scenario, "1")?.supplies().current(), 63);
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
                .all(|unit| unit.side() == PlayerNumber::Player1)
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
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 32);
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, PlayerNumber::Player1)?;
        set_path(&mut player1, "4", &[(2, 7), (2, 6), (3, 6)])?;
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, player1)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 32);
        turns
            .submit(&mut scenario, PlayerNumber::Player1, 1, vec![])
            .fixture()?;
        let player2 = holds(&scenario, PlayerNumber::Player2)?;
        turns
            .submit(&mut scenario, PlayerNumber::Player2, 1, player2)
            .fixture()?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 30);
        assert_eq!(vehicle(&mut scenario, "11")?.fuel().fixture()?.current, 32);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 30);

        Ok(())
    }

    #[test]
    fn fuel_rejection_is_atomic_and_empty_vehicles_can_hold() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
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
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 32);

        Ok(())
    }

    #[test]
    fn tank_paths_must_fit_remaining_fuel_even_with_movement_points_left() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
        for _ in 0..15 {
            vehicle(&mut scenario, "11")?.follow_path(&[
                Coordinate::new(4, 8),
                Coordinate::new(5, 8),
                Coordinate::new(4, 8),
            ]);
        }
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
    fn any_depot_refills_either_side_after_arrival_and_holding() -> TestResult<()> {
        let mut scenario = Scenario::supply_point().fixture()?;
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
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 32);
        vehicle(&mut scenario, "4")?.follow_path(&[Coordinate::new(2, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5")?.follow_path(&[Coordinate::new(2, 9), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "9")?.follow_path(&[Coordinate::new(14, 7), Coordinate::new(2, 8)]);
        // Refuel at the center and both starting depots, regardless of side.
        vehicle(&mut scenario, "4")?.move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 32);
        assert_eq!(vehicle(&mut scenario, "5")?.fuel().fixture()?.current, 32);
        assert_eq!(vehicle(&mut scenario, "9")?.fuel().fixture()?.current, 32);
        vehicle(&mut scenario, "9")?.follow_path(&[Coordinate::new(2, 8), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "4")?.follow_path(&[Coordinate::new(14, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5")?.follow_path(&[Coordinate::new(8, 8), Coordinate::new(8, 7)]);
        resolve_holds(&mut scenario, &mut turns)?;
        assert_eq!(vehicle(&mut scenario, "4")?.fuel().fixture()?.current, 32);
        assert_eq!(vehicle(&mut scenario, "9")?.fuel().fixture()?.current, 32);
        assert_eq!(vehicle(&mut scenario, "5")?.fuel().fixture()?.current, 31);

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
            assert_eq!(unit.fuel().fixture()?.current, 31);
            assert_eq!(unit.supplies().current(), 31);
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
        scenario.map = crate::map::Map::from_ascii(".....\n.....\n.....").fixture()?;
        scenario
            .units
            .retain(|unit| ["1", "2", "3", "4"].contains(&unit.id().as_str()));
        for (id, x) in [("1", 1), ("2", 2), ("3", 3), ("4", 4)] {
            vehicle(&mut scenario, id)?.move_to(Coordinate::new(x, 1));
        }
        Ok(scenario)
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
            for unloading_side in [PlayerNumber::Player1, PlayerNumber::Player2] {
                for first_side in [PlayerNumber::Player1, PlayerNumber::Player2] {
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
                    for (passenger, truck, origin, side) in [
                        ("1", "4", Coordinate::new(5, 6), PlayerNumber::Player1),
                        ("6", "9", Coordinate::new(7, 6), PlayerNumber::Player2),
                    ] {
                        let unit = vehicle(&mut scenario, passenger)?;
                        if both_aboard || side == unloading_side {
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
                        if unloading_side == PlayerNumber::Player1 {
                            set_path(&mut player2, "6", &[(7, 6), (6, 6), (6, 5)])?;
                        } else {
                            set_path(&mut player1, "1", &[(5, 6), (6, 6), (6, 5)])?;
                        }
                    }
                    let submissions = if first_side == PlayerNumber::Player1 {
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
                    for (side, orders) in submissions {
                        turns.submit(&mut scenario, side, 1, orders).fixture()?;
                    }
                    assert_eq!(turns.number, 2);
                    let events = &turns.last_resolution.as_ref().fixture()?.events;
                    assert_eq!(events.len(), 4);
                    let winner = if both_aboard {
                        PlayerNumber::Player1
                    } else {
                        unloading_side
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
                                - 1
                                - traveled as i32 * unit.supplies().movement_per_tile()
                        );
                        if ["1", "6"].contains(&unit.id().as_str()) {
                            assert_eq!(event.kind, TurnEventKind::MovementStopped);
                            if unit.side() == winner {
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
                "1" => (Coordinate::new(3, 6), 59),
                "6" => (Coordinate::new(4, 6), 59),
                _ => (
                    original.board_position().fixture()?,
                    original.supplies().current() - 1,
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
}
