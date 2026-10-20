//! Private authoritative archives, independent of HTTP and viewer projections.
use crate::{
    lobby::Opponent,
    lobby_id::LobbyId,
    map_type::MapType,
    scenario::{PlayerNumber, Scenario},
    turns::{self, GameOutcome, MoveOrderInput, TurnResolution, Turns},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

const FORMAT_VERSION: u32 = 1;

pub struct Directory(PathBuf);

pub struct GameLog {
    directory: PathBuf,
    next_record: u64,
}

#[derive(Serialize, Deserialize)]
pub struct RecordedPlayer {
    pub player_number: PlayerNumber,
    pub name: String,
    /// Human, Ai (Easy), or AiMedium; never a browser credential.
    pub opponent: Opponent,
}

#[derive(Serialize, Deserialize)]
pub struct GameStarted {
    pub game_id: LobbyId,
    pub name: String,
    pub map_type: MapType,
    pub players: Vec<RecordedPlayer>,
    pub scenario: Scenario,
    pub server_version: String,
    pub build_revision: Option<String>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Submission {
    pub player_number: PlayerNumber,
    pub orders: Vec<MoveOrderInput>,
}

#[derive(Serialize, Deserialize)]
pub struct SubmissionResult {
    pub turn_number: i32,
    pub submissions: Vec<Submission>,
    pub scenario: Scenario,
    pub next_turn_number: i32,
    pub submitted_players: Vec<PlayerNumber>,
    pub outcome: Option<GameOutcome>,
    pub resolution: Option<TurnResolution>,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", content = "data")]
enum Event {
    Started(GameStarted),
    Submitted(SubmissionResult),
}

#[derive(Serialize, Deserialize)]
struct Record {
    format_version: u32,
    recorded_at_unix_ms: u128,
    event: Event,
}

fn now() -> io::Result<std::time::Duration> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)
}

impl Directory {
    pub fn open(path: PathBuf) -> io::Result<Self> {
        fs::create_dir_all(&path)?;
        // Check actual write access before accepting players, even if it exists.
        let probe = path.join(format!(
            ".probe-{}-{}",
            std::process::id(),
            now()?.as_nanos()
        ));
        private_file(&probe)?.sync_all()?;
        fs::remove_file(probe)?;
        Ok(Self(path))
    }

    pub fn start(&self, started: GameStarted) -> io::Result<GameLog> {
        // A fresh directory prevents overwrites even when a seed/ID is reused.
        let id = started.game_id.to_string();
        if id.len() != 32 || !id.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid game log ID",
            ));
        }
        let directory = self.0.join(format!("{id}-{}", now()?.as_nanos()));
        let mut builder = fs::DirBuilder::new();
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        builder.create(&directory)?;
        sync_directory(&self.0)?;
        let mut log = GameLog {
            directory,
            next_record: 0,
        };
        if let Err(error) = log.record(Event::Started(started)) {
            if let Err(cleanup) = fs::remove_dir(&log.directory) {
                eprintln!("Game log directory cleanup failed: {cleanup}");
            }
            return Err(error);
        }
        Ok(log)
    }
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

fn sync_directory(directory: &Path) -> io::Result<()> {
    #[cfg(unix)]
    File::open(directory)?.sync_all()?;
    Ok(())
}

impl GameLog {
    pub fn submitted(&mut self, result: SubmissionResult) -> io::Result<()> {
        self.record(Event::Submitted(result))
    }

    fn record(&mut self, event: Event) -> io::Result<()> {
        let record = Record {
            format_version: FORMAT_VERSION,
            recorded_at_unix_ms: now()?.as_millis(),
            event,
        };
        // Serialize before touching disk. Incomplete writes never become records.
        let mut bytes = serde_json::to_vec_pretty(&record)?;
        bytes.push(b'\n');
        let destination = self.directory.join(format!("{:08}.json", self.next_record));
        let temporary = self
            .directory
            .join(format!("{:08}.pending", self.next_record));
        let write = || -> io::Result<()> {
            let mut file = private_file(&temporary)?;
            file.write_all(&bytes)?;
            file.sync_all()?;
            // Publish atomically without replacing an existing record.
            fs::hard_link(&temporary, &destination)?;
            if let Err(error) = sync_directory(&self.directory) {
                // Do not leave a published transition after reporting failure.
                if let Err(cleanup) = fs::remove_file(&destination) {
                    eprintln!("Game log rollback failed: {cleanup}");
                }
                return Err(error);
            }
            Ok(())
        };
        let result = write();
        if let Err(error) = fs::remove_file(&temporary)
            && error.kind() != io::ErrorKind::NotFound
        {
            eprintln!("Game log temporary-file cleanup failed: {error}");
        }
        result?;
        self.next_record += 1;
        Ok(())
    }
}

impl SubmissionResult {
    pub fn new(
        turn_number: i32,
        submissions: Vec<Submission>,
        scenario: &Scenario,
        turns: &Turns,
    ) -> Self {
        Self {
            turn_number,
            submissions,
            scenario: scenario.clone(),
            next_turn_number: turns.number,
            submitted_players: submitted_players(turns),
            outcome: turns.outcome,
            resolution: if turns.number != turn_number {
                turns.last_resolution.clone()
            } else {
                None
            },
        }
    }
}

fn submitted_players(turns: &Turns) -> Vec<PlayerNumber> {
    [PlayerNumber::Player1, PlayerNumber::Player2]
        .into_iter()
        .filter(|player| turns.orders[turns::player_index(*player)].is_some())
        .collect()
}

/// Re-run captured orders using the current engine. Compare every authoritative
/// board, pending status, outcome and playback frame, without re-running the AI.
/// Source records remain readable even when a future engine produces differences.
pub fn replay(directory: &Path) -> io::Result<String> {
    let mut paths = fs::read_dir(directory)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<io::Result<Vec<_>>>()?;
    paths.retain(|path| {
        path.extension()
            .is_some_and(|extension| extension == "json")
    });
    paths.sort();
    let mut scenario = None;
    let mut turns = Turns::default();
    let mut count = 0;
    for (index, path) in paths.iter().enumerate() {
        let expected_name = format!("{index:08}.json");
        if path.file_name().and_then(|name| name.to_str()) != Some(&expected_name) {
            return Err(io::Error::other(format!(
                "missing or unexpected record at {expected_name}"
            )));
        }
        let record: Record = serde_json::from_reader(File::open(path)?)
            .map_err(|error| io::Error::other(format!("{}: {error}", path.display())))?;
        if record.format_version != FORMAT_VERSION {
            return Err(io::Error::other(format!(
                "unsupported game log version {}",
                record.format_version
            )));
        }
        match record.event {
            Event::Started(started) if index == 0 => scenario = Some(started.scenario),
            Event::Submitted(submitted) => {
                let scenario = scenario
                    .as_mut()
                    .ok_or_else(|| io::Error::other("game log must begin with Started"))?;
                if submitted.submissions.is_empty() {
                    return Err(io::Error::other("submission record has no orders"));
                }
                for submission in &submitted.submissions {
                    turns
                        .submit(
                            scenario,
                            submission.player_number,
                            submitted.turn_number,
                            submission.orders.clone(),
                        )
                        .map_err(|error| {
                            io::Error::other(format!("{}: {error}", path.display()))
                        })?;
                }
                let actual = SubmissionResult::new(
                    submitted.turn_number,
                    submitted.submissions.clone(),
                    scenario,
                    &turns,
                );
                if serde_json::to_value(&actual)? != serde_json::to_value(&submitted)? {
                    return Err(io::Error::other(format!(
                        "{}: replay differs from recorded turn {}",
                        path.display(),
                        submitted.turn_number
                    )));
                }
                count += 1;
            }
            Event::Started(_) => return Err(io::Error::other("unexpected Started record")),
        }
    }
    if scenario.is_none() {
        return Err(io::Error::other("game log has no Started record"));
    }
    Ok(format!(
        "Verified {count} submission records; next turn {}, outcome {:?}.",
        turns.number, turns.outcome
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        map_definition::MapDefinition,
        test_support::{FixtureValue, TestResult},
    };
    use serde_json::json;

    #[test]
    fn archives_hidden_combat_terminal_outcomes_and_detects_missing_or_malformed_records()
    -> TestResult<()> {
        let root = std::env::temp_dir().join(format!(
            "fightlines-combat-log-{}-{}",
            std::process::id(),
            now()?.as_nanos()
        ));
        let directory = Directory::open(root.clone())?;
        let mut scenario = MapDefinition::parse(r#"{
            "width": 5, "height": 3, "theme": "GreenForest",
            "features": [{"position": {"x": 2, "y": 1}, "terrain": "Forest"}],
            "depots": [],
            "units": [
                {"id": 1, "position": {"x": 0, "y": 1}, "playerNumber": "Player1", "kind": "FieldGun", "direction": "East"},
                {"id": 2, "position": {"x": 2, "y": 1}, "playerNumber": "Player2", "kind": "Infantry", "direction": "West"}
            ]
        }"#).fixture()?.scenario().fixture()?;
        // Exhausting the target's provisions ends the match after the shell hits.
        scenario
            .units
            .iter_mut()
            .find(|unit| unit.id() == "2")
            .fixture()?
            .set_supplies_for_test(4);
        let mut log = directory.start(GameStarted {
            game_id: LobbyId::from_token("01".repeat(16)),
            name: "Combat fixture".into(),
            map_type: MapType::SupplyPoint,
            players: vec![],
            scenario: scenario.clone(),
            server_version: "test".into(),
            build_revision: None,
        })?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&log.directory)?.permissions().mode() & 0o777,
                0o700
            );
            assert_eq!(
                fs::metadata(log.directory.join("00000000.json"))?
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
        let mut turns = Turns::default();
        for (player_number, order) in [
            (
                PlayerNumber::Player1,
                json!({"unit_id":"1", "path":[{"x":0,"y":1}], "indirect_fire":{"x":2,"y":1}}),
            ),
            (
                PlayerNumber::Player2,
                json!({"unit_id":"2", "path":[{"x":2,"y":1}]}),
            ),
        ] {
            let orders: Vec<MoveOrderInput> = vec![serde_json::from_value(order)?];
            turns
                .submit(&mut scenario, player_number, 1, orders.clone())
                .fixture()?;
            log.submitted(SubmissionResult::new(
                1,
                vec![Submission {
                    player_number,
                    orders,
                }],
                &scenario,
                &turns,
            ))?;
        }
        assert_eq!(
            turns.outcome,
            Some(GameOutcome::Victory(PlayerNumber::Player1))
        );
        let resolution = turns.last_resolution.as_ref().fixture()?;
        assert!(
            resolution
                .frames
                .iter()
                .any(|frame| !frame.shots.is_empty() && !frame.indirect_impacts.is_empty())
        );
        assert!(replay(&log.directory)?.contains("Victory(Player1)"));
        // Incomplete temporary files are not published records.
        fs::write(log.directory.join("00000003.pending"), b"{")?;
        replay(&log.directory)?;
        let final_path = log.directory.join("00000002.json");
        let final_bytes = fs::read(&final_path)?;
        fs::write(&final_path, b"{")?;
        assert!(replay(&log.directory).is_err());
        fs::write(&final_path, final_bytes)?;
        let first_submission = log.directory.join("00000001.json");
        let original = fs::read(&first_submission)?;
        fs::remove_file(&first_submission)?;
        assert!(
            replay(&log.directory)
                .err()
                .fixture()?
                .to_string()
                .contains("missing or unexpected")
        );
        fs::write(&first_submission, original)?;
        replay(&log.directory)?;
        // Existing records are never overwritten by a failed publication.
        let destination = log.directory.join("00000003.json");
        fs::write(&destination, b"existing record")?;
        assert!(
            log.submitted(SubmissionResult::new(1, vec![], &scenario, &turns))
                .is_err()
        );
        assert_eq!(fs::read(&destination)?, b"existing record");
        fs::remove_file(destination)?;
        replay(&log.directory)?;
        fs::remove_dir_all(root)?;
        Ok(())
    }
}
