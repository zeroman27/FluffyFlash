#!/bin/bash
#
# Build a source bundle for GPL/third‑party compliance.
# Intended usage: run this on the release build machine, then attach the outputs as GitHub Release assets.
#
# Outputs:
# - FluffyFlash/ReleaseArtifacts/third-party/THIRD_PARTY_NOTICES.txt
# - FluffyFlash/ReleaseArtifacts/third-party/tool-versions.txt
# - FluffyFlash/ReleaseArtifacts/third-party/third-party-sources.tar.gz
#
# Notes:
# - This script is deliberately conservative: it records evidence (versions) and downloads upstream source tarballs.
# - It does NOT modify the app bundle. It only prepares release artifacts.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/ReleaseArtifacts/third-party"
mkdir -p "$OUT_DIR"

NOTICES_SRC="$ROOT/THIRD_PARTY_NOTICES.txt"
NOTICES_DST="$OUT_DIR/THIRD_PARTY_NOTICES.txt"

if [[ ! -f "$NOTICES_SRC" ]]; then
  echo "error: missing $NOTICES_SRC"
  exit 1
fi
cp -f "$NOTICES_SRC" "$NOTICES_DST"

VERSIONS_FILE="$OUT_DIR/tool-versions.txt"
: > "$VERSIONS_FILE"

record_tool_version() {
  local label="$1"
  local bin="$2"
  echo "== $label ==" >> "$VERSIONS_FILE"
  if [[ -x "$bin" ]]; then
    # Best-effort: tools vary in flags and some may crash on unsupported machines.
    # Run each attempt in a subshell to avoid noisy "Abort trap" lines.
    local out=""
    for args in "--version" "-V" "-v"; do
      out="$(bash -lc "\"$bin\" $args" 2>/dev/null | head -n 5 || true)"
      if [[ -n "${out// /}" ]]; then
        echo "$out" >> "$VERSIONS_FILE"
        out=""
        break
      fi
    done
    if [[ -n "${out// /}" ]]; then
      echo "$out" >> "$VERSIONS_FILE"
    fi
    if ! tail -n 1 "$VERSIONS_FILE" | grep -q .; then
      echo "(could not read version; tool may have crashed)" >> "$VERSIONS_FILE"
    fi
  else
    echo "(missing binary: $bin)" >> "$VERSIONS_FILE"
  fi
  echo "" >> "$VERSIONS_FILE"
}

# Prefer the exact binaries we ship (Tools/bin). This keeps evidence aligned with the distributed `.app`.
TOOLS_BIN="$ROOT/Fluffy Flash/Tools/bin"
record_tool_version "aria2c"        "$TOOLS_BIN/aria2c"
record_tool_version "cabextract"    "$TOOLS_BIN/cabextract"
record_tool_version "wimlib-imagex" "$TOOLS_BIN/wimlib-imagex"
record_tool_version "chntpw"        "$TOOLS_BIN/chntpw"
record_tool_version "mkisofs"       "$TOOLS_BIN/mkisofs"
record_tool_version "mist"          "$TOOLS_BIN/mist"

# Capture Homebrew package versions as additional evidence (best-effort).
if command -v brew &>/dev/null; then
  {
    echo "== brew list --versions =="
    brew list --versions aria2 cabextract wimlib cdrtools mist-cli minacle/chntpw/chntpw 2>/dev/null || true
    echo ""
    echo "== brew info (selected) =="
    brew info aria2 cabextract wimlib cdrtools mist-cli minacle/chntpw/chntpw 2>/dev/null || true
  } >> "$VERSIONS_FILE"
fi

# Download upstream source tarballs.
# Primary mode (preferred): derive URL + sha256 from Homebrew formula metadata.
# Fallback mode: use pinned URLs below if Homebrew metadata is unavailable.
SRC_DIR="$OUT_DIR/sources"
mkdir -p "$SRC_DIR"

MANIFEST_JSON="$OUT_DIR/manifest.json"
MANIFEST_NDJSON="$OUT_DIR/manifest.ndjson"
: > "$MANIFEST_NDJSON"

download() {
  local url="$1"
  local out="$2"
  if [[ -f "$out" ]]; then
    echo "Using cached $(basename "$out")"
    return 0
  fi
  echo "Downloading $url"
  curl -L --fail --retry 3 --retry-delay 2 -o "$out" "$url"
}

SHA256_FILE="$OUT_DIR/source-sha256.txt"
: > "$SHA256_FILE"

append_manifest_entry() {
  local name="$1"
  local version="$2"
  local license="$3"
  local source_url="$4"
  local filename="$5"
  local sha256="$6"
  local method="$7"

  python3 - "$name" "$version" "$license" "$source_url" "$filename" "$sha256" "$method" >> "$MANIFEST_NDJSON" <<'PY'
import json, sys
name, version, license, source_url, filename, sha256, method = sys.argv[1:]
print(json.dumps({
  "name": name,
  "version": version,
  "license": license,
  "source_url": source_url,
  "filename": filename,
  "sha256": sha256,
  "method": method,
}, ensure_ascii=False))
PY
}

finalize_manifest_json() {
  python3 - "$MANIFEST_NDJSON" "$MANIFEST_JSON" <<'PY'
import json, sys
ndjson_path, out_path = sys.argv[1], sys.argv[2]
items = []
with open(ndjson_path, "r", encoding="utf-8") as f:
  for line in f:
    line = line.strip()
    if not line:
      continue
    items.append(json.loads(line))
with open(out_path, "w", encoding="utf-8") as f:
  json.dump({"sources": items}, f, ensure_ascii=False, indent=2)
  f.write("\n")
PY
}

brew_formula_source() {
  # Prints: <name>\t<version>\t<stable_url>\t<sha256>
  # Uses brew's JSON to avoid scraping human-readable output.
  local formula="$1"
  python3 - "$formula" <<'PY'
import json, subprocess, sys

formula = sys.argv[1]
try:
  raw = subprocess.check_output(["brew", "info", "--json=v2", formula], text=True)
except Exception:
  sys.exit(2)

data = json.loads(raw)
items = data.get("formulae") or []
if not items:
  sys.exit(3)

f = items[0]
name = f.get("name") or formula
versions = f.get("versions") or {}
version = versions.get("stable") or versions.get("head") or "unknown"
stable = f.get("urls", {}).get("stable", {})
url = stable.get("url") or ""
# Homebrew JSON uses "checksum" for stable URL.
sha256 = stable.get("checksum") or stable.get("sha256") or ""
print(f"{name}\t{version}\t{url}\t{sha256}")
PY
}

download_from_brew_formula() {
  local formula="$1"
  local out_prefix="$2"
  local license="$3"

  local line
  if ! line="$(brew_formula_source "$formula" 2>/dev/null)"; then
    return 1
  fi

  local name version url sha256
  name="$(echo "$line" | cut -f1)"
  version="$(echo "$line" | cut -f2)"
  url="$(echo "$line" | cut -f3)"
  sha256="$(echo "$line" | cut -f4)"

  if [[ -n "$url" && -n "$sha256" ]]; then
    local ext="tar.gz"
    case "$url" in
      *.tar.xz)  ext="tar.xz" ;;
      *.tar.bz2) ext="tar.bz2" ;;
      *.zip)     ext="zip" ;;
      *.tgz)     ext="tgz" ;;
      *.tar.gz)  ext="tar.gz" ;;
    esac
    local out="$SRC_DIR/${out_prefix}-${version}.${ext}"
    download "$url" "$out"
    echo "$sha256  $(basename "$out")" >> "$SHA256_FILE"
    append_manifest_entry "$out_prefix" "$version" "$license" "$url" "$(basename "$out")" "$sha256" "brew-json"
    return 0
  fi

  # Fallback: ask Homebrew to fetch the exact source it would build from.
  # This avoids relying on URL fields that may be absent for some formulae/taps.
  local fetched
  fetched="$(python3 - "$formula" <<'PY'
import re, subprocess, sys

formula = sys.argv[1]
cmd = ["brew", "fetch", "--force", "--retry", "--build-from-source", "-v", formula]
proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
out = proc.stdout or ""
if proc.returncode != 0:
  sys.exit(proc.returncode)

# Heuristics: find the last path-like token that looks like a downloaded archive.
paths = []
for line in out.splitlines():
  m = re.search(r"(/.*\\.(?:tar\\.(?:gz|bz2|xz)|zip))\\b", line)
  if m:
    paths.append(m.group(1))
if paths:
  print(paths[-1])
  sys.exit(0)
sys.exit(2)
PY
)" || return 1

  if [[ ! -f "$fetched" ]]; then
    return 1
  fi

  local ext="tar.gz"
  case "$fetched" in
    *.tar.bz2) ext="tar.bz2" ;;
    *.tar.xz)  ext="tar.xz" ;;
    *.zip)     ext="zip" ;;
  esac

  local out="$SRC_DIR/${out_prefix}-${version}.${ext}"
  if [[ -f "$out" ]]; then
    echo "Using cached $(basename "$out")"
  else
    cp -f "$fetched" "$out"
  fi
  local computed
  computed="$(shasum -a 256 "$out" | awk '{print $1}')"
  echo "$computed  $(basename "$out")" >> "$SHA256_FILE"
  append_manifest_entry "$out_prefix" "$version" "$license" "brew-fetch:$formula" "$(basename "$out")" "$computed" "brew-fetch"
  return 0
}

BREW_OK=0
if command -v brew &>/dev/null; then
  # Sanity check: brew must be functional (sometimes PATH exists but brew isn't usable in CI).
  if ! brew --version >/dev/null 2>&1; then
    echo "warning: brew exists but is not functional; falling back to pinned source URLs" >&2
  else
  # Formulae installed by FluffyFlash/Scripts/bundle-mac-cli-tools.sh
  if download_from_brew_formula "aria2" "aria2" "GPL-2.0-or-later"; then BREW_OK=1; fi
  if download_from_brew_formula "cabextract" "cabextract" "GPL-3.0-or-later"; then BREW_OK=1; fi
  if download_from_brew_formula "wimlib" "wimlib" "GPL-3.0-or-later"; then BREW_OK=1; fi
  if download_from_brew_formula "cdrtools" "cdrtools" "CDDL-1.0"; then BREW_OK=1; fi
  if download_from_brew_formula "mist-cli" "mist-cli" "MIT"; then BREW_OK=1; fi
  if download_from_brew_formula "minacle/chntpw/chntpw" "chntpw" "GPL-2.0"; then BREW_OK=1; fi
  fi
fi

if [[ "$BREW_OK" -eq 0 ]]; then
  echo "warning: Homebrew metadata unavailable; using pinned source URLs" >&2
  download "https://github.com/aria2/aria2/archive/refs/tags/release-1.37.0.tar.gz" "$SRC_DIR/aria2-release-1.37.0.tar.gz"
  append_manifest_entry "aria2" "release-1.37.0" "GPL-2.0-or-later" "https://github.com/aria2/aria2/archive/refs/tags/release-1.37.0.tar.gz" "aria2-release-1.37.0.tar.gz" "" "pinned"
  download "https://www.cabextract.org.uk/cabextract-1.11.tar.gz" "$SRC_DIR/cabextract-1.11.tar.gz"
  append_manifest_entry "cabextract" "1.11" "GPL-3.0-or-later" "https://www.cabextract.org.uk/cabextract-1.11.tar.gz" "cabextract-1.11.tar.gz" "" "pinned"
  download "https://wimlib.net/downloads/wimlib-1.14.5.tar.gz" "$SRC_DIR/wimlib-1.14.5.tar.gz"
  append_manifest_entry "wimlib" "1.14.5" "GPL-3.0-or-later" "https://wimlib.net/downloads/wimlib-1.14.5.tar.gz" "wimlib-1.14.5.tar.gz" "" "pinned"
  download "https://github.com/minacle/chntpw/archive/refs/tags/v1.0.3.tar.gz" "$SRC_DIR/chntpw-v1.0.3.tar.gz"
  append_manifest_entry "chntpw" "1.0.3" "GPL-2.0" "https://github.com/minacle/chntpw/archive/refs/tags/v1.0.3.tar.gz" "chntpw-v1.0.3.tar.gz" "" "pinned"
  download "https://sourceforge.net/projects/cdrtools/files/alpha/cdrtools-3.02a09.tar.gz/download" "$SRC_DIR/cdrtools-3.02a09.tar.gz"
  append_manifest_entry "cdrtools" "3.02a09" "CDDL-1.0" "https://sourceforge.net/projects/cdrtools/files/alpha/cdrtools-3.02a09.tar.gz/download" "cdrtools-3.02a09.tar.gz" "" "pinned"
  download "https://github.com/ninxsoft/mist-cli/archive/refs/tags/v2.2.tar.gz" "$SRC_DIR/mist-cli-v2.2.tar.gz"
  append_manifest_entry "mist-cli" "2.2" "MIT" "https://github.com/ninxsoft/mist-cli/archive/refs/tags/v2.2.tar.gz" "mist-cli-v2.2.tar.gz" "" "pinned"
fi

# Fill sha256 into pinned entries (if any) by matching filenames in source-sha256.txt after the fact.
python3 - "$MANIFEST_NDJSON" "$SHA256_FILE" "$MANIFEST_NDJSON.tmp" <<'PY'
import json, sys
ndjson_in, sha_path, ndjson_out = sys.argv[1:]
sha = {}
with open(sha_path, "r", encoding="utf-8") as f:
  for line in f:
    line = line.strip()
    if not line:
      continue
    h, fn = line.split(None, 1)
    sha[fn.strip()] = h

with open(ndjson_in, "r", encoding="utf-8") as src, open(ndjson_out, "w", encoding="utf-8") as dst:
  for line in src:
    line = line.strip()
    if not line:
      continue
    obj = json.loads(line)
    if not obj.get("sha256") and obj.get("filename") in sha:
      obj["sha256"] = sha[obj["filename"]]
    dst.write(json.dumps(obj, ensure_ascii=False) + "\n")
PY
mv -f "$MANIFEST_NDJSON.tmp" "$MANIFEST_NDJSON"
finalize_manifest_json

TARBALL="$OUT_DIR/third-party-sources.tar.gz"
tar -czf "$TARBALL" -C "$OUT_DIR" "sources"

echo "OK: wrote:"
echo " - $NOTICES_DST"
echo " - $VERSIONS_FILE"
echo " - $SHA256_FILE"
echo " - $MANIFEST_JSON"
echo " - $TARBALL"

