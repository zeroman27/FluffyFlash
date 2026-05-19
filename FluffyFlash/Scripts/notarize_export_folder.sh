#!/usr/bin/env bash
# Notarize FluffyFlash.app from an Xcode export folder, staple the app,
# rebuild DMG from the stapled app, notarize the DMG, staple the DMG.
#
# Xcode "Developer ID" export often signs the main binary but leaves bundled
# CLI tools and Sparkle helpers without a valid Developer ID signature, hardened
# runtime, and secure timestamp. This script re-signs every Mach-O, re-seals
# nested .framework/.app/.xpc bundles inside-out, then deep-seals the .app
# (same idea as codesign_and_notarize.sh) before submitting.
#
# Usage (signing + notary):
#   export FLUFFY_DEV_ID="Developer ID Application: Your Name (TEAMID)"
#   # Either Keychain profile (recommended after store-credentials):
#   export FLUFFY_NOTARY_PROFILE="fluffy-notary"
#   # Or Apple ID + app-specific password:
#   export FLUFFY_APPLE_ID="you@example.com"
#   export FLUFFY_TEAM_ID="XXXXXXXXXX"
#   export FLUFFY_NOTARY_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   ./Scripts/notarize_export_folder.sh "/Users/Shared/FluffyFlash 2026-05-14 12-12-06"
#
# Optional:
#   OUT_DMG_DIR — directory for FluffyFlash.dmg (default: same export folder)
#
set -euo pipefail

EXPORT_DIR="${1:?usage: $0 /path/to/Export-folder-containing-FluffyFlash.app}"

: "${FLUFFY_DEV_ID:?Set FLUFFY_DEV_ID (Developer ID Application identity)}"

if [[ -n "${FLUFFY_NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$FLUFFY_NOTARY_PROFILE")
else
  : "${FLUFFY_APPLE_ID:?Set FLUFFY_APPLE_ID or FLUFFY_NOTARY_PROFILE}"
  : "${FLUFFY_TEAM_ID:?Set FLUFFY_TEAM_ID or FLUFFY_NOTARY_PROFILE}"
  : "${FLUFFY_NOTARY_PASSWORD:?Set FLUFFY_NOTARY_PASSWORD or FLUFFY_NOTARY_PROFILE}"
  NOTARY_AUTH=(--apple-id "$FLUFFY_APPLE_ID" --team-id "$FLUFFY_TEAM_ID" --password "$FLUFFY_NOTARY_PASSWORD")
fi

APP="$EXPORT_DIR/FluffyFlash.app"
OUT_DMG_DIR="${OUT_DMG_DIR:-$EXPORT_DIR}"
DMG_OUT="$OUT_DMG_DIR/FluffyFlash.dmg"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_SUBMIT="$(mktemp -t fluffy_notary_app).zip"
SUBMIT_LOG="$(mktemp -t fluffy_notary_submit)"
NESTED_LIST=""
SORTED_BUNDLES=""

if [[ ! -d "$APP" ]]; then
  echo "error: missing $APP" >&2
  exit 64
fi

cleanup() {
  rm -f "$ZIP_SUBMIT" "$SUBMIT_LOG" "${SUBMIT_LOG}.dmg" 2>/dev/null || true
  rm -f ${NESTED_LIST:+"$NESTED_LIST"} ${SORTED_BUNDLES:+"$SORTED_BUNDLES"} 2>/dev/null || true
}
trap cleanup EXIT

notary_fail_log() {
  local sid="$1"
  echo "" >&2
  echo "Notarization was rejected. Apple log for submission $sid:" >&2
  xcrun notarytool log "$sid" "${NOTARY_AUTH[@]}" >&2 || true
}

assert_notary_accepted() {
  local logfile="$1"
  if grep -q "status: Invalid" "$logfile"; then
    local sid
    sid="$(awk '/^[[:space:]]*id:/{print $2; exit}' "$logfile")"
    [[ -n "$sid" ]] && notary_fail_log "$sid"
    exit 1
  fi
  if grep -q "status: Rejected" "$logfile"; then
    local sid
    sid="$(awk '/^[[:space:]]*id:/{print $2; exit}' "$logfile")"
    [[ -n "$sid" ]] && notary_fail_log "$sid"
    exit 1
  fi
  if ! grep -q "status: Accepted" "$logfile"; then
    echo "error: could not confirm Accepted status in notarytool output. Full log:" >&2
    cat "$logfile" >&2
    exit 1
  fi
}

# Bundled CLI tools are often ad-hoc signed in-repo; Sparkle helpers ship from
# SPM with a signature that is not your Developer ID. Notarization requires
# every Mach-O to be signed with the same Developer ID Application identity,
# hardened runtime, and a secure timestamp — then nested bundles re-sealed.
echo "== 0/5 Re-sign all Mach-O inside bundle (hardened runtime) =="
while IFS= read -r -d '' bin; do
  ftype="$(file -b "$bin" 2>/dev/null || true)"
  case "$ftype" in
    *Mach-O*)
      /usr/bin/codesign --force --options=runtime --timestamp \
        --sign "$FLUFFY_DEV_ID" "$bin" >/dev/null
      ;;
  esac
done < <(find "$APP/Contents" \( -type f -o -type l \) -print0)

echo "== 0b/5 Re-seal nested bundles (.framework, nested .app, .xpc) deepest-first …"
NESTED_LIST="$(mktemp -t fluffy_nested_bundles)"
SORTED_BUNDLES="$(mktemp -t fluffy_nested_sorted)"
find "$APP/Contents" -type d \( -name "*.app" -o -name "*.framework" -o -name "*.xpc" -o -name "*.appex" \) -print >"$NESTED_LIST"
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

echo "Sealing $APP …"
/usr/bin/codesign --force --deep --options=runtime --timestamp \
  --sign "$FLUFFY_DEV_ID" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

echo "== 1/5 Submit ZIP of .app for notarization =="
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_SUBMIT"
set +o pipefail
xcrun notarytool submit "$ZIP_SUBMIT" \
  "${NOTARY_AUTH[@]}" \
  --wait 2>&1 | tee "$SUBMIT_LOG"
NSUBMIT="${PIPESTATUS[0]}"
set -o pipefail
if [[ "$NSUBMIT" -ne 0 ]]; then
  echo "notarytool submit exited with $NSUBMIT" >&2
  exit "$NSUBMIT"
fi
assert_notary_accepted "$SUBMIT_LOG"

echo "== 2/5 Staple FluffyFlash.app =="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "== 3/5 Rebuild DMG from stapled app =="
mkdir -p "$OUT_DMG_DIR"
rm -f "$DMG_OUT"
cd "$REPO_ROOT"
FLUFFYFLASH_APP="$APP" ./Scripts/build_dmg.sh
mv -f "$REPO_ROOT/ReleaseArtifacts/FluffyFlash.dmg" "$DMG_OUT"

echo "== 4/5 Submit DMG for notarization =="
SUBMIT_LOG_DMG="${SUBMIT_LOG}.dmg"
set +o pipefail
xcrun notarytool submit "$DMG_OUT" \
  "${NOTARY_AUTH[@]}" \
  --wait 2>&1 | tee "$SUBMIT_LOG_DMG"
NSUBMIT_DMG="${PIPESTATUS[0]}"
set -o pipefail
if [[ "$NSUBMIT_DMG" -ne 0 ]]; then
  echo "notarytool submit (DMG) exited with $NSUBMIT_DMG" >&2
  exit "$NSUBMIT_DMG"
fi
assert_notary_accepted "$SUBMIT_LOG_DMG"

echo "== 5/5 Staple DMG =="
xcrun stapler staple "$DMG_OUT"
xcrun stapler validate "$DMG_OUT"

echo "Done."
echo "  Stapled app: $APP"
echo "  Stapled dmg: $DMG_OUT"
ls -lh "$APP" "$DMG_OUT"
