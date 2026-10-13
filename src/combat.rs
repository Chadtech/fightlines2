//! Stationary directional combat. Outcomes are resolved at shared movement and transport boundaries.
use crate::{
    map::{Coordinate, Terrain},
    scenario::{Direction, HitPoints, Scenario, Unit, UnitId, UnitKind},
    turns::{MoveOrder, TravelMode, TurnFrame},
    visibility,
};
use juniper::{GraphQLEnum, GraphQLObject};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, Debug, GraphQLEnum)]
pub enum AmbushShape {
    Line,
    Cross,
}

#[derive(Clone, Copy, Debug, GraphQLObject)]
pub struct CombatRules {
    pub range: i32,
    pub shape: AmbushShape,
    /// Full-health weapon power before matchup and situational factors.
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
        shape: match kind {
            UnitKind::FieldGun => AmbushShape::Cross,
            UnitKind::Infantry | UnitKind::Tank | UnitKind::Truck => AmbushShape::Line,
        },
        damage,
        readiness_cost: 2,
        shot_cost: if kind == UnitKind::Infantry { 3 } else { 2 },
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum CombatKind {
    Ambush,
    AttackMove,
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct Shot {
    pub kind: CombatKind,
    pub origin: Coordinate,
    pub destination: Coordinate,
    pub damage: i32,
    pub attacker: Unit,
    pub target: Unit,
    pub attacker_health: CombatHealth,
    pub target_health: CombatHealth,
}

/// Encounter portraits are separate from battlefield sightings and never expose resources.
fn theater_participant(unit: &Unit) -> Unit {
    let mut participant = unit.clone();
    participant.conceal_resources();
    participant
}

#[derive(Clone, Copy, Debug, GraphQLObject)]
pub struct CombatHealth {
    pub before: HitPoints,
    pub after: HitPoints,
}

#[derive(Clone)]
struct Engagement {
    shooter: UnitId,
    target: UnitId,
    shot: Shot,
}

/// Serialize simultaneous damage into pair displays without changing combat outcomes.
/// Reciprocal shots share one transition; later pairs start at the preceding pair's health.
fn theater_shots(board: &Scenario, engagements: &[Engagement]) -> Vec<Shot> {
    let mut participants = board.units.clone();
    let mut pending: Vec<_> = engagements.iter().collect();
    let mut shots = Vec::new();
    while let Some(first) = pending.first().copied() {
        let (pair, rest): (Vec<_>, Vec<_>) = pending.into_iter().partition(|engagement| {
            (engagement.shooter == first.shooter && engagement.target == first.target)
                || (engagement.shooter == first.target && engagement.target == first.shooter)
        });
        pending = rest;
        let mut pair_shots: Vec<_> = pair
            .iter()
            .map(|engagement| engagement.shot.clone())
            .collect();
        for shot in &mut pair_shots {
            for unit in &participants {
                if unit.unit_id() == shot.attacker.unit_id() {
                    shot.attacker_health.before = unit.hit_points();
                }
                if unit.unit_id() == shot.target.unit_id() {
                    shot.target_health.before = unit.hit_points();
                }
            }
        }
        for engagement in pair {
            if let Some(unit) = participants
                .iter_mut()
                .find(|unit| unit.unit_id() == engagement.target)
            {
                unit.take_damage(engagement.shot.damage);
            }
        }
        for shot in &mut pair_shots {
            for unit in &participants {
                if unit.unit_id() == shot.attacker.unit_id() {
                    shot.attacker_health.after = unit.hit_points();
                }
                if unit.unit_id() == shot.target.unit_id() {
                    shot.target_health.after = unit.hit_points();
                }
            }
        }
        shots.extend(pair_shots);
    }
    shots
}

#[derive(Clone, Copy)]
enum AttackAspect {
    Front,
    Flank,
    Rear,
}

/// The forward/rear 90-degree sectors include their diagonal boundaries.
fn attack_aspect(unit: &Unit, opponent: &Unit) -> AttackAspect {
    if let (Some(position), Some(other), Some(direction)) = (
        unit.board_position(),
        opponent.board_position(),
        unit.direction(),
    ) {
        let dx = other.x() - position.x();
        let dy = other.y() - position.y();
        let (forward, sideways) = match direction {
            Direction::North => (-dy, dx),
            Direction::East => (dx, dy),
            Direction::South => (dy, dx),
            Direction::West => (-dx, dy),
        };
        if forward > 0 && forward >= sideways.abs() {
            AttackAspect::Front
        } else if forward < 0 && -forward >= sideways.abs() {
            AttackAspect::Rear
        } else {
            AttackAspect::Flank
        }
    } else {
        AttackAspect::Front
    }
}

pub struct Combat {
    ready: BTreeSet<UnitId>,
    fired: BTreeSet<UnitId>,
    attack_movers: BTreeSet<UnitId>,
    deferred_targets: BTreeMap<UnitId, BTreeSet<UnitId>>,
}

impl Combat {
    pub fn prepare(board: &mut Scenario, orders: &[MoveOrder]) -> Self {
        let mut ready = BTreeSet::new();
        for order in orders
            .iter()
            .filter(|order| order.facing.is_ambush() || order.travel == TravelMode::AttackMove)
        {
            if let Some(unit) = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == order.unit_id)
            {
                if let Some(direction) = order.facing.direction() {
                    unit.rotate(direction);
                }
                unit.spend_supplies(rules(unit.kind()).readiness_cost);
                if order.facing.is_ambush() {
                    ready.insert(unit.unit_id());
                }
            }
        }
        let mut combat = Self {
            ready,
            fired: BTreeSet::new(),
            attack_movers: orders
                .iter()
                .filter(|order| order.travel == TravelMode::AttackMove)
                .map(|order| order.unit_id)
                .collect(),
            deferred_targets: BTreeMap::new(),
        };
        for shooter in board
            .units
            .iter()
            .filter(|unit| combat.ready.contains(&unit.unit_id()))
        {
            let targets = board
                .units
                .iter()
                .filter(|target| combat.engagement(board, shooter, target).is_some())
                .map(Unit::unit_id)
                .collect();
            combat.deferred_targets.insert(shooter.unit_id(), targets);
        }
        combat
    }

    fn can_fire(&self, unit: &Unit) -> bool {
        let rule = rules(unit.kind());
        unit.is_alive()
            && unit.board_position().is_some()
            && rule.range > 0
            && !self.fired.contains(&unit.unit_id())
            && unit.supplies().current() >= unit.supplies().upkeep_per_turn() + rule.shot_cost
    }

    /// Resolve against the pre-volley board so reciprocal fire is simultaneous.
    fn damage(&self, board: &Scenario, shooter: &Unit, target: &Unit, kind: CombatKind) -> i32 {
        let health = shooter.hit_points();
        let strength = f64::from(health.current()) / f64::from(health.maximum());
        let battle_ready = self.ready.contains(&target.unit_id())
            || (self.attack_movers.contains(&target.unit_id())
                && (self.can_fire(target) || self.fired.contains(&target.unit_id())));
        let matchup = match (shooter.kind(), target.kind()) {
            (UnitKind::Truck, _) => 0.0,
            (_, UnitKind::Truck) => 3.5,
            (UnitKind::Infantry, UnitKind::Tank) if battle_ready => 0.25,
            (UnitKind::Infantry, UnitKind::Tank) => 2.0,
            (UnitKind::Tank, UnitKind::Infantry) => 2.5,
            (UnitKind::Tank, UnitKind::FieldGun) => 2.0,
            (UnitKind::FieldGun, _) => 1.5,
            _ => 1.0,
        };
        let readiness = if battle_ready { 1.0 } else { 1.5 };
        let facing = if battle_ready {
            match attack_aspect(target, shooter) {
                AttackAspect::Front => 1.0,
                AttackAspect::Flank => 1.25,
                AttackAspect::Rear => 1.5,
            }
        } else {
            1.0
        };
        let aim = match attack_aspect(shooter, target) {
            AttackAspect::Front => 1.0,
            AttackAspect::Flank => 0.85,
            AttackAspect::Rear => 0.7,
        };
        let cover = match target
            .board_position()
            .and_then(|position| board.map.tile_at(position))
        {
            Some(Terrain::Hills | Terrain::Forest) => 0.85,
            Some(Terrain::GrassPlain) | None => 1.0,
        };
        let ambush = if kind == CombatKind::Ambush && self.attack_movers.contains(&target.unit_id())
        {
            1.125
        } else {
            1.0
        };
        let damage = f64::from(rules(shooter.kind()).damage)
            * strength.powi(2)
            * matchup
            * readiness
            * facing
            * aim
            * cover
            * ambush;
        // Round once, after every factor. A living armed shooter still inflicts a hit.
        if shooter.is_alive() && shooter.kind() != UnitKind::Truck {
            (damage.round() as i32).clamp(1, target.hit_points().maximum())
        } else {
            0
        }
    }

    fn engagement(&self, board: &Scenario, shooter: &Unit, target: &Unit) -> Option<Engagement> {
        let origin = shooter.board_position()?;
        let destination = target.board_position()?;
        let dx = destination.x() - origin.x();
        let dy = destination.y() - origin.y();
        let (forward, sideways) = match shooter.direction()? {
            Direction::North => (-dy, dx),
            Direction::East => (dx, dy),
            Direction::South => (dy, dx),
            Direction::West => (-dx, dy),
        };
        let rule = rules(shooter.kind());
        let in_line = sideways == 0 && forward > 0 && forward <= rule.range;
        let in_cross_arm = match rule.shape {
            AmbushShape::Line => false,
            AmbushShape::Cross => forward == (rule.range + 1) / 2 && sideways.abs() == 1,
        };
        let visible = visibility::visible_tiles(board, shooter.side());
        if !self.can_fire(shooter)
            || !target.is_alive()
            || shooter.side() == target.side()
            || !(in_line || in_cross_arm)
            || !visibility::observable(&board.map, &visible, destination)
            || !visibility::clear_line(&board.map, origin, destination)
        {
            return None;
        }
        Some(Engagement {
            shooter: shooter.unit_id(),
            target: target.unit_id(),
            shot: Shot {
                kind: CombatKind::Ambush,
                origin,
                destination,
                damage: self.damage(board, shooter, target, CombatKind::Ambush),
                attacker: theater_participant(shooter),
                target: theater_participant(target),
                attacker_health: CombatHealth {
                    before: shooter.hit_points(),
                    after: shooter.hit_points(),
                },
                target_health: CombatHealth {
                    before: target.hit_points(),
                    after: target.hit_points(),
                },
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
        let shots = theater_shots(board, engagements);
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
            depots: board.depots.clone(),
            supply_crates: board.supply_crates.clone(),
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: 450,
            shots,
        });
        // Clear shots while preserving enough time to read the exchange and death marker.
        frames.push(TurnFrame {
            depots: board.depots.clone(),
            supply_crates: board.supply_crates.clone(),
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: if dead_carriers.is_empty() { 600 } else { 1400 },
            shots: Vec::new(),
        });
    }

    pub fn engage(
        &mut self,
        board: &mut Scenario,
        stopped: &mut BTreeSet<UnitId>,
        frames: &mut Vec<TurnFrame>,
    ) {
        self.engage_contacts(board, stopped, frames, &[]);
    }

    /// A ready field gun gets the first shot when a tank contacts it or aims
    /// an opposing ambush at it inside its observable firing area. Initial-contact
    /// deferral must not let a tank charge down that area before the gun responds.
    fn field_gun_interceptions(
        &self,
        board: &Scenario,
        contacts: &[(UnitId, UnitId)],
    ) -> Vec<Engagement> {
        board
            .units
            .iter()
            .filter(|gun| gun.kind() == UnitKind::FieldGun && self.ready.contains(&gun.unit_id()))
            .filter_map(|gun| {
                board
                    .units
                    .iter()
                    .filter(|tank| {
                        let contact = contacts.contains(&(tank.unit_id(), gun.unit_id()));
                        let deferred = self
                            .deferred_targets
                            .get(&gun.unit_id())
                            .is_some_and(|targets| targets.contains(&tank.unit_id()));
                        let opposing_ambush = self.ready.contains(&tank.unit_id())
                            && !deferred
                            && self.engagement(board, tank, gun).is_some();
                        tank.kind() == UnitKind::Tank && (contact || opposing_ambush)
                    })
                    .filter_map(|tank| self.engagement(board, gun, tank))
                    .min_by_key(|engagement| {
                        (
                            (engagement.shot.destination.x() - engagement.shot.origin.x()).abs()
                                + (engagement.shot.destination.y() - engagement.shot.origin.y())
                                    .abs(),
                            engagement.target,
                        )
                    })
            })
            .collect()
    }

    /// Physical encounters bypass sight and ambush range, including concealed defenders.
    pub fn engage_contacts(
        &mut self,
        board: &mut Scenario,
        stopped: &mut BTreeSet<UnitId>,
        frames: &mut Vec<TurnFrame>,
        contacts: &[(UnitId, UnitId)],
    ) {
        let interceptions = self.field_gun_interceptions(board, contacts);
        self.volley(board, &interceptions, frames);
        // Survivors may return fire with their reduced strength; other encounters
        // retain simultaneous resolution within their usual volley.
        let eligible: Vec<_> = board
            .units
            .iter()
            .filter(|unit| self.ready.contains(&unit.unit_id()))
            .flat_map(|shooter| {
                board
                    .units
                    .iter()
                    .filter_map(|target| self.engagement(board, shooter, target))
                    .collect::<Vec<_>>()
            })
            .collect();
        // Initial contacts may escape. Once they leave contact, re-entry triggers
        // immediate fire just like any newcomer, even if another unit moved.
        for (shooter, targets) in &mut self.deferred_targets {
            targets.retain(|target| {
                eligible.iter().any(|engagement| {
                    engagement.shooter == *shooter && engagement.target == *target
                })
            });
        }
        let opening: Vec<_> = self
            .ready
            .iter()
            .filter_map(|shooter| {
                eligible
                    .iter()
                    .filter(|engagement| {
                        engagement.shooter == *shooter
                            && !self
                                .deferred_targets
                                .get(shooter)
                                .is_some_and(|targets| targets.contains(&engagement.target))
                    })
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
        let mut opening: Vec<_> = opening.into_iter().cloned().collect();
        for (shooter_id, target_id) in contacts {
            let shooter = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == *shooter_id);
            let target = board.units.iter().find(|unit| unit.unit_id() == *target_id);
            if let (Some(shooter), Some(target)) = (shooter, target)
                && self.can_fire(shooter)
                && target.is_alive()
                && shooter.side() != target.side()
                && let (Some(origin), Some(destination)) =
                    (shooter.board_position(), target.board_position())
                && !opening
                    .iter()
                    .any(|engagement| engagement.shooter == *shooter_id)
            {
                opening.push(Engagement {
                    shooter: *shooter_id,
                    target: *target_id,
                    shot: Shot {
                        kind: CombatKind::AttackMove,
                        origin,
                        destination,
                        damage: self.damage(board, shooter, target, CombatKind::AttackMove),
                        attacker: theater_participant(shooter),
                        target: theater_participant(target),
                        attacker_health: CombatHealth {
                            before: shooter.hit_points(),
                            after: shooter.hit_points(),
                        },
                        target_health: CombatHealth {
                            before: target.hit_points(),
                            after: target.hit_points(),
                        },
                    },
                });
            }
        }
        opening.sort_by_key(|engagement| (engagement.shooter, engagement.target));
        for engagement in &opening {
            let continues_attack_move = engagement.shot.kind == CombatKind::Ambush
                && self.attack_movers.contains(&engagement.target);
            if !continues_attack_move {
                stopped.insert(engagement.target);
            }
        }
        self.volley(board, &opening, frames);
        stopped.extend(
            board
                .units
                .iter()
                .filter(|unit| !unit.is_alive())
                .map(Unit::unit_id),
        );
    }

    /// After movement and transport, initial contacts still in the line are vulnerable.
    pub fn finish(
        &mut self,
        board: &mut Scenario,
        stopped: &mut BTreeSet<UnitId>,
        frames: &mut Vec<TurnFrame>,
    ) {
        self.deferred_targets.clear();
        self.engage(board, stopped, frames);
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
                supply: crate::supplies::SupplyOrder::default(),
                travel: crate::turns::TravelMode::Normal,
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

    fn resolve_completed_movement(
        scenario: &Scenario,
        orders: &[MoveOrder],
        turn: i32,
    ) -> TestResult<movement_resolution::MovementResolution> {
        let mut result = movement_resolution::resolve(scenario, orders, turn)?;
        let mut board = scenario.clone();
        board.units = result.frames.last().fixture()?.units.clone();
        result
            .combat
            .finish(&mut board, &mut result.stopped, &mut result.frames);
        Ok(result)
    }

    fn shots(result: &movement_resolution::MovementResolution) -> Vec<&Shot> {
        result
            .frames
            .iter()
            .flat_map(|frame| &frame.shots)
            .collect()
    }

    #[test]
    fn full_strength_ready_tanks_destroy_ready_infantry_with_negligible_losses() -> TestResult<()> {
        for terrain in [Terrain::GrassPlain, Terrain::Hills] {
            for attack_move in [false, true] {
                let (mut board, mut orders) =
                    fixture(UnitKind::Tank, UnitKind::Infantry, Coordinate::new(4, 3))?;
                board.map = Map::new(9, 9, terrain, BTreeMap::new()).fixture()?;
                let infantry = orders.get_mut(1).fixture()?;
                if attack_move {
                    infantry.travel = TravelMode::AttackMove;
                    infantry.path.push(Coordinate::new(3, 3));
                } else {
                    infantry.facing = crate::turns::FacingOrder::Ambush(Direction::West);
                }
                let result = resolve_completed_movement(&board, &orders, 1)?;
                let units = &result.frames.last().fixture()?.units;
                assert_eq!(units.first().fixture()?.hit_points().current(), 15);
                assert_eq!(units.get(1).fixture()?.hit_points().current(), 0);
                let hits = shots(&result);
                assert_eq!(hits.len(), 2);
                let infantry_hit = hits
                    .iter()
                    .find(|shot| shot.attacker.kind() == UnitKind::Infantry)
                    .fixture()?;
                assert_eq!(infantry_hit.damage, 1);
                let tank_hit = hits
                    .iter()
                    .find(|shot| shot.attacker.kind() == UnitKind::Tank)
                    .fixture()?;
                assert_eq!(tank_hit.damage, 16);
            }
        }
        Ok(())
    }

    #[test]
    fn infantry_examples_show_readiness_cover_flanking_and_health() -> TestResult<()> {
        let (mut board, mut orders) =
            fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
        let combat = Combat::prepare(&mut board, &orders);
        for (direction, expected) in [
            (Direction::West, 12),
            (Direction::North, 12),
            (Direction::East, 12),
        ] {
            board.units.get_mut(1).fixture()?.rotate(direction);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::AttackMove
                ),
                expected
            );
        }
        board.units.get_mut(1).fixture()?.rotate(Direction::West);
        board.map = Map::new(9, 9, Terrain::Hills, BTreeMap::new()).fixture()?;
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            10
        );
        board.map = Map::new(9, 9, Terrain::GrassPlain, BTreeMap::new()).fixture()?;
        for (loss, expected) in [(4, 7), (4, 3), (4, 1)] {
            board.units.first_mut().fixture()?.take_damage(loss);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::AttackMove
                ),
                expected
            );
        }
        orders.get_mut(1).fixture()?.facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let (mut board, _) = fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
        let combat = Combat::prepare(&mut board, &orders);
        board.map = Map::new(9, 9, Terrain::Hills, BTreeMap::new()).fixture()?;
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            1
        );
        let (mut board, orders) =
            fixture(UnitKind::Infantry, UnitKind::Truck, Coordinate::new(4, 3))?;
        let combat = Combat::prepare(&mut board, &orders);
        board.map = Map::new(9, 9, Terrain::Hills, BTreeMap::new()).fixture()?;
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            16
        );
        board.map = Map::new(9, 9, Terrain::GrassPlain, BTreeMap::new()).fixture()?;
        board.units.first_mut().fixture()?.take_damage(8);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            5
        );
        Ok(())
    }

    #[test]
    fn ready_gun_also_preempts_an_opposing_tank_ambush() -> TestResult<()> {
        let (board, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders.get_mut(1).fixture()?.facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = resolve_completed_movement(&board, &orders, 1)?;
        let shots = shots(&result);
        assert_eq!(shots.len(), 1);
        assert_eq!(shots.first().fixture()?.attacker.kind(), UnitKind::FieldGun);
        assert_eq!(shots.first().fixture()?.target_health.after.current(), 0);
        assert_eq!(shots.first().fixture()?.attacker_health.after.current(), 16);
        Ok(())
    }

    #[test]
    fn tank_charging_a_ready_gun_cannot_bypass_initial_contact_deferral() -> TestResult<()> {
        let (board, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
        orders
            .get_mut(1)
            .fixture()?
            .path
            .push(Coordinate::new(3, 3));
        let result = resolve_completed_movement(&board, &orders, 1)?;
        let shots = shots(&result);
        assert_eq!(shots.len(), 1);
        assert_eq!(shots.first().fixture()?.kind, CombatKind::Ambush);
        assert_eq!(shots.first().fixture()?.target_health.after.current(), 0);
        assert_eq!(shots.first().fixture()?.attacker_health.after.current(), 16);
        orders.reverse();
        let reversed = resolve_completed_movement(&board, &orders, 1)?;
        assert_eq!(result.paths, reversed.paths);
        assert_eq!(self::shots(&reversed).first().fixture()?.damage, 16);
        Ok(())
    }

    #[test]
    fn tank_and_field_gun_contact_depends_on_the_guns_readiness_and_firing_area() -> TestResult<()>
    {
        for (facing, ready, expected_kind, tank_health, gun_health) in [
            (Direction::East, true, CombatKind::Ambush, 0, 16),
            (Direction::North, true, CombatKind::AttackMove, 16, 0),
            (Direction::West, true, CombatKind::AttackMove, 16, 0),
            (Direction::East, false, CombatKind::AttackMove, 16, 0),
        ] {
            let (mut board, mut orders) =
                fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
            orders.first_mut().fixture()?.facing = if ready {
                crate::turns::FacingOrder::Ambush(facing)
            } else {
                crate::turns::FacingOrder::Unchanged
            };
            orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
            let tank_id = board.units.get(1).fixture()?.unit_id();
            let gun_id = board.units.first().fixture()?.unit_id();
            let mut combat = Combat::prepare(&mut board, &orders);
            let mut frames = Vec::new();
            combat.engage_contacts(
                &mut board,
                &mut BTreeSet::new(),
                &mut frames,
                &[(tank_id, gun_id)],
            );
            let shots: Vec<_> = frames.iter().flat_map(|frame| &frame.shots).collect();
            assert_eq!(shots.len(), 1);
            assert_eq!(shots.first().fixture()?.kind, expected_kind);
            assert_eq!(
                board.units.get(1).fixture()?.hit_points().current(),
                tank_health
            );
            assert_eq!(
                board.units.first().fixture()?.hit_points().current(),
                gun_health
            );
        }
        Ok(())
    }

    #[test]
    fn wounded_or_spent_field_guns_do_not_guarantee_victory_over_tanks() -> TestResult<()> {
        let (mut board, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
        board.units.first_mut().fixture()?.take_damage(8);
        orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
        let gun_id = board.units.first().fixture()?.unit_id();
        let tank_id = board.units.get(1).fixture()?.unit_id();
        let mut combat = Combat::prepare(&mut board, &orders);
        let mut frames = Vec::new();
        combat.engage_contacts(
            &mut board,
            &mut BTreeSet::new(),
            &mut frames,
            &[(tank_id, gun_id)],
        );
        let shots: Vec<_> = frames.iter().flat_map(|frame| &frame.shots).collect();
        assert_eq!(shots.len(), 2);
        assert_eq!(shots.first().fixture()?.kind, CombatKind::Ambush);
        assert_eq!(shots.first().fixture()?.damage, 5);
        assert_eq!(shots.get(1).fixture()?.attacker_health.before.current(), 11);
        assert_eq!(shots.get(1).fixture()?.damage, 8);
        assert_eq!(board.units.first().fixture()?.hit_points().current(), 0);
        assert_eq!(board.units.get(1).fixture()?.hit_points().current(), 11);

        let (mut board, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
        let gun_id = board.units.first().fixture()?.unit_id();
        let tank_id = board.units.get(1).fixture()?.unit_id();
        let mut combat = Combat::prepare(&mut board, &orders);
        combat.fired.insert(gun_id);
        let mut frames = Vec::new();
        combat.engage_contacts(
            &mut board,
            &mut BTreeSet::new(),
            &mut frames,
            &[(tank_id, gun_id)],
        );
        assert_eq!(frames.iter().flat_map(|frame| &frame.shots).count(), 1);
        assert_eq!(board.units.first().fixture()?.hit_points().current(), 0);
        Ok(())
    }

    #[test]
    fn weapon_matchups_punish_trucks_unready_tanks_and_exposed_infantry() -> TestResult<()> {
        for (attacker, defender, expected) in [
            (UnitKind::Infantry, UnitKind::Truck, 16),
            (UnitKind::Tank, UnitKind::Truck, 16),
            (UnitKind::FieldGun, UnitKind::Truck, 16),
            (UnitKind::Infantry, UnitKind::Tank, 12),
            (UnitKind::Tank, UnitKind::Infantry, 16),
            (UnitKind::Tank, UnitKind::FieldGun, 16),
            (UnitKind::FieldGun, UnitKind::Infantry, 16),
            (UnitKind::FieldGun, UnitKind::Tank, 16),
            (UnitKind::FieldGun, UnitKind::FieldGun, 16),
        ] {
            let (mut board, orders) = fixture(attacker, defender, Coordinate::new(4, 3))?;
            let combat = Combat::prepare(&mut board, &orders);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::Ambush
                ),
                expected
            );
        }
        let (mut board, mut orders) =
            fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let combat = Combat::prepare(&mut board, &orders);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            1
        );
        Ok(())
    }

    #[test]
    fn health_reduces_firepower_quadratically_and_simultaneous_fire_uses_initial_health()
    -> TestResult<()> {
        for (lost_health, expected) in [(0, 12), (4, 7), (8, 3), (12, 1), (16, 0)] {
            let (mut board, orders) =
                fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
            board.units.first_mut().fixture()?.take_damage(lost_health);
            let combat = Combat::prepare(&mut board, &orders);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::Ambush
                ),
                expected
            );
        }
        let (mut board, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        for unit in &mut board.units {
            unit.take_damage(8);
        }
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = resolve_completed_movement(&board, &orders, 1)?;
        let shots = shots(&result);
        assert_eq!(shots.len(), 2);
        for shot in shots {
            assert_eq!(shot.damage, 2);
            assert_eq!(shot.attacker_health.before.current(), 8);
            assert_eq!(shot.attacker_health.after.current(), 6);
            assert_eq!(shot.target_health.after.current(), 6);
        }
        Ok(())
    }

    #[test]
    fn facing_and_terrain_modify_damage_without_granting_visibility() -> TestResult<()> {
        let (mut board, orders) = fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        let combat = Combat::prepare(&mut board, &orders);
        for (direction, expected) in [
            (Direction::West, 12),
            (Direction::North, 12),
            (Direction::East, 12),
        ] {
            board.units.get_mut(1).fixture()?.rotate(direction);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::Ambush
                ),
                expected
            );
        }
        let mut combat = combat;
        combat.ready.insert(board.units.get(1).fixture()?.unit_id());
        for (direction, expected) in [
            (Direction::West, 8),
            (Direction::North, 10),
            (Direction::East, 12),
        ] {
            board.units.get_mut(1).fixture()?.rotate(direction);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::Ambush
                ),
                expected
            );
        }
        combat
            .ready
            .remove(&board.units.get(1).fixture()?.unit_id());
        board.units.get_mut(1).fixture()?.rotate(Direction::West);
        for (direction, expected) in [
            (Direction::East, 12),
            (Direction::North, 10),
            (Direction::West, 8),
        ] {
            board.units.first_mut().fixture()?.rotate(direction);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::AttackMove
                ),
                expected
            );
        }
        board.units.first_mut().fixture()?.rotate(Direction::East);
        for terrain in [Terrain::Hills, Terrain::Forest] {
            board.map = Map::new(
                9,
                9,
                Terrain::GrassPlain,
                BTreeMap::from([(Coordinate::new(4, 3), terrain)]),
            )
            .fixture()?;
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    CombatKind::AttackMove
                ),
                10
            );
        }
        Ok(())
    }

    #[test]
    fn ambushers_have_a_small_bonus_against_battle_ready_attack_movers() -> TestResult<()> {
        let (mut board, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders[1].travel = TravelMode::AttackMove;
        let mut combat = Combat::prepare(&mut board, &orders);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            9
        );
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            8
        );
        combat.fired.insert(board.units.get(1).fixture()?.unit_id());
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            9
        );
        // An attack order without firing supplies cannot provide battle readiness.
        combat.fired.clear();
        board.units.get_mut(1).fixture()?.spend_supplies(31);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            14
        );
        Ok(())
    }

    #[test]
    fn directional_ranges_include_forward_squares_and_field_gun_cross_arms() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            for (position, expected) in [
                (Coordinate::new(4, 3), true),
                (Coordinate::new(5, 3), kind == UnitKind::FieldGun),
                (Coordinate::new(6, 3), kind == UnitKind::FieldGun),
                (Coordinate::new(7, 3), false),
                (Coordinate::new(5, 2), kind == UnitKind::FieldGun),
                (Coordinate::new(5, 4), kind == UnitKind::FieldGun),
                (Coordinate::new(6, 4), false),
                (Coordinate::new(3, 4), false),
                (Coordinate::new(2, 3), false),
                (Coordinate::new(4, 4), false),
            ] {
                let (scenario, orders) = fixture(kind, UnitKind::Truck, position)?;
                let result = resolve_completed_movement(&scenario, &orders, 1)?;
                assert_eq!(
                    !shots(&result).is_empty(),
                    expected,
                    "{kind:?} at {position:?}"
                );
                let final_unit = result.frames.last().fixture()?.units.first().fixture()?;
                assert_eq!(
                    final_unit.supplies().current(),
                    scenario.units[0].supplies().current()
                        - rules(kind).readiness_cost
                        - if expected { rules(kind).shot_cost } else { 0 }
                );
            }
        }
        Ok(())
    }

    #[test]
    fn field_gun_cross_rotates_with_facing() -> TestResult<()> {
        for direction in [
            Direction::North,
            Direction::East,
            Direction::South,
            Direction::West,
        ] {
            for (forward, sideways, expected) in [
                (1i32, 0i32, true),
                (2, 0, true),
                (3, 0, true),
                (2, -1, true),
                (2, 1, true),
                (1, 1, false),
                (3, 1, false),
                (2, 2, false),
                (0, 1, false),
                (-1, 0, false),
                (4, 0, false),
            ] {
                let (dx, dy) = match direction {
                    Direction::North => (sideways, -forward),
                    Direction::East => (forward, sideways),
                    Direction::South => (sideways, forward),
                    Direction::West => (-forward, sideways),
                };
                let position = Coordinate::new(u16::try_from(4 + dx)?, u16::try_from(4 + dy)?);
                let (mut scenario, mut orders) =
                    fixture(UnitKind::FieldGun, UnitKind::Truck, position)?;
                scenario.units[0].move_to(Coordinate::new(4, 4));
                orders[0].path = vec![Coordinate::new(4, 4)];
                orders[0].facing = crate::turns::FacingOrder::Ambush(direction);
                let result = resolve_completed_movement(&scenario, &orders, 1)?;
                assert_eq!(
                    !shots(&result).is_empty(),
                    expected,
                    "{direction:?} at {position:?}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn initial_contacts_can_escape_but_remaining_contacts_wait_until_movement_finishes()
    -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            let within_line_x = if kind == UnitKind::FieldGun { 5 } else { 4 };
            let within_line = Coordinate::new(within_line_x, 3);
            for (route, expected_shots) in [
                (Vec::new(), 1),
                (vec![within_line], 1),
                (vec![Coordinate::new(4, 2)], 0),
                // Passing through a second firing square while withdrawing is safe.
                (
                    vec![
                        within_line,
                        Coordinate::new(within_line_x, 2),
                        Coordinate::new(within_line_x, 1),
                    ],
                    0,
                ),
            ] {
                let (scenario, mut orders) = fixture(kind, UnitKind::Truck, Coordinate::new(4, 3))?;
                // Avoid a duplicate position for the one-square firing lines.
                orders[1].path.extend(
                    route
                        .into_iter()
                        .filter(|position| *position != Coordinate::new(4, 3)),
                );
                let mut result = movement_resolution::resolve(&scenario, &orders, 1)?;
                assert!(shots(&result).is_empty());
                assert_eq!(
                    result.paths.get(&orders[1].unit_id).fixture()?,
                    &orders[1].path
                );
                let mut board = scenario.clone();
                board.units = result.frames.last().fixture()?.units.clone();
                result
                    .combat
                    .finish(&mut board, &mut result.stopped, &mut result.frames);
                assert_eq!(shots(&result).len(), expected_shots, "{kind:?}");
            }
        }
        Ok(())
    }

    #[test]
    fn initial_contact_leaving_and_reentering_triggers_before_its_route_finishes() -> TestResult<()>
    {
        let (scenario, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        orders[1].path.extend([
            Coordinate::new(4, 2),
            Coordinate::new(5, 2),
            Coordinate::new(5, 3),
            Coordinate::new(6, 3),
        ]);
        let result = movement_resolution::resolve(&scenario, &orders, 1)?;
        assert_eq!(shots(&result).len(), 1);
        assert_eq!(shots(&result)[0].destination, Coordinate::new(5, 2));
        assert_eq!(result.paths.get(&orders[1].unit_id).fixture()?.len(), 3);
        Ok(())
    }

    #[test]
    fn newcomer_triggers_even_with_a_nearer_initial_contact_and_consumes_the_only_shot()
    -> TestResult<()> {
        let (mut scenario, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        let mut newcomer = Scenario::el_alamein()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| {
                unit.side() == PlayerNumber::Player2
                    && unit.kind() == UnitKind::Truck
                    && unit.unit_id() != scenario.units[1].unit_id()
            })
            .fixture()?;
        newcomer.move_to(Coordinate::new(5, 1));
        orders.push(MoveOrder {
            supply: crate::supplies::SupplyOrder::default(),
            travel: crate::turns::TravelMode::Normal,
            unit_id: newcomer.unit_id(),
            facing: crate::turns::FacingOrder::Unchanged,
            path: vec![
                Coordinate::new(5, 1),
                Coordinate::new(5, 2),
                Coordinate::new(5, 3),
            ],
            unloads: Vec::new(),
        });
        scenario.units.push(newcomer);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        assert_eq!(shots(&result).len(), 1);
        assert_eq!(shots(&result)[0].destination, Coordinate::new(5, 2));
        assert_eq!(result.paths.get(&orders[2].unit_id).fixture()?.len(), 2);
        assert_eq!(
            result.frames.last().fixture()?.units[1]
                .hit_points()
                .current(),
            16
        );
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
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        assert_eq!(result.paths.get(&orders[1].unit_id).fixture()?.len(), 2);
        assert_eq!(shots(&result).len(), 1);
        let units = &result.frames.last().fixture()?.units;
        assert_eq!(units[0].hit_points().current(), 16);
        assert_eq!(units[1].hit_points().current(), 10);
        assert_eq!(units[0].supplies().current(), 59);
        assert_eq!(units[1].supplies().current(), 61);
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
    fn ambushed_attack_move_continues_only_if_it_survives() -> TestResult<()> {
        for initial_damage in [0, 8] {
            let (mut scenario, mut orders) =
                fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 2))?;
            scenario.units[1].take_damage(initial_damage);
            orders[1].travel = TravelMode::AttackMove;
            orders[1]
                .path
                .extend([Coordinate::new(4, 3), Coordinate::new(4, 4)]);
            let result = resolve_completed_movement(&scenario, &orders, 1)?;
            let target = result.frames.last().fixture()?.units.get(1).fixture()?;
            let survived = initial_damage == 0;
            let expected_path = if survived {
                orders[1].path.clone()
            } else {
                orders[1].path[..2].to_vec()
            };
            assert_eq!(
                result.paths.get(&orders[1].unit_id).fixture()?,
                &expected_path
            );
            assert_eq!(result.stopped.contains(&orders[1].unit_id), !survived);
            assert_eq!(target.is_alive(), survived);
            assert_eq!(target.hit_points().current(), if survived { 5 } else { 0 });
            assert_eq!(
                target.fuel().fixture()?.current,
                if survived { 30 } else { 31 }
            );
            assert_eq!(
                target.supplies().current(),
                scenario.units[1].supplies().current() - rules(target.kind()).readiness_cost
            );
            assert_eq!(shots(&result).len(), 1);
            assert_eq!(shots(&result)[0].kind, CombatKind::Ambush);
            assert_eq!(shots(&result)[0].destination, Coordinate::new(4, 3));
        }
        Ok(())
    }

    #[test]
    fn ambushed_attack_move_can_reach_and_attack_an_enemy_later() -> TestResult<()> {
        let (mut scenario, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 2))?;
        let mut defender = Scenario::el_alamein()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| {
                unit.side() == PlayerNumber::Player1
                    && unit.kind() == UnitKind::Tank
                    && unit.unit_id() != orders[0].unit_id
            })
            .fixture()?;
        defender.move_to(Coordinate::new(4, 5));
        let defender_id = defender.unit_id();
        scenario.units.push(defender);
        orders[1].travel = TravelMode::AttackMove;
        orders[1]
            .path
            .extend([Coordinate::new(4, 3), Coordinate::new(4, 4)]);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        assert_eq!(
            result.paths.get(&orders[1].unit_id).fixture()?,
            &orders[1].path
        );
        let shots = shots(&result);
        assert_eq!(shots.len(), 2);
        assert_eq!(shots[0].kind, CombatKind::Ambush);
        assert_eq!(shots[1].kind, CombatKind::AttackMove);
        assert_eq!(shots[1].attacker.unit_id(), orders[1].unit_id);
        assert_eq!(shots[1].target.unit_id(), defender_id);
        assert_eq!(shots[1].attacker_health.before.current(), 5);
        assert_eq!(shots[1].target_health.after.current(), 15);
        assert!(result.stopped.contains(&orders[1].unit_id));
        let mover = result.frames.last().fixture()?.units.get(1).fixture()?;
        assert_eq!(mover.supplies().current(), 28);
        assert_eq!(mover.fuel().fixture()?.current, 30);
        Ok(())
    }

    #[test]
    fn tank_entering_an_ambush_takes_one_hit_without_return_fire() -> TestResult<()> {
        let (scenario, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 2))?;
        orders[1]
            .path
            .extend([Coordinate::new(4, 3), Coordinate::new(4, 4)]);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        let feedback = result
            .frames
            .iter()
            .skip_while(|frame| frame.shots.is_empty())
            .nth(1)
            .fixture()?;
        assert_eq!(feedback.duration_ms, 600);
        let units = &result.frames.last().fixture()?.units;
        assert_eq!(shots(&result).len(), 1);
        assert_eq!(shots(&result)[0].origin, Coordinate::new(3, 3));
        assert_eq!(shots(&result)[0].destination, Coordinate::new(4, 3));
        assert_eq!(shots(&result)[0].damage, 12);
        assert_eq!(shots(&result)[0].attacker_health.before.current(), 16);
        assert_eq!(shots(&result)[0].attacker_health.after.current(), 16);
        assert_eq!(shots(&result)[0].target_health.before.current(), 16);
        assert_eq!(shots(&result)[0].target_health.after.current(), 4);
        assert_eq!(units[0].hit_points().current(), 16);
        assert_eq!(units[1].hit_points().current(), 4);
        assert_eq!(units[0].supplies().current(), 28);
        assert_eq!(units[1].supplies(), scenario.units[1].supplies());
        assert_eq!(units[1].direction(), Some(Direction::South));
        assert_eq!(units[1].fuel().fixture()?.current, 31);
        assert_eq!(
            result.paths.get(&orders[1].unit_id).fixture()?,
            &vec![Coordinate::new(4, 2), Coordinate::new(4, 3)]
        );
        Ok(())
    }

    #[test]
    fn ambush_kills_an_unready_target_without_return_fire() -> TestResult<()> {
        let (mut scenario, orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        scenario.units[1].take_damage(4);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
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
        let (scenario, mut orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::FieldGun,
            Coordinate::new(4, 3),
        )?;
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
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
        assert_eq!(result.frames.last().fixture()?.duration_ms, 1400);
        let mut reversed = orders.clone();
        reversed.reverse();
        let other = resolve_completed_movement(&scenario, &reversed, 1)?;
        assert_eq!(result.paths, other.paths);
        assert_eq!(shots(&other).len(), 2);
        Ok(())
    }

    #[test]
    fn overlapping_ambushes_carry_health_between_pair_displays() -> TestResult<()> {
        let (mut scenario, mut orders) =
            fixture(UnitKind::Tank, UnitKind::Tank, Coordinate::new(4, 3))?;
        let first_id = scenario.units.first().fixture()?.unit_id();
        let mut second_shooter = Scenario::el_alamein()
            .fixture()?
            .units
            .iter()
            .find(|unit| {
                unit.side() == PlayerNumber::Player1
                    && unit.kind() == UnitKind::Tank
                    && unit.unit_id() != first_id
            })
            .cloned()
            .fixture()?;
        second_shooter.move_to(Coordinate::new(5, 3));
        orders.push(MoveOrder {
            supply: crate::supplies::SupplyOrder::default(),
            travel: crate::turns::TravelMode::Normal,
            unit_id: second_shooter.unit_id(),
            facing: crate::turns::FacingOrder::Ambush(Direction::West),
            path: vec![Coordinate::new(5, 3)],
            unloads: Vec::new(),
        });
        scenario.units.push(second_shooter);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        let shots = shots(&result);
        assert_eq!(shots.len(), 2);
        let first = shots.first().fixture()?;
        let second = shots.get(1).fixture()?;
        assert_eq!(first.target_health.before.current(), 16);
        assert_eq!(first.target_health.after.current(), 4);
        assert_eq!(second.target_health.before.current(), 4);
        assert_eq!(second.target_health.after.current(), 0);
        assert!(
            !result
                .frames
                .last()
                .fixture()?
                .units
                .get(1)
                .fixture()?
                .is_alive()
        );
        for side in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let resolution = crate::turns::TurnResolution {
                turn_number: 1,
                events: Vec::new(),
                frames: result.frames.clone(),
            };
            let visible = visibility::visible_tiles(&scenario, side);
            let observed = visibility::observed_resolution(&scenario, side, &visible, &resolution);
            let projected: Vec<_> = observed
                .frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .collect();
            assert_eq!(
                projected.first().fixture()?.target_health.after.current(),
                4
            );
            assert_eq!(
                projected.get(1).fixture()?.target_health.before.current(),
                4
            );
        }
        Ok(())
    }

    #[test]
    fn projected_shots_show_hidden_combatants_without_revealing_battlefield_units() -> TestResult<()>
    {
        let (scenario, mut orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::FieldGun,
            Coordinate::new(4, 3),
        )?;
        orders[1].facing = crate::turns::FacingOrder::Ambush(Direction::West);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
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
            for shot in &volley.shots {
                assert_eq!(shot.attacker_health.before.current(), 16);
                assert_eq!(shot.attacker_health.after.current(), 0);
                assert_eq!(shot.target_health.before.current(), 16);
                assert_eq!(shot.target_health.after.current(), 0);
            }
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
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        let resolution = crate::turns::TurnResolution {
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        let side = PlayerNumber::Player2;
        let visible = visibility::visible_tiles(&scenario, side);
        let observed = visibility::observed_resolution(&scenario, side, &visible, &resolution);
        let volley = observed
            .frames
            .iter()
            .find(|frame| !frame.shots.is_empty())
            .fixture()?;
        assert_eq!(volley.shots.len(), 1);
        let shot = volley.shots.first().fixture()?;
        assert_eq!(shot.attacker.kind(), UnitKind::FieldGun);
        assert_eq!(shot.target.kind(), UnitKind::Truck);
        assert_eq!(shot.target_health.before.current(), 16);
        assert_eq!(shot.target_health.after.current(), 0);
        assert!(shot.attacker.resources().is_none());
        assert!(shot.target.resources().is_none());
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
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
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
        combat.finish(&mut scenario, &mut stopped, &mut frames);
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
            let result = resolve_completed_movement(&scenario, &orders, 1)?;
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
        assert!(shots(&resolve_completed_movement(&scenario, &orders, 1)?).is_empty());
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
        combat.finish(&mut scenario, &mut BTreeSet::new(), &mut Vec::new());
        assert!(!scenario.units[1].is_alive());
        assert!(!scenario.units[2].is_alive());
        assert!(visibility::visible_tiles(&scenario, PlayerNumber::Player2).is_empty());
        scenario.finish_turn_resources(1);
        assert_eq!(scenario.units.len(), 1);
        Ok(())
    }
}
