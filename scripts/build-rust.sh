#!/bin/bash
# Builds the Rust core as a static library and regenerates the UniFFI Swift
# bindings. Called by scripts/bootstrap.sh and by the Xcode pre-build phase.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
OUT="$ROOT/CaniClip/Generated"
export PATH="$HOME/.cargo/bin:$PATH"

# Xcode exports SDKROOT/MACOSX_DEPLOYMENT_TARGET for its own toolchain; they
# confuse cargo's build scripts for host tools, so clear them.
unset SDKROOT MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET

PROFILE="${CANICLIP_RUST_PROFILE:-release}"
if [ "$PROFILE" = "release" ]; then
  (cd "$CORE" && cargo build --release --lib)
else
  (cd "$CORE" && cargo build --lib)
fi

mkdir -p "$OUT"
(cd "$CORE" && cargo run --quiet --bin uniffi-bindgen -- generate \
  --library "target/$PROFILE/libcaniclip_core.dylib" \
  --language swift \
  --out-dir "$OUT")

# Swift only discovers a Clang module through a file literally named module.modulemap.
mv -f "$OUT/CaniClipCoreFFI.modulemap" "$OUT/module.modulemap"
echo "Rust core built ($PROFILE) and Swift bindings written to $OUT"
