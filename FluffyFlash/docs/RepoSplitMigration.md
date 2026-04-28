# Public/Private repo split migration (safe sequence)

Goal: create a **Public** repo with source code and required legal materials, and a **Private** repo with Obsidian notes and release artifacts — without accidentally leaking anything sensitive.

## 0) Preparation

- Create two repositories:
  - `fluffyflash` (Public)
  - `fluffyflash-private` (Private)
- Decide where GPL tool source bundles will live:
  - Recommended: publish them as **Release assets** in Public releases (this satisfies “provide source when distributing”).
  - The Private repo can be used as an archive, but Public releases should contain the assets (or a clear path to obtain them).

## 1) Public repo: what to keep

Keep:
- `FluffyFlash/**` (sources)
- `LICENSE`
- `FluffyFlash/THIRD_PARTY.md`
- `FluffyFlash/THIRD_PARTY_NOTICES.txt` (optional)
- `.cursor/rules/**` (only safe rules)
- `.github/workflows/guardrails.yml` (secret scanning + private-path denylist)

Remove / do not move:
- `ObsidianVault/**`
- `FluffyFlash/ReleaseArtifacts/**`
- `FluffyFlash/**/Tools/bin/**`, `FluffyFlash/**/Tools/lib/**`, `FluffyFlash/EmbeddedCLI/lib/**`
- `xcuserdata/**` and other local artifacts

## 2) Private repo: what to store

Move:
- `ObsidianVault/**`
- (optional) `FluffyFlash/ReleaseArtifacts/**` and other internal materials

## 3) Git history: avoid dragging private files into Public

Options:
- **Option A (safest): new Public repo without history**
  - Export only the required directories/files (fresh init).
  - Pros: it’s extremely hard to accidentally publish historical secrets.
  - Cons: you lose public git history.

- **Option B (keep history): filter the history**
  - Use `git filter-repo` to remove `ObsidianVault/**`, `ReleaseArtifacts/**`, `Tools/bin/**`, and any sensitive files from *all* history.
  - Pros: preserves history.
  - Cons: more complex; requires careful dry-runs and verification.

For “professional and safe”, **A** is usually recommended unless public history is critical.

## 4) Checks before publishing

- Run locally:
  - `FluffyFlash/Scripts/check_public_scope.sh`
- Enable GitHub Actions:
  - `.github/workflows/guardrails.yml` (gitleaks + path restrictions)

## 5) After publishing

In the release process, each release should attach:
- `FluffyFlash/THIRD_PARTY_NOTICES.txt`
- `FluffyFlash/ReleaseArtifacts/third-party/manifest.json`
- `FluffyFlash/ReleaseArtifacts/third-party/third-party-sources.tar.gz`

