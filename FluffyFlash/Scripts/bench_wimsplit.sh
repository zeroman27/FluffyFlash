#!/bin/bash
# Bench helper for FAT32 install.wim splitting speed.
#
# Usage:
#   ./FluffyFlash/Scripts/bench_wimsplit.sh /path/to/install.wim /path/to/dest_dir [part_size_mb]
#
# Example (split to USB volume):
#   ./FluffyFlash/Scripts/bench_wimsplit.sh "/Volumes/CCCOMA_X64FRE_EN-US_DV9/sources/install.wim" "/Volumes/WINSETUP/sources" 4000
#
# Notes:
# - Requires wimlib-imagex (Homebrew: `brew install wimlib`)
# - Destination should be a directory; output will be install.swm, install2.swm, ...
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/install.wim /path/to/dest_dir [part_size_mb]" >&2
  exit 2
fi

SRC="$1"
DEST_DIR="$2"
PART_MB="${3:-3800}"

if [[ ! -f "$SRC" ]]; then
  echo "error: source file not found: $SRC" >&2
  exit 2
fi

if [[ ! -d "$DEST_DIR" ]]; then
  echo "error: destination directory not found: $DEST_DIR" >&2
  exit 2
fi

if ! command -v wimlib-imagex >/dev/null 2>&1; then
  echo "error: wimlib-imagex not found in PATH. Install with: brew install wimlib" >&2
  exit 2
fi

OUT="$DEST_DIR/install.swm"

SRC_BYTES="$(/usr/bin/stat -f%z "$SRC" 2>/dev/null || echo 0)"
if [[ "$SRC_BYTES" == "0" ]]; then
  echo "warning: could not stat source size; throughput will be omitted" >&2
fi

echo "Source: $SRC"
echo "Dest:   $OUT*"
echo "Part:   ${PART_MB} MB"
echo

# Cleanup old outputs to avoid mixing runs.
rm -f "$DEST_DIR/install.swm" "$DEST_DIR/install2.swm" "$DEST_DIR/install3.swm" "$DEST_DIR/install4.swm" \
      "$DEST_DIR/install5.swm" "$DEST_DIR/install6.swm" "$DEST_DIR/install7.swm" "$DEST_DIR/install8.swm" \
      "$DEST_DIR/install9.swm" "$DEST_DIR/install10.swm" 2>/dev/null || true

START_NS="$(/bin/date +%s%N)"
echo "Running: wimlib-imagex split \"${SRC}\" \"${OUT}\" ${PART_MB}"
echo

# /usr/bin/time prints resource usage to stderr; keep it visible for copy/paste.
/usr/bin/time -lp wimlib-imagex split "$SRC" "$OUT" "$PART_MB"

END_NS="$(/bin/date +%s%N)"

ELAPSED_NS=$((END_NS - START_NS))
if [[ "$ELAPSED_NS" -le 0 ]]; then
  exit 0
fi

ELAPSED_S="$(python3 - <<'PY'
import os
ns = int(os.environ["ELAPSED_NS"])
print(f"{ns/1e9:.3f}")
PY
)"

echo
echo "Elapsed: ${ELAPSED_S}s"

if [[ "$SRC_BYTES" != "0" ]]; then
  MBPS="$(python3 - <<'PY'
import os
bytes_ = float(os.environ["SRC_BYTES"])
elapsed = float(os.environ["ELAPSED_S"])
if elapsed <= 0: 
    print("0")
else:
    print(f"{(bytes_/1024/1024)/elapsed:.1f}")
PY
)"
  echo "Throughput (approx): ${MBPS} MiB/s"
fi

