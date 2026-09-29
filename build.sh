#!/bin/bash
# Build Kolam.app and install it into ~/Applications (or the dir given as $1).
# If Kolam is running it is restarted with the new build (unless NO_RESTART=1).
# Builds a universal (Apple Silicon + Intel) binary; see ARCHS below.
# Set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HOME/Applications}"
APP="$OUT_DIR/Kolam.app"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "→ Compiling Kolam..."
mkdir -p "$BUILD/Kolam.app/Contents/MacOS"
# Universal binary: one slice per arch, merged with lipo.
# ARCHS="$(uname -m)" builds only the local arch (faster dev builds).
slices=()
for arch in ${ARCHS:-arm64 x86_64}; do
  swiftc -O -whole-module-optimization \
    -target "$arch-apple-macos13.0" \
    -o "$BUILD/Kolam-$arch" \
    "$SRC_DIR"/Sources/*.swift
  slices+=("$BUILD/Kolam-$arch")
done
lipo -create "${slices[@]}" -output "$BUILD/Kolam.app/Contents/MacOS/Kolam"
rm "${slices[@]}"
cp "$SRC_DIR/Info.plist" "$BUILD/Kolam.app/Contents/Info.plist"
mkdir -p "$BUILD/Kolam.app/Contents/Resources"
cp "$SRC_DIR/Resources/AppIcon.icns" "$BUILD/Kolam.app/Contents/Resources/AppIcon.icns"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Developer ID + hardened runtime + secure timestamp: required for notarization.
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$BUILD/Kolam.app"
else
  codesign --force --sign - "$BUILD/Kolam.app" 2>/dev/null
fi

was_running=false
if [ -z "${NO_RESTART:-}" ] && pgrep -xq Kolam; then
  was_running=true
  pkill -x Kolam || true
  sleep 0.5
fi

mkdir -p "$OUT_DIR"
rm -rf "$APP"
mv "$BUILD/Kolam.app" "$APP"
echo "✓ Installed: $APP"

if $was_running; then
  open "$APP"
  echo "✓ Restarted Kolam"
fi
