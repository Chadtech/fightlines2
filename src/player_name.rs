use serde::Serialize;

#[derive(Clone, Serialize)]
#[serde(transparent)]
pub struct PlayerName(String);

impl PlayerName {
    pub fn parse(input: &str) -> Option<Self> {
        let name = input.trim();
        (!name.is_empty() && name.chars().count() <= 40).then(|| Self(name.to_owned()))
    }

    pub fn matches(&self, other: &Self) -> bool {
        self.0.to_lowercase() == other.0.to_lowercase()
    }
}

impl std::fmt::Display for PlayerName {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(formatter)
    }
}
