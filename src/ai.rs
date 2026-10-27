//! Deterministic, fog-limited opponent. Produces ordinary orders; Turns remains
//! responsible for validation, combat, resource costs and victory.
use crate::{
    combat,
    map::Coordinate,
    movement,
    scenario::{Direction, PlayerNumber, ResourceKind, Scenario, Unit, UnitKind},
    turns::{CoordinateInput, MoveOrderInput},
    visibility,
};
use std::collections::{BTreeMap, BTreeSet};

mod logistics;
mod search;
mod transport;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Difficulty {
    Easy,
    Medium,
    Hard,
}

pub fn plan_with_difficulty(
    scenario: &Scenario,
    player: PlayerNumber,
    difficulty: Difficulty,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    match difficulty {
        Difficulty::Easy => plan(scenario, player),
        Difficulty::Medium => search::plan_medium(scenario, player),
        Difficulty::Hard => search::plan_hard(scenario, player),
    }
}

pub fn plan(
    scenario: &Scenario,
    player: PlayerNumber,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    let visible = visibility::visible_tiles(scenario, player);
    let observed = visibility::observed_scenario(scenario, player, &visible);
    let mut reserved = BTreeSet::new();
    let mut orders = Vec::new();
    for unit in observed
        .units
        .iter()
        .filter(|unit| unit.player_number() == player)
    {
        let origin = observed
            .physical_position(unit)
            .ok_or("the AI unit has no position.")?;
        let mut order = hold(unit, origin);
        if unit.carrier_id().is_none() {
            let enemy = observed
                .units
                .iter()
                .filter(|enemy| enemy.player_number() != player && enemy.board_position().is_some())
                .filter_map(|enemy| enemy.board_position())
                .min_by_key(|position| (distance(origin, *position), *position));
            let rules = combat::rules(unit.kind());
            let ready = unit.supplies().current()
                >= unit.supplies().upkeep_per_turn() + rules.readiness_cost + rules.shot_cost;
            let resupply = resource_target(&observed, unit, origin);
            if let Some(target) = enemy.filter(|target| {
                unit.kind() == UnitKind::FieldGun
                    && ready
                    && combat::within_indirect_range(origin, *target, rules.indirect_range)
            }) {
                order.indirect_fire = Some(coordinate_input(target));
            } else {
                let target = resupply
                    .or(enemy.filter(|_| unit.kind() != UnitKind::Truck))
                    .unwrap_or_else(|| objective(&observed, origin));
                let attack = resupply.is_none()
                    && ready
                    && match unit.kind() {
                        UnitKind::Infantry | UnitKind::Tank => true,
                        UnitKind::FieldGun | UnitKind::Truck => false,
                    };
                let path = route(&observed, unit, target, &reserved, attack)?;
                if path.len() > 1 {
                    if attack {
                        order.attack_move = Some(true);
                        order.direction = path
                            .windows(2)
                            .last()
                            .and_then(|step| Direction::between(step[0], step[1]));
                    }
                    order.path = path.into_iter().map(coordinate_input).collect();
                } else if ready && unit.kind() != UnitKind::Truck {
                    order.ambush = Some(true);
                    order.direction = Some(facing(origin, target));
                }
            }
        }
        if let Some(destination) = order.path.last() {
            reserved.insert(Coordinate::new(destination.x as u16, destination.y as u16));
        }
        orders.push(order);
    }
    logistics::support(&observed, player, &mut orders)?;
    Ok(orders)
}

fn hold(unit: &Unit, origin: Coordinate) -> MoveOrderInput {
    MoveOrderInput {
        unit_id: unit.id(),
        path: vec![coordinate_input(origin)],
        direction: None,
        ambush: None,
        stand_ground: None,
        dig_in: None,
        sabotage: None,
        indirect_fire: None,
        attack_move: None,
        unloads: None,
        load_crates: None,
        pickup_ground_freight: None,
        crate_unloads: None,
    }
}

fn coordinate_input(position: Coordinate) -> CoordinateInput {
    CoordinateInput {
        x: position.x(),
        y: position.y(),
    }
}

fn distance(a: Coordinate, b: Coordinate) -> i32 {
    (a.x() - b.x()).abs() + (a.y() - b.y()).abs()
}

fn facing(origin: Coordinate, target: Coordinate) -> Direction {
    let dx = target.x() - origin.x();
    let dy = target.y() - origin.y();
    if dx.abs() >= dy.abs() {
        if dx < 0 {
            Direction::West
        } else {
            Direction::East
        }
    } else if dy < 0 {
        Direction::North
    } else {
        Direction::South
    }
}

fn resource_target(scenario: &Scenario, unit: &Unit, origin: Coordinate) -> Option<Coordinate> {
    let kind = if unit.supplies().current() < unit.supplies().maximum() / 2 {
        ResourceKind::Supply
    } else if unit
        .fuel()
        .is_some_and(|fuel| fuel.current < fuel.maximum / 2)
    {
        ResourceKind::Fuel
    } else {
        return None;
    };
    scenario
        .depots
        .iter()
        // Unknown stock is not knowledge of an empty or full source.
        .filter(|depot| {
            !depot.is_destroyed()
                && depot.kind.resource_kind() == Some(kind)
                && (!depot.stock_visible || depot.stock.current > 0)
        })
        .map(|depot| depot.position)
        .min_by_key(|position| (distance(origin, *position), *position))
}

fn objective(scenario: &Scenario, origin: Coordinate) -> Coordinate {
    let center = Coordinate::new(
        (scenario.map.width() / 2) as u16,
        (scenario.map.height() / 2) as u16,
    );
    scenario
        .depots
        .iter()
        .filter(|depot| {
            !depot.is_destroyed() && depot.kind.resource_kind() == Some(ResourceKind::Supply)
        })
        .map(|depot| depot.position)
        .min_by_key(|position| {
            (
                distance(center, *position),
                distance(origin, *position),
                *position,
            )
        })
        .unwrap_or(center)
}

/// Search beyond this turn's budget so routes can go around forests, mountains
/// and friendly formations. Take only an affordable prefix of the chosen route.
fn route(
    scenario: &Scenario,
    unit: &Unit,
    target: Coordinate,
    reserved: &BTreeSet<Coordinate>,
    attack: bool,
) -> Result<Vec<Coordinate>, &'static str> {
    let origin = unit
        .board_position()
        .ok_or("the AI mover is not on the map.")?;
    let rule = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == unit.kind())
        .ok_or("the AI unit has no movement rule.")?;
    let occupied: BTreeSet<_> = scenario
        .units
        .iter()
        .filter(|other| other.unit_id() != unit.unit_id())
        .filter(|other| other.player_number() == unit.player_number() || !attack)
        .filter_map(Unit::board_position)
        .collect();
    let mut costs = BTreeMap::from([(origin, 0)]);
    let mut parents = BTreeMap::new();
    let mut pending = BTreeSet::from([(0, origin)]);
    while let Some((cost, position)) = pending.pop_first() {
        if costs.get(&position) != Some(&cost) {
            continue;
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
            if occupied.contains(&next) || reserved.contains(&next) {
                continue;
            }
            let Some(terrain) = scenario.map.tile_at(next) else {
                continue;
            };
            let Some(entry) = rule
                .terrain_costs
                .iter()
                .find(|entry| entry.terrain == terrain && entry.cost > 0)
            else {
                continue;
            };
            let total = cost + entry.cost;
            if costs.get(&next).is_none_or(|previous| total < *previous) {
                costs.insert(next, total);
                parents.insert(next, position);
                pending.insert((total, next));
            }
        }
    }
    let destination = costs
        .iter()
        .min_by_key(|(position, cost)| (distance(**position, target), **cost, **position))
        .map(|(position, _)| *position)
        .ok_or("the AI route has no origin.")?;
    let mut path = vec![destination];
    let mut cursor = destination;
    while cursor != origin {
        cursor = *parents.get(&cursor).ok_or("the AI route is incomplete.")?;
        path.push(cursor);
    }
    path.reverse();
    affordable_path(scenario, unit, &path, attack)
}

fn affordable_path(
    scenario: &Scenario,
    unit: &Unit,
    path: &[Coordinate],
    attack: bool,
) -> Result<Vec<Coordinate>, &'static str> {
    let origin = unit
        .board_position()
        .ok_or("the AI mover is not on the map.")?;
    let rule = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == unit.kind())
        .ok_or("the AI unit has no movement rule.")?;
    let mut affordable = vec![origin];
    let mut terrain_cost = 0;
    let combat = combat::rules(unit.kind());
    let firing_cost = if attack {
        combat.readiness_cost + combat.shot_cost
    } else {
        0
    };
    for next in path.iter().copied().skip(1) {
        let terrain = scenario
            .map
            .tile_at(next)
            .ok_or("the AI route leaves the map.")?;
        let entry = rule
            .terrain_costs
            .iter()
            .find(|entry| entry.terrain == terrain && entry.cost > 0)
            .ok_or("the AI route crosses impassable terrain.")?;
        terrain_cost += entry.cost;
        affordable.push(next);
        let movement_cost = unit.supplies().movement_cost(&scenario.map, &affordable);
        let fuel_cost = unit.fuel_movement_cost(
            &scenario.map,
            &affordable,
            scenario.passenger_count(unit.unit_id()),
        );
        let over_budget = terrain_cost > rule.budget;
        let over_supplies = movement_cost + firing_cost
            > (unit.supplies().current() - unit.supplies().upkeep_per_turn()).max(0);
        let over_fuel = unit.fuel().is_some_and(|fuel| fuel_cost > fuel.current);
        if over_budget || over_supplies || over_fuel {
            affordable.pop();
            break;
        }
    }
    Ok(affordable)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::Map,
        map_id::MapId,
        test_support::{FixtureValue, TestResult},
        turns::{self, Turns},
    };

    #[test]
    fn all_difficulties_keep_every_unit_on_its_water_island() -> TestResult {
        for kind in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::Truck,
            UnitKind::FieldGun,
        ] {
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario.map = Map::from_ascii(".~.").fixture()?;
            scenario.depots.clear();
            scenario.units.retain(|unit| unit.kind() == kind);
            for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                let mut retained = false;
                scenario.units.retain(|unit| {
                    if unit.player_number() != player {
                        return true;
                    }
                    if retained {
                        return false;
                    }
                    retained = true;
                    true
                });
            }
            for unit in &mut scenario.units {
                let x = if unit.player_number() == PlayerNumber::Player1 {
                    0
                } else {
                    2
                };
                unit.move_to(Coordinate::new(x, 0));
            }
            for difficulty in [Difficulty::Easy, Difficulty::Medium, Difficulty::Hard] {
                let inputs =
                    plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
                let orders = turns::validate(&scenario, PlayerNumber::Player1, inputs).fixture()?;
                assert!(
                    orders
                        .iter()
                        .all(|order| order.path == [Coordinate::new(0, 0)]),
                    "{difficulty:?} {kind:?} crossed water"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn every_map_plays_valid_turns_through_completion() -> TestResult {
        // Keep this bounded AI regression sample independent of catalog growth.
        for name in [
            "supply-point",
            "el-alamein",
            "blood-gulch",
            "sidewinder",
            "black-forest",
            "crossroads",
            "ridgeway",
            "three-crossings",
            "lake-of-pennsylvania",
            "convoy-country",
            "tobruk",
            "bastion-pass",
        ] {
            let map = MapId::parse(name.into())?;
            let mut scenario = map.scenario().fixture()?;
            let mut turns = Turns::default();
            for _ in 0..160 {
                if turns.outcome.is_some() {
                    break;
                }
                let number = turns.number;
                for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                    let inputs = plan(&scenario, player).fixture()?;
                    turns
                        .submit(&mut scenario, player, number, inputs)
                        .map_err(|error| format!("{map:?}, turn {number}, {player:?}: {error}"))?;
                }
            }
            assert!(turns.outcome.is_some(), "{map:?} did not finish");
        }
        Ok(())
    }

    #[test]
    fn concealed_enemy_changes_do_not_change_orders() -> TestResult {
        let scenario = Scenario::supply_point().fixture()?;
        let mut changed = scenario.clone();
        let hidden = visibility::visible_tiles(&scenario, PlayerNumber::Player2);
        changed.units.retain(|unit| {
            unit.player_number() == PlayerNumber::Player2
                || unit
                    .board_position()
                    .is_some_and(|position| hidden.contains(&position))
        });
        // Initial enemy forces are concealed; removing them must not affect planning.
        assert!(changed.units.len() < scenario.units.len());
        let original = turns::validate(
            &scenario,
            PlayerNumber::Player2,
            plan(&scenario, PlayerNumber::Player2).fixture()?,
        )
        .fixture()?;
        let other = turns::validate(
            &changed,
            PlayerNumber::Player2,
            plan(&changed, PlayerNumber::Player2).fixture()?,
        )
        .fixture()?;
        assert_eq!(format!("{original:?}"), format!("{other:?}"));
        Ok(())
    }

    #[test]
    fn visible_enemies_take_damage_from_combat_units() -> TestResult {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            let mut scenario = Scenario::supply_point().fixture()?;
            let attacker = scenario
                .units
                .iter()
                .find(|unit| unit.player_number() == PlayerNumber::Player2 && unit.kind() == kind)
                .fixture()?
                .unit_id();
            let defender = scenario
                .units
                .iter()
                .find(|unit| {
                    unit.player_number() == PlayerNumber::Player1
                        && unit.kind() == UnitKind::Infantry
                })
                .fixture()?
                .unit_id();
            scenario
                .units
                .retain(|unit| unit.unit_id() == attacker || unit.unit_id() == defender);
            scenario.map =
                crate::map::Map::from_ascii("........\n........\n........\n........").fixture()?;
            scenario.depots.clear();
            for unit in &mut scenario.units {
                let position = if unit.unit_id() == attacker {
                    Coordinate::new(2, 2)
                } else {
                    Coordinate::new(3, 2)
                };
                unit.move_to(position);
            }
            let mut turns = Turns::default();
            let ai_orders = plan(&scenario, PlayerNumber::Player2).fixture()?;
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, ai_orders)
                .fixture()?;
            let human = scenario
                .units
                .iter()
                .find(|unit| unit.unit_id() == defender)
                .fixture()?;
            let human_order = hold(human, human.board_position().fixture()?);
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, vec![human_order])
                .fixture()?;
            let resolution = turns.last_resolution.as_ref().fixture()?;
            assert!(
                resolution
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .any(|shot| shot.damage > 0),
                "{kind:?} did not attack"
            );
        }
        Ok(())
    }

    #[test]
    fn exhausted_units_can_hold_and_do_not_overspend() -> TestResult {
        let mut scenario = Scenario::supply_point().fixture()?;
        for unit in &mut scenario.units {
            unit.set_supplies_for_test(1);
            unit.set_fuel_for_test(0);
        }
        let orders = turns::validate(
            &scenario,
            PlayerNumber::Player2,
            plan(&scenario, PlayerNumber::Player2).fixture()?,
        )
        .fixture()?;
        assert!(orders.iter().all(|order| order.path.len() == 1));
        Ok(())
    }
}
