//! Shared freight and fuel-reserve planning on the already projected board.
//! Trucks carry their stock to allies; ordinary settlement performs transfers.
use super::{affordable_path, coordinate_input, distance, hold, transport};
use crate::{
    map::Coordinate,
    movement,
    scenario::{DepotKind, PlayerNumber, Scenario, Unit, UnitId, UnitKind},
    supplies,
    turns::MoveOrderInput,
};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Clone, Copy)]
pub(super) struct Destination {
    pub(super) position: Coordinate,
    // Loading requires the exact tile; replenishment includes cardinal neighbors.
    pub(super) range: i32,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TruckMission {
    Deliver {
        resource: DepotKind,
        recipient: UnitId,
    },
    Transport(UnitId),
    SelfResupply,
}

pub(super) struct TruckPlan {
    pub(super) mission: TruckMission,
    pub(super) score: i32,
    pub(super) order: MoveOrderInput,
    pub(super) dependent_orders: Vec<MoveOrderInput>,
}

pub(super) fn support(
    scenario: &Scenario,
    player: PlayerNumber,
    orders: &mut [MoveOrderInput],
) -> Result<(), &'static str> {
    let mut assigned = Vec::new();
    for truck in scenario.units.iter().filter(|unit| {
        unit.player_number() == player
            && unit.kind() == UnitKind::Truck
            && unit.board_position().is_some()
    }) {
        let mut plans = Vec::new();
        if scenario.passenger_count(truck.unit_id()) > 0 {
            plans.push(transport::deployment(scenario, truck, orders)?);
        } else {
            plans.extend(freight_plans(scenario, truck, orders, &assigned)?);
            plans.extend(transport::pickups(scenario, truck, orders, &assigned)?);
        }
        if let Some(plan) = provisions_plan(scenario, truck, orders)? {
            if truck.supplies().current() * 4 <= truck.supplies().maximum() {
                plans.clear();
            }
            plans.push(plan);
        }
        let best = plans.into_iter().max_by_key(|plan| plan.score);
        match best {
            Some(plan) => {
                replace_order(orders, truck, plan.order)?;
                // Fuel safety can redirect the carrier. Never retain passenger
                // commands or exits that depended on the abandoned route.
                if !protect_reserve(scenario, truck, orders)? {
                    assigned.push(plan.mission);
                    for passenger_order in plan.dependent_orders {
                        let passenger = scenario
                            .units
                            .iter()
                            .find(|unit| unit.id() == passenger_order.unit_id)
                            .ok_or("the AI transport passenger is missing.")?;
                        assigned.push(TruckMission::Transport(passenger.unit_id()));
                        replace_order(orders, passenger, passenger_order)?;
                    }
                }
            }
            None => {
                replace_order(
                    orders,
                    truck,
                    hold(
                        truck,
                        truck
                            .board_position()
                            .ok_or("the AI truck is not on the map.")?,
                    ),
                )?;
            }
        }
    }
    // Carriers are finalized before their destinations become tank refill sources.
    for vehicle in scenario.units.iter().filter(|unit| {
        unit.player_number() == player
            && unit.kind() == UnitKind::Tank
            && unit.board_position().is_some()
    }) {
        protect_reserve(scenario, vehicle, orders)?;
    }
    Ok(())
}

pub(super) fn planned_destination(
    orders: &[MoveOrderInput],
    unit: &Unit,
) -> Result<Coordinate, &'static str> {
    let end = orders
        .iter()
        .find(|order| order.unit_id == unit.id())
        .and_then(|order| order.path.last())
        .ok_or("the AI unit has no destination.")?;
    Ok(Coordinate::new(end.x as u16, end.y as u16))
}

pub(super) fn replace_order(
    orders: &mut [MoveOrderInput],
    unit: &Unit,
    replacement: MoveOrderInput,
) -> Result<(), &'static str> {
    let order = orders
        .iter_mut()
        .find(|order| order.unit_id == unit.id())
        .ok_or("the AI unit has no order.")?;
    *order = replacement;
    Ok(())
}

pub(super) fn blocked_tiles(
    scenario: &Scenario,
    unit: &Unit,
    orders: &[MoveOrderInput],
) -> Result<BTreeSet<Coordinate>, &'static str> {
    let mut blocked: BTreeSet<_> = scenario
        .units
        .iter()
        .filter(|other| other.unit_id() != unit.unit_id())
        .filter_map(Unit::board_position)
        .collect();
    for other in scenario.units.iter().filter(|other| {
        other.player_number() == unit.player_number() && other.unit_id() != unit.unit_id()
    }) {
        blocked.insert(planned_destination(orders, other)?);
    }
    // Passenger holds still name the carrier's old position. Reserve explicit
    // unload exits too, including guns that cannot issue a dismount command.
    for order in orders.iter().filter(|order| order.unit_id != unit.id()) {
        for unload in order.unloads.iter().flatten() {
            blocked.insert(unload.destination_coordinate()?);
        }
    }
    Ok(blocked)
}

/// Shortest fuel distance counts traversed tiles, not terrain half-points.
/// Terrain still determines passability and the affordable per-turn prefix.
pub(super) fn path_to(
    scenario: &Scenario,
    unit: &Unit,
    origin: Coordinate,
    destination: Destination,
    blocked: &BTreeSet<Coordinate>,
) -> Result<Option<Vec<Coordinate>>, &'static str> {
    let rule = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == unit.kind())
        .ok_or("the AI unit has no movement rule.")?;
    let mut parents = BTreeMap::from([(origin, origin)]);
    let mut pending = VecDeque::from([origin]);
    while let Some(position) = pending.pop_front() {
        if distance(position, destination.position) <= destination.range {
            let mut path = vec![position];
            let mut cursor = position;
            while cursor != origin {
                cursor = *parents
                    .get(&cursor)
                    .ok_or("the AI fuel route is incomplete.")?;
                path.push(cursor);
            }
            path.reverse();
            return Ok(Some(path));
        }
        for (x, y) in [
            (position.x() - 1, position.y()),
            (position.x() + 1, position.y()),
            (position.x(), position.y() - 1),
            (position.x(), position.y() + 1),
        ] {
            if x < 0 || y < 0 {
                continue;
            }
            let next = Coordinate::new(x as u16, y as u16);
            if blocked.contains(&next) || parents.contains_key(&next) {
                continue;
            }
            let passable = scenario.map.tile_at(next).is_some_and(|terrain| {
                rule.terrain_costs
                    .iter()
                    .any(|entry| entry.terrain == terrain && entry.cost > 0)
            });
            if passable {
                parents.insert(next, position);
                pending.push_back(next);
            }
        }
    }
    Ok(None)
}

fn pickup_targets(scenario: &Scenario, kind: DepotKind) -> Vec<Destination> {
    scenario
        .depots
        .iter()
        .filter(|depot| depot.kind == kind && (!depot.stock_visible || depot.stock.current > 0))
        .map(|depot| Destination {
            position: depot.position,
            range: 0,
        })
        .chain(
            scenario
                .supply_crates
                .iter()
                .filter(|cargo| cargo.stock.kind == kind && cargo.stock.current > 0)
                .map(|cargo| Destination {
                    position: cargo.position,
                    range: 0,
                }),
        )
        .collect()
}

fn freight_plans(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
    assigned: &[TruckMission],
) -> Result<Vec<TruckPlan>, &'static str> {
    let mut plans = Vec::new();
    for resource in [DepotKind::Fuel, DepotKind::Supply] {
        let carrying = truck
            .supply_cargo
            .iter()
            .any(|cargo| cargo.kind == resource && cargo.current > 0);
        if !carrying
            && supplies::occupied_berths(scenario, truck) >= truck.cargo_capacity() as usize
        {
            continue;
        }
        let mut recipients = Vec::new();
        for recipient in scenario.units.iter().filter(|unit| {
            unit.player_number() == truck.player_number()
                && unit.unit_id() != truck.unit_id()
                && unit.board_position().is_some()
        }) {
            let mission = TruckMission::Deliver {
                resource,
                recipient: recipient.unit_id(),
            };
            if assigned.contains(&mission) {
                continue;
            }
            let (current, maximum) = match resource {
                DepotKind::Supply => (
                    recipient.supplies().current(),
                    recipient.supplies().maximum(),
                ),
                DepotKind::Fuel => match recipient.fuel() {
                    Some(fuel) => (fuel.current, fuel.maximum),
                    None => continue,
                },
            };
            let deficit = (maximum - current) * 100 / maximum;
            // Healthy tanks still benefit from a prepared escort. Otherwise,
            // proportionate shortages decide who needs a delivery most urgently.
            let escort = if resource == DepotKind::Fuel && recipient.kind() == UnitKind::Tank {
                30
            } else {
                0
            };
            let emergency = if current * 4 <= maximum { 500 } else { 0 };
            let continuity = if carrying { 35 } else { 0 };
            let score = deficit * 2 + emergency + escort + continuity;
            if score > 0 {
                recipients.push((score, recipient));
            }
        }
        recipients
            .sort_by_key(|(score, recipient)| (std::cmp::Reverse(*score), recipient.unit_id()));
        // Bound source/route searches under the game store lock.
        for (score, recipient) in recipients.into_iter().take(4) {
            if let Some(plan) = freight_plan(scenario, truck, orders, resource, recipient, score)? {
                plans.push(plan);
            }
        }
    }
    Ok(plans)
}

fn freight_plan(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
    resource: DepotKind,
    recipient: &Unit,
    score: i32,
) -> Result<Option<TruckPlan>, &'static str> {
    let origin = truck
        .board_position()
        .ok_or("the AI truck is not on the map.")?;
    let carrying = truck
        .supply_cargo
        .iter()
        .any(|cargo| cargo.kind == resource && cargo.current > 0);
    let recipient_origin = recipient
        .board_position()
        .ok_or("the AI recipient is not on the map.")?;
    let waiting_for_supplies = resource == DepotKind::Supply
        // A carrier may already own boarding or dismount dependencies. Keep
        // its planned route intact and deliver to that rendezvous.
        && recipient.kind() != UnitKind::Truck
        && recipient.supplies().current() * 4 <= recipient.supplies().maximum();
    let recipient_destination = if waiting_for_supplies {
        recipient_origin
    } else {
        planned_destination(orders, recipient)?
    };
    let targets = if carrying {
        vec![Destination {
            position: recipient_destination,
            range: 1,
        }]
    } else {
        pickup_targets(scenario, resource)
    };
    let blocked = blocked_tiles(scenario, truck, orders)?;
    let mut routes = Vec::new();
    for target in targets {
        if let Some(path) = path_to(scenario, truck, origin, target, &blocked)? {
            routes.push(path);
        }
    }
    routes.sort_by_key(|path| (path.len(), path.last().copied()));
    let Some(path) = routes.first() else {
        return Ok(None);
    };
    let mut journey = path.len().saturating_sub(1) as i32;
    if !carrying {
        let source = path
            .last()
            .copied()
            .ok_or("the AI freight route has no source.")?;
        let delivery = Destination {
            position: recipient_destination,
            range: 1,
        };
        let Some(delivery) = path_to(scenario, truck, source, delivery, &BTreeSet::new())? else {
            return Ok(None);
        };
        journey += delivery.len().saturating_sub(1) as i32;
    }
    let mut order = hold(truck, origin);
    order.path = affordable_path(scenario, truck, path, false)?
        .into_iter()
        .map(coordinate_input)
        .collect();
    let destination = order
        .path
        .last()
        .ok_or("the AI truck has no destination.")?;
    let destination = Coordinate::new(destination.x as u16, destination.y as u16);
    if !carrying {
        let pickup = usize::from(
            scenario
                .supply_crates
                .iter()
                .any(|cargo| cargo.position == destination),
        );
        let mut room = (truck.cargo_capacity() as usize)
            .saturating_sub(supplies::occupied_berths(scenario, truck) + pickup);
        // When troops could use a lift, leave a berth for mixed freight/transport.
        if transport::has_candidates(scenario, truck) {
            room = room.min(1);
        }
        if room > 0
            && let Some(depot) = scenario.depots.iter().find(|depot| {
                depot.position == destination
                    && depot.kind == resource
                    && (!depot.stock_visible || depot.stock.current > 0)
            })
        {
            let stock = if depot.stock_visible {
                depot.stock.current
            } else {
                supplies::rules().depot_capacity
            };
            let loads =
                (stock + supplies::rules().crate_capacity - 1) / supplies::rules().crate_capacity;
            order.load_crates = Some((room as i32).min(loads));
        }
    }
    Ok(Some(TruckPlan {
        mission: TruckMission::Deliver {
            resource,
            recipient: recipient.unit_id(),
        },
        score: score - journey * 2,
        order,
        dependent_orders: if waiting_for_supplies {
            vec![hold(recipient, recipient_origin)]
        } else {
            Vec::new()
        },
    }))
}

fn provisions_plan(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
) -> Result<Option<TruckPlan>, &'static str> {
    if truck.supplies().current() >= truck.supplies().maximum() / 2
        || truck
            .supply_cargo
            .iter()
            .any(|cargo| cargo.kind == DepotKind::Supply && cargo.current > 0)
    {
        return Ok(None);
    }
    let origin = truck
        .board_position()
        .ok_or("the AI truck is not on the map.")?;
    let blocked = blocked_tiles(scenario, truck, orders)?;
    let mut routes = Vec::new();
    for mut target in pickup_targets(scenario, DepotKind::Supply) {
        target.range = 1;
        if let Some(path) = path_to(scenario, truck, origin, target, &blocked)? {
            routes.push(path);
        }
    }
    routes.sort_by_key(|path| (path.len(), path.last().copied()));
    let Some(path) = routes.first() else {
        return Ok(None);
    };
    let mut order = hold(truck, origin);
    order.path = affordable_path(scenario, truck, path, false)?
        .into_iter()
        .map(coordinate_input)
        .collect();
    Ok(Some(TruckPlan {
        mission: TruckMission::SelfResupply,
        score: 700,
        order,
        dependent_orders: Vec::new(),
    }))
}

fn fuel_sources(
    scenario: &Scenario,
    vehicle: &Unit,
    orders: &[MoveOrderInput],
) -> Result<Vec<Destination>, &'static str> {
    let mut sources = pickup_targets(scenario, DepotKind::Fuel);
    for source in &mut sources {
        source.range = 1;
    }
    for truck in scenario.units.iter().filter(|unit| {
        unit.player_number() == vehicle.player_number()
            && unit.kind() == UnitKind::Truck
            && unit.board_position().is_some()
    }) {
        let stock: i32 = truck
            .supply_cargo
            .iter()
            .filter(|cargo| cargo.kind == DepotKind::Fuel)
            .map(|cargo| cargo.current)
            .sum();
        let order = orders
            .iter()
            .find(|order| order.unit_id == truck.id())
            .ok_or("the AI truck has no order.")?;
        let cost = order.path.len().saturating_sub(1) as i32
            * truck.fuel_movement_per_tile(scenario.passenger_count(truck.unit_id()));
        let deficit = truck
            .fuel()
            .map_or(0, |fuel| fuel.maximum - fuel.current + cost);
        // Do not promise a delivery that the carrier itself will consume.
        if stock > deficit {
            sources.push(Destination {
                position: planned_destination(orders, truck)?,
                range: 1,
            });
        }
    }
    Ok(sources)
}

fn protect_reserve(
    scenario: &Scenario,
    vehicle: &Unit,
    orders: &mut [MoveOrderInput],
) -> Result<bool, &'static str> {
    let fuel = vehicle.fuel().ok_or("the AI vehicle has no fuel.")?;
    let origin = vehicle
        .board_position()
        .ok_or("the AI vehicle is not on the map.")?;
    let sources = fuel_sources(scenario, vehicle, orders)?;
    // Maps without fuel sources still allow combat; there is no return trip to reserve.
    if sources.is_empty() {
        return Ok(false);
    }
    let end = planned_destination(orders, vehicle)?;
    let order = orders
        .iter()
        .find(|order| order.unit_id == vehicle.id())
        .ok_or("the AI vehicle has no order.")?;
    if vehicle.kind() == UnitKind::Truck && order.path.len() == 1 {
        return Ok(false);
    }
    let per_tile = vehicle.fuel_movement_per_tile(scenario.passenger_count(vehicle.unit_id()));
    let remaining = fuel.current - order.path.len().saturating_sub(1) as i32 * per_tile;
    let mut reserve = None;
    for source in &sources {
        if let Some(path) = path_to(scenario, vehicle, end, *source, &BTreeSet::new())? {
            let cost = path.len().saturating_sub(1) as i32 * per_tile;
            reserve = Some(reserve.map_or(cost, |known: i32| known.min(cost)));
        }
    }
    let tank_needs_fuel = vehicle.kind() == UnitKind::Tank && fuel.current < fuel.maximum / 2;
    if !tank_needs_fuel && reserve.is_some_and(|cost| remaining >= cost) {
        return Ok(false);
    }
    let blocked = blocked_tiles(scenario, vehicle, orders)?;
    let mut routes = Vec::new();
    for source in sources {
        if let Some(path) = path_to(scenario, vehicle, origin, source, &blocked)?
            && path.len().saturating_sub(1) as i32 * per_tile <= fuel.current
        {
            routes.push(path);
        }
    }
    routes.sort_by_key(|path| (path.len(), path.last().copied()));
    let mut replacement = hold(vehicle, origin);
    if let Some(path) = routes.first() {
        replacement.path = affordable_path(scenario, vehicle, path, false)?
            .into_iter()
            .map(coordinate_input)
            .collect();
    }
    replace_order(orders, vehicle, replacement)?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::{self, Difficulty},
        map_definition::MapDefinition,
        supplies::{CargoStock, GroundSupplyCrate},
        test_support::{FixtureValue, TestResult},
        turns::Turns,
        visibility,
    };

    fn convoy_fixture(player: PlayerNumber) -> TestResult<Scenario> {
        let mut definition = MapDefinition::parse(r#"{
            "width": 42, "height": 5, "theme": "GreenForest", "features": [],
            "depots": [
                {"position": {"x": 1, "y": 1}, "kind": "Fuel"},
                {"position": {"x": 30, "y": 2}, "kind": "Supply"}
            ],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 1}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
                {"id": 2, "position": {"x": 1, "y": 1}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 3, "position": {"x": 41, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?;
        if player == PlayerNumber::Player2 {
            for unit in &mut definition.units {
                unit.player_number = match unit.player_number {
                    PlayerNumber::Player1 => PlayerNumber::Player2,
                    PlayerNumber::Player2 => PlayerNumber::Player1,
                };
                unit.position =
                    Coordinate::new(41 - unit.position.x() as u16, unit.position.y() as u16);
            }
            for depot in &mut definition.depots {
                depot.position =
                    Coordinate::new(41 - depot.position.x() as u16, depot.position.y() as u16);
            }
        }
        definition.scenario().fixture()
    }

    fn resolve_turn(
        scenario: &mut Scenario,
        turns: &mut Turns,
        player: PlayerNumber,
        difficulty: Difficulty,
    ) -> TestResult {
        let number = turns.number;
        let orders = ai::plan_with_difficulty(scenario, player, difficulty).fixture()?;
        let enemy = if player == PlayerNumber::Player1 {
            PlayerNumber::Player2
        } else {
            PlayerNumber::Player1
        };
        let holds = scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() == enemy)
            .map(|unit| Ok(hold(unit, unit.board_position().fixture()?)))
            .collect::<TestResult<Vec<_>>>()?;
        turns.submit(scenario, player, number, orders).fixture()?;
        turns.submit(scenario, enemy, number, holds).fixture()?;
        Ok(())
    }

    #[test]
    fn loads_fuel_and_refuels_a_tank_beyond_its_unassisted_range() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                let mut scenario = convoy_fixture(player)?;
                let mut turns = Turns::default();
                let mut loaded = false;
                let mut delivered = false;
                let mut furthest = 0;
                for _ in 0..12 {
                    let before = scenario
                        .units
                        .iter()
                        .find(|unit| unit.kind() == UnitKind::Tank)
                        .fixture()?
                        .fuel()
                        .fixture()?
                        .current;
                    resolve_turn(&mut scenario, &mut turns, player, difficulty)?;
                    let tank = scenario
                        .units
                        .iter()
                        .find(|unit| unit.kind() == UnitKind::Tank)
                        .fixture()?;
                    let position = tank.board_position().fixture()?;
                    let progress = match player {
                        PlayerNumber::Player1 => position.x(),
                        PlayerNumber::Player2 => 41 - position.x(),
                    };
                    furthest = furthest.max(progress);
                    delivered |= progress > 2 && tank.fuel().fixture()?.current > before;
                    loaded |= scenario.units.iter().any(|unit| {
                        unit.kind() == UnitKind::Truck
                            && unit
                                .supply_cargo
                                .iter()
                                .any(|cargo| cargo.kind == DepotKind::Fuel)
                    });
                    assert!(
                        tank.fuel().fixture()?.current > 0,
                        "{difficulty:?} stranded its tank at {position:?}"
                    );
                }
                assert!(loaded, "{difficulty:?} never loaded fuel");
                assert!(delivered, "{difficulty:?} never refueled in the field");
                assert!(furthest > 18, "{difficulty:?} only reached {furthest}");
            }
        }
        Ok(())
    }

    #[test]
    fn unsupported_tank_returns_before_spending_its_return_fuel() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = convoy_fixture(PlayerNumber::Player1)?;
            scenario.units.retain(|unit| unit.kind() != UnitKind::Truck);
            let mut turns = Turns::default();
            let mut advanced = false;
            let mut returned = false;
            for _ in 0..8 {
                resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
                let tank = scenario
                    .units
                    .iter()
                    .find(|unit| unit.kind() == UnitKind::Tank)
                    .fixture()?;
                let position = tank.board_position().fixture()?;
                advanced |= position.x() > 2;
                returned |= advanced && position.x() <= 2;
                assert!(
                    tank.fuel().fixture()?.current > 0,
                    "{difficulty:?} ran dry returning home"
                );
            }
            assert!(
                advanced && returned,
                "{difficulty:?} did not make a safe sortie"
            );
        }
        Ok(())
    }

    #[test]
    fn collects_ground_fuel_and_loads_partial_depot_stock() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = convoy_fixture(PlayerNumber::Player1)?;
            scenario.depots.first_mut().fixture()?.stock.current = 19;
            scenario.supply_crates.push(GroundSupplyCrate {
                position: Coordinate::new(1, 1),
                stock: CargoStock::new(DepotKind::Fuel, 23),
            });
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            let truck_order = orders.iter().find(|order| order.unit_id == "2").fixture()?;
            assert_eq!(truck_order.load_crates, Some(1));
            let mut turns = Turns::default();
            resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
            let truck = scenario
                .units
                .iter()
                .find(|unit| unit.kind() == UnitKind::Truck)
                .fixture()?;
            assert_eq!(truck.supply_cargo.len(), 2);
            assert_eq!(
                truck
                    .supply_cargo
                    .iter()
                    .map(|cargo| cargo.current)
                    .sum::<i32>(),
                42
            );
        }
        Ok(())
    }

    #[test]
    fn carries_supplies_to_infantry_when_no_tanks_need_an_escort() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = MapDefinition::parse(r#"{
                "width": 20, "height": 5, "theme": "GreenForest", "features": [],
                "depots": [{"position": {"x": 1, "y": 1}, "kind": "Supply"}],
                "units": [
                    {"id": 1, "position": {"x": 10, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                    {"id": 2, "position": {"x": 1, "y": 1}, "playerNumber": "Player1", "kind": "Truck"},
                    {"id": 3, "position": {"x": 19, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
                ]
            }"#).fixture()?.scenario().fixture()?;
            scenario
                .units
                .first_mut()
                .fixture()?
                .set_supplies_for_test(64);
            let mut turns = Turns::default();
            resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
            let before = scenario.units.first().fixture()?.supplies().current();
            let mut delivered = false;
            for _ in 0..3 {
                resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
                let infantry = scenario.units.first().fixture()?;
                delivered |= infantry.board_position().fixture()?.x() > 2
                    && infantry.supplies().current() > before;
            }
            assert!(delivered, "{difficulty:?} did not deliver provisions");
        }
        Ok(())
    }

    #[test]
    fn unreachable_fuel_across_mountains_does_not_justify_an_advance() -> TestResult {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 8, "height": 5, "theme": "GreenForest",
            "features": [
                {"position": {"x": 4, "y": 0}, "terrain": "Mountains"},
                {"position": {"x": 4, "y": 1}, "terrain": "Mountains"},
                {"position": {"x": 4, "y": 2}, "terrain": "Mountains"},
                {"position": {"x": 4, "y": 3}, "terrain": "Mountains"}
            ],
            "depots": [{"position": {"x": 6, "y": 1}, "kind": "Fuel"}],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 1}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
                {"id": 2, "position": {"x": 7, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        scenario.units.first_mut().fixture()?.set_fuel_for_test(32);
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            assert_eq!(orders.first().fixture()?.path.len(), 1);
        }
        Ok(())
    }

    #[test]
    fn hidden_ground_fuel_does_not_change_logistics_orders() -> TestResult {
        let scenario = convoy_fixture(PlayerNumber::Player1)?;
        let mut changed = scenario.clone();
        let hidden = Coordinate::new(35, 0);
        assert!(!visibility::visible_tiles(&scenario, PlayerNumber::Player1).contains(&hidden));
        changed.supply_crates.push(GroundSupplyCrate {
            position: hidden,
            stock: CargoStock::new(DepotKind::Fuel, 256),
        });
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let original =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            let other =
                ai::plan_with_difficulty(&changed, PlayerNumber::Player1, difficulty).fixture()?;
            assert_eq!(
                serde_json::to_value(original).fixture()?,
                serde_json::to_value(other).fixture()?
            );
        }
        Ok(())
    }

    #[test]
    fn fuel_escort_replenishes_its_own_provisions_before_resuming_delivery() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = convoy_fixture(PlayerNumber::Player1)?;
            let truck = scenario
                .units
                .iter_mut()
                .find(|unit| unit.kind() == UnitKind::Truck)
                .fixture()?;
            truck.move_to(Coordinate::new(29, 2));
            truck.set_supplies_for_test(8);
            truck
                .supply_cargo
                .push(CargoStock::new(DepotKind::Fuel, 256));
            let mut turns = Turns::default();
            resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
            let truck = scenario
                .units
                .iter()
                .find(|unit| unit.kind() == UnitKind::Truck)
                .fixture()?;
            assert_eq!(
                truck.supplies().current(),
                truck.supplies().maximum() - truck.supplies().upkeep_per_turn()
            );
            assert!(
                truck
                    .supply_cargo
                    .iter()
                    .any(|cargo| cargo.kind == DepotKind::Fuel && cargo.current > 0)
            );
        }
        Ok(())
    }

    #[test]
    fn urgent_provisions_outrank_a_healthy_tank_and_other_trucks_take_other_jobs() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = MapDefinition::parse(r#"{
                "width": 24, "height": 7, "theme": "GreenForest", "features": [],
                "depots": [
                    {"position": {"x": 1, "y": 3}, "kind": "Supply"},
                    {"position": {"x": 1, "y": 2}, "kind": "Fuel"}
                ],
                "units": [
                    {"id": 1, "position": {"x": 1, "y": 3}, "playerNumber": "Player1", "kind": "Truck"},
                    {"id": 2, "position": {"x": 1, "y": 2}, "playerNumber": "Player1", "kind": "Truck"},
                    {"id": 3, "position": {"x": 5, "y": 3}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
                    {"id": 4, "position": {"x": 9, "y": 3}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                    {"id": 5, "position": {"x": 23, "y": 6}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
                ]
            }"#).fixture()?.scenario().fixture()?;
            scenario
                .units
                .iter_mut()
                .find(|unit| unit.id() == "4")
                .fixture()?
                .set_supplies_for_test(28);
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            assert!(
                orders
                    .iter()
                    .find(|order| order.unit_id == "1")
                    .fixture()?
                    .load_crates
                    .is_some()
            );
            assert!(
                orders
                    .iter()
                    .find(|order| order.unit_id == "2")
                    .fixture()?
                    .load_crates
                    .is_some()
            );
            assert_eq!(
                orders
                    .iter()
                    .find(|order| order.unit_id == "4")
                    .fixture()?
                    .path
                    .len(),
                1
            );
            let mut turns = Turns::default();
            for _ in 0..5 {
                resolve_turn(&mut scenario, &mut turns, PlayerNumber::Player1, difficulty)?;
            }
            assert!(
                scenario
                    .units
                    .iter()
                    .find(|unit| unit.id() == "4")
                    .fixture()?
                    .supplies()
                    .current()
                    > 28
            );
        }
        Ok(())
    }
}
