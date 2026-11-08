#![deny(clippy::unwrap_used, clippy::expect_used)]

//! Single-host release controller, separate from the game server.
mod cli;
mod control;
#[path = "../deployment_id.rs"]
mod deployment_id;
mod runtime;

type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

fn main() -> Result {
    cli::run(std::env::args_os().skip(1))
}
