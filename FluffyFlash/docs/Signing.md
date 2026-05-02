# Signing, bundle identifier, and metadata

The app’s bundle identifier is **not hardcoded in Swift**. It is configured in the Xcode target settings (`PRODUCT_BUNDLE_IDENTIFIER`). You only need to set up signing once for your Apple ID / team.

## 1) What you set yourself

| Field | Where in Xcode | Notes |
|------|-----------------|------|
| **Team** | Target **Wist** → *Signing & Capabilities* → **Team** | Requires an Apple ID (free for personal signing) or a paid account for distribution. |
| **Bundle Identifier** (app) | Same screen → **Bundle Identifier** | Reverse-DNS, e.g. `com.yourdomain.Wist` (ASCII/latin only, no spaces). Must be **unique** in Apple’s ecosystem for public distribution. |
| **Test targets** | Targets **WistTests**, **WistUITests** → *Signing* | Separate bundle IDs, **different** from the main app. Current convention: suffixes `WistTests` and `WistUITests` with the same prefix (e.g. `com.yourdomain.WistTests`). |

After selecting a **Team** with **Automatically manage signing** enabled, Xcode will create/attach provisioning profiles automatically (this is enough for running locally on your Mac).

**Team ID** (a string like `A1B2C3D4E5`) can be found on Apple’s developer portal under *Membership details*, or it will appear in the project as `DEVELOPMENT_TEAM` after you save signing settings.

## 2) Versions and copyright (optional)

In the **Build Settings** of the **Wist** target:

| Key | Purpose |
|-----|---------|
| **Marketing Version** (`MARKETING_VERSION`) | User-facing version (e.g. `1.0`). |
| **Current Project Version** (`CURRENT_PROJECT_VERSION`) | Build number (integer, typically increments per TestFlight/App Store upload). |
| **Info.plist Values** → *Human Readable Copyright* | `INFOPLIST_KEY_NSHumanReadableCopyright`, e.g. `Copyright © 2026 Your Name`. |

## 3) Where these live in files

If you prefer editing files instead of the UI, see `FluffyFlash/Fluffy Flash.xcodeproj/project.pbxproj`:

- `PRODUCT_BUNDLE_IDENTIFIER` — for each target / configuration (Debug/Release);
- after signing is configured, Xcode adds **`DEVELOPMENT_TEAM`**;
- `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `INFOPLIST_KEY_*` — under *XCBuildConfiguration* sections.

`App-Info.plist` contains ATS only; the app’s main `Info.plist` is **generated** (`GENERATE_INFOPLIST_FILE = YES`), and the bundle identifier is injected from `PRODUCT_BUNDLE_IDENTIFIER`.

## 4) Distribution (beyond local “Run”)

- **Notarization and public distribution** typically require a **paid** Apple Developer Program membership and correct **Developer ID** / distribution signing.
- For **TestFlight** / **Mac App Store**, the Bundle ID must match a registered **App ID** in Apple’s developer portal.

## 5) Repos and other machines

Bundle identifiers and Teams are often **personal**. After you configure signing locally, `project.pbxproj` may gain a `DEVELOPMENT_TEAM` value. If you publish the repo publicly, keep neutral placeholders and document the setup steps (this file), or use a local non-committed override (e.g. an `.xcconfig` kept in `.gitignore`).

## 6) Privileged helper (`SMJobBless`)

The host app merges **`App-Info.plist`** into the bundle; it must contain **`SMPrivilegedExecutables`** — a **designated requirement** string that the embedded helper binary must satisfy. The helper’s **`PrivilegedHelperInfo.plist`** lists **`SMAuthorizedClients`** — requirements that the **host app** must satisfy.

Do **not** hardcode `certificate leaf[subject.CN] = "Apple Development: …"` — that breaks as soon as Xcode uses another Development certificate. Use **Team ID** instead:

- `certificate leaf[subject.OU] = "YOUR_TEAM_ID"` (same value as `DEVELOPMENT_TEAM` in the project).

If **`SMJobBless` fails** or **`/Library/PrivilegedHelperTools/com.fluffyflash.FluffyFlash.PrivilegedHelper` never appears**, re-check that both plist requirement strings use your current Team ID and rebuild *both* the app and the helper target.

