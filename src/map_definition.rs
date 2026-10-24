//! Editable scenario data. Resources are initialized by the ordinary game rules.
use crate::{
    graphql::Context,
    map::{Coordinate, Map, MapError, MapTheme, Terrain, TerrainValue},
    map_type::MapType,
    scenario::{BuildingKind, Direction, PlayerNumber, Scenario, UnitKind},
};
use juniper::{GraphQLObject, graphql_object};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapDefinition {
    /// Selection copy; older definitions without metadata remain loadable.
    #[serde(default)]
    pub description: String,
    pub width: u16,
    pub height: u16,
    pub theme: MapTheme,
    pub features: Vec<TerrainPlacement>,
    pub depots: Vec<DepotPlacement>,
    pub units: Vec<UnitPlacement>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TerrainPlacement {
    pub position: Coordinate,
    pub terrain: Terrain,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DepotPlacement {
    pub position: Coordinate,
    pub kind: BuildingKind,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UnitPlacement {
    pub id: u16,
    pub position: Coordinate,
    #[serde(rename = "playerNumber")]
    pub player_number: PlayerNumber,
    pub kind: UnitKind,
    pub direction: Option<Direction>,
}

#[derive(GraphQLObject)]
#[graphql(context = Context)]
pub struct NamedMap {
    pub map_type: MapType,
    pub definition: MapDefinition,
}

#[graphql_object(context = Context)]
impl MapDefinition {
    fn description(&self) -> &str {
        &self.description
    }
    fn width(&self) -> i32 {
        i32::from(self.width)
    }
    fn height(&self) -> i32 {
        i32::from(self.height)
    }
    fn theme(&self) -> MapTheme {
        self.theme
    }
    fn features(&self) -> &[TerrainPlacement] {
        &self.features
    }
    fn depots(&self) -> &[DepotPlacement] {
        &self.depots
    }
    fn units(&self) -> &[UnitPlacement] {
        &self.units
    }
}

#[graphql_object(context = Context)]
impl TerrainPlacement {
    fn position(&self) -> Coordinate {
        self.position
    }
    fn terrain(&self) -> TerrainValue {
        self.terrain.into()
    }
}
#[graphql_object(context = Context)]
impl DepotPlacement {
    fn position(&self) -> Coordinate {
        self.position
    }
    fn kind(&self) -> BuildingKind {
        self.kind
    }
}
#[graphql_object(context = Context)]
impl UnitPlacement {
    fn id(&self) -> i32 {
        i32::from(self.id)
    }
    fn position(&self) -> Coordinate {
        self.position
    }
    fn player_number(&self) -> PlayerNumber {
        self.player_number
    }
    fn kind(&self) -> UnitKind {
        self.kind
    }
    fn direction(&self) -> Option<Direction> {
        self.direction
    }
}

impl MapDefinition {
    pub fn parse(json: &str) -> Result<Self, MapError> {
        serde_json::from_str(json).map_err(|error| MapError::InvalidDefinition(error.to_string()))
    }

    pub fn terrain_map(&self) -> Result<Map, MapError> {
        let invalid = |message: &str| MapError::InvalidDefinition(message.into());
        if self.width > 64 || self.height > 64 {
            return Err(invalid("maps must be at most 64 × 64 tiles"));
        }
        let mut features = BTreeMap::new();
        for feature in &self.features {
            if features.insert(feature.position, feature.terrain).is_some() {
                return Err(invalid("duplicate terrain position"));
            }
        }
        let map =
            Map::new(self.width, self.height, Terrain::Plain, features)?.with_theme(self.theme);
        let mut depot_positions = BTreeSet::new();
        for depot in &self.depots {
            if !map.contains(depot.position) {
                return Err(MapError::PositionOutOfBounds(depot.position));
            }
            if !depot_positions.insert(depot.position) {
                return Err(invalid("two depots cannot share a tile"));
            }
        }
        if self.units.len() > 256 {
            return Err(invalid("maps must have at most 256 units"));
        }
        let mut ids = BTreeSet::new();
        let mut positions = BTreeSet::new();
        for unit in &self.units {
            if unit.id == 0 || !ids.insert(unit.id) {
                return Err(invalid("unit ids must be unique and greater than zero"));
            }
            if !map.contains(unit.position) {
                return Err(MapError::PositionOutOfBounds(unit.position));
            }
            if !positions.insert(unit.position) {
                return Err(invalid("two units cannot share a tile"));
            }
            if map.tile_at(unit.position) == Some(Terrain::Mountains)
                && unit.kind != UnitKind::Infantry
            {
                return Err(invalid("only infantry can start on mountains"));
            }
            if map.tile_at(unit.position) == Some(Terrain::Water) {
                return Err(invalid("units cannot start on water"));
            }
            match (unit.kind, unit.direction) {
                (UnitKind::Truck, None) => {}
                (UnitKind::Truck, Some(_)) => return Err(invalid("trucks have no facing")),
                (_, Some(_)) => {}
                (_, None) => return Err(invalid("combat units require a facing")),
            }
        }
        for player_number in [PlayerNumber::Player1, PlayerNumber::Player2] {
            if !self
                .units
                .iter()
                .any(|unit| unit.player_number == player_number)
            {
                return Err(invalid("each player needs at least one starting unit"));
            }
        }
        Ok(map)
    }

    pub fn scenario(&self) -> Result<Scenario, MapError> {
        Scenario::from_definition(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map::RoadShape,
        test_support::{FixtureValue, TestResult},
    };

    #[test]
    fn fortresses_round_trip_with_eight_hp_and_no_resource_stock() -> TestResult<()> {
        let json = serde_json::json!({
            "width": 3, "height": 2, "theme": "GreenForest", "features": [],
            "depots": [{"position": {"x": 1, "y": 0}, "kind": "Fortress"}],
            "units": [
                {"id": 1, "position": {"x": 1, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                {"id": 2, "position": {"x": 2, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        });
        let definition = MapDefinition::parse(&json.to_string()).fixture()?;
        let saved = serde_json::to_string(&definition)?;
        let mut scenario = MapDefinition::parse(&saved)
            .fixture()?
            .scenario()
            .fixture()?;
        let fortress = scenario.depots.first().fixture()?;
        assert_eq!(fortress.kind, BuildingKind::Fortress);
        assert_eq!(fortress.hit_points().current, 8);
        assert_eq!(fortress.hit_points().maximum, 8);
        assert_eq!(fortress.stock.current, 0);
        assert_eq!(fortress.stock.maximum, 0);
        assert!(fortress.kind.resource_kind().is_none());
        let infantry = scenario.units.first_mut().fixture()?;
        infantry.set_supplies_for_test(100);
        let upkeep = infantry.supplies().upkeep_per_turn();
        scenario.finish_turn_resources(1);
        assert_eq!(
            scenario.units.first().fixture()?.supplies().current(),
            100 - upkeep
        );
        // Building positions share the existing occupancy validation.
        let mut overlapping = definition;
        overlapping.depots.push(DepotPlacement {
            position: Coordinate::new(1, 0),
            kind: BuildingKind::Supply,
        });
        assert!(overlapping.scenario().is_err());
        Ok(())
    }

    #[test]
    fn explicit_road_variants_survive_map_json_and_scenario_loading() -> TestResult<()> {
        for shape in RoadShape::ALL {
            let road = Terrain::Road(shape);
            let json = serde_json::json!({
                "width": 3, "height": 2, "theme": "GreenForest",
                "features": [{ "position": { "x": 1, "y": 0 }, "terrain": road }],
                "depots": [],
                "units": [
                    { "id": 1, "position": { "x": 0, "y": 0 }, "playerNumber": "Player1", "kind": "Tank", "direction": "East" },
                    { "id": 2, "position": { "x": 2, "y": 1 }, "playerNumber": "Player2", "kind": "Infantry", "direction": "West" }
                ]
            });
            let definition = MapDefinition::parse(&json.to_string()).fixture()?;
            let saved = serde_json::to_string(&definition)?;
            let reloaded = MapDefinition::parse(&saved).fixture()?;
            let scenario = reloaded.scenario().fixture()?;
            assert_eq!(scenario.map.tile_at(Coordinate::new(1, 0)), Some(road));
        }
        Ok(())
    }

    fn definition() -> TestResult<MapDefinition> {
        MapDefinition::parse(include_str!("../maps/supply-point.json")).fixture()
    }

    #[test]
    fn starting_terrain_blocks_water_but_accepts_beaches_for_every_unit() -> TestResult<()> {
        let original = MapDefinition::parse(
            r#"{
                "width": 3, "height": 1, "theme": "GreenForest",
                "features": [{"position": {"x": 0, "y": 0}, "terrain": "Water"}],
                "depots": [],
                "units": [
                    {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
                    {"id": 2, "position": {"x": 2, "y": 0}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
                ]
            }"#,
        ).fixture()?;
        for kind in [
            UnitKind::Infantry,
            UnitKind::Tank,
            UnitKind::Truck,
            UnitKind::FieldGun,
        ] {
            let mut draft = original.clone();
            let unit = draft.units.first_mut().fixture()?;
            unit.kind = kind;
            unit.direction = if kind == UnitKind::Truck {
                None
            } else {
                Some(Direction::East)
            };
            assert_eq!(
                draft.terrain_map().err(),
                Some(MapError::InvalidDefinition(
                    "units cannot start on water".into()
                ))
            );
            draft.features.clear();
            draft.features.push(TerrainPlacement {
                position: Coordinate::new(0, 0),
                terrain: Terrain::Beach,
            });
            draft.scenario().fixture()?;
        }
        Ok(())
    }

    #[test]
    fn validates_occupancy_bounds_ids_player_numbers_and_facing() -> TestResult<()> {
        let original = definition()?;
        original.scenario().fixture()?;
        let mut draft = original.clone();
        draft.units.push(draft.units.first().fixture()?.clone());
        assert!(draft.scenario().is_err());
        let mut draft = original.clone();
        draft.width = 0;
        assert!(draft.scenario().is_err());
        let mut draft = original.clone();
        draft.units.first_mut().fixture()?.direction = None;
        assert!(draft.scenario().is_err());
        let mut draft = original.clone();
        draft
            .units
            .retain(|unit| unit.player_number == PlayerNumber::Player1);
        assert!(draft.scenario().is_err());
        let mut draft = original.clone();
        draft.depots.first_mut().fixture()?.position = Coordinate::new(64, 64);
        assert!(draft.scenario().is_err());
        let mut draft = original;
        let unit = draft.units.first_mut().fixture()?;
        unit.kind = UnitKind::Tank;
        draft.features.push(TerrainPlacement {
            position: unit.position,
            terrain: Terrain::Mountains,
        });
        assert!(draft.scenario().is_err());
        Ok(())
    }
}
