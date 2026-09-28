#!/bin/bash
# Build PondWall.app and install it into ~/Applications (or the dir given as $1).
# If PondWall is running it is restarted with the new build.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HOME/Applications}"
APP="$OUT_DIR/PondWall.app"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "→ Compiling PondWall..."
mkdir -p "$BUILD/PondWall.app/Contents/MacOS"
swiftc -O -whole-module-optimization \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$BUILD/PondWall.app/Contents/MacOS/PondWall" \
  "$SRC_DIR"/Sources/*.swift
cp "$SRC_DIR/Info.plist" "$BUILD/PondWall.app/Contents/Info.plist"
codesign --force --sign - "$BUILD/PondWall.app" 2>/dev/null

was_running=false
if pgrep -xq PondWall; then
  was_running=true
  pkill -x PondWall || true
  sleep 0.5
fi

mkdir -p "$OUT_DIR"
rm -rf "$APP"
mv "$BUILD/PondWall.app" "$APP"
echo "✓ Installed: $APP"

if $was_running; then
  open "$APP"
  echo "✓ Restarted PondWall"
fi
