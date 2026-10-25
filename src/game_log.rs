//! Private authoritative archives, independent of HTTP and viewer projections.
use crate::{
    lobby::Controller,
    lobby_id::LobbyId,
    map_type::MapType,
    scenario::{PlayerNumber, Scenario},
    seed::Seed,
    turns::{self, GameOutcome, MoveOrderInput, TurnResolution, Turns},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, BufReader, Write},
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
    /// This player's control kind, never another player or a browser credential.
    #[serde(alias = "opponent")]
    pub controller: Controller,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resigned_player: Option<PlayerNumber>,
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

/// Kept separate from game records so archive queries cannot expose the seed.
#[derive(Serialize)]
struct ServerStarted {
    format_version: u32,
    started_at_unix_ms: u128,
    initial_seed: String,
    server_version: &'static str,
    build_revision: Option<&'static str>,
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

    pub fn record_server_start(&self, seed: Seed) -> io::Result<PathBuf> {
        let started_at = now()?;
        // Root-level files are not game directories and are never browsed.
        let path = self.0.join(format!(
            "server-start-{}-{}.json",
            started_at.as_nanos(),
            std::process::id()
        ));
        let record = ServerStarted {
            format_version: FORMAT_VERSION,
            started_at_unix_ms: started_at.as_millis(),
            initial_seed: seed.to_hex(),
            server_version: env!("CARGO_PKG_VERSION"),
            build_revision: option_env!("FIGHTLINES_BUILD_REVISION"),
        };
        let mut bytes = serde_json::to_vec_pretty(&record)?;
        bytes.push(b'\n');
        let mut file = private_file(&path)?;
        let mut write = || -> io::Result<()> {
            file.write_all(&bytes)?;
            file.sync_all()?;
            sync_directory(&self.0)
        };
        let result = write();
        drop(file);
        if let Err(error) = result {
            if let Err(cleanup) = fs::remove_file(&path) {
                eprintln!("Server-start record cleanup failed: {cleanup}");
            }
            return Err(error);
        }
        Ok(path)
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
            resigned_player: None,
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

/// A published archive is a contiguous prefix; pending files are never read.
fn records(directory: &Path) -> io::Result<Vec<Record>> {
    let mut paths = fs::read_dir(directory)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<io::Result<Vec<_>>>()?;
    paths.retain(|path| {
        path.extension()
            .is_some_and(|extension| extension == "json")
    });
    paths.sort();
    let mut records = Vec::new();
    for (index, path) in paths.iter().enumerate() {
        let expected = format!("{index:08}.json");
        if path.file_name().and_then(|name| name.to_str()) != Some(&expected) {
            return Err(io::Error::other(format!(
                "missing or unexpected record at {expected}"
            )));
        }
        let record: Record = serde_json::from_reader(BufReader::new(File::open(path)?))
            .map_err(|error| io::Error::other(format!("{expected}: {error}")))?;
        if record.format_version != FORMAT_VERSION {
            return Err(io::Error::other(format!(
                "unsupported game log version {}",
                record.format_version
            )));
        }
        records.push(record);
    }
    Ok(records)
}

pub struct Archive {
    pub started: GameStarted,
    pub recorded_at_unix_ms: u128,
    pub submissions: Vec<SubmissionResult>,
}

impl Archive {
    pub fn read(directory: &Path) -> io::Result<Self> {
        let mut records = records(directory)?.into_iter();
        let first = records
            .next()
            .ok_or_else(|| io::Error::other("game log has no Started record"))?;
        let Event::Started(started) = first.event else {
            return Err(io::Error::other("game log must begin with Started"));
        };
        let mut submissions = Vec::new();
        let mut next_turn = 1;
        for record in records {
            let Event::Submitted(submitted) = record.event else {
                return Err(io::Error::other("unexpected Started record"));
            };
            if (submitted.submissions.is_empty() && submitted.resigned_player.is_none())
                || submitted.turn_number != next_turn
            {
                return Err(io::Error::other("invalid submission sequence"));
            }
            match &submitted.resolution {
                Some(resolution)
                    if resolution.turn_number == next_turn
                        && submitted.next_turn_number == next_turn + 1 =>
                {
                    next_turn += 1
                }
                None if submitted.next_turn_number == next_turn => {}
                _ => return Err(io::Error::other("invalid recorded turn resolution")),
            }
            submissions.push(submitted);
        }
        Ok(Self {
            started,
            recorded_at_unix_ms: first.recorded_at_unix_ms,
            submissions,
        })
    }

    pub fn turn_count(&self) -> i32 {
        self.submissions
            .iter()
            .filter(|submission| submission.resolution.is_some())
            .count() as i32
    }
}

/// Re-run captured orders using the current engine. Compare every authoritative
/// board, pending status, outcome and playback frame, without re-running the AI.
/// Source records remain readable even when a future engine produces differences.
pub fn replay(directory: &Path) -> io::Result<String> {
    let mut scenario = None;
    let mut turns = Turns::default();
    let mut count = 0;
    for (index, record) in records(directory)?.into_iter().enumerate() {
        let path = directory.join(format!("{index:08}.json"));
        match record.event {
            Event::Started(started) if index == 0 => scenario = Some(started.scenario),
            Event::Submitted(submitted) => {
                let scenario = scenario
                    .as_mut()
                    .ok_or_else(|| io::Error::other("game log must begin with Started"))?;
                if submitted.submissions.is_empty() && submitted.resigned_player.is_none() {
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
                if let Some(player) = submitted.resigned_player {
                    turns.resign(player);
                }
                let mut actual = SubmissionResult::new(
                    submitted.turn_number,
                    submitted.submissions.clone(),
                    scenario,
                    &turns,
                );
                actual.resigned_player = submitted.resigned_player;
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
    fn recorded_players_accept_legacy_opponent_fields_and_write_controller() -> TestResult<()> {
        for controller in [
            Controller::Human,
            Controller::Ai,
            Controller::AiMedium,
            Controller::AiHard,
        ] {
            let current = json!({
                "player_number": "Player1",
                "name": "Recorded player",
                "controller": controller,
            });
            let legacy = json!({
                "player_number": "Player1",
                "name": "Recorded player",
                "opponent": controller,
            });
            for value in [current.clone(), legacy] {
                let player: RecordedPlayer = serde_json::from_value(value)?;
                assert_eq!(player.controller, controller);
                assert_eq!(serde_json::to_value(player)?, current);
            }
        }
        Ok(())
    }

    #[test]
    fn server_start_records_keep_the_seed_private_and_preserve_previous_runs() -> TestResult<()> {
        let root = std::env::temp_dir().join(format!(
            "fightlines-server-start-{}-{}",
            std::process::id(),
            now()?.as_nanos()
        ));
        let directory = Directory::open(root.clone())?;
        let seed = Seed::new([19; 32]);
        let first = directory.record_server_start(seed)?;
        let original = fs::read(&first)?;
        let record: serde_json::Value = serde_json::from_slice(&original)?;
        assert_eq!(record["format_version"], FORMAT_VERSION);
        assert_eq!(record["initial_seed"], "13".repeat(32));
        assert!(record["started_at_unix_ms"].as_u64().fixture()? > 0);
        assert_eq!(record["server_version"], env!("CARGO_PKG_VERSION"));
        assert_eq!(
            record["build_revision"],
            serde_json::to_value(option_env!("FIGHTLINES_BUILD_REVISION"))?
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(fs::metadata(&first)?.permissions().mode() & 0o777, 0o600);
        }
        let second = directory.record_server_start(Seed::new([20; 32]))?;
        assert_ne!(first, second);
        assert_eq!(fs::read(first)?, original);
        assert!(second.is_file());
        fs::remove_dir_all(root)?;
        Ok(())
    }

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
