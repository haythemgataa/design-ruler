#!/bin/bash
# Fail if an embedded framework would be rejected by library validation at launch.
# Usage: scripts/check-library-validation.sh <path/to/Design Ruler.app>
#
# With hardened runtime on, dyld only loads non-Apple frameworks signed with the app's own
# Team ID; otherwise the app dies at launch with "mapping process and mapped file (non-platform)
# have different Team IDs". Ad-hoc code has no Team ID, and "not set" never matches, even when
# the framework is ad-hoc too, so an ad-hoc app with hardened runtime can't load any framework.
# GitHub's macOS runners run with SIP disabled and don't enforce this, so a launch smoke test
# there can't catch it; this checks the signatures statically instead.
set -euo pipefail

APP="$1"
sig_field() { codesign -dv "$1" 2>&1 | sed -n "s/^$2=//p" | head -1; }

APP_TEAM=$(sig_field "$APP" TeamIdentifier)
APP_FLAGS=$(codesign -dv "$APP" 2>&1 | sed -n 's/^CodeDirectory.*flags=\([^ ]*\).*/\1/p' | head -1)
echo "$(basename "$APP"): TeamIdentifier=$APP_TEAM flags=$APP_FLAGS"

FAIL=0
for FW in "$APP"/Contents/Frameworks/*.framework; do
  [ -e "$FW" ] || continue
  FW_TEAM=$(sig_field "$FW" TeamIdentifier)
  echo "$(basename "$FW"): TeamIdentifier=$FW_TEAM"
  if [[ "$APP_FLAGS" == *runtime* && ( "$APP_TEAM" == "not set" || "$FW_TEAM" != "$APP_TEAM" ) ]]; then
    echo "::error::$(basename "$FW") has Team ID '$FW_TEAM' but the app has '$APP_TEAM' with hardened runtime on: dyld will refuse to load it at launch"
    FAIL=1
  fi
done
exit "$FAIL"
