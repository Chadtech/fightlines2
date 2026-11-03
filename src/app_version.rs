//! Application build identity, shared with the generated Elm version.

pub fn current() -> &'static str {
    include_str!("../VERSION").trim()
}
