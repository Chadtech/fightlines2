//! Compare a carried freight slot with dropping it beside the truck's route.
use super::{distance, planned_destination};
use crate::{
    map::Coordinate,
    player_number::PlayerNumber,
    scenario::{ResourceKind, Scenario, Unit, UnitId, UnitKind},
    supplies,
    turns::{CrateUnloadInput, UnitOrderInput},
};
use std::collections::BTreeSet;

struct Recipient {
    unit: UnitId,
    destination: Coordinate,
    supply_shortage: i32,
    fuel_shortage: Option<i32>,
}

impl Recipient {
    fn shortage(&self, resource: ResourceKind) -> Option<i32> {
        match resource {
            ResourceKind::Supply => Some(self.supply_shortage),
            ResourceKind::Fuel => self.fuel_shortage,
        }
    }
}

struct UnloadValue {
    extra_demand: i32,
    lost_demand: bool,
    needful_allies: i32,
    nearest_enemy: i32,
    transport_berth: bool,
}

impl UnloadValue {
    fn score(&self) -> Option<i32> {
        // Ground freight is neutral. Keep current deliveries in range and
        // avoid placing stock where an observed enemy can use it immediately.
        let preserves_deliveries = !self.lost_demand && self.nearest_enemy > 1;
        let improves_delivery = self.transport_berth || self.extra_demand > 0;
        (preserves_deliveries && self.needful_allies > 0 && improves_delivery)
            .then_some(i32::from(self.transport_berth) * 40 + self.extra_demand)
    }
}

pub(super) fn plan_unloads(
    scenario: &Scenario,
    player: PlayerNumber,
    orders: &mut [UnitOrderInput],
) -> Result<(), &'static str> {
    let mut reserved = BTreeSet::new();
    let enemies: Vec<_> = scenario
        .units
        .iter()
        .filter(|unit| unit.player_number() != player && unit.is_alive())
        .filter_map(Unit::board_position)
        .collect();
    let recipients = scenario
        .units
        .iter()
        .filter(|ally| ally.player_number() == player && ally.is_alive())
        .map(|ally| recipient(scenario, orders, ally))
        .collect::<Result<Vec<_>, _>>()?;
    for truck in scenario.units.iter().filter(|unit| {
        unit.player_number() == player && unit.kind() == UnitKind::Truck && unit.is_alive()
    }) {
        if truck.supply_cargo.is_empty() || truck.board_position().is_none() {
            continue;
        }
        let order_index = orders
            .iter()
            .position(|order| order.unit_id == truck.id())
            .ok_or("the AI truck has no freight order.")?;
        let order = &orders[order_index];
        if order.load_crates.unwrap_or_default() > 0 || order.pickup_ground_freight.is_some() {
            continue;
        }
        let destination = planned_destination(orders, truck)?;
        let transport_berth = supplies::occupied_berths(scenario, truck)
            >= truck.cargo_capacity() as usize
            && super::transport::has_candidates(scenario, truck);
        let mut best = None;
        for exit in adjacent_squares(destination) {
            if reserved.contains(&exit)
                || !supplies::legal_crate_exit(scenario, player, destination, exit)
            {
                continue;
            }
            for (slot, cargo) in truck.supply_cargo.iter().enumerate() {
                if cargo.current <= 0 {
                    continue;
                }
                let mut facts = UnloadValue {
                    extra_demand: 0,
                    lost_demand: false,
                    needful_allies: 0,
                    nearest_enemy: enemies
                        .iter()
                        .map(|enemy| distance(*enemy, exit))
                        .min()
                        .unwrap_or(i32::MAX),
                    transport_berth,
                };
                for ally in recipients
                    .iter()
                    .filter(|ally| ally.unit != truck.unit_id())
                {
                    let Some(shortage) = ally.shortage(cargo.kind).filter(|shortage| *shortage > 0)
                    else {
                        continue;
                    };
                    let carry = supplies::adjacent(destination, ally.destination);
                    let unload = supplies::adjacent(exit, ally.destination);
                    facts.lost_demand |= carry && !unload;
                    if unload {
                        facts.needful_allies += 1;
                        if !carry {
                            facts.extra_demand += shortage;
                        }
                    }
                }
                if let Some(score) = facts.score()
                    && best.is_none_or(|(highest, _, _)| score > highest)
                {
                    best = Some((score, slot, exit));
                }
            }
        }
        if let Some((_, slot, exit)) = best {
            reserved.insert(exit);
            orders[order_index].crate_unloads =
                Some(vec![CrateUnloadInput::new(slot as i32, exit)]);
        }
    }
    Ok(())
}

fn recipient(
    scenario: &Scenario,
    orders: &[UnitOrderInput],
    ally: &Unit,
) -> Result<Recipient, &'static str> {
    let order = orders
        .iter()
        .find(|order| order.unit_id == ally.id())
        .ok_or("the AI freight recipient has no movement order.")?;
    let path: Vec<_> = order
        .path
        .iter()
        .map(|tile| Coordinate::new(tile.x as u16, tile.y as u16))
        .collect();
    let mut destination = path
        .last()
        .copied()
        .ok_or("the AI freight recipient has no destination.")?;
    let supply = ally.supplies();
    let mut movement_supplies = supply.movement_cost(&scenario.map, &path);
    if let Some(carrier) = ally.carrier_id() {
        let carrier = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == carrier)
            .ok_or("the AI freight recipient has no carrier.")?;
        let carrier_order = orders
            .iter()
            .find(|order| order.unit_id == carrier.id())
            .ok_or("the AI freight carrier has no movement order.")?;
        if let Some(exit) = carrier_order
            .unloads
            .iter()
            .flatten()
            .find(|exit| exit.is_for(ally.unit_id()))
        {
            let exit = exit.destination_coordinate()?;
            if ally.kind() == UnitKind::FieldGun {
                destination = exit;
            }
            movement_supplies += supply.movement_cost(&scenario.map, &[exit, exit]);
        } else {
            destination = planned_destination(orders, carrier)?;
        }
    }
    let provisions_after = supply.current() - movement_supplies;
    let supply_shortage = shortage_percent(provisions_after, supply.maximum());
    let fuel_shortage = ally.fuel().map(|fuel| {
        let passengers = scenario.passenger_count(ally.unit_id());
        let movement_cost = ally.fuel_movement_cost(&scenario.map, &path, passengers);
        shortage_percent(fuel.current - movement_cost, fuel.maximum)
    });
    Ok(Recipient {
        unit: ally.unit_id(),
        destination,
        supply_shortage,
        fuel_shortage,
    })
}

fn shortage_percent(current: i32, maximum: i32) -> i32 {
    // Ignore routine top-offs when deciding whether to leave stock behind.
    (100 - current.max(0) * 100 / maximum - 10).max(0)
}

fn adjacent_squares(origin: Coordinate) -> impl Iterator<Item = Coordinate> {
    [
        (origin.x() - 1, origin.y()),
        (origin.x() + 1, origin.y()),
        (origin.x(), origin.y() - 1),
        (origin.x(), origin.y() + 1),
    ]
    .into_iter()
    .filter_map(|(x, y)| {
        Some(Coordinate::new(
            u16::try_from(x).ok()?,
            u16::try_from(y).ok()?,
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        ai::{hold, logistics},
        map_definition::MapDefinition,
        supplies::{CargoStock, GroundSupplyCrate},
        test_support::{FixtureValue, TestResult},
        turns::Turns,
    };

    fn fixture() -> TestResult<Scenario> {
        let mut scenario = MapDefinition::parse(r#"{
            "width": 9, "height": 3, "theme": "GreenForest", "features": [], "depots": [],
            "units": [
                {"id": 1, "position": {"x": 1, "y": 1}, "playerNumber": "Player1", "kind": "Truck"},
                {"id": 2, "position": {"x": 3, "y": 1}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 3, "position": {"x": 8, "y": 2}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        let truck = scenario.units.first_mut().fixture()?;
        truck.set_fuel_for_test(0);
        truck
            .supply_cargo
            .push(CargoStock::new(ResourceKind::Supply, 256));
        scenario
            .units
            .get_mut(1)
            .fixture()?
            .set_supplies_for_test(16);
        Ok(scenario)
    }

    fn holds(scenario: &Scenario, player: PlayerNumber) -> TestResult<Vec<UnitOrderInput>> {
        scenario
            .units
            .iter()
            .filter(|unit| unit.player_number() == player)
            .map(|unit| Ok(hold(unit, unit.board_position().fixture()?)))
            .collect()
    }

    #[test]
    fn stranded_truck_can_deliver_provisions_by_unloading() -> TestResult {
        let mut scenario = fixture()?;
        let player = PlayerNumber::Player1;
        let mut orders = holds(&scenario, player)?;
        logistics::support(&scenario, player, &mut orders)?;
        assert!(orders.first().fixture()?.crate_unloads.is_none());

        logistics::support_with_freight(&scenario, player, &mut orders, true)?;
        let order = orders.first().fixture()?;
        assert_eq!(order.path.len(), 1);
        let unload = order.crate_unloads.as_ref().fixture()?.first().fixture()?;
        assert_eq!((unload.destination.x, unload.destination.y), (2, 1));
        let opponent = holds(&scenario, PlayerNumber::Player2)?;
        let mut turns = Turns::default();
        turns.submit(&mut scenario, player, 1, orders)?;
        turns.submit(&mut scenario, PlayerNumber::Player2, 1, opponent)?;
        let infantry = scenario.units.get(1).fixture()?;
        assert_eq!(
            infantry.supplies().current(),
            infantry.supplies().maximum() - infantry.supplies().upkeep_per_turn()
        );
        assert!(scenario.units.first().fixture()?.supply_cargo.is_empty());
        assert_eq!(
            scenario.supply_crates.first().fixture()?.position,
            Coordinate::new(2, 1)
        );
        Ok(())
    }

    #[test]
    fn skips_the_only_reaching_exit_if_occupied_or_enemy_accessible() -> TestResult {
        let player = PlayerNumber::Player1;
        for blocked_by_freight in [true, false] {
            let mut scenario = fixture()?;
            if blocked_by_freight {
                scenario.supply_crates.push(GroundSupplyCrate {
                    position: Coordinate::new(2, 1),
                    stock: CargoStock::new(ResourceKind::Fuel, 512),
                });
            } else {
                scenario
                    .units
                    .get_mut(2)
                    .fixture()?
                    .move_to(Coordinate::new(2, 2));
            }
            let mut orders = holds(&scenario, player)?;
            plan_unloads(&scenario, player, &mut orders)?;
            assert!(orders.first().fixture()?.crate_unloads.is_none());
        }
        Ok(())
    }

    #[test]
    fn unloads_to_free_a_berth_while_keeping_delivery_in_range() -> TestResult {
        let mut scenario = fixture()?;
        let player = PlayerNumber::Player1;
        scenario
            .units
            .get_mut(1)
            .fixture()?
            .move_to(Coordinate::new(2, 1));
        scenario
            .units
            .first_mut()
            .fixture()?
            .supply_cargo
            .push(CargoStock::new(ResourceKind::Supply, 100));
        let mut orders = holds(&scenario, player)?;
        plan_unloads(&scenario, player, &mut orders)?;
        assert!(orders.first().fixture()?.crate_unloads.is_some());
        Ok(())
    }
}
