# Releasing Fluffy Flash

This document describes how to produce an end-to-end release of Fluffy Flash via the GitHub Actions pipeline in [`.github/workflows/release.yml`](../.github/workflows/release.yml).

The pipeline supports **two paths**:

1. Manual dry-run (`workflow_dispatch`) — produces an unsigned `.app` and the GPL source bundle. Used for verifying the pipeline without publishing a Release.
2. Tag push (`v*`) — produces a Release attached to the tag. If the codesign / notarization secrets are present, the `.app` is signed and notarized automatically.

## Prerequisites

| Need | Where it lives |
| --- | --- |
| Apple Developer Program enrolment | apple.com |
| Developer ID Application certificate (`.p12` + password) | local Keychain export |
| App-specific password (Apple ID) | appleid.apple.com → "App-Specific Passwords" |
| Apple Team ID | appleid.apple.com / Apple Developer portal |

## GitHub Secrets

Set the following on the repository (Settings → Secrets and variables → Actions):

| Secret | Description |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` of the exported certificate. |
| `MACOS_CERTIFICATE_PASSWORD` | The password used to export the `.p12`. |
| `MACOS_KEYCHAIN_PASSWORD` | Any throwaway string. Used to lock the temporary CI keychain. |
| `MACOS_DEVELOPER_ID_APPLICATION_NAME` | Identity name, e.g. `Developer ID Application: Foo Bar (TEAMID)`. |
| `APPLE_ID` | Apple ID email used for notarization. |
| `APPLE_TEAM_ID` | Apple Team ID (10-char string). |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password generated for notarization. |

If any of these is missing, the pipeline still succeeds but produces an **unsigned** build (signing/notarization steps log a warning and skip).

## 1. Manual dry-run (no release published)

Use this on every meaningful workflow change before tagging.

```bash
gh workflow run "Release artifacts" --ref main \
  -f sign_and_notarize=false
gh run watch
```

Artifacts (downloadable from the run page):

- `FluffyFlash-<branch-or-dev>.zip`
- `FluffyFlash-<branch-or-dev>.zip.sha256`
- `THIRD_PARTY_NOTICES.txt`
- `third-party-sources.tar.gz`
- `tool-versions.txt`
- `third-party-manifest.json`

If `sign_and_notarize=true` is passed, the same workflow also runs codesign + `notarytool submit --wait` + `stapler staple` — provided secrets are configured.

## 2. Tag-driven release (publishes a GitHub Release)

```bash
git switch main
git pull --rebase
git tag v0.0.0-rc1
git push origin v0.0.0-rc1
gh run watch
```

The workflow auto-creates a GitHub Release named after the tag and attaches all artifacts above.

To delete a test release and tag:

```bash
gh release delete v0.0.0-rc1 --yes --cleanup-tag
```

## 3. Local verification of a downloaded build

```bash
unzip FluffyFlash-v0.0.0-rc1.zip
codesign --verify --deep --strict --verbose=2 FluffyFlash.app
spctl -a -vv -t install FluffyFlash.app
xcrun stapler validate FluffyFlash.app
```

Expected: `accepted, source=Notarized Developer ID`.

## 4. Common failure modes

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `xcodebuild` step fails during `Bundle Embedded CLI Tools` | Homebrew not yet primed on runner | The workflow now runs `bundle-mac-cli-tools.sh` explicitly before `xcodebuild`. Make sure brew is reachable. |
| `notarytool submit` rejects with `Invalid` | Missing hardened runtime, expired cert, embedded binary unsigned | Inspect notarization log: `xcrun notarytool log <submission-id> --apple-id ... --team-id ...`. Sign every Mach-O inside `Resources/Tools/bin` and `EmbeddedCLI/lib`. |
| `spctl` reports `unsigned` | Pipeline ran without secrets | Configure all secrets above and rerun. |
| Tag-driven build does not pick up new files | The new files are not committed | The workflow checks out the tagged commit; ensure all changes are committed before tagging. |

## 5. Updating third-party tooling

Whenever a bundled CLI tool is added/replaced, follow `.cursor/rules/legal-third-party-intake.mdc` and update:

- [`FluffyFlash/THIRD_PARTY.md`](../FluffyFlash/THIRD_PARTY.md)
- [`FluffyFlash/THIRD_PARTY_NOTICES.txt`](../FluffyFlash/THIRD_PARTY_NOTICES.txt)
- [`FluffyFlash/Scripts/build_third_party_sources_bundle.sh`](../FluffyFlash/Scripts/build_third_party_sources_bundle.sh)
- [`ObsidianVault/10-Project-Wist/Legal.md`](../ObsidianVault/10-Project-Wist/Legal.md)
