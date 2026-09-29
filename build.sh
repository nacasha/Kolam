#!/bin/bash
# Build PondWall.app and install it into ~/Applications (or the dir given as $1).
# If PondWall is running it is restarted with the new build (unless NO_RESTART=1).
# Builds a universal (Apple Silicon + Intel) binary; see ARCHS below.
# Set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HOME/Applications}"
APP="$OUT_DIR/PondWall.app"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "→ Compiling PondWall..."
mkdir -p "$BUILD/PondWall.app/Contents/MacOS"
# Universal binary: one slice per arch, merged with lipo.
# ARCHS="$(uname -m)" builds only the local arch (faster dev builds).
slices=()
for arch in ${ARCHS:-arm64 x86_64}; do
  swiftc -O -whole-module-optimization \
    -target "$arch-apple-macos13.0" \
    -o "$BUILD/PondWall-$arch" \
    "$SRC_DIR"/Sources/*.swift
  slices+=("$BUILD/PondWall-$arch")
done
lipo -create "${slices[@]}" -output "$BUILD/PondWall.app/Contents/MacOS/PondWall"
rm "${slices[@]}"
cp "$SRC_DIR/Info.plist" "$BUILD/PondWall.app/Contents/Info.plist"
mkdir -p "$BUILD/PondWall.app/Contents/Resources"
cp "$SRC_DIR/Resources/AppIcon.icns" "$BUILD/PondWall.app/Contents/Resources/AppIcon.icns"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Developer ID + hardened runtime + secure timestamp: required for notarization.
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$BUILD/PondWall.app"
else
  codesign --force --sign - "$BUILD/PondWall.app" 2>/dev/null
fi

was_running=false
if [ -z "${NO_RESTART:-}" ] && pgrep -xq PondWall; then
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
