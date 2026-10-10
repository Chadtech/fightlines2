use crate::{
    map::{Coordinate, Map, Terrain},
    scenario::{Scenario, Side, Unit, UnitKind},
    turns::TurnResolution,
};
use std::collections::BTreeSet;

/// Sight is a circular radius measured between tile centers.
pub fn sight_range(kind: UnitKind) -> i32 {
    match kind {
        UnitKind::Infantry | UnitKind::FieldGun => 4,
        UnitKind::SupplyTruck => 3,
        UnitKind::Tank => 2,
    }
}

pub fn visible_tiles(scenario: &Scenario, side: Side) -> BTreeSet<Coordinate> {
    let mut visible = BTreeSet::new();
    for unit in scenario.units.iter().filter(|unit| unit.side() == side) {
        let origin = unit.position();
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

/// Trace every crossed cell. At an exact corner both adjacent cells must be
/// clear, so sight cannot slip diagonally past blocking hills or forests.
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
            if blocks(x + dx.signum(), y) || blocks(x, y + dy.signum()) {
                return false;
            }
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
    observed
        .units
        .retain(|unit| unit.side() == side || observable(&scenario.map, visible, unit.position()));
    observed
}

/// Never reveal an enemy path through fog. Partial sightings appear at their
/// final observed position without replay; own orders always remain available.
pub fn observed_resolution(
    scenario: &Scenario,
    side: Side,
    visible: &BTreeSet<Coordinate>,
    resolution: &TurnResolution,
) -> TurnResolution {
    let mut before = scenario.clone();
    for unit in &mut before.units {
        if let Some(origin) = resolution
            .events
            .iter()
            .find(|event| event.unit_id == unit.unit_id())
            .and_then(|event| event.path.first())
        {
            unit.move_to(*origin);
        }
    }
    let initial_visible = visible_tiles(&before, side);
    let mut observed = resolution.clone();
    observed.events.retain(|event| {
        let unit: Option<&Unit> = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == event.unit_id);
        unit.is_some_and(|unit| {
            unit.side() == side
                || (observable(&scenario.map, visible, unit.position())
                    && event.path.iter().all(|position| {
                        observable(&scenario.map, &initial_visible, *position)
                            && observable(&scenario.map, visible, *position)
                    }))
        })
    });
    observed
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
            .retain(|unit| unit.side() == Side::West && unit.kind() == kind);
        scenario.units.truncate(1);
        scenario.units[0].move_to(Coordinate::new(0, 0));
        scenario
    }

    #[test]
    fn ranges_and_hill_bonus_follow_each_kind() {
        for (kind, range) in [
            (UnitKind::Infantry, 4),
            (UnitKind::FieldGun, 4),
            (UnitKind::SupplyTruck, 3),
            (UnitKind::Tank, 2),
        ] {
            for (sketch, bonus) in [(".......", 0), ("%......", 1)] {
                let board = scenario(kind, sketch);
                let visible = visible_tiles(&board, Side::West);
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
            UnitKind::SupplyTruck,
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
                let visible = visible_tiles(&board, Side::West);
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
            let visible = visible_tiles(&board, Side::West);
            let hidden = match sketch {
                sketch if sketch.starts_with(".#") => Coordinate::new(3, 0),
                sketch if sketch.contains("\n#") => Coordinate::new(0, 3),
                _ => Coordinate::new(2, 2),
            };
            assert!(!visible.contains(&hidden));
        }
        let board = scenario(UnitKind::Infantry, ".#...\n.....\n.....\n.....\n.....");
        assert!(!visible_tiles(&board, Side::West).contains(&Coordinate::new(2, 2)));
    }

    #[test]
    fn hills_are_visible_and_cast_shadows_in_both_directions() {
        let mut board = scenario(UnitKind::Infantry, ".%...");
        assert_eq!(
            visible_tiles(&board, Side::West),
            BTreeSet::from([Coordinate::new(0, 0), Coordinate::new(1, 0)])
        );
        board.units[0].move_to(Coordinate::new(4, 0));
        let visible = visible_tiles(&board, Side::West);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(0, 0)));
        board.units[0].move_to(Coordinate::new(1, 0));
        assert!(visible_tiles(&board, Side::West).contains(&Coordinate::new(4, 0)));
    }

    #[test]
    fn forest_contents_are_hidden_even_when_occupied_by_an_ally() {
        let mut board = scenario(UnitKind::Infantry, ".#...");
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::East)
            .unwrap();
        enemy.move_to(Coordinate::new(1, 0));
        board.units.push(enemy);
        let visible = visible_tiles(&board, Side::West);
        assert!(!visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, Side::West, &visible).units.len(),
            1
        );
        board.units[0].move_to(Coordinate::new(1, 0));
        let visible = visible_tiles(&board, Side::West);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, Side::West, &visible).units.len(),
            1
        );
    }

    #[test]
    fn diagonal_corner_hills_block_and_allies_share_sight() {
        let mut board = scenario(UnitKind::Infantry, ".%...\n.....\n.....\n.....\n.....");
        let visible = visible_tiles(&board, Side::West);
        assert!(!visible.contains(&Coordinate::new(2, 2)));
        let mut ally = board.units[0].clone();
        ally.move_to(Coordinate::new(4, 4));
        board.units.push(ally);
        assert!(visible_tiles(&board, Side::West).contains(&Coordinate::new(2, 2)));
    }

    #[test]
    fn resolution_omits_enemy_paths_that_cross_fog() {
        let mut board = scenario(UnitKind::Infantry, ".......");
        let mut enemy = Scenario::supply_point()
            .unwrap()
            .units
            .into_iter()
            .find(|unit| unit.side() == Side::East)
            .unwrap();
        enemy.move_to(Coordinate::new(3, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let resolution = TurnResolution {
            turn_number: 1,
            events: vec![TurnEvent {
                initial_direction: None,
                kind: TurnEventKind::Move,
                unit_id: enemy_id,
                path: vec![
                    Coordinate::new(5, 0),
                    Coordinate::new(4, 0),
                    Coordinate::new(3, 0),
                ],
            }],
        };
        let visible = visible_tiles(&board, Side::West);
        assert!(
            observed_resolution(&board, Side::West, &visible, &resolution)
                .events
                .is_empty()
        );
        let mut observable = resolution;
        observable.events[0].path.remove(0);
        assert_eq!(
            observed_resolution(&board, Side::West, &visible, &observable)
                .events
                .len(),
            1
        );
    }
}
