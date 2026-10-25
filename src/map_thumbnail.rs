//! Derived browser-rendered map images. Definition fingerprints keep cache URLs
//! stable across processes; bump the render version when shared artwork changes.
use crate::map_definition::MapDefinition;
use base64::{Engine, engine::general_purpose::STANDARD};
use std::{fs, io, path::Path};

const RENDER_VERSION: &str = "v1";
const MAX_PNG_BYTES: usize = 1_000_000;

pub fn url(definition: &MapDefinition) -> Result<String, serde_json::Error> {
    // FNV-1a is a stable cache fingerprint, not a security or identity token.
    let hash = serde_json::to_vec(definition)?
        .into_iter()
        .fold(0xcbf29ce484222325_u64, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3)
        });
    Ok(format!("/map-thumbnails/{RENDER_VERSION}-{hash:016x}.png"))
}

pub fn save(frontend: &Path, definition: &MapDefinition, encoded: &str) -> io::Result<()> {
    let invalid = |message: &str| io::Error::new(io::ErrorKind::InvalidInput, message.to_owned());
    if encoded.len() > MAX_PNG_BYTES * 4 / 3 + 4 {
        return Err(invalid("map thumbnail exceeds 1 MB"));
    }
    let bytes = STANDARD
        .decode(encoded)
        .map_err(|error| invalid(&error.to_string()))?;
    // Only accept bounded PNG thumbnails, never arbitrary public file contents.
    if bytes.len() < 33
        || !bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.get(12..16) != Some(b"IHDR")
    {
        return Err(invalid("map thumbnail must be a PNG"));
    }
    let width = u32::from_be_bytes(
        bytes[16..20]
            .try_into()
            .map_err(|_| invalid("missing PNG width"))?,
    );
    let height = u32::from_be_bytes(
        bytes[20..24]
            .try_into()
            .map_err(|_| invalid("missing PNG height"))?,
    );
    let longest = u32::from(definition.width.max(definition.height)).max(1);
    let expected_width = (u32::from(definition.width) * 320 / longest).max(1);
    let expected_height = (u32::from(definition.height) * 320 / longest).max(1);
    if width != expected_width || height != expected_height {
        return Err(invalid("map thumbnail dimensions do not match the map"));
    }
    let relative = url(definition).map_err(io::Error::other)?;
    let destination = frontend.join(relative.trim_start_matches('/'));
    let directory = destination
        .parent()
        .ok_or_else(|| invalid("missing thumbnail directory"))?;
    fs::create_dir_all(directory)?;
    let temporary = destination.with_extension("png.tmp");
    fs::write(&temporary, bytes)?;
    fs::rename(temporary, destination)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{map::MapTheme, test_support::TestResult};

    fn definition() -> MapDefinition {
        MapDefinition {
            description: "thumbnail test".into(),
            width: 1,
            height: 1,
            theme: MapTheme::GreenForest,
            features: vec![],
            depots: vec![],
            units: vec![],
        }
    }

    #[test]
    fn fingerprint_is_stable_and_changes_with_saved_content() -> TestResult<()> {
        let original = definition();
        let original_url = url(&original)?;
        assert_eq!(original_url, url(&original)?);
        let mut changed = original.clone();
        changed.theme = MapTheme::Snow;
        assert_ne!(original_url, url(&changed)?);
        changed = original;
        changed.width = 2;
        assert_ne!(original_url, url(&changed)?);
        Ok(())
    }

    #[test]
    fn stores_png_atomically_and_rejects_bad_images_without_replacing_it() -> TestResult<()> {
        let directory =
            std::env::temp_dir().join(format!("fightlines-thumbnail-{}", std::process::id()));
        let definition = definition();
        let png = include_bytes!("../tests/fixtures/map-thumbnail.png");
        save(&directory, &definition, &STANDARD.encode(png))?;
        let destination = directory.join(url(&definition)?.trim_start_matches('/'));
        assert_eq!(fs::read(&destination)?, png);
        for invalid in [
            "invalid base64".to_owned(),
            STANDARD.encode(b"not a PNG"),
            "a".repeat(1_400_000),
        ] {
            assert!(save(&directory, &definition, &invalid).is_err());
            assert_eq!(fs::read(&destination)?, png);
        }
        let mut wrong_dimensions = definition;
        wrong_dimensions.width = 2;
        assert!(save(&directory, &wrong_dimensions, &STANDARD.encode(png)).is_err());
        assert!(!destination.with_extension("png.tmp").exists());
        fs::remove_dir_all(directory)?;
        Ok(())
    }
}
