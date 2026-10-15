# Contributing

Thanks for helping! Keep it small and focused.

## 1. Set up

```bash
brew install xcodegen
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
./scripts/bootstrap.sh
```

## 2. Make your change

- Swift app: `CaniClip/` · Rust core: `core/` · tests: `CaniClipTests/`, `core/tests/`
- Write a failing test first, then the fix.
- Added a file? Run `xcodegen generate`.

## 3. Check it

```bash
(cd core && cargo test)
xcodebuild test -project CaniClip.xcodeproj -scheme CaniClip -destination 'platform=macOS,arch=arm64'
./scripts/run.sh
```

Changed how the app looks? Regenerate the README images (see **About these images** in the README).

## 4. Open a pull request

- One topic per PR.
- Say what changed and how you tested it.
- Screenshots for UI changes.

## Rules

- **No copyleft dependencies** (GPL, AGPL, LGPL). They clash with the licence. `core/tests/licences.rs` checks the GIF libraries.
- By contributing, you agree your work is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
- Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).

## Design docs

How things were planned lives in `docs/superpowers/`. The logo kit and its build script live in `design/logo/`.
