use crate::{
    map::{Coordinate, Map, Terrain},
    scenario::{Direction, Scenario, Side, Unit, UnitKind},
    turns::{TurnEventKind, TurnFrame, TurnResolution},
};
use std::collections::BTreeSet;

/// Sight is a circular radius measured between tile centers.
pub fn sight_range(kind: UnitKind) -> i32 {
    match kind {
        UnitKind::Infantry | UnitKind::FieldGun => 4,
        UnitKind::Truck => 3,
        UnitKind::Tank => 2,
    }
}

pub fn visible_tiles(scenario: &Scenario, side: Side) -> BTreeSet<Coordinate> {
    let mut visible = BTreeSet::new();
    for (unit, origin) in scenario
        .units
        .iter()
        .filter(|unit| unit.side() == side)
        .filter_map(|unit| unit.board_position().map(|origin| (unit, origin)))
    {
        // The occupied square is known even when the unit is in a forest.
        visible.insert(origin);
        let bonus = i32::from(scenario.map.tile_at(origin) == Some(Terrain::Hills));
        let range = sight_range(unit.kind()) + bonus;
        for y in (origin.y() - range).max(0)..=(origin.y() + range).min(scenario.map.height() - 1) {
            for x in
                (origin.x() - range).max(0)..=(origin.x() + range).min(scenario.map.width() - 1)
            {
                let target = Coordinate::new(x as u16, y as u16);
                let dx = x - origin.x();
                let dy = y - origin.y();
                let within_sight = dx * dx + dy * dy <= range * range;
                if within_sight
                    && scenario.map.tile_at(target) != Some(Terrain::Forest)
                    && clear_line(&scenario.map, origin, target)
                {
                    visible.insert(target);
                }
            }
        }
    }
    visible
}

/// Trace cells crossed by the center-to-center sight line. Touching a corner
/// does not enter the adjacent cells, so their terrain does not block sight.
/// Target hills remain visible; forests conceal their contents. Intervening
/// hills and forests block even elevated observers; the origin never blocks.
fn clear_line(map: &Map, origin: Coordinate, target: Coordinate) -> bool {
    let dx = target.x() - origin.x();
    let dy = target.y() - origin.y();
    let nx = dx.abs();
    let ny = dy.abs();
    let mut x = origin.x();
    let mut y = origin.y();
    let mut ix = 0;
    let mut iy = 0;
    let blocks = |x: i32, y: i32| {
        let position = Coordinate::new(x as u16, y as u16);
        let blocking_terrain = match map.tile_at(position) {
            Some(Terrain::Hills | Terrain::Forest) => true,
            Some(Terrain::GrassPlain) | None => false,
        };
        position != origin && position != target && blocking_terrain
    };
    while ix < nx || iy < ny {
        let decision =
            i64::from(1 + 2 * ix) * i64::from(ny) - i64::from(1 + 2 * iy) * i64::from(nx);
        if decision == 0 {
            x += dx.signum();
            y += dy.signum();
            ix += 1;
            iy += 1;
        } else if decision < 0 {
            x += dx.signum();
            ix += 1;
        } else {
            y += dy.signum();
            iy += 1;
        }
        if blocks(x, y) {
            return false;
        }
    }
    true
}

fn observable(map: &Map, visible: &BTreeSet<Coordinate>, position: Coordinate) -> bool {
    visible.contains(&position) && map.tile_at(position) != Some(Terrain::Forest)
}

pub fn observed_scenario(
    scenario: &Scenario,
    side: Side,
    visible: &BTreeSet<Coordinate>,
) -> Scenario {
    let mut observed = scenario.clone();
    observed.units.retain(|unit| {
        unit.side() == side
            || unit
                .board_position()
                .is_some_and(|position| observable(&scenario.map, visible, position))
    });
    observed
}

/// Keep own summary events and only wholly observable enemy summaries.
/// Partial enemy sightings are represented exclusively by projected frames.
pub fn observed_resolution(
    scenario: &Scenario,
    side: Side,
    visible: &BTreeSet<Coordinate>,
    resolution: &TurnResolution,
) -> TurnResolution {
    let before = initial_scenario(scenario, resolution);
    let initial_visible = visible_tiles(&before, side);
    let mut observed = resolution.clone();
    observed.frames = observed_frames(scenario, side, resolution);
    observed.events.retain(|event| {
        let unit: Option<&Unit> = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == event.unit_id);
        unit.is_some_and(|unit| {
            unit.side() == side
                || (unit
                    .board_position()
                    .is_some_and(|position| observable(&scenario.map, visible, position))
                    && event.path.iter().all(|position| {
                        observable(&scenario.map, &initial_visible, *position)
                            && observable(&scenario.map, visible, *position)
                    })
                    && observed.frames.iter().all(|frame| {
                        frame
                            .units
                            .iter()
                            .any(|seen| seen.unit_id() == event.unit_id)
                            && event.path.iter().all(|position| {
                                frame.visible_tiles.contains(position)
                                    && scenario.map.tile_at(*position) != Some(Terrain::Forest)
                            })
                    }))
        })
    });
    observed
}

fn initial_scenario(scenario: &Scenario, resolution: &TurnResolution) -> Scenario {
    let mut board = scenario.clone();
    for unit in &mut board.units {
        if let Some(event) = resolution
            .events
            .iter()
            .find(|event| event.unit_id == unit.unit_id())
        {
            match event.initial_carrier {
                Some(carrier) => unit.board(carrier),
                None => {
                    if let Some(origin) = event.path.first() {
                        unit.move_to(*origin);
                    }
                }
            }
            if let Some(direction) = event.initial_direction {
                unit.rotate(direction);
            }
        }
    }
    board
}

/// One unit completes its route at a time in the stored interleaved order. Project each frame
/// independently so even a transient sighting is replayed without hidden routes.
fn observed_frames(scenario: &Scenario, side: Side, resolution: &TurnResolution) -> Vec<TurnFrame> {
    let mut board = initial_scenario(scenario, resolution);
    let project = |board: &Scenario| {
        let visible = visible_tiles(board, side);
        TurnFrame {
            units: observed_scenario(board, side, &visible).units,
            visible_tiles: visible.into_iter().collect(),
        }
    };
    let mut frames = vec![project(&board)];
    for event in &resolution.events {
        if let TurnEventKind::Hold | TurnEventKind::DestinationConflict = event.kind {
            continue;
        }
        let steps = event.path.len().saturating_sub(1).max(1);
        for step in 1..=steps {
            if let Some(unit) = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == event.unit_id)
            {
                if let Some(destination) = event.path.get(step) {
                    if let Some(direction) = Direction::between(event.path[step - 1], *destination)
                    {
                        unit.rotate(direction);
                    }
                    unit.move_to(*destination);
                }
                if step == steps {
                    if let Some(direction) = event.rotation_direction {
                        unit.rotate(direction);
                    }
                    if event.kind == TurnEventKind::Load
                        && let Some(carrier) = event.carrier_id
                    {
                        unit.board(carrier);
                    }
                }
            }
            frames.push(project(&board));
        }
    }
    // Use the authoritative final snapshot, including resources and transport.
    if let Some(last) = frames.last_mut() {
        *last = project(scenario);
    }
    frames
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::turns::{TurnEvent, TurnEventKind};

    fn scenario(kind: UnitKind, sketch: &str) -> Scenario {
        let mut scenario = Scenario::supply_point().unwrap();
        scenario.map = Map::from_ascii(sketch).unwrap();
        scenario
            .units
            .retain(|unit| unit.side() == Side::Player1 && unit.kind() == kind);
        scenario.units.truncate(1);
        scenario.units[0].move_to(Coordinate::new(0, 0));
        scenario
    }

    #[test]
    fn passengers_do_not_grant_sight_or_reveal_enemy_cargo() {
        let mut board = scenario(UnitKind::Truck, ".........");
        let truck = board.units[0].unit_id();
        let mut passenger = Scenario::supply_point().unwrap().units.remove(0);
        passenger.move_to(Coordinate::new(0, 0));
        passenger.board(truck);
        board.units.push(passenger);
        let visible = visible_tiles(&board, Side::Player1);
        assert!(!visible.contains(&Coordinate::new(4, 0)));
        assert_eq!(
            observed_scenario(&board, Side::Player1, &visible)
                .units
                .len(),
            2
        );
        let enemy_visible = BTreeSet::from([Coordinate::new(0, 0)]);
        assert_eq!(
            observed_scenario(&board, Side::Player2, &enemy_visible)
                .units
                .len(),
            1
        );
    }

    #[test]
    fn ranges_and_hill_bonus_follow_each_kind() {
        for (kind, range) in [
            (UnitKind::Infantry, 4),
            (UnitKind::FieldGun, 4),
            (UnitKind::Truck, 3),
            (UnitKind::Tank, 2),
        ] {
            for (sketch, bonus) in [(".......", 0), ("%......", 1)] {
                let board = scenario(kind, sketch);
                let visible = visible_tiles(&board, Side::Player1);
                assert!(visible.contains(&Coordinate::new(range + bonus, 0)));
                assert!(!visible.contains(&Coordinate::new(range + bonus + 1, 0)));
            }
        }
    }

    #[test]
    fn sight_budget_forms_a_circle_for_every_kind_and_hill_bonus() {
        let sketch = ["............."; 13].join("\n");
        let origin = Coordinate::new(6, 6);
        for kind in [
            UnitKind::Infantry,
            UnitKind::FieldGun,
            UnitKind::Truck,
            UnitKind::Tank,
        ] {
            for bonus in [0, 1] {
                let mut board = scenario(kind, &sketch);
                board.units[0].move_to(origin);
                if bonus == 1 {
                    board.map = Map::new(
                        13,
                        13,
                        Terrain::GrassPlain,
                        std::collections::BTreeMap::from([(origin, Terrain::Hills)]),
                    )
                    .unwrap();
                }
                let range = sight_range(kind) + bonus;
                let visible = visible_tiles(&board, Side::Player1);
                for y in 0..13 {
                    for x in 0..13 {
                        let dx = x - origin.x();
                        let dy = y - origin.y();
                        assert_eq!(
                            visible.contains(&Coordinate::new(x as u16, y as u16)),
                            dx * dx + dy * dy <= range * range,
                            "{kind:?}, bonus {bonus}, offset ({dx}, {dy})"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn forests_cast_horizontal_vertical_and_diagonal_shadows() {
        for sketch in [
            ".#...\n.....\n.....\n.....\n.....",
            ".....\n#....\n.....\n.....\n.....",
            ".....\n.#...\n.....\n.....\n.....",
        ] {
            let board = scenario(UnitKind::Infantry, sketch);
            let visible = visible_tiles(&board, Side::Player1);
            let hidden = match sketch {
                sketch if sketch.starts_with(".#") => Coordinate::new(3, 0),
                sketch if sketch.contains("\n#") => Coordinate::new(0, 3),
                _ => Coordinate::new(2, 2),
            };
            assert!(!visible.contains(&hidden));
        }
    }

    #[test]
    fn corner_touching_terrain_leaves_open_diagonals_visible() {
        let origin = Coordinate::new(3, 3);
        for terrain in [Terrain::Forest, Terrain::Hills] {
            for dx in [-1, 1] {
                for dy in [-1, 1] {
                    let horizontal = Coordinate::new((3 + dx) as u16, 3);
                    let vertical = Coordinate::new(3, (3 + dy) as u16);
                    for blockers in [vec![horizontal], vec![vertical], vec![horizontal, vertical]] {
                        let mut board = scenario(UnitKind::Infantry, &["......."; 7].join("\n"));
                        board.units[0].move_to(origin);
                        board.map = Map::new(
                            7,
                            7,
                            Terrain::GrassPlain,
                            blockers
                                .into_iter()
                                .map(|position| (position, terrain))
                                .collect(),
                        )
                        .unwrap();
                        let visible = visible_tiles(&board, Side::Player1);
                        for distance in [1, 2] {
                            let target = Coordinate::new(
                                (3 + distance * dx) as u16,
                                (3 + distance * dy) as u16,
                            );
                            assert!(visible.contains(&target), "{terrain:?}, {target:?}");
                            assert!(clear_line(&board.map, target, origin));
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn terrain_crossed_by_the_sight_line_still_blocks() {
        for terrain in [Terrain::Forest, Terrain::Hills] {
            let map = Map::new(
                5,
                5,
                Terrain::GrassPlain,
                std::collections::BTreeMap::from([(Coordinate::new(1, 1), terrain)]),
            )
            .unwrap();
            let origin = Coordinate::new(0, 0);
            // Check diagonal and oblique lines that actually enter the blocker.
            for target in [
                Coordinate::new(2, 2),
                Coordinate::new(3, 2),
                Coordinate::new(2, 3),
            ] {
                assert!(!clear_line(&map, origin, target));
                assert!(!clear_line(&map, target, origin));
            }
        }
    }

    #[test]
    fn hills_are_visible_and_cast_shadows_in_both_directions() {
        let mut board = scenario(UnitKind::Infantry, ".%...");
        assert_eq!(
            visible_tiles(&board, Side::Player1),
            BTreeSet::from([Coordinate::new(0, 0), Coordinate::new(1, 0)])
        );
        board.units[0].move_to(Coordinate::new(4, 0));
        let visible = visible_tiles(&board, Side::Player1);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(0, 0)));
        board.units[0].move_to(Coordinate::new(1, 0));
        assert!(visible_tiles(&board, Side::Player1).contains(&Coordinate::new(4, 0)));
    }

    #[test]
    fn forest_contents_are_hidden_even_when_occupied_by_an_ally() {
        let mut board = scenario(UnitKind::Infantry, ".#...");
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::Player2)
            .unwrap();
        enemy.move_to(Coordinate::new(1, 0));
        board.units.push(enemy);
        let visible = visible_tiles(&board, Side::Player1);
        assert!(!visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, Side::Player1, &visible)
                .units
                .len(),
            1
        );
        board.units[0].move_to(Coordinate::new(1, 0));
        let visible = visible_tiles(&board, Side::Player1);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, Side::Player1, &visible)
                .units
                .len(),
            1
        );
    }

    #[test]
    fn allies_share_sight_around_blocking_terrain() {
        let mut board = scenario(UnitKind::Infantry, ".....\n.%...\n.....\n.....\n.....");
        let visible = visible_tiles(&board, Side::Player1);
        assert!(!visible.contains(&Coordinate::new(2, 2)));
        let mut ally = board.units[0].clone();
        ally.move_to(Coordinate::new(4, 4));
        board.units.push(ally);
        assert!(visible_tiles(&board, Side::Player1).contains(&Coordinate::new(2, 2)));
    }

    #[test]
    fn timeline_replays_transient_sightings_without_hidden_positions() {
        let mut board = scenario(UnitKind::Infantry, "........");
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::Player2)
            .unwrap();
        enemy.move_to(Coordinate::new(5, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let resolution = TurnResolution {
            turn_number: 1,
            frames: Vec::new(),
            events: vec![TurnEvent {
                rotation_direction: None,
                initial_direction: None,
                initial_carrier: None,
                carrier_id: None,
                kind: TurnEventKind::Move,
                unit_id: enemy_id,
                path: [5, 4, 3, 4, 5].map(|x| Coordinate::new(x, 0)).to_vec(),
            }],
        };
        let projected = observed_resolution(
            &board,
            Side::Player1,
            &visible_tiles(&board, Side::Player1),
            &resolution,
        );
        assert!(projected.events.is_empty());
        let sightings: Vec<_> = projected
            .frames
            .iter()
            .map(|frame| {
                frame
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == enemy_id)
                    .and_then(Unit::board_position)
            })
            .collect();
        assert_eq!(
            sightings,
            vec![
                None,
                Some(Coordinate::new(4, 0)),
                Some(Coordinate::new(3, 0)),
                Some(Coordinate::new(4, 0)),
                None
            ]
        );
    }

    #[test]
    fn timeline_completes_one_route_before_the_next_and_refreshes_sight_each_step() {
        let mut board = scenario(UnitKind::Infantry, "...........");
        let own_id = board.units[0].unit_id();
        board.units[0].move_to(Coordinate::new(2, 0));
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::Player2)
            .unwrap();
        enemy.move_to(Coordinate::new(5, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let event = |unit_id, path: Vec<Coordinate>| TurnEvent {
            rotation_direction: None,
            initial_direction: None,
            initial_carrier: None,
            carrier_id: None,
            kind: TurnEventKind::Move,
            unit_id,
            path,
        };
        let resolution = TurnResolution {
            turn_number: 1,
            frames: Vec::new(),
            events: vec![
                event(own_id, [0, 1, 2].map(|x| Coordinate::new(x, 0)).to_vec()),
                event(enemy_id, [7, 6, 5].map(|x| Coordinate::new(x, 0)).to_vec()),
            ],
        };
        let frames = observed_frames(&board, Side::Player1, &resolution);
        assert_eq!(frames.len(), 5);
        assert!(!frames[0].visible_tiles.contains(&Coordinate::new(5, 0)));
        assert!(frames[1].visible_tiles.contains(&Coordinate::new(5, 0)));
        assert!(
            !frames[1]
                .units
                .iter()
                .any(|unit| unit.unit_id() == enemy_id)
        );
        assert_eq!(
            frames[4]
                .units
                .iter()
                .find(|unit| unit.unit_id() == enemy_id)
                .and_then(Unit::board_position),
            Some(Coordinate::new(5, 0))
        );
        let opposing = observed_frames(&board, Side::Player2, &resolution);
        assert_eq!(opposing.len(), frames.len());
        assert_eq!(
            opposing[1]
                .units
                .iter()
                .find(|unit| unit.unit_id() == enemy_id)
                .and_then(Unit::board_position),
            Some(Coordinate::new(7, 0))
        );
        // Both viewers share the schedule, including concealed movement steps.
        for frame in &frames[..=2] {
            assert!(!frame.units.iter().any(|unit| unit.unit_id() == enemy_id));
        }
        for (index, frame) in opposing.iter().enumerate() {
            let expected_x = [7, 7, 7, 6, 5][index];
            assert_eq!(
                frame
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == enemy_id)
                    .and_then(Unit::board_position),
                Some(Coordinate::new(expected_x, 0))
            );
        }
    }

    #[test]
    fn summary_does_not_reveal_enemies_hidden_only_mid_turn() {
        let mut board = scenario(UnitKind::Infantry, ".......");
        board.units[0].move_to(Coordinate::new(4, 0));
        let own_id = board.units[0].unit_id();
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::Player2)
            .unwrap();
        enemy.move_to(Coordinate::new(0, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let event = |unit_id, kind, path| TurnEvent {
            unit_id,
            kind,
            path,
            initial_direction: None,
            rotation_direction: None,
            initial_carrier: None,
            carrier_id: None,
        };
        let resolution = TurnResolution {
            turn_number: 1,
            frames: Vec::new(),
            events: vec![
                event(
                    own_id,
                    TurnEventKind::Move,
                    [4, 5, 4].map(|x| Coordinate::new(x, 0)).to_vec(),
                ),
                event(enemy_id, TurnEventKind::Hold, vec![Coordinate::new(0, 0)]),
            ],
        };
        let projected = observed_resolution(
            &board,
            Side::Player1,
            &visible_tiles(&board, Side::Player1),
            &resolution,
        );
        assert!(
            projected.frames[0]
                .units
                .iter()
                .any(|unit| unit.unit_id() == enemy_id)
        );
        assert!(
            !projected.frames[1]
                .units
                .iter()
                .any(|unit| unit.unit_id() == enemy_id)
        );
        assert!(
            projected.frames[2]
                .units
                .iter()
                .any(|unit| unit.unit_id() == enemy_id)
        );
        assert!(
            !projected
                .events
                .iter()
                .any(|event| event.unit_id == enemy_id)
        );
    }

    #[test]
    fn resolution_omits_enemy_paths_that_cross_fog() {
        let mut board = scenario(UnitKind::Infantry, ".......");
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::Player2)
            .unwrap();
        enemy.move_to(Coordinate::new(3, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let resolution = TurnResolution {
            turn_number: 1,
            frames: Vec::new(),
            events: vec![TurnEvent {
                rotation_direction: None,
                initial_direction: None,
                initial_carrier: None,
                carrier_id: None,
                kind: TurnEventKind::Move,
                unit_id: enemy_id,
                path: vec![
                    Coordinate::new(5, 0),
                    Coordinate::new(4, 0),
                    Coordinate::new(3, 0),
                ],
            }],
        };
        let visible = visible_tiles(&board, Side::Player1);
        assert!(
            observed_resolution(&board, Side::Player1, &visible, &resolution)
                .events
                .is_empty()
        );
        let mut observable = resolution;
        observable.events[0].path.remove(0);
        assert_eq!(
            observed_resolution(&board, Side::Player1, &visible, &observable)
                .events
                .len(),
            1
        );
    }
}
