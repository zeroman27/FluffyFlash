#!/bin/bash
#
# Local/CI guardrail: fail if sensitive paths are tracked.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

forbidden=(
  '^ObsidianVault/'
  '^FluffyFlash/ReleaseArtifacts/'
  '^FluffyFlash/.*/Tools/bin/'
  '^FluffyFlash/.*/Tools/lib/'
  '^FluffyFlash/EmbeddedCLI/lib/'
  '^FluffyFlash/.*\.xcodeproj/xcuserdata/'
)

failed=0
for pat in "${forbidden[@]}"; do
  if git ls-files | grep -E "$pat" >/dev/null 2>&1; then
    echo "Found forbidden tracked paths matching: $pat"
    git ls-files | grep -E "$pat" | head -n 50
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo ""
  echo "Move these paths to the private repo or remove from git tracking."
  exit 1
fi

echo "OK: no forbidden tracked paths found."

