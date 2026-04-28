# GitHub Public/Private scope (security)

Goal: publish source code and legally required materials **without** leaking internal notes, release artifacts, signing keys, or developer-local data.

## Public (allowed / required)

- App sources (`FluffyFlash/**`), excluding bundled binary artifacts.
- `LICENSE` (Apache-2.0) and licensing docs:
  - `FluffyFlash/THIRD_PARTY.md`
  - (optional) `FluffyFlash/THIRD_PARTY_NOTICES.txt` — can live in the repo or be generated and shipped only in releases.
- Compliance/build scripts without secrets:
  - `FluffyFlash/Scripts/build_third_party_sources_bundle.sh`
  - `FluffyFlash/Scripts/bundle-mac-cli-tools.sh` (only if it doesn’t pull secrets and doesn’t include private URLs)
- Installation/build/signing documentation (without real Team IDs, certificate identifiers, or personal data).

## Private (must not go public)

- `ObsidianVault/**` — internal notes (Vision/Roadmap/Backlog/Sessions/Decisions/Legal).
- `FluffyFlash/ReleaseArtifacts/**` — third-party sources and compliance artifacts (prefer release assets or a private repo/archive).
- `FluffyFlash/**/Tools/bin/**` and `FluffyFlash/**/EmbeddedCLI/lib/**` — bundled binaries and dylibs.
- `FluffyFlash/*.xcodeproj/xcuserdata/**` — local Xcode settings.
- Any signing keys/certs/profiles: `*.p12`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, etc.
- Logs/dumps and local artifacts (`*.log`, `DerivedData/`, `xcuserdata/`, etc.).

## Special attention (do not expose in public)

- `SMPrivilegedExecutables` / `SMAuthorizedClients` in `FluffyFlash/App-Info.plist` and `FluffyFlash/PrivilegedHelper/PrivilegedHelperInfo.plist` may contain `certificate leaf[subject.OU] = \"...\"` (Team ID). For a public repo this should be replaced with a safe placeholder and documented as a setup step.

