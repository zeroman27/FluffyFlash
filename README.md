# Fluffy Flash

[![Release](https://img.shields.io/github/v/release/zeroman27/FluffyFlash?display_name=tag&sort=semver)](https://github.com/zeroman27/FluffyFlash/releases)
[![License](https://img.shields.io/github/license/zeroman27/FluffyFlash)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](#)

**Languages:** **English** · [Русский](README.ru.md)

**Fluffy Flash** is a macOS app (SwiftUI) that helps you:

- download Windows build sources via [UUPDump](https://uupdump.net)
- build a Windows **ISO** and/or write a **bootable Windows installer USB** on a Mac
- (optional) work with macOS installers and IPSW downloads via `mist` in the corresponding app mode

The key idea: in release builds, users typically **don’t need Homebrew** — the required CLI toolchain can be bundled inside the `.app` (with proper third‑party attribution and notices).

<p align="center">
  <img src="docs/images/screenshot-home-windows.png" alt="Fluffy Flash — Windows mode (home screen)" width="900" />
</p>

## Features

- **UUP → ISO**: runs the official `convert.sh` (UUP converter) with progress streaming  
- **ISO → USB**: creates a bootable installer USB (FAT32 layout + `install.wim` handling)  
- **Bundled toolchain (release builds)**: the `.app` may include `aria2c`, `cabextract`, `wimlib-imagex`, `xorriso` (or compatible `mkisofs`/`genisoimage`), `chntpw`, etc.  
- **Privileged helper**: for operations where macOS requires elevated privileges (disks/partitions)  
- **Third‑party compliance**: inventory and notices live in [`FluffyFlash/THIRD_PARTY.md`](FluffyFlash/THIRD_PARTY.md) and [`FluffyFlash/THIRD_PARTY_NOTICES.txt`](FluffyFlash/THIRD_PARTY_NOTICES.txt)

## Requirements

- **macOS**: depends on the `MACOSX_DEPLOYMENT_TARGET` set in the Xcode project (`Fluffy Flash.xcodeproj`).  
- **CPU architecture**:
  - current release may be Apple Silicon focused
  - **Intel support is planned for a future release** (it requires shipping an x86_64‑compatible bundled toolchain)

## Download

Stable builds are published on **GitHub Releases**: https://github.com/zeroman27/FluffyFlash/releases

## Screenshots

Images live under `docs/images/` (export/naming tips: [`docs/images/README.md`](docs/images/README.md)).

<p>
  <img src="docs/images/screenshot-home-winbuild.png" alt="Windows: building an ISO from UUP" width="420" />
  <img src="docs/images/screenshot-settings.png" alt="Settings" width="420" />
</p>

<p>
  <img src="docs/images/screenshot-home-macos.png" alt="macOS: downloads mode" width="420" />
  <img src="docs/images/screenshot-home-macinstaller.png" alt="macOS: installer selection" width="420" />
</p>

## Build from source

See **[`FluffyFlash/README.md`](FluffyFlash/README.md)**.

Quick notes:
- Xcode project: `FluffyFlash/Fluffy Flash.xcodeproj`
- scheme: `FluffyFlash`
- to iterate faster and avoid re-downloading bundled tools on each build, you can use `WIST_SKIP_TOOL_BUNDLE=1`

Release automation / signing / notarization: **[`docs/RELEASING.md`](docs/RELEASING.md)** and **[`FluffyFlash/docs/Signing.md`](FluffyFlash/docs/Signing.md)**.

## FAQ / Troubleshooting

See **[`docs/FAQ.md`](docs/FAQ.md)**.

## Repository layout

- **`FluffyFlash/`**: Xcode project, app sources, scripts, third‑party inventory  
- **`docs/`**: maintainer docs and README assets  
- **`ObsidianVault/`**: internal notes/planning (not required to build the app)

## Contributing

See **[`CONTRIBUTING.md`](CONTRIBUTING.md)**.

## License

Source code: **Apache License 2.0** — see [`LICENSE`](LICENSE).

Third‑party bundled components and obligations: [`FluffyFlash/THIRD_PARTY.md`](FluffyFlash/THIRD_PARTY.md) and [`FluffyFlash/THIRD_PARTY_NOTICES.txt`](FluffyFlash/THIRD_PARTY_NOTICES.txt).

## Security

The app performs disk operations and network downloads by design; sandboxing is intentionally limited for USB workflows. For responsible disclosure: **[`SECURITY.md`](SECURITY.md)**.
