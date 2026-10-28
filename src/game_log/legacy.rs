//! One-time interpretation of version-one archives, which predate explicit loss events.
//! Live resolution and the client never use this compatibility path.
use crate::{
    scenario::Unit,
    turns::TurnResolution,
    unit_loss::{self, CarrierUnitLoss, DirectUnitLoss, ExhaustedUnitLoss, UnitLoss},
};
use std::collections::BTreeSet;

pub(super) fn restore_losses(resolution: &mut TurnResolution) {
    let mut previous = Vec::<Unit>::new();
    let mut presented = BTreeSet::new();
    for frame in &mut resolution.frames {
        let newly_dead: Vec<_> = frame
            .units
            .iter()
            .filter(|unit| unit.destroyed() && !presented.contains(&unit.unit_id()))
            .collect();
        let combat_losses = unit_loss::combat(&frame.shots, &previous);
        let direct: Vec<DirectUnitLoss> = newly_dead
            .iter()
            .filter_map(|unit| {
                if unit
                    .carrier_id()
                    .is_some_and(|carrier| newly_dead.iter().any(|dead| dead.unit_id() == carrier))
                {
                    return None;
                }
                if let Some(UnitLoss::Combat(loss)) = combat_losses
                    .iter()
                    .find(|loss| loss.unit().unit_id() == unit.unit_id())
                {
                    return Some(DirectUnitLoss::Combat(loss.clone()));
                }
                previous
                    .iter()
                    .find(|earlier| earlier.unit_id() == unit.unit_id() && !earlier.destroyed())
                    .map(|earlier| {
                        DirectUnitLoss::Exhaustion(ExhaustedUnitLoss {
                            unit: earlier.clone(),
                        })
                    })
            })
            .collect();
        frame.losses = newly_dead
            .iter()
            .filter_map(|unit| {
                if let Some(carrier_loss) = direct
                    .iter()
                    .find(|loss| unit.carrier_id() == Some(loss.unit().unit_id()))
                {
                    let earlier = previous
                        .iter()
                        .find(|earlier| earlier.unit_id() == unit.unit_id())?;
                    Some(UnitLoss::Carrier(CarrierUnitLoss {
                        unit: earlier.clone(),
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
            .collect();
        presented.extend(newly_dead.iter().map(|unit| unit.unit_id()));
        previous = frame.units.clone();
    }
}
