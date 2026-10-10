use crate::{
    map::Coordinate,
    movement,
    scenario::{Direction, Scenario, Side, Unit, UnitId},
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
    /// Passenger destinations after this truck moves.
    unloads: Option<Vec<UnloadOrderInput>>,
}

#[derive(Clone, Debug)]
pub struct MoveOrder {
    pub direction: Option<Direction>,
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
    pub unloads: Vec<UnloadOrder>,
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
    Rotate,
    Load,
    Unload,
    Hold,
    DestinationConflict,
}

/// Ordered presentation events. Future attacks and interruptions belong here;
/// clients replay these outcomes rather than reimplementing resolution rules.
#[derive(Clone, Debug)]
pub struct TurnEvent {
    pub rotation_direction: Option<Direction>,
    pub initial_direction: Option<Direction>,
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

pub fn side_index(side: Side) -> usize {
    match side {
        Side::Player1 => 0,
        Side::Player2 => 1,
    }
}

pub fn validate(
    scenario: &Scenario,
    side: Side,
    inputs: Vec<MoveOrderInput>,
) -> Result<Vec<MoveOrder>, &'static str> {
    let own_count = scenario
        .units
        .iter()
        .filter(|unit| unit.side() == side)
        .count();
    if inputs.len() != own_count {
        return Err("set a move or hold order for every unit before submitting.");
    }
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
            .unwrap();
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
        if input.direction.is_some() {
            if unit.direction().is_none() || unit.carrier_id().is_some() {
                return Err("only units on the map with a facing can rotate.");
            }
            if path.len() != 1 || !input.unloads.as_ref().is_none_or(Vec::is_empty) {
                return Err("rotation must be an in-place order without unloading.");
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
            if scenario.units.iter().any(|other| {
                other.carrier_id().is_none()
                    && other.side() != side
                    && other.board_position() == Some(step[1])
            }) {
                return Err("enemy units block movement.");
            }
            let terrain = scenario.map.tile_at(step[1]).unwrap();
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
        let destination = *path.last().unwrap();
        if unit.carrier_id().is_some() {
            if path.len() > 2 {
                return Err("unloading must end on an adjacent square.");
            }
            if path.len() > 1
                && scenario.units.iter().any(|other| {
                    other.carrier_id().is_none() && other.board_position() == Some(destination)
                })
            {
                return Err("unloading requires an empty square.");
            }
        } else if let Some(target) = scenario.units.iter().find(|other| {
            other.unit_id() != unit.unit_id()
                && other.carrier_id().is_none()
                && other.board_position() == Some(destination)
        }) && scenario.loading_pair(unit, target).is_none()
        {
            return Err("occupied squares cannot be destinations.");
        }
        // Stationary units may share a loading destination with their partner.
        // Validate those pairs together after all individual paths are checked.
        if path.len() > 1
            && !destinations.insert(destination)
            && !scenario.units.iter().any(|target| {
                target.board_position() == Some(destination)
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
            if !legal_unload(scenario, passenger, exit, Some(unit_id)) {
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
            direction: input.direction,
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
            .unwrap();
        if let Some(carrier) = unit.carrier_id() {
            let carrier_order = orders
                .iter()
                .find(|order| order.unit_id == carrier)
                .unwrap();
            if carrier_order.path.len() != 1 {
                return Err("the truck must hold while unloading.");
            }
            continue;
        }
        if let Some(target) = scenario.units.iter().find(|target| {
            target.carrier_id().is_none()
                && target.board_position() == Some(*order.path.last().unwrap())
                && target.unit_id() != unit.unit_id()
        }) {
            let target_order = orders
                .iter()
                .find(|order| order.unit_id == target.unit_id())
                .unwrap();
            if target_order.path.len() != 1 || target_order.direction.is_some() {
                return Err("the receiving unit must hold while loading.");
            }
            let (truck, passenger) = scenario.loading_pair(unit, target).unwrap();
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
                .unwrap();
            if *count > truck_unit.cargo_capacity() as usize {
                return Err("the truck has no room for another unit.");
            }
        }
    }
    Ok(orders)
}

/// Analyze both locked submissions against the unchanged starting board. Future
/// combat must extend this pass to settle path intersections and interruptions
/// before constructing movement events or applying any unit/resource changes.
fn destination_conflicts(scenario: &Scenario, orders: &[MoveOrder]) -> BTreeSet<UnitId> {
    let sides: BTreeMap<_, _> = scenario
        .units
        .iter()
        .map(|unit| (unit.unit_id(), unit.side()))
        .collect();
    orders
        .iter()
        .filter(|order| {
            order.path.len() > 1
                && orders.iter().any(|other| {
                    sides[&other.unit_id] != sides[&order.unit_id]
                        && other.path.last() == order.path.last()
                        && scenario
                            .units
                            .iter()
                            .find(|unit| unit.unit_id() == other.unit_id)
                            .is_some_and(|unit| unit.carrier_id().is_none())
                })
        })
        .map(|order| order.unit_id)
        .collect()
}

/// Presentation order never determines outcomes. Complete routes alternate when
/// counts match and spread proportionally when counts differ. Initiative switches
/// each turn; both viewers replay the same schedule, regardless of submission order.
fn playback_order(scenario: &Scenario, turn_number: i32, events: Vec<TurnEvent>) -> Vec<TurnEvent> {
    let sides: BTreeMap<_, _> = scenario
        .units
        .iter()
        .map(|unit| (unit.unit_id(), side_index(unit.side())))
        .collect();
    let mut ordered = Vec::with_capacity(events.len());
    // Keep transport dependencies: complete movement before boarding/unloading.
    // Holds remain before loads so the first event still restores a unit's origin.
    for kinds in [
        &[TurnEventKind::Move, TurnEventKind::Rotate][..],
        &[TurnEventKind::Hold, TurnEventKind::DestinationConflict][..],
        &[TurnEventKind::Load][..],
        &[TurnEventKind::Unload][..],
    ] {
        let mut queues: [Vec<_>; 2] = std::array::from_fn(|side| {
            let mut queue: Vec<_> = events
                .iter()
                .filter(|event| kinds.contains(&event.kind) && sides[&event.unit_id] == side)
                .cloned()
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
    ordered
}

impl Turns {
    pub fn submit(
        &mut self,
        scenario: &mut Scenario,
        side: Side,
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
                .flat_map(|orders| orders.take().unwrap())
                .collect();
            // Stable unit order, independent of which player's request arrives first.
            orders.sort_by_key(|order| order.unit_id);
            let conflicts = destination_conflicts(scenario, &orders);
            let mut events = Vec::new();
            let mut loads = Vec::new();
            for order in &orders {
                let unit = scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == order.unit_id)
                    .unwrap();
                let destination = *order.path.last().unwrap();
                let conflict = conflicts.contains(&order.unit_id);
                let kind = if conflict {
                    TurnEventKind::DestinationConflict
                } else if order.direction.is_some() {
                    TurnEventKind::Rotate
                } else if order.path.len() == 1 {
                    TurnEventKind::Hold
                } else if unit.carrier_id().is_some() {
                    TurnEventKind::Unload
                } else {
                    TurnEventKind::Move
                };
                let path = if conflict {
                    vec![order.path[0]]
                } else {
                    order.path.clone()
                };
                if !conflict
                    && order.path.len() > 1
                    && unit.carrier_id().is_none()
                    && let Some(target) = scenario.units.iter().find(|target| {
                        target.carrier_id().is_none()
                            && target.board_position() == Some(destination)
                            && target.unit_id() != unit.unit_id()
                    })
                    && let Some(pair) = scenario.loading_pair(unit, target)
                {
                    loads.push(pair);
                }
                events.push(TurnEvent {
                    rotation_direction: order.direction,
                    initial_direction: unit.direction(),
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
                    .unwrap();
                unit.follow_path(&event.path);
                if let Some(direction) = event.rotation_direction {
                    unit.rotate(direction);
                }
            }
            // Attach after movement, so stable event order cannot move cargo back
            // to its old hold position. The explicit event makes playback reversible.
            for (truck, passenger) in loads {
                let unit = scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == passenger)
                    .unwrap();
                events.push(TurnEvent {
                    rotation_direction: None,
                    initial_direction: unit.direction(),
                    initial_carrier: None,
                    carrier_id: Some(truck),
                    kind: TurnEventKind::Load,
                    unit_id: passenger,
                    path: vec![unit.board_position().unwrap()],
                });
                unit.board(truck);
            }

            // Resolve unloading after all vehicle movement and loading. A blocked
            // truck or a passenger without a legal exit keeps its cargo aboard.
            for order in &orders {
                let truck_arrived = events.iter().any(|event| {
                    event.unit_id == order.unit_id
                        && event.kind != TurnEventKind::DestinationConflict
                });
                if !truck_arrived {
                    continue;
                }
                for unload in &order.unloads {
                    let passenger = scenario
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == unload.unit_id)
                        .unwrap();
                    let origin = scenario.physical_position(passenger).unwrap();
                    let destination = unload.destination;
                    if !legal_unload(scenario, passenger, destination, None) {
                        continue;
                    }
                    let event = TurnEvent {
                        rotation_direction: None,
                        initial_direction: passenger.direction(),
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
                        .unwrap()
                        .follow_path(&event.path);
                    events.push(event);
                }
            }

            scenario.finish_turn_resources();
            self.last_resolution = Some(TurnResolution {
                turn_number: self.number,
                events: playback_order(scenario, self.number, events),
                frames: Vec::new(),
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
        Some(unit.unit_id()) != moving_truck && unit.board_position() == Some(destination)
    });
    affordable && !occupied
}

#[cfg(test)]
mod tests {
    use super::*;

    fn playback_fixture(scenario: &Scenario, counts: [usize; 2]) -> Vec<TurnEvent> {
        [Side::Player1, Side::Player2]
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
                rotation_direction: None,
                initial_carrier: None,
                carrier_id: None,
            })
            .collect()
    }

    #[test]
    fn playback_interleaves_three_moves_and_two_moves_and_switches_initiative() {
        let scenario = Scenario::supply_point().unwrap();
        let events = playback_fixture(&scenario, [3, 2]);
        let ids: Vec<_> = events.iter().map(|event| event.unit_id).collect();
        let order = |turn, events| {
            playback_order(&scenario, turn, events)
                .into_iter()
                .map(|event| event.unit_id)
                .collect::<Vec<_>>()
        };
        assert_eq!(
            order(1, events.clone()),
            vec![ids[0], ids[3], ids[1], ids[4], ids[2]]
        );
        assert_eq!(
            order(2, events.clone()),
            vec![ids[3], ids[0], ids[1], ids[4], ids[2]]
        );
        let mut reversed = events.clone();
        reversed.reverse();
        assert_eq!(order(1, events), order(1, reversed));
    }

    #[test]
    fn playback_spreads_unequal_forces_and_handles_empty_sides() {
        let scenario = Scenario::supply_point().unwrap();
        for counts in [[8, 3], [3, 8], [8, 8], [0, 3], [3, 0], [0, 0]] {
            for turn in [1, 2] {
                let events = playback_fixture(&scenario, counts);
                let ordered = playback_order(&scenario, turn, events.clone());
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
                        .unwrap();
                    seen[side_index(unit.side())] += 1;
                    let total = seen.iter().sum::<usize>();
                    let expected =
                        total as f64 * counts[0] as f64 / counts.iter().sum::<usize>() as f64;
                    assert!((seen[0] as f64 - expected).abs() <= 1.0);
                }
            }
        }
    }

    #[test]
    fn playback_keeps_transport_after_all_movement() {
        let scenario = Scenario::supply_point().unwrap();
        let mut events = playback_fixture(&scenario, [2, 2]);
        let mut load = events[0].clone();
        load.kind = TurnEventKind::Load;
        let mut unload = events[1].clone();
        unload.kind = TurnEventKind::Unload;
        events.insert(0, unload);
        events.insert(1, load);
        let ordered = playback_order(&scenario, 2, events);
        assert!(
            ordered[..4]
                .iter()
                .all(|event| event.kind == TurnEventKind::Move)
        );
        assert_eq!(ordered[4].kind, TurnEventKind::Load);
        assert_eq!(ordered[5].kind, TurnEventKind::Unload);
    }

    fn holds(scenario: &Scenario, side: Side) -> Vec<MoveOrderInput> {
        scenario
            .units
            .iter()
            .filter(|unit| unit.side() == side)
            .map(|unit| MoveOrderInput {
                direction: None,
                unit_id: unit.id(),
                unloads: None,
                path: vec![CoordinateInput {
                    x: scenario.physical_position(unit).unwrap().x(),
                    y: scenario.physical_position(unit).unwrap().y(),
                }],
            })
            .collect()
    }

    #[test]
    fn rotations_resolve_in_place_with_only_upkeep_and_preserve_health_and_fuel() {
        for direction in [
            Direction::North,
            Direction::East,
            Direction::South,
            Direction::West,
        ] {
            let mut scenario = Scenario::supply_point().unwrap();
            let originals = scenario.units.clone();
            let mut orders = holds(&scenario, Side::Player1);
            for order in &mut orders {
                let unit = originals
                    .iter()
                    .find(|unit| unit.id() == order.unit_id)
                    .unwrap();
                if unit.direction().is_some() {
                    order.direction = Some(direction);
                }
            }
            let mut turns = Turns::default();
            turns
                .submit(&mut scenario, Side::Player1, 1, orders)
                .unwrap();
            assert_eq!(scenario.units[0].direction(), originals[0].direction());
            let opposing = holds(&scenario, Side::Player2);
            turns
                .submit(&mut scenario, Side::Player2, 1, opposing)
                .unwrap();
            for (unit, original) in scenario.units.iter().zip(&originals) {
                assert_eq!(unit.board_position(), original.board_position());
                assert_eq!(unit.fuel(), original.fuel());
                assert_eq!(unit.hit_points(), original.hit_points());
                assert_eq!(unit.supplies().current(), 63);
                let expected = if unit.side() == Side::Player1 && original.direction().is_some() {
                    Some(direction)
                } else {
                    original.direction()
                };
                assert_eq!(unit.direction(), expected);
            }
            let event = &turns.last_resolution.as_ref().unwrap().events[0];
            assert_eq!(event.kind, TurnEventKind::Rotate);
            assert_eq!(event.rotation_direction, Some(direction));
            assert_eq!(event.initial_direction, originals[0].direction());
        }
    }

    #[test]
    fn rotation_rejects_trucks_passengers_movement_and_rotating_load_receivers() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut orders = holds(&scenario, Side::Player1);
        orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .unwrap()
            .direction = Some(Direction::North);
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        let mut orders = holds(&scenario, Side::Player1);
        orders[0].direction = Some(Direction::North);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)]);
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        vehicle(&mut scenario, "1").board(UnitId::parse("4").unwrap());
        let mut orders = holds(&scenario, Side::Player1);
        orders[0].direction = Some(Direction::North);
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        vehicle(&mut scenario, "1").move_to(Coordinate::new(3, 7));
        let mut orders = holds(&scenario, Side::Player1);
        orders[0].direction = Some(Direction::North);
        set_path(&mut orders, "4", &[(2, 7), (3, 7)]);
        assert!(validate(&scenario, Side::Player1, orders).is_err());
    }

    fn set_path(orders: &mut [MoveOrderInput], id: &str, path: &[(i32, i32)]) {
        orders
            .iter_mut()
            .find(|order| order.unit_id == id)
            .unwrap()
            .path = path
            .iter()
            .map(|&(x, y)| CoordinateInput { x, y })
            .collect();
    }

    fn vehicle<'a>(scenario: &'a mut Scenario, id: &str) -> &'a mut crate::scenario::Unit {
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == id)
            .unwrap()
    }

    fn resolve_holds(scenario: &mut Scenario, turns: &mut Turns) {
        let player1 = holds(scenario, Side::Player1);
        let player2 = holds(scenario, Side::Player2);
        let number = turns.number;
        turns
            .submit(scenario, Side::Player1, number, player1)
            .unwrap();
        turns
            .submit(scenario, Side::Player2, number, player2)
            .unwrap();
    }

    fn resolve_orders(scenario: &mut Scenario, turns: &mut Turns, player1: Vec<MoveOrderInput>) {
        let player2 = holds(scenario, Side::Player2);
        let number = turns.number;
        turns
            .submit(scenario, Side::Player1, number, player1)
            .unwrap();
        turns
            .submit(scenario, Side::Player2, number, player2)
            .unwrap();
    }

    #[test]
    fn two_units_board_then_ride_and_unload_without_walking_costs() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(3, 7), (2, 7)]);
        set_path(&mut player1, "2", &[(3, 8), (2, 8), (2, 7)]);
        resolve_orders(&mut scenario, &mut turns, player1);
        let truck = UnitId::parse("4").unwrap();
        for id in ["1", "2"] {
            assert_eq!(vehicle(&mut scenario, id).carrier_id(), Some(truck));
            assert_eq!(
                scenario
                    .physical_position(scenario.units.iter().find(|unit| unit.id() == id).unwrap())
                    .unwrap(),
                Coordinate::new(2, 7)
            );
        }
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 62);
        assert_eq!(vehicle(&mut scenario, "2").supplies().current(), 61);
        assert_eq!(
            turns
                .last_resolution
                .as_ref()
                .unwrap()
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::Load)
                .count(),
            2
        );
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (2, 8), (1, 8)]);
        resolve_orders(&mut scenario, &mut turns, player1);
        for id in ["1", "2"] {
            assert_eq!(
                scenario
                    .physical_position(scenario.units.iter().find(|unit| unit.id() == id).unwrap())
                    .unwrap(),
                Coordinate::new(1, 8)
            );
        }
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 61);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 62);
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(1, 8), (0, 8)]);
        set_path(&mut player1, "2", &[(1, 8), (1, 7)]);
        resolve_orders(&mut scenario, &mut turns, player1);
        assert_eq!(vehicle(&mut scenario, "1").carrier_id(), None);
        assert_eq!(vehicle(&mut scenario, "2").carrier_id(), None);
        assert_eq!(
            scenario
                .physical_position(scenario.units.iter().find(|unit| unit.id() == "1").unwrap())
                .unwrap(),
            Coordinate::new(0, 8)
        );
        assert_eq!(
            scenario
                .physical_position(scenario.units.iter().find(|unit| unit.id() == "2").unwrap())
                .unwrap(),
            Coordinate::new(1, 7)
        );
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 59);
    }

    #[test]
    fn truck_moves_then_unloads_selected_passengers_at_chosen_squares() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let truck = UnitId::parse("4").unwrap();
        vehicle(&mut scenario, "1").board(truck);
        vehicle(&mut scenario, "2").board(truck);
        let mut orders = holds(&scenario, Side::Player1);
        set_path(&mut orders, "4", &[(2, 7), (2, 8), (1, 8)]);
        orders
            .iter_mut()
            .find(|order| order.unit_id == "4")
            .unwrap()
            .unloads = Some(vec![UnloadOrderInput {
            unit_id: "1".into(),
            destination: CoordinateInput { x: 0, y: 8 },
        }]);
        resolve_orders(&mut scenario, &mut turns, orders);
        assert_eq!(
            vehicle(&mut scenario, "1").board_position(),
            Some(Coordinate::new(0, 8))
        );
        assert_eq!(vehicle(&mut scenario, "2").carrier_id(), Some(truck));
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 62);
        assert_eq!(vehicle(&mut scenario, "2").supplies().current(), 63);
        let events = &turns.last_resolution.as_ref().unwrap().events;
        let movement_index = events
            .iter()
            .position(|event| event.unit_id == truck)
            .unwrap();
        let unload_index = events
            .iter()
            .position(|event| event.kind == TurnEventKind::Unload)
            .unwrap();
        assert!(unload_index > movement_index);
        assert_eq!(
            events[unload_index].path,
            vec![Coordinate::new(1, 8), Coordinate::new(0, 8)]
        );
    }

    #[test]
    fn truck_unloads_validate_cargo_adjacency_and_reserved_destinations() {
        let mut scenario = Scenario::supply_point().unwrap();
        let truck = UnitId::parse("4").unwrap();
        vehicle(&mut scenario, "1").board(truck);
        vehicle(&mut scenario, "2").board(truck);
        for (passenger, x, y) in [("3", 1, 8), ("1", 0, 8), ("1", 2, 9)] {
            let mut orders = holds(&scenario, Side::Player1);
            set_path(&mut orders, "4", &[(2, 7), (2, 8)]);
            orders
                .iter_mut()
                .find(|order| order.unit_id == "4")
                .unwrap()
                .unloads = Some(vec![UnloadOrderInput {
                unit_id: passenger.into(),
                destination: CoordinateInput { x, y },
            }]);
            if passenger == "1" && x == 2 {
                // Two passengers cannot share one exit.
                orders
                    .iter_mut()
                    .find(|order| order.unit_id == "4")
                    .unwrap()
                    .unloads
                    .as_mut()
                    .unwrap()
                    .push(UnloadOrderInput {
                        unit_id: "2".into(),
                        destination: CoordinateInput { x, y },
                    });
            }
            assert!(validate(&scenario, Side::Player1, orders).is_err());
        }
    }

    #[test]
    fn blocked_truck_and_occupied_exit_keep_passengers_aboard() {
        for block_truck in [false, true] {
            let mut scenario = Scenario::supply_point().unwrap();
            let mut turns = Turns::default();
            let truck = UnitId::parse("4").unwrap();
            vehicle(&mut scenario, "1").board(truck);
            vehicle(&mut scenario, "6").move_to(Coordinate::new(0, 9));
            let mut orders = holds(&scenario, Side::Player1);
            set_path(&mut orders, "4", &[(2, 7), (2, 8), (1, 8)]);
            orders
                .iter_mut()
                .find(|order| order.unit_id == "4")
                .unwrap()
                .unloads = Some(vec![UnloadOrderInput {
                unit_id: "1".into(),
                destination: CoordinateInput { x: 0, y: 8 },
            }]);
            let mut opponent = holds(&scenario, Side::Player2);
            if block_truck {
                set_path(&mut opponent, "6", &[(0, 9), (1, 9), (1, 8)]);
            } else {
                set_path(&mut opponent, "6", &[(0, 9), (0, 8)]);
            }
            turns
                .submit(&mut scenario, Side::Player1, 1, orders)
                .unwrap();
            turns
                .submit(&mut scenario, Side::Player2, 1, opponent)
                .unwrap();
            assert_eq!(vehicle(&mut scenario, "1").carrier_id(), Some(truck));
            assert!(
                !turns
                    .last_resolution
                    .as_ref()
                    .unwrap()
                    .events
                    .iter()
                    .any(|event| event.kind == TurnEventKind::Unload)
            );
        }
    }

    #[test]
    fn trucks_collect_field_guns_and_can_fill_the_second_berth() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (3, 7), (4, 7)]);
        resolve_orders(&mut scenario, &mut turns, player1);
        assert_eq!(
            vehicle(&mut scenario, "12").carrier_id(),
            UnitId::parse("4")
        );
        assert_eq!(vehicle(&mut scenario, "12").supplies().current(), 63);
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(4, 7), (3, 7)]);
        resolve_orders(&mut scenario, &mut turns, player1);
        assert_eq!(vehicle(&mut scenario, "1").carrier_id(), UnitId::parse("4"));
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "12")
                        .unwrap()
                )
                .unwrap(),
            Coordinate::new(3, 7)
        );
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "2", &[(3, 8), (3, 7)]);
        assert!(validate(&scenario, Side::Player1, player1).is_err());
    }

    #[test]
    fn transport_rejects_overcapacity_tanks_moving_receivers_and_invalid_unloads() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "3").move_to(Coordinate::new(2, 6));
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(3, 7), (2, 7)]);
        set_path(&mut player1, "2", &[(3, 8), (2, 8), (2, 7)]);
        set_path(&mut player1, "3", &[(2, 6), (2, 7)]);
        assert_eq!(
            validate(&scenario, Side::Player1, player1).unwrap_err(),
            "the truck has no room for another unit."
        );
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (3, 7), (4, 7), (4, 8)]);
        assert!(validate(&scenario, Side::Player1, player1).is_err());
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(3, 7), (2, 7)]);
        set_path(&mut player1, "4", &[(2, 7), (2, 8)]);
        assert_eq!(
            validate(&scenario, Side::Player1, player1).unwrap_err(),
            "the receiving unit must hold while loading."
        );
        vehicle(&mut scenario, "1").board(UnitId::parse("4").unwrap());

        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(2, 7), (1, 7), (0, 7)]);
        assert!(validate(&scenario, Side::Player1, player1).is_err());
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(2, 7), (1, 7)]);
        set_path(&mut player1, "4", &[(2, 7), (2, 8)]);
        assert_eq!(
            validate(&scenario, Side::Player1, player1).unwrap_err(),
            "the truck must hold while unloading."
        );
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(2, 7), (2, 6)]);
        assert!(validate(&scenario, Side::Player1, player1).is_err());
    }

    #[test]
    fn supplies_charge_upkeep_once_and_walking_movement_only() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        for _ in 0..61 {
            resolve_holds(&mut scenario, &mut turns);
        }
        let number = turns.number;
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut player1, "13", &[(4, 9), (4, 10)]);
        set_path(&mut player1, "4", &[(2, 7), (2, 6)]);
        set_path(&mut player1, "11", &[(4, 8), (5, 8)]);
        turns
            .submit(&mut scenario, Side::Player1, number, player1)
            .unwrap();
        turns
            .submit(&mut scenario, Side::Player1, number, vec![])
            .unwrap();
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.supplies().current() == 3)
        );
        let player2 = holds(&scenario, Side::Player2);
        turns
            .submit(&mut scenario, Side::Player2, number, player2)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 0);
        assert_eq!(vehicle(&mut scenario, "13").supplies().current(), 1);
        for id in ["2", "4", "11", "6"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 2);
        }
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 63);
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 63);
    }

    #[test]
    fn supplies_reserve_upkeep_reject_movement_and_stop_at_zero() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        for _ in 0..63 {
            resolve_holds(&mut scenario, &mut turns);
        }
        let number = turns.number;
        for (id, path) in [("1", vec![(3, 7), (3, 6)]), ("12", vec![(4, 7), (4, 6)])] {
            let mut player1 = holds(&scenario, Side::Player1);
            set_path(&mut player1, id, &path);
            assert_eq!(
                turns.submit(&mut scenario, Side::Player1, number, player1),
                Err("movement exceeds supplies available after upkeep.")
            );
            assert!(turns.orders[0].is_none());
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 1);
        }
        resolve_holds(&mut scenario, &mut turns);
        resolve_holds(&mut scenario, &mut turns);
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.supplies().current() == 0)
        );
    }

    #[test]
    fn depots_do_not_replenish_supplies() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "4").move_to(Coordinate::new(14, 8));
        vehicle(&mut scenario, "9").move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "5").move_to(Coordinate::new(8, 8));
        let mut turns = Turns::default();
        resolve_holds(&mut scenario, &mut turns);
        for id in ["4", "5", "9"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 63);
        }
        vehicle(&mut scenario, "4").move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "9").move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns);
        for id in ["4", "9"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 62);
        }
        assert_eq!(vehicle(&mut scenario, "5").supplies().current(), 62);
    }

    #[test]
    fn walking_destination_conflicts_pay_upkeep_but_no_movement_supplies() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "6").move_to(Coordinate::new(5, 6));
        let mut player1 = holds(&scenario, Side::Player1);
        let mut player2 = holds(&scenario, Side::Player2);
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut player2, "6", &[(5, 6), (4, 6)]);
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 63);
        assert_eq!(vehicle(&mut scenario, "6").supplies().current(), 63);
        assert_eq!(
            scenario
                .physical_position(scenario.units.iter().find(|unit| unit.id() == "1").unwrap())
                .unwrap(),
            Coordinate::new(3, 7)
        );
        assert_eq!(
            scenario
                .physical_position(scenario.units.iter().find(|unit| unit.id() == "6").unwrap())
                .unwrap(),
            Coordinate::new(5, 6)
        );
    }

    #[test]
    fn fuel_is_vehicle_only_and_successful_tiles_consume_it_once() {
        let mut scenario = Scenario::supply_point().unwrap();
        assert!(vehicle(&mut scenario, "1").fuel().is_none());
        assert!(vehicle(&mut scenario, "12").fuel().is_none());
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 64);
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (2, 6), (3, 6)]);
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        turns
            .submit(&mut scenario, Side::Player1, 1, vec![])
            .unwrap();
        let player2 = holds(&scenario, Side::Player2);
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 62);
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 64);
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 62);
    }

    #[test]
    fn fuel_rejection_is_atomic_and_empty_vehicles_can_hold() {
        let mut scenario = Scenario::supply_point().unwrap();
        for _ in 0..32 {
            vehicle(&mut scenario, "4").follow_path(&[
                Coordinate::new(2, 7),
                Coordinate::new(2, 6),
                Coordinate::new(2, 7),
            ]);
        }
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (2, 6)]);
        assert_eq!(
            turns.submit(&mut scenario, Side::Player1, 1, player1),
            Err("movement exceeds the unit's available fuel.")
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 0);
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 0);
        vehicle(&mut scenario, "4").move_to(Coordinate::new(2, 8));
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
    }

    #[test]
    fn tank_paths_must_fit_remaining_fuel_even_with_movement_points_left() {
        let mut scenario = Scenario::supply_point().unwrap();
        for _ in 0..31 {
            vehicle(&mut scenario, "11").follow_path(&[
                Coordinate::new(4, 8),
                Coordinate::new(5, 8),
                Coordinate::new(4, 8),
            ]);
        }
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "11", &[(4, 8), (5, 8), (6, 8), (7, 8)]);
        assert_eq!(
            validate(&scenario, Side::Player1, player1).unwrap_err(),
            "movement exceeds the unit's available fuel."
        );
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "11", &[(4, 8), (5, 8), (6, 8)]);
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        let player2 = holds(&scenario, Side::Player2);
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 0);
        assert_eq!(
            scenario
                .physical_position(
                    scenario
                        .units
                        .iter()
                        .find(|unit| unit.id() == "11")
                        .unwrap()
                )
                .unwrap(),
            Coordinate::new(6, 8)
        );
    }

    #[test]
    fn any_depot_refills_either_side_after_arrival_and_holding() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "4", &[(2, 7), (2, 8)]);
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        let player2 = holds(&scenario, Side::Player2);
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        vehicle(&mut scenario, "4").follow_path(&[Coordinate::new(2, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5").follow_path(&[Coordinate::new(2, 9), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "9").follow_path(&[Coordinate::new(14, 7), Coordinate::new(2, 8)]);
        // Refuel at the center and both starting depots, regardless of side.
        vehicle(&mut scenario, "4").move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        assert_eq!(vehicle(&mut scenario, "5").fuel().unwrap().current, 64);
        assert_eq!(vehicle(&mut scenario, "9").fuel().unwrap().current, 64);
        vehicle(&mut scenario, "9").follow_path(&[Coordinate::new(2, 8), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "4").follow_path(&[Coordinate::new(14, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5").follow_path(&[Coordinate::new(8, 8), Coordinate::new(8, 7)]);
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        assert_eq!(vehicle(&mut scenario, "9").fuel().unwrap().current, 64);
        assert_eq!(vehicle(&mut scenario, "5").fuel().unwrap().current, 63);
    }

    #[test]
    fn vehicle_destination_conflicts_consume_no_fuel() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "9").move_to(Coordinate::new(4, 6));
        let mut player1 = holds(&scenario, Side::Player1);
        let mut player2 = holds(&scenario, Side::Player2);
        set_path(&mut player1, "4", &[(2, 7), (2, 6), (3, 6)]);
        set_path(&mut player2, "9", &[(4, 6), (3, 6)]);
        let initial = scenario.clone();
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        for (unit, original) in scenario.units.iter().zip(&initial.units) {
            assert_eq!(
                unit.board_position().unwrap(),
                original.board_position().unwrap()
            );
            assert_eq!(unit.direction(), original.direction());
            assert_eq!(unit.fuel(), original.fuel());
            assert_eq!(unit.supplies().current(), 63);
        }
    }

    #[test]
    fn locks_orders_resolves_once_and_rejects_stale_turns() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut player1 = holds(&scenario, Side::Player1);
        set_path(&mut player1, "1", &[(3, 7), (3, 6)]);
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        assert_eq!(turns.number, 1);
        assert_eq!(
            scenario.units[0].board_position().unwrap(),
            Coordinate::new(3, 7)
        );
        turns
            .submit(&mut scenario, Side::Player1, 1, vec![])
            .unwrap();
        assert!(turns.orders[1].is_none());
        let player2 = holds(&scenario, Side::Player2);
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        assert_eq!(turns.number, 2);
        assert_eq!(
            scenario.units[0].board_position().unwrap(),
            Coordinate::new(3, 6)
        );
        assert_eq!(scenario.units[0].direction(), Some(Direction::North));
        assert_eq!(scenario.units[1].direction(), Some(Direction::East));
        assert!(turns.orders.iter().all(Option::is_none));
        let resolution = turns.last_resolution.as_ref().unwrap();
        assert_eq!(resolution.events.len(), 16);
        assert_eq!(resolution.events[0].kind, TurnEventKind::Move);
        assert_eq!(
            resolution.events[0].initial_direction,
            Some(Direction::East)
        );
        assert_eq!(resolution.turn_number, 1);
        assert!(
            turns
                .submit(&mut scenario, Side::Player2, 1, vec![])
                .is_err()
        );
    }

    #[test]
    fn rejects_missing_duplicate_foreign_illegal_and_over_budget_orders_atomically() {
        let mut scenario = Scenario::supply_point().unwrap();
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
            let mut orders = holds(&scenario, Side::Player1);
            set_path(&mut orders, "1", &path);
            let mut turns = Turns::default();
            assert!(
                turns
                    .submit(&mut scenario, Side::Player1, 1, orders)
                    .is_err()
            );
            assert!(turns.orders[0].is_none());
        }
        let mut orders = holds(&scenario, Side::Player1);
        orders.pop();
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        let mut orders = holds(&scenario, Side::Player1);
        orders[1].unit_id = "1".into();
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        let mut orders = holds(&scenario, Side::Player1);
        orders[0].unit_id = "6".into();
        assert!(validate(&scenario, Side::Player1, orders).is_err());
    }

    #[test]
    fn allies_allow_passage_but_enemies_and_duplicate_destinations_do_not() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut orders = holds(&scenario, Side::Player1);
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)]);
        assert!(validate(&scenario, Side::Player1, orders).is_ok());
        let mut orders = holds(&scenario, Side::Player1);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)]);
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)]);
        assert!(validate(&scenario, Side::Player1, orders).is_err());
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .unwrap()
            .move_to(Coordinate::new(3, 6));
        let mut orders = holds(&scenario, Side::Player1);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)]);
        assert_eq!(
            validate(&scenario, Side::Player1, orders).unwrap_err(),
            "enemy units block movement."
        );
    }

    #[test]
    fn opposing_destination_conflicts_hold_both_units() {
        let mut scenario = Scenario::supply_point().unwrap();
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .unwrap()
            .move_to(Coordinate::new(5, 6));
        let initial = scenario.clone();
        let mut player1 = holds(&scenario, Side::Player1);
        let mut player2 = holds(&scenario, Side::Player2);
        set_path(&mut player1, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut player2, "6", &[(5, 6), (4, 6)]);
        let mut turns = Turns::default();
        turns
            .submit(&mut scenario, Side::Player2, 1, player2)
            .unwrap();
        turns
            .submit(&mut scenario, Side::Player1, 1, player1)
            .unwrap();
        assert_eq!(
            turns
                .last_resolution
                .unwrap()
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::DestinationConflict)
                .count(),
            2
        );
        for (unit, original) in scenario.units.iter().zip(&initial.units) {
            assert_eq!(
                unit.board_position().unwrap(),
                original.board_position().unwrap()
            );
            assert_eq!(unit.direction(), original.direction());
            assert_eq!(unit.fuel(), original.fuel());
            assert_eq!(unit.supplies().current(), 63);
        }
    }
}
