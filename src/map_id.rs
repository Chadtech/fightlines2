//! File-backed map identity and catalog discovery, shared by play and authoring.
use crate::{
    map::MapError,
    map_definition::{MapDefinition, NamedMap},
    scenario::Scenario,
};
use juniper::{GraphQLScalar, Scalar, ScalarValue};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
};

/// Stable filename stem. Archived games retain their own boards independently.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, GraphQLScalar, Serialize, Deserialize)]
#[graphql(to_output_with = output, from_input_with = parse_input, parse_token(String))]
#[serde(try_from = "String", into = "String")]
pub struct MapId(String);

fn output<S: ScalarValue>(id: &MapId) -> S {
    S::from_displayable(&id.0)
}

fn parse_input(value: &Scalar<impl ScalarValue>) -> Result<MapId, String> {
    let value = value.try_to_string().ok_or("map id must be a string")?;
    MapId::parse(value)
}

impl MapId {
    pub fn parse(value: String) -> Result<Self, String> {
        if value.is_empty() || value.len() > 100 {
            return Err("map id must contain 1–100 characters".into());
        }
        if !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        {
            return Err(
                "map id may contain only lowercase ASCII letters, digits, and hyphens".into(),
            );
        }
        if value.starts_with('-') || value.ends_with('-') {
            return Err("map id must start and end with a letter or digit".into());
        }
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn player_count(&self) -> usize {
        2
    }

    pub fn definition(&self) -> Result<MapDefinition, MapError> {
        self.definition_in(&directory())
    }

    pub fn definition_in(&self, directory: &Path) -> Result<MapDefinition, MapError> {
        let path = directory.join(format!("{}.json", self.as_str()));
        let json = fs::read_to_string(&path)
            .map_err(|error| MapError::InvalidDefinition(format!("{}: {error}", path.display())))?;
        MapDefinition::parse(&json)
            .map_err(|error| MapError::InvalidDefinition(format!("{}: {error}", path.display())))
    }

    pub fn scenario(&self) -> Result<Scenario, MapError> {
        self.definition()?.scenario()
    }
}

impl Default for MapId {
    fn default() -> Self {
        Self("supply-point".into())
    }
}

impl TryFrom<String> for MapId {
    type Error = String;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        // Archives previously serialized enum variants such as `SupplyPoint`.
        // Generic case conversion preserves those IDs without a fixed map list.
        let mut canonical = String::new();
        for (index, character) in value.chars().enumerate() {
            if character.is_ascii_uppercase() {
                if index > 0 {
                    canonical.push('-');
                }
                canonical.push(character.to_ascii_lowercase());
            } else {
                canonical.push(character);
            }
        }
        Self::parse(canonical)
    }
}

impl From<MapId> for String {
    fn from(id: MapId) -> Self {
        id.0
    }
}

pub fn directory() -> PathBuf {
    std::env::var_os("FIGHTLINES_MAP_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("maps"))
}

pub fn catalog_in(directory: &Path) -> Result<Vec<NamedMap>, MapError> {
    let mut ids = Vec::new();
    let entries = fs::read_dir(directory).map_err(|error| {
        MapError::InvalidDefinition(format!("{}: {error}", directory.display()))
    })?;
    for entry in entries {
        let entry = entry.map_err(|error| MapError::InvalidDefinition(error.to_string()))?;
        if !entry
            .file_type()
            .map_err(|error| MapError::InvalidDefinition(error.to_string()))?
            .is_file()
        {
            continue;
        }
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let stem = path
            .file_stem()
            .and_then(|value| value.to_str())
            .ok_or_else(|| MapError::InvalidDefinition("map filename must be UTF-8".into()))?;
        let id = MapId::parse(stem.into()).map_err(MapError::InvalidDefinition)?;
        ids.push(id);
    }
    ids.sort_by_key(|id| (id != &MapId::default(), id.clone()));
    if ids.is_empty() {
        return Err(MapError::InvalidDefinition("map catalog is empty".into()));
    }
    ids.into_iter()
        .map(|map_type| {
            let definition = map_type.definition_in(directory)?;
            definition.scenario()?;
            Ok(NamedMap {
                map_type,
                definition,
            })
        })
        .collect()
}

pub fn catalog() -> Result<Vec<NamedMap>, MapError> {
    catalog_in(&directory())
}

pub fn options() -> Result<Vec<MapId>, MapError> {
    Ok(catalog()?.into_iter().map(|map| map.map_type).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;
    use std::time::{SystemTime, UNIX_EPOCH};

    const FIXTURE: &str = r#"{
        "width": 2, "height": 2, "theme": "GreenForest", "features": [], "depots": [],
        "units": [
            {"id": 1, "position": {"x": 0, "y": 0}, "playerNumber": "Player1", "kind": "Infantry", "direction": "East"},
            {"id": 2, "position": {"x": 1, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
        ]
    }"#;

    #[test]
    fn discovers_new_maps_and_reads_changes_without_a_rebuild() -> TestResult {
        let directory = std::env::temp_dir().join(format!(
            "fightlines-catalog-{}-{}",
            std::process::id(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        fs::create_dir_all(&directory)?;
        assert!(catalog_in(&directory).is_err());
        fs::write(directory.join("zulu.json"), FIXTURE)?;
        fs::write(directory.join("alpha.json"), FIXTURE)?;
        fs::write(directory.join("ignored.json.tmp"), "incomplete")?;
        let maps = catalog_in(&directory).map_err(|error| error.to_string())?;
        assert_eq!(
            maps.iter()
                .map(|map| map.map_type.as_str())
                .collect::<Vec<_>>(),
            ["alpha", "zulu"]
        );
        let id = MapId::parse("new-battlefield-42".into())?;
        fs::write(directory.join("new-battlefield-42.json"), FIXTURE)?;
        let maps = catalog_in(&directory).map_err(|error| error.to_string())?;
        assert!(maps.iter().any(|map| map.map_type == id));
        let changed = FIXTURE.replace("\"width\": 2", "\"width\": 3");
        fs::write(directory.join("new-battlefield-42.json"), changed)?;
        assert_eq!(
            id.definition_in(&directory)
                .map_err(|error| error.to_string())?
                .width,
            3
        );
        fs::write(directory.join("invalid.json"), "malformed")?;
        assert!(catalog_in(&directory).is_err());
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[test]
    fn identifiers_reject_paths_and_preserve_legacy_archive_identity() -> TestResult {
        for invalid in [
            "",
            "../outside",
            "map/name",
            "map.json",
            "-map",
            "map-",
            "Uppercase",
        ] {
            assert!(MapId::parse(invalid.into()).is_err(), "{invalid}");
        }
        for (legacy, current) in [
            ("SupplyPoint", "supply-point"),
            ("LakeOfPennsylvania", "lake-of-pennsylvania"),
            ("ElAlamein", "el-alamein"),
        ] {
            let id: MapId = serde_json::from_str(&serde_json::to_string(legacy)?)?;
            assert_eq!(id.as_str(), current);
            assert_eq!(serde_json::to_string(&id)?, serde_json::to_string(current)?);
        }
        let missing = MapId::parse("map-that-was-removed".into())?;
        assert!(missing.definition().is_err());
        Ok(())
    }
}
