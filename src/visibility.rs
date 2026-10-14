use crate::{
    combat::CombatKind,
    map::{Coordinate, Map, Terrain},
    scenario::{Direction, PlayerNumber, Scenario, Unit, UnitKind},
    turns::{TurnEventKind, TurnFrame, TurnResolution},
};
use std::collections::BTreeSet;

/// Sight is a circular radius measured between tile centers.
pub fn sight_range(kind: UnitKind) -> i32 {
    match kind {
        UnitKind::Infantry => 3,
        UnitKind::FieldGun => 3,
        UnitKind::Truck => 1,
        UnitKind::Tank => 1,
    }
}

pub fn visible_tiles(scenario: &Scenario, player_number: PlayerNumber) -> BTreeSet<Coordinate> {
    let mut visible = BTreeSet::new();
    for (unit, origin) in scenario
        .units
        .iter()
        .filter(|unit| unit.player_number() == player_number && unit.is_alive())
        .filter_map(|unit| unit.board_position().map(|origin| (unit, origin)))
    {
        // The occupied square is known even when the unit is in a forest.
        visible.insert(origin);
        let bonus = match scenario.map.tile_at(origin) {
            Some(Terrain::Mountains) => 2,
            Some(Terrain::Hills) => 1,
            _ => 0,
        };
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
    // Firing reveals only the gun's occupied tile, without granting it sight.
    visible.extend(
        scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() != player_number && unit.firing_position_revealed())
            .filter_map(Unit::board_position),
    );
    visible
}

/// Trace cells crossed by the center-to-center sight line. Touching a corner
/// does not enter the adjacent cells, so their terrain does not block sight.
/// Target hills and mountains remain visible; forests conceal their contents.
/// Intervening hills, mountains and forests block ground-level observers.
/// Hill and mountain observers see over
/// intervening terrain; forests still conceal their contents.
pub(crate) fn clear_line(map: &Map, origin: Coordinate, target: Coordinate) -> bool {
    if matches!(
        map.tile_at(origin),
        Some(Terrain::Hills | Terrain::Mountains)
    ) {
        return true;
    }
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
            Some(Terrain::Hills | Terrain::Forest | Terrain::Mountains) => true,
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

pub(crate) fn observable(map: &Map, visible: &BTreeSet<Coordinate>, position: Coordinate) -> bool {
    visible.contains(&position) && map.tile_at(position) != Some(Terrain::Forest)
}

pub fn observed_scenario(
    scenario: &Scenario,
    player_number: PlayerNumber,
    visible: &BTreeSet<Coordinate>,
) -> Scenario {
    let mut observed = scenario.clone();
    observed.units.retain(|unit| {
        unit.player_number() == player_number
            || unit.board_position().is_some_and(|position| {
                unit.firing_position_revealed() || observable(&scenario.map, visible, position)
            })
    });
    for unit in &mut observed.units {
        if unit.player_number() != player_number {
            unit.conceal_resources();
        }
    }
    for depot in &mut observed.depots {
        depot.stock_visible = visible.contains(&depot.position);
    }
    observed
        .supply_crates
        .retain(|supply_crate| visible.contains(&supply_crate.position));
    observed
}

/// Keep own summary events and only wholly observable enemy summaries.
/// Partial enemy sightings are represented exclusively by projected frames.
pub fn observed_resolution(
    scenario: &Scenario,
    player_number: PlayerNumber,
    visible: &BTreeSet<Coordinate>,
    resolution: &TurnResolution,
) -> TurnResolution {
    let before = initial_scenario(scenario, resolution);
    let initial_visible = visible_tiles(&before, player_number);
    let mut observed = resolution.clone();
    observed.frames = observed_frames(scenario, player_number, resolution);
    observed
        .reports
        .retain(|report| report.player_number == player_number);
    for report in &mut observed.reports {
        let shots: Vec<_> = observed
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .filter(|shot| {
                shot.attacker.player_number() == player_number
                    && shot.target.player_number() != player_number
            })
            .collect();
        report.damage_inflicted = shots
            .iter()
            .map(|shot| {
                (shot.target_health.before.current() - shot.target_health.after.current()).max(0)
            })
            .sum();
        report.enemy_units_destroyed = shots
            .iter()
            .filter(|shot| {
                shot.target_health.before.current() > 0 && shot.target_health.after.current() == 0
            })
            .map(|shot| shot.target.unit_id())
            .collect::<BTreeSet<_>>()
            .len() as i32;
    }
    observed.events.retain(|event| {
        let unit: Option<&Unit> = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == event.unit_id)
            .or_else(|| {
                before
                    .units
                    .iter()
                    .find(|unit| unit.unit_id() == event.unit_id)
            });
        unit.is_some_and(|unit| {
            unit.player_number() == player_number
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
    if let Some(first) = resolution.frames.first() {
        board.units = first.units.clone();
        return board;
    }
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
            unit.restore_sprite_facing(event.initial_sprite_facing);
        }
    }
    board
}

/// Project authoritative shared frames independently, withholding hidden units.
/// Event-only fixtures retain the legacy reconstruction fallback.
fn observed_frames(
    scenario: &Scenario,
    player_number: PlayerNumber,
    resolution: &TurnResolution,
) -> Vec<TurnFrame> {
    if !resolution.frames.is_empty() {
        let mut previous_visible = BTreeSet::new();
        let mut previous_shots = false;
        let mut casualties = BTreeSet::new();
        let mut concealed_casualties = BTreeSet::new();
        return resolution
            .frames
            .iter()
            .map(|frame| {
                let mut board = scenario.clone();
                board.units = frame.units.clone();
                board.depots = frame.depots.clone();
                board.supply_crates = frame.supply_crates.clone();
                let mut visible = visible_tiles(&board, player_number);
                // Keep the observed exchange visible when the volley kills an observer.
                if !frame.shots.is_empty() || previous_shots {
                    visible.extend(&previous_visible);
                }
                previous_visible = visible.clone();
                previous_shots = !frame.shots.is_empty();
                let known_endpoint = |position| {
                    observable(&board.map, &visible, position)
                        || board.units.iter().any(|unit| {
                            unit.player_number() == player_number
                                && unit.board_position() == Some(position)
                        })
                };
                let mut observed = observed_scenario(&board, player_number, &visible);
                // Corpses persist until cleanup. Later sight or a firing reveal
                // must not disclose a casualty that was hidden when it happened.
                for unit in &board.units {
                    if unit.player_number() != player_number
                        && unit.destroyed()
                        && casualties.insert(unit.unit_id())
                        && !observed
                            .units
                            .iter()
                            .any(|seen| seen.unit_id() == unit.unit_id())
                    {
                        concealed_casualties.insert(unit.unit_id());
                    }
                }
                observed
                    .units
                    .retain(|unit| !concealed_casualties.contains(&unit.unit_id()));
                TurnFrame {
                    indirect_impacts: frame
                        .indirect_impacts
                        .iter()
                        .filter(|impact| {
                            impact.player_number == player_number
                                || known_endpoint(impact.destination)
                        })
                        .cloned()
                        .collect(),
                    depots: observed.depots,
                    supply_crates: observed.supply_crates,
                    shots: frame
                        .shots
                        .iter()
                        .filter(|shot| {
                            let unconfirmed_bombardment = shot.kind == CombatKind::IndirectFire
                                && shot.target.player_number() != player_number
                                && !known_endpoint(shot.destination);
                            !unconfirmed_bombardment
                                && (shot.attacker.player_number() == player_number
                                    || shot.target.player_number() == player_number
                                    || (known_endpoint(shot.origin)
                                        && known_endpoint(shot.destination)))
                        })
                        .cloned()
                        .collect(),
                    duration_ms: frame.duration_ms,
                    units: observed.units,
                    visible_tiles: visible.into_iter().collect(),
                }
            })
            .collect();
    }
    let mut board = initial_scenario(scenario, resolution);
    let project = |board: &Scenario| {
        let visible = visible_tiles(board, player_number);
        let observed = observed_scenario(board, player_number, &visible);
        TurnFrame {
            indirect_impacts: Vec::new(),
            depots: observed.depots,
            supply_crates: observed.supply_crates,
            shots: Vec::new(),
            duration_ms: 180,
            units: observed.units,
            visible_tiles: visible.into_iter().collect(),
        }
    };
    let mut frames = vec![project(&board)];
    for event in &resolution.events {
        if event.kind == TurnEventKind::Hold {
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
    use crate::test_support::{FixtureValue, TestResult};
    use crate::turns::{TurnEvent, TurnEventKind};

    fn scenario(kind: UnitKind, sketch: &str) -> TestResult<Scenario> {
        Ok({
            let mut scenario = Scenario::supply_point().fixture()?;
            scenario.map = Map::from_ascii(sketch).fixture()?;
            scenario.units.retain(|unit| {
                unit.player_number() == PlayerNumber::Player1 && unit.kind() == kind
            });
            scenario.units.truncate(1);
            scenario.units[0].move_to(Coordinate::new(0, 0));
            scenario
        })
    }

    #[test]
    fn hidden_casualties_stay_hidden_after_sight_or_firing_reveal() -> TestResult<()> {
        for firing_reveal in [false, true] {
            let mut board = scenario(UnitKind::Infantry, "........")?;
            let mut enemy = Scenario::supply_point()
                .fixture()?
                .units
                .into_iter()
                .find(|unit| {
                    unit.player_number() == PlayerNumber::Player2
                        && unit.kind() == UnitKind::FieldGun
                })
                .fixture()?;
            enemy.move_to(Coordinate::new(6, 0));
            let enemy_id = enemy.unit_id();
            board.units.push(enemy);
            let frame = |board: &Scenario| TurnFrame {
                indirect_impacts: Vec::new(),
                units: board.units.clone(),
                depots: board.depots.clone(),
                supply_crates: board.supply_crates.clone(),
                shots: vec![],
                visible_tiles: vec![],
                duration_ms: 180,
            };
            let mut frames = vec![frame(&board)];
            board.units.get_mut(1).fixture()?.take_damage(16);
            frames.push(frame(&board));
            if firing_reveal {
                board.units.get_mut(1).fixture()?.finish_firing_reveal(true);
            } else {
                board
                    .units
                    .first_mut()
                    .fixture()?
                    .move_to(Coordinate::new(3, 0));
            }
            frames.push(frame(&board));
            let resolution = TurnResolution {
                reports: Vec::new(),
                turn_number: 1,
                events: vec![],
                frames,
            };
            let projected = observed_resolution(
                &board,
                PlayerNumber::Player1,
                &visible_tiles(&board, PlayerNumber::Player1),
                &resolution,
            );
            assert!(
                projected
                    .frames
                    .iter()
                    .all(|frame| { !frame.units.iter().any(|unit| unit.unit_id() == enemy_id) })
            );
            assert!(
                projected
                    .frames
                    .get(2)
                    .fixture()?
                    .visible_tiles
                    .contains(&Coordinate::new(6, 0))
            );
            // The owner still receives the casualty, including its death frame.
            let own_frames = observed_frames(&board, PlayerNumber::Player2, &resolution);
            assert!(
                own_frames
                    .get(1)
                    .fixture()?
                    .units
                    .iter()
                    .any(|unit| { unit.unit_id() == enemy_id && unit.destroyed() })
            );
        }
        Ok(())
    }

    struct ResourceQuery {
        board: Scenario,
        resolution: TurnResolution,
    }

    #[juniper::graphql_object]
    impl ResourceQuery {
        fn scenario(&self) -> &Scenario {
            &self.board
        }

        fn resolution(&self) -> &TurnResolution {
            &self.resolution
        }
    }

    #[test]
    fn graphql_conceals_enemy_resources_in_snapshots_and_frames() -> TestResult<()> {
        let mut board = Scenario::supply_point().fixture()?;
        board.map = Map::from_ascii(".....").fixture()?;
        let unit_count = board.units.len();
        for unit in &mut board.units {
            if unit.kind() == UnitKind::Truck {
                unit.supply_cargo.push(crate::supplies::ResourceStock {
                    current: 64,
                    maximum: 64,
                });
            }
        }
        for unit in &mut board.units {
            let x = if unit.player_number() == PlayerNumber::Player1 {
                1
            } else {
                2
            };
            unit.move_to(Coordinate::new(x, 0));
        }
        let resolution = TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            events: vec![],
            frames: vec![TurnFrame {
                indirect_impacts: Vec::new(),
                depots: board.depots.clone(),
                supply_crates: board.supply_crates.clone(),
                shots: Vec::new(),
                duration_ms: 0,
                units: board.units.clone(),
                visible_tiles: vec![],
            }],
        };
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let visible = visible_tiles(&board, player_number);
            let query = ResourceQuery {
                board: observed_scenario(&board, player_number, &visible),
                resolution: observed_resolution(&board, player_number, &visible, &resolution),
            };
            let schema = juniper::RootNode::new(
                query,
                juniper::EmptyMutation::<()>::new(),
                juniper::EmptySubscription::<()>::new(),
            );
            let (data, errors) = juniper::execute_sync(
                "{ scenario { units { playerNumber kind resources { hitPoints { current maximum } supplies { current maximum upkeepPerTurn movementPerTile } fuel { current maximum } supplyCargo { current maximum } } } } resolution { frames { units { playerNumber kind resources { hitPoints { current } supplies { current } fuel { current } supplyCargo { current maximum } } } } } }",
                None,
                &schema,
                &juniper::Variables::new(),
                &(),
            )?;
            assert!(errors.is_empty());
            let json = serde_json::to_value(data)?;
            for units in [
                json["scenario"]["units"].as_array().fixture()?,
                json["resolution"]["frames"][0]["units"]
                    .as_array()
                    .fixture()?,
            ] {
                assert_eq!(units.len(), unit_count);
                let own_player_number = match player_number {
                    PlayerNumber::Player1 => "PLAYER1",
                    PlayerNumber::Player2 => "PLAYER2",
                };
                for unit in units {
                    let resources = &unit["resources"];
                    let own_unit = unit["playerNumber"] == own_player_number;
                    assert_eq!(resources.is_null(), !own_unit);
                    if own_unit {
                        assert!(resources["hitPoints"].is_object());
                        assert!(resources["supplies"].is_object());
                        let vehicle = unit["kind"] == "TANK" || unit["kind"] == "TRUCK";
                        assert_eq!(resources["fuel"].is_object(), vehicle);
                        assert_eq!(resources["fuel"].is_null(), !vehicle);
                        assert_eq!(resources["hitPoints"]["current"], 16);
                        let cargo = resources["supplyCargo"].as_array().fixture()?;
                        assert_eq!(cargo.len(), usize::from(unit["kind"] == "TRUCK"));
                    }
                }
            }
        }
        assert!(board.units.iter().all(|unit| unit.resources().is_some()));
        Ok(())
    }

    #[test]
    fn passengers_do_not_grant_sight_or_reveal_enemy_cargo() -> TestResult<()> {
        let mut board = scenario(UnitKind::Truck, ".........")?;
        let truck = board.units[0].unit_id();
        let mut passenger = Scenario::supply_point().fixture()?.units.remove(0);
        passenger.move_to(Coordinate::new(0, 0));
        passenger.board(truck);
        board.units.push(passenger);
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(!visible.contains(&Coordinate::new(4, 0)));
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player1, &visible)
                .units
                .len(),
            2
        );
        let enemy_visible = BTreeSet::from([Coordinate::new(0, 0)]);
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player2, &enemy_visible)
                .units
                .len(),
            1
        );

        Ok(())
    }

    #[test]
    fn ranges_and_hill_bonus_follow_each_kind() -> TestResult<()> {
        for (kind, range) in [
            (UnitKind::Infantry, 3),
            (UnitKind::FieldGun, 3),
            (UnitKind::Truck, 1),
            (UnitKind::Tank, 1),
        ] {
            for (sketch, bonus) in [("........", 0), ("%.......", 1), ("^.......", 2)] {
                let board = scenario(kind, sketch)?;
                let visible = visible_tiles(&board, PlayerNumber::Player1);
                assert!(visible.contains(&Coordinate::new(range + bonus, 0)));
                assert!(!visible.contains(&Coordinate::new(range + bonus + 1, 0)));
            }
        }

        Ok(())
    }

    #[test]
    fn sight_budget_forms_a_circle_for_every_kind_and_hill_bonus() -> TestResult<()> {
        let sketch = ["............."; 13].join("\n");
        let origin = Coordinate::new(6, 6);
        for kind in [
            UnitKind::Infantry,
            UnitKind::FieldGun,
            UnitKind::Truck,
            UnitKind::Tank,
        ] {
            for bonus in [0, 1, 2] {
                let mut board = scenario(kind, &sketch)?;
                board.units[0].move_to(origin);
                if bonus > 0 {
                    board.map = Map::new(
                        13,
                        13,
                        Terrain::GrassPlain,
                        std::collections::BTreeMap::from([(
                            origin,
                            if bonus == 2 {
                                Terrain::Mountains
                            } else {
                                Terrain::Hills
                            },
                        )]),
                    )
                    .fixture()?;
                }
                let range = sight_range(kind) + bonus;
                let visible = visible_tiles(&board, PlayerNumber::Player1);
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

        Ok(())
    }

    #[test]
    fn mountains_block_ground_sight_and_grant_elevated_sight() -> TestResult<()> {
        let ground = scenario(UnitKind::Infantry, ".^.....")?;
        let visible = visible_tiles(&ground, PlayerNumber::Player1);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(2, 0)));
        for sketch in ["^%.....", "^^.....", "^#....."] {
            let board = scenario(UnitKind::Infantry, sketch)?;
            let visible = visible_tiles(&board, PlayerNumber::Player1);
            assert!(visible.contains(&Coordinate::new(5, 0)));
            assert!(!visible.contains(&Coordinate::new(6, 0)));
        }
        Ok(())
    }

    #[test]
    fn forests_cast_horizontal_vertical_and_diagonal_shadows() -> TestResult<()> {
        for sketch in [
            ".#...\n.....\n.....\n.....\n.....",
            ".....\n#....\n.....\n.....\n.....",
            ".....\n.#...\n.....\n.....\n.....",
        ] {
            let board = scenario(UnitKind::Infantry, sketch)?;
            let visible = visible_tiles(&board, PlayerNumber::Player1);
            let hidden = match sketch {
                sketch if sketch.starts_with(".#") => Coordinate::new(3, 0),
                sketch if sketch.contains("\n#") => Coordinate::new(0, 3),
                _ => Coordinate::new(2, 2),
            };
            assert!(!visible.contains(&hidden));
        }

        Ok(())
    }

    #[test]
    fn hill_observers_see_over_hills_and_forests_for_every_kind() -> TestResult<()> {
        for kind in [
            UnitKind::Infantry,
            UnitKind::FieldGun,
            UnitKind::Truck,
            UnitKind::Tank,
        ] {
            for terrain in [Terrain::Hills, Terrain::Forest] {
                let origin = Coordinate::new(0, 0);
                for blocker in [
                    Coordinate::new(1, 0),
                    Coordinate::new(0, 1),
                    Coordinate::new(1, 1),
                ] {
                    let mut board = scenario(kind, &["........"; 8].join("\n"))?;
                    board.map = Map::new(
                        8,
                        8,
                        Terrain::GrassPlain,
                        std::collections::BTreeMap::from([(blocker, terrain)]),
                    )
                    .fixture()?;
                    let target =
                        Coordinate::new((blocker.x() * 2) as u16, (blocker.y() * 2) as u16);
                    assert!(!visible_tiles(&board, PlayerNumber::Player1).contains(&target));
                    board.map = Map::new(
                        8,
                        8,
                        Terrain::GrassPlain,
                        std::collections::BTreeMap::from([
                            (origin, Terrain::Hills),
                            (blocker, terrain),
                        ]),
                    )
                    .fixture()?;
                    let visible = visible_tiles(&board, PlayerNumber::Player1);
                    assert!(clear_line(&board.map, origin, target));
                    let range = (sight_range(kind) + 1) as u16;
                    let within_sight = target.x() * target.x() + target.y() * target.y()
                        <= i32::from(range) * i32::from(range);
                    assert_eq!(
                        visible.contains(&target),
                        within_sight,
                        "{kind:?}, {terrain:?}, {target:?}"
                    );
                    assert!(visible.contains(&Coordinate::new(range, 0)));
                    assert!(!visible.contains(&Coordinate::new(range + 1, 0)));
                }
            }
        }

        Ok(())
    }

    #[test]
    fn hill_observers_reveal_enemies_beyond_forests_but_not_inside_them() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, "%#%#...")?;
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(4, 0));
        board.units.push(enemy);
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(visible.contains(&Coordinate::new(4, 0)));
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player1, &visible)
                .units
                .len(),
            2
        );
        board.units[1].move_to(Coordinate::new(3, 0));
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(!visible.contains(&Coordinate::new(3, 0)));
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player1, &visible)
                .units
                .len(),
            1
        );

        Ok(())
    }

    #[test]
    fn corner_touching_terrain_leaves_open_diagonals_visible() -> TestResult<()> {
        let origin = Coordinate::new(3, 3);
        for terrain in [Terrain::Forest, Terrain::Hills] {
            for dx in [-1, 1] {
                for dy in [-1, 1] {
                    let horizontal = Coordinate::new((3 + dx) as u16, 3);
                    let vertical = Coordinate::new(3, (3 + dy) as u16);
                    for blockers in [vec![horizontal], vec![vertical], vec![horizontal, vertical]] {
                        let mut board = scenario(UnitKind::Infantry, &["......."; 7].join("\n"))?;
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
                        .fixture()?;
                        let visible = visible_tiles(&board, PlayerNumber::Player1);
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

        Ok(())
    }

    #[test]
    fn terrain_crossed_by_the_sight_line_still_blocks() -> TestResult<()> {
        for terrain in [Terrain::Forest, Terrain::Hills] {
            let map = Map::new(
                5,
                5,
                Terrain::GrassPlain,
                std::collections::BTreeMap::from([(Coordinate::new(1, 1), terrain)]),
            )
            .fixture()?;
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

        Ok(())
    }

    #[test]
    fn hills_are_visible_and_cast_shadows_in_both_directions() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, ".%...")?;
        assert_eq!(
            visible_tiles(&board, PlayerNumber::Player1),
            BTreeSet::from([Coordinate::new(0, 0), Coordinate::new(1, 0)])
        );
        board.units[0].move_to(Coordinate::new(4, 0));
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(0, 0)));
        board.units[0].move_to(Coordinate::new(1, 0));
        assert!(visible_tiles(&board, PlayerNumber::Player1).contains(&Coordinate::new(4, 0)));

        Ok(())
    }

    #[test]
    fn forest_contents_are_hidden_even_when_occupied_by_an_ally() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, ".#...")?;
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(1, 0));
        board.units.push(enemy);
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(!visible.contains(&Coordinate::new(1, 0)));
        assert!(!visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player1, &visible)
                .units
                .len(),
            1
        );
        board.units[0].move_to(Coordinate::new(1, 0));
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(visible.contains(&Coordinate::new(1, 0)));
        assert!(visible.contains(&Coordinate::new(2, 0)));
        assert_eq!(
            observed_scenario(&board, PlayerNumber::Player1, &visible)
                .units
                .len(),
            1
        );

        Ok(())
    }

    #[test]
    fn allies_share_sight_around_blocking_terrain() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, ".....\n.%...\n.....\n.....\n.....")?;
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(!visible.contains(&Coordinate::new(2, 2)));
        let mut ally = board.units[0].clone();
        ally.move_to(Coordinate::new(4, 4));
        board.units.push(ally);
        assert!(visible_tiles(&board, PlayerNumber::Player1).contains(&Coordinate::new(2, 2)));

        Ok(())
    }

    #[test]
    fn timeline_replays_transient_sightings_without_hidden_positions() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, "........")?;
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(5, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let resolution = TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            frames: Vec::new(),
            events: vec![TurnEvent {
                rotation_direction: None,
                initial_direction: None,
                initial_sprite_facing: crate::scenario::SpriteFacing::Right,
                initial_carrier: None,
                carrier_id: None,
                kind: TurnEventKind::Move,
                unit_id: enemy_id,
                path: [5, 4, 3, 4, 5].map(|x| Coordinate::new(x, 0)).to_vec(),
            }],
        };
        let projected = observed_resolution(
            &board,
            PlayerNumber::Player1,
            &visible_tiles(&board, PlayerNumber::Player1),
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
            vec![None, None, Some(Coordinate::new(3, 0)), None, None]
        );

        Ok(())
    }

    #[test]
    fn timeline_completes_one_route_before_the_next_and_refreshes_sight_each_step() -> TestResult<()>
    {
        let mut board = scenario(UnitKind::Infantry, "...........")?;
        let own_id = board.units[0].unit_id();
        board.units[0].move_to(Coordinate::new(2, 0));
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(5, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let event = |unit_id, path: Vec<Coordinate>| TurnEvent {
            rotation_direction: None,
            initial_direction: None,
            initial_sprite_facing: crate::scenario::SpriteFacing::Right,
            initial_carrier: None,
            carrier_id: None,
            kind: TurnEventKind::Move,
            unit_id,
            path,
        };
        let resolution = TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            frames: Vec::new(),
            events: vec![
                event(own_id, [0, 1, 2].map(|x| Coordinate::new(x, 0)).to_vec()),
                event(enemy_id, [7, 6, 5].map(|x| Coordinate::new(x, 0)).to_vec()),
            ],
        };
        let frames = observed_frames(&board, PlayerNumber::Player1, &resolution);
        assert_eq!(frames.len(), 5);
        assert!(!frames[0].visible_tiles.contains(&Coordinate::new(5, 0)));
        assert!(frames[1].visible_tiles.contains(&Coordinate::new(4, 0)));
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
        let opposing = observed_frames(&board, PlayerNumber::Player2, &resolution);
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

        Ok(())
    }

    #[test]
    fn summary_does_not_reveal_enemies_hidden_only_mid_turn() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, ".......")?;
        board.units[0].move_to(Coordinate::new(3, 0));
        let own_id = board.units[0].unit_id();
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(0, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let event = |unit_id, kind, path| TurnEvent {
            unit_id,
            kind,
            path,
            initial_direction: None,
            initial_sprite_facing: crate::scenario::SpriteFacing::Right,
            rotation_direction: None,
            initial_carrier: None,
            carrier_id: None,
        };
        let resolution = TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            frames: Vec::new(),
            events: vec![
                event(
                    own_id,
                    TurnEventKind::Move,
                    [3, 4, 3].map(|x| Coordinate::new(x, 0)).to_vec(),
                ),
                event(enemy_id, TurnEventKind::Hold, vec![Coordinate::new(0, 0)]),
            ],
        };
        let projected = observed_resolution(
            &board,
            PlayerNumber::Player1,
            &visible_tiles(&board, PlayerNumber::Player1),
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

        Ok(())
    }

    #[test]
    fn resolution_omits_enemy_paths_that_cross_fog() -> TestResult<()> {
        let mut board = scenario(UnitKind::Infantry, ".......")?;
        let mut enemy = Scenario::supply_point()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2)
            .fixture()?;
        enemy.move_to(Coordinate::new(2, 0));
        let enemy_id = enemy.unit_id();
        board.units.push(enemy);
        let resolution = TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            frames: Vec::new(),
            events: vec![TurnEvent {
                rotation_direction: None,
                initial_direction: None,
                initial_sprite_facing: crate::scenario::SpriteFacing::Right,
                initial_carrier: None,
                carrier_id: None,
                kind: TurnEventKind::Move,
                unit_id: enemy_id,
                path: vec![
                    Coordinate::new(4, 0),
                    Coordinate::new(3, 0),
                    Coordinate::new(2, 0),
                ],
            }],
        };
        let visible = visible_tiles(&board, PlayerNumber::Player1);
        assert!(
            observed_resolution(&board, PlayerNumber::Player1, &visible, &resolution)
                .events
                .is_empty()
        );
        let mut observable = resolution;
        observable.events[0].path.remove(0);
        assert_eq!(
            observed_resolution(&board, PlayerNumber::Player1, &visible, &observable)
                .events
                .len(),
            1
        );

        Ok(())
    }
}
