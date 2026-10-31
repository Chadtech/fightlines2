//! Shared presentation settings. Only the localhost map editor can write them.
use crate::{graphql::Context, map_editor::Editor, scenario::UnitKind};
use juniper::{FieldResult, GraphQLInputObject, GraphQLObject};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    env, fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Deserialize, Serialize, GraphQLObject, PartialEq)]
#[serde(rename_all = "camelCase", from = "StoredCalibration")]
pub struct BackdropCalibration {
    pub front_footing: f64,
    pub row_spacing: f64,
    pub unit_size: f64,
    pub rear_scale: f64,
    pub trench_footing: f64,
    pub trench_size: f64,
    pub second_trench_footing: f64,
    pub second_trench_size: f64,
}

/// Older files share the first trench's settings with the second trench.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredCalibration {
    front_footing: f64,
    row_spacing: f64,
    unit_size: f64,
    rear_scale: f64,
    #[serde(default = "default_trench_footing")]
    trench_footing: f64,
    #[serde(default = "default_trench_size")]
    trench_size: f64,
    second_trench_footing: Option<f64>,
    second_trench_size: Option<f64>,
}

impl From<StoredCalibration> for BackdropCalibration {
    fn from(stored: StoredCalibration) -> Self {
        Self {
            front_footing: stored.front_footing,
            row_spacing: stored.row_spacing,
            unit_size: stored.unit_size,
            rear_scale: stored.rear_scale,
            trench_footing: stored.trench_footing,
            trench_size: stored.trench_size,
            second_trench_footing: stored
                .second_trench_footing
                .unwrap_or(stored.trench_footing),
            second_trench_size: stored.second_trench_size.unwrap_or(stored.trench_size),
        }
    }
}

#[derive(GraphQLInputObject)]
pub struct BackdropCalibrationInput {
    front_footing: f64,
    row_spacing: f64,
    unit_size: f64,
    rear_scale: f64,
    trench_footing: f64,
    trench_size: f64,
    second_trench_footing: f64,
    second_trench_size: f64,
}

#[derive(GraphQLObject)]
pub struct CalibratedBackdrop {
    pub backdrop: String,
    pub unit_kind: UnitKind,
    pub calibration: BackdropCalibration,
}

#[derive(Debug, GraphQLObject)]
pub struct CombatBackdrop {
    pub path: String,
    pub label: String,
}

#[derive(Debug, GraphQLObject)]
pub struct CombatBackdropCatalog {
    pub first: CombatBackdrop,
    pub rest: Vec<CombatBackdrop>,
}

type Catalog = BTreeMap<String, BTreeMap<UnitKind, BackdropCalibration>>;

#[derive(Deserialize)]
#[serde(untagged)]
enum StoredSettings {
    Shared(BackdropCalibration),
    PerUnit(BTreeMap<UnitKind, BackdropCalibration>),
}

const UNIT_KINDS: [UnitKind; 4] = [
    UnitKind::Infantry,
    UnitKind::Tank,
    UnitKind::FieldGun,
    UnitKind::Truck,
];
const FILE_NAME: &str = "backdrop-calibrations.json";
const ASSET_PREFIX: &str = "/assets/combat-backdrops-anime-v1/";

fn default_trench_footing() -> f64 {
    86.0
}

fn default_trench_size() -> f64 {
    35.0
}

impl BackdropCalibration {
    fn validate(&self) -> Result<(), String> {
        for (name, value, minimum, maximum) in [
            ("front footing", self.front_footing, 55.0, 98.0),
            ("row spacing", self.row_spacing, 0.0, 26.0),
            ("unit size", self.unit_size, 12.0, 40.0),
            ("rear scale", self.rear_scale, 35.0, 100.0),
            ("trench footing", self.trench_footing, 25.0, 98.0),
            ("trench size", self.trench_size, 10.0, 45.0),
            (
                "second trench footing",
                self.second_trench_footing,
                25.0,
                98.0,
            ),
            ("second trench size", self.second_trench_size, 10.0, 45.0),
        ] {
            if !value.is_finite() || value < minimum || value > maximum {
                return Err(format!("{name} must be between {minimum} and {maximum}"));
            }
        }
        Ok(())
    }
}

fn read(directory: &Path) -> Result<Catalog, String> {
    let bytes = fs::read(directory.join(FILE_NAME))
        .map_err(|error| format!("could not read backdrop calibrations: {error}"))?;
    let stored: BTreeMap<String, StoredSettings> = serde_json::from_slice(&bytes)
        .map_err(|error| format!("invalid backdrop calibrations: {error}"))?;
    let catalog: Catalog = stored
        .into_iter()
        .map(|(backdrop, settings)| {
            let units = match settings {
                StoredSettings::Shared(calibration) => UNIT_KINDS
                    .into_iter()
                    .map(|kind| (kind, calibration.clone()))
                    .collect(),
                StoredSettings::PerUnit(units) => units,
            };
            (backdrop, units)
        })
        .collect();
    for (backdrop, units) in &catalog {
        validate_backdrop(directory, backdrop)?;
        for calibration in units.values() {
            calibration.validate()?;
        }
    }
    Ok(catalog)
}

fn validate_backdrop(directory: &Path, backdrop: &str) -> Result<(), String> {
    let filename = backdrop
        .strip_prefix(ASSET_PREFIX)
        .ok_or("choose a backdrop from the local combat backdrop directory before saving")?;
    if !valid_backdrop_filename(filename) {
        return Err("invalid backdrop filename".into());
    }
    let file = directory
        .join("assets/combat-backdrops-anime-v1")
        .join(filename);
    if !file.is_file() {
        return Err(format!("backdrop does not exist: {filename}"));
    }
    Ok(())
}

fn valid_backdrop_filename(filename: &str) -> bool {
    filename.len() > ".png".len()
        && filename.ends_with(".png")
        && filename
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'.')
        && !filename.contains("..")
}

fn frontend_directory() -> PathBuf {
    env::var_os("FIGHTLINES_FRONTEND_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("public"))
}

/// Available artwork includes backdrops without saved calibrations.
pub fn available() -> FieldResult<CombatBackdropCatalog> {
    Ok(available_in(&frontend_directory())?)
}

fn available_in(directory: &Path) -> Result<CombatBackdropCatalog, String> {
    let entries = fs::read_dir(directory.join("assets/combat-backdrops-anime-v1"))
        .map_err(|error| format!("could not list combat backdrops: {error}"))?;
    let mut backdrops = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|error| format!("could not read combat backdrop: {error}"))?;
        let filename = entry.file_name();
        let Some(filename) = filename.to_str() else {
            continue;
        };
        if valid_backdrop_filename(filename) && entry.path().is_file() {
            backdrops.push(CombatBackdrop {
                path: format!("{ASSET_PREFIX}{filename}"),
                label: filename.trim_end_matches(".png").replace('-', " "),
            });
        }
    }
    backdrops.sort_by(|left, right| left.path.cmp(&right.path));
    let mut backdrops = backdrops.into_iter();
    Ok(CombatBackdropCatalog {
        first: backdrops
            .next()
            .ok_or("no combat backdrops are available")?,
        rest: backdrops.collect(),
    })
}

pub fn list() -> FieldResult<Vec<CalibratedBackdrop>> {
    Ok(read(&frontend_directory())?
        .into_iter()
        .flat_map(|(backdrop, units)| {
            units
                .into_iter()
                .map(move |(unit_kind, calibration)| CalibratedBackdrop {
                    backdrop: backdrop.clone(),
                    unit_kind,
                    calibration,
                })
        })
        .collect())
}

pub fn save(
    context: &Context,
    backdrop: String,
    unit_kind: UnitKind,
    input: BackdropCalibrationInput,
) -> FieldResult<CalibratedBackdrop> {
    let editor = context.editor.write()?;
    let calibration = BackdropCalibration {
        front_footing: input.front_footing,
        row_spacing: input.row_spacing,
        unit_size: input.unit_size,
        rear_scale: input.rear_scale,
        trench_footing: input.trench_footing,
        trench_size: input.trench_size,
        second_trench_footing: input.second_trench_footing,
        second_trench_size: input.second_trench_size,
    };
    persist(editor, &backdrop, unit_kind, &calibration)?;
    Ok(CalibratedBackdrop {
        backdrop,
        unit_kind,
        calibration,
    })
}

fn persist(
    editor: &Editor,
    backdrop: &str,
    unit_kind: UnitKind,
    calibration: &BackdropCalibration,
) -> Result<(), String> {
    let directory = &editor.frontend;
    validate_backdrop(directory, backdrop)?;
    calibration.validate()?;
    let _guard = editor
        .writes
        .lock()
        .map_err(|_| "calibration save lock is unavailable")?;
    let mut catalog = read(directory)?;
    catalog
        .entry(backdrop.to_owned())
        .or_default()
        .insert(unit_kind, calibration.clone());
    write_catalog(directory, &catalog)
}

fn write_catalog(directory: &Path, catalog: &Catalog) -> Result<(), String> {
    let mut bytes = serde_json::to_vec_pretty(catalog)
        .map_err(|error| format!("could not encode backdrop calibrations: {error}"))?;
    bytes.push(b'\n');
    let temporary = directory.join("backdrop-calibrations.json.tmp");
    fs::write(&temporary, bytes)
        .map_err(|error| format!("could not write backdrop calibrations: {error}"))?;
    fs::rename(&temporary, directory.join(FILE_NAME))
        .map_err(|error| format!("could not replace backdrop calibrations: {error}"))?;
    Ok(())
}

pub fn copy(
    context: &Context,
    source: String,
    destination: String,
    unit_kind: Option<UnitKind>,
) -> FieldResult<Vec<CalibratedBackdrop>> {
    Ok(copy_saved(
        context.editor.write()?,
        &source,
        &destination,
        unit_kind,
    )?)
}

fn copy_saved(
    editor: &Editor,
    source: &str,
    destination: &str,
    unit_kind: Option<UnitKind>,
) -> Result<Vec<CalibratedBackdrop>, String> {
    if source == destination {
        return Err("choose different source and destination backdrops".into());
    }
    let directory = &editor.frontend;
    validate_backdrop(directory, source)?;
    validate_backdrop(directory, destination)?;
    let _guard = editor
        .writes
        .lock()
        .map_err(|_| "calibration save lock is unavailable")?;
    let mut catalog = read(directory)?;
    let source_units = catalog
        .get(source)
        .filter(|units| !units.is_empty())
        .ok_or("the source backdrop has no saved calibrations")?;
    let units = match unit_kind {
        Some(kind) => {
            let calibration = source_units
                .get(&kind)
                .ok_or("the source backdrop has no saved calibration for this unit type")?;
            BTreeMap::from([(kind, calibration.clone())])
        }
        None => source_units.clone(),
    };
    catalog
        .entry(destination.to_owned())
        .or_default()
        .extend(units.clone());
    write_catalog(directory, &catalog)?;
    Ok(units
        .into_iter()
        .map(|(unit_kind, calibration)| CalibratedBackdrop {
            backdrop: destination.to_owned(),
            unit_kind,
            calibration,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;
    use std::sync::Mutex;

    #[test]
    fn legacy_trenches_inherit_custom_settings_and_new_rows_round_trip() -> TestResult {
        let legacy = serde_json::json!({
            "frontFooting": 94, "rowSpacing": 9, "unitSize": 25, "rearScale": 78,
            "trenchFooting": 73, "trenchSize": 29
        });
        let mut calibration: BackdropCalibration = serde_json::from_value(legacy)?;
        assert_eq!(calibration.second_trench_footing, 73.0);
        assert_eq!(calibration.second_trench_size, 29.0);
        calibration.second_trench_footing = 60.0;
        calibration.second_trench_size = 18.0;
        calibration.validate()?;
        let restored: BackdropCalibration =
            serde_json::from_slice(&serde_json::to_vec(&calibration)?)?;
        assert_eq!(restored, calibration);
        assert_eq!(restored.trench_footing, 73.0);
        assert_eq!(restored.trench_size, 29.0);
        Ok(())
    }

    #[test]
    fn available_backdrops_follow_assets_without_requiring_calibrations() -> TestResult {
        let directory = env::temp_dir().join(format!(
            "fightlines-backdrop-options-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_nanos()
        ));
        assert!(available_in(&directory).is_err());
        let assets = directory.join("assets/combat-backdrops-anime-v1");
        fs::create_dir_all(&assets)?;
        assert!(available_in(&directory).is_err());
        for filename in ["road.png", "snowy-road.png", "notes.txt", "bad..name.png"] {
            fs::write(assets.join(filename), [])?;
        }
        fs::create_dir(assets.join("directory.png"))?;
        let catalog = available_in(&directory)?;
        assert_eq!(catalog.first.path, format!("{ASSET_PREFIX}road.png"));
        assert_eq!(catalog.first.label, "road");
        assert_eq!(catalog.rest.len(), 1);
        let snowy = catalog.rest.first().ok_or("missing snowy road option")?;
        assert_eq!(snowy.path, format!("{ASSET_PREFIX}snowy-road.png"));
        assert_eq!(snowy.label, "snowy road");
        assert!(!directory.join(FILE_NAME).exists());

        fs::write(assets.join("new-backdrop.png"), [])?;
        let updated = available_in(&directory)?;
        assert_eq!(
            updated.first.path,
            format!("{ASSET_PREFIX}new-backdrop.png")
        );
        assert_eq!(updated.rest.len(), 2);
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[test]
    fn copying_one_unit_preserves_other_types_and_rejects_missing_source_settings() -> TestResult {
        let directory = env::temp_dir().join(format!(
            "fightlines-copy-unit-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_nanos()
        ));
        let assets = directory.join("assets/combat-backdrops-anime-v1");
        fs::create_dir_all(&assets)?;
        for name in ["source.png", "destination.png"] {
            fs::write(assets.join(name), [])?;
        }
        let source = format!("{ASSET_PREFIX}source.png");
        let destination = format!("{ASSET_PREFIX}destination.png");
        let calibration = |size| BackdropCalibration {
            front_footing: 80.0,
            row_spacing: 10.0,
            unit_size: size,
            rear_scale: 70.0,
            trench_footing: 85.0,
            trench_size: 30.0,
            second_trench_footing: 85.0,
            second_trench_size: 30.0,
        };
        let source_units = BTreeMap::from([
            (UnitKind::Infantry, calibration(20.0)),
            (UnitKind::Tank, calibration(30.0)),
        ]);
        let destination_units = BTreeMap::from([
            (UnitKind::Infantry, calibration(25.0)),
            (UnitKind::Tank, calibration(35.0)),
            (UnitKind::Truck, calibration(40.0)),
            (UnitKind::FieldGun, calibration(32.0)),
        ]);
        write_catalog(
            &directory,
            &BTreeMap::from([
                (source.clone(), source_units.clone()),
                (destination.clone(), destination_units.clone()),
            ]),
        )?;
        let editor = Editor {
            directory: directory.clone(),
            frontend: directory.clone(),
            writes: Mutex::new(()),
        };
        let copied = copy_saved(&editor, &source, &destination, Some(UnitKind::Infantry))?;
        assert_eq!(copied.len(), 1);
        let copied_unit = copied.first().ok_or("missing copied unit")?;
        assert_eq!(copied_unit.unit_kind, UnitKind::Infantry);
        let after_one = read(&directory)?;
        let target = after_one.get(&destination).ok_or("missing destination")?;
        assert_eq!(
            target.get(&UnitKind::Infantry),
            source_units.get(&UnitKind::Infantry)
        );
        for kind in [UnitKind::Tank, UnitKind::Truck, UnitKind::FieldGun] {
            assert_eq!(target.get(&kind), destination_units.get(&kind));
        }
        assert_eq!(after_one.get(&source), Some(&source_units));

        let before_rejection = fs::read(directory.join(FILE_NAME))?;
        let error = copy_saved(&editor, &source, &destination, Some(UnitKind::Truck));
        assert!(error.is_err());
        assert_eq!(before_rejection, fs::read(directory.join(FILE_NAME))?);

        let all_copied = copy_saved(&editor, &source, &destination, None)?;
        assert_eq!(all_copied.len(), 2);
        let after_all = read(&directory)?;
        let target = after_all.get(&destination).ok_or("missing destination")?;
        for kind in [UnitKind::Infantry, UnitKind::Tank] {
            assert_eq!(target.get(&kind), source_units.get(&kind));
        }
        for kind in [UnitKind::Truck, UnitKind::FieldGun] {
            assert_eq!(target.get(&kind), destination_units.get(&kind));
        }
        fs::remove_dir_all(directory)?;
        Ok(())
    }

    #[test]
    fn saves_preserve_other_backdrops_and_reject_invalid_updates() -> TestResult {
        let directory = env::temp_dir().join(format!(
            "fightlines-calibration-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_nanos()
        ));
        fs::create_dir_all(&directory)?;
        fs::create_dir_all(directory.as_path().join("assets/combat-backdrops-anime-v1"))?;
        for name in ["road", "plains", "forest"] {
            fs::write(
                directory
                    .as_path()
                    .join(format!("assets/combat-backdrops-anime-v1/{name}.png")),
                [],
            )?;
        }
        let legacy = serde_json::json!({ format!("{ASSET_PREFIX}road.png"): { "frontFooting": 98, "rowSpacing": 5, "unitSize": 35, "rearScale": 84 } });
        fs::write(
            directory.as_path().join(FILE_NAME),
            serde_json::to_vec(&legacy)?,
        )?;
        let migrated = read(directory.as_path())?;
        let migrated_road = migrated
            .get(&format!("{ASSET_PREFIX}road.png"))
            .ok_or("missing migrated road")?;
        assert_eq!(migrated_road.len(), 4);
        assert!(
            migrated_road
                .values()
                .all(|settings| settings.unit_size == 35.0)
        );
        assert!(
            migrated_road
                .values()
                .all(|settings| (settings.trench_footing == 86.0) && (settings.trench_size == 35.0))
        );
        let editor = Editor {
            directory: directory.as_path().into(),
            frontend: directory.as_path().into(),
            writes: Mutex::new(()),
        };
        let mut settings = BackdropCalibration {
            front_footing: 94.0,
            row_spacing: 9.0,
            unit_size: 25.0,
            rear_scale: 78.0,
            trench_footing: 86.0,
            trench_size: 35.0,
            second_trench_footing: 86.0,
            second_trench_size: 35.0,
        };
        persist(
            &editor,
            &format!("{ASSET_PREFIX}road.png"),
            UnitKind::Tank,
            &settings,
        )?;
        settings.unit_size = 30.0;
        settings.trench_footing = 65.0;
        settings.trench_size = 25.0;
        settings.second_trench_footing = 78.0;
        settings.second_trench_size = 18.0;
        persist(
            &editor,
            &format!("{ASSET_PREFIX}plains.png"),
            UnitKind::Tank,
            &settings,
        )?;
        persist(
            &editor,
            &format!("{ASSET_PREFIX}road.png"),
            UnitKind::Infantry,
            &settings,
        )?;
        let catalog = read(directory.as_path())?;
        let road = catalog
            .get(&format!("{ASSET_PREFIX}road.png"))
            .ok_or("missing road")?;
        assert_eq!(
            road.get(&UnitKind::Tank).ok_or("missing tank")?.unit_size,
            25.0
        );
        assert_eq!(
            road.get(&UnitKind::Infantry)
                .ok_or("missing infantry")?
                .unit_size,
            30.0
        );
        assert_eq!(
            road.get(&UnitKind::FieldGun)
                .ok_or("missing field gun")?
                .unit_size,
            35.0
        );
        assert_eq!(
            road.get(&UnitKind::Truck).ok_or("missing truck")?.unit_size,
            35.0
        );
        assert_eq!(
            road.get(&UnitKind::Tank)
                .ok_or("missing tank")?
                .trench_footing,
            86.0
        );
        assert_eq!(
            road.get(&UnitKind::Infantry)
                .ok_or("missing infantry")?
                .trench_footing,
            65.0
        );
        assert_eq!(
            road.get(&UnitKind::Tank).ok_or("missing tank")?.trench_size,
            35.0
        );
        assert_eq!(
            road.get(&UnitKind::Infantry)
                .ok_or("missing infantry")?
                .trench_size,
            25.0
        );
        let road_before = road.clone();
        assert_eq!(road.get(&UnitKind::Infantry), Some(&settings));
        let copied = copy_saved(
            &editor,
            &format!("{ASSET_PREFIX}plains.png"),
            &format!("{ASSET_PREFIX}road.png"),
            None,
        )?;
        assert_eq!(copied.len(), 1);
        let after_copy = read(directory.as_path())?;
        let road_after = after_copy
            .get(&format!("{ASSET_PREFIX}road.png"))
            .ok_or("missing copied road")?;
        assert_eq!(
            road_after
                .get(&UnitKind::Tank)
                .ok_or("missing copied tank")?
                .unit_size,
            30.0
        );
        assert_eq!(
            road_after
                .get(&UnitKind::Tank)
                .ok_or("missing copied tank")?
                .trench_footing,
            65.0
        );
        assert_eq!(
            road_after
                .get(&UnitKind::Tank)
                .ok_or("missing copied tank")?
                .trench_size,
            25.0
        );
        assert_eq!(
            road_after.get(&UnitKind::Infantry),
            road_before.get(&UnitKind::Infantry)
        );
        assert_eq!(
            road_after.get(&UnitKind::FieldGun),
            road_before.get(&UnitKind::FieldGun)
        );
        assert_eq!(
            after_copy
                .get(&format!("{ASSET_PREFIX}plains.png"))
                .ok_or("missing source")?
                .len(),
            1
        );
        let before = fs::read(directory.as_path().join(FILE_NAME))?;
        for invalid_size in [9.0, 46.0, f64::NAN, f64::INFINITY] {
            settings.second_trench_size = invalid_size;
            assert!(
                persist(
                    &editor,
                    &format!("{ASSET_PREFIX}road.png"),
                    UnitKind::Infantry,
                    &settings
                )
                .is_err()
            );
            assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);
        }
        settings.second_trench_size = 18.0;
        for invalid_footing in [24.0, 99.0, f64::NAN, f64::NEG_INFINITY] {
            settings.second_trench_footing = invalid_footing;
            assert!(
                persist(
                    &editor,
                    &format!("{ASSET_PREFIX}road.png"),
                    UnitKind::Infantry,
                    &settings
                )
                .is_err()
            );
            assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);
        }
        settings.second_trench_footing = 78.0;
        assert!(
            copy_saved(
                &editor,
                &format!("{ASSET_PREFIX}road.png"),
                &format!("{ASSET_PREFIX}road.png"),
                None,
            )
            .is_err()
        );
        assert!(
            copy_saved(
                &editor,
                &format!("{ASSET_PREFIX}forest.png"),
                &format!("{ASSET_PREFIX}road.png"),
                None,
            )
            .is_err()
        );
        assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);

        assert_eq!(read(directory.as_path())?.len(), 2);
        for invalid_size in [9.0, 46.0, f64::NAN] {
            settings.trench_size = invalid_size;
            assert!(
                persist(
                    &editor,
                    &format!("{ASSET_PREFIX}road.png"),
                    UnitKind::Infantry,
                    &settings
                )
                .is_err()
            );
            assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);
        }
        settings.trench_size = 25.0;
        settings.trench_footing = 99.0;
        assert!(
            persist(
                &editor,
                &format!("{ASSET_PREFIX}road.png"),
                UnitKind::Infantry,
                &settings
            )
            .is_err()
        );
        assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);
        settings.trench_footing = 65.0;
        settings.rear_scale = 101.0;
        assert!(
            persist(
                &editor,
                &format!("{ASSET_PREFIX}road.png"),
                UnitKind::Tank,
                &settings
            )
            .is_err()
        );
        assert_eq!(before, fs::read(directory.as_path().join(FILE_NAME))?);
        for invalid in [
            "../road.png",
            "/assets/combat-backdrops-anime-v1/../road.png",
            "https://example.com/road.png",
            "/assets/combat-backdrops-anime-v1/missing.png",
        ] {
            assert!(validate_backdrop(directory.as_path(), invalid).is_err());
        }
        fs::write(directory.as_path().join(FILE_NAME), "invalid json")?;
        settings.rear_scale = 78.0;
        assert!(
            persist(
                &editor,
                &format!("{ASSET_PREFIX}road.png"),
                UnitKind::Tank,
                &settings
            )
            .is_err()
        );
        assert_eq!(
            fs::read_to_string(directory.as_path().join(FILE_NAME))?,
            "invalid json"
        );
        fs::remove_dir_all(&directory)?;
        Ok(())
    }
}
