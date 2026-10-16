//! Editable scenario data. Resources are initialized by the ordinary game rules.
use crate::{
    map::{Coordinate, Map, MapError, MapTheme, Terrain},
    scenario::{DepotKind, Direction, PlayerNumber, Scenario, UnitKind},
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MapDefinition {
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
    pub kind: DepotKind,
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
    use crate::test_support::{FixtureValue, TestResult};

    fn definition() -> TestResult<MapDefinition> {
        MapDefinition::parse(include_str!("../maps/supply-point.json")).fixture()
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
