#[derive(Clone)]
pub struct LobbyName(String);

impl LobbyName {
    pub fn parse(input: &str) -> Option<Self> {
        let name = input.trim();
        (!name.is_empty() && name.chars().count() <= 40).then(|| Self(name.to_owned()))
    }
}

impl std::fmt::Display for LobbyName {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(formatter)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};

    #[test]
    fn validates_and_trims_names_without_changing_case() -> TestResult<()> {
        assert_eq!(
            LobbyName::parse("  Friday Night  ").fixture()?.to_string(),
            "Friday Night"
        );
        assert!(LobbyName::parse("  ").is_none());
        assert!(LobbyName::parse(&"é".repeat(40)).is_some());
        assert!(LobbyName::parse(&"é".repeat(41)).is_none());

        Ok(())
    }
}
