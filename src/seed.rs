use rand::{
    Rng, SeedableRng, TryRng,
    rngs::{StdRng, SysRng},
};
use std::io;

/// Explicit state for deterministic token generation. Never sent to clients.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Seed([u8; 32]);

impl Seed {
    pub const fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Resolve the optional debugging override without changing process environment.
    pub fn startup(override_hex: Option<&str>) -> io::Result<Self> {
        match override_hex {
            Some(value) => Self::from_hex(value).ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "FIGHTLINES_SEED must contain 64 hexadecimal characters",
                )
            }),
            None => {
                let mut bytes = [0; 32];
                SysRng
                    .try_fill_bytes(&mut bytes)
                    .map_err(io::Error::other)?;
                Ok(Self(bytes))
            }
        }
    }

    /// Secret material: only write this to the private server-start record.
    pub fn to_hex(self) -> String {
        self.0.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    pub fn from_hex(value: &str) -> Option<Self> {
        if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return None;
        }
        let mut bytes = [0; 32];
        for (index, byte) in bytes.iter_mut().enumerate() {
            *byte = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16).ok()?;
        }
        Some(Self(bytes))
    }
}

/// The same seed always returns the same token and successor seed with the
/// locked rand version. Callers must retain the successor for the next call.
pub fn token(seed: Seed) -> (String, Seed) {
    let mut generator = StdRng::from_seed(seed.0);
    let mut bytes = [0; 16];
    let mut next = [0; 32];
    generator.fill_bytes(&mut bytes);
    generator.fill_bytes(&mut next);
    let token = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    (token, Seed(next))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};

    #[test]
    fn startup_generates_fresh_seeds_or_uses_the_exact_debug_override() -> TestResult<()> {
        let first = Seed::startup(None)?;
        let second = Seed::startup(None)?;
        assert!(first != second);
        assert!(Seed::from_hex(&first.to_hex()) == Some(first));
        let override_hex = "aB".repeat(32);
        let overridden = Seed::startup(Some(&override_hex))?;
        assert!(overridden == Seed::new([0xab; 32]));
        assert!(Seed::startup(Some(&overridden.to_hex()))? == overridden);
        for invalid in ["", "invalid", &"a".repeat(63), &"g".repeat(64)] {
            let error = Seed::startup(Some(invalid)).err().fixture()?;
            assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
            assert_eq!(
                error.to_string(),
                "FIGHTLINES_SEED must contain 64 hexadecimal characters"
            );
        }
        Ok(())
    }

    #[test]
    fn generation_is_replayable_and_advances() {
        let initial = Seed::new([7; 32]);
        let (first, next) = token(initial);
        let (replayed, replayed_next) = token(initial);
        assert_eq!(first, replayed);
        assert!(next == replayed_next && next != initial);
        let (second, _) = token(next);
        assert_ne!(first, second);
        assert_eq!(first.len(), 32);
        assert!(Seed::from_hex(&"07".repeat(32)) == Some(initial));
        assert!(Seed::from_hex("invalid").is_none());
    }
}
