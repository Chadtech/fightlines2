use super::*;
use crate::{
    ai::{hard, medium, memory::EnemyMemory, very_hard},
    map::{Map, RoadShape},
    map_definition::MapDefinition,
    map_id::MapId,
    scenario::{Building, BuildingKind},
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

#[test]
fn only_higher_difficulties_prepare_for_contact_before_an_enemy_is_visible() -> TestResult {
    let mut scenario = MapDefinition::parse(r#"{
        "width": 8, "height": 3, "theme": "GreenForest",
        "features": [], "depots": [],
        "units": [
            {"id": 1, "position": {"x": 1, "y": 1}, "playerNumber": "Player1", "kind": "Tank", "direction": "East"},
            {"id": 2, "position": {"x": 4, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
        ]
    }"#).fixture()?.scenario().fixture()?;
    let player = PlayerNumber::Player1;
    let visible = visibility::visible_tiles(&scenario, player);
    let enemy = scenario.units.get(1).fixture()?;
    let enemy_position = enemy.board_position().fixture()?;
    assert!(!visible.contains(&enemy_position));

    let easy_orders = plan(&scenario, player).fixture()?;
    let scout = easy_orders.first().fixture()?;
    assert!(scout.path.len() > 1);
    assert_ne!(scout.attack_move, Some(true));

    let mut empty = scenario.clone();
    empty.units.retain(|unit| unit.player_number() == player);
    let memory = EnemyMemory::default();
    for planner in [medium::plan, hard::plan, very_hard::plan] {
        let orders = planner(&scenario, player, &memory, 1).fixture()?;
        let attack = orders.first().fixture()?;
        assert_eq!(attack.attack_move, Some(true));
        assert!(medium::approaches_fog(&scenario, &visible, attack));
        assert_eq!(
            serde_json::to_value(&orders)?,
            serde_json::to_value(planner(&empty, player, &memory, 1).fixture()?)?
        );
    }

    let orders = medium::plan(&scenario, player, &memory, 1).fixture()?;
    let initial_health = enemy.hit_points().current();
    let enemy_order = hold(enemy, enemy_position);
    let mut turns = Turns::default();
    turns.submit(&mut scenario, player, 1, orders).fixture()?;
    turns
        .submit(&mut scenario, player.opponent(), 1, vec![enemy_order])
        .fixture()?;
    assert!(
        scenario
            .units
            .iter()
            .find(|unit| unit.player_number() == player.opponent())
            .is_none_or(|unit| unit.hit_points().current() < initial_health)
    );
    Ok(())
}

fn resolved_enemy_count(scenario: &Scenario) -> TestResult<usize> {
    let mut board = scenario.clone();
    let mut turns = Turns::default();
    let orders = plan(scenario, PlayerNumber::Player1).fixture()?;
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
    assert_eq!(resolved_enemy_count(&scenario)?, 0);
    Ok(())
}

#[test]
fn private_enemy_resources_do_not_change_plans() -> TestResult {
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
        plan(&scenario, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    let other = turns::validate(
        &changed,
        PlayerNumber::Player1,
        plan(&changed, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    assert_eq!(format!("{original:?}"), format!("{other:?}"));
    Ok(())
}

#[test]
fn unknown_depot_stock_does_not_change_plans() -> TestResult {
    let scenario = Scenario::supply_point().fixture()?;
    let visible = visibility::visible_tiles(&scenario, PlayerNumber::Player1);
    let mut changed = scenario.clone();
    let mut hidden_count = 0;
    for depot in &mut changed.buildings {
        if !visible.contains(&depot.position) {
            depot.stock.current = 0;
            hidden_count += 1;
        }
    }
    assert!(hidden_count > 0);
    let original = turns::validate(
        &scenario,
        PlayerNumber::Player1,
        plan(&scenario, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    let other = turns::validate(
        &changed,
        PlayerNumber::Player1,
        plan(&changed, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    assert_eq!(format!("{original:?}"), format!("{other:?}"));
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
        let orders = candidates(&scenario, unit, &BTreeSet::new(), &goal).fixture()?;
        assert!(orders.iter().all(|order| order.dig_in != Some(true)));
        let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
        assert!(orders.iter().all(|order| order.dig_in != Some(true)));
        turns::validate(&scenario, PlayerNumber::Player1, orders).fixture()?;
    }
    Ok(())
}

#[test]
fn building_candidates_exclude_digging_and_plans_remain_legal() -> TestResult {
    let initial = MapDefinition::parse(r#"{
        "width": 5, "height": 3, "theme": "GreenForest", "features": [], "depots": [],
        "units": [
            {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
            {"id": 2, "position": {"x": 4, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
        ]
    }"#).fixture()?.scenario().fixture()?;
    for kind in [
        BuildingKind::Supply,
        BuildingKind::Fuel,
        BuildingKind::Fortress,
    ] {
        for destroyed in [false, true] {
            let mut scenario = initial.clone();
            let mut depot = Building::new(kind, Coordinate::new(0, 0));
            if destroyed {
                depot.sabotage();
            }
            scenario.buildings = vec![depot];
            let unit = scenario.units.first().fixture()?;
            let goal = StrategicGoal::new(&scenario, unit).fixture()?;
            let orders = candidates(&scenario, unit, &BTreeSet::new(), &goal).fixture()?;
            assert!(orders.iter().all(|order| order.dig_in != Some(true)));
            let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
            assert!(orders.iter().all(|order| order.dig_in != Some(true)));
            turns::validate(&scenario, PlayerNumber::Player1, orders).fixture()?;
        }
    }
    Ok(())
}

#[test]
fn guards_beside_supply_point_by_digging_in() -> TestResult {
    let mut scenario = MapDefinition::parse(r#"{
    "width": 12, "height": 5, "theme": "GreenForest", "features": [],
    "depots": [{"position": {"x": 6, "y": 2}, "kind": "Supply"}],
    "units": [
        {"id": 1, "position": {"x": 5, "y": 2}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
        {"id": 2, "position": {"x": 11, "y": 4}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
    ]
    }"#).fixture()?.scenario().fixture()?;
    let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
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
    Ok(())
}

#[test]
fn concealed_enemies_do_not_change_plans_and_exhausted_units_hold() -> TestResult {
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
        plan(&scenario, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    let other = turns::validate(
        &changed,
        PlayerNumber::Player1,
        plan(&changed, PlayerNumber::Player1).fixture()?,
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
        plan(&changed, PlayerNumber::Player1).fixture()?,
    )
    .fixture()?;
    assert!(orders.iter().all(|order| order.path().len() == 1));
    Ok(())
}

#[test]
fn low_supply_unit_stays_beside_stock_instead_of_spending_to_enter_depot() -> TestResult {
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
    let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
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
        let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
        let order = orders.first().fixture()?;
        assert!(order.path.len() > 1, "{kind:?} refused the mountain detour");
        assert!(
            order.path.get(1).fixture()?.x > 6,
            "{kind:?} did not head for the pass"
        );
        let mut turns = Turns::default();
        for _ in 0..12 {
            let number = turns.number;
            let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
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
    Ok(())
}

#[test]
fn preserves_artillery_against_an_infantry_rush() -> TestResult {
    let scenario = MapDefinition::parse(r#"{
        "width": 10, "height": 7, "theme": "GreenForest", "features": [], "depots": [],
        "units": [
            {"id": 1, "position": {"x": 2, "y": 3}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
            {"id": 2, "position": {"x": 4, "y": 3}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
        ]
    }"#).fixture()?.scenario().fixture()?;
    // The planner never receives the independently chosen human attack.
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
    let orders = plan(&scenario, PlayerNumber::Player1).fixture()?;
    let mut board = scenario.clone();
    let mut turns = Turns::default();
    turns
        .submit(&mut board, PlayerNumber::Player1, 1, orders)
        .fixture()?;
    turns
        .submit(&mut board, PlayerNumber::Player2, 1, vec![rush])
        .fixture()?;
    let gun = board
        .units
        .iter()
        .find(|unit| unit.kind() == UnitKind::FieldGun);
    assert_eq!(gun.fixture()?.hit_points().current(), 16);
    Ok(())
}

#[test]
#[ignore = "slow AI simulation; run with make check-all"]
fn plays_valid_turns_on_sample_maps_and_both_sides() -> TestResult {
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
                let orders = plan(&scenario, player).fixture()?;
                turns
                    .submit(&mut scenario, player, number, orders)
                    .map_err(|error| format!("{map:?}, turn {number}, {player:?}: {error}"))?;
            }
        }
    }
    Ok(())
}
