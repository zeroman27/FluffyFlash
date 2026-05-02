#!/bin/bash
# Codesign + notarize a Release-built FluffyFlash.app locally.
#
# Usage:
#   ./codesign_and_notarize.sh path/to/FluffyFlash.app
#
# Reads:
#   FLUFFY_DEV_ID         (e.g. "Developer ID Application: Foo Bar (TEAMID)")
#   FLUFFY_APPLE_ID       (Apple ID email used for notarization)
#   FLUFFY_TEAM_ID        (10-char Team ID)
#   FLUFFY_NOTARY_PASSWORD (App-specific password)
#
# Use this for:
#   - debugging codesign issues without pushing CI runs;
#   - re-stapling after a failed notarization;
#   - ad-hoc signing of bundled tools when iterating on entitlements.
#
# Notes:
#   - Mirrors the same logic the GitHub Actions release workflow uses, so a
#     local run is a faithful preview of CI behaviour.

set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "usage: $(basename "$0") path/to/FluffyFlash.app" >&2
  exit 64
fi

: "${FLUFFY_DEV_ID:?Set FLUFFY_DEV_ID to your Developer ID Application identity}"
: "${FLUFFY_APPLE_ID:?Set FLUFFY_APPLE_ID}"
: "${FLUFFY_TEAM_ID:?Set FLUFFY_TEAM_ID}"
: "${FLUFFY_NOTARY_PASSWORD:?Set FLUFFY_NOTARY_PASSWORD (app-specific password)}"

echo "Signing every bundled Mach-O inside $APP_PATH …"
while IFS= read -r -d '' bin; do
  ftype="$(file -b "$bin" || true)"
  case "$ftype" in
    *Mach-O*)
      /usr/bin/codesign --force --options=runtime --timestamp \
        --sign "$FLUFFY_DEV_ID" "$bin" >/dev/null
      ;;
  esac
done < <(find "$APP_PATH/Contents" -type f -print0)

echo "Sealing the .app …"
/usr/bin/codesign --force --deep --options=runtime --timestamp \
  --sign "$FLUFFY_DEV_ID" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ZIP="$(mktemp -t FluffyFlashNotarize)".zip
echo "Creating $ZIP for notarization …"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

echo "Submitting to notarytool …"
xcrun notarytool submit "$ZIP" \
  --apple-id "$FLUFFY_APPLE_ID" \
  --team-id "$FLUFFY_TEAM_ID" \
  --password "$FLUFFY_NOTARY_PASSWORD" \
  --wait

echo "Stapling …"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Final Gatekeeper check:"
spctl -a -vv -t install "$APP_PATH" || true

rm -f "$ZIP"
echo "Done."
