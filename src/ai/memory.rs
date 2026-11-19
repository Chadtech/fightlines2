//! Last observed enemy positions and depot stock. Only projected frames may enter the tracker.
use super::{distance, facing};
use crate::{
    map::{Coordinate, Terrain},
    player_number::PlayerNumber,
    scenario::{Direction, Scenario, Unit, UnitId, UnitKind},
    supplies::ResourceStock,
    turns::{TurnFrame, UnitOrderInput},
};
use std::collections::{BTreeMap, BTreeSet};

const MAX_AGE: i32 = 8;

#[derive(Clone, Copy)]
pub(super) struct ContactPolicy {
    pub horizon: i32,
    pub weight: i64,
    pub preference: fn(&ContactOrderFacts) -> i64,
}

#[derive(Clone, Copy)]
struct Sighting {
    position: Coordinate,
    kind: UnitKind,
    turn: i32,
}

struct DepotSighting {
    stock: ResourceStock,
    damage: i32,
}

#[derive(Default)]
pub(crate) struct EnemyMemory {
    sightings: BTreeMap<UnitId, Sighting>,
    depots: BTreeMap<Coordinate, DepotSighting>,
}

impl EnemyMemory {
    pub(crate) fn observe(&mut self, player: PlayerNumber, turn: i32, frames: &[TurnFrame]) {
        self.sightings
            .retain(|_, sighting| turn - sighting.turn < MAX_AGE);
        let mut confirmed_losses = BTreeSet::new();
        for frame in frames {
            for depot in frame.buildings.iter().filter(|building| {
                building.stock_visible && building.kind.resource_kind().is_some()
            }) {
                self.depots.insert(
                    depot.position,
                    DepotSighting {
                        stock: depot.stock.clone(),
                        damage: depot.damage,
                    },
                );
            }
            for loss in &frame.losses {
                let id = loss.unit().unit_id();
                confirmed_losses.insert(id);
                self.sightings.remove(&id);
            }
            for enemy in frame
                .units
                .iter()
                .filter(|unit| unit.player_number() != player)
            {
                if !confirmed_losses.contains(&enemy.unit_id())
                    && let Some(position) = enemy.board_position()
                {
                    self.sightings.insert(
                        enemy.unit_id(),
                        Sighting {
                            position,
                            kind: enemy.kind(),
                            turn,
                        },
                    );
                }
            }
        }
    }

    /// Mark last-seen empty depots on the forecast board. Current sightings
    /// take precedence, and other hidden depots keep their default stock.
    pub(super) fn apply_empty_depots(&self, observed: &mut Scenario) {
        for depot in observed
            .buildings
            .iter_mut()
            .filter(|depot| !depot.stock_visible && depot.kind.resource_kind().is_some())
        {
            if let Some(seen) = self.depots.get(&depot.position)
                && seen.stock.current == 0
            {
                depot.stock = seen.stock.clone();
                depot.stock_visible = true;
                depot.damage = seen.damage;
            }
        }
    }

    pub(super) fn contacts(
        &self,
        observed: &Scenario,
        turn: i32,
        policy: ContactPolicy,
    ) -> Vec<Contact> {
        let horizon = policy.horizon;
        self.sightings
            .iter()
            .filter_map(|(id, sighting)| {
                let age = turn - sighting.turn;
                if age < 1
                    || age > horizon
                    || sighting.kind == UnitKind::Truck
                    || observed.units.iter().any(|unit| unit.unit_id() == *id)
                {
                    return None;
                }
                Some(Contact {
                    position: sighting.position,
                    strength: policy.weight * i64::from(horizon + 1 - age) / i64::from(horizon),
                    age,
                    preference: policy.preference,
                })
            })
            .collect()
    }
}

#[derive(Clone, Copy)]
pub(super) struct Contact {
    pub position: Coordinate,
    strength: i64,
    age: i32,
    preference: fn(&ContactOrderFacts) -> i64,
}

impl Contact {
    pub fn near(contacts: &[Self], unit: &Unit, origin: Coordinate) -> Option<Self> {
        if unit.kind() == UnitKind::Truck {
            return None;
        }
        contacts
            .iter()
            .copied()
            .filter(|contact| distance(origin, contact.position) <= 6)
            .min_by_key(|contact| {
                (
                    distance(origin, contact.position),
                    -contact.strength,
                    contact.position,
                )
            })
    }

    pub fn watches(self, origin: Coordinate, direction: Direction) -> bool {
        (1..=4).contains(&distance(origin, self.position))
            && facing(origin, self.position) == direction
    }

    pub fn readiness(self, order: &UnitOrderInput) -> i64 {
        if order.attack_move != Some(true) {
            return 0;
        }
        let near = order.path.iter().skip(1).any(|tile| {
            distance(Coordinate::new(tile.x as u16, tile.y as u16), self.position) <= 2
        });
        self.strength * i64::from(near)
    }
}

pub(super) struct ContactOrderFacts {
    pub(super) age: i32,
    pub(super) distance_before: i32,
    pub(super) distance_after: i32,
    pub(super) progress: i32,
    pub(super) cover_after: bool,
    pub(super) attack_move: bool,
    pub(super) ambush: bool,
    pub(super) faces_sighting: bool,
    pub(super) moves: bool,
    pub(super) low_supplies: bool,
    pub(super) supported: bool,
}

impl Contact {
    pub fn order_preference(
        self,
        observed: &Scenario,
        unit: &Unit,
        origin: Coordinate,
        order: &UnitOrderInput,
    ) -> i64 {
        let Some(end) = order.path.last() else {
            return 0;
        };
        let end = Coordinate::new(end.x as u16, end.y as u16);
        let cover = |position| {
            observed
                .map
                .tile_at(position)
                .is_some_and(|terrain| terrain == Terrain::Forest || terrain == Terrain::Hills)
        };
        let distance_before = distance(origin, self.position);
        let distance_after = distance(end, self.position);
        let supplies = unit.supplies();
        let supported = observed.units.iter().any(|ally| {
            ally.player_number() == unit.player_number()
                && ally.unit_id() != unit.unit_id()
                && ally.kind() != UnitKind::Truck
                && ally.board_position().is_some_and(|p| distance(p, end) <= 2)
        });
        let facts = ContactOrderFacts {
            age: self.age,
            distance_before,
            distance_after,
            progress: distance_before - distance_after,
            cover_after: cover(end),
            attack_move: order.attack_move == Some(true),
            ambush: order.ambush == Some(true),
            faces_sighting: distance_after > 0
                && order.direction == Some(facing(end, self.position)),
            moves: order.path.len() > 1,
            low_supplies: supplies.current() * 2 < supplies.maximum(),
            supported,
        };
        let bias = (self.preference)(&facts);
        bias.clamp(-220, 220) * self.strength / 64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::resource_target,
        map_definition::MapDefinition,
        test_support::{FixtureValue, TestResult},
        unit_loss::{ExhaustedUnitLoss, UnitLoss},
        visibility,
    };

    const CONTACT_POLICY: ContactPolicy = ContactPolicy {
        horizon: 6,
        weight: 96,
        preference: |_| 0,
    };

    fn frame(units: Vec<Unit>, losses: Vec<UnitLoss>) -> TurnFrame {
        TurnFrame {
            units,
            losses,
            sabotages: Vec::new(),
            departures: Vec::new(),
            indirect_impacts: Vec::new(),
            shots: Vec::new(),
            buildings: Vec::new(),
            supply_crates: Vec::new(),
            visible_tiles: Vec::new(),
            duration_ms: 0,
        }
    }

    #[test]
    fn depot_memory_distinguishes_visible_remembered_and_unknown_stock() -> TestResult {
        let mut scenario = MapDefinition::parse(
            r#"{
            "width": 8, "height": 3, "theme": "GreenForest",
            "features": [],
            "depots": [
                {"position": {"x": 1, "y": 1}, "kind": "Supply"},
                {"position": {"x": 4, "y": 1}, "kind": "Fuel"},
                {"position": {"x": 7, "y": 1}, "kind": "Supply"}
            ],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 7, "y": 0}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#,
        )
        .fixture()?
        .scenario()
        .fixture()?;
        let player = PlayerNumber::Player1;
        let empty = Coordinate::new(1, 1);
        let partial = Coordinate::new(4, 1);
        scenario.buildings.first_mut().fixture()?.stock.current = 0;
        scenario.buildings.get_mut(1).fixture()?.stock.current = 1500;
        // Projected frames retain raw hidden stock internally. The tracker
        // must gate all observations on visibility.
        scenario.buildings.last_mut().fixture()?.stock.current = 1;
        let seen =
            visibility::observed_scenario(&scenario, player, &BTreeSet::from([empty, partial]));
        let mut playback = frame(Vec::new(), Vec::new());
        playback.buildings = seen.buildings;
        let mut memory = EnemyMemory::default();
        memory.observe(player, 3, &[playback]);

        // Fuel was spent while out of sight. Only the public fallback and
        // remembered amount may affect the AI forecast.
        scenario.buildings.get_mut(1).fixture()?.stock.current = 50;
        let mut fogged = visibility::observed_scenario(&scenario, player, &BTreeSet::new());
        for depot in &mut fogged.buildings {
            depot.stock = ResourceStock::depot(depot.kind.resource_kind().fixture()?);
        }
        let mut hungry = scenario.units.first().fixture()?.clone();
        hungry.set_supplies_for_test(25);
        let origin = hungry.board_position().fixture()?;
        assert_eq!(resource_target(&fogged, &hungry, origin), Some(empty));
        memory.apply_empty_depots(&mut fogged);
        let depot = fogged.buildings.first().fixture()?;
        assert!(depot.stock_visible);
        assert_eq!(depot.stock.current, 0);
        assert_eq!(fogged.buildings.get(1).fixture()?.stock.current, 4096);
        assert_eq!(fogged.buildings.last().fixture()?.stock.current, 1024);
        assert_eq!(
            resource_target(&fogged, &hungry, origin),
            Some(Coordinate::new(7, 1))
        );

        let mut visible_again =
            visibility::observed_scenario(&scenario, player, &BTreeSet::from([partial]));
        memory.apply_empty_depots(&mut visible_again);
        assert_eq!(visible_again.buildings.get(1).fixture()?.stock.current, 50);
        Ok(())
    }

    #[test]
    fn retains_last_observed_tile_without_tracking_hidden_movement_or_confirmed_losses()
    -> TestResult {
        let scenario = MapDefinition::parse(r#"{
            "width": 8, "height": 3, "theme": "GreenForest",
            "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 1, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 4, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let player = PlayerNumber::Player1;
        let enemy = scenario
            .units
            .iter()
            .find(|unit| unit.player_number() != player)
            .fixture()?;
        let last_seen = enemy.board_position().fixture()?;
        let mut observed = scenario.clone();
        observed.units.retain(|unit| unit.player_number() == player);

        let mut memory = EnemyMemory::default();
        memory.observe(
            player,
            1,
            &[
                frame(scenario.units.clone(), Vec::new()),
                frame(observed.units.clone(), Vec::new()),
            ],
        );
        let contacts = memory.contacts(&observed, 2, CONTACT_POLICY);
        assert_eq!(contacts.first().fixture()?.position, last_seen);
        assert!(memory.contacts(&scenario, 2, CONTACT_POLICY).is_empty());
        assert!(memory.contacts(&observed, 8, CONTACT_POLICY).is_empty());

        memory.observe(
            player,
            2,
            &[
                frame(
                    scenario.units.clone(),
                    vec![UnitLoss::Exhaustion(ExhaustedUnitLoss {
                        unit: enemy.clone(),
                    })],
                ),
                frame(scenario.units.clone(), Vec::new()),
            ],
        );
        assert!(memory.contacts(&observed, 3, CONTACT_POLICY).is_empty());
        Ok(())
    }
}
