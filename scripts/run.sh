#!/bin/bash
# Builds Debug and launches the app bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d CaniClip.xcodeproj ] || ./scripts/bootstrap.sh
xcodebuild -project CaniClip.xcodeproj -scheme CaniClip -configuration Debug -destination 'platform=macOS,arch=arm64' build -quiet
APP="$(xcodebuild -project CaniClip.xcodeproj -scheme CaniClip -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/CaniClip.app"
pkill -x CaniClip 2>/dev/null || true
# Make macOS pick up icon changes: bump the bundle's date and re-register it.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
open "$APP"
echo "Launched $APP"
