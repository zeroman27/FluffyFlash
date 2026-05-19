#!/bin/bash
# Codesign + notarize a Release-built FluffyFlash.app locally.
#
# Usage:
#   ./codesign_and_notarize.sh path/to/FluffyFlash.app
#
# Reads:
#   FLUFFY_DEV_ID          (e.g. "Developer ID Application: Foo Bar (TEAMID)")
#   FLUFFY_NOTARY_PROFILE  (optional; Keychain profile from notarytool store-credentials)
#   FLUFFY_APPLE_ID        (if no profile)
#   FLUFFY_TEAM_ID
#   FLUFFY_NOTARY_PASSWORD (app-specific password)
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

if [[ -n "${FLUFFY_NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$FLUFFY_NOTARY_PROFILE")
else
  : "${FLUFFY_APPLE_ID:?Set FLUFFY_APPLE_ID or FLUFFY_NOTARY_PROFILE}"
  : "${FLUFFY_TEAM_ID:?Set FLUFFY_TEAM_ID or FLUFFY_NOTARY_PROFILE}"
  : "${FLUFFY_NOTARY_PASSWORD:?Set FLUFFY_NOTARY_PASSWORD or FLUFFY_NOTARY_PROFILE}"
  NOTARY_AUTH=(--apple-id "$FLUFFY_APPLE_ID" --team-id "$FLUFFY_TEAM_ID" --password "$FLUFFY_NOTARY_PASSWORD")
fi

NESTED_LIST=""
SORTED_BUNDLES=""
ZIP=""
cleanup() {
  rm -f ${ZIP:+"$ZIP"} ${NESTED_LIST:+"$NESTED_LIST"} ${SORTED_BUNDLES:+"$SORTED_BUNDLES"} 2>/dev/null || true
}
trap cleanup EXIT

echo "Signing every bundled Mach-O inside $APP_PATH …"
while IFS= read -r -d '' bin; do
  ftype="$(file -b "$bin" 2>/dev/null || true)"
  case "$ftype" in
    *Mach-O*)
      /usr/bin/codesign --force --options=runtime --timestamp \
        --sign "$FLUFFY_DEV_ID" "$bin" >/dev/null
      ;;
  esac
done < <(find "$APP_PATH/Contents" \( -type f -o -type l \) -print0)

echo "Re-sealing nested bundles (.framework, nested .app, .xpc) deepest-first …"
NESTED_LIST="$(mktemp -t fluffy_nested_bundles)"
SORTED_BUNDLES="$(mktemp -t fluffy_nested_sorted)"
find "$APP_PATH/Contents" -type d \( -name "*.app" -o -name "*.framework" -o -name "*.xpc" -o -name "*.appex" \) -print >"$NESTED_LIST"
while IFS= read -r bundle; do
  [[ -z "$bundle" || ! -d "$bundle" ]] && continue
  depth="$(printf '%s' "$bundle" | awk -F/ '{print NF}')"
  printf '%05d\t%s\n' "$depth" "$bundle"
done <"$NESTED_LIST" | sort -t $'\t' -k1,1nr | cut -f2- >"$SORTED_BUNDLES"
while IFS= read -r bundle; do
  [[ -z "$bundle" ]] && continue
  /usr/bin/codesign --force --deep --options=runtime --timestamp \
    --sign "$FLUFFY_DEV_ID" "$bundle" >/dev/null
done <"$SORTED_BUNDLES"

echo "Sealing the .app …"
/usr/bin/codesign --force --deep --options=runtime --timestamp \
  --sign "$FLUFFY_DEV_ID" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ZIP="$(mktemp -t FluffyFlashNotarize)".zip
echo "Creating $ZIP for notarization …"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"

echo "Submitting to notarytool …"
xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait

echo "Stapling …"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Final Gatekeeper check:"
spctl -a -vv -t install "$APP_PATH" || true

rm -f "$ZIP"
echo "Done."
