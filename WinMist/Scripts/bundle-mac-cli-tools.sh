#!/bin/bash
# Populates Wist/Wist/Tools/bin (+ lib) for embedding in the app bundle.
# Invoked automatically from an Xcode Run Script phase.
#
# Requires: Homebrew (https://brew.sh). First run may download & install packages (needs network).
# Skip: WIST_SKIP_TOOL_BUNDLE=1

set -euo pipefail

if [[ "${WIST_SKIP_TOOL_BUNDLE:-}" == "1" ]]; then
  echo "Wist: skipping embedded CLI bundle (WIST_SKIP_TOOL_BUNDLE=1)"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_BIN="$ROOT/Wist/Tools/bin"
# Keep .dylibs OUTSIDE the synchronized Wist/ sources tree — otherwise Xcode adds this path to
# LIBRARY_SEARCH_PATHS and links Wist.debug.dylib against OpenSSL/wimlib by mistake.
DEST_LIB="$ROOT/EmbeddedCLI/lib"
mkdir -p "$DEST_BIN" "$DEST_LIB"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if ! command -v brew &>/dev/null; then
  echo "error: Homebrew is not installed. Install from https://brew.sh — it is required once on the build machine to fetch CLI tools into the app bundle."
  echo "Alternatively set WIST_SKIP_TOOL_BUNDLE=1 and provide Tools/bin manually."
  exit 1
fi

BREW_PREFIX="$(brew --prefix)"
echo "Wist: using Homebrew at $BREW_PREFIX"

brew_install_if_missing() {
  local pkg="$1"
  if brew list "$pkg" &>/dev/null; then return 0; fi
  echo "Wist: brew install $pkg"
  brew install "$pkg"
}

for pkg in aria2 cabextract wimlib cdrtools; do
  brew_install_if_missing "$pkg"
done

if [[ ! -x "$BREW_PREFIX/bin/chntpw" ]]; then
  echo "Wist: installing chntpw (tap minacle/chntpw)"
  brew tap minacle/chntpw 2>/dev/null || true
  brew install minacle/chntpw/chntpw || brew install chntpw
fi

if ! command -v dylibbundler &>/dev/null; then
  echo "Wist: brew install dylibbundler (pulls dependent .dylib into Tools/lib)"
  brew install dylibbundler || true
fi

copy_one() {
  local name="$1"
  local src="$BREW_PREFIX/bin/$name"
  if [[ ! -x "$src" ]]; then
    echo "error: missing executable: $src (Homebrew package not linked?)"
    return 1
  fi
  echo "Wist: copy $src -> $DEST_BIN/"
  cp -f "$src" "$DEST_BIN/$name"
  chmod +x "$DEST_BIN/$name"
  if command -v dylibbundler &>/dev/null; then
    echo "  dylibbundler $name"
    (cd "$DEST_BIN" && dylibbundler -of -b -x "./$name" -d "$DEST_LIB" -p '@loader_path/../lib/') || true
  fi
}

for t in aria2c cabextract wimlib-imagex chntpw mkisofs; do
  copy_one "$t"
done

fail=0
for t in aria2c cabextract wimlib-imagex chntpw mkisofs; do
  if [[ ! -x "$DEST_BIN/$t" ]]; then
    echo "error: bundled tool missing: $DEST_BIN/$t"
    fail=1
  fi
done
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "Wist: embedded CLI tools OK → $DEST_BIN"
echo "Wist: next build will copy them into Wist.app via the synchronized folder."
