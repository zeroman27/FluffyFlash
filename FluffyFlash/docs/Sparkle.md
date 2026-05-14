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

## Release checklist (first update users can install)

Do these **in order** so Sparkle never downloads a 404 or an unsigned file.

1. **Bump versions in Xcode** (example patch release):
   - `MARKETING_VERSION` (e.g. `0.1.2`) — `CFBundleShortVersionString`
   - `CURRENT_PROJECT_VERSION` (integer build, e.g. `3`) — `CFBundleVersion`  
   Both must be **newer** than what users already have, or Sparkle will not offer the update.

2. **Archive** the **FluffyFlash** scheme (**Product → Archive**), **Distribute** the resulting `.app` (Release), then **notarize** and staple (same flow you use for DMG; locally see `Scripts/codesign_and_notarize.sh` if you sign outside Xcode).

3. **Create the update ZIP** (Sparkle expects a zip that contains the `.app` at the top level):

   ```bash
   cd /path/to/folder/containing/FluffyFlash.app
   ditto -c -k --sequesterRsrc --keepParent FluffyFlash.app FluffyFlash-0.1.2.zip
   ```

   Use a **stable file name** per release; the appcast `url` must point exactly to this file.

4. **Create a GitHub Release** (tag `v0.1.2` or your convention) and **upload the ZIP** as a release asset **before** you point the appcast at it. Copy the **browser download URL** for the asset (or the `releases/download/...` URL).

5. **Sign the ZIP** with the **same** EdDSA private key that matches `SUPublicEDKey` in the app users already run:

   ```bash
   /path/to/Sparkle-2.9.1/bin/sign_update FluffyFlash-0.1.2.zip
   ```

   If the key is only in Keychain, omit `--ed-key-file`. Otherwise:

   ```bash
   ./bin/sign_update FluffyFlash-0.1.2.zip --ed-key-file /path/to/exported.key
   ```

   The tool prints **`sparkle:edSignature`** and **`length`** — copy them into the appcast.

6. **Append one `<item>`** to `FluffyFlash/appcast.xml` (newest items are usually **first** in the channel). Replace placeholders:

   ```xml
   <item>
     <title>Fluffy Flash 0.1.2</title>
     <link>https://github.com/zeroman27/FluffyFlash/releases</link>
     <sparkle:version>3</sparkle:version>
     <sparkle:shortVersionString>0.1.2</sparkle:shortVersionString>
     <pubDate>Wed, 14 May 2026 12:00:00 +0000</pubDate>
     <enclosure
       url="https://github.com/zeroman27/FluffyFlash/releases/download/v0.1.2/FluffyFlash-0.1.2.zip"
       sparkle:edSignature="PASTE_FROM_sign_update"
       length="PASTE_LENGTH_FROM_sign_update"
       type="application/octet-stream"
     />
   </item>
   ```

   `sparkle:version` = **`CFBundleVersion`** (integer string). `sparkle:shortVersionString` = **`CFBundleShortVersionString`**.

7. **Commit and push** `appcast.xml` only **after** the ZIP is downloadable at `url`.

8. **Smoke-test**: install the **previous** build on a VM or second Mac, run **Check for Updates…**, confirm Sparkle offers **0.1.2** and installs.

## Optional automation

Sparkle ships **`generate_appcast`** for maintaining the RSS file from a folder of update archives; you can adopt it later. Until then, one manual `<item>` per release is enough.

## Helper tool

Sparkle updates the **main application**. The **privileged helper** must still be upgraded with your existing logic (version / hash checks and reinstall) after the new `.app` is in place.

## Legal / notices

Sparkle is **MIT** — see `THIRD_PARTY.md` and `THIRD_PARTY_NOTICES.txt`.
