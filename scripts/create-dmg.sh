#!/bin/bash
# Package a built Design Ruler.app into the branded DMG.
# Usage: scripts/create-dmg.sh <path/to/Design Ruler.app> <output.dmg>
# Shared by build-release.yml (Developer ID build) and ci.yml (ad-hoc test build).
set -euo pipefail

APP="$1"
DMG="$2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Stage only the .app (an export dir also holds plists and Packaging.log)
mkdir -p "$WORK/staging"
ditto "$APP" "$WORK/staging/Design Ruler.app"

# 1200x864 art for a 600x432 window: tag it 144 DPI so Finder draws it at 600x432pt.
# The window size includes the title bar (32pt on macOS 27, varies by version), so the content
# area is ~600x400 with the icons centered in it; the bottom of the art is bleed.
cp "$REPO_ROOT/scripts/assets/dmg-background.png" "$WORK/background.png"
sips -s dpiWidth 144 -s dpiHeight 144 "$WORK/background.png" >/dev/null

VOLICON=$(find "$WORK/staging/Design Ruler.app/Contents/Resources" -name "*.icns" | head -1)
if [ -z "$VOLICON" ]; then
  echo "No .icns in app bundle (missing AppIcon?)" >&2
  exit 1
fi

rm -f "$DMG"
# create-dmg exits 2 for cosmetic warnings; check for the output file instead
create-dmg \
  --volname "Design Ruler" \
  --volicon "$VOLICON" \
  --background "$WORK/background.png" \
  --window-pos 200 120 \
  --window-size 600 432 \
  --icon-size 128 \
  --icon "Design Ruler.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "Design Ruler.app" \
  --no-internet-enable \
  "$DMG" \
  "$WORK/staging/" || true
test -f "$DMG"
echo "Created $DMG"
