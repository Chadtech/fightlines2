//! Stationary directional combat. Outcomes are resolved at shared movement and transport boundaries.
use crate::{
    map::Coordinate,
    scenario::{Direction, Scenario, Unit, UnitId, UnitKind},
    turns::{MoveOrder, TurnFrame},
    visibility,
};
use juniper::GraphQLObject;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, Debug, GraphQLObject)]
pub struct CombatRules {
    pub range: i32,
    pub damage: i32,
    pub readiness_cost: i32,
    pub shot_cost: i32,
}

pub fn rules(kind: UnitKind) -> CombatRules {
    let (range, damage) = match kind {
        UnitKind::Infantry => (1, 4),
        UnitKind::Tank => (1, 8),
        UnitKind::FieldGun => (3, 12),
        UnitKind::Truck => (0, 0),
    };
    CombatRules {
        range,
        damage,
        readiness_cost: 2,
        shot_cost: 2,
    }
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct Shot {
    pub origin: Coordinate,
    pub destination: Coordinate,
    pub damage: i32,
}

struct Engagement {
    shooter: UnitId,
    target: UnitId,
    shot: Shot,
}

pub struct Combat {
    ready: BTreeSet<UnitId>,
    fired: BTreeSet<UnitId>,
}

impl Combat {
    pub fn prepare(board: &mut Scenario, orders: &[MoveOrder]) -> Self {
        let mut ready = BTreeSet::new();
        for order in orders.iter().filter(|order| order.facing.is_ambush()) {
            if let Some(unit) = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == order.unit_id)
            {
                if let Some(direction) = order.facing.direction() {
                    unit.rotate(direction);
                }
                unit.spend_supplies(rules(unit.kind()).readiness_cost);
                ready.insert(unit.unit_id());
            }
        }
        Self {
            ready,
            fired: BTreeSet::new(),
        }
    }

    fn can_fire(&self, unit: &Unit) -> bool {
        let rule = rules(unit.kind());
        unit.is_alive()
            && unit.board_position().is_some()
            && rule.range > 0
            && !self.fired.contains(&unit.unit_id())
            && unit.supplies().current() >= unit.supplies().upkeep_per_turn() + rule.shot_cost
    }

    fn engagement(
        &self,
        board: &Scenario,
        shooter: &Unit,
        target: &Unit,
        directional: bool,
    ) -> Option<Engagement> {
        let origin = shooter.board_position()?;
        let destination = target.board_position()?;
        let dx = destination.x() - origin.x();
        let dy = destination.y() - origin.y();
        let distance = dx.abs() + dy.abs();
        let in_line = dx == 0 || dy == 0;
        let in_direction = match shooter.direction()? {
            Direction::North => dx == 0 && dy < 0,
            Direction::East => dy == 0 && dx > 0,
            Direction::South => dx == 0 && dy > 0,
            Direction::West => dy == 0 && dx < 0,
        };
        // Unready infantry/tanks can turn to return adjacent fire. Guns retain their narrow arc.
        let valid_arc = if directional || shooter.kind() == UnitKind::FieldGun {
            in_direction
        } else {
            in_line
        };
        let visible = visibility::visible_tiles(board, shooter.side());
        if !self.can_fire(shooter)
            || !target.is_alive()
            || shooter.side() == target.side()
            || distance == 0
            || distance > rules(shooter.kind()).range
            || !valid_arc
            || !visibility::observable(&board.map, &visible, destination)
            || !visibility::clear_line(&board.map, origin, destination)
        {
            return None;
        }
        Some(Engagement {
            shooter: shooter.unit_id(),
            target: target.unit_id(),
            shot: Shot {
                origin,
                destination,
                damage: rules(shooter.kind()).damage,
            },
        })
    }

    fn volley(
        &mut self,
        board: &mut Scenario,
        engagements: &[Engagement],
        frames: &mut Vec<TurnFrame>,
    ) {
        if engagements.is_empty() {
            return;
        }
        let mut damage = BTreeMap::<UnitId, i32>::new();
        for engagement in engagements {
            self.fired.insert(engagement.shooter);
            *damage.entry(engagement.target).or_default() += engagement.shot.damage;
            if let Some(unit) = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == engagement.shooter)
            {
                unit.spend_supplies(rules(unit.kind()).shot_cost);
                if let Some(direction) =
                    Direction::between(engagement.shot.origin, engagement.shot.destination)
                {
                    unit.rotate(direction);
                }
            }
        }
        for unit in &mut board.units {
            if let Some(damage) = damage.get(&unit.unit_id()) {
                unit.take_damage(*damage);
            }
        }
        let dead_carriers: BTreeSet<_> = board
            .units
            .iter()
            .filter(|unit| !unit.is_alive())
            .map(Unit::unit_id)
            .collect();
        for unit in &mut board.units {
            if unit
                .carrier_id()
                .is_some_and(|id| dead_carriers.contains(&id))
            {
                unit.take_damage(16);
            }
        }
        frames.push(TurnFrame {
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: 450,
            shots: engagements
                .iter()
                .map(|engagement| engagement.shot.clone())
                .collect(),
        });
        // Clear shots while preserving enough time to read the exchange and death marker.
        frames.push(TurnFrame {
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: 600,
            shots: Vec::new(),
        });
    }

    pub fn engage(
        &mut self,
        board: &mut Scenario,
        stopped: &mut BTreeSet<UnitId>,
        frames: &mut Vec<TurnFrame>,
    ) {
        let opening: Vec<_> = board
            .units
            .iter()
            .filter(|unit| self.ready.contains(&unit.unit_id()))
            .filter_map(|shooter| {
                board
                    .units
                    .iter()
                    .filter_map(|target| self.engagement(board, shooter, target, true))
                    .min_by_key(|engagement| {
                        (
                            (engagement.shot.destination.x() - engagement.shot.origin.x()).abs()
                                + (engagement.shot.destination.y() - engagement.shot.origin.y())
                                    .abs(),
                            engagement.target,
                        )
                    })
            })
            .collect();
        for engagement in &opening {
            stopped.insert(engagement.target);
        }
        self.volley(board, &opening, frames);
        let mut responses = Vec::new();
        for shooter in board
            .units
            .iter()
            .filter(|unit| !self.ready.contains(&unit.unit_id()))
        {
            let response = opening
                .iter()
                .filter(|engagement| engagement.target == shooter.unit_id())
                .filter_map(|engagement| {
                    board
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == engagement.shooter)
                })
                .filter_map(|target| self.engagement(board, shooter, target, false))
                .min_by_key(|engagement| engagement.target);
            if let Some(response) = response {
                responses.push(response);
            }
        }
        self.volley(board, &responses, frames);
        stopped.extend(
            board
                .units
                .iter()
                .filter(|unit| !unit.is_alive())
                .map(Unit::unit_id),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::{Map, Terrain},
        movement_resolution,
        scenario::PlayerNumber,
        test_support::{FixtureValue, TestResult},
    };

    fn fixture(
        kind: UnitKind,
        enemy_kind: UnitKind,
        enemy: Coordinate,
    ) -> TestResult<(Scenario, Vec<MoveOrder>)> {
        let mut scenario = Scenario::el_alamein().fixture()?;
        let shooter = scenario
            .units
            .iter()
            .find(|unit| unit.side() == PlayerNumber::Player1 && unit.kind() == kind)
            .cloned()
            .fixture()?;
        let target = scenario
            .units
            .iter()
            .find(|unit| unit.side() == PlayerNumber::Player2 && unit.kind() == enemy_kind)
            .cloned()
            .fixture()?;
        scenario.units = vec![shooter, target];
        scenario.map = Map::new(9, 9, Terrain::GrassPlain, BTreeMap::new()).fixture()?;
        scenario.units[0].move_to(Coordinate::new(3, 3));
        scenario.units[1].move_to(enemy);
        let orders = scenario
            .units
            .iter()
            .enumerate()
            .map(|(index, unit)| MoveOrder {
                unit_id: unit.unit_id(),
                facing: if index == 0 {
                    crate::turns::FacingOrder::Ambush(Direction::East)
                } else {
                    crate::turns::FacingOrder::Unchanged
                },
                path: vec![if index == 0 {
                    Coordinate::new(3, 3)
                } else {
                    enemy
                }],
                unloads: Vec::new(),
            })
            .collect();
        Ok((scenario, orders))
    }

    fn shots(result: &movement_resolution::MovementResolution) -> Vec<&Shot> {
        result
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .collect()
    }

    #[test]
    fn directional_ranges_include_each_forward_square_only() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            for (position, expected) in [
                (Coordinate::new(4, 3), true),
                (Coordinate::new(5, 3), kind == UnitKind::FieldGun),
                (Coordinate::new(6, 3), kind == UnitKind::FieldGun),
                (Coordinate::new(7, 3), false),
                (Coordinate::new(3, 4), false),
                (Coordinate::new(2, 3), false),
                (Coordinate::new(4, 4), false),
            ] {
                let (scenario, orders) = fixture(kind, UnitKind::Truck, position)?;
                let result = movement_resolution::resolve(&scenario, &orders, 1)?;
                assert_eq!(
                    !shots(&result).is_empty(),
                    expected,
                    "{kind:?} at {position:?}"
                );
                let final_unit = result.frames.last().fixture()?.units.first().fixture()?;
                assert_eq!(
                    final_unit.supplies().current(),
                    scenario.units[0].supplies().current() - 2 - if expected { 2 } else { 0 }
                );
            }
        }
        Ok(())
    }

    #[test]
    fn ambush_catches_a_crossing_unit_and_charges_only_successful_movement() -> TestResult<()> {
        let (scenario, mut orders) = fixture(
            UnitKind::Infantry,
            UnitKind::Infantry,
            Coordinate::new(4, 2),
        )?;
        orders[1]
            .path
            .extend([Coordinate::new(4, 3), Coordinate::new(4, 4)]);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        assert_eq!(result.paths.get(&orders[1].unit_id).fixture()?.len(), 2);
        assert_eq!(shots(&result).len(), 2);
        let units = &result.frames.last().fixture()?.units;
        assert_eq!(units[0].hit_points().current(), 12);
        assert_eq!(units[1].hit_points().current(), 12);
        assert_eq!(units[0].supplies().current(), 60);
        assert_eq!(units[1].supplies().current(), 58);
        assert!(
            result
                .frames
                .iter()
                .position(|frame| !frame.shots.is_empty())
                .fixture()?
                > 1
        );
        Ok(())
    }

    #[test]
    fn opening_fire_prevents_a_dead_unready_target_from_responding() -> TestResult<()> {
        let (mut scenario, orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        scenario.units[1].take_damage(4);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        assert_eq!(shots(&result).len(), 1);
        assert!(!result.frames.last().fixture()?.units[1].is_alive());
        assert_eq!(
            result.frames.last().fixture()?.units[0]
                .hit_points()
                .current(),
            16
        );
        Ok(())
    }

    #[test]
    fn ready_opponents_fire_simultaneously_and_can_destroy_each_other() -> TestResult<()> {
        let (mut scenario, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        for unit in &mut scenario.units {
            unit.take_damage(8);
        }
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        assert_eq!(
            result
                .frames
                .iter()
                .find(|frame| !frame.shots.is_empty())
                .fixture()?
                .shots
                .len(),
            2
        );
        assert!(
            result
                .frames
                .last()
                .fixture()?
                .units
                .iter()
                .all(|unit| !unit.is_alive())
        );
        let mut reversed = orders.clone();
        reversed.reverse();
        let other = movement_resolution::resolve(&scenario, &reversed, 1)?;
        assert_eq!(result.paths, other.paths);
        assert_eq!(shots(&other).len(), 2);
        Ok(())
    }

    #[test]
    fn projected_shots_preserve_observed_mutual_deaths_and_conceal_hidden_shooters()
    -> TestResult<()> {
        let (mut scenario, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        for unit in &mut scenario.units {
            unit.take_damage(8);
        }
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        let resolution = crate::turns::TurnResolution {
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        for side in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let visible = visibility::visible_tiles(&scenario, side);
            let observed = visibility::observed_resolution(&scenario, side, &visible, &resolution);
            let volley = observed
                .frames
                .iter()
                .find(|frame| !frame.shots.is_empty())
                .fixture()?;
            assert_eq!(volley.shots.len(), 2);
            assert_eq!(volley.units.len(), 2);
            assert!(volley.units.iter().all(|unit| unit.destroyed()));
        }
        let (mut scenario, orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(5, 3))?;
        scenario.map = Map::new(
            9,
            9,
            Terrain::GrassPlain,
            BTreeMap::from([(Coordinate::new(3, 3), Terrain::Forest)]),
        )
        .fixture()?;
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        let resolution = crate::turns::TurnResolution {
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        let side = PlayerNumber::Player2;
        let visible = visibility::visible_tiles(&scenario, side);
        let observed = visibility::observed_resolution(&scenario, side, &visible, &resolution);
        assert!(observed.frames.iter().all(|frame| frame.shots.is_empty()));
        assert!(observed.frames.iter().all(|frame| {
            frame
                .units
                .iter()
                .all(|unit| unit.unit_id() != scenario.units[0].unit_id())
        }));
        let side = PlayerNumber::Player1;
        let visible = visibility::visible_tiles(&scenario, side);
        let observed = visibility::observed_resolution(&scenario, side, &visible, &resolution);
        assert_eq!(
            observed
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .count(),
            1
        );
        Ok(())
    }

    #[test]
    fn readiness_and_firing_costs_reserve_upkeep_and_do_not_repeat() -> TestResult<()> {
        let (mut scenario, orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        scenario.units[0].spend_supplies(61);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        assert!(shots(&result).is_empty());
        assert_eq!(
            result.frames.last().fixture()?.units[0]
                .supplies()
                .current(),
            1
        );
        let (mut scenario, orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        let mut combat = Combat::prepare(&mut scenario, &orders);
        let mut frames = Vec::new();
        let mut stopped = BTreeSet::new();
        combat.engage(&mut scenario, &mut stopped, &mut frames);
        combat.engage(&mut scenario, &mut stopped, &mut frames);
        assert_eq!(frames.iter().flat_map(|frame| &frame.shots).count(), 1);
        assert_eq!(scenario.units[0].supplies().current(), 60);
        Ok(())
    }

    #[test]
    fn concealed_targets_and_obstructed_firing_lines_do_not_trigger() -> TestResult<()> {
        for terrain in [Terrain::Forest, Terrain::Hills] {
            let (mut scenario, orders) =
                fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(6, 3))?;
            scenario.map = Map::new(
                9,
                9,
                Terrain::GrassPlain,
                BTreeMap::from([(Coordinate::new(5, 3), terrain)]),
            )
            .fixture()?;
            let result = movement_resolution::resolve(&scenario, &orders, 1)?;
            assert!(shots(&result).is_empty());
        }
        let (mut scenario, orders) =
            fixture(UnitKind::Infantry, UnitKind::Truck, Coordinate::new(4, 3))?;
        scenario.map = Map::new(
            9,
            9,
            Terrain::GrassPlain,
            BTreeMap::from([(Coordinate::new(4, 3), Terrain::Forest)]),
        )
        .fixture()?;
        assert!(shots(&movement_resolution::resolve(&scenario, &orders, 1)?).is_empty());
        Ok(())
    }

    #[test]
    fn destroyed_truck_cargo_dies_and_grants_no_sight() -> TestResult<()> {
        let (mut scenario, orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        scenario.units[1].take_damage(4);
        let mut passenger = Scenario::el_alamein()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| unit.side() == PlayerNumber::Player2 && unit.kind() == UnitKind::Infantry)
            .fixture()?;
        passenger.board(scenario.units[1].unit_id());
        scenario.units.push(passenger);
        let mut combat = Combat::prepare(&mut scenario, &orders);
        combat.engage(&mut scenario, &mut BTreeSet::new(), &mut Vec::new());
        assert!(!scenario.units[1].is_alive());
        assert!(!scenario.units[2].is_alive());
        assert!(visibility::visible_tiles(&scenario, PlayerNumber::Player2).is_empty());
        scenario.finish_turn_resources();
        assert_eq!(scenario.units.len(), 1);
        Ok(())
    }
}
