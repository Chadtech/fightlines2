//! Passenger missions use the same fog-limited goals and ordinary transport orders.
use super::{
    affordable_path, coordinate_input, distance, facing, hold,
    logistics::{self, Destination, TruckMission, TruckPlan},
    resource_target, search,
};
use crate::{
    combat,
    map::Coordinate,
    movement,
    scenario::{DepotKind, Entrenchment, Scenario, Unit, UnitKind},
    supplies,
    turns::{self, MoveOrderInput, UnloadOrderInput},
};
use std::collections::BTreeSet;

fn eligible(unit: &Unit, truck: &Unit) -> bool {
    unit.player_number() == truck.player_number()
        && unit.board_position().is_some()
        && unit.entrenchment() == Entrenchment::Exposed
        && match unit.kind() {
            UnitKind::Infantry | UnitKind::FieldGun => true,
            UnitKind::Tank | UnitKind::Truck => false,
        }
        && unit.supplies().current()
            >= unit.supplies().upkeep_per_turn() + unit.supplies().movement_per_tile()
}

pub(super) fn has_candidates(scenario: &Scenario, truck: &Unit) -> bool {
    scenario.units.iter().any(|unit| eligible(unit, truck))
}

fn goal(scenario: &Scenario, passenger: &Unit) -> Result<Destination, &'static str> {
    let origin = scenario
        .physical_position(passenger)
        .ok_or("the AI passenger has no position.")?;
    let resupply = resource_target(scenario, passenger, origin);
    Ok(Destination {
        position: resupply.unwrap_or_else(|| search::strategic_target(scenario, passenger, origin)),
        range: if resupply.is_some() {
            1
        } else if passenger.kind() == UnitKind::FieldGun {
            6
        } else {
            2
        },
    })
}

fn threatened(scenario: &Scenario, passenger: &Unit, position: Coordinate) -> bool {
    scenario
        .units
        .iter()
        .filter(|unit| unit.player_number() != passenger.player_number())
        .any(|enemy| {
            enemy.board_position().is_some_and(|origin| {
                enemy.kind() != UnitKind::Truck
                    && distance(origin, position) <= combat::rules(enemy.kind()).range
            })
        })
}

fn safe_route_tiles(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
) -> Result<BTreeSet<Coordinate>, &'static str> {
    let mut blocked = logistics::blocked_tiles(scenario, truck, orders)?;
    for enemy in scenario.units.iter().filter(|unit| {
        unit.player_number() != truck.player_number() && unit.kind() != UnitKind::Truck
    }) {
        if let Some(origin) = enemy.board_position() {
            let range = combat::rules(enemy.kind()).range;
            for dy in -range..=range {
                for dx in -range..=range {
                    let x = origin.x() + dx;
                    let y = origin.y() + dy;
                    if x >= 0 && y >= 0 && dx.abs() + dy.abs() <= range {
                        let position = Coordinate::new(x as u16, y as u16);
                        if scenario.map.tile_at(position).is_some() {
                            blocked.insert(position);
                        }
                    }
                }
            }
        }
    }
    Ok(blocked)
}

fn travel_turns(
    scenario: &Scenario,
    unit: &Unit,
    path: &[Coordinate],
) -> Result<i32, &'static str> {
    let rule = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == unit.kind())
        .ok_or("the AI unit has no movement rule.")?;
    let mut turns = 0;
    let mut used = 0;
    for position in path.iter().skip(1) {
        let terrain = scenario
            .map
            .tile_at(*position)
            .ok_or("the AI transport route leaves the map.")?;
        let cost = rule
            .terrain_costs
            .iter()
            .find(|entry| entry.terrain == terrain && entry.cost > 0)
            .ok_or("the AI transport route is impassable.")?
            .cost;
        if used + cost > rule.budget {
            turns += 1;
            used = 0;
        }
        used += cost;
    }
    Ok(turns + i32::from(used > 0))
}

pub(super) fn pickups(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
    assigned: &[TruckMission],
) -> Result<Vec<TruckPlan>, &'static str> {
    if supplies::occupied_berths(scenario, truck) >= truck.cargo_capacity() as usize {
        return Ok(Vec::new());
    }
    let origin = truck
        .board_position()
        .ok_or("the AI truck is not on the map.")?;
    let mut passengers: Vec<_> = scenario
        .units
        .iter()
        .filter(|unit| {
            eligible(unit, truck)
                && !assigned.contains(&TruckMission::Transport(unit.unit_id()))
                && !assigned.contains(&TruckMission::Deliver {
                    resource: DepotKind::Supply,
                    recipient: unit.unit_id(),
                })
        })
        .collect();
    passengers.sort_by_key(|unit| {
        (
            unit.board_position()
                .map_or(i32::MAX, |position| distance(origin, position)),
            unit.unit_id(),
        )
    });
    let mut plans = Vec::new();
    let route_blocked = safe_route_tiles(scenario, truck, orders)?;
    for passenger in passengers.into_iter().take(4) {
        let original = orders
            .iter()
            .find(|order| order.unit_id == passenger.id())
            .ok_or("the AI passenger has no order.")?;
        if original.dig_in == Some(true) || original.indirect_fire.is_some() {
            continue;
        }
        let passenger_origin = passenger
            .board_position()
            .ok_or("the AI passenger is not on the map.")?;
        // Keep units already fighting on foot. Transport is for deployment,
        // rather than interrupting a useful shot or loading into a known threat.
        if threatened(scenario, passenger, passenger_origin) {
            continue;
        }
        let destination = goal(scenario, passenger)?;
        let Some(walking) = logistics::path_to(
            scenario,
            passenger,
            passenger_origin,
            destination,
            &BTreeSet::new(),
        )?
        else {
            continue;
        };
        let rendezvous = logistics::planned_destination(orders, passenger)?;
        let mut blocked = route_blocked.clone();
        if threatened(scenario, truck, rendezvous) {
            continue;
        }
        blocked.remove(&rendezvous);
        let Some(approach) = logistics::path_to(
            scenario,
            truck,
            origin,
            Destination {
                position: rendezvous,
                range: 0,
            },
            &blocked,
        )?
        else {
            continue;
        };
        let Some(ride) =
            logistics::path_to(scenario, truck, rendezvous, destination, &BTreeSet::new())?
        else {
            continue;
        };
        let pickup_turns = travel_turns(scenario, truck, &approach)?;
        let ride_turns = travel_turns(scenario, truck, &ride)?;
        let saved_turns =
            travel_turns(scenario, passenger, &walking)? - pickup_turns - ride_turns - 1;
        if saved_turns < 1 {
            continue;
        }
        let provisions: i32 = truck
            .supply_cargo
            .iter()
            .filter(|cargo| cargo.kind == DepotKind::Supply)
            .map(|cargo| cargo.current)
            .sum();
        let travel_upkeep =
            (pickup_turns + ride_turns + 1) * passenger.supplies().upkeep_per_turn();
        let unload_cost = passenger.supplies().movement_per_tile()
            + passenger.supplies().rough_terrain_surcharge();
        let boarding_cost = passenger.supplies().movement_cost(
            &scenario.map,
            &original
                .path
                .iter()
                .map(|position| Coordinate::new(position.x as u16, position.y as u16))
                .collect::<Vec<_>>(),
        );
        if passenger.supplies().current() + provisions < travel_upkeep + unload_cost + boarding_cost
        {
            continue;
        }
        let fuel = truck.fuel().ok_or("the AI truck has no fuel.")?;
        let aboard_cost = truck.fuel_movement_per_tile(scenario.passenger_count(truck.unit_id()));
        let pickup_fuel = approach.len().saturating_sub(1) as i32 * aboard_cost;
        let ride_fuel =
            ride.len().saturating_sub(1) as i32 * (aboard_cost + fuel.movement_per_cargo_slot);
        let carried_fuel: i32 = truck
            .supply_cargo
            .iter()
            .filter(|cargo| cargo.kind == DepotKind::Fuel)
            .map(|cargo| cargo.current)
            .sum();
        if pickup_fuel + ride_fuel > fuel.current + carried_fuel {
            continue;
        }
        let mut order = hold(truck, origin);
        let prefix = affordable_path(scenario, truck, &approach, false)?;
        let arrives = prefix.last() == Some(&rendezvous);
        order.path = prefix.into_iter().map(coordinate_input).collect();
        let mut passenger_orders = Vec::new();
        if arrives {
            let mut boarding = hold(passenger, passenger_origin);
            boarding.path = original.path.clone();
            passenger_orders.push(boarding);
            // Share a useful ride when another compatible unit can reach the
            // same boarding point this turn without changing the carrier route.
            let room = truck.cargo_capacity() as usize - supplies::occupied_berths(scenario, truck);
            for other in scenario.units.iter().filter(|unit| {
                eligible(unit, truck)
                    && unit.unit_id() != passenger.unit_id()
                    && !assigned.contains(&TruckMission::Transport(unit.unit_id()))
                    && !assigned.contains(&TruckMission::Deliver {
                        resource: DepotKind::Supply,
                        recipient: unit.unit_id(),
                    })
            }) {
                if passenger_orders.len() >= room {
                    break;
                }
                let additional_slots = passenger_orders.len() as i32 + 1;
                let shared_ride_fuel = ride.len().saturating_sub(1) as i32
                    * (aboard_cost + additional_slots * fuel.movement_per_cargo_slot);
                if pickup_fuel + shared_ride_fuel > fuel.current + carried_fuel {
                    break;
                }
                let other_origin = other
                    .board_position()
                    .ok_or("the AI passenger is not on the map.")?;
                let other_order = orders
                    .iter()
                    .find(|order| order.unit_id == other.id())
                    .ok_or("the AI passenger has no order.")?;
                if other_order.dig_in == Some(true)
                    || other_order.indirect_fire.is_some()
                    || threatened(scenario, other, other_origin)
                    || distance(goal(scenario, other)?.position, destination.position) > 6
                {
                    continue;
                }
                let mut blocked = logistics::blocked_tiles(scenario, other, orders)?;
                blocked.remove(&rendezvous);
                let Some(path) = logistics::path_to(
                    scenario,
                    other,
                    other_origin,
                    Destination {
                        position: rendezvous,
                        range: 0,
                    },
                    &blocked,
                )?
                else {
                    continue;
                };
                let prefix = affordable_path(scenario, other, &path, false)?;
                if prefix.last() == Some(&rendezvous) {
                    let reserved_provisions = (travel_upkeep + unload_cost + boarding_cost
                        - passenger.supplies().current())
                    .max(0);
                    let available =
                        other.supplies().current() + (provisions - reserved_provisions).max(0);
                    let needed = other.supplies().movement_cost(&scenario.map, &prefix)
                        + (ride_turns + 2) * other.supplies().upkeep_per_turn()
                        + other.supplies().movement_per_tile()
                        + other.supplies().rough_terrain_surcharge();
                    if available < needed {
                        continue;
                    }
                    let mut boarding = hold(other, other_origin);
                    boarding.path = prefix.into_iter().map(coordinate_input).collect();
                    passenger_orders.push(boarding);
                }
            }
        }
        plans.push(TruckPlan {
            mission: TruckMission::Transport(passenger.unit_id()),
            score: saved_turns * 35
                + if passenger.kind() == UnitKind::FieldGun {
                    25
                } else {
                    0
                }
                + passenger_orders.len().saturating_sub(1) as i32 * 25,
            order,
            dependent_orders: passenger_orders,
        });
    }
    Ok(plans)
}

pub(super) fn deployment(
    scenario: &Scenario,
    truck: &Unit,
    orders: &[MoveOrderInput],
) -> Result<TruckPlan, &'static str> {
    let origin = truck
        .board_position()
        .ok_or("the AI truck is not on the map.")?;
    let passengers: Vec<_> = scenario
        .units
        .iter()
        .filter(|unit| unit.carrier_id() == Some(truck.unit_id()))
        .collect();
    let primary = passengers
        .first()
        .copied()
        .ok_or("the AI transport has no passenger.")?;
    let destination = goal(scenario, primary)?;
    let blocked = safe_route_tiles(scenario, truck, orders)?;
    let route = logistics::path_to(scenario, truck, origin, destination, &blocked)?;
    let mut order = hold(truck, origin);
    if let Some(path) = &route {
        order.path = affordable_path(scenario, truck, path, false)?
            .into_iter()
            .map(coordinate_input)
            .collect();
    }
    let end = order
        .path
        .last()
        .ok_or("the AI transport has no destination.")?;
    let end = Coordinate::new(end.x as u16, end.y as u16);
    let arrived = distance(end, destination.position) <= destination.range;
    let stranded = truck.fuel().is_some_and(|fuel| {
        fuel.current < truck.fuel_movement_per_tile(scenario.passenger_count(truck.unit_id()))
    });
    let emergency = threatened(scenario, truck, origin) || stranded || route.is_none();
    let mut passenger_orders = Vec::new();
    if arrived || emergency {
        let mut reserved = logistics::blocked_tiles(scenario, truck, orders)?;
        reserved.insert(end);
        let mut unloads = Vec::new();
        for passenger in passengers {
            let mut exits = Vec::new();
            for (x, y) in [
                (end.x() - 1, end.y()),
                (end.x() + 1, end.y()),
                (end.x(), end.y() - 1),
                (end.x(), end.y() + 1),
            ] {
                if x < 0 || y < 0 {
                    continue;
                }
                let exit = Coordinate::new(x as u16, y as u16);
                if !reserved.contains(&exit)
                    && turns::legal_unload(scenario, passenger, exit, Some(truck.unit_id()))
                {
                    exits.push(exit);
                }
            }
            exits.sort_by_key(|exit| {
                (
                    threatened(scenario, passenger, *exit),
                    distance(*exit, destination.position),
                    *exit,
                )
            });
            if let Some(exit) = exits.first().copied() {
                reserved.insert(exit);
                unloads.push(UnloadOrderInput::new(passenger.unit_id(), exit));
                if passenger.kind() == UnitKind::Infantry {
                    let mut deployed = passenger.clone();
                    deployed.follow_terrain_path(&scenario.map, &[exit, exit], 0);
                    let mut action = hold(&deployed, exit);
                    let enemy = scenario
                        .units
                        .iter()
                        .filter(|unit| unit.player_number() != passenger.player_number())
                        .filter_map(Unit::board_position)
                        .min_by_key(|position| (distance(exit, *position), *position));
                    let rules = combat::rules(passenger.kind());
                    let ready = deployed.supplies().current()
                        >= deployed.supplies().upkeep_per_turn()
                            + rules.readiness_cost
                            + rules.shot_cost;
                    if let Some(enemy) = enemy
                        && ready
                    {
                        action.ambush = Some(true);
                        action.direction = Some(facing(exit, enemy));
                    }
                    passenger_orders.push(action);
                }
            }
        }
        if !unloads.is_empty() {
            order.unloads = Some(unloads);
        }
    }
    Ok(TruckPlan {
        mission: TruckMission::Transport(primary.unit_id()),
        score: 600,
        order,
        dependent_orders: passenger_orders,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::{self, Difficulty},
        map_definition::MapDefinition,
        scenario::PlayerNumber,
        supplies::CargoStock,
        test_support::{FixtureValue, TestResult},
        turns::Turns,
    };

    fn fixture(kind: UnitKind, player: PlayerNumber) -> TestResult<Scenario> {
        let mut definition = MapDefinition::parse(r#"{
            "width": 40, "height": 7, "theme": "GreenForest", "features": [],
            "depots": [{"position": {"x": 32, "y": 3}, "kind": "Supply"}],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 3}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 1, "y": 3}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 3, "position": {"x": 39, "y": 6}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?;
        definition.units.first_mut().fixture()?.kind = kind;
        if player == PlayerNumber::Player2 {
            for unit in &mut definition.units {
                unit.player_number = match unit.player_number {
                    PlayerNumber::Player1 => PlayerNumber::Player2,
                    PlayerNumber::Player2 => PlayerNumber::Player1,
                };
                unit.position =
                    Coordinate::new(39 - unit.position.x() as u16, unit.position.y() as u16);
            }
            for depot in &mut definition.depots {
                depot.position =
                    Coordinate::new(39 - depot.position.x() as u16, depot.position.y() as u16);
            }
        }
        definition.scenario().fixture()
    }

    fn resolve(
        scenario: &mut Scenario,
        turns: &mut Turns,
        player: PlayerNumber,
        orders: Vec<MoveOrderInput>,
    ) -> TestResult {
        let enemy = match player {
            PlayerNumber::Player1 => PlayerNumber::Player2,
            PlayerNumber::Player2 => PlayerNumber::Player1,
        };
        let holds = scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() == enemy)
            .map(|unit| Ok(hold(unit, scenario.physical_position(unit).fixture()?)))
            .collect::<TestResult<Vec<_>>>()?;
        let number = turns.number;
        turns.submit(scenario, player, number, orders).fixture()?;
        turns.submit(scenario, enemy, number, holds).fixture()?;
        Ok(())
    }

    #[test]
    fn picks_up_carries_and_deploys_both_passenger_kinds_on_both_sides() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                for kind in [UnitKind::Infantry, UnitKind::FieldGun] {
                    let mut scenario = fixture(kind, player)?;
                    let mut turns = Turns::default();
                    let mut boarded = false;
                    let mut deployed = false;
                    for _ in 0..12 {
                        let orders =
                            ai::plan_with_difficulty(&scenario, player, difficulty).fixture()?;
                        resolve(&mut scenario, &mut turns, player, orders)?;
                        let passenger = scenario
                            .units
                            .iter()
                            .find(|unit| unit.id() == "1")
                            .fixture()?;
                        boarded |= passenger.carrier_id().is_some();
                        if boarded && let Some(position) = passenger.board_position() {
                            let progress = match player {
                                PlayerNumber::Player1 => position.x(),
                                PlayerNumber::Player2 => 39 - position.x(),
                            };
                            assert!(
                                progress > 12,
                                "{difficulty:?} {kind:?} unloaded too early at {position:?}"
                            );
                            deployed = true;
                            break;
                        }
                    }
                    assert!(
                        boarded && deployed,
                        "{difficulty:?} {player:?} never transported {kind:?}"
                    );
                }
            }
        }
        Ok(())
    }

    #[test]
    fn mixes_one_freight_load_with_a_passenger_without_exceeding_capacity() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = fixture(UnitKind::FieldGun, PlayerNumber::Player1)?;
            scenario
                .units
                .iter_mut()
                .find(|unit| unit.kind() == UnitKind::Truck)
                .fixture()?
                .supply_cargo
                .push(CargoStock::new(DepotKind::Fuel, 256));
            let mut turns = Turns::default();
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
            let passenger = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .fixture()?;
            let truck = scenario
                .units
                .iter()
                .find(|unit| unit.kind() == UnitKind::Truck)
                .fixture()?;
            assert_eq!(passenger.carrier_id(), Some(truck.unit_id()));
            assert_eq!(supplies::occupied_berths(&scenario, truck), 2);
        }
        Ok(())
    }

    #[test]
    fn stranded_carrier_unloads_infantry_instead_of_holding_it_aboard() -> TestResult {
        let mut scenario = fixture(UnitKind::Infantry, PlayerNumber::Player1)?;
        let truck = scenario
            .units
            .iter_mut()
            .find(|unit| unit.kind() == UnitKind::Truck)
            .fixture()?;
        truck.set_fuel_for_test(0);
        let carrier = truck.unit_id();
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "1")
            .fixture()?
            .board(carrier);
        let mut turns = Turns::default();
        let orders = ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, Difficulty::Medium)
            .fixture()?;
        resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
        assert!(
            scenario
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .fixture()?
                .board_position()
                .is_some()
        );
        Ok(())
    }

    #[test]
    fn field_gun_can_fire_on_the_turn_after_deployment() -> TestResult {
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut scenario = fixture(UnitKind::FieldGun, PlayerNumber::Player1)?;
            let truck = scenario
                .units
                .iter_mut()
                .find(|unit| unit.id() == "2")
                .fixture()?;
            truck.move_to(Coordinate::new(23, 3));
            let carrier = truck.unit_id();
            scenario
                .units
                .iter_mut()
                .find(|unit| unit.id() == "1")
                .fixture()?
                .board(carrier);
            scenario
                .units
                .iter_mut()
                .find(|unit| unit.id() == "3")
                .fixture()?
                .move_to(Coordinate::new(28, 3));
            let mut turns = Turns::default();
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            assert!(
                orders
                    .iter()
                    .find(|order| order.unit_id == "1")
                    .fixture()?
                    .indirect_fire
                    .is_none()
            );
            resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
            assert!(
                scenario
                    .units
                    .iter()
                    .find(|unit| unit.id() == "1")
                    .fixture()?
                    .board_position()
                    .is_some()
            );
            let mut orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            let gun = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .fixture()?;
            let mut firing = hold(gun, gun.board_position().fixture()?);
            firing.indirect_fire = Some(coordinate_input(Coordinate::new(28, 3)));
            logistics::replace_order(&mut orders, gun, firing).fixture()?;
            resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
            assert!(
                turns
                    .last_resolution
                    .as_ref()
                    .fixture()?
                    .frames
                    .iter()
                    .any(|frame| !frame.indirect_impacts.is_empty()
                        || frame.shots.iter().any(|shot| shot.attacker.id() == "1"))
            );
        }
        Ok(())
    }

    #[test]
    fn two_passengers_share_a_ride_and_get_distinct_unload_squares() -> TestResult {
        let mut scenario = fixture(UnitKind::FieldGun, PlayerNumber::Player1)?;
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.kind() == UnitKind::Truck)
            .fixture()?
            .move_to(Coordinate::new(3, 2));
        // Author a second identity through the map definition, retaining normal resources.
        let extra = MapDefinition::parse(r#"{
            "width": 40, "height": 7, "theme": "GreenForest", "features": [], "depots": [],
            "units": [
                {"id": 4, "position": {"x": 3, "y": 4}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 5, "position": {"x": 39, "y": 6}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        scenario.units.push(extra.units.first().fixture()?.clone());
        let mut turns = Turns::default();
        let orders = ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, Difficulty::Medium)
            .fixture()?;
        let submitted = serde_json::to_string(&orders).fixture()?;
        resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
        let truck = scenario
            .units
            .iter()
            .find(|unit| unit.kind() == UnitKind::Truck)
            .fixture()?;
        assert_eq!(scenario.passenger_count(truck.unit_id()), 2, "{submitted}");
        for _ in 0..8 {
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, Difficulty::Medium)
                    .fixture()?;
            resolve(&mut scenario, &mut turns, PlayerNumber::Player1, orders)?;
            let first = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .fixture()?;
            let second = scenario
                .units
                .iter()
                .find(|unit| unit.id() == "4")
                .fixture()?;
            if let (Some(a), Some(b)) = (first.board_position(), second.board_position()) {
                assert_ne!(a, b);
                return Ok(());
            }
        }
        Err("the shared passengers never deployed".into())
    }

    #[test]
    fn later_delivery_trucks_respect_a_guns_reserved_unload_square() -> TestResult {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 14, "height": 7, "theme": "GreenForest",
            "features": [
                {"position": {"x": 6, "y": 2}, "terrain": "Water"},
                {"position": {"x": 6, "y": 4}, "terrain": "Water"}
            ],
            "depots": [{"position": {"x": 8, "y": 3}, "kind": "Supply"}],
            "units": [
                {"id": 1, "position": {"x": 3, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 4, "y": 0}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 3, "position": {"x": 6, "y": 3}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 4, "position": {"x": 2, "y": 3}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 5, "position": {"x": 13, "y": 6}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let carrier = scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "3")
            .fixture()?;
        carrier.set_fuel_for_test(14);
        let carrier = carrier.unit_id();
        for passenger in scenario
            .units
            .iter_mut()
            .filter(|unit| unit.id() == "1" || unit.id() == "2")
        {
            passenger.board(carrier);
        }
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "4")
            .fixture()?
            .supply_cargo
            .push(CargoStock::new(DepotKind::Fuel, 68));
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut board = scenario.clone();
            let orders =
                ai::plan_with_difficulty(&board, PlayerNumber::Player1, difficulty).fixture()?;
            let carrier_order = orders.iter().find(|order| order.unit_id == "3").fixture()?;
            let gun_exit = carrier_order
                .unloads
                .as_ref()
                .fixture()?
                .iter()
                .map(UnloadOrderInput::destination_coordinate)
                .collect::<Result<Vec<_>, _>>()
                .fixture()?;
            let arriving = board.units.iter().find(|unit| unit.id() == "4").fixture()?;
            assert!(
                !gun_exit.contains(&logistics::planned_destination(&orders, arriving).fixture()?)
            );
            let mut turns = Turns::default();
            resolve(&mut board, &mut turns, PlayerNumber::Player1, orders)?;
            assert!(
                board
                    .units
                    .iter()
                    .find(|unit| unit.id() == "2")
                    .fixture()?
                    .board_position()
                    .is_some()
            );
        }
        Ok(())
    }

    #[test]
    fn resupplying_a_carrier_preserves_its_infantry_dismount_command() -> TestResult {
        let mut scenario = fixture(UnitKind::Infantry, PlayerNumber::Player1)?;
        scenario.depots.clear();
        let carrier = scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "2")
            .fixture()?;
        carrier.move_to(Coordinate::new(23, 3));
        carrier.set_supplies_for_test(8);
        let carrier = carrier.unit_id();
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "1")
            .fixture()?
            .board(carrier);
        let extra = MapDefinition::parse(r#"{
            "width": 40, "height": 7, "theme": "GreenForest", "features": [], "depots": [],
            "units": [
                {"id": 4, "position": {"x": 20, "y": 1}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 5, "position": {"x": 39, "y": 6}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let mut donor = extra.units.first().fixture()?.clone();
        donor
            .supply_cargo
            .push(CargoStock::new(DepotKind::Supply, 256));
        scenario.units.push(donor);
        for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
            let mut board = scenario.clone();
            let orders =
                ai::plan_with_difficulty(&board, PlayerNumber::Player1, difficulty).fixture()?;
            assert!(
                !orders
                    .iter()
                    .find(|order| order.unit_id == "2")
                    .fixture()?
                    .unloads
                    .as_ref()
                    .fixture()?
                    .is_empty()
            );
            let mut turns = Turns::default();
            resolve(&mut board, &mut turns, PlayerNumber::Player1, orders)?;
            assert!(
                board
                    .units
                    .iter()
                    .find(|unit| unit.id() == "1")
                    .fixture()?
                    .board_position()
                    .is_some()
            );
            assert!(
                board
                    .units
                    .iter()
                    .find(|unit| unit.id() == "2")
                    .fixture()?
                    .supplies()
                    .current()
                    > 8
            );
        }
        Ok(())
    }
}
