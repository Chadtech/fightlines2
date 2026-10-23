//! Replay inspection is derived from accepted orders and recorded snapshots, never re-simulation.
use crate::{
    combat,
    game_log::Archive,
    map::Coordinate,
    scenario::{Direction, PlayerNumber, Unit, UnitId},
    turns::{CoordinateInput, MoveOrderInput, TurnEventKind, TurnResolution, UnitOrderKind},
};
use juniper::{GraphQLObject, graphql_object};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, GraphQLObject)]
pub struct RecordedUnload {
    destination: Coordinate,
}

#[derive(Clone)]
pub struct RecordedOrder {
    pub unit_id: UnitId,
    pub player_number: PlayerNumber,
    pub kind: UnitOrderKind,
    path: Vec<Coordinate>,
    direction: Option<Direction>,
    target: Option<Coordinate>,
    unloads: Vec<RecordedUnload>,
    stopped_at: Option<Coordinate>,
}

#[graphql_object]
impl RecordedOrder {
    fn unit_id(&self) -> String {
        self.unit_id.to_string()
    }
    fn player_number(&self) -> PlayerNumber {
        self.player_number
    }
    fn kind(&self) -> UnitOrderKind {
        self.kind
    }
    fn path(&self) -> &[Coordinate] {
        &self.path
    }
    fn direction(&self) -> Option<Direction> {
        self.direction
    }
    fn target(&self) -> Option<Coordinate> {
        self.target
    }
    fn unloads(&self) -> &[RecordedUnload] {
        &self.unloads
    }
    fn stopped_at(&self) -> Option<Coordinate> {
        self.stopped_at
    }
}

fn coordinate(input: &CoordinateInput) -> Result<Coordinate, &'static str> {
    Ok(Coordinate::new(
        u16::try_from(input.x).map_err(|_| "invalid recorded x coordinate")?,
        u16::try_from(input.y).map_err(|_| "invalid recorded y coordinate")?,
    ))
}

impl RecordedOrder {
    fn from_input(
        player_number: PlayerNumber,
        input: &MoveOrderInput,
    ) -> Result<Self, &'static str> {
        let unit_id = UnitId::parse(&input.unit_id).ok_or("invalid recorded unit id")?;
        let path = input
            .path
            .iter()
            .map(coordinate)
            .collect::<Result<Vec<_>, _>>()?;
        if path.is_empty() {
            return Err("recorded order has no origin");
        }
        let kind = if input.attack_move == Some(true) {
            UnitOrderKind::AttackMove
        } else if input.ambush == Some(true) {
            UnitOrderKind::Ambush
        } else if input.stand_ground == Some(true) {
            UnitOrderKind::StandGround
        } else if input.dig_in == Some(true) {
            UnitOrderKind::DigIn
        } else if input.indirect_fire.is_some() {
            UnitOrderKind::IndirectFire
        } else if path.len() > 1 {
            UnitOrderKind::Move
        } else if input.direction.is_some() {
            UnitOrderKind::Rotate
        } else {
            UnitOrderKind::Hold
        };
        let unloads = input
            .unloads
            .iter()
            .flatten()
            .map(|unload| {
                unload
                    .destination_coordinate()
                    .map(|destination| RecordedUnload { destination })
            })
            .collect::<Result<_, _>>()?;
        let mut unloads: Vec<RecordedUnload> = unloads;
        for unload in input.crate_unloads.iter().flatten() {
            unloads.push(RecordedUnload {
                destination: coordinate(&unload.destination)?,
            });
        }
        Ok(Self {
            unit_id,
            player_number,
            kind,
            path,
            direction: input.direction,
            target: input.indirect_fire.as_ref().map(coordinate).transpose()?,
            unloads,
            stopped_at: None,
        })
    }
}

pub fn orders(archive: &Archive, turn: i32) -> Result<Vec<RecordedOrder>, &'static str> {
    let mut orders = BTreeMap::new();
    for result in archive
        .submissions
        .iter()
        .filter(|result| result.turn_number == turn)
    {
        for submission in &result.submissions {
            for input in &submission.orders {
                let order = RecordedOrder::from_input(submission.player_number, input)?;
                orders.insert(order.unit_id, order);
            }
        }
    }
    if let Some(resolution) = archive
        .submissions
        .iter()
        .filter(|result| result.turn_number == turn)
        .find_map(|result| result.resolution.as_ref())
    {
        for order in orders.values_mut().filter(|order| order.path.len() > 1) {
            let actual = resolution
                .events
                .iter()
                .filter(|event| {
                    event.unit_id == order.unit_id
                        && (event.kind == TurnEventKind::Move
                            || event.kind == TurnEventKind::MovementStopped)
                })
                .filter_map(|event| event.path.last())
                .next_back()
                .copied();
            order.stopped_at = actual.filter(|position| Some(position) != order.path.last());
        }
    }
    Ok(orders.into_values().collect())
}

fn inspect_unit(unit: &mut Unit, orders: &[RecordedOrder], fired: &BTreeSet<UnitId>) {
    unit.combat_state = orders
        .iter()
        .find(|order| order.unit_id == unit.unit_id())
        .map(|order| combat::combat_state(unit, order.kind, fired.contains(&unit.unit_id())));
}

/// Theater participants retain their pre-volley resources internally, even with gauges concealed.
/// Inspect them before counting this frame's shots; board units show the state after the volley.
pub fn inspect_resolution(resolution: &mut TurnResolution, orders: &[RecordedOrder]) {
    let mut fired = BTreeSet::new();
    for frame in &mut resolution.frames {
        for shot in &mut frame.shots {
            inspect_unit(&mut shot.attacker, orders, &fired);
            inspect_unit(&mut shot.target, orders, &fired);
        }
        for impact in &mut frame.indirect_impacts {
            if let Some(attacker) = &mut impact.attacker {
                inspect_unit(&mut attacker.unit, orders, &fired);
            }
            if let Some(target) = &mut impact.target {
                inspect_unit(&mut target.unit, orders, &fired);
            }
        }
        fired.extend(frame.shots.iter().map(|shot| shot.attacker.unit_id()));
        fired.extend(frame.indirect_impacts.iter().filter_map(|impact| {
            impact
                .attacker
                .as_ref()
                .map(|attacker| attacker.unit.unit_id())
        }));
        for unit in &mut frame.units {
            inspect_unit(unit, orders, &fired);
        }
    }
}

pub fn conceal_enemy_states(resolution: &mut TurnResolution, player: PlayerNumber) {
    fn conceal(unit: &mut Unit, player: PlayerNumber) {
        if unit.player_number() != player {
            unit.combat_state = None;
        }
    }
    for frame in &mut resolution.frames {
        for unit in &mut frame.units {
            conceal(unit, player);
        }
        for shot in &mut frame.shots {
            conceal(&mut shot.attacker, player);
            conceal(&mut shot.target, player);
        }
        for impact in &mut frame.indirect_impacts {
            if let Some(attacker) = &mut impact.attacker {
                conceal(&mut attacker.unit, player);
            }
            if let Some(target) = &mut impact.target {
                conceal(&mut target.unit, player);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        combat::{DefenseReadiness, WeaponReadiness},
        map_definition::MapDefinition,
        scenario::Scenario,
        test_support::{FixtureValue, TestResult},
        turns::Turns,
    };
    use serde_json::json;

    fn scenario() -> TestResult<Scenario> {
        MapDefinition::parse(r#"{
            "width":5,"height":3,"theme":"GreenForest","features":[],"depots":[],
            "units":[
                {"id":1,"position":{"x":1,"y":1},"playerNumber":"Player1","kind":"Infantry","direction":"East"},
                {"id":2,"position":{"x":2,"y":1},"playerNumber":"Player2","kind":"Infantry","direction":"West"}
            ]
        }"#).fixture()?.scenario().fixture()
    }

    #[test]
    fn readiness_distinguishes_defense_shots_and_supplies() -> TestResult<()> {
        let mut board = scenario()?;
        let unit = board.units.first_mut().fixture()?;
        for (order, defense, weapon) in [
            (
                UnitOrderKind::Hold,
                DefenseReadiness::Unready,
                WeaponReadiness::NotOrdered,
            ),
            (
                UnitOrderKind::Move,
                DefenseReadiness::Unready,
                WeaponReadiness::NotOrdered,
            ),
            (
                UnitOrderKind::StandGround,
                DefenseReadiness::Ready,
                WeaponReadiness::NotOrdered,
            ),
            (
                UnitOrderKind::Ambush,
                DefenseReadiness::Ready,
                WeaponReadiness::CanFire,
            ),
            (
                UnitOrderKind::AttackMove,
                DefenseReadiness::Ready,
                WeaponReadiness::CanFire,
            ),
        ] {
            let state = combat::combat_state(unit, order, false);
            assert_eq!((state.defense, state.weapon), (defense, weapon));
        }
        unit.set_supplies_for_test(unit.supplies().upkeep_per_turn());
        let state = combat::combat_state(unit, UnitOrderKind::AttackMove, false);
        assert_eq!(
            (state.defense, state.weapon),
            (
                DefenseReadiness::Unready,
                WeaponReadiness::InsufficientSupplies
            )
        );
        let state = combat::combat_state(unit, UnitOrderKind::AttackMove, true);
        assert_eq!(
            (state.defense, state.weapon),
            (DefenseReadiness::Ready, WeaponReadiness::AlreadyFired)
        );
        Ok(())
    }

    #[test]
    fn inspection_preserves_pre_volley_state_archive_bytes_and_fog() -> TestResult<()> {
        let mut board = scenario()?;
        let mut turns = Turns::default();
        let mut orders = Vec::new();
        for (player, id, x, facing) in [
            (PlayerNumber::Player1, "1", 1, "East"),
            (PlayerNumber::Player2, "2", 2, "West"),
        ] {
            let input: MoveOrderInput = serde_json::from_value(json!({
                "unit_id":id, "path":[{"x":x,"y":1}], "ambush":true, "direction":facing
            }))?;
            orders.push(RecordedOrder::from_input(player, &input)?);
            turns.submit(&mut board, player, 1, vec![input])?;
        }
        let mut resolution = turns.last_resolution.fixture()?;
        let saved = serde_json::to_value(&resolution)?;
        inspect_resolution(&mut resolution, &orders);
        assert_eq!(saved, serde_json::to_value(&resolution)?);
        let volley = resolution
            .frames
            .iter()
            .find(|frame| !frame.shots.is_empty())
            .fixture()?;
        assert_eq!(volley.shots.len(), 2);
        for shot in &volley.shots {
            assert_eq!(
                shot.attacker.combat_state.fixture()?.weapon,
                WeaponReadiness::CanFire
            );
            assert_eq!(
                shot.target.combat_state.fixture()?.defense,
                DefenseReadiness::Ready
            );
        }
        for unit in &volley.units {
            let state = unit.combat_state.fixture()?;
            assert_eq!(
                (state.defense, state.weapon),
                (DefenseReadiness::Ready, WeaponReadiness::AlreadyFired)
            );
        }
        conceal_enemy_states(&mut resolution, PlayerNumber::Player1);
        for frame in &resolution.frames {
            for unit in &frame.units {
                assert_eq!(
                    unit.combat_state.is_some(),
                    unit.player_number() == PlayerNumber::Player1
                );
            }
            for shot in &frame.shots {
                assert_eq!(
                    shot.attacker.combat_state.is_some(),
                    shot.attacker.player_number() == PlayerNumber::Player1
                );
                assert_eq!(
                    shot.target.combat_state.is_some(),
                    shot.target.player_number() == PlayerNumber::Player1
                );
            }
        }
        Ok(())
    }
}
