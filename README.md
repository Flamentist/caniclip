# CaniClip

A small menu bar app for macOS to screenshot, annotate, and record a screen area to GIF.
Swift (AppKit + SwiftUI + ScreenCaptureKit) for the app, Rust for GIF encoding and
image processing, joined by UniFFI.

## Requirements

- macOS 15 or later on Apple Silicon
- Xcode 26 with command line tools
- Rust via rustup (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- XcodeGen (`brew install xcodegen`)

## Build and run

    ./scripts/bootstrap.sh   # builds the Rust core, writes Local.xcconfig, generates CaniClip.xcodeproj
    ./scripts/run.sh         # builds Debug and launches the app

Or open `CaniClip.xcodeproj` after bootstrapping and press Run. The Xcode build
re-runs `scripts/build-rust.sh` before compiling Swift.

On first launch macOS asks for Screen Recording permission. Grant it, then quit
and reopen the app.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture area | ⌘⇧7 |
| Record area to GIF | ⌘⇧8 |
| Capture full screen | ⌘⇧9 |

Change them in Settings from the menu bar icon.

## Window

Choose **Open CaniClip** from the menu bar icon (or ⌘0 when CaniClip is active) for the
capture hub: large capture tiles plus a history of every screenshot and GIF with reopen,
copy, reveal and remove. History lives in `~/Library/Application Support/CaniClip/Library`
and is pruned after 30 days by default (Settings → General → Keep history).

## Tests

    (cd core && cargo test)
    xcodebuild test -project CaniClip.xcodeproj -scheme CaniClip -destination 'platform=macOS,arch=arm64'

## Layout

- `core/` Rust crate `caniclip-core`: GifEncoder over gifski, pixelate, UniFFI exports
- `CaniClip/` Swift app sources; `CaniClip/Generated/` holds UniFFI output (gitignored)
- `project.yml` XcodeGen definition; `scripts/` build helpers
- `CaniClip/Library/` capture history store; `CaniClip/Hub/` the hub window and view model
- `docs/superpowers/` design spec, implementation plan and smoke test
