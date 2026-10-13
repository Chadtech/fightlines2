//! Finite stock, explicit crate cargo, and automatic end-of-turn replenishment.
use crate::{
    map::Coordinate,
    scenario::{PlayerNumber, Scenario, Unit, UnitId, UnitKind},
};
use juniper::GraphQLObject;

/// Default capacities for newly created sources; existing stocks retain their own maximum.
#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLObject)]
pub struct SupplyRules {
    pub depot_capacity: i32,
    pub crate_capacity: i32,
}

pub fn rules() -> SupplyRules {
    SupplyRules {
        depot_capacity: 256,
        crate_capacity: 64,
    }
}

#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct SupplyStock {
    pub current: i32,
    pub maximum: i32,
}

impl SupplyStock {
    pub fn depot() -> Self {
        Self {
            current: rules().depot_capacity,
            maximum: rules().depot_capacity,
        }
    }

    fn crate_stock(current: i32) -> Self {
        Self {
            current,
            maximum: rules().crate_capacity,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, GraphQLObject)]
pub struct GroundSupplyCrate {
    pub position: Coordinate,
    pub stock: SupplyStock,
}

#[derive(Clone, Debug, Default)]
pub enum SupplyOrder {
    #[default]
    None,
    LoadCrates(usize),
    UnloadCrates(Vec<CrateUnload>),
}

impl SupplyOrder {
    pub fn loading_count(&self) -> usize {
        match self {
            Self::LoadCrates(count) => *count,
            Self::None | Self::UnloadCrates(_) => 0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CrateUnload {
    pub cargo_index: usize,
    pub destination: Coordinate,
}

pub fn adjacent(origin: Coordinate, destination: Coordinate) -> bool {
    (origin.x() - destination.x()).abs() + (origin.y() - destination.y()).abs() <= 1
}

pub fn occupied_berths(scenario: &Scenario, truck: &Unit) -> usize {
    truck.supply_cargo.len()
        + scenario
            .units
            .iter()
            .filter(|unit| unit.carrier_id() == Some(truck.unit_id()))
            .count()
}

pub fn legal_crate_exit(
    scenario: &Scenario,
    side: PlayerNumber,
    origin: Coordinate,
    exit: Coordinate,
) -> bool {
    origin != exit
        && adjacent(origin, exit)
        && scenario.map.contains(exit)
        && !scenario.units.iter().any(|unit| {
            unit.is_alive() && unit.side() != side && unit.board_position() == Some(exit)
        })
        && !scenario
            .supply_crates
            .iter()
            .any(|supply_crate| supply_crate.position == exit)
}

/// Competing orders alternate their side priority each turn. Actual positions
/// and stock decide success; blocked deliveries leave the cargo aboard.
pub fn resolve_orders(scenario: &mut Scenario, orders: &[(UnitId, SupplyOrder)], turn_number: i32) {
    let mut scheduled = orders.to_vec();
    scheduled.sort_by_key(|(id, _)| {
        let side = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == *id)
            .map(Unit::side);
        let preferred = if turn_number % 2 == 1 {
            PlayerNumber::Player1
        } else {
            PlayerNumber::Player2
        };
        (side != Some(preferred), *id)
    });
    for (id, order) in scheduled {
        let Some(index) = scenario.units.iter().position(|unit| {
            unit.unit_id() == id && unit.is_alive() && unit.kind() == UnitKind::Truck
        }) else {
            continue;
        };
        let Some(origin) = scenario.units[index].board_position() else {
            continue;
        };
        let room = (scenario.units[index].cargo_capacity() as usize)
            .saturating_sub(occupied_berths(scenario, &scenario.units[index]));
        // Ground crates are neutral freight. Preserve the remaining stock when
        // a truck ends its movement on one, sharing berths with passengers.
        if room > 0
            && let Some(crate_index) = scenario
                .supply_crates
                .iter()
                .position(|supply_crate| supply_crate.position == origin)
        {
            let supply_crate = scenario.supply_crates.remove(crate_index);
            scenario.units[index].supply_cargo.push(supply_crate.stock);
        }
        let room = (scenario.units[index].cargo_capacity() as usize)
            .saturating_sub(occupied_berths(scenario, &scenario.units[index]));
        for _ in 0..order.loading_count().min(room) {
            let Some(depot) = scenario
                .depots
                .iter_mut()
                .find(|depot| origin == depot.position && depot.stock.current > 0)
            else {
                break;
            };
            let amount = depot.stock.current.min(rules().crate_capacity);
            depot.stock.current -= amount;
            scenario.units[index]
                .supply_cargo
                .push(SupplyStock::crate_stock(amount));
        }
        // Remove from the highest slot first so input slots keep their identity.
        let mut unloads = match order {
            SupplyOrder::UnloadCrates(unloads) => unloads,
            SupplyOrder::None | SupplyOrder::LoadCrates(_) => Vec::new(),
        };
        unloads.sort_by_key(|unload| std::cmp::Reverse(unload.cargo_index));
        for unload in unloads {
            if unload.cargo_index < scenario.units[index].supply_cargo.len()
                && legal_crate_exit(
                    scenario,
                    scenario.units[index].side(),
                    origin,
                    unload.destination,
                )
            {
                let stock = scenario.units[index]
                    .supply_cargo
                    .remove(unload.cargo_index);
                scenario.supply_crates.push(GroundSupplyCrate {
                    position: unload.destination,
                    stock,
                });
            }
        }
    }
}

/// Stock moves only to recipients, never between supply sources. Every recipient
/// is filled to its own capacity, even when several sources overlap.
pub fn replenish(scenario: &mut Scenario, turn_number: i32) {
    for index in 0..scenario.depots.len() {
        let origin = scenario.depots[index].position;
        let mut stock = scenario.depots[index].stock.clone();
        distribute(scenario, origin, &mut stock, turn_number);
        scenario.depots[index].stock = stock;
    }
    for index in 0..scenario.supply_crates.len() {
        let origin = scenario.supply_crates[index].position;
        let mut stock = scenario.supply_crates[index].stock.clone();
        distribute(scenario, origin, &mut stock, turn_number);
        scenario.supply_crates[index].stock = stock;
    }
    let trucks: Vec<_> = scenario
        .units
        .iter()
        .filter(|unit| unit.is_alive() && unit.kind() == UnitKind::Truck)
        .map(Unit::unit_id)
        .collect();
    for id in trucks {
        let Some(index) = scenario.units.iter().position(|unit| unit.unit_id() == id) else {
            continue;
        };
        let Some(origin) = scenario.units[index].board_position() else {
            continue;
        };
        for slot in 0..scenario.units[index].supply_cargo.len() {
            let mut stock = scenario.units[index].supply_cargo[slot].clone();
            distribute(scenario, origin, &mut stock, turn_number);
            scenario.units[index].supply_cargo[slot] = stock;
        }
        scenario.units[index]
            .supply_cargo
            .retain(|stock| stock.current > 0);
    }
    scenario
        .supply_crates
        .retain(|supply_crate| supply_crate.stock.current > 0);
}

fn distribute(
    scenario: &mut Scenario,
    origin: Coordinate,
    stock: &mut SupplyStock,
    turn_number: i32,
) {
    let mut recipients: Vec<_> = scenario
        .units
        .iter()
        .filter(|unit| {
            unit.is_alive()
                && unit.carrier_id().is_none_or(|id| {
                    scenario
                        .units
                        .iter()
                        .any(|carrier| carrier.unit_id() == id && carrier.is_alive())
                })
                && scenario
                    .physical_position(unit)
                    .is_some_and(|position| adjacent(origin, position))
        })
        .map(Unit::unit_id)
        .collect();
    recipients.sort();
    if !recipients.is_empty() {
        let offset = (turn_number.max(1) as usize - 1) % recipients.len();
        // Deterministic fairness: rotate first access to scarce stock each turn.
        recipients.rotate_left(offset);
    }
    while stock.current > 0 {
        let mut delivered = false;
        for id in &recipients {
            if stock.current == 0 {
                break;
            }
            let Some(unit) = scenario.units.iter_mut().find(|unit| unit.unit_id() == *id) else {
                continue;
            };
            if unit.supplies().current() < unit.supplies().maximum() {
                unit.receive_supplies(1);
                stock.current -= 1;
                delivered = true;
            }
        }
        if !delivered {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::Map,
        scenario::Depot,
        test_support::{FixtureValue, TestResult},
    };

    fn board() -> TestResult<Scenario> {
        let mut board = Scenario::supply_point().fixture()?;
        board.map = Map::from_ascii(".......\n.......\n.......").fixture()?;
        board.depots.clear();
        board
            .units
            .retain(|unit| ["1", "2", "4", "9"].contains(&unit.id().as_str()));
        for (index, unit) in board.units.iter_mut().enumerate() {
            unit.move_to(Coordinate::new(index as u16, 1));
            unit.set_supplies_for_test(10);
        }
        Ok(board)
    }

    #[test]
    fn limited_stock_is_shared_without_side_ownership_or_overfill() -> TestResult<()> {
        let mut board = board()?;
        board
            .units
            .retain(|unit| unit.id() == "1" || unit.id() == "9");
        board
            .units
            .get_mut(0)
            .fixture()?
            .move_to(Coordinate::new(2, 1));
        board
            .units
            .get_mut(1)
            .fixture()?
            .move_to(Coordinate::new(4, 1));
        board.supply_crates.push(GroundSupplyCrate {
            position: Coordinate::new(3, 1),
            stock: SupplyStock::crate_stock(5),
        });
        replenish(&mut board, 1);
        assert_eq!(board.units.get_mut(0).fixture()?.supplies().current(), 13);
        assert_eq!(board.units.get_mut(1).fixture()?.supplies().current(), 12);
        assert!(board.supply_crates.is_empty());
        board.supply_crates.push(GroundSupplyCrate {
            position: Coordinate::new(3, 1),
            stock: SupplyStock::crate_stock(5),
        });
        replenish(&mut board, 2);
        assert_eq!(board.units.get_mut(0).fixture()?.supplies().current(), 15);
        assert_eq!(board.units.get_mut(1).fixture()?.supplies().current(), 15);
        Ok(())
    }

    #[test]
    fn overlapping_sources_fill_capacity_and_do_not_refill_each_other() -> TestResult<()> {
        let mut board = board()?;
        board.units.retain(|unit| unit.id() == "1");
        board.supply_crates = vec![
            GroundSupplyCrate {
                position: Coordinate::new(0, 0),
                stock: SupplyStock::crate_stock(64),
            },
            GroundSupplyCrate {
                position: Coordinate::new(0, 2),
                stock: SupplyStock::crate_stock(2),
            },
        ];
        replenish(&mut board, 1);
        assert_eq!(board.units.get_mut(0).fixture()?.supplies().current(), 64);
        assert_eq!(board.supply_crates.get_mut(0).fixture()?.stock.current, 10);
        assert_eq!(board.supply_crates.get_mut(1).fixture()?.stock.current, 2);
        board.units.get_mut(0).fixture()?.set_supplies_for_test(63);
        replenish(&mut board, 2);
        assert_eq!(board.units.get_mut(0).fixture()?.supplies().current(), 64);
        assert_eq!(board.supply_crates.get_mut(0).fixture()?.stock.current, 9);
        Ok(())
    }

    #[test]
    fn depleted_sources_combine_to_fill_a_unit_in_one_turn() -> TestResult<()> {
        let mut board = board()?;
        board.units.retain(|unit| unit.id() == "1");
        board.supply_crates = vec![
            GroundSupplyCrate {
                position: Coordinate::new(0, 0),
                stock: SupplyStock::crate_stock(20),
            },
            GroundSupplyCrate {
                position: Coordinate::new(0, 2),
                stock: SupplyStock::crate_stock(40),
            },
        ];
        replenish(&mut board, 1);
        assert_eq!(board.units.first().fixture()?.supplies().current(), 64);
        assert_eq!(board.supply_crates.len(), 1);
        assert_eq!(board.supply_crates.first().fixture()?.stock.current, 6);
        Ok(())
    }

    #[test]
    fn truck_crates_supply_both_sides_and_passengers() -> TestResult<()> {
        let mut board = board()?;
        let truck_id = UnitId::parse("4").fixture()?;
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "1")
            .fixture()?
            .board(truck_id);
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "2")
            .fixture()?
            .move_to(Coordinate::new(2, 0));
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "9")
            .fixture()?
            .move_to(Coordinate::new(3, 1));
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "4")
            .fixture()?
            .supply_cargo
            .push(SupplyStock::crate_stock(64));
        replenish(&mut board, 1);
        assert_eq!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "9")
                .fixture()?
                .supplies()
                .current(),
            26
        );
        assert_eq!(
            board
                .units
                .iter()
                .filter(|unit| unit.side() == PlayerNumber::Player1)
                .map(|unit| unit.supplies().current() - 10)
                .sum::<i32>(),
            48
        );
        assert!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "4")
                .fixture()?
                .supply_cargo
                .is_empty()
        );
        Ok(())
    }

    #[test]
    fn depot_rescues_exhaustion_but_never_resurrects_combat_deaths_or_loads_cargo() -> TestResult<()>
    {
        let mut board = board()?;
        board.depots.push(Depot {
            position: Coordinate::new(1, 1),
            stock: SupplyStock::depot(),
            stock_visible: true,
        });
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "1")
            .fixture()?
            .set_supplies_for_test(1);
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "2")
            .fixture()?
            .take_damage(16);
        board.finish_turn_resources(1);
        assert!(
            board
                .units
                .iter()
                .any(|unit| unit.id() == "1" && unit.supplies().current() == 63)
        );
        assert!(!board.units.iter().any(|unit| unit.id() == "2"));
        assert!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "4")
                .fixture()?
                .supply_cargo
                .is_empty()
        );
        assert_eq!(board.depots.get_mut(0).fixture()?.stock.current, 171);
        Ok(())
    }

    #[test]
    fn loading_uses_finite_stock_and_shared_berths_then_unloading_keeps_quantity() -> TestResult<()>
    {
        let mut board = board()?;
        let truck_id = UnitId::parse("4").fixture()?;
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "1")
            .fixture()?
            .board(truck_id);
        board.depots.push(Depot {
            position: Coordinate::new(2, 1),
            stock: SupplyStock::crate_stock(20),
            stock_visible: true,
        });
        resolve_orders(&mut board, &[(truck_id, SupplyOrder::LoadCrates(2))], 1);
        assert_eq!(board.depots.get_mut(0).fixture()?.stock.current, 0);
        let truck = board.units.iter().find(|unit| unit.id() == "4").fixture()?;
        assert_eq!(occupied_berths(&board, truck), 2);
        assert_eq!(truck.supply_cargo.first().fixture()?.current, 20);
        resolve_orders(
            &mut board,
            &[(
                truck_id,
                SupplyOrder::UnloadCrates(vec![CrateUnload {
                    cargo_index: 0,
                    destination: Coordinate::new(2, 2),
                }]),
            )],
            2,
        );
        assert_eq!(board.supply_crates.get_mut(0).fixture()?.stock.current, 20);
        assert!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "4")
                .fixture()?
                .supply_cargo
                .is_empty()
        );
        Ok(())
    }

    #[test]
    fn either_side_can_collect_neutral_ground_crates_without_refilling_stock() -> TestResult<()> {
        for side in [PlayerNumber::Player1, PlayerNumber::Player2] {
            let mut board = Scenario::supply_point().fixture()?;
            board
                .units
                .retain(|unit| unit.kind() == UnitKind::Truck && unit.side() == side);
            let truck = board.units.first_mut().fixture()?;
            let id = truck.unit_id();
            let position = Coordinate::new(8, 8);
            truck.move_to(position);
            board.supply_crates.push(GroundSupplyCrate {
                position,
                stock: SupplyStock::crate_stock(23),
            });
            resolve_orders(&mut board, &[(id, SupplyOrder::None)], 1);
            assert!(board.supply_crates.is_empty());
            assert_eq!(
                board
                    .units
                    .first()
                    .fixture()?
                    .supply_cargo
                    .first()
                    .fixture()?
                    .current,
                23
            );
        }
        Ok(())
    }

    #[test]
    fn full_truck_leaves_ground_crate_and_adjacent_truck_cannot_load_depot() -> TestResult<()> {
        let mut board = board()?;
        let truck = board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "4")
            .fixture()?;
        let id = truck.unit_id();
        let position = truck.board_position().fixture()?;
        truck.supply_cargo = vec![SupplyStock::crate_stock(12), SupplyStock::crate_stock(34)];
        board.supply_crates.push(GroundSupplyCrate {
            position,
            stock: SupplyStock::crate_stock(23),
        });
        resolve_orders(&mut board, &[(id, SupplyOrder::None)], 1);
        assert_eq!(board.supply_crates.first().fixture()?.stock.current, 23);
        board
            .units
            .iter_mut()
            .find(|unit| unit.unit_id() == id)
            .fixture()?
            .supply_cargo
            .clear();
        board.supply_crates.clear();
        board.depots.push(Depot {
            position: Coordinate::new(2, 0),
            stock: SupplyStock::depot(),
            stock_visible: true,
        });
        resolve_orders(&mut board, &[(id, SupplyOrder::LoadCrates(1))], 1);
        assert!(
            board
                .units
                .iter()
                .find(|unit| unit.unit_id() == id)
                .fixture()?
                .supply_cargo
                .is_empty()
        );
        assert_eq!(board.depots.first().fixture()?.stock.current, 256);
        Ok(())
    }

    #[test]
    fn blocked_exits_preserve_cargo_and_destroyed_trucks_cannot_deliver() -> TestResult<()> {
        let mut board = board()?;
        let truck_id = UnitId::parse("4").fixture()?;
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "4")
            .fixture()?
            .supply_cargo
            .push(SupplyStock::crate_stock(64));
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "2")
            .fixture()?
            .move_to(Coordinate::new(6, 2));
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "9")
            .fixture()?
            .move_to(Coordinate::new(1, 1));
        resolve_orders(
            &mut board,
            &[(
                truck_id,
                SupplyOrder::UnloadCrates(vec![CrateUnload {
                    cargo_index: 0,
                    destination: Coordinate::new(1, 1),
                }]),
            )],
            1,
        );
        assert!(board.supply_crates.is_empty());
        assert_eq!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "4")
                .fixture()?
                .supply_cargo
                .len(),
            1
        );
        board
            .units
            .iter_mut()
            .find(|unit| unit.id() == "4")
            .fixture()?
            .take_damage(16);
        replenish(&mut board, 1);
        assert_eq!(
            board
                .units
                .iter()
                .find(|unit| unit.id() == "2")
                .fixture()?
                .supplies()
                .current(),
            10
        );
        Ok(())
    }
}

#[cfg(test)]
mod visibility_tests {
    use super::*;
    use crate::{
        map::Map,
        scenario::Depot,
        test_support::{FixtureValue, TestResult},
        visibility,
    };

    #[test]
    fn unseen_depot_stock_and_ground_crates_are_concealed() -> TestResult<()> {
        let mut board = Scenario::supply_point().fixture()?;
        board.map = Map::from_ascii("....................").fixture()?;
        board.units.retain(|unit| unit.id() == "4");
        board
            .units
            .first_mut()
            .fixture()?
            .move_to(Coordinate::new(0, 0));
        board.depots = vec![
            Depot {
                position: Coordinate::new(1, 0),
                stock: SupplyStock::depot(),
                stock_visible: true,
            },
            Depot {
                position: Coordinate::new(19, 0),
                stock: SupplyStock::depot(),
                stock_visible: true,
            },
        ];
        board.supply_crates = vec![
            GroundSupplyCrate {
                position: Coordinate::new(1, 0),
                stock: SupplyStock::crate_stock(64),
            },
            GroundSupplyCrate {
                position: Coordinate::new(19, 0),
                stock: SupplyStock::crate_stock(64),
            },
        ];
        let visible = visibility::visible_tiles(&board, PlayerNumber::Player1);
        let observed = visibility::observed_scenario(&board, PlayerNumber::Player1, &visible);
        assert!(observed.depots.first().fixture()?.stock_visible);
        assert!(!observed.depots.last().fixture()?.stock_visible);
        assert_eq!(observed.supply_crates.len(), 1);
        assert_eq!(board.supply_crates.len(), 2);
        assert!(board.depots.iter().all(|depot| depot.stock_visible));
        Ok(())
    }
}
