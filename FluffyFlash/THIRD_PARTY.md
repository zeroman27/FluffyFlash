# Third-party code (release-ready)

This file documents **what Wist/Fluffy Flash redistributes** and **what we must do** to stay compliant when shipping a `.app` that bundles third‑party code and CLI tools.

Repository license: **Apache License 2.0** (see `LICENSE`).

## Summary (what is bundled in releases)

| Component | Where it lives (repo / app) | License | Why we use it | Compliance when shipping `.app` |
|---|---|---|---|---|
| CrystalFetch code (partial) | `FluffyFlash/Fluffy Flash/ThirdParty/CrystalFetch/**` | Apache‑2.0 | UUPDump client + downloader patterns | Keep Apache headers; include Apache‑2.0 license text in distribution; keep attributions (and `NOTICE` if upstream ships one we incorporate). |
| UUP converter `convert.sh` | `FluffyFlash/Fluffy Flash/ThirdParty/UUPConverter/convert.sh` (invoked via `/bin/bash`) | MIT | Convert downloaded UUP → ISO | Include MIT license text + attribution in notices. |
| `aria2c` (bundled tool) | `Wist.app/Contents/Resources/Tools/bin/aria2c` | GPL‑2.0‑or‑later | Fast/reliable large downloads (resume/segments) | Provide license text + **corresponding source** for the exact version shipped (as release asset or download). |
| `cabextract` (bundled tool) | `.../Tools/bin/cabextract` | GPL‑3.0‑or‑later | Extract `.cab` (used by UUP converter) | Provide license text + **corresponding source** for the exact version shipped. |
| `wimlib-imagex` (bundled tool) | `.../Tools/bin/wimlib-imagex` | GPL‑3.0‑or‑later | Split `install.wim` for FAT32; used by converter | Provide license text + **corresponding source** for the exact version shipped. |
| `chntpw` (bundled tool) | `.../Tools/bin/chntpw` | GPL‑2.0 (project also includes LGPL parts) | Registry edits used by UUP converter | Provide license text + **corresponding source** for the exact version shipped. |
| `xorriso` (bundled tool) | `.../Tools/bin/xorriso` + thin wrappers `.../Tools/bin/genisoimage` and `.../Tools/bin/mkisofs` (each `exec xorriso -as mkisofs "$@"`) | GPL‑3.0‑or‑later | ISO image creation used by UUP converter (replaces the historical `cdrtools/mkisofs` bundle). | Provide license text + **corresponding source** for the exact `xorriso` version shipped (release tarball + sha256 in `third-party-sources.tar.gz`). Wrappers are repository code, no extra obligations. |
| `mist` (bundled tool) | `.../Tools/bin/mist` | MIT | macOS installers/firmware download | Include MIT license text + attribution. |
| `ntfs-3g` (Windows-To-Go research only) | NOT yet bundled in shipping `.app`. Will be staged at `.../Tools/bin/ntfs-3g` and `.../Tools/bin/mkntfs` once the WTG track ships. Currently behind the `WTG_LOCAL` Swift compilation condition. | GPL‑2.0 | NTFS partition write support on macOS for Windows-To-Go (`mkntfs` + FUSE mount). Replaces no existing component. | Process boundary: invoked as a subprocess by Swift code (no linking). Will require: corresponding source tarball, license text in `THIRD_PARTY_NOTICES.txt`, evidence in `tool-versions.txt`. App will refuse to bundle/ship until that is in place. |
| FUSE-T / macFUSE (user prerequisite) | NOT bundled. App detects the runtime and asks the user to install. | LGPL/MPL (FUSE-T) / BSD-2 + macFUSE EULA (macFUSE) | Required by `ntfs-3g` to mount NTFS volumes. Shipping a kernel/system extension from a third party is not realistic for our distribution channel. | None for us — pointer in UI to user-driven install only. Documented in `Windows-To-Go-Research.md`. |

## CrystalFetch (Apache License 2.0)

The following files are copied from **CrystalFetch** by Turing Software, LLC:

- `Wist/ThirdParty/CrystalFetch/Downloader.swift`
- `Wist/ThirdParty/CrystalFetch/UUPDump/*.swift`

Source: [https://github.com/TuringSoftware/CrystalFetch](https://github.com/TuringSoftware/CrystalFetch)

License: [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). A copy of the Apache 2.0 license header appears at the top of each file.

`ProcessRunner.swift` and `DownloadISOViewModel.swift` are original to Wist but follow patterns described in CrystalFetch (UUPDump API usage, download queue, subprocess execution).

## UUP converter (`convert.sh`)

The file `Wist/ThirdParty/UUPConverter/convert.sh` is the official **uup-dump/converter** script ([source](https://git.uupdump.net/uup-dump/converter)).

- License: **MIT** (upstream `LICENSE`).
- Usage: bundled for UUP → ISO conversion.
- Invocation: Wist invokes it via `/bin/bash` with `PATH` that prefers **`Contents/Resources/Tools/bin`** (embedded CLI tools in release builds).

## Embedded CLI toolchain (optional in repo)

Release maintainers bundle the toolchain using `FluffyFlash/Scripts/bundle-mac-cli-tools.sh`.

- Destination in repo: `FluffyFlash/Fluffy Flash/Tools/bin/*` (then copied into `Wist.app/Contents/Resources/Tools/bin/*` by the build).
- Tools: `aria2c`, `cabextract`, `wimlib-imagex`, `chntpw`, `xorriso` (with `genisoimage`/`mkisofs` shell wrappers in front of `xorriso -as mkisofs`), `mist` (+ dependent `.dylib` gathered via **dylibbundler** where applicable).

### What “GPL compliance” means for our releases

If we ship a `.app` that contains GPL tools (aria2/cabextract/wimlib/chntpw), we must ship:

- a readable copy of the relevant license texts, and
- the **corresponding source** for the *exact versions shipped* (plus any patches we applied).

In practice, we do this by attaching a **`third-party-sources-<version>.tar.gz`** (and a `THIRD_PARTY_NOTICES.txt`) to every GitHub release.

## Version pinning / evidence

For every release, record:

- the output of `--version` (or equivalent) for each bundled tool,
- the Homebrew formula versions used to build/copy them,
- and the source tarball URLs + checksums.

This makes it possible to prove exactly what we shipped and to provide matching sources.

## mist-cli (MIT License)

The macOS mode uses the `mist` command from **mist-cli** (Nindi Gill) to list and download macOS installers / firmwares from official sources.

Source: [https://github.com/ninxsoft/mist-cli](https://github.com/ninxsoft/mist-cli)

License: **MIT License** (see upstream `LICENSE`).

## wimlib (runtime dependency)

USB creation calls **`wimlib-imagex`** from [wimlib](https://wimlib.net/) (GPL-3.0+). Users typically install via Homebrew (`brew install wimlib`). An optional copy may be placed in the app bundle under `Resources/Tools/`; it is not shipped in this repository by default.

Note: our release builds **do** bundle `wimlib-imagex` inside the `.app` (see “Summary” above). Once bundled, GPL compliance applies to distribution.

## WinDiskWriter (reference only)

[WinDiskWriter](https://github.com/TechUnRestricted/windiskwriter) (GPL-3.0) was used as a **conceptual** reference for bootable USB and WIM splitting; no source code was copied from that project.

## Windows-To-Go research (NTFS write path)

The Windows-To-Go P0 work uses `ntfs-3g` (GPL-2.0) and one of macFUSE / FUSE-T to format and mount NTFS volumes from macOS. Because this introduces a sensitive copyleft surface, the entire prototype is gated behind the Swift compilation condition `WTG_LOCAL` and **never** runs in shipping `.app` builds.

When we are ready to ship Windows-To-Go to end users we MUST:

1. Pin a specific `ntfs-3g` version (preferably the maintained fork at [tuxera/ntfs-3g](https://github.com/tuxera/ntfs-3g)) and document the source URL + sha256 in `Scripts/build_third_party_sources_bundle.sh`.
2. Add `ntfs-3g` and `mkntfs` to `THIRD_PARTY_NOTICES.txt` with their license texts.
3. Add `ntfs-3g` to the version-evidence step in `Scripts/build_third_party_sources_bundle.sh`.
4. Decide whether macFUSE or FUSE-T is the supported runtime; both must be **user prerequisites**, not bundled, because they install kernel / system extensions.
5. Re-run `legal-third-party-intake.mdc` to confirm the inventory before flipping the gate.

Until those steps are done, `ntfs-3g` MUST stay out of `Fluffy Flash/Tools/bin` and out of `bundle-mac-cli-tools.sh`.
