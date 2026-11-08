//! Private, durable player feedback, independent of games and operational logs.
use crate::{
    app_version,
    graphql::Context,
    server_log,
    storage_budget::{self, Budget, Capacity, Usage},
};
use juniper::FieldResult;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_CHARACTERS: usize = 5000;
const MAX_STORAGE_BYTES: u64 = 32 * 1024 * 1024;
const MAX_STORAGE_ENTRIES: u64 = 4096;
static NEXT_FILE: AtomicU64 = AtomicU64::new(0);

#[derive(Deserialize)]
struct SavedRecord {
    submitted_at_unix_ms: u128,
    server_version: String,
    text: String,
}

#[derive(juniper::GraphQLObject)]
pub struct FeedbackRecord {
    id: String,
    submitted_at: String,
    server_version: String,
    text: String,
}

#[derive(juniper::GraphQLObject)]
pub struct FeedbackReadError {
    id: String,
    message: String,
}

#[derive(juniper::GraphQLObject)]
pub struct FeedbackPage {
    records: Vec<FeedbackRecord>,
    errors: Vec<FeedbackReadError>,
    total: i32,
    next_offset: Option<i32>,
}

pub struct Directory {
    path: PathBuf,
    budget: Budget,
}

struct FeedbackText(String);

impl FeedbackText {
    fn parse(text: &str) -> FieldResult<Self> {
        let text = text.trim();
        if text.is_empty() {
            return Err(juniper::FieldError::from("please enter some feedback."));
        }
        if text.chars().count() > MAX_CHARACTERS {
            return Err(juniper::FieldError::from(
                "feedback must be 5000 characters or fewer.",
            ));
        }
        Ok(Self(text.to_owned()))
    }
}

#[derive(Serialize)]
struct Record<'a> {
    submitted_at_unix_ms: u128,
    server_version: &'static str,
    text: &'a str,
}

impl Directory {
    /// List newest submissions in bounded pages. Corrupt files remain visible as
    /// errors without concealing otherwise readable feedback.
    pub fn list(&self, offset: i32) -> FieldResult<FeedbackPage> {
        if offset < 0 {
            return Err("feedback offset must be nonnegative.".into());
        }
        let mut files = (|| -> io::Result<Vec<fs::DirEntry>> {
            let mut files = Vec::new();
            for root in crate::deployment::storage_roots(&self.path, "feedback")? {
                files.extend(fs::read_dir(root)?.collect::<io::Result<Vec<_>>>()?);
            }
            Ok(files)
        })().map_err(|error| {
            tracing::error!(event = "feedback_list_failed", error = %error, "could not list feedback");
            server_log::internal_error("could not list feedback.")
        })?;
        files.retain(|entry| {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            name.starts_with("feedback-") && name.ends_with(".json")
        });
        files.sort_by_key(|entry| std::cmp::Reverse(entry.file_name()));
        let total = files.len() as i32;
        let mut records = Vec::new();
        let mut errors = Vec::new();
        for entry in files.into_iter().skip(offset as usize).take(50) {
            let id = entry.file_name().to_string_lossy().into_owned();
            let read = (|| -> io::Result<SavedRecord> {
                let metadata = fs::symlink_metadata(entry.path())?;
                if !metadata.is_file() || metadata.len() > 64 * 1024 {
                    return Err(io::Error::other("invalid feedback file"));
                }
                serde_json::from_slice(&fs::read(entry.path())?).map_err(io::Error::other)
            })();
            match read {
                Ok(record) => records.push(FeedbackRecord {
                    id,
                    submitted_at: record.submitted_at_unix_ms.to_string(),
                    server_version: record.server_version,
                    text: record.text,
                }),
                Err(_) => errors.push(FeedbackReadError {
                    id,
                    message: "could not read this feedback submission.".into(),
                }),
            }
        }
        Ok(FeedbackPage {
            records,
            errors,
            total,
            next_offset: (offset.saturating_add(50) < total).then_some(offset.saturating_add(50)),
        })
    }

    pub fn open(path: PathBuf, frontend: &Path) -> io::Result<Self> {
        // Check the existing ancestor before creating anything under a public root.
        let frontend = frontend.canonicalize()?;
        let mut ancestor = path.clone();
        while !ancestor.exists() {
            if !ancestor.pop() || ancestor.as_os_str().is_empty() {
                ancestor = std::env::current_dir()?;
                break;
            }
        }
        if ancestor.canonicalize()?.starts_with(&frontend) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "FIGHTLINES_FEEDBACK_DIR must be outside FIGHTLINES_FRONTEND_DIR",
            ));
        }
        let mut builder = fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        builder.create(&path)?;
        // A missing component followed by `..` can hide the final location
        // from the ancestor check. Resolve it before writing any feedback.
        let path = path.canonicalize()?;
        if path.starts_with(&frontend) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "FIGHTLINES_FEEDBACK_DIR must be outside FIGHTLINES_FRONTEND_DIR",
            ));
        }
        // Verify write access before serving the feedback form.
        let probe = path.join(format!(".probe-{}", file_id()?));
        private_file(&probe)?.sync_all()?;
        fs::remove_file(probe)?;
        let used = storage_usage(&path)?;
        Ok(Self {
            path,
            budget: Budget::new(
                Capacity {
                    bytes: MAX_STORAGE_BYTES,
                    entries: MAX_STORAGE_ENTRIES,
                },
                used,
            ),
        })
    }

    fn save(&self, text: FeedbackText) -> io::Result<()> {
        let submitted_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(io::Error::other)?;
        let id = file_id()?;
        let pending = self.path.join(format!(".{id}.pending"));
        let published = self.path.join(format!("feedback-{id}.json"));
        let record = Record {
            submitted_at_unix_ms: submitted_at.as_millis(),
            server_version: app_version::current(),
            text: &text.0,
        };
        let mut bytes = serde_json::to_vec_pretty(&record)?;
        bytes.push(b'\n');
        let reservation = self.budget.reserve(Usage::file(bytes.len() as u64))?;
        let mut file = private_file(&pending)?;
        let result = (|| -> io::Result<()> {
            file.write_all(&bytes)?;
            file.sync_all()?;
            // Publish a complete record without overwriting an existing submission.
            fs::hard_link(&pending, &published)?;
            #[cfg(unix)]
            if let Err(error) = File::open(&self.path).and_then(|directory| directory.sync_all()) {
                if let Err(cleanup) = fs::remove_file(&published) {
                    tracing::error!(event = "feedback_rollback_failed", error = %cleanup, "could not roll back feedback publication");
                }
                return Err(error);
            }
            Ok(())
        })();
        drop(file);
        if let Err(error) = fs::remove_file(&pending) {
            tracing::error!(event = "feedback_cleanup_failed", error = %error, "could not clean up temporary feedback file");
        }
        if published.exists() || pending.exists() {
            reservation.retain();
        }
        result
    }
}

fn storage_usage(path: &Path) -> io::Result<Usage> {
    storage_budget::scan(path, &|_, metadata| {
        Ok(if metadata.is_dir() {
            Usage::directory()
        } else {
            Usage::file(metadata.len())
        })
    })
}

fn file_id() -> io::Result<String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?;
    Ok(format!(
        "{}-{}-{}",
        now.as_nanos(),
        std::process::id(),
        NEXT_FILE.fetch_add(1, Ordering::Relaxed)
    ))
}

fn private_file(path: &Path) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}

pub fn submit(context: &Context, text: &str) -> FieldResult<bool> {
    let text = FeedbackText::parse(text)?;
    let directory = context.feedback.as_ref().ok_or_else(|| {
        server_log::internal_error("feedback is unavailable. please try again later.")
    })?;
    directory.save(text).map_err(|error| {
        if error.kind() == io::ErrorKind::StorageFull {
            return storage_budget::full("feedback storage is full. new feedback cannot be saved.");
        }
        tracing::error!(event = "feedback_save_failed", error = %error, "could not save feedback");
        server_log::internal_error("could not save your feedback. please try again.")
    })?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};

    #[test]
    fn admin_pages_are_bounded_newest_first_and_isolate_corrupt_entries() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!("fightlines-feedback-list-{}", file_id()?));
        let frontend = root.join("public");
        fs::create_dir_all(&frontend)?;
        let directory = Directory::open(root.join("feedback"), &frontend)?;
        for number in 0..52 {
            directory.save(FeedbackText::parse(&format!("submission {number}")).fixture()?)?;
        }
        let page = directory.list(0).fixture()?;
        assert_eq!(page.total, 52);
        assert_eq!(page.records.len(), 50);
        assert_eq!(page.next_offset, Some(50));
        assert_eq!(page.records.first().fixture()?.text, "submission 51");
        let older = directory.list(50).fixture()?;
        assert_eq!(older.records.len(), 2);
        assert_eq!(older.next_offset, None);
        let newest = page.records.first().fixture()?.id.clone();
        fs::write(directory.path.join(&newest), b"invalid json")?;
        let damaged = directory.list(0).fixture()?;
        assert_eq!(damaged.records.len(), 49);
        assert_eq!(damaged.errors.first().fixture()?.id, newest);
        assert!(directory.list(-1).is_err());
        assert!(directory.list(i32::MAX).fixture()?.records.is_empty());
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(
                root.join("public"),
                directory.path.join("feedback-zzzz.json"),
            )?;
            assert_eq!(directory.list(0).fixture()?.errors.len(), 2);
        }
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn storage_limit_survives_reopening_and_failed_writes_release_capacity() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!("fightlines-feedback-budget-{}", file_id()?));
        let frontend = root.join("public");
        fs::create_dir_all(&frontend)?;
        let path = root.join("feedback");
        let mut directory = Directory::open(path.clone(), &frontend)?;
        directory.budget = Budget::new(
            Capacity {
                bytes: 8192,
                entries: 1,
            },
            Usage::default(),
        );
        let offline = root.join("offline");
        fs::rename(&path, &offline)?;
        assert!(
            directory
                .save(FeedbackText::parse("retry me").fixture()?)
                .is_err()
        );
        fs::rename(&offline, &path)?;
        directory.save(FeedbackText::parse("saved").fixture()?)?;
        let error = directory
            .save(FeedbackText::parse("full").fixture()?)
            .err()
            .fixture()?;
        assert_eq!(error.kind(), io::ErrorKind::StorageFull);
        assert_eq!(fs::read_dir(&path)?.count(), 1);
        let mut reopened = Directory::open(path.clone(), &frontend)?;
        reopened.budget = Budget::new(
            Capacity {
                bytes: 8192,
                entries: 1,
            },
            storage_usage(&path)?,
        );
        assert_eq!(
            reopened
                .save(FeedbackText::parse("still full").fixture()?)
                .err()
                .fixture()?
                .kind(),
            io::ErrorKind::StorageFull
        );
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn storage_charges_serialized_unicode_and_json_escapes() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!("fightlines-feedback-bytes-{}", file_id()?));
        let frontend = root.join("public");
        fs::create_dir_all(&frontend)?;
        let path = root.join("feedback");
        let mut directory = Directory::open(path.clone(), &frontend)?;
        directory.budget = Budget::new(
            Capacity {
                bytes: 16384,
                entries: 10,
            },
            Usage::default(),
        );
        for text in ["😀".repeat(5000), format!("x{}x", "\0".repeat(4998))] {
            assert_eq!(
                directory
                    .save(FeedbackText::parse(&text).fixture()?)
                    .err()
                    .fixture()?
                    .kind(),
                io::ErrorKind::StorageFull
            );
        }
        assert_eq!(fs::read_dir(&path)?.count(), 0);
        directory.save(FeedbackText::parse(&"x".repeat(5000)).fixture()?)?;
        assert_eq!(fs::read_dir(&path)?.count(), 1);
        fs::remove_dir_all(root)?;
        Ok(())
    }

    #[test]
    fn validates_text_and_preserves_unicode_and_paragraphs() -> TestResult<()> {
        assert!(FeedbackText::parse(" \n\t ").is_err());
        assert!(FeedbackText::parse(&"x".repeat(MAX_CHARACTERS + 1)).is_err());
        assert!(FeedbackText::parse(&"é".repeat(MAX_CHARACTERS)).is_ok());
        assert_eq!(
            FeedbackText::parse("  hello\n\n世界  ").fixture()?.0,
            "hello\n\n世界"
        );
        Ok(())
    }

    #[test]
    fn rejects_public_storage_through_a_missing_parent() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!("fightlines-feedback-path-{}", file_id()?));
        let frontend = root.join("public");
        fs::create_dir_all(&frontend)?;
        let path = root.join("missing/../public/feedback");
        let rejected = Directory::open(path, &frontend).is_err();
        fs::remove_dir_all(root)?;
        assert!(rejected, "feedback storage must stay outside the frontend");
        Ok(())
    }

    #[test]
    fn persists_separate_private_records_across_reopening() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!("fightlines-feedback-{}", file_id()?));
        let frontend = root.join("public");
        fs::create_dir_all(&frontend)?;
        let path = root.join("feedback");
        Directory::open(path.clone(), &frontend)?
            .save(FeedbackText::parse("  hello\n世界  ").fixture()?)?;
        Directory::open(path.clone(), &frontend)?.save(FeedbackText::parse("second").fixture()?)?;
        let files = fs::read_dir(&path)?.collect::<Result<Vec<_>, _>>()?;
        assert_eq!(files.len(), 2);
        let mut texts = Vec::new();
        for entry in files {
            assert_eq!(
                entry.path().extension().and_then(|value| value.to_str()),
                Some("json")
            );
            let value: serde_json::Value = serde_json::from_slice(&fs::read(entry.path())?)?;
            texts.push(
                value["text"]
                    .as_str()
                    .ok_or("missing feedback text")?
                    .to_owned(),
            );
            assert!(value["submitted_at_unix_ms"].as_u64().is_some());
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                assert_eq!(entry.metadata()?.permissions().mode() & 0o777, 0o600);
            }
        }
        texts.sort();
        assert_eq!(texts, vec!["hello\n世界", "second"]);
        // Missing storage reports failure rather than accepting and dropping text.
        let directory = Directory::open(path.clone(), &frontend)?;
        fs::remove_dir_all(&path)?;
        assert!(
            directory
                .save(FeedbackText::parse("unsaved").fixture()?)
                .is_err()
        );
        assert!(Directory::open(frontend.join("feedback"), &frontend).is_err());
        assert!(!frontend.join("feedback").exists());
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
