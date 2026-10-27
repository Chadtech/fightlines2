//! Stationary directional combat. Outcomes are resolved at shared movement and transport boundaries.
use crate::{
    map::{Coordinate, Terrain},
    scenario::{
        BuildingKind, DepotHp, Direction, Entrenchment, HitPoints, PlayerNumber, Scenario, Unit,
        UnitId, UnitKind,
    },
    turns::{FacingOrder, MoveOrder, TravelMode, TurnFrame, UnitOrderKind},
    visibility,
};
use juniper::{GraphQLEnum, GraphQLObject, graphql_object};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Copy, Debug, GraphQLEnum)]
pub enum AmbushShape {
    Line,
    Cross,
}

#[derive(Clone, Copy, Debug, GraphQLObject)]
pub struct CombatRules {
    pub range: i32,
    /// Euclidean tile radius; zero disables indirect fire.
    pub indirect_range: i32,
    pub shape: AmbushShape,
    /// Full-health weapon power before matchup and situational factors.
    pub damage: i32,
    pub dig_in_cost: i32,
    pub readiness_cost: i32,
    pub shot_cost: i32,
}

pub fn rules(kind: UnitKind) -> CombatRules {
    let (range, damage) = match kind {
        UnitKind::Infantry => (1, 4),
        UnitKind::Tank => (2, 8),
        UnitKind::FieldGun => (3, 12),
        UnitKind::Truck => (0, 0),
    };
    CombatRules {
        range,
        indirect_range: if kind == UnitKind::FieldGun { 9 } else { 0 },
        shape: match kind {
            UnitKind::FieldGun => AmbushShape::Cross,
            UnitKind::Infantry | UnitKind::Tank | UnitKind::Truck => AmbushShape::Line,
        },
        damage,
        dig_in_cost: if kind == UnitKind::Infantry { 16 } else { 0 },
        readiness_cost: 8,
        shot_cost: match kind {
            UnitKind::Infantry => 12,
            UnitKind::FieldGun => 20,
            UnitKind::Tank => 16,
            UnitKind::Truck => 8,
        },
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum, Serialize, Deserialize)]
pub enum CombatKind {
    Ambush,
    AttackMove,
    IndirectFire,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum DefenseReadiness {
    Ready,
    Unready,
    Exposed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum WeaponReadiness {
    CanFire,
    AlreadyFired,
    InsufficientSupplies,
    NotOrdered,
    Aboard,
    Destroyed,
    Unarmed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject)]
pub struct CombatState {
    pub order: UnitOrderKind,
    pub defense: DefenseReadiness,
    pub weapon: WeaponReadiness,
}

fn weapon_readiness(unit: &Unit, fired: bool) -> WeaponReadiness {
    if !unit.is_alive() {
        WeaponReadiness::Destroyed
    } else if unit.board_position().is_none() {
        WeaponReadiness::Aboard
    } else if rules(unit.kind()).range == 0 {
        WeaponReadiness::Unarmed
    } else if fired {
        WeaponReadiness::AlreadyFired
    } else if unit.supplies().current()
        < unit.supplies().upkeep_per_turn() + rules(unit.kind()).shot_cost
    {
        WeaponReadiness::InsufficientSupplies
    } else {
        WeaponReadiness::CanFire
    }
}

/// The same readiness decision drives damage and recorded-turn inspection.
pub fn combat_state(unit: &Unit, order: UnitOrderKind, fired: bool) -> CombatState {
    let availability = weapon_readiness(unit, fired);
    let defense = match unit.kind() {
        UnitKind::Truck | UnitKind::FieldGun => DefenseReadiness::Exposed,
        UnitKind::Infantry | UnitKind::Tank => {
            let prepared = match order {
                UnitOrderKind::Ambush | UnitOrderKind::StandGround => true,
                UnitOrderKind::AttackMove => availability == WeaponReadiness::CanFire || fired,
                _ => false,
            };
            if prepared && unit.board_position().is_some() && unit.is_alive() {
                DefenseReadiness::Ready
            } else {
                DefenseReadiness::Unready
            }
        }
    };
    let weapon = match order {
        UnitOrderKind::Ambush | UnitOrderKind::AttackMove | UnitOrderKind::IndirectFire => {
            availability
        }
        _ if availability == WeaponReadiness::CanFire
            || availability == WeaponReadiness::InsufficientSupplies =>
        {
            WeaponReadiness::NotOrdered
        }
        _ => availability,
    };
    CombatState {
        order,
        defense,
        weapon,
    }
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
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

#[derive(Clone, Copy, Debug, GraphQLObject, Serialize, Deserialize)]
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
    while let Some(first) = next_theater_pair(&pending) {
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

/// Show a shooter's outgoing pair before another pair can kill it. Reciprocal
/// shots are already one pair. Cycles retain stable order because no pair can
/// precede all of its incoming fire in a simultaneous cycle.
fn next_theater_pair<'a>(pending: &[&'a Engagement]) -> Option<&'a Engagement> {
    pending
        .iter()
        .copied()
        .find(|candidate| {
            !pending
                .iter()
                .any(|other| other.shooter == candidate.target && other.target != candidate.shooter)
        })
        .or_else(|| pending.first().copied())
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

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct IndirectImpact {
    #[serde(default)]
    pub depot: Option<BuildingImpact>,
    pub attacker: Option<IndirectFireAttacker>,
    pub player_number: PlayerNumber,
    pub destination: Coordinate,
    pub target: Option<IndirectFireTarget>,
}

#[graphql_object]
impl IndirectImpact {
    fn depot(&self) -> Option<&BuildingImpact> {
        self.depot.as_ref()
    }
    fn attacker(&self) -> Option<&IndirectFireAttacker> {
        self.attacker.as_ref()
    }

    fn player_number(&self) -> PlayerNumber {
        self.player_number
    }

    fn destination(&self) -> Coordinate {
        self.destination
    }

    fn target(&self) -> Option<&IndirectFireTarget> {
        self.target.as_ref()
    }
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct BuildingImpact {
    pub kind: BuildingKind,
    pub before: DepotHp,
    pub after: DepotHp,
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct IndirectFireAttacker {
    pub unit: Unit,
    pub health: HitPoints,
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct IndirectFireTarget {
    pub unit: Unit,
    pub health: CombatHealth,
}

pub fn within_indirect_range(origin: Coordinate, target: Coordinate, range: i32) -> bool {
    let dx = i64::from(target.x() - origin.x());
    let dy = i64::from(target.y() - origin.y());
    range > 0 && dx * dx + dy * dy <= i64::from(range).pow(2)
}

#[derive(Clone, Copy)]
struct ShellLaunch {
    shooter: UnitId,
    origin: Coordinate,
    destination: Coordinate,
}

#[derive(Clone)]
pub struct Combat {
    indirect_targets: BTreeMap<UnitId, Coordinate>,
    ambushers: BTreeSet<UnitId>,
    standing_ground: BTreeSet<UnitId>,
    fired: BTreeSet<UnitId>,
    attack_movers: BTreeSet<UnitId>,
    deferred_targets: BTreeMap<UnitId, BTreeSet<UnitId>>,
}

impl Combat {
    pub fn prepare(board: &mut Scenario, orders: &[MoveOrder]) -> Self {
        // Pay before combat; protection is completed only after all fighting.
        for order in orders.iter().filter(|order| order.facing.is_digging_in()) {
            if let Some(unit) = board
                .units
                .iter_mut()
                .find(|unit| unit.unit_id() == order.unit_id)
            {
                unit.spend_supplies(rules(unit.kind()).dig_in_cost);
            }
        }
        let mut ambushers = BTreeSet::new();
        for order in orders.iter().filter(|order| {
            order.facing.is_ambush()
                || order.facing.is_standing_ground()
                || order.facing.indirect_target().is_some()
                || order.travel == TravelMode::AttackMove
        }) {
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
                    ambushers.insert(unit.unit_id());
                }
            }
        }
        let mut combat = Self {
            indirect_targets: orders
                .iter()
                .filter_map(|order| match order.facing {
                    FacingOrder::IndirectFire(target) => Some((order.unit_id, target)),
                    _ => None,
                })
                .collect(),
            ambushers,
            standing_ground: orders
                .iter()
                .filter(|order| order.facing.is_standing_ground())
                .map(|order| order.unit_id)
                .collect(),
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
            .filter(|unit| combat.ambushers.contains(&unit.unit_id()))
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

    /// Activate a dismounted unit without resetting anyone's spent shots or targets.
    pub fn activate(&mut self, board: &mut Scenario, orders: &[MoveOrder]) {
        let additional = Self::prepare(board, orders);
        self.ambushers.extend(additional.ambushers);
        self.standing_ground.extend(additional.standing_ground);
        self.attack_movers.extend(additional.attack_movers);
        self.indirect_targets.extend(additional.indirect_targets);
    }

    pub fn has_fired_directly(&self, id: UnitId) -> bool {
        // Indirect-fire orders are exclusive, but still consume the unit's shot.
        self.fired.contains(&id) && !self.indirect_targets.contains_key(&id)
    }

    fn can_fire(&self, unit: &Unit) -> bool {
        weapon_readiness(unit, self.fired.contains(&unit.unit_id())) == WeaponReadiness::CanFire
    }

    /// Resolve against the pre-volley board so reciprocal fire is simultaneous.
    fn damage(&self, board: &Scenario, shooter: &Unit, target: &Unit, kind: CombatKind) -> i32 {
        let health = shooter.hit_points();
        let strength = f64::from(health.current()) / f64::from(health.maximum());
        // A prepared gun can fire, but its exposed crew cannot gain defensive readiness.
        let order = if self.standing_ground.contains(&target.unit_id()) {
            UnitOrderKind::StandGround
        } else if self.ambushers.contains(&target.unit_id()) {
            UnitOrderKind::Ambush
        } else if self.attack_movers.contains(&target.unit_id()) {
            UnitOrderKind::AttackMove
        } else {
            UnitOrderKind::Hold
        };
        let defensively_ready = combat_state(target, order, self.fired.contains(&target.unit_id()))
            .defense
            == DefenseReadiness::Ready;
        let matchup = match (shooter.kind(), target.kind()) {
            (UnitKind::Truck, _) => 0.0,
            (_, UnitKind::Truck) => 3.5,
            (UnitKind::Infantry, UnitKind::Infantry) => 1.75,
            (UnitKind::Infantry, UnitKind::Tank) if defensively_ready => 0.25,
            (UnitKind::Infantry, UnitKind::Tank) => 2.0,
            (UnitKind::Infantry, UnitKind::FieldGun) => 3.0,
            (UnitKind::Tank, UnitKind::Infantry) => 2.5,
            (UnitKind::Tank, UnitKind::FieldGun) => 2.0,
            (UnitKind::FieldGun, _) => 1.5,
            _ => 1.0,
        };
        let readiness = if defensively_ready { 1.0 } else { 1.5 };
        let target_aspect = attack_aspect(target, shooter);
        let facing = if defensively_ready {
            match target_aspect {
                AttackAspect::Front => 1.0,
                AttackAspect::Flank => 1.25,
                AttackAspect::Rear => 1.5,
            }
        } else {
            1.0
        };
        let aim = if kind == CombatKind::IndirectFire {
            1.0
        } else {
            match attack_aspect(shooter, target) {
                AttackAspect::Front => 1.0,
                AttackAspect::Flank => 0.85,
                AttackAspect::Rear => 0.7,
            }
        };
        let cover = match target
            .board_position()
            .and_then(|position| board.map.tile_at(position))
        {
            Some(Terrain::Hills | Terrain::Forest) => 0.85,
            Some(
                Terrain::Plain
                | Terrain::Mountains
                | Terrain::Water
                | Terrain::Beach
                | Terrain::Road(_),
            )
            | None => 1.0,
        };
        let ambush = match (kind, shooter.kind(), target.kind(), target_aspect) {
            // Infantry can seriously hurt prepared armor by ambushing its sides or rear.
            (
                CombatKind::Ambush,
                UnitKind::Infantry,
                UnitKind::Tank,
                AttackAspect::Flank | AttackAspect::Rear,
            ) if defensively_ready => 5.0,
            (CombatKind::Ambush, _, _, _) if self.attack_movers.contains(&target.unit_id()) => {
                1.125
            }
            _ => 1.0,
        };
        let entrenchment = if target.entrenchment() == Entrenchment::Entrenched {
            match shooter.kind() {
                UnitKind::Infantry => 0.15,
                UnitKind::FieldGun => 0.06,
                UnitKind::Tank | UnitKind::Truck => 1.0,
            }
        } else {
            1.0
        };
        let fortified = board.depots.iter().any(|depot| {
            depot.kind == BuildingKind::Fortress
                && !depot.is_destroyed()
                && Some(depot.position) == target.board_position()
        });
        let fortification = if fortified { 0.25 } else { 1.0 };
        let damage = f64::from(rules(shooter.kind()).damage)
            * strength.powi(2)
            * matchup
            * readiness
            * facing
            * aim
            * cover
            * ambush
            * entrenchment;
        // Apply fortress cover to the bounded hit so even the heaviest weapon
        // cannot bypass the bonus by exceeding the ordinary maximum damage.
        let damage = damage.min(f64::from(target.hit_points().maximum())) * fortification;
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
        if !self.can_fire(shooter)
            || !target.is_alive()
            || shooter.player_number() == target.player_number()
            || !(in_line || in_cross_arm)
        {
            return None;
        }
        // Most pairs cannot engage. Avoid recomputing the entire army's sight
        // for them, especially during the AI's repeated candidate simulations.
        // Shared sightings enable ambush fire even through intervening terrain.
        let visible = visibility::visible_tiles(board, shooter.player_number());
        if !visibility::unit_observable(&board.map, &visible, target) {
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

    /// Spend one shot and face its landing, whether or not a target is present.
    fn fire(&mut self, board: &mut Scenario, launch: ShellLaunch) {
        self.fired.insert(launch.shooter);
        if let Some(unit) = board
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == launch.shooter)
        {
            unit.spend_supplies(rules(unit.kind()).shot_cost);
            if let Some(direction) = Direction::between(launch.origin, launch.destination) {
                unit.rotate(direction);
            }
        }
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
            self.fire(
                board,
                ShellLaunch {
                    shooter: engagement.shooter,
                    origin: engagement.shot.origin,
                    destination: engagement.shot.destination,
                },
            );
            *damage.entry(engagement.target).or_default() += engagement.shot.damage;
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
            sabotages: Vec::new(),
            departures: Vec::new(),
            indirect_impacts: Vec::new(),
            depots: board.depots.clone(),
            supply_crates: board.supply_crates.clone(),
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: 450,
            shots,
        });
        let has_bombardment = engagements
            .iter()
            .any(|engagement| engagement.shot.kind == CombatKind::IndirectFire);
        let casualty_pause = !dead_carriers.is_empty() || has_bombardment;
        // Clear shots while preserving enough time to read the exchange and death marker.
        frames.push(TurnFrame {
            sabotages: Vec::new(),
            departures: Vec::new(),
            indirect_impacts: Vec::new(),
            depots: board.depots.clone(),
            supply_crates: board.supply_crates.clone(),
            units: board.units.clone(),
            visible_tiles: Vec::new(),
            duration_ms: if casualty_pause { 1400 } else { 600 },
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

    /// An ambushing field gun gets the first shot when a tank contacts it or aims
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
            .filter(|gun| {
                gun.kind() == UnitKind::FieldGun && self.ambushers.contains(&gun.unit_id())
            })
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
                        let opposing_ambush = self.ambushers.contains(&tank.unit_id())
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
        // Resolving an allied traffic jam can retract a participant's movement.
        // Only contacts that remain physically adjacent can trigger direct fire
        // or a field gun's contact interception from the settled board positions.
        let adjacent_contacts: Vec<_> = contacts
            .iter()
            .copied()
            .filter(|(shooter_id, target_id)| {
                let position = |id| {
                    board
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == id)
                        .and_then(Unit::board_position)
                };
                match (position(*shooter_id), position(*target_id)) {
                    (Some(origin), Some(destination)) => {
                        (destination.x() - origin.x()).abs() + (destination.y() - origin.y()).abs()
                            == 1
                    }
                    _ => false,
                }
            })
            .collect();
        let interceptions = self.field_gun_interceptions(board, &adjacent_contacts);
        self.volley(board, &interceptions, frames);
        // Survivors may return fire with their reduced strength; other encounters
        // retain simultaneous resolution within their usual volley.
        let eligible: Vec<_> = board
            .units
            .iter()
            .filter(|unit| self.ambushers.contains(&unit.unit_id()))
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
            .ambushers
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
        for (shooter_id, target_id) in &adjacent_contacts {
            let shooter = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == *shooter_id);
            let target = board.units.iter().find(|unit| unit.unit_id() == *target_id);
            if let (Some(shooter), Some(target)) = (shooter, target)
                && self.can_fire(shooter)
                && target.is_alive()
                && shooter.player_number() != target.player_number()
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
        self.bombard(board, frames);
    }

    /// All surviving guns fire together after transport. Empty tiles still spend ammunition.
    fn bombard(&mut self, board: &mut Scenario, frames: &mut Vec<TurnFrame>) {
        let mut engagements = Vec::new();
        let mut misses = Vec::new();
        let mut impacts = Vec::new();
        for (id, destination) in &self.indirect_targets {
            let Some(shooter) = board
                .units
                .iter()
                .find(|unit| unit.unit_id() == *id && self.can_fire(unit))
            else {
                continue;
            };
            let Some(origin) = shooter.board_position() else {
                continue;
            };
            impacts.push(IndirectImpact {
                depot: None,
                attacker: Some(IndirectFireAttacker {
                    unit: theater_participant(shooter),
                    health: shooter.hit_points(),
                }),
                player_number: shooter.player_number(),
                destination: *destination,
                target: None,
            });
            if let Some(target) = board
                .units
                .iter()
                .find(|unit| unit.is_alive() && unit.board_position() == Some(*destination))
            {
                engagements.push(Engagement {
                    shooter: *id,
                    target: target.unit_id(),
                    shot: Shot {
                        kind: CombatKind::IndirectFire,
                        origin,
                        destination: *destination,
                        damage: self.damage(board, shooter, target, CombatKind::IndirectFire),
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
            } else {
                misses.push(ShellLaunch {
                    shooter: *id,
                    origin,
                    destination: *destination,
                });
            }
        }
        // A shell hits infrastructure independently of any unit sharing its tile.
        // Freight is deliberately unaffected, and a destroyed depot has no blast radius.
        for impact in &mut impacts {
            if let Some(depot) = board
                .depots
                .iter_mut()
                .find(|depot| depot.position == impact.destination && !depot.is_destroyed())
            {
                let before = depot.hit_points();
                depot.take_structural_hit();
                impact.depot = Some(BuildingImpact {
                    kind: depot.kind,
                    before,
                    after: depot.hit_points(),
                });
            }
        }
        for launch in &misses {
            self.fire(board, *launch);
        }
        let volley_frame = frames.len();
        self.volley(board, &engagements, frames);
        if engagements.is_empty() && !misses.is_empty() {
            frames.push(TurnFrame {
                sabotages: Vec::new(),
                departures: Vec::new(),
                indirect_impacts: Vec::new(),
                depots: board.depots.clone(),
                supply_crates: board.supply_crates.clone(),
                units: board.units.clone(),
                visible_tiles: Vec::new(),
                duration_ms: 450,
                shots: Vec::new(),
            });
            frames.push(TurnFrame {
                sabotages: Vec::new(),
                departures: Vec::new(),
                indirect_impacts: Vec::new(),
                depots: board.depots.clone(),
                supply_crates: board.supply_crates.clone(),
                units: board.units.clone(),
                visible_tiles: Vec::new(),
                duration_ms: 1400,
                shots: Vec::new(),
            });
        }
        if let Some(frame) = frames.get_mut(volley_frame) {
            for impact in &mut impacts {
                impact.target = frame
                    .shots
                    .iter()
                    .find(|shot| {
                        shot.destination == impact.destination
                            && impact.attacker.as_ref().is_some_and(|attacker| {
                                attacker.unit.unit_id() == shot.attacker.unit_id()
                            })
                    })
                    .map(|shot| IndirectFireTarget {
                        unit: shot.target.clone(),
                        health: shot.target_health,
                    });
            }
            frame.indirect_impacts = impacts;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::{Map, Terrain},
        movement_resolution,
        scenario::{Depot, PlayerNumber},
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
            .find(|unit| unit.player_number() == PlayerNumber::Player1 && unit.kind() == kind)
            .cloned()
            .fixture()?;
        let target = scenario
            .units
            .iter()
            .find(|unit| unit.player_number() == PlayerNumber::Player2 && unit.kind() == enemy_kind)
            .cloned()
            .fixture()?;
        scenario.units = vec![shooter, target];
        scenario.map = Map::new(9, 9, Terrain::Plain, BTreeMap::new()).fixture()?;
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
        for terrain in [Terrain::Plain, Terrain::Hills] {
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
    fn intact_fortresses_protect_each_occupant_from_every_attack_kind() -> TestResult<()> {
        for target_kind in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::FieldGun,
            UnitKind::Truck,
        ] {
            for attack in [
                CombatKind::Ambush,
                CombatKind::AttackMove,
                CombatKind::IndirectFire,
            ] {
                let position = Coordinate::new(4, 3);
                let (mut board, orders) = fixture(UnitKind::FieldGun, target_kind, position)?;
                board.depots.clear();
                let combat = Combat::prepare(&mut board, &orders);
                let damage = |board: &Scenario| -> TestResult<i32> {
                    Ok(combat.damage(
                        board,
                        board.units.first().fixture()?,
                        board.units.get(1).fixture()?,
                        attack,
                    ))
                };
                let exposed = damage(&board)?;
                board
                    .depots
                    .push(Depot::new(BuildingKind::Fortress, position));
                assert_eq!(damage(&board)?, 4, "{target_kind:?} {attack:?}");
                board.depots.first_mut().fixture()?.position = Coordinate::new(4, 4);
                assert_eq!(
                    damage(&board)?,
                    exposed,
                    "adjacent units receive no protection"
                );
                board.depots.first_mut().fixture()?.position = position;
                board.depots.first_mut().fixture()?.sabotage();
                assert_eq!(
                    damage(&board)?,
                    exposed,
                    "destroyed fortresses provide no protection"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn a_fortress_protects_during_its_last_shell_hit_but_not_the_next_volley() -> TestResult<()> {
        let position = Coordinate::new(4, 3);
        let (mut board, mut orders) = fixture(UnitKind::FieldGun, UnitKind::Infantry, position)?;
        board.depots = vec![Depot {
            damage: 7,
            ..Depot::new(BuildingKind::Fortress, position)
        }];
        orders.first_mut().fixture()?.facing = FacingOrder::IndirectFire(position);
        let mut frames = Vec::new();
        Combat::prepare(&mut board, &orders).bombard(&mut board, &mut frames);
        assert!(board.depots.first().fixture()?.is_destroyed());
        assert_eq!(board.units.get(1).fixture()?.hit_points().current(), 12);
        assert_eq!(
            frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .next()
                .fixture()?
                .damage,
            4
        );
        let impact = frames
            .iter()
            .flat_map(|frame| &frame.indirect_impacts)
            .next()
            .fixture()?
            .depot
            .as_ref()
            .fixture()?;
        assert_eq!(impact.before.current, 1);
        assert_eq!(impact.after.current, 0);
        frames.clear();
        Combat::prepare(&mut board, &orders).bombard(&mut board, &mut frames);
        assert_eq!(
            frames
                .iter()
                .flat_map(|frame| &frame.shots)
                .next()
                .fixture()?
                .damage,
            16
        );
        assert!(!board.units.get(1).fixture()?.is_alive());
        Ok(())
    }

    #[test]
    fn fortress_cover_stacks_with_entrenchment_and_keeps_the_minimum_hit() -> TestResult<()> {
        let position = Coordinate::new(4, 3);
        let (mut board, orders) = fixture(UnitKind::Infantry, UnitKind::Infantry, position)?;
        board.depots = vec![Depot::new(BuildingKind::Fortress, position)];
        let combat = Combat::prepare(&mut board, &orders);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            3
        );
        board.units.get_mut(1).fixture()?.dig_in();
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            1
        );
        board.depots.first_mut().fixture()?.sabotage();
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::Ambush
            ),
            2
        );
        Ok(())
    }

    #[test]
    fn infantry_matchup_rewards_attacks_on_unready_infantry() -> TestResult<()> {
        for (terrain, defense, health, expected) in [
            (Terrain::Plain, FacingOrder::Unchanged, 16, 11),
            (Terrain::Hills, FacingOrder::Unchanged, 16, 9),
            (Terrain::Forest, FacingOrder::Unchanged, 16, 9),
            (
                Terrain::Plain,
                FacingOrder::StandGround(Direction::West),
                16,
                7,
            ),
            (
                Terrain::Hills,
                FacingOrder::StandGround(Direction::West),
                16,
                6,
            ),
            (
                Terrain::Forest,
                FacingOrder::StandGround(Direction::West),
                16,
                6,
            ),
            (Terrain::Plain, FacingOrder::Unchanged, 8, 3),
            (
                Terrain::Plain,
                FacingOrder::StandGround(Direction::West),
                8,
                2,
            ),
        ] {
            let (mut board, mut orders) = fixture(
                UnitKind::Infantry,
                UnitKind::Infantry,
                Coordinate::new(4, 3),
            )?;
            board.map = Map::new(9, 9, terrain, BTreeMap::new()).fixture()?;
            board.units.first_mut().fixture()?.rotate(Direction::East);
            board.units.first_mut().fixture()?.take_damage(16 - health);
            board.units.get_mut(1).fixture()?.rotate(Direction::West);
            orders[0].facing = FacingOrder::Unchanged;
            orders[0].travel = TravelMode::AttackMove;
            orders[1].facing = defense;
            let attacker = board.units.first().fixture()?.unit_id();
            let defender = board.units.get(1).fixture()?.unit_id();
            let mut combat = Combat::prepare(&mut board, &orders);
            let mut frames = Vec::new();
            combat.engage_contacts(
                &mut board,
                &mut BTreeSet::new(),
                &mut frames,
                &[(attacker, defender)],
            );
            let shots: Vec<_> = frames.iter().flat_map(|frame| &frame.shots).collect();
            assert_eq!(shots.len(), 1);
            assert_eq!(shots.first().fixture()?.damage, expected);
            assert_eq!(
                board.units.get(1).fixture()?.hit_points().current(),
                16 - expected
            );
        }
        Ok(())
    }

    #[test]
    fn entrenchment_protects_against_infantry_and_both_gun_attacks_but_not_tanks() -> TestResult<()>
    {
        for (kind, combat_kind, expected) in [
            (UnitKind::Infantry, CombatKind::AttackMove, 1),
            (UnitKind::FieldGun, CombatKind::Ambush, 1),
            (UnitKind::FieldGun, CombatKind::IndirectFire, 1),
            (UnitKind::Tank, CombatKind::AttackMove, 16),
        ] {
            let (mut board, mut orders) = fixture(kind, UnitKind::Infantry, Coordinate::new(4, 3))?;
            board.units.get_mut(1).fixture()?.rotate(Direction::West);
            board.units.get_mut(1).fixture()?.dig_in();
            orders.get_mut(1).fixture()?.facing = FacingOrder::StandGround(Direction::West);
            let combat = Combat::prepare(&mut board, &orders);
            assert_eq!(
                combat.damage(
                    &board,
                    board.units.first().fixture()?,
                    board.units.get(1).fixture()?,
                    combat_kind
                ),
                expected
            );
        }
        Ok(())
    }

    #[test]
    fn entrenched_infantry_win_a_comparable_infantry_exchange() -> TestResult<()> {
        let (mut board, mut orders) = fixture(
            UnitKind::Infantry,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        board.units.first_mut().fixture()?.rotate(Direction::East);
        board.units.get_mut(1).fixture()?.dig_in();
        orders.get_mut(1).fixture()?.facing = FacingOrder::Ambush(Direction::West);
        let resolved = resolve_completed_movement(&board, &orders, 1)?;
        let units = &resolved.frames.last().fixture()?.units;
        assert_eq!(units.first().fixture()?.hit_points().current(), 9);
        assert_eq!(units.get(1).fixture()?.hit_points().current(), 15);
        Ok(())
    }

    #[test]
    fn only_successfully_traveled_movement_removes_entrenchment() -> TestResult<()> {
        let (mut board, mut orders) = fixture(
            UnitKind::Infantry,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        board.units.first_mut().fixture()?.dig_in();
        let id = board.units.first().fixture()?.unit_id();
        orders.first_mut().fixture()?.facing = FacingOrder::Unchanged;
        orders
            .first_mut()
            .fixture()?
            .path
            .push(Coordinate::new(4, 3));
        let blocked = movement_resolution::resolve(&board, &orders, 1)?;
        assert!(blocked.stopped.contains(&id));
        assert_eq!(
            blocked
                .frames
                .last()
                .fixture()?
                .units
                .iter()
                .find(|unit| unit.unit_id() == id)
                .fixture()?
                .entrenchment(),
            Entrenchment::Entrenched
        );
        orders.first_mut().fixture()?.path = vec![Coordinate::new(3, 3), Coordinate::new(3, 4)];
        let moved = movement_resolution::resolve(&board, &orders, 1)?;
        assert_eq!(
            moved
                .frames
                .last()
                .fixture()?
                .units
                .iter()
                .find(|unit| unit.unit_id() == id)
                .fixture()?
                .entrenchment(),
            Entrenchment::Exposed
        );
        Ok(())
    }

    #[test]
    fn digging_in_is_vulnerable_and_never_initiates_fire() -> TestResult<()> {
        let (mut board, mut orders) = fixture(
            UnitKind::Infantry,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        orders.get_mut(1).fixture()?.facing = FacingOrder::DigIn;
        let mut combat = Combat::prepare(&mut board, &orders);
        assert_eq!(
            board.units.get(1).fixture()?.entrenchment(),
            Entrenchment::Exposed
        );
        assert_eq!(board.units.get(1).fixture()?.supplies().current(), 176);
        assert_eq!(
            combat.damage(
                &board,
                board.units.first().fixture()?,
                board.units.get(1).fixture()?,
                CombatKind::AttackMove
            ),
            11
        );
        let mut frames = Vec::new();
        combat.finish(&mut board, &mut BTreeSet::new(), &mut frames);
        assert!(!combat.has_fired_directly(board.units.get(1).fixture()?.unit_id()));
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
        board.map = Map::new(9, 9, Terrain::Plain, BTreeMap::new()).fixture()?;
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
        board.map = Map::new(9, 9, Terrain::Plain, BTreeMap::new()).fixture()?;
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
    fn stationary_gun_return_fire_can_share_a_volley_with_an_unrelated_exchange() -> TestResult<()>
    {
        let (mut board, mut orders) =
            fixture(UnitKind::FieldGun, UnitKind::Tank, Coordinate::new(4, 3))?;
        board.units.first_mut().fixture()?.take_damage(8);
        orders.get_mut(1).fixture()?.facing = FacingOrder::Ambush(Direction::West);
        let (other, mut other_orders) = fixture(
            UnitKind::Infantry,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        other_orders.get_mut(1).fixture()?.facing = FacingOrder::Ambush(Direction::West);
        for ((mut unit, mut order), position) in other
            .units
            .into_iter()
            .zip(other_orders)
            .zip([Coordinate::new(3, 6), Coordinate::new(4, 6)])
        {
            unit.move_to(position);
            order.path = vec![position];
            board.units.push(unit);
            orders.push(order);
        }
        let result = resolve_completed_movement(&board, &orders, 1)?;
        let volleys: Vec<_> = result
            .frames
            .iter()
            .filter(|frame| !frame.shots.is_empty())
            .collect();
        assert_eq!(volleys.len(), 2);
        let opening = volleys.first().fixture()?;
        let returning = volleys.get(1).fixture()?;
        assert_eq!(opening.shots.len(), 1);
        assert_eq!(returning.shots.len(), 3);
        let gun_shot = opening.shots.first().fixture()?;
        let tank_shot = returning
            .shots
            .iter()
            .find(|shot| shot.attacker.kind() == UnitKind::Tank)
            .fixture()?;
        assert_eq!(gun_shot.damage, 5);
        assert_eq!(tank_shot.attacker_health.before.current(), 11);
        assert_eq!(tank_shot.damage, 11);
        assert_eq!(tank_shot.target_health.after.current(), 0);
        for unit in &returning.units {
            let initial = board
                .units
                .iter()
                .find(|initial| initial.unit_id() == unit.unit_id())
                .fixture()?;
            assert_eq!(unit.board_position(), initial.board_position());
            assert_eq!(
                unit.supplies().current(),
                initial.supplies().current()
                    - rules(unit.kind()).readiness_cost
                    - rules(unit.kind()).shot_cost
            );
        }
        for shot in shots(&result) {
            assert!(shot.attacker.resources().is_none());
            assert!(shot.target.resources().is_none());
        }
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
    fn stale_attack_contacts_require_cardinal_adjacency_before_interception() -> TestResult<()> {
        for defender in [UnitKind::Infantry, UnitKind::FieldGun] {
            for position in [Coordinate::new(5, 3), Coordinate::new(4, 4)] {
                let (mut board, mut orders) = fixture(defender, UnitKind::Tank, position)?;
                orders.first_mut().fixture()?.facing = FacingOrder::Ambush(Direction::East);
                orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
                let tank_id = board.units.get(1).fixture()?.unit_id();
                let defender_id = board.units.first().fixture()?.unit_id();
                let mut combat = Combat::prepare(&mut board, &orders);
                let prepared = board.units.clone();
                let mut frames = Vec::new();
                combat.engage_contacts(
                    &mut board,
                    &mut BTreeSet::new(),
                    &mut frames,
                    &[(tank_id, defender_id)],
                );
                assert!(frames.iter().all(|frame| frame.shots.is_empty()));
                assert_eq!(board.units, prepared);
            }
        }
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
        assert_eq!(shots.get(1).fixture()?.damage, 11);
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
    fn infantry_contact_damage_against_field_guns_ignores_defensive_readiness() -> TestResult<()> {
        for terrain in [Terrain::Plain, Terrain::Hills, Terrain::Forest] {
            for defense in [
                FacingOrder::Unchanged,
                FacingOrder::StandGround(Direction::West),
                FacingOrder::Ambush(Direction::West),
            ] {
                let (mut board, mut orders) = fixture(
                    UnitKind::Infantry,
                    UnitKind::FieldGun,
                    Coordinate::new(4, 3),
                )?;
                board.map = Map::new(9, 9, terrain, BTreeMap::new()).fixture()?;
                board.units.first_mut().fixture()?.rotate(Direction::East);
                board.units.get_mut(1).fixture()?.rotate(Direction::West);
                orders[0].facing = FacingOrder::Unchanged;
                orders[0].travel = TravelMode::AttackMove;
                orders[1].facing = defense;
                let mut combat = Combat::prepare(&mut board, &orders);
                let infantry_id = board.units.first().fixture()?.unit_id();
                let gun_id = board.units.get(1).fixture()?.unit_id();
                let mut frames = Vec::new();
                combat.engage_contacts(
                    &mut board,
                    &mut BTreeSet::new(),
                    &mut frames,
                    &[(infantry_id, gun_id)],
                );
                let hit = frames
                    .iter()
                    .flat_map(|frame| &frame.shots)
                    .find(|shot| shot.attacker.unit_id() == infantry_id)
                    .fixture()?;
                let expected = if terrain == Terrain::Plain { 16 } else { 15 };
                assert_eq!(hit.damage, expected);
                assert_eq!(hit.target_health.after.current(), 16 - expected);
                assert_eq!(board.units.get(1).fixture()?.is_alive(), expected < 16);
            }
        }
        Ok(())
    }

    #[test]
    fn field_gun_preparation_never_reduces_incoming_damage_from_any_direction() -> TestResult<()> {
        for facing in [Direction::West, Direction::North, Direction::East] {
            for defense in [
                FacingOrder::Unchanged,
                FacingOrder::StandGround(facing),
                FacingOrder::Ambush(facing),
                FacingOrder::IndirectFire(Coordinate::new(3, 3)),
            ] {
                let (mut board, mut orders) = fixture(
                    UnitKind::Infantry,
                    UnitKind::FieldGun,
                    Coordinate::new(4, 3),
                )?;
                board.units.first_mut().fixture()?.take_damage(8);
                board.units.get_mut(1).fixture()?.rotate(facing);
                orders[1].facing = defense;
                let combat = Combat::prepare(&mut board, &orders);
                // Below the damage cap so a defensive reduction cannot be hidden.
                assert_eq!(
                    combat.damage(
                        &board,
                        board.units.first().fixture()?,
                        board.units.get(1).fixture()?,
                        CombatKind::AttackMove,
                    ),
                    5
                );
            }
        }
        Ok(())
    }

    #[test]
    fn infantry_field_gun_damage_table_includes_health_and_cover() -> TestResult<()> {
        for (health, open_damage, covered_damage) in [
            (16, 16, 15),
            (15, 16, 13),
            (14, 14, 12),
            (13, 12, 10),
            (12, 10, 9),
            (11, 9, 7),
            (10, 7, 6),
            (9, 6, 5),
            (8, 5, 4),
            (7, 3, 3),
            (6, 3, 2),
            (5, 2, 1),
            (4, 1, 1),
            (3, 1, 1),
            (2, 1, 1),
            (1, 1, 1),
        ] {
            for (terrain, expected) in [
                (Terrain::Plain, open_damage),
                (Terrain::Hills, covered_damage),
                (Terrain::Forest, covered_damage),
            ] {
                let (mut board, mut orders) = fixture(
                    UnitKind::Infantry,
                    UnitKind::FieldGun,
                    Coordinate::new(4, 3),
                )?;
                board.map = Map::new(9, 9, terrain, BTreeMap::new()).fixture()?;
                board.units.first_mut().fixture()?.take_damage(16 - health);
                orders[1].facing = FacingOrder::Ambush(Direction::West);
                let combat = Combat::prepare(&mut board, &orders);
                for kind in [CombatKind::Ambush, CombatKind::AttackMove] {
                    assert_eq!(
                        combat.damage(
                            &board,
                            board.units.first().fixture()?,
                            board.units.get(1).fixture()?,
                            kind,
                        ),
                        expected
                    );
                }
            }
        }
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
        combat
            .ambushers
            .insert(board.units.get(1).fixture()?.unit_id());
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
            .ambushers
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
                Terrain::Plain,
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
    fn infantry_ambushes_hurt_ready_tanks_only_from_the_flank_or_rear() -> TestResult<()> {
        for (travel, facing) in [
            (TravelMode::AttackMove, FacingOrder::Unchanged),
            (TravelMode::Normal, FacingOrder::Ambush(Direction::West)),
            (
                TravelMode::Normal,
                FacingOrder::StandGround(Direction::West),
            ),
        ] {
            let (mut board, mut orders) =
                fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
            let tank_order = orders.get_mut(1).fixture()?;
            tank_order.travel = travel;
            tank_order.facing = facing;
            let combat = Combat::prepare(&mut board, &orders);
            for (direction, ambush_damage, contact_damage) in [
                (Direction::West, 1, 1),
                (Direction::North, 6, 1),
                (Direction::East, 8, 2),
            ] {
                board.units.get_mut(1).fixture()?.rotate(direction);
                let infantry = board.units.first().fixture()?;
                let tank = board.units.get(1).fixture()?;
                assert_eq!(
                    combat.damage(&board, infantry, tank, CombatKind::Ambush),
                    ambush_damage
                );
                assert_eq!(
                    combat.damage(&board, infantry, tank, CombatKind::AttackMove),
                    contact_damage
                );
            }
        }
        Ok(())
    }

    #[test]
    fn infantry_flank_ambushes_retain_cover_health_and_readiness_factors() -> TestResult<()> {
        for (terrain, health_loss, expected) in [
            (Terrain::Plain, 0, 6),
            (Terrain::Hills, 0, 5),
            (Terrain::Forest, 0, 5),
            (Terrain::Plain, 8, 2),
        ] {
            let (mut board, mut orders) =
                fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
            orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
            board.map = Map::new(9, 9, terrain, BTreeMap::new()).fixture()?;
            board.units.first_mut().fixture()?.take_damage(health_loss);
            let mut combat = Combat::prepare(&mut board, &orders);
            board.units.get_mut(1).fixture()?.rotate(Direction::North);
            let infantry = board.units.first().fixture()?;
            let tank = board.units.get(1).fixture()?;
            assert_eq!(
                combat.damage(&board, infantry, tank, CombatKind::Ambush),
                expected
            );
            // Spending its shot does not remove an attack mover's defensive readiness.
            combat.fired.insert(tank.unit_id());
            assert_eq!(
                combat.damage(&board, infantry, tank, CombatKind::Ambush),
                expected
            );
        }

        let (mut board, mut orders) =
            fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 3))?;
        orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
        let combat = Combat::prepare(&mut board, &orders);
        let tank = board.units.get_mut(1).fixture()?;
        tank.rotate(Direction::North);
        let firing_supplies = tank.supplies().current() - tank.supplies().upkeep_per_turn();
        tank.spend_supplies(firing_supplies);
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
        board.units.get_mut(1).fixture()?.spend_supplies(124);
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
                (Coordinate::new(5, 3), kind != UnitKind::Infantry),
                (Coordinate::new(6, 3), kind == UnitKind::FieldGun),
                (Coordinate::new(7, 3), false),
                (Coordinate::new(5, 2), kind == UnitKind::FieldGun),
                (Coordinate::new(5, 4), kind == UnitKind::FieldGun),
                (Coordinate::new(6, 4), false),
                (Coordinate::new(3, 4), false),
                (Coordinate::new(2, 3), false),
                (Coordinate::new(4, 4), false),
            ] {
                let (mut scenario, orders) = fixture(kind, UnitKind::Truck, position)?;
                if kind == UnitKind::Tank {
                    // An allied observer supplies sight beyond a tank's own one-tile radius.
                    let mut observer = Scenario::supply_point()
                        .fixture()?
                        .units
                        .into_iter()
                        .find(|unit| {
                            unit.kind() == UnitKind::Infantry
                                && unit.player_number() == PlayerNumber::Player1
                        })
                        .fixture()?;
                    observer.move_to(Coordinate::new(3, 2));
                    scenario.units.push(observer);
                }
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
                unit.player_number() == PlayerNumber::Player2
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
        assert_eq!(units[1].hit_points().current(), 5);
        assert_eq!(units[0].supplies().current(), 172);
        assert_eq!(units[1].supplies().current(), 183);
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
    fn infantry_flank_ambush_damages_a_passing_tank_without_return_fire() -> TestResult<()> {
        let (scenario, mut orders) =
            fixture(UnitKind::Infantry, UnitKind::Tank, Coordinate::new(4, 2))?;
        let tank_order = orders.get_mut(1).fixture()?;
        tank_order.travel = TravelMode::AttackMove;
        tank_order
            .path
            .extend([Coordinate::new(4, 3), Coordinate::new(4, 4)]);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        let hits = shots(&result);
        assert_eq!(hits.len(), 1);
        let hit = hits.first().fixture()?;
        assert_eq!(hit.kind, CombatKind::Ambush);
        assert_eq!(hit.damage, 6);
        let units = &result.frames.last().fixture()?.units;
        let infantry = units.first().fixture()?;
        let tank = units.get(1).fixture()?;
        assert_eq!(infantry.hit_points().current(), 16);
        assert_eq!(tank.hit_points().current(), 10);
        assert_eq!(tank.board_position(), Some(Coordinate::new(4, 4)));
        assert!(!result.stopped.contains(&tank.unit_id()));
        assert_eq!(
            result.paths.get(&tank.unit_id()).fixture()?,
            &orders.get(1).fixture()?.path
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
                if survived { 114 } else { 121 }
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
                unit.player_number() == PlayerNumber::Player1
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
        assert_eq!(mover.supplies().current(), 104);
        assert_eq!(mover.fuel().fixture()?.current, 114);
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
        assert_eq!(units[0].supplies().current(), 104);
        assert_eq!(
            units[1].supplies().current(),
            scenario.units[1].supplies().current()
        );
        assert_eq!(units[1].direction(), Some(Direction::South));
        assert_eq!(units[1].fuel().fixture()?.current, 121);
        assert_eq!(
            result.paths.get(&orders[1].unit_id).fixture()?,
            &vec![Coordinate::new(4, 2), Coordinate::new(4, 3)]
        );
        Ok(())
    }

    #[test]
    fn stand_ground_pays_readiness_without_initiating_combat() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            let (mut board, mut orders) = fixture(kind, UnitKind::Tank, Coordinate::new(4, 3))?;
            orders[0].facing = crate::turns::FacingOrder::StandGround(Direction::East);
            board.units[0].rotate(Direction::South);
            let supplies = board.units[0].supplies().current();
            let mut combat = Combat::prepare(&mut board, &orders);
            let mut frames = Vec::new();
            combat.engage(&mut board, &mut BTreeSet::new(), &mut frames);
            combat.finish(&mut board, &mut BTreeSet::new(), &mut frames);
            assert!(frames.iter().all(|frame| frame.shots.is_empty()));
            assert_eq!(
                board.units[0].supplies().current(),
                supplies - rules(kind).readiness_cost
            );
            assert_eq!(board.units[0].direction(), Some(Direction::East));
        }
        Ok(())
    }

    #[test]
    fn stand_ground_defends_like_ambush_without_return_fire_or_interception() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            for enemy_kind in [UnitKind::Infantry, UnitKind::Tank] {
                let (mut board, mut orders) = fixture(kind, enemy_kind, Coordinate::new(4, 3))?;
                board.units[0].rotate(Direction::East);
                board.units[1].rotate(Direction::West);
                orders[0].facing = crate::turns::FacingOrder::StandGround(Direction::East);
                orders[1].travel = TravelMode::AttackMove;
                let mut prepared = board.clone();
                let combat = Combat::prepare(&mut prepared, &orders);
                let damage = combat.damage(
                    &prepared,
                    &prepared.units[1],
                    &prepared.units[0],
                    CombatKind::AttackMove,
                );
                let mut ambush_board = board.clone();
                orders[0].facing = crate::turns::FacingOrder::Ambush(Direction::East);
                let ambush = Combat::prepare(&mut ambush_board, &orders);
                assert_eq!(
                    damage,
                    ambush.damage(
                        &ambush_board,
                        &ambush_board.units[1],
                        &ambush_board.units[0],
                        CombatKind::AttackMove
                    )
                );
                orders[0].facing = crate::turns::FacingOrder::StandGround(Direction::East);
                let defender_supplies = board.units[0].supplies().current();
                let defender_id = board.units[0].unit_id();
                let attacker_id = board.units[1].unit_id();
                let mut combat = Combat::prepare(&mut board, &orders);
                let mut frames = Vec::new();
                combat.engage_contacts(
                    &mut board,
                    &mut BTreeSet::new(),
                    &mut frames,
                    &[(attacker_id, defender_id)],
                );
                combat.finish(&mut board, &mut BTreeSet::new(), &mut frames);
                let shots: Vec<_> = frames.iter().flat_map(|frame| &frame.shots).collect();
                assert_eq!(shots.len(), 1);
                assert_eq!(shots[0].kind, CombatKind::AttackMove);
                assert_eq!(shots[0].damage, damage);
                assert_eq!(
                    board.units[0].supplies().current(),
                    defender_supplies - rules(kind).readiness_cost
                );
                assert_eq!(board.units[1].hit_points().current(), 16);
            }
        }
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
                unit.player_number() == PlayerNumber::Player1
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
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let resolution = crate::turns::TurnResolution {
                reports: Vec::new(),
                turn_number: 1,
                events: Vec::new(),
                frames: result.frames.clone(),
            };
            let visible = visibility::visible_tiles(&scenario, player_number);
            let observed =
                visibility::observed_resolution(&scenario, player_number, &visible, &resolution);
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
    fn attack_movers_show_their_simultaneous_shot_before_another_pair_kills_them() -> TestResult<()>
    {
        let (mut scenario, mut orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::Infantry,
            Coordinate::new(4, 4),
        )?;
        let mut defender = Scenario::el_alamein()
            .fixture()?
            .units
            .into_iter()
            .find(|unit| {
                unit.player_number() == PlayerNumber::Player1 && unit.kind() == UnitKind::Infantry
            })
            .fixture()?;
        defender.move_to(Coordinate::new(5, 3));
        let defender_id = defender.unit_id();
        let attacker_id = scenario.units.get(1).fixture()?.unit_id();
        orders.get_mut(1).fixture()?.travel = TravelMode::AttackMove;
        orders.push(MoveOrder {
            unit_id: defender_id,
            path: vec![Coordinate::new(5, 3)],
            travel: TravelMode::Normal,
            facing: FacingOrder::Unchanged,
            supply: crate::supplies::SupplyOrder::default(),
            unloads: Vec::new(),
        });
        scenario.units.push(defender);
        let mut combat = Combat::prepare(&mut scenario, &orders);
        scenario
            .units
            .get_mut(1)
            .fixture()?
            .move_to(Coordinate::new(4, 3));
        let before = scenario.clone();
        let mut frames = Vec::new();
        combat.engage_contacts(
            &mut scenario,
            &mut BTreeSet::new(),
            &mut frames,
            &[(attacker_id, defender_id)],
        );
        let volley = frames.first().fixture()?;
        assert_eq!(volley.shots.len(), 2);
        let attack = volley
            .shots
            .iter()
            .find(|shot| shot.kind == CombatKind::AttackMove)
            .fixture()?;
        assert_eq!(attack.attacker_health.before.current(), 16);
        assert_eq!(attack.attacker_health.after.current(), 16);
        assert!(attack.target_health.after.current() < attack.target_health.before.current());
        assert_eq!(
            volley.shots.first().fixture()?.attacker.unit_id(),
            attacker_id
        );
        assert_eq!(
            volley.shots.get(1).fixture()?.target_health.after.current(),
            0
        );
        assert!(
            !scenario
                .units
                .iter()
                .find(|unit| unit.unit_id() == attacker_id)
                .fixture()?
                .is_alive()
        );
        for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let resolution = crate::turns::TurnResolution {
                reports: Vec::new(),
                turn_number: 1,
                events: Vec::new(),
                frames: frames.clone(),
            };
            let projected = visibility::observed_resolution(
                &before,
                player,
                &visibility::visible_tiles(&before, player),
                &resolution,
            );
            let shot = projected
                .frames
                .first()
                .fixture()?
                .shots
                .first()
                .fixture()?;
            assert_eq!(shot.kind, CombatKind::AttackMove);
            assert_eq!(shot.attacker_health.before.current(), 16);
            assert!(shot.attacker.resources().is_none());
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
            reports: Vec::new(),
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let visible = visibility::visible_tiles(&scenario, player_number);
            let observed =
                visibility::observed_resolution(&scenario, player_number, &visible, &resolution);
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
            Terrain::Plain,
            BTreeMap::from([(Coordinate::new(3, 3), Terrain::Forest)]),
        )
        .fixture()?;
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        let resolution = crate::turns::TurnResolution {
            reports: Vec::new(),
            turn_number: 1,
            events: Vec::new(),
            frames: result.frames,
        };
        let player_number = PlayerNumber::Player2;
        let visible = visibility::visible_tiles(&scenario, player_number);
        let observed =
            visibility::observed_resolution(&scenario, player_number, &visible, &resolution);
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
        let player_number = PlayerNumber::Player1;
        let visible = visibility::visible_tiles(&scenario, player_number);
        let observed =
            visibility::observed_resolution(&scenario, player_number, &visible, &resolution);
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
        scenario.units[0].spend_supplies(176);
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        assert!(shots(&result).is_empty());
        assert_eq!(
            result.frames.last().fixture()?.units[0]
                .supplies()
                .current(),
            12
        );
        let (mut scenario, orders) =
            fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(4, 3))?;
        let mut combat = Combat::prepare(&mut scenario, &orders);
        let mut frames = Vec::new();
        let mut stopped = BTreeSet::new();
        combat.finish(&mut scenario, &mut stopped, &mut frames);
        combat.engage(&mut scenario, &mut stopped, &mut frames);
        assert_eq!(frames.iter().flat_map(|frame| &frame.shots).count(), 1);
        assert_eq!(scenario.units[0].supplies().current(), 168);
        Ok(())
    }

    #[test]
    fn ambushes_hit_revealed_forest_targets_that_stay_in_the_area() -> TestResult<()> {
        for kind in [UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun] {
            for revealed in [false, true] {
                for attack_move in [false, true] {
                    let (mut scenario, mut orders) =
                        fixture(kind, UnitKind::Infantry, Coordinate::new(4, 3))?;
                    scenario.map = Map::new(9, 9, Terrain::Forest, BTreeMap::new()).fixture()?;
                    scenario
                        .units
                        .get_mut(1)
                        .fixture()?
                        .finish_firing_reveal(revealed);
                    if attack_move {
                        let infantry = orders.get_mut(1).fixture()?;
                        infantry.travel = TravelMode::AttackMove;
                        infantry.path.push(Coordinate::new(3, 3));
                    }
                    let result = resolve_completed_movement(&scenario, &orders, 1)?;
                    let shooter_id = scenario.units.first().fixture()?.unit_id();
                    let hits: Vec<_> = shots(&result)
                        .into_iter()
                        .filter(|shot| shot.attacker.unit_id() == shooter_id)
                        .collect();
                    assert_eq!(hits.len(), usize::from(revealed));
                    if revealed {
                        let hit = hits.first().fixture()?;
                        assert_eq!(hit.kind, CombatKind::Ambush);
                        assert_eq!(hit.destination, Coordinate::new(4, 3));
                        assert!(
                            hit.target_health.after.current() < hit.target_health.before.current()
                        );
                    }
                    // Enemy contact stops the attack move on its original square.
                    let infantry_id = scenario.units.get(1).fixture()?.unit_id();
                    assert_eq!(
                        result.paths.get(&infantry_id).fixture()?,
                        &vec![Coordinate::new(4, 3)]
                    );
                }
            }
        }
        Ok(())
    }

    #[test]
    fn revealed_forest_targets_can_escape_an_initial_ambush_area() -> TestResult<()> {
        let (mut scenario, mut orders) = fixture(
            UnitKind::FieldGun,
            UnitKind::Infantry,
            Coordinate::new(4, 3),
        )?;
        scenario.map = Map::new(9, 9, Terrain::Forest, BTreeMap::new()).fixture()?;
        scenario
            .units
            .get_mut(1)
            .fixture()?
            .finish_firing_reveal(true);
        orders
            .get_mut(1)
            .fixture()?
            .path
            .push(Coordinate::new(4, 4));
        let result = resolve_completed_movement(&scenario, &orders, 1)?;
        assert!(shots(&result).is_empty());
        assert_eq!(
            result
                .frames
                .last()
                .fixture()?
                .units
                .get(1)
                .fixture()?
                .board_position(),
            Some(Coordinate::new(4, 4))
        );
        Ok(())
    }

    #[test]
    fn firing_reveals_enable_ambushes_through_intervening_terrain() -> TestResult<()> {
        for terrain in [Terrain::Forest, Terrain::Hills, Terrain::Mountains] {
            let (mut scenario, orders) = fixture(
                UnitKind::FieldGun,
                UnitKind::Infantry,
                Coordinate::new(6, 3),
            )?;
            scenario.map = Map::new(
                9,
                9,
                Terrain::Plain,
                BTreeMap::from([(Coordinate::new(5, 3), terrain)]),
            )
            .fixture()?;
            scenario
                .units
                .get_mut(1)
                .fixture()?
                .finish_firing_reveal(true);
            let result = resolve_completed_movement(&scenario, &orders, 1)?;
            assert_eq!(shots(&result).len(), 1);
        }
        Ok(())
    }

    #[test]
    fn allied_sight_enables_ambushes_through_intervening_terrain() -> TestResult<()> {
        for kind in [UnitKind::Tank, UnitKind::FieldGun] {
            let targets = if kind == UnitKind::FieldGun {
                vec![Coordinate::new(5, 3), Coordinate::new(5, 2)]
            } else {
                vec![Coordinate::new(5, 3)]
            };
            for target in targets {
                for terrain in [Terrain::Forest, Terrain::Hills, Terrain::Mountains] {
                    for spotted in [false, true] {
                        let (mut scenario, orders) = fixture(kind, UnitKind::FieldGun, target)?;
                        scenario.map = Map::new(
                            9,
                            9,
                            Terrain::Plain,
                            BTreeMap::from([(Coordinate::new(4, 3), terrain)]),
                        )
                        .fixture()?;
                        if spotted {
                            let mut observer = Scenario::supply_point()
                                .fixture()?
                                .units
                                .into_iter()
                                .find(|unit| {
                                    unit.kind() == UnitKind::Truck
                                        && unit.player_number() == PlayerNumber::Player1
                                })
                                .fixture()?;
                            observer.move_to(Coordinate::new(6, target.y() as u16));
                            scenario.units.push(observer);
                        }
                        let result = resolve_completed_movement(&scenario, &orders, 1)?;
                        let hits = shots(&result);
                        assert_eq!(
                            hits.len(),
                            usize::from(spotted),
                            "{kind:?}, {target:?}, {terrain:?}, spotted={spotted}"
                        );
                        if spotted {
                            let hit = hits.first().fixture()?;
                            assert_eq!(hit.kind, CombatKind::Ambush);
                            assert_eq!(hit.destination, target);
                            assert!(
                                hit.target_health.after.current()
                                    < hit.target_health.before.current()
                            );
                        }
                    }
                }
            }
        }
        Ok(())
    }

    #[test]
    fn unseen_targets_do_not_trigger_ambushes() -> TestResult<()> {
        for terrain in [Terrain::Forest, Terrain::Hills, Terrain::Mountains] {
            let (mut scenario, orders) =
                fixture(UnitKind::FieldGun, UnitKind::Truck, Coordinate::new(6, 3))?;
            scenario.map = Map::new(
                9,
                9,
                Terrain::Plain,
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
            Terrain::Plain,
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
            .find(|unit| {
                unit.player_number() == PlayerNumber::Player2 && unit.kind() == UnitKind::Infantry
            })
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
