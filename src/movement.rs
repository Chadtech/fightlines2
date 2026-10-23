use crate::{
    map::{RoadShape, Terrain, TerrainValue},
    scenario::UnitKind,
};
use juniper::{GraphQLObject, graphql_object};

/// Budgets and entry costs use half-points: two stored points equal one displayed point.
#[derive(Clone, Debug)]
pub struct TerrainMovementCost {
    pub(crate) terrain: Terrain,
    pub(crate) cost: i32,
}

/// Budgets and entry costs use half-points: two stored points equal one displayed point.
#[graphql_object]
impl TerrainMovementCost {
    fn terrain(&self) -> TerrainValue {
        self.terrain.into()
    }

    fn cost(&self) -> i32 {
        self.cost
    }
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct MovementRule {
    pub(crate) kind: UnitKind,
    pub(crate) budget: i32,
    pub(crate) terrain_costs: Vec<TerrainMovementCost>,
    pub(crate) road_fuel_per_tile: i32,
    pub(crate) road_fuel_per_cargo_slot: i32,
}

/// Road entry consumes whole fuel quantities, including cargo at departure.
pub fn road_fuel_cost(kind: UnitKind, occupied_slots: usize) -> i32 {
    match kind {
        UnitKind::Tank => 5,
        UnitKind::Truck => 1 + occupied_slots as i32,
        UnitKind::Infantry | UnitKind::FieldGun => 0,
    }
}

pub fn rules() -> Vec<MovementRule> {
    [
        (UnitKind::Infantry, 4, [2, 2, 2, 4, 0, 2]),
        (UnitKind::Tank, 12, [2, 4, 6, 0, 0, 2]),
        // One adjacent passable square, regardless of terrain.
        (UnitKind::FieldGun, 2, [2, 2, 2, 0, 0, 2]),
        (UnitKind::Truck, 14, [2, 6, 8, 0, 0, 2]),
    ]
    .into_iter()
    .map(|(kind, budget, costs)| MovementRule {
        kind,
        budget,
        road_fuel_per_tile: road_fuel_cost(kind, 0),
        road_fuel_per_cargo_slot: road_fuel_cost(kind, 1) - road_fuel_cost(kind, 0),
        terrain_costs: [
            Terrain::Plain,
            Terrain::Hills,
            Terrain::Forest,
            Terrain::Mountains,
            Terrain::Water,
            Terrain::Beach,
        ]
        .into_iter()
        .zip(costs)
        .map(|(terrain, cost)| TerrainMovementCost { terrain, cost })
        .chain(RoadShape::ALL.into_iter().map(|shape| TerrainMovementCost {
            terrain: Terrain::Road(shape),
            cost: 2,
        }))
        .collect(),
    })
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map::{Coordinate, Map};
    use crate::test_support::{FixtureValue, TestResult};
    use serde_json::Value;
    use std::collections::BTreeMap;

    fn kind(name: &str) -> TestResult<UnitKind> {
        Ok({
            match name {
                "INFANTRY" => UnitKind::Infantry,
                "TANK" => UnitKind::Tank,
                "FIELD_GUN" => UnitKind::FieldGun,
                "TRUCK" => UnitKind::Truck,
                _ => return Err("unknown fixture unit".into()),
            }
        })
    }

    fn coordinate(value: &Value) -> TestResult<Coordinate> {
        Ok({
            Coordinate::new(
                value[0].as_u64().fixture()? as u16,
                value[1].as_u64().fixture()? as u16,
            )
        })
    }

    #[test]
    fn shared_movement_cases_match_rust_rules() -> TestResult<()> {
        let fixtures: Value =
            serde_json::from_str(include_str!("../tests/movement.json")).fixture()?;
        for fixture in fixtures["rules"].as_array().fixture()? {
            let kind = kind(fixture["kind"].as_str().fixture()?)?;
            let rule = rules()
                .into_iter()
                .find(|rule| rule.kind == kind)
                .fixture()?;
            assert_eq!(rule.budget, fixture["budget"].as_i64().fixture()? as i32);
            assert_eq!(
                rule.road_fuel_per_tile,
                fixture["roadFuelPerTile"].as_i64().fixture()? as i32
            );
            assert_eq!(
                rule.road_fuel_per_cargo_slot,
                fixture["roadFuelPerCargoSlot"].as_i64().fixture()? as i32
            );
            assert_eq!(
                rule.terrain_costs.len(),
                fixture["terrainCosts"].as_array().fixture()?.len()
            );
            for (entry, expected) in rule
                .terrain_costs
                .iter()
                .zip(fixture["terrainCosts"].as_array().fixture()?)
            {
                assert_eq!(entry.cost, expected["cost"].as_i64().fixture()? as i32);
                let terrain = match expected["terrain"].as_str().fixture()? {
                    "PLAIN" => Terrain::Plain,
                    "HILLS" => Terrain::Hills,
                    "FOREST" => Terrain::Forest,
                    "MOUNTAINS" => Terrain::Mountains,
                    "WATER" => Terrain::Water,
                    "BEACH" => Terrain::Beach,
                    "ROAD_NORTH_SOUTH" => Terrain::Road(RoadShape::NorthSouth),
                    "ROAD_EAST_WEST" => Terrain::Road(RoadShape::EastWest),
                    "ROAD_NORTH_EAST" => Terrain::Road(RoadShape::NorthEast),
                    "ROAD_SOUTH_EAST" => Terrain::Road(RoadShape::SouthEast),
                    "ROAD_SOUTH_WEST" => Terrain::Road(RoadShape::SouthWest),
                    "ROAD_NORTH_WEST" => Terrain::Road(RoadShape::NorthWest),
                    "ROAD_NORTH_EAST_SOUTH" => Terrain::Road(RoadShape::NorthEastSouth),
                    "ROAD_EAST_SOUTH_WEST" => Terrain::Road(RoadShape::EastSouthWest),
                    "ROAD_NORTH_SOUTH_WEST" => Terrain::Road(RoadShape::NorthSouthWest),
                    "ROAD_NORTH_EAST_WEST" => Terrain::Road(RoadShape::NorthEastWest),
                    "ROAD_CROSSROADS" => Terrain::Road(RoadShape::Crossroads),
                    _ => return Err("unknown fixture terrain".into()),
                };
                assert_eq!(entry.terrain, terrain);
            }
        }
        for case in fixtures["cases"].as_array().fixture()? {
            let map = Map::from_ascii(case["sketch"].as_str().fixture()?).fixture()?;
            let origin = coordinate(&case["origin"])?;
            let occupied: Vec<_> = case["occupied"]
                .as_array()
                .fixture()?
                .iter()
                .map(coordinate)
                .collect::<TestResult<Vec<_>>>()?;
            let allies: Vec<_> = case["allies"]
                .as_array()
                .fixture()?
                .iter()
                .map(coordinate)
                .collect::<TestResult<Vec<_>>>()?;
            let kind = kind(case["kind"].as_str().fixture()?)?;
            let rule = rules()
                .into_iter()
                .find(|rule| rule.kind == kind)
                .fixture()?;
            // Independent relaxation reference, sharing the production rule values.
            let mut costs = BTreeMap::from([(origin, 0)]);
            loop {
                let mut changed = false;
                for (position, cost) in costs.clone() {
                    for (x, y) in [
                        (position.x(), position.y() - 1),
                        (position.x() - 1, position.y()),
                        (position.x() + 1, position.y()),
                        (position.x(), position.y() + 1),
                    ] {
                        if x < 0 || y < 0 {
                            continue;
                        }
                        let next = Coordinate::new(x as u16, y as u16);
                        if next == origin {
                            continue;
                        }
                        let Some(terrain) = map.tile_at(next) else {
                            continue;
                        };
                        let entry_cost = rule
                            .terrain_costs
                            .iter()
                            .find(|entry| entry.terrain == terrain)
                            .fixture()?
                            .cost;
                        if entry_cost <= 0 {
                            continue;
                        }
                        let total = cost + entry_cost;
                        if total <= rule.budget
                            && costs.get(&next).is_none_or(|previous| total < *previous)
                        {
                            costs.insert(next, total);
                            changed = true;
                        }
                    }
                }
                if !changed {
                    break;
                }
            }
            costs.remove(&origin);
            costs.retain(|position, _| !allies.contains(position) && !occupied.contains(position));
            let actual: Vec<_> = costs
                .into_iter()
                .map(|(position, cost)| vec![position.x(), position.y(), cost])
                .collect();
            let expected: Vec<Vec<i32>> =
                serde_json::from_value(case["expected"].clone()).fixture()?;
            assert_eq!(actual, expected, "{}", case["name"]);
        }

        Ok(())
    }
}
