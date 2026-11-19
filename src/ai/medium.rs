//! Break Contact.
use super::{
    RouteSearch, coordinate_input, distance, facing, hold, logistics,
    memory::{Contact, ContactOrderFacts, ContactPolicy, EnemyMemory},
    objective, resource_target, tactics,
};
use crate::{
    combat,
    map::{Coordinate, Terrain},
    movement,
    player_number::PlayerNumber,
    scenario::{Direction, Entrenchment, Scenario, Unit, UnitId, UnitKind},
    supplies::ResourceStock,
    turns::{Turns, UnitOrderInput},
    visibility,
};
use std::collections::{BTreeMap, BTreeSet};

const CONTACT_POLICY: ContactPolicy = ContactPolicy {
    horizon: 6,
    weight: 96,
    preference: contact_preference,
};

fn contact_preference(f: &ContactOrderFacts) -> i64 {
    let mut bonus = 0;
    if f.cover_after && f.progress > 0 && f.supported {
        bonus += 70 + i64::from(f.progress) * 12;
    }
    if f.low_supplies && f.distance_before <= 4 {
        bonus += if f.progress < 0 && f.cover_after {
            190
        } else {
            -190
        };
    }
    if f.age >= 1 && f.moves && !f.cover_after && f.progress > 0 {
        bonus -= 123;
    }
    bonus
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
        let reserve_target = resource_target(scenario, unit, origin);
        let positioning_goal = reserve_target
            .is_none()
            .then(|| tactics::positioning_goal(scenario, unit, origin))
            .flatten();
        let target = reserve_target
            .or(positioning_goal)
            .unwrap_or_else(|| non_supply_target(scenario, unit, origin));
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
        let desired_distance = if positioning_goal.is_some() {
            0
        } else if reserve_target.is_none() && unit.kind() == UnitKind::FieldGun {
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

pub(crate) fn plan(
    scenario: &Scenario,
    player: PlayerNumber,
    enemy: &EnemyMemory,
    turn: i32,
) -> Result<Vec<UnitOrderInput>, &'static str> {
    let visible = visibility::visible_tiles(scenario, player);
    let mut observed = visibility::observed_scenario(scenario, player, &visible);
    let contacts = enemy.contacts(&observed, turn, CONTACT_POLICY);
    // Projection hides gauges in GraphQL but retains their underlying values.
    // Replace them before any search, including combat and replenishment.
    for unit in &mut observed.units {
        if unit.player_number() != player {
            unit.assume_full_resources();
        }
    }
    for depot in &mut observed.buildings {
        if !depot.stock_visible
            && let Some(kind) = depot.kind.resource_kind()
        {
            depot.stock = ResourceStock::depot(kind);
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
    let response = defensive_orders(&observed, player)?;
    let counterplay = observed
        .units
        .iter()
        .any(|unit| unit.player_number() != player);
    // Reuse terrain searches across every candidate simulation in this plan.
    let goals = own
        .iter()
        .filter(|unit| unit.board_position().is_some())
        .map(|unit| Ok((unit.unit_id(), StrategicGoal::new(&observed, unit)?)))
        .collect::<Result<BTreeMap<_, _>, &'static str>>()?;
    let mut reserved = BTreeSet::new();
    for (index, unit) in own.iter().enumerate() {
        if unit.carrier_id().is_some() {
            continue;
        }
        let goal = goals
            .get(&unit.unit_id())
            .ok_or("the AI mover has no strategic goal.")?;
        let origin = unit
            .board_position()
            .ok_or("the AI mover is not on the map.")?;
        let contact = Contact::near(&contacts, unit, origin);
        let candidates = candidates(&observed, unit, &reserved, goal, contact)?;
        let mut best = orders
            .get(index)
            .ok_or("the AI unit has no order.")?
            .clone();
        // Keep tactical preferences on the same scale as the single forecast.
        let score_scale = 3;
        let fog_readiness = |order: &UnitOrderInput| {
            let memory_readiness = contact.map_or(0, |contact| contact.readiness(order));
            let scouting =
                order.attack_move == Some(true) && approaches_fog(&observed, &visible, order);
            let scouting_readiness = i64::from(scouting) * 42;
            (scouting_readiness + memory_readiness) * score_scale
        };
        let allied_destinations = if matches!(unit.kind(), UnitKind::Infantry | UnitKind::Tank) {
            own.iter()
                .zip(&orders)
                .filter(|(ally, _)| {
                    ally.unit_id() != unit.unit_id()
                        && ally.kind() != UnitKind::Truck
                        && ally.board_position().is_some()
                })
                .filter_map(|(_, order)| order.path.last())
                .map(|tile| Coordinate::new(tile.x as u16, tile.y as u16))
                .collect()
        } else {
            Vec::new()
        };
        let tactical_preference = |order: &UnitOrderInput| {
            let positioning = tactics::counterfire(&observed, unit, order)
                + tactics::crossfire(&observed, unit, order)
                + tactics::dispersed_screen(order, &allied_destinations);
            let last_contact = contact.map_or(0, |contact| {
                contact.order_preference(&observed, unit, origin, order)
            });
            (positioning + last_contact) * score_scale
        };
        let evaluate = |orders: &[UnitOrderInput]| {
            forecast(&observed, player, orders, &response, &goals).map(|score| score * score_scale)
        };
        let mut best_score = evaluate(&orders)? + fog_readiness(&best) + tactical_preference(&best);
        for candidate in candidates {
            let readiness = fog_readiness(&candidate);
            if !counterplay && candidate.attack_move == Some(true) && readiness == 0 {
                continue;
            }
            let preference = tactical_preference(&candidate);
            *orders.get_mut(index).ok_or("the AI unit has no order.")? = candidate;
            let score = evaluate(&orders)? + readiness + preference;
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
    logistics::support(&observed, player, &mut orders)?;
    Ok(orders)
}

fn defensive_orders(
    scenario: &Scenario,
    player: PlayerNumber,
) -> Result<Vec<UnitOrderInput>, &'static str> {
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
    contact: Option<Contact>,
) -> Result<Vec<UnitOrderInput>, &'static str> {
    let origin = unit
        .board_position()
        .ok_or("the AI mover is not on the map.")?;
    let rules = combat::rules(unit.kind());
    let available = unit.supplies().current() - unit.supplies().upkeep_per_turn();
    let ready = available >= rules.readiness_cost + rules.shot_cost;
    // Revisit holding when later allied choices make an earlier action redundant.
    let mut candidates = vec![hold(unit, origin)];
    let has_enemies = scenario
        .units
        .iter()
        .any(|other| other.player_number() != unit.player_number());
    if ready && unit.kind() != UnitKind::Truck {
        for direction in [
            Direction::North,
            Direction::East,
            Direction::South,
            Direction::West,
        ] {
            if !has_enemies && !contact.is_some_and(|contact| contact.watches(origin, direction)) {
                continue;
            }
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
        && !scenario
            .buildings
            .iter()
            .any(|depot| depot.position == origin)
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
    if let Some(contact) = contact {
        targets.insert(contact.position);
    }
    if let Some(target) = resource_target(scenario, unit, origin) {
        targets.insert(target);
    }
    for enemy in enemies.iter().take(3) {
        targets.insert(*enemy);
        // Side approaches offer alternatives to a costly frontal attack.
        targets.extend(neighbors(*enemy).filter(|position| scenario.map.contains(*position)));
    }
    if has_enemies {
        // Include local escapes even when they make no progress toward the
        // strategic target; the best approaches can omit all of them.
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
        if attack && !can_attack_move {
            continue;
        }
        let mut paths = BTreeSet::new();
        let routes = RouteSearch::new(scenario, unit, reserved, attack)?;
        for target in &targets {
            let path = routes.path_to(*target)?;
            for length in 2..=path.len() {
                paths.insert(path[..length].to_vec());
            }
        }
        // Bound approaches per movement mode and keep up to four local escapes.
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
        let mut selected: Vec<_> = paths
            .iter()
            .take(16)
            .map(|(_, path)| path.clone())
            .collect();
        if !attack && has_enemies {
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
            if attack {
                let countercharge = tactics::countercharge_order(&order, &enemies);
                let guarded =
                    tactics::guarded_arrival(scenario, &order, &enemies).filter(|candidate| {
                        countercharge
                            .as_ref()
                            .is_none_or(|inherited| inherited.direction != candidate.direction)
                    });
                candidates.extend(countercharge);
                candidates.extend(guarded);
            }
            candidates.push(order);
        }
    }
    Ok(candidates)
}

/// Attack moves can make contact on the route or on the square straight ahead
/// at the end. Treat unseen land along that approach as a possible contact.
pub(super) fn approaches_fog(
    scenario: &Scenario,
    visible: &BTreeSet<Coordinate>,
    order: &UnitOrderInput,
) -> bool {
    let unseen_land =
        |x, y| tactics::map_coordinate(scenario, x, y).is_some_and(|tile| !visible.contains(&tile));
    if order
        .path
        .iter()
        .skip(1)
        .any(|step| unseen_land(step.x, step.y))
    {
        return true;
    }
    let (Some(end), Some(direction)) = (order.path.last(), order.direction) else {
        return false;
    };
    let (dx, dy) = direction_offset(direction);
    unseen_land(end.x + dx, end.y + dy)
}

fn direction_offset(direction: Direction) -> (i32, i32) {
    match direction {
        Direction::North => (0, -1),
        Direction::East => (1, 0),
        Direction::South => (0, 1),
        Direction::West => (-1, 0),
    }
}

fn non_supply_target(scenario: &Scenario, unit: &Unit, origin: Coordinate) -> Coordinate {
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
    own_orders: &[UnitOrderInput],
    enemy_orders: &[UnitOrderInput],
    goals: &BTreeMap<UnitId, StrategicGoal>,
) -> Result<i64, &'static str> {
    let mut board = scenario.clone();
    let mut turns = Turns::default();
    turns.submit(&mut board, player, 1, own_orders.to_vec())?;
    turns.submit(&mut board, player.opponent(), 1, enemy_orders.to_vec())?;
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
        score -= i64::from((before.hit_points().current() - health) * value * 3 / 2);
        if let Some(unit) = after {
            // Supplies/fuel are known only for our own force.
            score += i64::from(unit.supplies().current() / 8);
            score += i64::from(unit.fuel().map_or(0, |fuel| fuel.current / 32));
            if before.board_position().is_some()
                && let Some(position) = unit.board_position()
            {
                let goal = goals
                    .get(&before.unit_id())
                    .ok_or("the AI mover has no strategic goal.")?;
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
