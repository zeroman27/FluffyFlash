# Changelog

Формат вдохновлён [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) и SemVer.

## [Unreleased]

- **Добавлено**:
  - —
- **Изменено**:
  - —
- **Исправлено**:
  - —

## [0.1.1] — 2026-05-07

- **Добавлено**:
  - **Settings → System status** card with on-demand diagnostics over bundled CLI tools, permissions, environment (macOS, arch, subprocess `PATH`, app bundle path, quarantine xattr), and free space on the cache volume. Per-row safe fixes (Open System Settings, Reveal in Finder, Copy `xattr -dr com.apple.quarantine` command). New `FluffySystemDoctor` + `SystemStatusReport`.
  - **Run diagnostics…** button in the Error log sheet (HomeView) that opens Settings → System status via `@Environment(\.openSettings)`.
  - Failure log now includes a `convert.sh log (tail)` section (last 50 streamed lines) and an `environment` section (subprocess `PATH`, bundled `Tools/bin` path, `hasEmbeddedUUPToolchain`, macOS version, architecture, app bundle path).
  - New documentation page `FluffyFlash/docs/Testing-clean-mac.md` with three local techniques to simulate a Mac without Homebrew.
- **Изменено**:
  - `BundledToolLocator` resolves bundled CLI tools when Xcode's `PBXFileSystemSynchronizedRootGroup` flattens `Tools/bin/*` into `Contents/Resources/`. Added testable `detectBundledBinDirectory(resourceURL:bundleURL:)`.
  - `HostToolPaths` always prepends the bundled directory to subprocess `PATH` (`composeSubprocessPATH`); added `subprocessPATHForDiagnostics()` for UI / failure logs.
  - `Scripts/bundle-mac-cli-tools.sh` now provides mkisofs/genisoimage wrappers compatible with bundled `xorriso -as mkisofs` (drops `--udf`/`-udf` and `--hide "*"`) so the produced ISO mounts with a visible ISO9660 tree on macOS.
  - `Scripts/bundle-mac-cli-tools.sh` adhoc-codesigns every bundled CLI binary and embedded `.dylib` to avoid Gatekeeper SIGKILL on clean Macs.
  - `ProcessRunner` accumulates a bounded stderr/stdout tail during streaming so failures include real output (not just exit code).
- **Исправлено**:
  - **ISO build on clean Apple Silicon Macs without Homebrew.** Fixed PATH discovery for bundled tools + improved diagnostics.
  - Writer install-image detection now tolerates ISO9660 case variations for `sources/install.wim|esd`.
  - macOS privileged helper preflight now prints mount/perms diagnostics and avoids `.atomic` for write probe; reinstalling helper updates these diagnostics.

## [0.1.0] — 2026-05-05

- Первый публичный релиз Fluffy Flash для macOS.
- Notarized + stapled DMG.

