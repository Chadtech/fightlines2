//! Facts about candidate orders, derived from each planner's projected board.
use super::{distance, objective};
use crate::{
    combat,
    map::{Coordinate, Terrain},
    player_number::PlayerNumber,
    scenario::{Scenario, Unit, UnitId, UnitKind},
    turns::UnitOrderInput,
    visibility,
};
use std::collections::BTreeSet;

/// Summary of an order evaluated on the fog-limited board.
pub(super) struct BoardOrderFacts<'a> {
    pub(super) sight: OrderSight<'a>,
    pub(super) field_gun: bool,
    pub(super) infantry: bool,
    pub(super) revealed: bool,
    pub(super) moves: bool,
    pub(super) attack_move: bool,
    pub(super) indirect_fire: bool,
    pub(super) hold: bool,
    pub(super) cover_after: bool,
    pub(super) low_supplies: bool,
    pub(super) wounded: bool,
    pub(super) screened_after: bool,
    pub(super) threat_before: bool,
    pub(super) threat_after: bool,
    pub(super) path_crosses_threat: bool,
    pub(super) nearest_enemy_after: i32,
    pub(super) moving_toward_known_contact: bool,
    pub(super) allies_near_end: i32,
    pub(super) near_supply_after: bool,
    pub(super) target_enemy_visible: bool,
    pub(super) target_last_seen: bool,
}

/// Sight from the order's end tile, using public terrain and the current
/// shared view. Rules can ask for geometry without evaluating it for every
/// candidate.
pub(super) struct OrderSight<'a> {
    observed: &'a Scenario,
    visible: &'a BTreeSet<Coordinate>,
    player: PlayerNumber,
    unit: UnitId,
    kind: UnitKind,
    origin: Coordinate,
    end: Coordinate,
    indirect_target: Option<Coordinate>,
}

impl OrderSight<'_> {
    pub(super) fn bonus_before(&self) -> i32 {
        visibility::sight_bonus(&self.observed.map, self.origin)
    }

    pub(super) fn bonus_after(&self) -> i32 {
        visibility::sight_bonus(&self.observed.map, self.end)
    }

    pub(super) fn indirect_target_bonus(&self) -> Option<i32> {
        self.indirect_target
            .map(|target| visibility::sight_bonus(&self.observed.map, target))
    }

    pub(super) fn new_tiles(&self) -> usize {
        self.terrain_tiles()
            .filter(|tile| !self.visible.contains(tile))
            .count()
    }

    pub(super) fn artillery_tiles(&self) -> usize {
        self.count_artillery_tiles(self.terrain_tiles())
    }

    fn terrain_tiles(&self) -> impl Iterator<Item = Coordinate> + '_ {
        visibility::terrain_sight(&self.observed.map, self.end, self.kind)
    }

    fn ready_gun_positions(&self) -> impl Iterator<Item = Coordinate> + '_ {
        let rules = combat::rules(UnitKind::FieldGun);
        self.observed.units.iter().filter_map(move |ally| {
            let supplies = ally.supplies();
            (ally.unit_id() != self.unit
                && ally.player_number() == self.player
                && ally.kind() == UnitKind::FieldGun
                && ally.is_alive()
                && supplies.current()
                    >= supplies.upkeep_per_turn() + rules.readiness_cost + rules.shot_cost)
                .then(|| ally.board_position())
                .flatten()
        })
    }

    fn count_artillery_tiles(&self, tiles: impl Iterator<Item = Coordinate>) -> usize {
        let guns: Vec<_> = self.ready_gun_positions().collect();
        let range = combat::rules(UnitKind::FieldGun).indirect_range;
        tiles
            .filter(|tile| {
                guns.iter()
                    .any(|gun| combat::within_indirect_range(*gun, *tile, range))
            })
            .count()
    }
}

pub(super) type BoardPreference = fn(&BoardOrderFacts<'_>) -> i64;

/// Score a candidate using only the unit's own state, projected units and
/// terrain, and its optional last sighting. Threat ranges are conservative
/// geometric estimates before accounting for facing or terrain obstructions.
pub(super) fn preference(
    score: BoardPreference,
    observed: &Scenario,
    visible: &BTreeSet<Coordinate>,
    unit: &Unit,
    order: &UnitOrderInput,
    known_contact: Option<Coordinate>,
) -> i64 {
    board_order_facts(observed, visible, unit, order, known_contact).map_or(0, |facts| {
        let bias = score(&facts);
        bias.clamp(-400, 400)
    })
}

fn board_order_facts<'a>(
    observed: &'a Scenario,
    visible: &'a BTreeSet<Coordinate>,
    unit: &Unit,
    order: &UnitOrderInput,
    known_contact: Option<Coordinate>,
) -> Option<BoardOrderFacts<'a>> {
    let origin = unit.board_position()?;
    let end = order.path.last()?;
    let end = Coordinate::new(end.x as u16, end.y as u16);
    let indirect_target = order
        .indirect_fire
        .as_ref()
        .map(|tile| Coordinate::new(tile.x as u16, tile.y as u16));
    let target = indirect_target.unwrap_or(end);
    let supplies = unit.supplies();
    let health = unit.hit_points();
    let terrain_after = observed.map.tile_at(end);
    let covers = |terrain| matches!(terrain, Some(Terrain::Hills | Terrain::Forest));
    let moves = order.path.len() > 1;
    let attack_move = order.attack_move == Some(true);
    let ambush = order.ambush == Some(true);
    let stand_ground = order.stand_ground == Some(true);
    let mut facts = BoardOrderFacts {
        sight: OrderSight {
            observed,
            visible,
            player: unit.player_number(),
            unit: unit.unit_id(),
            kind: unit.kind(),
            origin,
            end,
            indirect_target,
        },
        field_gun: unit.kind() == UnitKind::FieldGun,
        infantry: unit.kind() == UnitKind::Infantry,
        revealed: unit.position_revealed(),
        moves,
        attack_move,
        indirect_fire: indirect_target.is_some(),
        hold: !moves
            && !ambush
            && !stand_ground
            && indirect_target.is_none()
            && order.dig_in != Some(true)
            && order.sabotage != Some(true),
        cover_after: covers(terrain_after),
        low_supplies: supplies.current() * 2 < supplies.maximum(),
        wounded: health.current() * 2 < health.maximum(),
        screened_after: false,
        threat_before: false,
        threat_after: false,
        path_crosses_threat: false,
        nearest_enemy_after: 1000,
        moving_toward_known_contact: known_contact
            .is_some_and(|contact| distance(end, contact) < distance(origin, contact)),
        allies_near_end: 0,
        near_supply_after: observed.buildings.iter().any(|building| {
            building.kind.resource_kind().is_some()
                && !building.is_destroyed()
                && distance(building.position, end) <= 1
        }),
        target_enemy_visible: false,
        target_last_seen: known_contact == Some(target),
    };

    let mut nearest_enemy_before = 1000;
    let mut front = known_contact;
    for enemy in observed
        .units
        .iter()
        .filter(|other| other.player_number() != unit.player_number())
    {
        let Some(position) = enemy.board_position() else {
            continue;
        };
        if position == target {
            facts.target_enemy_visible = true;
        }
        if enemy.kind() == UnitKind::Truck {
            continue;
        }
        let before = distance(origin, position);
        if before < nearest_enemy_before {
            nearest_enemy_before = before;
            front = Some(position);
        }
        facts.nearest_enemy_after = facts.nearest_enemy_after.min(distance(end, position));
        let rules = combat::rules(enemy.kind());
        let threatens = |tile| {
            distance(tile, position) <= rules.range
                || (rules.indirect_range > 0
                    && combat::within_indirect_range(position, tile, rules.indirect_range))
        };
        facts.threat_before |= threatens(origin);
        facts.threat_after |= threatens(end);
        facts.path_crosses_threat |= order
            .path
            .iter()
            .skip(1)
            .any(|tile| threatens(Coordinate::new(tile.x as u16, tile.y as u16)));
    }

    let front = front.unwrap_or_else(|| objective(observed, origin));
    for ally in observed.units.iter().filter(|other| {
        other.player_number() == unit.player_number()
            && other.unit_id() != unit.unit_id()
            && other.kind() != UnitKind::Truck
    }) {
        let Some(position) = ally.board_position() else {
            continue;
        };
        if distance(position, end) <= 3 {
            facts.allies_near_end += 1;
        }
        if matches!(ally.kind(), UnitKind::Tank | UnitKind::Infantry) {
            let ahead = distance(position, front);
            facts.screened_after |= distance(position, end) <= 3 && ahead < distance(end, front);
        }
    }
    Some(facts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::{coordinate_input, hold},
        map_definition::MapDefinition,
        test_support::{FixtureValue, TestResult},
    };

    #[test]
    fn board_rules_distinguish_a_remembered_target_from_a_visible_threat() -> TestResult {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 8, "height": 5, "theme": "GreenForest",
            "features": [{"position": {"x": 4, "y": 2}, "terrain": "Forest"}],
            "depots": [],
            "units": [
                {"id": 1, "position": {"x": 2, "y": 2}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 2, "position": {"x": 3, "y": 2}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 3, "position": {"x": 4, "y": 2}, "playerNumber": "Player2", "kind": "Tank", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let player = PlayerNumber::Player1;
        scenario.units.first_mut().fixture()?.reveal_position();
        let gun = scenario.units.first().fixture()?.clone();
        let target = Coordinate::new(4, 2);
        let mut order = hold(&gun, gun.board_position().fixture()?);
        order.indirect_fire = Some(coordinate_input(target));
        let visible = visibility::visible_tiles(&scenario, player);
        let observed = visibility::observed_scenario(&scenario, player, &visible);
        let remembered =
            board_order_facts(&observed, &visible, &gun, &order, Some(target)).fixture()?;
        assert!(remembered.field_gun);
        assert!(remembered.revealed);
        assert!(remembered.screened_after);
        assert!(remembered.target_last_seen);
        assert!(!remembered.target_enemy_visible);
        assert!(!remembered.threat_before);

        scenario.units.last_mut().fixture()?.reveal_position();
        let visible = visibility::visible_tiles(&scenario, player);
        let observed = visibility::observed_scenario(&scenario, player, &visible);
        let seen = board_order_facts(&observed, &visible, &gun, &order, None).fixture()?;
        assert!(seen.target_enemy_visible);
        assert!(seen.threat_before);
        assert!(!seen.target_last_seen);
        Ok(())
    }

    #[test]
    fn board_rules_expose_sight_gain_independently_of_artillery_readiness() -> TestResult {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 16, "height": 5, "theme": "GreenForest",
            "features": [
                {"position": {"x": 5, "y": 2}, "terrain": "Hills"},
                {"position": {"x": 6, "y": 2}, "terrain": "Mountains"}
            ],
            "depots": [],
            "units": [
                {"id": 1, "position": {"x": 4, "y": 2}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 2, "y": 2}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 3, "position": {"x": 14, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let player = PlayerNumber::Player1;
        let visible = visibility::visible_tiles(&scenario, player);
        let scout = scenario.units.first().fixture()?.clone();
        let gun = scenario.units.get(1).fixture()?.clone();
        let mountain = Coordinate::new(6, 2);
        let mut advance = hold(&scout, scout.board_position().fixture()?);
        advance.path.push(coordinate_input(Coordinate::new(5, 2)));
        let mut fire = hold(&gun, gun.board_position().fixture()?);
        fire.indirect_fire = Some(coordinate_input(mountain));
        let observed = visibility::observed_scenario(&scenario, player, &visible);
        let scout_facts =
            board_order_facts(&observed, &visible, &scout, &advance, None).fixture()?;
        assert_eq!(scout_facts.sight.bonus_before(), 0);
        assert_eq!(scout_facts.sight.bonus_after(), 1);
        assert_eq!(scout_facts.sight.indirect_target_bonus(), None);
        assert!(scout_facts.sight.artillery_tiles() > 0);
        let gun_facts = board_order_facts(&observed, &visible, &gun, &fire, None).fixture()?;
        assert_eq!(gun_facts.sight.indirect_target_bonus(), Some(2));
        assert!(!gun_facts.target_enemy_visible);

        scenario
            .units
            .get_mut(1)
            .fixture()?
            .set_supplies_for_test(0);
        let observed = visibility::observed_scenario(&scenario, player, &visible);
        let scout_without_support =
            board_order_facts(&observed, &visible, &scout, &advance, None).fixture()?;
        assert_eq!(
            scout_without_support.sight.new_tiles(),
            scout_facts.sight.new_tiles()
        );
        assert_eq!(scout_without_support.sight.artillery_tiles(), 0);
        Ok(())
    }
}
