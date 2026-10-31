//! Authoritative loss events, emitted where combat and resource settlement kill units.
use crate::{
    combat::{CombatKind, Shot},
    scenario::{PlayerNumber, Unit},
};
use juniper::{GraphQLObject, GraphQLUnion};
use serde::{Deserialize, Serialize};

/// The living casualty snapshot lets presentation show the unit before removal.
#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct CombatUnitLoss {
    pub unit: Unit,
    pub kind: CombatKind,
    pub attacker: Unit,
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct ExhaustedUnitLoss {
    pub unit: Unit,
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct ConcealedIndirectFireUnitLoss {
    pub unit: Unit,
}

/// Trucks cannot ride aboard other trucks, so carrier causes are direct losses.
#[derive(Clone, Debug, GraphQLUnion, Serialize, Deserialize)]
pub enum DirectUnitLoss {
    Combat(CombatUnitLoss),
    Exhaustion(ExhaustedUnitLoss),
    ConcealedIndirectFire(ConcealedIndirectFireUnitLoss),
}

#[derive(Clone, Debug, GraphQLObject, Serialize, Deserialize)]
pub struct CarrierUnitLoss {
    pub unit: Unit,
    pub carrier_loss: DirectUnitLoss,
}

#[derive(Clone, Debug, GraphQLUnion, Serialize, Deserialize)]
pub enum UnitLoss {
    Combat(CombatUnitLoss),
    Exhaustion(ExhaustedUnitLoss),
    ConcealedIndirectFire(ConcealedIndirectFireUnitLoss),
    Carrier(CarrierUnitLoss),
}

impl DirectUnitLoss {
    pub fn unit(&self) -> &Unit {
        match self {
            Self::Combat(loss) => &loss.unit,
            Self::Exhaustion(loss) => &loss.unit,
            Self::ConcealedIndirectFire(loss) => &loss.unit,
        }
    }

    fn for_each_unit_mut(&mut self, visit: &mut impl FnMut(&mut Unit)) {
        match self {
            Self::Combat(loss) => {
                visit(&mut loss.unit);
                visit(&mut loss.attacker);
            }
            Self::Exhaustion(loss) => visit(&mut loss.unit),
            Self::ConcealedIndirectFire(loss) => visit(&mut loss.unit),
        }
    }

    fn projected(&self, units: &[Unit], player: PlayerNumber) -> Option<Self> {
        let mut unit = self.unit().clone();
        if !units.iter().any(|seen| seen.unit_id() == unit.unit_id()) {
            return None;
        }
        if unit.player_number() != player {
            unit.conceal_resources();
        }
        Some(match self {
            Self::Combat(loss) => {
                let attacker_seen = units
                    .iter()
                    .any(|seen| seen.unit_id() == loss.attacker.unit_id());
                if loss.kind == CombatKind::IndirectFire
                    && loss.attacker.player_number() != player
                    && !attacker_seen
                {
                    Self::ConcealedIndirectFire(ConcealedIndirectFireUnitLoss { unit })
                } else {
                    let mut attacker = loss.attacker.clone();
                    attacker.conceal_resources();
                    Self::Combat(CombatUnitLoss {
                        unit,
                        kind: loss.kind,
                        attacker,
                    })
                }
            }
            Self::Exhaustion(_) => Self::Exhaustion(ExhaustedUnitLoss { unit }),
            Self::ConcealedIndirectFire(_) => {
                Self::ConcealedIndirectFire(ConcealedIndirectFireUnitLoss { unit })
            }
        })
    }
}

impl From<DirectUnitLoss> for UnitLoss {
    fn from(loss: DirectUnitLoss) -> Self {
        match loss {
            DirectUnitLoss::Combat(loss) => Self::Combat(loss),
            DirectUnitLoss::Exhaustion(loss) => Self::Exhaustion(loss),
            DirectUnitLoss::ConcealedIndirectFire(loss) => Self::ConcealedIndirectFire(loss),
        }
    }
}

impl UnitLoss {
    pub fn unit(&self) -> &Unit {
        match self {
            Self::Combat(loss) => &loss.unit,
            Self::Exhaustion(loss) => &loss.unit,
            Self::ConcealedIndirectFire(loss) => &loss.unit,
            Self::Carrier(loss) => &loss.unit,
        }
    }

    /// Replay inspection and redaction must also visit event-owned portraits.
    pub fn for_each_unit_mut(&mut self, visit: &mut impl FnMut(&mut Unit)) {
        match self {
            Self::Combat(loss) => {
                visit(&mut loss.unit);
                visit(&mut loss.attacker);
            }
            Self::Exhaustion(loss) => visit(&mut loss.unit),
            Self::ConcealedIndirectFire(loss) => visit(&mut loss.unit),
            Self::Carrier(loss) => {
                visit(&mut loss.unit);
                loss.carrier_loss.for_each_unit_mut(visit);
            }
        }
    }

    pub fn projected(&self, units: &[Unit], player: PlayerNumber) -> Option<Self> {
        match self {
            Self::Combat(loss) => DirectUnitLoss::Combat(loss.clone())
                .projected(units, player)
                .map(Into::into),
            Self::Exhaustion(loss) => DirectUnitLoss::Exhaustion(loss.clone())
                .projected(units, player)
                .map(Into::into),
            Self::ConcealedIndirectFire(loss) => {
                DirectUnitLoss::ConcealedIndirectFire(loss.clone())
                    .projected(units, player)
                    .map(Into::into)
            }
            Self::Carrier(loss) => {
                if !units
                    .iter()
                    .any(|seen| seen.unit_id() == loss.unit.unit_id())
                {
                    return None;
                }
                let mut unit = loss.unit.clone();
                if unit.player_number() != player {
                    unit.conceal_resources();
                }
                loss.carrier_loss
                    .projected(units, player)
                    .map(|carrier_loss| Self::Carrier(CarrierUnitLoss { unit, carrier_loss }))
            }
        }
    }
}

fn with_passengers(direct: Vec<DirectUnitLoss>, units: &[Unit]) -> Vec<UnitLoss> {
    // Preserve board ordering so independent losses retain their presentation order.
    units
        .iter()
        .filter(|unit| unit.is_alive())
        .filter_map(|unit| {
            if let Some(carrier_loss) = direct
                .iter()
                .find(|loss| unit.carrier_id() == Some(loss.unit().unit_id()))
            {
                Some(UnitLoss::Carrier(CarrierUnitLoss {
                    unit: unit.clone(),
                    carrier_loss: carrier_loss.clone(),
                }))
            } else {
                direct
                    .iter()
                    .find(|loss| loss.unit().unit_id() == unit.unit_id())
                    .cloned()
                    .map(Into::into)
            }
        })
        .collect()
}

pub fn combat(shots: &[Shot], units: &[Unit]) -> Vec<UnitLoss> {
    let mut direct = Vec::new();
    for shot in shots.iter().filter(|shot| {
        shot.target_health.before.current() > 0 && shot.target_health.after.current() == 0
    }) {
        if direct
            .iter()
            .any(|loss: &DirectUnitLoss| loss.unit().unit_id() == shot.target.unit_id())
        {
            continue;
        }
        if let Some(unit) = units
            .iter()
            .find(|unit| unit.unit_id() == shot.target.unit_id())
        {
            direct.push(DirectUnitLoss::Combat(CombatUnitLoss {
                unit: unit.clone(),
                kind: shot.kind,
                attacker: shot.attacker.clone(),
            }));
        }
    }
    with_passengers(direct, units)
}

pub fn exhaustion(units: &[Unit]) -> Vec<UnitLoss> {
    let direct = units
        .iter()
        .filter(|unit| unit.is_alive() && unit.exhaustion_expired())
        .map(|unit| DirectUnitLoss::Exhaustion(ExhaustedUnitLoss { unit: unit.clone() }))
        .collect();
    with_passengers(direct, units)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        combat::CombatHealth,
        map_definition::MapDefinition,
        scenario::Scenario,
        test_support::{FixtureValue, TestResult},
        turns::{TurnFrame, TurnResolution},
        visibility,
    };

    fn scenario() -> TestResult<Scenario> {
        MapDefinition::parse(r#"{
            "width":12,"height":3,"theme":"GreenForest","features":[],"depots":[],
            "units":[
                {"id":1,"position":{"x":1,"y":1},"playerNumber":"Player1","kind":"Truck"},
                {"id":2,"position":{"x":2,"y":1},"playerNumber":"Player1","kind":"Infantry","direction":"East"},
                {"id":3,"position":{"x":9,"y":1},"playerNumber":"Player2","kind":"FieldGun","direction":"West"}
            ]
        }"#).fixture()?.scenario().fixture()
    }

    #[test]
    fn combat_records_lethal_source_once_and_groups_carried_passengers() -> TestResult<()> {
        let mut board = scenario()?;
        let truck = board.units.first().fixture()?.clone();
        board.units.get_mut(1).fixture()?.board(truck.unit_id());
        let attacker = board.units.get(2).fixture()?.clone();
        let mut dead = truck.clone();
        dead.take_damage(16);
        let shot = Shot {
            kind: CombatKind::AttackMove,
            origin: attacker.board_position().fixture()?,
            destination: truck.board_position().fixture()?,
            damage: 16,
            flank_bonus: false,
            attacker: attacker.clone(),
            target: truck.clone(),
            attacker_health: CombatHealth {
                before: attacker.hit_points(),
                after: attacker.hit_points(),
            },
            target_health: CombatHealth {
                before: truck.hit_points(),
                after: dead.hit_points(),
            },
        };
        let mut overkill = shot.clone();
        overkill.target_health.before = dead.hit_points();
        let losses = combat(&[shot, overkill], &board.units);
        assert_eq!(losses.len(), 2);
        let UnitLoss::Combat(loss) = losses.first().fixture()? else {
            return Err("expected a direct combat loss".into());
        };
        assert_eq!(loss.kind, CombatKind::AttackMove);
        assert_eq!(loss.attacker.unit_id(), attacker.unit_id());
        assert!(loss.unit.is_alive());
        let UnitLoss::Carrier(passenger) = losses.get(1).fixture()? else {
            return Err("expected passenger loss from its carrier".into());
        };
        assert_eq!(passenger.carrier_loss.unit().unit_id(), truck.unit_id());
        Ok(())
    }

    #[test]
    fn settlement_records_carrier_cause_and_independent_passenger_exhaustion() -> TestResult<()> {
        for carrier_exhausts in [false, true] {
            let mut board = scenario()?;
            let truck = board.units.first().fixture()?.clone();
            let passenger = board.units.get_mut(1).fixture()?;
            passenger.board(truck.unit_id());
            passenger.set_supplies_for_test(1);
            if carrier_exhausts {
                board.units.first_mut().fixture()?.set_supplies_for_test(1);
            }
            assert!(board.finish_turn_resources(1).losses.is_empty());
            assert!(board.finish_turn_resources(2).losses.is_empty());
            let settled = board.finish_turn_resources(3);
            assert_eq!(settled.losses.len(), if carrier_exhausts { 2 } else { 1 });
            let passenger = settled
                .losses
                .iter()
                .find(|loss| loss.unit().id() == "2")
                .fixture()?;
            match passenger {
                UnitLoss::Carrier(loss) if carrier_exhausts => {
                    assert_eq!(loss.carrier_loss.unit().unit_id(), truck.unit_id());
                    let DirectUnitLoss::Exhaustion(_) = &loss.carrier_loss else {
                        return Err("exhausted carrier lost its supply cause".into());
                    };
                }
                UnitLoss::Exhaustion(_) if !carrier_exhausts => {}
                _ => return Err("incorrect passenger loss cause".into()),
            }
            assert!(board.finish_turn_resources(4).losses.is_empty());
        }
        Ok(())
    }

    #[test]
    fn projection_conceals_gun_and_its_hidden_victim_independently() -> TestResult<()> {
        let mut board = scenario()?;
        let victim = board.units.first().fixture()?.clone();
        let attacker = board.units.get(2).fixture()?.clone();
        let event = UnitLoss::Combat(CombatUnitLoss {
            unit: victim.clone(),
            kind: CombatKind::IndirectFire,
            attacker: attacker.clone(),
        });
        let mut enemy = attacker.clone();
        enemy.conceal_resources();
        assert!(event.projected(&[enemy], PlayerNumber::Player2).is_none());
        let projected = event
            .projected(std::slice::from_ref(&victim), PlayerNumber::Player1)
            .fixture()?;
        let UnitLoss::ConcealedIndirectFire(concealed) = projected else {
            return Err("concealed gun retained an attacker portrait".into());
        };
        assert_eq!(concealed.unit.unit_id(), victim.unit_id());
        let visible_attacker = event
            .projected(&[victim.clone(), attacker], PlayerNumber::Player1)
            .fixture()?;
        let UnitLoss::Combat(known) = visible_attacker else {
            return Err("visible firing gun lost its identity".into());
        };
        assert!(known.attacker.resources().is_none());

        // Exercise the owning visibility projection, not just the event helper.
        board.units.first_mut().fixture()?.take_damage(16);
        let frame = TurnFrame {
            losses: vec![event],
            sabotages: Vec::new(),
            departures: Vec::new(),
            indirect_impacts: Vec::new(),
            shots: Vec::new(),
            units: board.units.clone(),
            depots: Vec::new(),
            supply_crates: Vec::new(),
            duration_ms: 180,
            visible_tiles: Vec::new(),
        };
        let resolution = TurnResolution {
            turn_number: 1,
            reports: Vec::new(),
            events: Vec::new(),
            frames: vec![frame],
        };
        for player in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let projected = visibility::observed_resolution(
                &board,
                player,
                &visibility::visible_tiles(&board, player),
                &resolution,
            );
            let losses = &projected.frames.first().fixture()?.losses;
            assert_eq!(
                losses.len(),
                if player == PlayerNumber::Player1 {
                    1
                } else {
                    0
                }
            );
        }
        Ok(())
    }

    #[test]
    fn graphql_loss_union_preserves_cause_and_carrier_payloads() -> TestResult<()> {
        #[derive(GraphQLObject)]
        struct Query {
            losses: Vec<UnitLoss>,
        }
        let mut board = scenario()?;
        let truck = board.units.first().fixture()?.clone();
        board.units.get_mut(1).fixture()?.board(truck.unit_id());
        board.units.first_mut().fixture()?.set_supplies_for_test(1);
        board.finish_turn_resources(1);
        board.finish_turn_resources(2);
        let settled = board.finish_turn_resources(3);
        let schema = juniper::RootNode::new(
            Query {
                losses: settled.losses,
            },
            juniper::EmptyMutation::<()>::new(),
            juniper::EmptySubscription::<()>::new(),
        );
        let (data, errors) = juniper::execute_sync(
            "{ losses { __typename ... on ExhaustedUnitLoss { unit { id } } ... on CarrierUnitLoss { unit { id } carrierLoss { __typename ... on ExhaustedUnitLoss { unit { id } } } } } }",
            None,
            &schema,
            &juniper::Variables::new(),
            &(),
        )?;
        assert!(errors.is_empty(), "{errors:?}");
        let data = serde_json::to_value(data)?;
        assert_eq!(
            data["losses"],
            serde_json::json!([
                {"__typename":"ExhaustedUnitLoss","unit":{"id":"1"}},
                {"__typename":"CarrierUnitLoss","unit":{"id":"2"},"carrierLoss":{"__typename":"ExhaustedUnitLoss","unit":{"id":"1"}}}
            ])
        );
        Ok(())
    }
}
