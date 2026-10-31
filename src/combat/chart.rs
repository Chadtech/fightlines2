//! Read-only, synthetic matchups using the same calculation as live combat.
use super::{AttackAspect, Combat, CombatKind, DamageCalculation};
use crate::{
    map::{Coordinate, MapTheme, Terrain},
    map_definition::{DepotPlacement, MapDefinition, TerrainPlacement, UnitPlacement},
    scenario::{BuildingKind, Direction, PlayerNumber, UnitKind},
    supplies::SupplyOrder,
    turns::{FacingOrder, MoveOrder, TravelMode},
};
use juniper::{FieldResult, GraphQLEnum, GraphQLInputObject, GraphQLObject};

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum CombatChartDefense {
    Unready,
    Ready,
    Front,
    Flank,
    Rear,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum CombatChartCover {
    OpenGround,
    HillsForest,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum CombatReadyOrder {
    StandGround,
    Ambush,
    AttackMove,
}

#[derive(Clone, Debug, GraphQLInputObject)]
pub struct CombatChartInput {
    pub attack: CombatKind,
    pub attacker_hp: i32,
    pub defender_hp: i32,
    pub attacker_aim: AttackAspect,
    pub ready_order: CombatReadyOrder,
    pub entrenched_infantry: bool,
    pub fortress: bool,
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct CombatChartHit {
    pub attacker: UnitKind,
    pub defender: UnitKind,
    pub defense: CombatChartDefense,
    pub cover: CombatChartCover,
    pub calculation: DamageCalculation,
    pub remaining_hp: i32,
}

/// Each legal damage comparison; firing eligibility and return volleys are separate.
pub fn hits(input: CombatChartInput) -> FieldResult<Vec<CombatChartHit>> {
    if !(1..=16).contains(&input.attacker_hp) || !(1..=16).contains(&input.defender_hp) {
        return Err("chart health must be between 1 and 16 hp".into());
    }
    let attackers: &[UnitKind] = if input.attack == CombatKind::IndirectFire {
        &[UnitKind::FieldGun]
    } else {
        &[UnitKind::Infantry, UnitKind::Tank, UnitKind::FieldGun]
    };
    let ready_defenses: &[CombatChartDefense] = if input.attack == CombatKind::IndirectFire {
        &[CombatChartDefense::Unready, CombatChartDefense::Ready]
    } else {
        &[
            CombatChartDefense::Unready,
            CombatChartDefense::Front,
            CombatChartDefense::Flank,
            CombatChartDefense::Rear,
        ]
    };
    let mut result = Vec::new();
    for defender in [
        UnitKind::Infantry,
        UnitKind::Tank,
        UnitKind::FieldGun,
        UnitKind::Truck,
    ] {
        let defenses = match defender {
            UnitKind::Infantry | UnitKind::Tank => ready_defenses,
            UnitKind::FieldGun | UnitKind::Truck => &[CombatChartDefense::Unready],
        };
        for &attacker in attackers {
            for &defense in defenses {
                for cover in [CombatChartCover::OpenGround, CombatChartCover::HillsForest] {
                    result.push(hit(&input, attacker, defender, defense, cover)?);
                }
            }
        }
    }
    Ok(result)
}

fn hit(
    input: &CombatChartInput,
    attacker: UnitKind,
    defender: UnitKind,
    defense: CombatChartDefense,
    cover: CombatChartCover,
) -> FieldResult<CombatChartHit> {
    let origin = Coordinate::new(1, 1);
    let destination = Coordinate::new(2, 1);
    let aim = match input.attacker_aim {
        AttackAspect::Front => Direction::East,
        AttackAspect::Flank => Direction::North,
        AttackAspect::Rear => Direction::West,
    };
    let facing = match defense {
        CombatChartDefense::Front | CombatChartDefense::Ready | CombatChartDefense::Unready => {
            Direction::West
        }
        CombatChartDefense::Flank => Direction::North,
        CombatChartDefense::Rear => Direction::East,
    };
    let definition = MapDefinition {
        description: String::new(),
        width: 4,
        height: 3,
        theme: MapTheme::GreenForest,
        features: match cover {
            CombatChartCover::OpenGround => Vec::new(),
            CombatChartCover::HillsForest => vec![TerrainPlacement {
                position: destination,
                terrain: Terrain::Hills,
            }],
        },
        depots: if input.fortress {
            vec![DepotPlacement {
                position: destination,
                kind: BuildingKind::Fortress,
            }]
        } else {
            Vec::new()
        },
        units: vec![
            UnitPlacement {
                id: 1,
                position: origin,
                player_number: PlayerNumber::Player1,
                kind: attacker,
                direction: Some(aim),
            },
            UnitPlacement {
                id: 2,
                position: destination,
                player_number: PlayerNumber::Player2,
                kind: defender,
                direction: if defender == UnitKind::Truck {
                    None
                } else {
                    Some(facing)
                },
            },
        ],
    };
    let mut board = definition.scenario().map_err(|error| error.to_string())?;
    let shooter = board.units.first_mut().ok_or("chart attacker is missing")?;
    shooter.take_damage(shooter.hit_points().maximum() - input.attacker_hp);
    let target = board.units.get_mut(1).ok_or("chart defender is missing")?;
    target.take_damage(target.hit_points().maximum() - input.defender_hp);
    if input.entrenched_infantry && defender == UnitKind::Infantry {
        target.dig_in();
    }
    let target_id = target.unit_id();
    let mut order = MoveOrder {
        unit_id: target_id,
        path: vec![destination],
        travel: TravelMode::Normal,
        facing: FacingOrder::Unchanged,
        supply: SupplyOrder::default(),
        unloads: Vec::new(),
    };
    if defense != CombatChartDefense::Unready {
        match input.ready_order {
            CombatReadyOrder::StandGround => order.facing = FacingOrder::StandGround(facing),
            CombatReadyOrder::Ambush => order.facing = FacingOrder::Ambush(facing),
            CombatReadyOrder::AttackMove => order.travel = TravelMode::AttackMove,
        }
    }
    let combat = Combat::prepare(&mut board, &[order]);
    let calculation = combat.damage_calculation(
        &board,
        board.units.first().ok_or("chart attacker is missing")?,
        board.units.get(1).ok_or("chart defender is missing")?,
        input.attack,
    );
    let remaining_hp = (input.defender_hp - calculation.damage).max(0);
    Ok(CombatChartHit {
        attacker,
        defender,
        defense,
        cover,
        calculation,
        remaining_hp,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};

    fn settings(attack: CombatKind) -> CombatChartInput {
        CombatChartInput {
            attack,
            attacker_hp: 16,
            defender_hp: 16,
            attacker_aim: AttackAspect::Front,
            ready_order: CombatReadyOrder::StandGround,
            entrenched_infantry: false,
            fortress: false,
        }
    }

    #[test]
    fn chart_has_every_valid_comparison_and_uses_current_combat_factors() -> TestResult<()> {
        let comparisons = hits(settings(CombatKind::Ambush)).fixture()?;
        assert_eq!(comparisons.len(), 60);
        let flank = comparisons
            .iter()
            .find(|hit| {
                hit.attacker == UnitKind::Infantry
                    && hit.defender == UnitKind::Tank
                    && hit.defense == CombatChartDefense::Flank
                    && hit.cover == CombatChartCover::OpenGround
            })
            .fixture()?;
        assert_eq!(flank.calculation.damage, 8);
        assert_eq!(flank.calculation.factors.ambush, 5.0);
        assert_eq!(flank.remaining_hp, 8);
        assert!(
            comparisons
                .iter()
                .filter(|hit| hit.defender == UnitKind::FieldGun || hit.defender == UnitKind::Truck)
                .all(|hit| hit.defense == CombatChartDefense::Unready)
        );
        Ok(())
    }

    #[test]
    fn indirect_chart_has_no_directional_cases_and_keeps_protection() -> TestResult<()> {
        let mut input = settings(CombatKind::IndirectFire);
        input.entrenched_infantry = true;
        input.fortress = true;
        let comparisons = hits(input).fixture()?;
        assert_eq!(comparisons.len(), 12);
        for hit in comparisons {
            assert_eq!(hit.attacker, UnitKind::FieldGun);
            assert!(
                hit.defense == CombatChartDefense::Unready
                    || hit.defense == CombatChartDefense::Ready
            );
            assert_eq!(hit.calculation.factors.defender_facing, 1.0);
            assert_eq!(hit.calculation.factors.attacker_aim, 1.0);
            assert_eq!(hit.calculation.factors.fortification, 0.25);
            if hit.defender == UnitKind::Infantry {
                assert_eq!(hit.calculation.factors.entrenchment, 0.06);
            }
        }
        Ok(())
    }

    #[test]
    fn chart_rejects_health_outside_the_supported_range() {
        for health in [-1, 0, 17, i32::MAX] {
            let mut input = settings(CombatKind::AttackMove);
            input.attacker_hp = health;
            assert!(hits(input).is_err());
            let mut input = settings(CombatKind::AttackMove);
            input.defender_hp = health;
            assert!(hits(input).is_err());
        }
    }
}
