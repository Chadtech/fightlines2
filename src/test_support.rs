//! Fallible fixture extraction for tests; errors include the source location.
use std::{error::Error, fmt::Debug, panic::Location};

pub type TestResult<T = ()> = Result<T, Box<dyn Error>>;

pub trait FixtureValue<T> {
    fn fixture(self) -> TestResult<T>;
}

impl<T> FixtureValue<T> for Option<T> {
    #[track_caller]
    fn fixture(self) -> TestResult<T> {
        let location = Location::caller();
        self.ok_or_else(|| format!("missing fixture value at {location}").into())
    }
}

impl<T, E: Debug> FixtureValue<T> for Result<T, E> {
    #[track_caller]
    fn fixture(self) -> TestResult<T> {
        let location = Location::caller();
        self.map_err(|error| format!("fixture failed at {location}: {error:?}").into())
    }
}
