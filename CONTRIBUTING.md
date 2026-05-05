# Contributing to Fluffy Flash

Thanks for helping improve **Fluffy Flash**. This repository is mostly macOS / Swift; the quickest path is to build locally and open a PR against `main`.

## Before you change code

1. Open **`Fluffy Flash.xcodeproj`** under [`FluffyFlash/`](FluffyFlash/) and select the **FluffyFlash** scheme.  
2. For a fast iteration loop without re-downloading bundled tools, use  
   `WIST_SKIP_TOOL_BUNDLE=1`  
   (see [`FluffyFlash/README.md`](FluffyFlash/README.md)).  
3. If you add or upgrade **any** bundled third-party binary, library, or script, update **`FluffyFlash/THIRD_PARTY.md`** and related notices as required by the project policy.

## Pull requests

- Keep commits focused; match existing Swift style and naming.  
- Add or adjust **unit tests** when behavior changes (`FluffyFlashTests`).  
- CI runs [**Guardrails**](.github/workflows/guardrails.yml) on PRs — avoid committing forbidden paths (private vault data, embedded tool binaries in ignored locations, etc.).

## Issues

When reporting bugs, include **macOS version**, **app version**, and steps to reproduce. For USB or disk issues, describe the volume layout only — never paste secrets or full disk identifiers if they identify sensitive environments.

## Signing & releases

Maintainers: signing, notarization, and GitHub Actions secrets are documented in [`FluffyFlash/docs/Signing.md`](FluffyFlash/docs/Signing.md) and [`docs/RELEASING.md`](docs/RELEASING.md).
