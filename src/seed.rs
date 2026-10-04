use rand::{Rng, SeedableRng, rngs::StdRng};

/// Explicit state for deterministic token generation. Never sent to clients.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Seed([u8; 32]);

impl Seed {
    pub const fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
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
