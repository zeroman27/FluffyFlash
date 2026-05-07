# Testing on a "clean" Mac without a second laptop

The ISO pipeline is fragile in one specific way: it is easy to introduce a regression where the bundled CLI tools (`aria2c`, `wimlib-imagex`, `chntpw`, `cabextract`, `xorriso`, `mist`) are not added to the subprocess `PATH`. On a developer machine the bug stays hidden because Homebrew already provides them in `/opt/homebrew/bin`. On a freshly bought Mac without Homebrew, `convert.sh` immediately fails with:

```
aria2c does not seem to be installed.
```

To catch this *before* shipping a release, simulate a clean machine **without** carrying a build to a second laptop. Three options, in order of fidelity:

## 1. Run the built `.app` with an empty environment

Quickest, no extra software. The trick is `env -i`, which wipes the parent process' environment, plus an explicit minimal `PATH` that *does not* include `/opt/homebrew/bin`:

```bash
arch -arm64 env -i \
  HOME="$HOME" \
  TMPDIR="$TMPDIR" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  "FluffyFlash/build/Debug/FluffyFlash.app/Contents/MacOS/FluffyFlash"
```

When the bundled-tools fix is correct, the app launches and the ISO build works (the bundled `Tools/bin` directory is added to `PATH` via `HostToolPaths.composeSubprocessPATH(...)`). When it regresses, `convert.sh` prints the same "does not seem to be installed" line and `Settings → System status` flags the missing tools.

> Note: Xcode's normal Run scheme inherits the developer's `PATH`, so this kind of regression cannot be reproduced by hitting Run in Xcode. Use the command line.

## 2. A separate macOS user account

Slightly slower but more realistic. Create a fresh Standard user (System Settings → Users & Groups → Add User), log in, drag the built `.app` to that account's `~/Applications`, and double-click. The new account has no Homebrew in `PATH`, no Apple Developer signing identity in its keychain, and (importantly) no Full Disk Access for our app. This is the closest we get to a real customer install without a second machine.

To copy a Debug build over to the new user without rebuilding inside that account:

```bash
sudo cp -R \
  "$HOME/Library/Developer/Xcode/DerivedData/Fluffy_Flash-*/Build/Products/Debug/FluffyFlash.app" \
  "/Users/Shared/FluffyFlash.app"
```

…then in the new account: `cp -R /Users/Shared/FluffyFlash.app ~/Applications/`.

## 3. A virtual machine

The most realistic of the three. On Apple Silicon, [Tart](https://tart.run/) and [Virtualization.framework]'s `macosvm` from Apple let you run a stock macOS VM in minutes:

```bash
brew install cirruslabs/cli/tart
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest fluffy-test
tart run --no-graphics fluffy-test &
tart ip fluffy-test
ssh admin@$(tart ip fluffy-test)
```

Then `scp` the `.app` over and double-click it. This is the only option that catches issues with notarization, Gatekeeper, and quarantine xattr (because the VM's Safari really does add `com.apple.quarantine` on download). When verifying a release DMG, prefer this option.

## What to verify in each scenario

After launching the app, regardless of which technique you used:

1. Open **Settings → System status** and click **Run diagnostics**. Every section should be green or, for `Permissions`, in a documented "needs grant" state.
2. From Home, kick off a UUP→ISO build for any Windows 11 build. It should succeed.
3. If the ISO build fails, click **Copy error** in the Error log dialog. The pasted text should now contain a `--- convert.sh log (tail) ---` section with real shell output and an `--- environment ---` section showing the subprocess `PATH`. If `PATH` is missing the bundled `Tools/bin` directory, that is the regression — see `BundledToolLocator.swift` and `HostToolPaths.swift`.

## Related code

- `Fluffy Flash/BundledToolLocator.swift` — flat-vs-nested layout detection.
- `Fluffy Flash/HostToolPaths.swift` — `composeSubprocessPATH` + `subprocessPATHForDiagnostics`.
- `Fluffy Flash/ProcessRunner.swift` — stderr tail accumulator.
- `Fluffy Flash/EndToEndMediaPipeline.swift` — `buildFailureLog` / `environmentDiagnosticsBlock`.
- `Fluffy Flash/FluffySystemDoctor.swift` + `Fluffy Flash/SettingsView.swift` (`systemStatusCard`).
- `Scripts/bundle-mac-cli-tools.sh` — adhoc codesign of every bundled CLI binary and dylib.
