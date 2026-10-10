use crate::{
    map::Coordinate,
    movement,
    scenario::{Direction, Scenario, Side, UnitId},
};
use juniper::{GraphQLEnum, GraphQLInputObject, GraphQLObject, graphql_object};
use std::collections::BTreeSet;

#[derive(GraphQLInputObject)]
pub struct CoordinateInput {
    x: i32,
    y: i32,
}

#[derive(GraphQLInputObject)]
pub struct MoveOrderInput {
    unit_id: String,
    /// Includes the starting square. A single square is an explicit hold order.
    path: Vec<CoordinateInput>,
}

#[derive(Clone, Debug)]
pub struct MoveOrder {
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum TurnEventKind {
    Move,
    Hold,
    DestinationConflict,
}

/// Ordered presentation events. Future attacks and interruptions belong here;
/// clients replay these outcomes rather than reimplementing resolution rules.
#[derive(Clone, Debug)]
pub struct TurnEvent {
    pub initial_direction: Option<Direction>,
    pub kind: TurnEventKind,
    pub unit_id: UnitId,
    pub path: Vec<Coordinate>,
}

#[graphql_object]
impl TurnEvent {
    fn initial_direction(&self) -> Option<Direction> {
        self.initial_direction
    }
    fn kind(&self) -> TurnEventKind {
        self.kind
    }
    fn unit_id(&self) -> String {
        self.unit_id.to_string()
    }
    fn path(&self) -> Vec<Coordinate> {
        self.path.clone()
    }
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct TurnResolution {
    pub turn_number: i32,
    pub events: Vec<TurnEvent>,
}

pub struct Turns {
    pub number: i32,
    pub orders: [Option<Vec<MoveOrder>>; 2],
    pub last_resolution: Option<TurnResolution>,
}

impl Default for Turns {
    fn default() -> Self {
        Self {
            number: 1,
            orders: [None, None],
            last_resolution: None,
        }
    }
}

pub fn side_index(side: Side) -> usize {
    match side {
        Side::West => 0,
        Side::East => 1,
    }
}

pub fn validate(
    scenario: &Scenario,
    side: Side,
    inputs: Vec<MoveOrderInput>,
) -> Result<Vec<MoveOrder>, &'static str> {
    let own_count = scenario
        .units
        .iter()
        .filter(|unit| unit.side() == side)
        .count();
    if inputs.len() != own_count {
        return Err("set a move or hold order for every unit before submitting.");
    }
    let mut unit_ids = BTreeSet::new();
    let mut destinations = BTreeSet::new();
    let mut orders = Vec::new();
    for input in inputs {
        let unit_id = UnitId::parse(&input.unit_id).ok_or("invalid unit id.")?;
        let unit = scenario
            .units
            .iter()
            .find(|unit| unit.unit_id() == unit_id && unit.side() == side)
            .ok_or("you can only submit orders for your own units.")?;
        if !unit_ids.insert(unit_id) {
            return Err("each unit must have exactly one order.");
        }
        let rule = movement::rules()
            .into_iter()
            .find(|rule| rule.kind == unit.kind())
            .unwrap();
        if input.path.is_empty() || input.path.len() > (rule.budget + 1) as usize {
            return Err("invalid movement path length.");
        }
        let path: Vec<_> = input
            .path
            .into_iter()
            .map(|position| {
                let x = u16::try_from(position.x).map_err(|_| "movement is outside the map.")?;
                let y = u16::try_from(position.y).map_err(|_| "movement is outside the map.")?;
                let coordinate = Coordinate::new(x, y);
                scenario
                    .map
                    .tile_at(coordinate)
                    .ok_or("movement is outside the map.")?;
                Ok(coordinate)
            })
            .collect::<Result<_, &str>>()?;
        if path[0] != unit.position() {
            return Err("movement must start at the unit's current position.");
        }
        let mut visited = BTreeSet::from([path[0]]);
        let mut cost = 0;
        for step in path.windows(2) {
            let adjacent =
                (step[0].x() - step[1].x()).abs() + (step[0].y() - step[1].y()).abs() == 1;
            if !adjacent || !visited.insert(step[1]) {
                return Err("movement must follow a path of distinct adjacent squares.");
            }
            if scenario
                .units
                .iter()
                .any(|other| other.side() != side && other.position() == step[1])
            {
                return Err("enemy units block movement.");
            }
            let terrain = scenario.map.tile_at(step[1]).unwrap();
            cost += rule
                .terrain_costs
                .iter()
                .find(|entry| entry.terrain == terrain)
                .ok_or("this terrain cannot be crossed.")?
                .cost;
        }
        if cost > rule.budget {
            return Err("movement exceeds the unit's budget.");
        }
        if let Some(fuel) = unit.fuel()
            && path.len() - 1 > fuel.current as usize
        {
            return Err("movement exceeds the unit's available fuel.");
        }
        if !unit.supplies().can_move(path.len() - 1) {
            return Err("movement exceeds supplies available after upkeep.");
        }
        let destination = *path.last().unwrap();
        if scenario
            .units
            .iter()
            .any(|other| other.unit_id() != unit.unit_id() && other.position() == destination)
        {
            return Err("occupied squares cannot be destinations.");
        }
        if !destinations.insert(destination) {
            return Err("units must have different destinations.");
        }
        orders.push(MoveOrder { unit_id, path });
    }
    Ok(orders)
}

impl Turns {
    pub fn submit(
        &mut self,
        scenario: &mut Scenario,
        side: Side,
        number: i32,
        inputs: Vec<MoveOrderInput>,
    ) -> Result<(), &'static str> {
        if number != self.number {
            return Err("the turn has changed. refresh before submitting.");
        }
        let index = side_index(side);
        // A retry after a lost response cannot alter or duplicate locked orders.
        if self.orders[index].is_some() {
            return Ok(());
        }
        self.orders[index] = Some(validate(scenario, side, inputs)?);
        if self.orders.iter().all(Option::is_some) {
            let mut orders: Vec<_> = self
                .orders
                .iter_mut()
                .flat_map(|orders| orders.take().unwrap())
                .collect();
            // Stable unit order, independent of which player's request arrives first.
            orders.sort_by_key(|order| order.unit_id);
            let events = orders
                .iter()
                .map(|order| {
                    let destination = *order.path.last().unwrap();
                    let conflict = orders.iter().any(|other| {
                        other.unit_id != order.unit_id && other.path.last() == Some(&destination)
                    });
                    let kind = if conflict {
                        TurnEventKind::DestinationConflict
                    } else if order.path.len() == 1 {
                        TurnEventKind::Hold
                    } else {
                        TurnEventKind::Move
                    };
                    let path = if conflict {
                        vec![order.path[0]]
                    } else {
                        order.path.clone()
                    };
                    let initial_direction = scenario
                        .units
                        .iter()
                        .find(|unit| unit.unit_id() == order.unit_id)
                        .unwrap()
                        .direction();
                    TurnEvent {
                        initial_direction,
                        kind,
                        unit_id: order.unit_id,
                        path,
                    }
                })
                .collect::<Vec<_>>();
            for event in &events {
                scenario
                    .units
                    .iter_mut()
                    .find(|unit| unit.unit_id() == event.unit_id)
                    .unwrap()
                    .follow_path(&event.path);
            }
            scenario.finish_turn_resources();
            self.last_resolution = Some(TurnResolution {
                turn_number: self.number,
                events,
            });
            self.number += 1;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn holds(scenario: &Scenario, side: Side) -> Vec<MoveOrderInput> {
        scenario
            .units
            .iter()
            .filter(|unit| unit.side() == side)
            .map(|unit| MoveOrderInput {
                unit_id: unit.id(),
                path: vec![CoordinateInput {
                    x: unit.position().x(),
                    y: unit.position().y(),
                }],
            })
            .collect()
    }

    fn set_path(orders: &mut [MoveOrderInput], id: &str, path: &[(i32, i32)]) {
        orders
            .iter_mut()
            .find(|order| order.unit_id == id)
            .unwrap()
            .path = path
            .iter()
            .map(|&(x, y)| CoordinateInput { x, y })
            .collect();
    }

    fn vehicle<'a>(scenario: &'a mut Scenario, id: &str) -> &'a mut crate::scenario::Unit {
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == id)
            .unwrap()
    }

    fn resolve_holds(scenario: &mut Scenario, turns: &mut Turns) {
        let west = holds(scenario, Side::West);
        let east = holds(scenario, Side::East);
        let number = turns.number;
        turns.submit(scenario, Side::West, number, west).unwrap();
        turns.submit(scenario, Side::East, number, east).unwrap();
    }

    #[test]
    fn supplies_charge_upkeep_once_and_walking_movement_only() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        for _ in 0..61 {
            resolve_holds(&mut scenario, &mut turns);
        }
        let number = turns.number;
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut west, "13", &[(4, 9), (4, 10)]);
        set_path(&mut west, "4", &[(2, 7), (2, 6)]);
        set_path(&mut west, "11", &[(4, 8), (5, 8)]);
        turns
            .submit(&mut scenario, Side::West, number, west)
            .unwrap();
        turns
            .submit(&mut scenario, Side::West, number, vec![])
            .unwrap();
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.supplies().current() == 3)
        );
        let east = holds(&scenario, Side::East);
        turns
            .submit(&mut scenario, Side::East, number, east)
            .unwrap();
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 0);
        assert_eq!(vehicle(&mut scenario, "13").supplies().current(), 1);
        for id in ["2", "4", "11", "6"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 2);
        }
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 63);
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 63);
    }

    #[test]
    fn supplies_reserve_upkeep_reject_movement_and_stop_at_zero() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        for _ in 0..63 {
            resolve_holds(&mut scenario, &mut turns);
        }
        let number = turns.number;
        for (id, path) in [("1", vec![(3, 7), (3, 6)]), ("12", vec![(4, 7), (4, 6)])] {
            let mut west = holds(&scenario, Side::West);
            set_path(&mut west, id, &path);
            assert_eq!(
                turns.submit(&mut scenario, Side::West, number, west),
                Err("movement exceeds supplies available after upkeep.")
            );
            assert!(turns.orders[0].is_none());
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 1);
        }
        resolve_holds(&mut scenario, &mut turns);
        resolve_holds(&mut scenario, &mut turns);
        assert!(
            scenario
                .units
                .iter()
                .all(|unit| unit.supplies().current() == 0)
        );
    }

    #[test]
    fn depots_do_not_replenish_supplies() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "4").move_to(Coordinate::new(14, 8));
        vehicle(&mut scenario, "9").move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "5").move_to(Coordinate::new(8, 8));
        let mut turns = Turns::default();
        resolve_holds(&mut scenario, &mut turns);
        for id in ["4", "5", "9"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 63);
        }
        vehicle(&mut scenario, "4").move_to(Coordinate::new(2, 8));
        vehicle(&mut scenario, "9").move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns);
        for id in ["4", "9"] {
            assert_eq!(vehicle(&mut scenario, id).supplies().current(), 62);
        }
        assert_eq!(vehicle(&mut scenario, "5").supplies().current(), 62);
    }

    #[test]
    fn walking_destination_conflicts_pay_upkeep_but_no_movement_supplies() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "6").move_to(Coordinate::new(5, 6));
        let mut west = holds(&scenario, Side::West);
        let mut east = holds(&scenario, Side::East);
        set_path(&mut west, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut east, "6", &[(5, 6), (4, 6)]);
        let mut turns = Turns::default();
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        assert_eq!(vehicle(&mut scenario, "1").supplies().current(), 63);
        assert_eq!(vehicle(&mut scenario, "6").supplies().current(), 63);
        assert_eq!(
            vehicle(&mut scenario, "1").position(),
            Coordinate::new(3, 7)
        );
        assert_eq!(
            vehicle(&mut scenario, "6").position(),
            Coordinate::new(5, 6)
        );
    }

    #[test]
    fn fuel_is_vehicle_only_and_successful_tiles_consume_it_once() {
        let mut scenario = Scenario::supply_point().unwrap();
        assert!(vehicle(&mut scenario, "1").fuel().is_none());
        assert!(vehicle(&mut scenario, "12").fuel().is_none());
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 64);
        let mut turns = Turns::default();
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "4", &[(2, 7), (2, 6), (3, 6)]);
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        turns.submit(&mut scenario, Side::West, 1, vec![]).unwrap();
        let east = holds(&scenario, Side::East);
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 62);
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 64);
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 62);
    }

    #[test]
    fn fuel_rejection_is_atomic_and_empty_vehicles_can_hold() {
        let mut scenario = Scenario::supply_point().unwrap();
        for _ in 0..32 {
            vehicle(&mut scenario, "4").follow_path(&[
                Coordinate::new(2, 7),
                Coordinate::new(2, 6),
                Coordinate::new(2, 7),
            ]);
        }
        let mut turns = Turns::default();
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "4", &[(2, 7), (2, 6)]);
        assert_eq!(
            turns.submit(&mut scenario, Side::West, 1, west),
            Err("movement exceeds the unit's available fuel.")
        );
        assert!(turns.orders[0].is_none());
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 0);
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 0);
        vehicle(&mut scenario, "4").move_to(Coordinate::new(2, 8));
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
    }

    #[test]
    fn tank_paths_must_fit_remaining_fuel_even_with_movement_points_left() {
        let mut scenario = Scenario::supply_point().unwrap();
        for _ in 0..31 {
            vehicle(&mut scenario, "11").follow_path(&[
                Coordinate::new(4, 8),
                Coordinate::new(5, 8),
                Coordinate::new(4, 8),
            ]);
        }
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "11", &[(4, 8), (5, 8), (6, 8), (7, 8)]);
        assert_eq!(
            validate(&scenario, Side::West, west).unwrap_err(),
            "movement exceeds the unit's available fuel."
        );
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "11", &[(4, 8), (5, 8), (6, 8)]);
        let mut turns = Turns::default();
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        let east = holds(&scenario, Side::East);
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        assert_eq!(vehicle(&mut scenario, "11").fuel().unwrap().current, 0);
        assert_eq!(
            vehicle(&mut scenario, "11").position(),
            Coordinate::new(6, 8)
        );
    }

    #[test]
    fn home_depot_refills_after_arrival_and_holding_but_other_depots_do_not() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "4", &[(2, 7), (2, 8)]);
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        let east = holds(&scenario, Side::East);
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        vehicle(&mut scenario, "4").follow_path(&[Coordinate::new(2, 8), Coordinate::new(2, 8)]);
        vehicle(&mut scenario, "5").follow_path(&[Coordinate::new(2, 9), Coordinate::new(8, 8)]);
        vehicle(&mut scenario, "9").follow_path(&[Coordinate::new(14, 7), Coordinate::new(2, 8)]);
        // Place the eastern truck on the western depot, away from its home.
        vehicle(&mut scenario, "4").move_to(Coordinate::new(14, 8));
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 63);
        assert_eq!(vehicle(&mut scenario, "5").fuel().unwrap().current, 63);
        assert_eq!(vehicle(&mut scenario, "9").fuel().unwrap().current, 63);
        vehicle(&mut scenario, "9").move_to(Coordinate::new(14, 8));
        vehicle(&mut scenario, "4").move_to(Coordinate::new(2, 8));
        resolve_holds(&mut scenario, &mut turns);
        assert_eq!(vehicle(&mut scenario, "4").fuel().unwrap().current, 64);
        assert_eq!(vehicle(&mut scenario, "9").fuel().unwrap().current, 64);
    }

    #[test]
    fn vehicle_destination_conflicts_consume_no_fuel() {
        let mut scenario = Scenario::supply_point().unwrap();
        vehicle(&mut scenario, "9").move_to(Coordinate::new(4, 6));
        let mut west = holds(&scenario, Side::West);
        let mut east = holds(&scenario, Side::East);
        set_path(&mut west, "4", &[(2, 7), (2, 6), (3, 6)]);
        set_path(&mut east, "9", &[(4, 6), (3, 6)]);
        let initial = scenario.clone();
        let mut turns = Turns::default();
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        for (unit, original) in scenario.units.iter().zip(&initial.units) {
            assert_eq!(unit.position(), original.position());
            assert_eq!(unit.direction(), original.direction());
            assert_eq!(unit.fuel(), original.fuel());
            assert_eq!(unit.supplies().current(), 63);
        }
    }

    #[test]
    fn locks_orders_resolves_once_and_rejects_stale_turns() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut turns = Turns::default();
        let mut west = holds(&scenario, Side::West);
        set_path(&mut west, "1", &[(3, 7), (3, 6)]);
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        assert_eq!(turns.number, 1);
        assert_eq!(scenario.units[0].position(), Coordinate::new(3, 7));
        turns.submit(&mut scenario, Side::West, 1, vec![]).unwrap();
        assert!(turns.orders[1].is_none());
        let east = holds(&scenario, Side::East);
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        assert_eq!(turns.number, 2);
        assert_eq!(scenario.units[0].position(), Coordinate::new(3, 6));
        assert_eq!(scenario.units[0].direction(), Some(Direction::North));
        assert_eq!(scenario.units[1].direction(), Some(Direction::East));
        assert!(turns.orders.iter().all(Option::is_none));
        let resolution = turns.last_resolution.as_ref().unwrap();
        assert_eq!(resolution.events.len(), 16);
        assert_eq!(resolution.events[0].kind, TurnEventKind::Move);
        assert_eq!(
            resolution.events[0].initial_direction,
            Some(Direction::East)
        );
        assert_eq!(resolution.turn_number, 1);
        assert!(turns.submit(&mut scenario, Side::East, 1, vec![]).is_err());
    }

    #[test]
    fn rejects_missing_duplicate_foreign_illegal_and_over_budget_orders_atomically() {
        let mut scenario = Scenario::supply_point().unwrap();
        for path in [
            vec![],
            vec![(0, 0)],
            vec![(3, 7), (-1, 7)],
            vec![(3, 7), (17, 7)],
            vec![(3, 7), (5, 7)],
            vec![(3, 7), (4, 7)],
            vec![(3, 7), (3, 6), (3, 5), (3, 4)],
            vec![(3, 7), (3, 6), (3, 7)],
        ] {
            let mut orders = holds(&scenario, Side::West);
            set_path(&mut orders, "1", &path);
            let mut turns = Turns::default();
            assert!(turns.submit(&mut scenario, Side::West, 1, orders).is_err());
            assert!(turns.orders[0].is_none());
        }
        let mut orders = holds(&scenario, Side::West);
        orders.pop();
        assert!(validate(&scenario, Side::West, orders).is_err());
        let mut orders = holds(&scenario, Side::West);
        orders[1].unit_id = "1".into();
        assert!(validate(&scenario, Side::West, orders).is_err());
        let mut orders = holds(&scenario, Side::West);
        orders[0].unit_id = "6".into();
        assert!(validate(&scenario, Side::West, orders).is_err());
    }

    #[test]
    fn allies_allow_passage_but_enemies_and_duplicate_destinations_do_not() {
        let mut scenario = Scenario::supply_point().unwrap();
        let mut orders = holds(&scenario, Side::West);
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)]);
        assert!(validate(&scenario, Side::West, orders).is_ok());
        let mut orders = holds(&scenario, Side::West);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)]);
        set_path(&mut orders, "2", &[(3, 8), (3, 7), (3, 6)]);
        assert!(validate(&scenario, Side::West, orders).is_err());
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .unwrap()
            .move_to(Coordinate::new(3, 6));
        let mut orders = holds(&scenario, Side::West);
        set_path(&mut orders, "1", &[(3, 7), (3, 6)]);
        assert_eq!(
            validate(&scenario, Side::West, orders).unwrap_err(),
            "enemy units block movement."
        );
    }

    #[test]
    fn opposing_destination_conflicts_hold_both_units() {
        let mut scenario = Scenario::supply_point().unwrap();
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "6")
            .unwrap()
            .move_to(Coordinate::new(5, 6));
        let initial = scenario.clone();
        let mut west = holds(&scenario, Side::West);
        let mut east = holds(&scenario, Side::East);
        set_path(&mut west, "1", &[(3, 7), (3, 6), (4, 6)]);
        set_path(&mut east, "6", &[(5, 6), (4, 6)]);
        let mut turns = Turns::default();
        turns.submit(&mut scenario, Side::East, 1, east).unwrap();
        turns.submit(&mut scenario, Side::West, 1, west).unwrap();
        assert_eq!(
            turns
                .last_resolution
                .unwrap()
                .events
                .iter()
                .filter(|event| event.kind == TurnEventKind::DestinationConflict)
                .count(),
            2
        );
        for (unit, original) in scenario.units.iter().zip(&initial.units) {
            assert_eq!(unit.position(), original.position());
            assert_eq!(unit.direction(), original.direction());
            assert_eq!(unit.fuel(), original.fuel());
            assert_eq!(unit.supplies().current(), 63);
        }
    }
}
