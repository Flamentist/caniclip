#!/bin/bash
# One-shot setup: build the Rust core, create Local.xcconfig, generate the Xcode project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./scripts/build-rust.sh

if [ ! -f Local.xcconfig ]; then
  # No certificate is normal (CI, contributors without an Apple developer
  # account): the lookup must not abort the script under `set -e`.
  CERT_NAME="${CANICLIP_SIGNING_CERT:-Apple Development}"
  TEAM="$( { security find-certificate -c "$CERT_NAME" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1; } || true )"
  if [ -n "$TEAM" ]; then
    printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\nCODE_SIGN_IDENTITY = Apple Development\n' "$TEAM" > Local.xcconfig
    echo "Local.xcconfig written with team $TEAM"
  else
    printf 'CODE_SIGN_STYLE = Manual\nCODE_SIGN_IDENTITY = -\n' > Local.xcconfig
    echo "No Apple Development certificate found; using ad-hoc signing (permission prompts will repeat after rebuilds)"
  fi
fi

xcodegen generate
echo "Project generated. Build with: xcodebuild -project CaniClip.xcodeproj -scheme CaniClip -configuration Debug build"
