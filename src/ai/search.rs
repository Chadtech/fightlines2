//! Bounded one-turn searches using the ordinary validator and resolver. Enemy
//! orders are modeled from observed state, never the human's actual plans.
use super::{coordinate_input, distance, facing, hold, objective, resource_target, route};
use crate::{
    combat,
    map::{Coordinate, Terrain},
    movement,
    scenario::{Direction, Entrenchment, PlayerNumber, Scenario, Unit, UnitId, UnitKind},
    supplies::ResourceStock,
    turns::{MoveOrderInput, Turns},
    visibility,
};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Tactics {
    Stationary,
    Counterplay,
}

/// Remaining terrain movement cost in half-points. Occupancy is handled by
/// route generation and the resolver, so a temporary ally cannot erase a goal.
struct StrategicGoal {
    target: Coordinate,
    costs: BTreeMap<Coordinate, i32>,
}

impl StrategicGoal {
    fn new(scenario: &Scenario, unit: &Unit) -> Result<Self, &'static str> {
        let origin = unit
            .board_position()
            .ok_or("the AI mover is not on the map.")?;
        let target = strategic_target(scenario, unit, origin);
        let rule = movement::rules()
            .into_iter()
            .find(|rule| rule.kind == unit.kind())
            .ok_or("the AI unit has no movement rule.")?;
        let entry_cost = |position| {
            scenario.map.tile_at(position).and_then(|terrain| {
                rule.terrain_costs
                    .iter()
                    .find(|entry| entry.terrain == terrain && entry.cost > 0)
                    .map(|entry| entry.cost)
            })
        };
        let mut reachable = BTreeSet::from([origin]);
        let mut pending = vec![origin];
        while let Some(position) = pending.pop() {
            for next in neighbors(position) {
                if entry_cost(next).is_some() && reachable.insert(next) {
                    pending.push(next);
                }
            }
        }
        // Authored scout coordinates (or enemies) can lie on impassable terrain
        // or another island. Aim for the closest tiles in our terrain component.
        let closest = reachable
            .iter()
            .map(|position| distance(*position, target))
            .min()
            .ok_or("the AI goal has no reachable terrain.")?;
        let resupplying = resource_target(scenario, unit, origin).is_some();
        let desired_distance = if !resupplying && unit.kind() == UnitKind::FieldGun {
            6
        } else {
            1
        };
        // Depot adjacency and artillery standoff are geometric ranges. Search
        // to that region, rather than subtracting a range from terrain costs.
        let arrival_distance = desired_distance.max(closest);
        let mut costs: BTreeMap<_, _> = reachable
            .iter()
            .filter(|position| distance(**position, target) <= arrival_distance)
            .map(|position| (*position, 0))
            .collect();
        let mut pending: BTreeSet<_> = costs.keys().map(|position| (0, *position)).collect();
        while let Some((cost, position)) = pending.pop_first() {
            if costs.get(&position) != Some(&cost) {
                continue;
            }
            // Reverse search pays entry into the current tile, not the tile
            // preceding it. This matters at forest and mountain boundaries.
            let step = entry_cost(position).ok_or("the AI goal is on impassable terrain.")?;
            for previous in neighbors(position) {
                if !reachable.contains(&previous) {
                    continue;
                }
                let total = cost + step;
                if costs.get(&previous).is_none_or(|known| total < *known) {
                    costs.insert(previous, total);
                    pending.insert((total, previous));
                }
            }
        }
        Ok(Self { target, costs })
    }

    fn cost(&self, position: Coordinate) -> Result<i32, &'static str> {
        self.costs
            .get(&position)
            .copied()
            .ok_or("the AI position is outside its goal's terrain component.")
    }
}

fn neighbors(position: Coordinate) -> impl Iterator<Item = Coordinate> {
    [
        (position.x() - 1, position.y()),
        (position.x() + 1, position.y()),
        (position.x(), position.y() - 1),
        (position.x(), position.y() + 1),
    ]
    .into_iter()
    .filter(|(x, y)| *x >= 0 && *y >= 0)
    .map(|(x, y)| Coordinate::new(x as u16, y as u16))
}

pub(super) fn plan_medium(
    scenario: &Scenario,
    player: PlayerNumber,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    plan(scenario, player, Tactics::Stationary)
}

pub(super) fn plan_hard(
    scenario: &Scenario,
    player: PlayerNumber,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    plan(scenario, player, Tactics::Counterplay)
}

fn plan(
    scenario: &Scenario,
    player: PlayerNumber,
    tactics: Tactics,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    let visible = visibility::visible_tiles(scenario, player);
    let mut observed = visibility::observed_scenario(scenario, player, &visible);
    // Projection hides gauges in GraphQL but retains their underlying values.
    // Replace them before any search, including combat and replenishment.
    for unit in &mut observed.units {
        if unit.player_number() != player {
            unit.assume_full_resources();
        }
    }
    for depot in &mut observed.depots {
        if !depot.stock_visible && depot.kind.resource_kind().is_some() {
            depot.stock = ResourceStock::depot();
        }
    }
    let own: Vec<_> = observed
        .units
        .iter()
        .filter(|unit| unit.player_number() == player)
        .collect();
    let mut orders = own
        .iter()
        .map(|unit| {
            observed
                .physical_position(unit)
                .map(|position| hold(unit, position))
                .ok_or("the AI unit has no position.")
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut responses = vec![defensive_orders(&observed, player)?];
    let counterplay = tactics == Tactics::Counterplay
        && observed
            .units
            .iter()
            .any(|unit| unit.player_number() != player);
    if counterplay {
        // Model an advancing opponent through the same fog-limited Easy policy.
        // This board has already discarded hidden units and private resources.
        responses.push(super::plan(&observed, opponent(player))?);
    }
    // Reuse terrain searches across every candidate simulation in this plan.
    let goals = own
        .iter()
        .filter(|unit| unit.board_position().is_some())
        .map(|unit| Ok((unit.unit_id(), StrategicGoal::new(&observed, unit)?)))
        .collect::<Result<BTreeMap<_, _>, &'static str>>()?;
    // Reserve the extra simulations for tactical coordination with observed
    // enemies; scouting uses a single response and pass.
    let passes = if counterplay { 2 } else { 1 };
    for pass in 0..passes {
        let mut reserved = BTreeSet::new();
        for (index, unit) in own.iter().enumerate() {
            if unit.carrier_id().is_some() {
                continue;
            }
            if pass > 0 {
                // On the coordination pass retain every other unit's destination,
                // including choices made later in the first pass.
                reserved = orders
                    .iter()
                    .enumerate()
                    .filter(|(other, _)| *other != index)
                    .filter_map(|(_, order)| order.path.last())
                    .map(|position| Coordinate::new(position.x as u16, position.y as u16))
                    .collect();
            }
            let goal = goals
                .get(&unit.unit_id())
                .ok_or("the AI mover has no strategic goal.")?;
            let candidates = candidates(&observed, unit, &reserved, goal, tactics)?;
            let mut best = orders
                .get(index)
                .ok_or("the AI unit has no order.")?
                .clone();
            let mut best_score = counterplay_score(&observed, player, &orders, &responses, &goals)?;
            for candidate in candidates {
                *orders.get_mut(index).ok_or("the AI unit has no order.")? = candidate;
                let score = counterplay_score(&observed, player, &orders, &responses, &goals)?;
                if score > best_score {
                    best_score = score;
                    best = orders
                        .get(index)
                        .ok_or("the AI unit has no order.")?
                        .clone();
                }
            }
            *orders.get_mut(index).ok_or("the AI unit has no order.")? = best;
            let destination = orders
                .get(index)
                .ok_or("the AI unit has no order.")?
                .path
                .last()
                .ok_or("the AI order has no destination.")?;
            reserved.insert(Coordinate::new(destination.x as u16, destination.y as u16));
        }
    }
    super::logistics::support(&observed, player, &mut orders)?;
    Ok(orders)
}

fn defensive_orders(
    scenario: &Scenario,
    player: PlayerNumber,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    scenario
        .units
        .iter()
        .filter(|unit| unit.player_number() != player)
        .map(|unit| {
            let origin = scenario
                .physical_position(unit)
                .ok_or("the observed enemy has no position.")?;
            let mut order = hold(unit, origin);
            if unit.kind() != UnitKind::Truck && unit.carrier_id().is_none() {
                order.ambush = Some(true);
                let target = scenario
                    .units
                    .iter()
                    .filter(|other| other.player_number() == player)
                    .filter_map(Unit::board_position)
                    .min_by_key(|position| (distance(origin, *position), *position));
                order.direction = target.map(|position| facing(origin, position));
                if order.direction.is_none() {
                    order.direction = unit.direction();
                }
            }
            Ok(order)
        })
        .collect()
}

fn candidates(
    scenario: &Scenario,
    unit: &Unit,
    reserved: &BTreeSet<Coordinate>,
    goal: &StrategicGoal,
    tactics: Tactics,
) -> Result<Vec<MoveOrderInput>, &'static str> {
    let origin = unit
        .board_position()
        .ok_or("the AI mover is not on the map.")?;
    let rules = combat::rules(unit.kind());
    let available = unit.supplies().current() - unit.supplies().upkeep_per_turn();
    let ready = available >= rules.readiness_cost + rules.shot_cost;
    let mut candidates = match tactics {
        Tactics::Stationary => Vec::new(),
        // Later allied choices can make an earlier action redundant. Revisit
        // holding as well as actions on the coordination pass.
        Tactics::Counterplay => vec![hold(unit, origin)],
    };
    let has_enemies = scenario
        .units
        .iter()
        .any(|other| other.player_number() != unit.player_number());
    if has_enemies && ready && unit.kind() != UnitKind::Truck {
        for direction in [
            Direction::North,
            Direction::East,
            Direction::South,
            Direction::West,
        ] {
            let mut order = hold(unit, origin);
            order.ambush = Some(true);
            order.direction = Some(direction);
            candidates.push(order);
        }
    }
    if unit.kind() == UnitKind::Infantry
        && unit.entrenchment() == Entrenchment::Exposed
        && available >= rules.dig_in_cost
        && !scenario.map.tile_at(origin).is_some_and(Terrain::is_road)
    {
        let mut order = hold(unit, origin);
        order.dig_in = Some(true);
        candidates.push(order);
    }
    let mut enemies: Vec<_> = scenario
        .units
        .iter()
        .filter(|other| other.player_number() != unit.player_number())
        .filter_map(Unit::board_position)
        .collect();
    enemies.sort_by_key(|position| (distance(origin, *position), *position));
    // Bound route generation even on authored maps with large armies.
    let mut targets = BTreeSet::from([goal.target]);
    if let Some(target) = resource_target(scenario, unit, origin) {
        targets.insert(target);
    }
    for enemy in enemies.iter().take(3) {
        targets.insert(*enemy);
        // Side approaches offer alternatives to a costly frontal attack.
        for (x, y) in [
            (enemy.x() - 1, enemy.y()),
            (enemy.x() + 1, enemy.y()),
            (enemy.x(), enemy.y() - 1),
            (enemy.x(), enemy.y() + 1),
        ] {
            if x >= 0 && y >= 0 {
                let position = Coordinate::new(x as u16, y as u16);
                if scenario.map.contains(position) {
                    targets.insert(position);
                }
            }
        }
    }
    if tactics == Tactics::Counterplay && has_enemies {
        // Include local escapes even when they make no progress toward the
        // strategic target; Medium's four best approaches can omit all of them.
        targets.extend(neighbors(origin).filter(|position| scenario.map.contains(*position)));
    }
    if unit.kind() == UnitKind::FieldGun && ready {
        for target in enemies
            .iter()
            .take(8)
            .filter(|target| combat::within_indirect_range(origin, **target, rules.indirect_range))
        {
            let mut order = hold(unit, origin);
            order.indirect_fire = Some(coordinate_input(*target));
            candidates.push(order);
        }
    }
    for attack in [false, true] {
        let can_attack_move = match unit.kind() {
            UnitKind::Infantry | UnitKind::Tank => ready,
            UnitKind::FieldGun | UnitKind::Truck => false,
        };
        if attack && (!can_attack_move || !has_enemies) {
            continue;
        }
        let mut paths = BTreeSet::new();
        for target in &targets {
            let path = route(scenario, unit, *target, reserved, attack)?;
            for length in 2..=path.len() {
                paths.insert(path[..length].to_vec());
            }
        }
        // Bound approaches per movement mode. Full turn simulation shares the
        // store's lock, so Hard adds only two routes and four local escapes.
        let mut paths = paths
            .into_iter()
            .map(|path| {
                let destination = path
                    .last()
                    .copied()
                    .ok_or("the AI candidate has no destination.")?;
                Ok(((goal.cost(destination)?, path.len(), destination), path))
            })
            .collect::<Result<Vec<_>, &'static str>>()?;
        paths.sort_by_key(|(rank, _)| *rank);
        let approaches = if tactics == Tactics::Counterplay {
            6
        } else {
            4
        };
        let mut selected: Vec<_> = paths
            .iter()
            .take(approaches)
            .map(|(_, path)| path.clone())
            .collect();
        if tactics == Tactics::Counterplay && !attack && has_enemies {
            selected.extend(
                paths
                    .into_iter()
                    .filter(|(_, path)| path.len() == 2)
                    .map(|(_, path)| path),
            );
            selected.sort();
            selected.dedup();
        }
        for path in selected {
            let mut order = hold(unit, origin);
            if attack {
                order.attack_move = Some(true);
                order.direction = path
                    .windows(2)
                    .last()
                    .and_then(|step| Direction::between(step[0], step[1]));
            }
            order.path = path.into_iter().map(coordinate_input).collect();
            candidates.push(order);
        }
    }
    Ok(candidates)
}

fn opponent(player: PlayerNumber) -> PlayerNumber {
    match player {
        PlayerNumber::Player1 => PlayerNumber::Player2,
        PlayerNumber::Player2 => PlayerNumber::Player1,
    }
}

/// Weight the worst response twice as heavily as the mean response. Scaling by
/// response count avoids rounding and preserves Medium's original ordering.
fn counterplay_score(
    scenario: &Scenario,
    player: PlayerNumber,
    own_orders: &[MoveOrderInput],
    responses: &[Vec<MoveOrderInput>],
    goals: &BTreeMap<UnitId, StrategicGoal>,
) -> Result<i64, &'static str> {
    let scores = responses
        .iter()
        .map(|response| forecast(scenario, player, own_orders, response, goals))
        .collect::<Result<Vec<_>, _>>()?;
    let worst = scores
        .iter()
        .min()
        .ok_or("the AI search has no enemy response.")?;
    Ok(worst * scores.len() as i64 * 2 + scores.iter().sum::<i64>())
}

pub(super) fn strategic_target(scenario: &Scenario, unit: &Unit, origin: Coordinate) -> Coordinate {
    if let Some(target) = resource_target(scenario, unit, origin) {
        return target;
    }
    if unit.kind() != UnitKind::Truck
        && let Some(target) = scenario
            .units
            .iter()
            .filter(|other| other.player_number() != unit.player_number())
            .filter_map(Unit::board_position)
            .min_by_key(|position| (distance(origin, *position), *position))
    {
        return target;
    }
    let center = objective(scenario, origin);
    // Keep one infantry guarding the central supply point; other combat units
    // scout the opposing half instead of all camping there. Goals depend on the
    // public map geometry and assigned side, never hidden starting positions.
    let guard = scenario.units.iter().find(|other| {
        other.player_number() == unit.player_number() && other.kind() == UnitKind::Infantry
    });
    if guard.is_none_or(|guard| guard.unit_id() != unit.unit_id()) && unit.kind() != UnitKind::Truck
    {
        Coordinate::new(
            match unit.player_number() {
                PlayerNumber::Player1 => (scenario.map.width() * 3 / 4) as u16,
                PlayerNumber::Player2 => (scenario.map.width() / 4) as u16,
            },
            (scenario.map.height() / 2) as u16,
        )
    } else {
        center
    }
}

fn forecast(
    scenario: &Scenario,
    player: PlayerNumber,
    own_orders: &[MoveOrderInput],
    enemy_orders: &[MoveOrderInput],
    goals: &BTreeMap<UnitId, StrategicGoal>,
) -> Result<i64, &'static str> {
    let mut board = scenario.clone();
    let mut turns = Turns::default();
    turns.submit(&mut board, player, 1, own_orders.to_vec())?;
    turns.submit(&mut board, opponent(player), 1, enemy_orders.to_vec())?;
    let mut score = 0_i64;
    for before in &scenario.units {
        let after = board
            .units
            .iter()
            .find(|unit| unit.unit_id() == before.unit_id());
        let health = after.map_or(0, |unit| unit.hit_points().current());
        let value = if before.kind() == UnitKind::Truck {
            25
        } else {
            100
        };
        if before.player_number() != player {
            score += i64::from((before.hit_points().current() - health) * value);
            continue;
        }
        // Losing our own force costs more than an equal exchange.
        score -= i64::from((before.hit_points().current() - health) * value * 3 / 2);
        if let Some(unit) = after {
            // Supplies/fuel are known only for our own force.
            score += i64::from(unit.supplies().current() / 8);
            score += i64::from(unit.fuel().map_or(0, |fuel| fuel.current / 8));
            if before.board_position().is_some()
                && let Some(position) = unit.board_position()
            {
                let goal = goals
                    .get(&before.unit_id())
                    .ok_or("the AI mover has no strategic goal.")?;
                // Two movement half-points retain the old plain-tile weight.
                score -= i64::from(goal.cost(position)? * 6);
                if unit.entrenchment() == Entrenchment::Entrenched
                    && distance(position, goal.target) <= 2
                {
                    score += 24;
                }
            }
        }
    }
    Ok(score)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::{self, Difficulty},
        map::{Map, RoadShape},
        map_definition::MapDefinition,
        map_id::MapId,
        test_support::{FixtureValue, TestResult},
        turns,
    };

    fn artillery_fixture() -> TestResult<Scenario> {
        MapDefinition::parse(r#"{
            "width": 10, "height": 5, "theme": "GreenForest",
            "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 2}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 2, "position": {"x": 2, "y": 3}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 3, "position": {"x": 4, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 4, "position": {"x": 5, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"},
                {"id": 5, "position": {"x": 6, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()
    }

    fn resolved_enemy_count(scenario: &Scenario, difficulty: Difficulty) -> TestResult<usize> {
        let mut board = scenario.clone();
        let mut turns = Turns::default();
        let orders =
            ai::plan_with_difficulty(scenario, PlayerNumber::Player1, difficulty).fixture()?;
        turns
            .submit(&mut board, PlayerNumber::Player1, 1, orders)
            .fixture()?;
        let holds = scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() == PlayerNumber::Player2)
            .map(|unit| Ok(hold(unit, unit.board_position().fixture()?)))
            .collect::<TestResult<Vec<_>>>()?;
        turns
            .submit(&mut board, PlayerNumber::Player2, 1, holds)
            .fixture()?;
        Ok(board
            .units
            .iter()
            .filter(|unit| unit.player_number() == PlayerNumber::Player2)
            .count())
    }

    #[test]
    fn coordinates_artillery_instead_of_overkilling_one_target() -> TestResult {
        let scenario = artillery_fixture()?;
        assert_eq!(resolved_enemy_count(&scenario, Difficulty::Easy)?, 1);
        assert_eq!(resolved_enemy_count(&scenario, Difficulty::Medium)?, 0);
        assert_eq!(resolved_enemy_count(&scenario, Difficulty::Hard)?, 0);
        Ok(())
    }

    #[test]
    fn private_enemy_resources_do_not_change_plans() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            let scenario = artillery_fixture()?;
            let mut changed = scenario.clone();
            for enemy in changed
                .units
                .iter_mut()
                .filter(|unit| unit.player_number() == PlayerNumber::Player2)
            {
                enemy.take_damage(12);
                enemy.set_supplies_for_test(1);
                enemy.set_fuel_for_test(0);
            }
            let original = turns::validate(
                &scenario,
                PlayerNumber::Player1,
                planner(&scenario, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            let other = turns::validate(
                &changed,
                PlayerNumber::Player1,
                planner(&changed, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            assert_eq!(format!("{original:?}"), format!("{other:?}"));
        }
        Ok(())
    }

    #[test]
    fn unknown_depot_stock_does_not_change_plans() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            let scenario = Scenario::supply_point().fixture()?;
            let visible = visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            let mut changed = scenario.clone();
            let mut hidden_count = 0;
            for depot in &mut changed.depots {
                if !visible.contains(&depot.position) {
                    depot.stock.current = 0;
                    hidden_count += 1;
                }
            }
            assert!(hidden_count > 0);
            let original = turns::validate(
                &scenario,
                PlayerNumber::Player1,
                planner(&scenario, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            let other = turns::validate(
                &changed,
                PlayerNumber::Player1,
                planner(&changed, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            assert_eq!(format!("{original:?}"), format!("{other:?}"));
        }
        Ok(())
    }

    #[test]
    fn road_candidates_exclude_digging_and_planners_still_submit_legal_orders() -> TestResult {
        let initial = MapDefinition::parse(
            r#"{
                "width": 5, "height": 3, "theme": "GreenForest",
                "features": [], "depots": [],
                "units": [
                    {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                    {"id": 2, "position": {"x": 4, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
                ]
            }"#,
        )
        .fixture()?
        .scenario()
        .fixture()?;
        for shape in RoadShape::ALL {
            let mut scenario = initial.clone();
            scenario.map = Map::new(5, 3, Terrain::Road(shape), BTreeMap::new()).fixture()?;
            let unit = scenario.units.first().fixture()?;
            let goal = StrategicGoal::new(&scenario, unit).fixture()?;
            let orders = candidates(
                &scenario,
                unit,
                &BTreeSet::new(),
                &goal,
                Tactics::Stationary,
            )
            .fixture()?;
            assert!(orders.iter().all(|order| order.dig_in != Some(true)));
            for planner in [plan_medium, plan_hard] {
                let orders = planner(&scenario, PlayerNumber::Player1).fixture()?;
                assert!(orders.iter().all(|order| order.dig_in != Some(true)));
                turns::validate(&scenario, PlayerNumber::Player1, orders).fixture()?;
            }
        }
        Ok(())
    }

    #[test]
    fn guards_supply_point_by_digging_in() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            let mut scenario = MapDefinition::parse(r#"{
            "width": 12, "height": 5, "theme": "GreenForest", "features": [],
            "depots": [{"position": {"x": 6, "y": 2}, "kind": "Supply"}],
            "units": [
                {"id": 1, "position": {"x": 6, "y": 2}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 11, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
            let orders = planner(&scenario, PlayerNumber::Player1).fixture()?;
            assert_eq!(orders.first().fixture()?.dig_in, Some(true));
            let mut turns = Turns::default();
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                .fixture()?;
            let enemy = scenario
                .units
                .iter()
                .find(|unit| unit.player_number() == PlayerNumber::Player2)
                .fixture()?;
            let hold = hold(enemy, enemy.board_position().fixture()?);
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, vec![hold])
                .fixture()?;
            assert_eq!(
                scenario.units.first().fixture()?.entrenchment(),
                Entrenchment::Entrenched
            );
        }
        Ok(())
    }

    #[test]
    fn concealed_enemies_do_not_change_plans_and_exhausted_units_hold() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            let scenario = Scenario::supply_point().fixture()?;
            let mut changed = scenario.clone();
            let visible = visibility::visible_tiles(&scenario, PlayerNumber::Player1);
            changed.units.retain(|unit| {
                unit.player_number() == PlayerNumber::Player1
                    || unit
                        .board_position()
                        .is_some_and(|position| visible.contains(&position))
            });
            assert!(changed.units.len() < scenario.units.len());
            let original = turns::validate(
                &scenario,
                PlayerNumber::Player1,
                planner(&scenario, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            let other = turns::validate(
                &changed,
                PlayerNumber::Player1,
                planner(&changed, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            assert_eq!(format!("{original:?}"), format!("{other:?}"));
            for unit in &mut changed.units {
                unit.set_supplies_for_test(1);
                unit.set_fuel_for_test(0);
            }
            let orders = turns::validate(
                &changed,
                PlayerNumber::Player1,
                planner(&changed, PlayerNumber::Player1).fixture()?,
            )
            .fixture()?;
            assert!(orders.iter().all(|order| order.path.len() == 1));
        }
        Ok(())
    }

    #[test]
    fn low_supply_unit_stays_beside_stock_instead_of_spending_to_enter_depot() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            let mut scenario = MapDefinition::parse(r#"{
            "width": 12, "height": 5, "theme": "GreenForest", "features": [],
            "depots": [{"position": {"x": 6, "y": 2}, "kind": "Supply"}],
            "units": [
                {"id": 1, "position": {"x": 5, "y": 2}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 11, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
            let infantry = scenario.units.first_mut().fixture()?;
            infantry.set_supplies_for_test(19);
            let orders = planner(&scenario, PlayerNumber::Player1).fixture()?;
            let order = orders.first().fixture()?;
            assert_eq!(order.path.len(), 1);
            assert_ne!(order.dig_in, Some(true));
            let enemy_orders = defensive_orders(&scenario, PlayerNumber::Player1).fixture()?;
            let mut turns = Turns::default();
            turns
                .submit(&mut scenario, PlayerNumber::Player1, 1, orders)
                .fixture()?;
            turns
                .submit(&mut scenario, PlayerNumber::Player2, 1, enemy_orders)
                .fixture()?;
            let infantry = scenario.units.first().fixture()?;
            assert_eq!(
                infantry.supplies().current(),
                infantry.supplies().maximum() - infantry.supplies().upkeep_per_turn()
            );
        }
        Ok(())
    }

    #[test]
    fn strategic_costs_pay_for_entered_terrain_and_stop_at_depot_adjacency() -> TestResult {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 5, "height": 3, "theme": "GreenForest", "features": [],
            "depots": [{"position": {"x": 4, "y": 1}, "kind": "Supply"}],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
                {"id": 2, "position": {"x": 0, "y": 0}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        scenario.map = crate::map::Map::from_ascii("^^^^^\n.#...\n^^^^^").fixture()?;
        let unit = scenario.units.first_mut().fixture()?;
        unit.set_supplies_for_test(unit.supplies().maximum() / 2 - 1);
        let goal = StrategicGoal::new(&scenario, scenario.units.first().fixture()?).fixture()?;
        assert_eq!(goal.cost(Coordinate::new(0, 1)).fixture()?, 10);
        assert_eq!(goal.cost(Coordinate::new(1, 1)).fixture()?, 4);
        assert_eq!(goal.cost(Coordinate::new(3, 1)).fixture()?, 0);
        Ok(())
    }

    #[test]
    fn resupply_detour_can_start_by_moving_away_from_the_depot() -> TestResult {
        for planner in [plan_medium, plan_hard] {
            for kind in [UnitKind::Tank, UnitKind::Truck, UnitKind::FieldGun] {
                let direction = if kind == UnitKind::Truck {
                    "null"
                } else {
                    "\"East\""
                };
                let mut scenario = MapDefinition::parse(&format!(r#"{{
                "width": 12, "height": 8, "theme": "Snow", "features": [],
                "depots": [{{"position": {{"x": 6, "y": 2}}, "kind": "Supply"}}],
                "units": [
                    {{"id": 1, "position": {{"x": 6, "y": 4}}, "playerNumber": "Player1", "kind": "{kind:?}", "direction": {direction}}},
                    {{"id": 2, "position": {{"x": 0, "y": 0}}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}},
                    {{"id": 3, "position": {{"x": 0, "y": 7}}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"}}
                ]
            }}"#)).fixture()?.scenario().fixture()?;
                scenario.map = crate::map::Map::from_ascii(
                "............\n............\n............\n^^^^^^^.....\n............\n............\n............\n............",
            ).fixture()?;
                let unit = scenario.units.first_mut().fixture()?;
                unit.set_supplies_for_test(unit.supplies().maximum() / 2 - 1);
                let orders = planner(&scenario, PlayerNumber::Player1).fixture()?;
                let order = orders.first().fixture()?;
                assert!(order.path.len() > 1, "{kind:?} refused the mountain detour");
                assert!(
                    order.path.get(1).fixture()?.x > 6,
                    "{kind:?} did not head for the pass"
                );
                let mut turns = Turns::default();
                for _ in 0..12 {
                    let number = turns.number;
                    let orders = planner(&scenario, PlayerNumber::Player1).fixture()?;
                    let enemy = scenario
                        .units
                        .iter()
                        .find(|unit| unit.player_number() == PlayerNumber::Player2)
                        .fixture()?;
                    let enemy_order = hold(enemy, enemy.board_position().fixture()?);
                    turns
                        .submit(&mut scenario, PlayerNumber::Player1, number, orders)
                        .fixture()?;
                    turns
                        .submit(
                            &mut scenario,
                            PlayerNumber::Player2,
                            number,
                            vec![enemy_order],
                        )
                        .fixture()?;
                    if scenario.units.first().fixture()?.supplies().current()
                        > scenario.units.first().fixture()?.supplies().maximum() / 2
                    {
                        break;
                    }
                }
                let unit = scenario.units.first().fixture()?;
                assert!(
                    distance(unit.board_position().fixture()?, Coordinate::new(6, 2)) <= 1,
                    "{kind:?} never reached supply"
                );
                assert!(
                    unit.supplies().current() > unit.supplies().maximum() / 2,
                    "{kind:?} never replenished"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn plays_valid_turns_on_every_map_and_both_sides() -> TestResult {
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
            "bastion-pass",
        ] {
            let map = MapId::parse(name.into())?;
            let mut scenario = map.scenario().fixture()?;
            let mut turns = Turns::default();
            for _ in 0..12 {
                if turns.outcome.is_some() {
                    break;
                }
                let number = turns.number;
                for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                    let orders = plan_medium(&scenario, player).fixture()?;
                    turns
                        .submit(&mut scenario, player, number, orders)
                        .map_err(|error| format!("{map:?}, turn {number}, {player:?}: {error}"))?;
                }
            }
        }
        Ok(())
    }

    #[test]
    fn hard_preserves_artillery_against_an_infantry_rush() -> TestResult {
        let scenario = MapDefinition::parse(r#"{
            "width": 10, "height": 7, "theme": "GreenForest", "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 3}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 2, "position": {"x": 4, "y": 3}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        // The same independently chosen human attack is resolved against both
        // difficulties. Neither planner receives these orders.
        let infantry = scenario.units.get(1).fixture()?;
        let mut rush = hold(infantry, infantry.board_position().fixture()?);
        rush.path = [
            Coordinate::new(4, 3),
            Coordinate::new(3, 3),
            Coordinate::new(2, 3),
        ]
        .into_iter()
        .map(coordinate_input)
        .collect();
        rush.attack_move = Some(true);
        rush.direction = Some(Direction::West);
        for difficulty in [Difficulty::Medium, Difficulty::Hard] {
            let orders =
                ai::plan_with_difficulty(&scenario, PlayerNumber::Player1, difficulty).fixture()?;
            let mut board = scenario.clone();
            let mut turns = Turns::default();
            turns
                .submit(&mut board, PlayerNumber::Player1, 1, orders)
                .fixture()?;
            turns
                .submit(&mut board, PlayerNumber::Player2, 1, vec![rush.clone()])
                .fixture()?;
            let gun = board
                .units
                .iter()
                .find(|unit| unit.kind() == UnitKind::FieldGun);
            match difficulty {
                Difficulty::Medium => assert!(gun.is_none()),
                Difficulty::Hard => assert_eq!(gun.fixture()?.hit_points().current(), 16),
                Difficulty::Easy => {
                    return Err("the regression only compares search difficulties".into());
                }
            }
        }
        Ok(())
    }

    #[test]
    fn hard_plays_valid_turns_on_every_map_and_both_sides() -> TestResult {
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
            "bastion-pass",
        ] {
            let map = MapId::parse(name.into())?;
            let mut scenario = map.scenario().fixture()?;
            let mut turns = Turns::default();
            for _ in 0..4 {
                if turns.outcome.is_some() {
                    break;
                }
                let number = turns.number;
                for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
                    let orders = plan_hard(&scenario, player).fixture()?;
                    turns
                        .submit(&mut scenario, player, number, orders)
                        .map_err(|error| {
                            format!("Hard {map:?}, turn {number}, {player:?}: {error}")
                        })?;
                }
            }
        }
        Ok(())
    }
}
