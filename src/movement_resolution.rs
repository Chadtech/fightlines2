//! Shared arrivals use accumulated terrain cost / full movement allowance.
//! Integer ticks are the least common multiple of allowances, never float comparisons.
use crate::{
    combat::Combat,
    map::Coordinate,
    movement,
    scenario::{PlayerNumber, Scenario, Unit, UnitId},
    turns::{self, FacingOrder, MoveOrder, PlannedLoad, TurnFrame},
};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, PartialEq, Eq)]
pub enum ResolutionError {
    MissingUnit,
    MissingRule,
    MissingTerrain,
    MissingTerrainCost,
    MissingPath,
    EmptyPath,
    DuplicateOrder,
    MissingFrame,
    InvalidAllowance,
}

impl std::fmt::Display for ResolutionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.message())
    }
}

impl std::error::Error for ResolutionError {}

impl ResolutionError {
    pub fn message(&self) -> &'static str {
        match self {
            Self::MissingUnit => "movement references a missing unit.",
            Self::MissingRule => "the unit has no movement rule.",
            Self::MissingTerrain => "movement is outside the map.",
            Self::MissingTerrainCost => "the terrain has no movement cost.",
            Self::MissingPath => "the unit has no resolved movement path.",
            Self::EmptyPath => "movement requires a starting position.",
            Self::DuplicateOrder => "each unit must have exactly one order.",
            Self::MissingFrame => "movement produced no board frame.",
            Self::InvalidAllowance => "movement allowances must be positive.",
        }
    }
}

pub struct MovementResolution {
    pub combat: Combat,
    pub paths: BTreeMap<UnitId, Vec<Coordinate>>,
    pub stopped: BTreeSet<UnitId>,
    pub frames: Vec<TurnFrame>,
}

fn frame(board: &Scenario, duration_ms: i32) -> TurnFrame {
    TurnFrame {
        departures: Vec::new(),
        indirect_impacts: Vec::new(),
        depots: board.depots.clone(),
        supply_crates: board.supply_crates.clone(),
        shots: Vec::new(),
        units: board.units.clone(),
        visible_tiles: Vec::new(),
        duration_ms,
    }
}

// A full movement turn is 2520ms (30ms per exact tick for current budgets).
const MOVEMENT_DURATION_MS: i32 = 2520;

struct ArrivalTime {
    cost: i32,
    allowance: i32,
}

fn arrival_time(
    scenario: &Scenario,
    id: UnitId,
    path: &[Coordinate],
) -> Result<ArrivalTime, ResolutionError> {
    let unit = scenario
        .units
        .iter()
        .find(|unit| unit.unit_id() == id)
        .ok_or(ResolutionError::MissingUnit)?;
    let rule = movement::rules()
        .into_iter()
        .find(|rule| rule.kind == unit.kind())
        .ok_or(ResolutionError::MissingRule)?;
    let mut cost = 0;
    for position in path.iter().skip(1) {
        let terrain = scenario
            .map
            .tile_at(*position)
            .ok_or(ResolutionError::MissingTerrain)?;
        cost += rule
            .terrain_costs
            .iter()
            .find(|entry| entry.terrain == terrain && entry.cost > 0)
            .ok_or(ResolutionError::MissingTerrainCost)?
            .cost;
    }
    Ok(ArrivalTime {
        cost,
        allowance: rule.budget,
    })
}

/// Resolve encounters before applying resources. A passing ally must not finish
/// on an occupied allied tile: shorten its outcome to the preceding free square,
/// then recheck arrivals so that newly blocked departures propagate consistently.
pub fn resolve(
    scenario: &Scenario,
    orders: &[MoveOrder],
    turn: i32,
) -> Result<MovementResolution, ResolutionError> {
    let loads = turns::planned_loads(scenario, orders);
    resolve_prepared(scenario, orders, turn, None, &loads)
}

/// Transport has finished; dismounted infantry cannot start another boarding.
pub fn resolve_dismounts(
    scenario: &Scenario,
    orders: &[MoveOrder],
    turn: i32,
    combat: &Combat,
) -> Result<MovementResolution, ResolutionError> {
    resolve_prepared(scenario, orders, turn, Some(combat), &[])
}

fn resolve_prepared(
    scenario: &Scenario,
    orders: &[MoveOrder],
    turn: i32,
    combat: Option<&Combat>,
    loads: &[PlannedLoad],
) -> Result<MovementResolution, ResolutionError> {
    let mut routes = orders.to_vec();
    let mut stopped = BTreeSet::new();
    loop {
        let mut result = resolve_arrivals(scenario, &routes, turn, combat)?;
        stopped.extend(&result.stopped);
        result.stopped = stopped.clone();
        let mut occupied: BTreeMap<Coordinate, Vec<_>> = BTreeMap::new();
        for unit in &result
            .frames
            .last()
            .ok_or(ResolutionError::MissingFrame)?
            .units
        {
            if unit.is_alive()
                && let Some(position) = unit.board_position()
            {
                occupied.entry(position).or_default().push(unit);
            }
        }
        let mut retreat = None;
        for units in occupied.values().filter(|units| units.len() > 1) {
            let ready_to_board = |unit: &Unit| {
                let reached_destination = orders.iter().any(|order| {
                    order.unit_id == unit.unit_id()
                        && order.path.last() == unit.board_position().as_ref()
                });
                reached_destination && !result.stopped.contains(&unit.unit_id())
            };
            // A mover and its loading target intentionally meet before boarding occurs.
            let loading = units.iter().any(|carrier| {
                units.iter().all(|passenger| {
                    let planned_pair = loads.contains(&PlannedLoad {
                        truck: carrier.unit_id(),
                        passenger: passenger.unit_id(),
                    });
                    carrier.unit_id() == passenger.unit_id()
                        || (planned_pair && ready_to_board(carrier) && ready_to_board(passenger))
                })
            });
            if loading {
                continue;
            }
            // Keep the resident; stable ID order settles simultaneous allied passage.
            let mut candidate: Option<(UnitId, ArrivalTime)> = None;
            for unit in units {
                let path = result
                    .paths
                    .get(&unit.unit_id())
                    .ok_or(ResolutionError::MissingPath)?;
                if path.len() <= 1 {
                    continue;
                }
                let time = arrival_time(scenario, unit.unit_id(), path)?;
                let replace = candidate.as_ref().is_none_or(|(id, previous)| {
                    (time.cost * previous.allowance)
                        .cmp(&(previous.cost * time.allowance))
                        .then_with(|| unit.unit_id().cmp(id))
                        .is_gt()
                });
                if replace {
                    candidate = Some((unit.unit_id(), time));
                }
            }
            if let Some((id, _)) = candidate {
                retreat = Some(id);
                break;
            }
        }
        let Some(id) = retreat else {
            return Ok(result);
        };
        stopped.insert(id);
        for route in &mut routes {
            route.path = result
                .paths
                .get(&route.unit_id)
                .ok_or(ResolutionError::MissingPath)?
                .clone();
            if route.unit_id == id {
                route.path.pop();
            }
        }
        // Every retry removes at least one path edge, so this converges to the
        // initially valid occupancy, including passengers still aboard.
    }
}

fn resolve_arrivals(
    scenario: &Scenario,
    orders: &[MoveOrder],
    turn: i32,
    combat: Option<&Combat>,
) -> Result<MovementResolution, ResolutionError> {
    let rules = movement::rules();
    fn gcd(a: i32, b: i32) -> i32 {
        if b == 0 { a } else { gcd(b, a % b) }
    }
    if rules.iter().any(|rule| rule.budget <= 0) {
        return Err(ResolutionError::InvalidAllowance);
    }
    let ticks = rules.iter().fold(1, |total, rule| {
        total / gcd(total, rule.budget) * rule.budget
    });
    let mut arrivals: BTreeMap<i32, Vec<(UnitId, Coordinate)>> = BTreeMap::new();
    for order in orders {
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == order.unit_id)
            .ok_or(ResolutionError::MissingUnit)?;
        let rule = rules
            .iter()
            .find(|rule| rule.kind == unit.kind())
            .ok_or(ResolutionError::MissingRule)?;
        let mut cost = 0;
        for destination in order.path.iter().skip(1) {
            let terrain = scenario
                .map
                .tile_at(*destination)
                .ok_or(ResolutionError::MissingTerrain)?;
            cost += rule
                .terrain_costs
                .iter()
                .find(|entry| entry.terrain == terrain && entry.cost > 0)
                .ok_or(ResolutionError::MissingTerrainCost)?
                .cost;
            arrivals
                .entry(cost * (ticks / rule.budget))
                .or_default()
                .push((order.unit_id, *destination));
        }
    }
    let mut board = scenario.clone();
    let mut paths = BTreeMap::new();
    for order in orders {
        let origin = *order.path.first().ok_or(ResolutionError::EmptyPath)?;
        if paths.insert(order.unit_id, vec![origin]).is_some() {
            return Err(ResolutionError::DuplicateOrder);
        }
        scenario
            .map
            .tile_at(origin)
            .ok_or(ResolutionError::MissingTerrain)?;
    }
    let initial_frame = frame(&board, 0);
    let combat = match combat {
        Some(combat) => combat.clone(),
        None => Combat::prepare(&mut board, orders),
    };
    let mut result = MovementResolution {
        combat,
        paths,
        stopped: BTreeSet::new(),
        frames: vec![initial_frame],
    };
    if orders.iter().any(|order| {
        order.facing.is_digging_in()
            || order.facing.is_ambush()
            || order.facing.is_standing_ground()
            || order.facing.indirect_target().is_some()
    }) {
        result.frames.push(frame(&board, 180));
    }
    let priority = if turn % 2 == 1 {
        PlayerNumber::Player1
    } else {
        PlayerNumber::Player2
    };
    let mut previous_tick = 0;
    for (tick, scheduled) in arrivals {
        let intents: BTreeMap<_, _> = scheduled
            .into_iter()
            .filter(|(id, _)| {
                !result.stopped.contains(id)
                    && board
                        .units
                        .iter()
                        .any(|unit| unit.unit_id() == *id && unit.is_alive())
            })
            .collect();
        let mut blocked = BTreeSet::new();
        let mut stop_after_arrival = BTreeSet::new();
        // Opposing claims on an empty square admit one team, then stop every claimant.
        for (id, destination) in &intents {
            let unit = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == *id)
                .ok_or(ResolutionError::MissingUnit)?;
            if intents.iter().any(|(other_id, other_destination)| {
                other_destination == destination
                    && board.units.iter().any(|other| {
                        other.unit_id() == *other_id
                            && other.player_number() != unit.player_number()
                    })
            }) {
                stop_after_arrival.insert(*id);
                if unit.player_number() != priority {
                    blocked.insert(*id);
                }
            }
        }
        // A successful departure frees a tile at this boundary. Swaps are blocked;
        // repeat until blocked departures can no longer allow another unit through.
        loop {
            let before = blocked.len();
            for (id, destination) in &intents {
                let unit = board
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == *id)
                    .ok_or(ResolutionError::MissingUnit)?;
                for enemy in board.units.iter().filter(|enemy| {
                    enemy.is_alive()
                        && enemy.player_number() != unit.player_number()
                        && enemy.board_position() == Some(*destination)
                }) {
                    let departure = intents.get(&enemy.unit_id());
                    let swaps =
                        departure.is_some_and(|target| Some(*target) == unit.board_position());
                    if departure.is_none() || blocked.contains(&enemy.unit_id()) || swaps {
                        blocked.insert(*id);
                        stop_after_arrival.insert(enemy.unit_id());
                        if swaps {
                            blocked.insert(enemy.unit_id());
                        }
                    }
                }
            }
            // A caught enemy must stop even if it had a departure at this boundary.
            for id in &stop_after_arrival {
                if !intents.contains_key(id) {
                    result.stopped.insert(*id);
                }
            }
            if blocked.len() == before {
                break;
            }
        }
        let mut contacts = Vec::new();
        for (id, destination) in &intents {
            if !orders.iter().any(|order| {
                order.unit_id == *id && order.travel == crate::turns::TravelMode::AttackMove
            }) {
                continue;
            }
            let mover = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == *id)
                .ok_or(ResolutionError::MissingUnit)?;
            let target = board
                .units
                .iter()
                .filter(|unit| unit.is_alive() && unit.player_number() != mover.player_number())
                .filter(|unit| {
                    (unit.board_position() == Some(*destination)
                        && (blocked.contains(&unit.unit_id())
                            || !intents.contains_key(&unit.unit_id())
                            || intents
                                .get(&unit.unit_id())
                                .is_some_and(|target| Some(*target) == mover.board_position())))
                        || intents.get(&unit.unit_id()) == Some(destination)
                })
                .min_by_key(|unit| unit.unit_id());
            if let Some(target) = target {
                contacts.push((*id, target.unit_id()));
                stop_after_arrival.insert(*id);
                stop_after_arrival.insert(target.unit_id());
            }
        }
        let completing_attack_moves: Vec<_> = orders
            .iter()
            .filter(|order| {
                order.travel == crate::turns::TravelMode::AttackMove
                    && intents.get(&order.unit_id) == order.path.last()
                    && !blocked.contains(&order.unit_id)
                    && !stop_after_arrival.contains(&order.unit_id)
            })
            .map(|order| (order.unit_id, order.facing))
            .collect();
        for (id, destination) in intents {
            if !blocked.contains(&id) {
                let passenger_count = scenario.passenger_count(id);
                let unit = board
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == id)
                    .ok_or(ResolutionError::MissingUnit)?;
                let path = result
                    .paths
                    .get_mut(&id)
                    .ok_or(ResolutionError::MissingPath)?;
                let origin = *path.last().ok_or(ResolutionError::EmptyPath)?;
                unit.follow_terrain_path(&board.map, &[origin, destination], passenger_count);
                path.push(destination);
            }
        }
        result.stopped.extend(blocked);
        result.stopped.extend(stop_after_arrival);
        // Check the final facing after every simultaneous arrival has been applied.
        // Adjacent contact is physical, just like attempting to enter an enemy tile.
        for (id, facing) in completing_attack_moves {
            let mover = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == id)
                .ok_or(ResolutionError::MissingUnit)?;
            if let FacingOrder::AfterMove(direction) = facing {
                mover.rotate(direction);
            }
            let origin = mover.board_position().ok_or(ResolutionError::MissingUnit)?;
            let direction = mover.direction();
            let player = mover.player_number();
            let target = board
                .units
                .iter()
                .filter(|unit| unit.is_alive() && unit.player_number() != player)
                .filter(|unit| {
                    unit.board_position().is_some_and(|destination| {
                        (destination.x() - origin.x()).abs() + (destination.y() - origin.y()).abs()
                            == 1
                            && crate::scenario::Direction::between(origin, destination) == direction
                    })
                })
                .min_by_key(|unit| unit.unit_id());
            if let Some(target) = target {
                contacts.push((id, target.unit_id()));
                result.stopped.extend([id, target.unit_id()]);
            }
        }
        // A contact can interrupt passage through an allied square. Retreat before
        // combat so its contact check uses the final, unoccupied positions.
        let participants: BTreeSet<_> = contacts
            .iter()
            .flat_map(|(attacker, target)| [*attacker, *target])
            .collect();
        for id in participants {
            let unit = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == id)
                .ok_or(ResolutionError::MissingUnit)?;
            let shared = board.units.iter().any(|other| {
                other.is_alive()
                    && other.unit_id() != id
                    && other.board_position() == unit.board_position()
            });
            if !shared {
                continue;
            }
            let path = result
                .paths
                .get_mut(&id)
                .ok_or(ResolutionError::MissingPath)?;
            let free = path
                .iter()
                .enumerate()
                .rev()
                .find(|(_, position)| {
                    !board.units.iter().any(|other| {
                        other.is_alive()
                            && other.unit_id() != id
                            && other.board_position() == Some(**position)
                    })
                })
                .map(|(index, _)| index);
            if let Some(index) = free {
                let discarded_path = path[index..].to_vec();
                path.truncate(index + 1);
                let initial = scenario
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == id)
                    .ok_or(ResolutionError::MissingUnit)?;
                let passenger_count = scenario.passenger_count(id);
                let unit = board
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == id)
                    .ok_or(ResolutionError::MissingUnit)?;
                unit.retract_movement(path, &board.map, &discarded_path, initial, passenger_count);
            }
        }
        // Retain waiting time even after a route ends; timing is independent of its length.
        result.frames.push(frame(
            &board,
            (tick - previous_tick) * MOVEMENT_DURATION_MS / ticks,
        ));
        result.combat.engage_contacts(
            &mut board,
            &mut result.stopped,
            &mut result.frames,
            &contacts,
        );
        previous_tick = tick;
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        combat::CombatKind,
        map::{Map, Terrain},
        scenario::UnitKind,
        turns::MoveOrder,
    };

    fn setup(
        paths: &[(&str, &[(u16, u16)])],
    ) -> Result<(Scenario, Vec<MoveOrder>), Box<dyn std::error::Error>> {
        let mut scenario = Scenario::supply_point().map_err(|error| format!("{error:?}"))?;
        scenario.map = Map::new(17, 17, Terrain::Plain, BTreeMap::new())
            .map_err(|error| format!("{error:?}"))?;
        scenario
            .units
            .retain(|unit| paths.iter().any(|(id, _)| unit.id() == *id));
        let orders = paths
            .iter()
            .map(|(id, path)| {
                let moving = scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.id() == *id)
                    .ok_or("missing fixture unit")?;
                let path: Vec<_> = path.iter().map(|(x, y)| Coordinate::new(*x, *y)).collect();
                moving.move_to(*path.first().ok_or("empty fixture path")?);
                Ok(MoveOrder {
                    supply: crate::supplies::SupplyOrder::default(),
                    travel: crate::turns::TravelMode::Normal,
                    facing: crate::turns::FacingOrder::Unchanged,
                    unit_id: moving.unit_id(),
                    path,
                    unloads: Vec::new(),
                })
            })
            .collect::<Result<Vec<_>, &str>>()?;
        Ok((scenario, orders))
    }

    fn path(
        result: &MovementResolution,
        id: &str,
    ) -> Result<Vec<Coordinate>, Box<dyn std::error::Error>> {
        Ok(result
            .paths
            .get(&UnitId::parse(id).ok_or("invalid fixture id")?)
            .ok_or("missing fixture path")?
            .clone())
    }

    #[test]
    fn jammed_attack_moves_cannot_fire_across_allied_units()
    -> Result<(), Box<dyn std::error::Error>> {
        for destination in [1, 2, 3] {
            let route: Vec<_> = (0..=destination).map(|x| (x, 0)).collect();
            let (scenario, mut orders) = setup(&[
                ("11", &route),
                ("1", &[(1, 0)]),
                ("2", &[(2, 0)]),
                ("6", &[(3, 0)]),
            ])?;
            orders.first_mut().ok_or("missing attack order")?.travel =
                crate::turns::TravelMode::AttackMove;
            for turn in [1, 2] {
                let result = resolve(&scenario, &orders, turn)?;
                assert_eq!(path(&result, "11")?, vec![Coordinate::new(0, 0)]);
                assert!(result.frames.iter().all(|frame| frame.shots.is_empty()));
                let final_units = &result.frames.last().ok_or("missing final frame")?.units;
                for unit in final_units {
                    let initial = scenario
                        .units
                        .iter()
                        .find(|initial| initial.unit_id() == unit.unit_id())
                        .ok_or("missing initial unit")?;
                    assert_eq!(unit.hit_points(), initial.hit_points());
                    assert_eq!(unit.fuel(), initial.fuel());
                }
                orders.reverse();
            }
        }
        Ok(())
    }

    #[test]
    fn tank_catches_infantry_and_short_routes_arrive_early()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, orders) = setup(&[
            (
                "11",
                &[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0)],
            ),
            ("6", &[(2, 0), (3, 0), (4, 0)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(
            path(&result, "11")?,
            vec![Coordinate::new(0, 0), Coordinate::new(1, 0)]
        );
        assert_eq!(path(&result, "6")?, vec![Coordinate::new(2, 0)]);
        assert_eq!(result.stopped.len(), 2);
        let (scenario, orders) = setup(&[("11", &[(0, 0), (1, 0)]), ("6", &[(3, 0), (4, 0)])])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(result.frames[1].duration_ms, 420);
        assert_eq!(
            result.frames[1]
                .units
                .iter()
                .find(|unit| unit.id() == "6")
                .ok_or("missing fixture unit")?
                .board_position(),
            Some(Coordinate::new(3, 0))
        );
        assert_eq!(result.frames[2].duration_ms, 840);
        Ok(())
    }

    #[test]
    fn intersections_at_different_times_miss_but_equal_claims_stop_and_alternate()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, orders) = setup(&[
            ("11", &[(0, 1), (1, 1), (2, 1), (3, 1)]),
            ("6", &[(1, 0), (1, 1), (1, 2)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert!(result.stopped.is_empty());
        assert_eq!(path(&result, "11")?, orders[0].path);
        assert_eq!(path(&result, "6")?, orders[1].path);
        let (scenario, mut orders) = setup(&[
            ("1", &[(0, 1), (1, 1), (2, 1)]),
            ("6", &[(1, 0), (1, 1), (1, 2)]),
        ])?;
        for turn in [1, 2] {
            let result = resolve(&scenario, &orders, turn)?;
            assert_eq!(result.stopped.len(), 2);
            let winner = if turn == 1 { "1" } else { "6" };
            let loser = if turn == 1 { "6" } else { "1" };
            assert_eq!(path(&result, winner)?.last(), Some(&Coordinate::new(1, 1)));
            assert_eq!(path(&result, loser)?.len(), 1);
            orders.reverse();
            let reversed = resolve(&scenario, &orders, turn)?;
            assert_eq!(result.paths, reversed.paths);
        }
        Ok(())
    }

    #[test]
    fn opposing_swaps_stop_and_blocked_departures_propagate()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, orders) = setup(&[
            ("1", &[(0, 0), (1, 0)]),
            ("6", &[(1, 0), (0, 0)]),
            ("2", &[(2, 0), (1, 0)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(result.stopped.len(), 3);
        for order in orders {
            assert_eq!(result.paths[&order.unit_id], vec![order.path[0]]);
        }
        Ok(())
    }

    #[test]
    fn mountain_entry_uses_the_full_infantry_movement_timeline()
    -> Result<(), Box<dyn std::error::Error>> {
        let (mut scenario, orders) = setup(&[("1", &[(0, 0), (1, 0)])])?;
        scenario.map = Map::from_ascii(".^.").map_err(|error| format!("{error:?}"))?;
        let arrival = arrival_time(&scenario, orders[0].unit_id, &orders[0].path)?;
        assert_eq!(arrival.cost, arrival.allowance);
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(path(&result, "1")?, orders[0].path);
        assert_eq!(result.frames[1].duration_ms, MOVEMENT_DURATION_MS);
        Ok(())
    }

    #[test]
    fn resolution_rejects_vehicle_mountain_routes() -> Result<(), Box<dyn std::error::Error>> {
        for kind in [UnitKind::Tank, UnitKind::Truck, UnitKind::FieldGun] {
            let fixture = Scenario::supply_point().map_err(|error| format!("{error:?}"))?;
            let id = fixture
                .units
                .iter()
                .find(|unit| unit.kind() == kind)
                .ok_or("missing fixture vehicle")?
                .id();
            let (mut scenario, orders) = setup(&[(&id, &[(0, 0), (1, 0)])])?;
            scenario.map = Map::from_ascii(".^.").map_err(|error| format!("{error:?}"))?;
            assert!(matches!(
                resolve(&scenario, &orders, 1),
                Err(ResolutionError::MissingTerrainCost)
            ));
        }
        Ok(())
    }

    #[test]
    fn terrain_delays_arrival_and_allies_allow_passage() -> Result<(), Box<dyn std::error::Error>> {
        let (mut scenario, orders) = setup(&[("11", &[(0, 0), (1, 0), (2, 0)]), ("1", &[(1, 0)])])?;
        scenario.map = Map::from_ascii(".%.").map_err(|error| format!("{error:?}"))?;
        let result = resolve(&scenario, &orders, 1)?;
        assert!(result.stopped.is_empty());
        assert_eq!(path(&result, "11")?, orders[0].path);
        assert_eq!(result.frames[1].duration_ms, 840);
        assert_eq!(result.frames[2].duration_ms, 420);
        Ok(())
    }

    #[test]
    fn interrupted_allied_passage_stops_at_preceding_free_square()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, orders) = setup(&[
            ("1", &[(0, 0), (1, 0), (2, 0)]),
            ("2", &[(1, 0)]),
            ("14", &[(4, 0), (3, 0), (2, 0), (1, 0), (0, 0)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(path(&result, "1")?, vec![Coordinate::new(0, 0)]);
        assert_eq!(path(&result, "2")?, vec![Coordinate::new(1, 0)]);
        assert_eq!(path(&result, "14")?.last(), Some(&Coordinate::new(2, 0)));
        let final_units = &result.frames.last().ok_or("missing frame")?.units;
        let occupied: BTreeSet<_> = final_units
            .iter()
            .filter_map(|unit| unit.board_position())
            .collect();
        assert_eq!(occupied.len(), final_units.len());
        assert!(
            result
                .stopped
                .contains(&UnitId::parse("1").ok_or("invalid fixture id")?)
        );
        assert_eq!(
            result.paths,
            resolve(&scenario, &orders.into_iter().rev().collect::<Vec<_>>(), 1)?.paths
        );
        Ok(())
    }

    #[test]
    fn caught_moving_enemy_stops_before_its_next_arrival() -> Result<(), Box<dyn std::error::Error>>
    {
        let (scenario, orders) = setup(&[
            ("11", &[(0, 1), (1, 1), (2, 1), (3, 1)]),
            ("6", &[(2, 0), (2, 1), (2, 2)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        // Departures at the same boundary allow a crossing when it is not a swap.
        assert_eq!(path(&result, "11")?.last(), Some(&Coordinate::new(3, 1)));
        assert!(result.stopped.is_empty());
        let (scenario, orders) = setup(&[
            ("11", &[(0, 1), (1, 1), (2, 1), (3, 1), (4, 1)]),
            ("6", &[(3, 0), (3, 1), (3, 2)]),
        ])?;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(result.stopped.len(), 2);
        assert_eq!(path(&result, "11")?.last(), Some(&Coordinate::new(3, 1)));
        assert_eq!(path(&result, "6")?.len(), 1);
        Ok(())
    }
    #[test]
    fn attack_move_stops_at_first_enemy_and_charges_only_traveled_edges()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, mut orders) = setup(&[("1", &[(0, 0), (1, 0), (2, 0)]), ("6", &[(2, 0)])])?;
        orders[0].travel = crate::turns::TravelMode::AttackMove;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(
            path(&result, "1")?,
            vec![Coordinate::new(0, 0), Coordinate::new(1, 0)]
        );
        let shots: Vec<_> = result
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .collect();
        assert_eq!(shots.len(), 1);
        assert_eq!(shots[0].kind, CombatKind::AttackMove);
        assert_eq!(shots[0].destination, Coordinate::new(2, 0));
        assert_eq!(shots[0].target_health.after.current(), 5);
        let units = &result.frames.last().ok_or("missing frame")?.units;
        assert_eq!(
            units
                .iter()
                .find(|unit| unit.id() == "1")
                .ok_or("missing attacker")?
                .supplies()
                .current(),
            160
        );
        assert_eq!(
            units
                .iter()
                .find(|unit| unit.id() == "6")
                .ok_or("missing target")?
                .supplies()
                .current(),
            192
        );
        Ok(())
    }

    #[test]
    fn attack_move_interrupted_during_allied_passage_loses_contact()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, mut orders) = setup(&[
            ("11", &[(0, 0), (1, 0), (2, 0), (3, 0)]),
            ("1", &[(1, 0)]),
            ("6", &[(2, 0)]),
        ])?;
        orders[0].travel = crate::turns::TravelMode::AttackMove;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(path(&result, "11")?, vec![Coordinate::new(0, 0)]);
        let shots: Vec<_> = result
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .collect();
        assert!(shots.is_empty());
        let units = &result.frames.last().ok_or("missing frame")?.units;
        assert_eq!(
            units
                .iter()
                .find(|unit| unit.id() == "11")
                .ok_or("missing attacker")?
                .fuel()
                .ok_or("missing fuel")?
                .current,
            128
        );
        let occupied: BTreeSet<_> = units
            .iter()
            .filter_map(|unit| unit.board_position())
            .collect();
        assert_eq!(occupied.len(), units.len());
        assert_eq!(
            units
                .iter()
                .find(|unit| unit.id() == "6")
                .ok_or("missing target")?
                .hit_points()
                .current(),
            16
        );
        Ok(())
    }

    #[test]
    fn attack_move_fires_at_an_enemy_directly_ahead_of_its_destination()
    -> Result<(), Box<dyn std::error::Error>> {
        for attacker in ["1", "11"] {
            for (destination, enemy) in [
                ((3, 2), (3, 1)),
                ((4, 3), (5, 3)),
                ((3, 4), (3, 5)),
                ((2, 3), (1, 3)),
            ] {
                let route = [(3, 3), destination];
                let defender = [enemy];
                let (scenario, mut orders) = setup(&[(attacker, &route), ("6", &defender)])?;
                orders[0].travel = crate::turns::TravelMode::AttackMove;
                let result = resolve(&scenario, &orders, 1)?;
                assert_eq!(path(&result, attacker)?, orders[0].path);
                let shots: Vec<_> = result
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .collect();
                assert_eq!(shots.len(), 1);
                let shot = shots.first().ok_or("missing final contact")?;
                assert_eq!(shot.kind, CombatKind::AttackMove);
                assert_eq!(shot.origin, Coordinate::new(destination.0, destination.1));
                assert_eq!(shot.destination, Coordinate::new(enemy.0, enemy.1));
                let damage = if attacker == "11" { 16 } else { 11 };
                assert_eq!(shot.target_health.after.current(), 16 - damage);
                let unit = result
                    .frames
                    .last()
                    .ok_or("missing frame")?
                    .units
                    .iter()
                    .find(|unit| unit.id() == attacker)
                    .ok_or("missing attacker")?;
                let supplies = if attacker == "11" { 104 } else { 160 };
                assert_eq!(unit.supplies().current(), supplies);
                assert_eq!(result.stopped.len(), 2);
            }
        }
        Ok(())
    }

    #[test]
    fn completed_attack_moves_turn_and_fire_in_the_chosen_direction()
    -> Result<(), Box<dyn std::error::Error>> {
        use crate::scenario::Direction;
        for attacker in ["1", "11"] {
            for (direction, enemy) in [
                (Direction::North, (4, 2)),
                (Direction::South, (4, 4)),
                (Direction::West, (3, 3)),
            ] {
                let (scenario, mut orders) =
                    setup(&[(attacker, &[(3, 3), (4, 3)]), ("6", &[enemy])])?;
                orders[0].travel = turns::TravelMode::AttackMove;
                orders[0].facing = FacingOrder::AfterMove(direction);
                let result = resolve(&scenario, &orders, 1)?;
                let shots: Vec<_> = result
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .collect();
                assert_eq!(shots.len(), 1);
                assert_eq!(
                    shots
                        .first()
                        .ok_or("missing chosen-direction shot")?
                        .destination,
                    Coordinate::new(enemy.0, enemy.1)
                );
                let arrived = result
                    .frames
                    .last()
                    .ok_or("missing final frame")?
                    .units
                    .iter()
                    .find(|unit| unit.id() == attacker)
                    .ok_or("missing attacker")?;
                assert_eq!(arrived.direction(), Some(direction));
                assert_eq!(path(&result, attacker)?, orders[0].path);
            }
        }
        Ok(())
    }

    #[test]
    fn final_facing_applies_without_a_target_but_not_after_early_contact()
    -> Result<(), Box<dyn std::error::Error>> {
        use crate::scenario::Direction;
        for (enemy, interrupted) in [((8, 8), false), ((5, 3), false), ((4, 3), true)] {
            let (scenario, mut orders) =
                setup(&[("1", &[(2, 3), (3, 3), (4, 3)]), ("6", &[enemy])])?;
            orders[0].travel = turns::TravelMode::AttackMove;
            orders[0].facing = FacingOrder::AfterMove(Direction::North);
            let result = resolve(&scenario, &orders, 1)?;
            let arrived = result
                .frames
                .last()
                .ok_or("missing final frame")?
                .units
                .iter()
                .find(|unit| unit.id() == "1")
                .ok_or("missing attacker")?;
            assert_eq!(
                arrived.direction(),
                Some(if interrupted {
                    Direction::East
                } else {
                    Direction::North
                })
            );
            assert_eq!(
                arrived.board_position(),
                Some(Coordinate::new(if interrupted { 3 } else { 4 }, 3))
            );
            assert_eq!(
                result.frames.iter().flat_map(|frame| &frame.shots).count(),
                usize::from(interrupted)
            );
        }
        Ok(())
    }

    #[test]
    fn final_attack_contact_requires_an_adjacent_enemy_ahead()
    -> Result<(), Box<dyn std::error::Error>> {
        for (target, enemy, attack) in [
            ("6", (3, 2), true),  // Beside.
            ("6", (2, 3), true),  // Behind.
            ("6", (4, 2), true),  // Diagonal.
            ("6", (5, 3), true),  // Two tiles ahead.
            ("2", (4, 3), true),  // Ally.
            ("6", (4, 3), false), // Ordinary move.
        ] {
            let defender = [enemy];
            let (scenario, mut orders) = setup(&[("1", &[(2, 3), (3, 3)]), (target, &defender)])?;
            if attack {
                orders[0].travel = crate::turns::TravelMode::AttackMove;
            }
            let result = resolve(&scenario, &orders, 1)?;
            assert!(result.frames.iter().all(|frame| frame.shots.is_empty()));
        }
        Ok(())
    }

    #[test]
    fn final_attack_contact_interrupts_a_later_enemy_departure_and_handles_concealment()
    -> Result<(), Box<dyn std::error::Error>> {
        for concealed in [false, true] {
            let (mut scenario, mut orders) =
                setup(&[("11", &[(0, 0), (1, 0)]), ("6", &[(2, 0), (3, 0)])])?;
            if concealed {
                scenario.map = Map::from_ascii("..#.").map_err(|error| format!("{error:?}"))?;
            }
            orders[0].travel = crate::turns::TravelMode::AttackMove;
            let result = resolve(&scenario, &orders, 1)?;
            assert_eq!(path(&result, "6")?, vec![Coordinate::new(2, 0)]);
            assert_eq!(
                result.frames.iter().flat_map(|frame| &frame.shots).count(),
                1
            );
        }
        Ok(())
    }

    #[test]
    fn opposing_attack_moves_finishing_adjacent_fire_simultaneously()
    -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, mut orders) = setup(&[("1", &[(0, 0), (1, 0)]), ("6", &[(3, 0), (2, 0)])])?;
        for order in &mut orders {
            order.travel = crate::turns::TravelMode::AttackMove;
        }
        for turn in [1, 2] {
            let result = resolve(&scenario, &orders, turn)?;
            let volley = result
                .frames
                .iter()
                .find(|frame| !frame.shots.is_empty())
                .ok_or("missing volley")?;
            assert_eq!(volley.shots.len(), 2);
            assert!(
                volley
                    .shots
                    .iter()
                    .all(|shot| shot.attacker_health.after.current() == 9
                        && shot.target_health.after.current() == 9)
            );
            orders.reverse();
            let reversed = resolve(&scenario, &orders, turn)?;
            assert_eq!(result.paths, reversed.paths);
            let health = |resolution: &MovementResolution| {
                resolution.frames.last().map(|frame| {
                    frame
                        .units
                        .iter()
                        .map(|unit| unit.hit_points().current())
                        .collect::<Vec<_>>()
                })
            };
            assert_eq!(health(&result), health(&reversed));
        }
        Ok(())
    }

    #[test]
    fn attack_move_passes_allies_and_misses_departing_enemies()
    -> Result<(), Box<dyn std::error::Error>> {
        for paths in [
            vec![("11", &[(0, 0), (1, 0), (2, 0)][..]), ("1", &[(1, 0)][..])],
            vec![
                ("1", &[(0, 0), (1, 0), (2, 0)][..]),
                ("6", &[(1, 0), (2, 0), (2, 1)][..]),
            ],
        ] {
            let (scenario, mut orders) = setup(&paths)?;
            orders[0].travel = crate::turns::TravelMode::AttackMove;
            let result = resolve(&scenario, &orders, 1)?;
            assert!(result.frames.iter().all(|frame| frame.shots.is_empty()));
            assert_eq!(
                result.paths.get(&orders[0].unit_id).ok_or("missing path")?,
                &orders[0].path
            );
        }
        Ok(())
    }

    #[test]
    fn attack_moves_fire_simultaneously_on_swaps_and_contested_arrivals()
    -> Result<(), Box<dyn std::error::Error>> {
        for paths in [
            vec![("1", &[(0, 0), (1, 0)][..]), ("6", &[(1, 0), (0, 0)][..])],
            vec![
                ("1", &[(0, 0), (1, 0), (2, 0)][..]),
                ("6", &[(2, 0), (1, 0), (0, 0)][..]),
            ],
        ] {
            let (scenario, mut orders) = setup(&paths)?;
            for order in &mut orders {
                order.travel = crate::turns::TravelMode::AttackMove;
            }
            for turn in [1, 2] {
                let result = resolve(&scenario, &orders, turn)?;
                let shots: Vec<_> = result
                    .frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .collect();
                assert_eq!(shots.len(), 2);
                assert!(
                    shots
                        .iter()
                        .all(|shot| shot.target_health.after.current() == 9
                            && shot.attacker_health.after.current() == 9)
                );
                assert_eq!(result.stopped.len(), 2);
                orders.reverse();
                let reversed = resolve(&scenario, &orders, turn)?;
                assert_eq!(result.paths, reversed.paths);
                assert_eq!(
                    result
                        .frames
                        .last()
                        .ok_or("missing frame")?
                        .units
                        .iter()
                        .map(|unit| unit.hit_points().current())
                        .collect::<Vec<_>>(),
                    reversed
                        .frames
                        .last()
                        .ok_or("missing frame")?
                        .units
                        .iter()
                        .map(|unit| unit.hit_points().current())
                        .collect::<Vec<_>>()
                );
            }
        }
        Ok(())
    }

    #[test]
    fn attack_move_finds_a_concealed_enemy_without_revealing_its_route()
    -> Result<(), Box<dyn std::error::Error>> {
        let (mut scenario, mut orders) =
            setup(&[("1", &[(0, 0), (1, 0), (2, 0)]), ("6", &[(1, 0)])])?;
        scenario.map = Map::from_ascii(".#.").map_err(|error| format!("{error:?}"))?;
        orders[0].travel = crate::turns::TravelMode::AttackMove;
        let result = resolve(&scenario, &orders, 1)?;
        assert_eq!(path(&result, "1")?.len(), 1);
        let resolution = crate::turns::TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        let visible = crate::visibility::visible_tiles(&scenario, PlayerNumber::Player1);
        let observed = crate::visibility::observed_resolution(
            &scenario,
            PlayerNumber::Player1,
            &visible,
            &resolution,
        );
        let shot = observed
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .next()
            .ok_or("missing encounter")?;
        assert_eq!(shot.target.id(), "6");
        assert!(shot.target.resources().is_none());
        Ok(())
    }

    #[test]
    fn invalid_resolution_inputs_return_errors() -> Result<(), Box<dyn std::error::Error>> {
        let (scenario, orders) = setup(&[("1", &[(0, 0), (1, 0)])])?;
        let mut missing = scenario.clone();
        missing.units.clear();
        assert_eq!(
            resolve(&missing, &orders, 1).err(),
            Some(ResolutionError::MissingUnit)
        );
        let mut invalid = orders.clone();
        invalid[0].path.clear();
        assert_eq!(
            resolve(&scenario, &invalid, 1).err(),
            Some(ResolutionError::EmptyPath)
        );
        invalid[0].path = vec![Coordinate::new(0, 0), Coordinate::new(17, 0)];
        assert_eq!(
            resolve(&scenario, &invalid, 1).err(),
            Some(ResolutionError::MissingTerrain)
        );
        invalid = vec![orders[0].clone(), orders[0].clone()];
        assert_eq!(
            resolve(&scenario, &invalid, 1).err(),
            Some(ResolutionError::DuplicateOrder)
        );
        assert_eq!(
            scenario.units[0].board_position(),
            Some(Coordinate::new(0, 0))
        );
        Ok(())
    }
}
