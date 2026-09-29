#!/bin/bash
# Watch the sources and rebuild + relaunch Kolam on every change (Ctrl-C to stop).
# Builds only for this Mac's chip; see build.sh for the universal build.
# Uses polling, so it needs no extra tools.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/Kolam.app"
WATCH=("$SRC_DIR/Sources" "$SRC_DIR/Info.plist" "$SRC_DIR/Resources/AppIcon.icns")

# One line per watched file with its modification time; any edit, new file or
# deletion changes the output.
snapshot() { find "${WATCH[@]}" -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort; }

build() {
  echo
  echo "── $(date +%H:%M:%S) rebuilding…"
  # NO_RESTART: we relaunch below, so a crashed or quit Kolam comes back too.
  if ARCHS="$(uname -m)" NO_RESTART=1 "$SRC_DIR/build.sh" 2>&1 \
      | grep -E --line-buffered 'error:|✓'; then
    pkill -x Kolam && sleep 0.5
    open "$APP"
    echo "── $(date +%H:%M:%S) running the new build"
  fi
}

trap 'echo; exit 0' INT
build
last="$(snapshot)"
echo "Watching Sources/, Info.plist and the icon. Ctrl-C to stop."
while sleep 1; do
  now="$(snapshot)"
  [ "$now" = "$last" ] && continue
  # Let a burst of saves (e.g. a multi-file edit) settle before building.
  sleep 0.5
  last="$(snapshot)"
  build
done
