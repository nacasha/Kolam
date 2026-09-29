#!/bin/bash
# Build Kolam.app and package it into dist/Kolam.dmg with a styled
# install window (background + drag-to-Applications layout).
# The first run asks for permission to let the terminal control Finder.
# Set SIGN_IDENTITY="Developer ID Application: …" to sign the app and DMG.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOL_NAME="Kolam"
DIST="$SRC_DIR/dist"
DMG="$DIST/Kolam.dmg"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
RW_DMG="$WORK/rw.dmg"
MOUNT=""
# Finder merges the volume window into a tab when "prefer tabs" is "always",
# which breaks the styling step — disable it while we run.
TAB_MODE="$(defaults read -g AppleWindowTabbingMode 2>/dev/null || echo fullscreen)"
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  defaults write -g AppleWindowTabbingMode "$TAB_MODE"
  rm -rf "$WORK"
}
trap cleanup EXIT

# Window layout (content size, icon centers).
WIN_W=660
WIN_H=400
TITLE_H=28   # Finder bounds include the title bar
ICON_SIZE=128
TEXT_SIZE=13
APP_X=170;  APP_Y=190
LINK_X=490; LINK_Y=190
HIDDEN_L_X=80; HIDDEN_R_X=580; HIDDEN_Y=75

mkdir -p "$STAGE/.background" "$DIST"
NO_RESTART=1 "$SRC_DIR/build.sh" "$STAGE"
ln -s /Applications "$STAGE/Applications"

# Combine 1x + 2x into one HiDPI TIFF so Finder picks the Retina version.
tiffutil -cathidpicheck \
  "$SRC_DIR/Resources/dmg/background.png" \
  "$SRC_DIR/Resources/dmg/background@2x.png" \
  -out "$STAGE/.background/background.tiff" 2>/dev/null

echo "→ Creating disk image..."
# Eject a leftover volume with the same name so the mount path is predictable.
[ -d "/Volumes/$VOL_NAME" ] && hdiutil detach "/Volumes/$VOL_NAME" -quiet -force || true
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL_NAME" \
  -fs HFS+ -format UDRW -size 50m "$RW_DMG"
MOUNT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen \
  | grep -o '/Volumes/.*$')"

echo "→ Styling window..."
defaults write -g AppleWindowTabbingMode manual
osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H + TITLE_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to $TEXT_SIZE
    set background picture of opts to file ".background:background.tiff"
    set position of item "Kolam.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
    -- Hidden items only show when Finder shows hidden files; keep them inside
    -- the window so they never cause scrollbars.
    try
      set position of item ".background" of container window to {$HIDDEN_L_X, $HIDDEN_Y}
    end try
    update without registering applications
  end tell
end tell
EOF

# Volume icon (shown on the desktop / sidebar while mounted). Finder's
# "update" deletes it, so add it afterwards, then position it inside the
# window (visible only with hidden files shown) to avoid scrollbars.
cp "$SRC_DIR/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true
osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    try
      set position of item ".VolumeIcon.icns" of container window to {$HIDDEN_R_X, $HIDDEN_Y}
    end try
    delay 1
    close
  end tell
end tell
EOF

chflags hidden "$MOUNT/.background" "$MOUNT/.VolumeIcon.icns"
rm -rf "$MOUNT/.fseventsd"
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

rm -f "$DMG"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "✓ Created: $DMG"
