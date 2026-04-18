# Third-party code

## CrystalFetch (Apache License 2.0)

The following files are copied from **CrystalFetch** by Turing Software, LLC:

- `Wist/ThirdParty/CrystalFetch/Downloader.swift`
- `Wist/ThirdParty/CrystalFetch/UUPDump/*.swift`

Source: [https://github.com/TuringSoftware/CrystalFetch](https://github.com/TuringSoftware/CrystalFetch)

License: [Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0). A copy of the Apache 2.0 license header appears at the top of each file.

`ProcessRunner.swift` and `DownloadISOViewModel.swift` are original to Wist but follow patterns described in CrystalFetch (UUPDump API usage, download queue, subprocess execution).

## UUP converter (`convert.sh`)

The file `Wist/ThirdParty/UUPConverter/convert.sh` is the official **uup-dump/converter** script ([source](https://git.uupdump.net/uup-dump/converter)). It is bundled for UUP → ISO conversion; license terms follow that project (see upstream repository). Wist invokes it via `/bin/bash` with `PATH` that prefers **`Contents/Resources/Tools/bin`** (embedded CLI tools in release builds).

## Embedded CLI toolchain (optional in repo)

Release maintainers may copy `aria2c`, `cabextract`, `wimlib-imagex`, `chntpw`, and `mkisofs` (plus dependent libraries via **dylibbundler**) into `Wist/Tools/bin` using `Scripts/bundle-mac-cli-tools.sh`. Those programs are typically **GPL** or similar; shipping them requires license compliance (offer of source, attribution). End users then need no Homebrew install.

## wimlib (runtime dependency)

USB creation calls **`wimlib-imagex`** from [wimlib](https://wimlib.net/) (GPL-3.0+). Users typically install via Homebrew (`brew install wimlib`). An optional copy may be placed in the app bundle under `Resources/Tools/`; it is not shipped in this repository by default.

## WinDiskWriter (reference only)

[WinDiskWriter](https://github.com/TechUnRestricted/windiskwriter) (GPL-3.0) was used as a **conceptual** reference for bootable USB and WIM splitting; no source code was copied from that project.
