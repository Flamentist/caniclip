//! CaniClip is licensed for non-commercial use only. Copyleft libraries such as
//! gifski (AGPL-3.0) and imagequant (GPL-3.0) forbid that restriction, so they
//! must never be linked into the app.

const FORBIDDEN: &[&str] = &["gifski", "imagequant"];

#[test]
fn no_copyleft_gif_libraries_in_the_lockfile() {
    let lock = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/Cargo.lock"))
        .expect("Cargo.lock should exist next to Cargo.toml");
    let names: Vec<&str> = lock
        .lines()
        .filter_map(|l| l.strip_prefix("name = \""))
        .map(|l| l.trim_end_matches('"'))
        .collect();
    for forbidden in FORBIDDEN {
        assert!(!names.contains(forbidden), "{forbidden} is in Cargo.lock; its licence is incompatible with CaniClip's");
    }
}
