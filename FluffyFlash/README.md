# Wist

macOS (SwiftUI) — downloads UUP via [UUPDump](https://uupdump.net) and writes a bootable Windows USB (FAT32 + `wimlib-imagex split`).

## Requirements

- Xcode 16+ / macOS 26+ (see the deployment target in the project).
- **USB writing:** `wimlib-imagex` in PATH or `Resources/Tools/wimlib-imagex` bundled with the app.

```bash
brew install wimlib
```

- **UUP → ISO and USB writing:** the built `.app` contains **bundled** CLI tools and `.dylib`s (`Contents/Resources/` and `Resources/lib`). End users **don’t need to install anything**.
- **Building in Xcode:** the **“Bundle Embedded CLI Tools”** build phase installs packages via Homebrew and copies binaries to `Wist/Tools/bin`, and `.dylib`s to **`EmbeddedCLI/lib`** (outside the sources folder, otherwise Xcode may auto-link them into the app). The **“Embed Tools dylibs”** phase copies the libraries into `Contents/lib` inside the `.app`. You need [Homebrew](https://brew.sh) and network access the first time packages are installed. Set `WIST_SKIP_TOOL_BUNDLE=1` to skip the phase and place files manually.

```bash
# Manual run of the same script (optional — Xcode runs it)
./Scripts/bundle-mac-cli-tools.sh
```

## Build

Open `Wist.xcodeproj`, select the **Wist** scheme, then Run.

### Signing and Bundle Identifier

To set up signing for **your Apple ID / team** and configure your **Bundle ID** (including test target identifiers), follow [docs/Signing.md](docs/Signing.md). The Bundle ID is not hardcoded in code — it’s configured in Xcode.

## Licenses

Wist source code is licensed under the **Apache License 2.0** (see `LICENSE`). Snippets from [CrystalFetch](https://github.com/TuringSoftware/CrystalFetch) are marked in file headers; see `THIRD_PARTY.md`.

## Security

- App Sandbox is disabled (we need `diskutil`, `hdiutil`, `rsync`, and external URLs).
- `NSAllowsArbitraryLoads` is enabled in `App-Info.plist` — some Microsoft download URLs are HTTP.
