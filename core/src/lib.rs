uniffi::setup_scaffolding!("caniclip_core");

mod error;

pub use error::CoreError;

/// Semantic version of the core crate, for the About menu and bridge smoke test.
#[uniffi::export]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn core_version_matches_cargo_manifest() {
        assert_eq!(core_version(), env!("CARGO_PKG_VERSION"));
    }
}
