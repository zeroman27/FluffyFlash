#!/usr/bin/env bash
# Build a drag-to-Applications DMG with docs/dmg/background.png.
# Usage:
#   ./Scripts/build_dmg.sh [/path/to/FluffyFlash.app]
# Env:
#   FLUFFYFLASH_APP — overrides the app path (default: Archive-style export path below).
#   DMG_WINDOW_WIDTH — window width in pt (default 660).
#   DMG_TITLEBAR_PT — Finder draws the folder background *below* the title bar; outer window
#     height must be inner_content_height + this fudge or the image aspect won’t match the
#     painted rect (typical 24–32; tweak if the fur frame still looks cropped).
#   DMG_BG_PIXEL_MODE — `window` (default): resample PNG to WINW×INNER_H **pixels** so Finder’s
#     usual 1px≈1pt mapping shows the whole art (fixes “zoomed/cropped” 1320-wide assets).
#     `retina2x`: old behaviour WINW×2 by INNER×2 for sharper Retina (may look zoomed on some OS).
#   DMG_BACKGROUND_SCALE — only for retina2x mode (default 2).
#   DMG_ICON_APP_X / DMG_ICON_APPS_X / DMG_ICON_Y — optional overrides (Finder pt coords).

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG="${REPO_ROOT}/../docs/dmg/background.png"
DEFAULT_EXPORT="/Users/igor.garber/Documents/FluffyFlash 2026-05-02 23-13-08/Products/Applications/FluffyFlash.app"
DEBUG_APP="${REPO_ROOT}/build/Debug/FluffyFlash.app"
if [[ -n "${FLUFFYFLASH_APP:-}" ]]; then
  APP_IN="$FLUFFYFLASH_APP"
elif [[ -d "$DEFAULT_EXPORT" ]]; then
  APP_IN="$DEFAULT_EXPORT"
elif [[ -d "$DEBUG_APP" ]]; then
  APP_IN="$DEBUG_APP"
else
  APP_IN="$DEFAULT_EXPORT"
fi
OUT_DIR="${REPO_ROOT}/ReleaseArtifacts"
OUT_DMG="${OUT_DIR}/FluffyFlash.dmg"

if [[ ! -f "$BG" ]]; then
  echo "Missing background: $BG" >&2
  exit 1
fi
if [[ ! -d "$APP_IN" ]]; then
  echo "Missing app bundle: $APP_IN" >&2
  echo "Build/export FluffyFlash.app or set FLUFFYFLASH_APP to its path." >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Install create-dmg: brew install create-dmg" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
BG_TMP=""
cleanup() { rm -rf "$STAGE"; [[ -n "$BG_TMP" ]] && rm -f "$BG_TMP"; }
trap cleanup EXIT

ditto "$APP_IN" "$STAGE/FluffyFlash.app"
mkdir -p "$OUT_DIR"
# hdiutil convert can fail if a previous run left the same path in a bad state
rm -f "$OUT_DMG" "${OUT_DIR}"/rw.*.dmg 2>/dev/null || true

# Finder icon-view background: on many macOS versions the PNG is mapped ~1 image pixel to
# 1 **point** of the *content* area. A 1320px-wide image in a ~660pt-wide inner rect therefore
# looks “zoomed” (only half the art visible). Default `window` mode resamples to WINW×INNER_H px.
IMGW=$(sips -g pixelWidth  "$BG" 2>/dev/null | awk '/pixelWidth:/{print $2}')
IMGH=$(sips -g pixelHeight "$BG" 2>/dev/null | awk '/pixelHeight:/{print $2}')
if [[ -z "$IMGW" || -z "$IMGH" || "$IMGW" -lt 1 || "$IMGH" -lt 1 ]]; then
  echo "Could not read dimensions of $BG (sips)" >&2
  exit 1
fi

WINW=${DMG_WINDOW_WIDTH:-660}
TBAR=${DMG_TITLEBAR_PT:-28}
BG_MODE="${DMG_BG_PIXEL_MODE:-window}"

# Inner content height (pt) matching source aspect — same as typical “660×440 canvas” minus title bar band.
INNER_H=$(( (WINW * IMGH + IMGW / 2) / IMGW ))
OUTER_H=$(( INNER_H + TBAR ))

if [[ "$BG_MODE" == "retina2x" ]]; then
  SCALE=${DMG_BACKGROUND_SCALE:-2}
  PIX_W=$(( WINW * SCALE ))
  PIX_H=$(( INNER_H * SCALE ))
else
  PIX_W=$WINW
  PIX_H=$INNER_H
fi

BG_TMP="${TMPDIR:-/tmp}/fluffy_dmg_resample_$$.png"
sips -z "$PIX_H" "$PIX_W" "$BG" --out "$BG_TMP" >/dev/null 2>&1
# Hint Finder this is a logical-window-sized asset (helps some macOS builds).
sips -s dpiWidth 72 -s dpiHeight 72 "$BG_TMP" >/dev/null 2>&1 || true

echo "DMG geometry: bg ${IMGW}x${IMGH}px → mode=${BG_MODE} resampled ${PIX_W}x${PIX_H}px; window ${WINW}x${OUTER_H} pt (inner ~${WINW}x${INNER_H} + titlebar ~${TBAR})"

# Icon coords: background has a centered wordmark + arrow — keep .app left of the arrow tail
# and Applications right of the arrowhead (~18% / ~81% of window width). Y sits mid content band.
APP_X="${DMG_ICON_APP_X:-$(( WINW * 18 / 100 ))}"
APPS_X="${DMG_ICON_APPS_X:-$(( WINW * 81 / 100 ))}"
ICON_Y="${DMG_ICON_Y:-$(( TBAR + INNER_H * 46 / 100 ))}"
if [[ "$APPS_X" -gt $(( WINW - 85 )) ]]; then APPS_X=$(( WINW - 85 )); fi
if [[ "$APP_X" -lt 72 ]]; then APP_X=72; fi

create-dmg \
  --volname "Fluffy Flash" \
  --background "$BG_TMP" \
  --window-size "$WINW" "$OUTER_H" \
  --icon-size 108 \
  --hide-extension "FluffyFlash.app" \
  --icon "FluffyFlash.app" "$APP_X" "$ICON_Y" \
  --app-drop-link "$APPS_X" "$ICON_Y" \
  --hdiutil-quiet \
  "$OUT_DMG" \
  "$STAGE"

echo "Done: $OUT_DMG"
ls -lh "$OUT_DMG"
shasum -a 256 "$OUT_DMG"
