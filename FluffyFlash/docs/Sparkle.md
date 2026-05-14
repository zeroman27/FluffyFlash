# Sparkle (in-app updates)

Fluffy Flash embeds **[Sparkle 2](https://github.com/sparkle-project/Sparkle)** (Swift Package Manager). Sparkle downloads a signed update archive, verifies the **EdDSA** signature with the **public** key shipped inside the app, replaces the `.app`, and relaunches.

## What you must configure once

### 1) EdDSA keys (one keypair per app / org)

On a Mac with Sparkle’s release tools (from [Sparkle Releases](https://github.com/sparkle-project/Sparkle/releases), use the `bin/` tools from the tarball):

```bash
./bin/generate_keys
```

- Copy the printed **`SUPublicEDKey`** into `App-Info.plist` (key `SUPublicEDKey`, string value).
- Keep the **private** key in the **macOS Keychain** on the machine that signs releases, **or** export for CI (see `sign_update --help` and `--ed-key-file`). **Never commit** the private key to git. For GitHub Actions, store the exported secret in a **repository secret** and pass it to `sign_update` via stdin (`--ed-key-file -`).

### 2) Appcast URL

`App-Info.plist` must contain **`SUFeedURL`**: a stable **HTTPS** URL to your Sparkle **appcast XML** (often `raw.githubusercontent.com/.../appcast.xml` or a static site).

The template **`FluffyFlash/appcast.xml`** is tracked in this workspace. **Match `SUFeedURL` to where that file lives on your default branch**, for example:

| Layout on GitHub | Example `SUFeedURL` |
|------------------|---------------------|
| File at `FluffyFlash/appcast.xml` (monorepo-style) | `https://raw.githubusercontent.com/zeroman27/FluffyFlash/main/FluffyFlash/appcast.xml` |
| File at repo root `appcast.xml` | `https://raw.githubusercontent.com/zeroman27/FluffyFlash/main/appcast.xml` |

The value baked into `App-Info.plist` should be updated if your published tree differs.

### 3) Each release

1. Build and **notarize** the app as you do today.
2. Produce an update archive Sparkle can install — commonly a **ZIP of `Fluffy Flash.app`** (name must stay consistent or adjust the appcast).
3. Upload the ZIP to a public URL (e.g. GitHub Release asset).
4. Sign the archive:

   ```bash
   ./bin/sign_update /path/to/FluffyFlash-0.2.0.zip --ed-key-file /path/to/private.key
   ```

   (Or omit `--ed-key-file` if the private key is only in the Keychain on that Mac.)

5. Add a new `<item>` to `appcast.xml` with `enclosure` `url`, `sparkle:version` / `sparkle:shortVersionString`, `length`, and `sparkle:edSignature` from the tool output. Commit and push the updated appcast **after** the ZIP is reachable at the `url` you embedded.

See Sparkle’s own documentation for delta updates and advanced options.

## Helper tool

Sparkle updates the **main application**. The **privileged helper** must still be upgraded with your existing logic (version / hash checks and reinstall) after the new `.app` is in place.

## Legal / notices

Sparkle is **MIT** — see `THIRD_PARTY.md` and `THIRD_PARTY_NOTICES.txt`.
