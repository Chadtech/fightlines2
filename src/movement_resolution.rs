//! Shared arrivals use accumulated terrain cost / full movement allowance.
//! Integer ticks are the least common multiple of allowances, never float comparisons.
use crate::{
    map::Coordinate,
    movement,
    scenario::{PlayerNumber, Scenario, UnitId},
    turns::{MoveOrder, TurnFrame},
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
    pub combat: crate::combat::Combat,
    pub paths: BTreeMap<UnitId, Vec<Coordinate>>,
    pub stopped: BTreeSet<UnitId>,
    pub frames: Vec<TurnFrame>,
}

fn frame(board: &Scenario, duration_ms: i32) -> TurnFrame {
    TurnFrame {
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
            .find(|entry| entry.terrain == terrain)
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
    let mut routes = orders.to_vec();
    let mut stopped = BTreeSet::new();
    loop {
        let mut result = resolve_arrivals(scenario, &routes, turn)?;
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
            // A mover and its loading target intentionally meet before boarding occurs.
            let loading = units.iter().any(|carrier| {
                units.iter().all(|passenger| {
                    carrier.unit_id() == passenger.unit_id()
                        || (scenario.loading_pair(carrier, passenger).is_some()
                            && !result.stopped.contains(&carrier.unit_id())
                            && !result.stopped.contains(&passenger.unit_id()))
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
                .find(|entry| entry.terrain == terrain)
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
    let combat = crate::combat::Combat::prepare(&mut board, orders);
    let mut result = MovementResolution {
        combat,
        paths,
        stopped: BTreeSet::new(),
        frames: vec![initial_frame],
    };
    if orders.iter().any(|order| order.facing.is_ambush()) {
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
            .filter(|(id, _)| !result.stopped.contains(id))
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
                    && board
                        .units
                        .iter()
                        .any(|other| other.unit_id() == *other_id && other.side() != unit.side())
            }) {
                stop_after_arrival.insert(*id);
                if unit.side() != priority {
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
                        && enemy.side() != unit.side()
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
        for (id, destination) in intents {
            if !blocked.contains(&id) {
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
                unit.follow_path(&[origin, destination]);
                path.push(destination);
            }
        }
        result.stopped.extend(blocked);
        result.stopped.extend(stop_after_arrival);
        // Retain waiting time even after a route ends; timing is independent of its length.
        result.frames.push(frame(
            &board,
            (tick - previous_tick) * MOVEMENT_DURATION_MS / ticks,
        ));
        result
            .combat
            .engage(&mut board, &mut result.stopped, &mut result.frames);
        previous_tick = tick;
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::{Map, Terrain},
        turns::MoveOrder,
    };

    fn setup(
        paths: &[(&str, &[(u16, u16)])],
    ) -> Result<(Scenario, Vec<MoveOrder>), Box<dyn std::error::Error>> {
        let mut scenario = Scenario::supply_point().map_err(|error| format!("{error:?}"))?;
        scenario.map = Map::new(17, 17, Terrain::GrassPlain, BTreeMap::new())
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
