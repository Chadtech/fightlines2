//! Private, durable player feedback, independent of games and operational logs.
use crate::{app_version, graphql::Context, server_log};
use juniper::FieldResult;
use serde::Serialize;
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

const MAX_CHARACTERS: usize = 5000;
static NEXT_FILE: AtomicU64 = AtomicU64::new(0);

pub struct Directory(PathBuf);

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
        Ok(Self(path))
    }

    fn save(&self, text: FeedbackText) -> io::Result<()> {
        let submitted_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(io::Error::other)?;
        let id = file_id()?;
        let pending = self.0.join(format!(".{id}.pending"));
        let published = self.0.join(format!("feedback-{id}.json"));
        let record = Record {
            submitted_at_unix_ms: submitted_at.as_millis(),
            server_version: app_version::current(),
            text: &text.0,
        };
        let mut bytes = serde_json::to_vec_pretty(&record)?;
        bytes.push(b'\n');
        let mut file = private_file(&pending)?;
        let result = (|| -> io::Result<()> {
            file.write_all(&bytes)?;
            file.sync_all()?;
            // Publish a complete record without overwriting an existing submission.
            fs::hard_link(&pending, &published)?;
            #[cfg(unix)]
            if let Err(error) = File::open(&self.0).and_then(|directory| directory.sync_all()) {
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
        result
    }
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
        fs::remove_dir_all(&path)?;
        assert!(
            Directory(path)
                .save(FeedbackText::parse("unsaved").fixture()?)
                .is_err()
        );
        assert!(Directory::open(frontend.join("feedback"), &frontend).is_err());
        assert!(!frontend.join("feedback").exists());
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
