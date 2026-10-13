use crate::{map::Terrain, scenario::UnitKind};
use juniper::GraphQLObject;

/// Budgets and entry costs use half-points: two stored points equal one displayed point.
#[derive(Clone, Debug, GraphQLObject)]
pub struct TerrainMovementCost {
    pub(crate) terrain: Terrain,
    pub(crate) cost: i32,
}

#[derive(Clone, Debug, GraphQLObject)]
pub struct MovementRule {
    pub(crate) kind: UnitKind,
    pub(crate) budget: i32,
    pub(crate) terrain_costs: Vec<TerrainMovementCost>,
}

pub fn rules() -> Vec<MovementRule> {
    [
        (UnitKind::Infantry, 4, [2, 2, 2]),
        (UnitKind::Tank, 12, [2, 4, 6]),
        // One adjacent passable square, regardless of terrain.
        (UnitKind::FieldGun, 2, [2, 2, 2]),
        (UnitKind::Truck, 14, [2, 6, 8]),
    ]
    .into_iter()
    .map(|(kind, budget, costs)| MovementRule {
        kind,
        budget,
        terrain_costs: [Terrain::GrassPlain, Terrain::Hills, Terrain::Forest]
            .into_iter()
            .zip(costs)
            .map(|(terrain, cost)| TerrainMovementCost { terrain, cost })
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
            for (entry, expected) in rule
                .terrain_costs
                .iter()
                .zip(fixture["terrainCosts"].as_array().fixture()?)
            {
                assert_eq!(entry.cost, expected["cost"].as_i64().fixture()? as i32);
                let terrain = match expected["terrain"].as_str().fixture()? {
                    "GRASS_PLAIN" => Terrain::GrassPlain,
                    "HILLS" => Terrain::Hills,
                    "FOREST" => Terrain::Forest,
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
                        let total = cost
                            + rule
                                .terrain_costs
                                .iter()
                                .find(|entry| entry.terrain == terrain)
                                .fixture()?
                                .cost;
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
