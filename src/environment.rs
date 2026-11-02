//! Runtime hosting policy, independent of compiler and frontend build settings.
use std::{env, ffi::OsStr, io};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Environment {
    Development,
    Production,
}

impl Environment {
    pub fn load() -> io::Result<Self> {
        Self::parse(env::var_os("FIGHTLINES_ENV").as_deref())
    }

    fn parse(value: Option<&OsStr>) -> io::Result<Self> {
        match value {
            None => Ok(Self::Development),
            Some(value) if value == "development" => Ok(Self::Development),
            Some(value) if value == "production" => Ok(Self::Production),
            Some(_) => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "FIGHTLINES_ENV must be development or production",
            )),
        }
    }

    pub fn validate_arguments(self, arguments: impl IntoIterator<Item = String>) -> io::Result<()> {
        if self == Self::Production {
            for argument in arguments {
                match argument.as_str() {
                    "--dev-game" | "--map-editor" | "--game-logs" => {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidInput,
                            format!("{argument} is unavailable when FIGHTLINES_ENV=production"),
                        ));
                    }
                    _ => {}
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TestResult;

    #[test]
    fn environment_defaults_locally_and_rejects_invalid_configuration() -> TestResult<()> {
        assert_eq!(Environment::parse(None)?, Environment::Development);
        assert_eq!(
            Environment::parse(Some(OsStr::new("development")))?,
            Environment::Development
        );
        assert_eq!(
            Environment::parse(Some(OsStr::new("production")))?,
            Environment::Production
        );
        for value in ["", "prod", "Production", " production "] {
            assert!(Environment::parse(Some(OsStr::new(value))).is_err());
        }
        Ok(())
    }

    #[test]
    fn production_rejects_each_development_server_flag() -> TestResult<()> {
        for argument in ["--dev-game", "--map-editor", "--game-logs"] {
            Environment::Development.validate_arguments([argument.into()])?;
            assert!(
                Environment::Production
                    .validate_arguments([argument.into()])
                    .is_err()
            );
        }
        Environment::Production.validate_arguments(Vec::new())?;
        Ok(())
    }
}
