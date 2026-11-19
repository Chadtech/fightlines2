//! Positioning and arrival preferences used by the stronger opponents.
use super::{distance, facing, objective};
use crate::{
    map::{Coordinate, Terrain},
    scenario::{Direction, Scenario, Unit, UnitKind},
    turns::UnitOrderInput,
    visibility,
};

pub(super) fn positioning_goal(
    scenario: &Scenario,
    unit: &Unit,
    origin: Coordinate,
) -> Option<Coordinate> {
    let mobile_combat = matches!(unit.kind(), UnitKind::Infantry | UnitKind::Tank);
    if !mobile_combat {
        return None;
    }
    let threat = nearest_threat(scenario, unit, origin);
    let ahead = threat.unwrap_or_else(|| objective(scenario, origin));
    screen_position(scenario, unit, origin, ahead)
        .or_else(|| crossfire_cover(scenario, unit, origin, threat?))
}

pub(super) fn dispersed_screen(order: &UnitOrderInput, allies: &[Coordinate]) -> i64 {
    if order.path.len() < 2 {
        return 0;
    }
    let Some(end) = order_end(order) else {
        return 0;
    };
    match allies.iter().map(|ally| distance(*ally, end)).min() {
        Some(0..=1) => -65,
        Some(2..=3) => 56,
        _ => 0,
    }
}

pub(super) fn crossfire(scenario: &Scenario, unit: &Unit, order: &UnitOrderInput) -> i64 {
    if order.attack_move != Some(true) {
        return 0;
    }
    let Some(end) = order_end(order) else {
        return 0;
    };
    let supports = nearest_threat(scenario, unit, end).is_some_and(|enemy| {
        distance(end, enemy) <= 3 && crosses_allied_fire(scenario, unit, end, enemy)
    });
    88 * i64::from(supports)
}

pub(super) fn countercharge_order(
    order: &UnitOrderInput,
    enemies: &[Coordinate],
) -> Option<UnitOrderInput> {
    let [.., previous, end] = order.path.as_slice() else {
        return None;
    };
    let destination = Coordinate::new(end.x as u16, end.y as u16);
    let before = Coordinate::new(previous.x as u16, previous.y as u16);
    let backward = Direction::between(destination, before);
    let (_, direction) = enemies
        .iter()
        .copied()
        .filter(|enemy| (1..=2).contains(&distance(destination, *enemy)))
        .map(|enemy| (enemy, Some(facing(destination, enemy))))
        // Arrival facing may turn sideways, but cannot reverse the route.
        .filter(|(_, direction)| *direction != backward && *direction != order.direction)
        .min_by_key(|(enemy, _)| (distance(destination, *enemy), *enemy))?;
    Some(UnitOrderInput {
        direction,
        ..order.clone()
    })
}

pub(super) fn guarded_arrival(
    scenario: &Scenario,
    order: &UnitOrderInput,
    enemies: &[Coordinate],
) -> Option<UnitOrderInput> {
    let [.., previous, end] = order.path.as_slice() else {
        return None;
    };
    let origin = position(previous.x, previous.y);
    let destination = position(end.x, end.y);
    if !is_cover(scenario, destination) {
        return None;
    }
    let backward = Direction::between(destination, origin);
    let (_, direction) = enemies
        .iter()
        .copied()
        // In cover, add an option specifically for threats outside the
        // inherited countercharge's two-square arrival radius.
        .filter(|enemy| (3..=4).contains(&distance(destination, *enemy)))
        .map(|enemy| (enemy, Some(facing(destination, enemy))))
        .filter(|(_, direction)| *direction != backward && *direction != order.direction)
        .min_by_key(|(enemy, _)| (distance(destination, *enemy), *enemy))?;
    Some(UnitOrderInput {
        direction,
        ..order.clone()
    })
}

fn position(x: i32, y: i32) -> Coordinate {
    // Coordinates come from the planner's map-bounded paths.
    Coordinate::new(x as u16, y as u16)
}

pub(super) fn counterfire(scenario: &Scenario, unit: &Unit, order: &UnitOrderInput) -> i64 {
    let Some(target) = &order.indirect_fire else {
        return 0;
    };
    let position = Coordinate::new(target.x as u16, target.y as u16);
    let targets_gun = scenario.units.iter().any(|enemy| {
        enemy.player_number() != unit.player_number()
            && enemy.kind() == UnitKind::FieldGun
            && enemy.board_position() == Some(position)
    });
    120 * i64::from(targets_gun)
}

fn screen_position(
    scenario: &Scenario,
    unit: &Unit,
    origin: Coordinate,
    target: Coordinate,
) -> Option<Coordinate> {
    let ally = allies(scenario, unit)
        .filter_map(Unit::board_position)
        .min_by_key(|ally| (distance(origin, *ally), *ally))?;
    local_tiles(scenario, unit, origin)
        .filter(|position| (2..=3).contains(&distance(*position, ally)))
        .filter(|position| distance(*position, target) <= distance(origin, target))
        .min_by_key(|position| {
            (
                !is_cover(scenario, *position),
                distance(*position, target),
                *position,
            )
        })
}

fn order_end(order: &UnitOrderInput) -> Option<Coordinate> {
    order
        .path
        .last()
        .map(|end| Coordinate::new(end.x as u16, end.y as u16))
}

fn allies<'a>(scenario: &'a Scenario, unit: &Unit) -> impl Iterator<Item = &'a Unit> {
    let player = unit.player_number();
    let id = unit.unit_id();
    scenario.units.iter().filter(move |ally| {
        ally.player_number() == player && ally.unit_id() != id && ally.kind() != UnitKind::Truck
    })
}

fn nearest_threat(scenario: &Scenario, unit: &Unit, origin: Coordinate) -> Option<Coordinate> {
    enemy_combat_positions(scenario, unit).min_by_key(|threat| (distance(origin, *threat), *threat))
}

fn local_tiles(
    scenario: &Scenario,
    unit: &Unit,
    origin: Coordinate,
) -> impl Iterator<Item = Coordinate> {
    (-3i32..=3)
        .flat_map(|dx| (-3i32..=3).map(move |dy| (dx, dy)))
        .filter(|(dx, dy)| dx.abs() + dy.abs() <= 3)
        .filter_map(move |(dx, dy)| map_coordinate(scenario, origin.x() + dx, origin.y() + dy))
        .filter(move |position| {
            !scenario.units.iter().any(|other| {
                other.unit_id() != unit.unit_id() && other.board_position() == Some(*position)
            })
        })
}

fn crossfire_cover(
    scenario: &Scenario,
    unit: &Unit,
    origin: Coordinate,
    threat: Coordinate,
) -> Option<Coordinate> {
    local_tiles(scenario, unit, origin)
        .filter(|position| (1..=3).contains(&distance(*position, threat)))
        .filter(|position| crosses_allied_fire(scenario, unit, *position, threat))
        .min_by_key(|position| {
            (
                !is_cover(scenario, *position),
                distance(origin, *position),
                *position,
            )
        })
}

fn crosses_allied_fire(
    scenario: &Scenario,
    unit: &Unit,
    position: Coordinate,
    target: Coordinate,
) -> bool {
    let dx = position.x() - target.x();
    let dy = position.y() - target.y();
    if !visibility::clear_line(&scenario.map, position, target) {
        return false;
    }
    allies(scenario, unit)
        .filter_map(Unit::board_position)
        .filter(|ally| distance(*ally, target) <= 4)
        .any(|ally| {
            let ax = ally.x() - target.x();
            let ay = ally.y() - target.y();
            (ax * dx + ay * dy <= 0 || (ax * dy - ay * dx).abs() >= 2)
                && visibility::clear_line(&scenario.map, ally, target)
        })
}

pub(super) fn map_coordinate(scenario: &Scenario, x: i32, y: i32) -> Option<Coordinate> {
    if x < 0 || y < 0 || x >= scenario.map.width() || y >= scenario.map.height() {
        return None;
    }
    let position = Coordinate::new(x as u16, y as u16);
    scenario
        .map
        .tile_at(position)
        .is_some_and(|terrain| terrain != Terrain::Water)
        .then_some(position)
}

fn is_cover(scenario: &Scenario, position: Coordinate) -> bool {
    scenario
        .map
        .tile_at(position)
        .is_some_and(|terrain| terrain == Terrain::Forest || terrain == Terrain::Hills)
}

fn enemy_combat_positions<'a>(
    scenario: &'a Scenario,
    unit: &Unit,
) -> impl Iterator<Item = Coordinate> + 'a {
    let player = unit.player_number();
    scenario
        .units
        .iter()
        .filter(move |enemy| enemy.player_number() != player && enemy.kind() != UnitKind::Truck)
        .filter_map(Unit::board_position)
}
