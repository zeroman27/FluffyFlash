#!/usr/bin/env bash
# Notarize FluffyFlash.app from an Xcode export folder, staple the app,
# rebuild DMG from the stapled app, notarize the DMG, staple the DMG.
#
# Usage:
#   export FLUFFY_APPLE_ID="you@example.com"
#   export FLUFFY_TEAM_ID="XXXXXXXXXX"
#   export FLUFFY_NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # app-specific password
#   ./Scripts/notarize_export_folder.sh "/Users/Shared/FluffyFlash 2026-05-14 11-53-35"
#
# Optional:
#   OUT_DMG_DIR — directory for FluffyFlash.dmg (default: same export folder)
#
set -euo pipefail

EXPORT_DIR="${1:?usage: $0 /path/to/Export-folder-containing-FluffyFlash.app}"

: "${FLUFFY_APPLE_ID:?Set FLUFFY_APPLE_ID}"
: "${FLUFFY_TEAM_ID:?Set FLUFFY_TEAM_ID}"
: "${FLUFFY_NOTARY_PASSWORD:?Set FLUFFY_NOTARY_PASSWORD (app-specific password)}"

APP="$EXPORT_DIR/FluffyFlash.app"
OUT_DMG_DIR="${OUT_DMG_DIR:-$EXPORT_DIR}"
DMG_OUT="$OUT_DMG_DIR/FluffyFlash.dmg"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_SUBMIT="$(mktemp -t fluffy_notary_app).zip"

if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP" >&2
  exit 64
fi

cleanup() { rm -f "$ZIP_SUBMIT"; }
trap cleanup EXIT

echo "== 1/4 Submit ZIP of .app for notarization =="
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_SUBMIT"
xcrun notarytool submit "$ZIP_SUBMIT" \
  --apple-id "$FLUFFY_APPLE_ID" \
  --team-id "$FLUFFY_TEAM_ID" \
  --password "$FLUFFY_NOTARY_PASSWORD" \
  --wait

echo "== 2/4 Staple FluffyFlash.app =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 3/4 Rebuild DMG from stapled app =="
mkdir -p "$OUT_DMG_DIR"
rm -f "$DMG_OUT"
cd "$REPO_ROOT"
FLUFFYFLASH_APP="$APP" ./Scripts/build_dmg.sh
mv -f "$REPO_ROOT/ReleaseArtifacts/FluffyFlash.dmg" "$DMG_OUT"

echo "== 4/4 Submit DMG and staple =="
xcrun notarytool submit "$DMG_OUT" \
  --apple-id "$FLUFFY_APPLE_ID" \
  --team-id "$FLUFFY_TEAM_ID" \
  --password "$FLUFFY_NOTARY_PASSWORD" \
  --wait
xcrun stapler staple "$DMG_OUT"
xcrun stapler validate "$DMG_OUT"

echo "Done."
echo "  Stapled app: $APP"
echo "  Stapled dmg: $DMG_OUT"
ls -lh "$APP" "$DMG_OUT"
