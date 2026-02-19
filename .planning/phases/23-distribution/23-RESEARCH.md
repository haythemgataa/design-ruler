# Phase 23: Distribution - Research

**Researched:** 2026-02-19
**Domain:** macOS code signing, notarization, DMG packaging, Sparkle EdDSA signing, GitHub Actions CI
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Classic drag-install DMG layout: app icon on left, Applications alias on right, arrow between them
- Custom branded background image with app name/logo
- Custom volume icon using the app icon
- Spacious window size (~600x400)
- User needs to set up an Apple Developer ID ($99/yr program) -- plan should document the required steps
- Signing credentials stored as GitHub Secrets (base64-encoded .p12 + password + Apple ID credentials)
- Hardened Runtime enabled with necessary entitlements for screen capture (CGEventTap, CGWindowListCreateImage)
- Entitlements handled by Claude -- user trusts the technical decisions here
- Appcast XML hosted via GitHub Releases (appcast points to release assets, no separate hosting)
- Auto-check for updates on launch (toggle already built in Phase 21 Settings)
- Stable channel only -- no beta/pre-release channel
- CI automatically generates/updates appcast.xml when publishing a release
- Tag format: `v1.0.0` (semantic versioning with 'v' prefix)
- Tag-driven versioning: CI extracts version from the git tag and injects into the build
- Draft release: CI creates a draft with DMG attached, user reviews and publishes manually
- CI also generates/updates Sparkle appcast.xml on release publish

### Claude's Discretion
- EdDSA signing key generation and management (private key in GitHub Secrets, public key in Info.plist)
- Universal binary vs Apple Silicon only (architecture choice)
- Specific Hardened Runtime entitlements needed
- DMG creation tooling (create-dmg, hdiutil, etc.)
- Appcast XML generation approach

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

---

## Summary

This phase implements the full distribution pipeline for the standalone Design Ruler app: code signing with Developer ID, notarization via `notarytool`, DMG packaging with `create-dmg`, Sparkle EdDSA update signing, and a GitHub Actions CI workflow triggered by version tags. The pipeline produces a notarized, stapled DMG that anyone can download from GitHub Releases without Gatekeeper warnings, plus a Sparkle appcast.xml for automatic updates.

The critical integration points are: (1) an entitlements file for Hardened Runtime that permits screen capture without breaking notarization, (2) EdDSA key generation for Sparkle update signing with the private key stored as a GitHub Secret and piped to `sign_update` via stdin (never written to disk in CI), (3) a two-workflow CI architecture where one workflow builds/signs/notarizes/packages on tag push (creating a draft release), and a second workflow generates/updates the appcast.xml when the draft is published, and (4) xcodegen project.yml updates to wire Release-configuration code signing settings.

**Primary recommendation:** Use `create-dmg` (Homebrew) for DMG creation, Apple's `notarytool` for notarization, Sparkle's `sign_update` tool (downloaded from GitHub Releases) for EdDSA signing, and build a Universal binary (arm64 + x86_64) to cover both Apple Silicon and Intel Macs. Ship with a minimal entitlements file -- no sandbox, no special hardened runtime exceptions needed for CGWindowListCreateImage (it uses TCC, not entitlements).

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| xcodebuild | Xcode 16.x (on macos-15 runner) | Archive + export with Developer ID signing | Apple's official build tool; required for code signing and Hardened Runtime |
| notarytool | Built-in (Xcode CLI) | Submit app to Apple's notarization service | Replaced `altool`; `xcrun notarytool submit --wait` is the current standard |
| stapler | Built-in (Xcode CLI) | Attach notarization ticket to DMG | `xcrun stapler staple` enables offline Gatekeeper validation |
| create-dmg | 1.2.x (via Homebrew) | Create branded DMG with drag-install layout | Shell script, no dependencies beyond macOS; supports background, icons, app-drop-link |
| Sparkle sign_update | 2.8.1 (from Sparkle release) | Generate EdDSA signature for DMG | Official Sparkle tool; outputs signature string for appcast.xml enclosure |
| Sparkle generate_keys | 2.8.1 (from Sparkle release) | One-time EdDSA key pair generation | Generates private key (for signing) + public key (for SUPublicEDKey in Info.plist) |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| xcodegen | 2.44.x (via Homebrew) | Regenerate .xcodeproj in CI before build | Already used in project; CI runs `xcodegen generate` before `xcodebuild` |
| security (macOS CLI) | Built-in | Create/unlock keychain, import .p12 certificate in CI | Every CI run; temporary keychain for code signing |
| gh (GitHub CLI) | Pre-installed on runner | Create draft releases, upload assets, update appcast | Interacting with GitHub Releases API in CI |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| create-dmg (CLI) | hdiutil + AppleScript | create-dmg wraps hdiutil with clean CLI flags; hdiutil alone requires manual DMG window scripting |
| Sparkle sign_update (from release tarball) | SPM artifacts path | SPM artifacts are in DerivedData at an unpredictable path; downloading Sparkle release tarball is simpler and deterministic in CI |
| Two workflows (tag + release publish) | Single workflow | Two workflows cleanly separate build (tag push) from appcast generation (release publish); single workflow would need complex conditional logic |
| Universal binary | Apple Silicon only | Universal adds ~10MB to binary size but supports Intel Macs until they're fully phased out; ARCHS_STANDARD on macos-15 runner produces arm64+x86_64 by default |

**Installation (CI):**
```bash
brew install create-dmg xcodegen
# Sparkle tools: downloaded from GitHub Release in CI step
```

---

## Architecture Patterns

### Recommended Project Structure (new/changed files)
```
porto/
├── .github/
│   └── workflows/
│       ├── build-release.yml       # Tag-push: build, sign, notarize, DMG, draft release
│       └── update-appcast.yml      # Release-publish: generate appcast.xml, attach to release
├── App/
│   ├── project.yml                 # UPDATED: Release signing settings, entitlements
│   ├── Sources/
│   │   └── DesignRuler.entitlements  # NEW: minimal entitlements file
│   └── ExportOptions.plist         # NEW: developer-id export method
├── scripts/
│   ├── generate-appcast.sh         # NEW: appcast XML generation script
│   └── dmg-background.png          # NEW: branded DMG background image (600x400 @2x)
```

### Pattern 1: Two-Workflow CI Architecture

**What:** Separate the build pipeline from appcast generation using two GitHub Actions workflows triggered by different events.

**When to use:** Always -- this cleanly separates concerns and allows the user to review the draft release before publishing.

**Workflow 1: `build-release.yml`** (triggers on tag push `v*`)
```
1. Checkout code
2. Install tools (xcodegen, create-dmg)
3. Import signing certificate into temporary keychain
4. Run xcodegen to generate .xcodeproj
5. Inject version from tag into build settings
6. xcodebuild archive (Release config, Universal binary)
7. xcodebuild -exportArchive (Developer ID method)
8. Sign DMG with Sparkle EdDSA key (sign_update)
9. Create DMG with create-dmg
10. Notarize DMG with notarytool
11. Staple notarization ticket
12. Create draft GitHub Release with DMG attached
```

**Workflow 2: `update-appcast.yml`** (triggers on release published)
```
1. Download DMG from release assets
2. Generate EdDSA signature (sign_update)
3. Extract version, build number, file size
4. Render appcast.xml from template
5. Upload appcast.xml to the release
```

### Pattern 2: Keychain Setup in CI

**What:** Create a temporary keychain, import the Developer ID .p12 certificate, configure it for non-interactive use, and clean up after build.

**Example:**
```bash
# Decode certificate
echo -n "$DEVELOPER_ID_CERT_BASE64" | base64 --decode -o $RUNNER_TEMP/certificate.p12

# Create and configure keychain
KEYCHAIN_PATH=$RUNNER_TEMP/signing.keychain-db
security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

# Import certificate
security import $RUNNER_TEMP/certificate.p12 \
  -P "$DEVELOPER_ID_CERT_PASSWORD" \
  -A -t cert -f pkcs12 \
  -k $KEYCHAIN_PATH

# Allow codesign access without prompt
security set-key-partition-list -S apple-tool:,apple: \
  -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

# Add to search list
security list-keychain -d user -s $KEYCHAIN_PATH
```

**Cleanup (always runs):**
```bash
security delete-keychain $RUNNER_TEMP/signing.keychain-db
```

### Pattern 3: Version Injection from Git Tag

**What:** Extract version number from the git tag and pass it to xcodebuild as build settings overrides.

**Example:**
```bash
# Extract version from tag (strip 'v' prefix)
VERSION=${GITHUB_REF_NAME#v}          # "1.0.0" from "v1.0.0"
BUILD_NUMBER=$(git rev-list --count HEAD)  # monotonic build number

xcodebuild archive \
  -project "Design Ruler.xcodeproj" \
  -scheme "Design Ruler" \
  -configuration Release \
  -archivePath "$RUNNER_TEMP/DesignRuler.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID"
```

### Pattern 4: EdDSA Signing via stdin (Never Write Key to Disk)

**What:** Pipe the Sparkle private key from a GitHub Secret directly to `sign_update` via stdin, never writing it to disk in CI.

**Example:**
```bash
# Download Sparkle tools from release
curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz" \
  | tar xJ --include='*/bin/sign_update' --include='*/bin/generate_appcast'

# Sign the DMG -- pipe private key via stdin
SIGNATURE=$(echo "$SPARKLE_PRIVATE_KEY" | ./bin/sign_update --ed-key-file - "DesignRuler-$VERSION.dmg")
# Output: sparkle:edSignature="..." length="..."
```

### Pattern 5: ExportOptions.plist for Developer ID

**What:** Tell `xcodebuild -exportArchive` to use Developer ID signing method (not App Store).

**Example `App/ExportOptions.plist`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

### Pattern 6: create-dmg Branded Layout

**What:** Use create-dmg CLI to produce the classic drag-install DMG with branded background.

**Example:**
```bash
create-dmg \
  --volname "Design Ruler" \
  --volicon "App/Sources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
  --background "scripts/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "Design Ruler.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "Design Ruler.app" \
  "Design-Ruler-$VERSION.dmg" \
  "$EXPORT_PATH/"
```

### Anti-Patterns to Avoid

- **Writing EdDSA private key to disk in CI:** Use `echo "$KEY" | sign_update --ed-key-file -` to pipe via stdin. Never write to a file that could be accidentally committed or cached.
- **Notarizing the .app instead of the .dmg:** Notarize the final DMG (not the .app inside it). The stapled ticket must be on the distribution artifact users download.
- **Forgetting `--wait` on notarytool submit:** Without `--wait`, the workflow continues before notarization completes. The subsequent `stapler staple` will fail because there is no ticket yet.
- **Using `altool` instead of `notarytool`:** `altool` is deprecated. Use `xcrun notarytool submit` with `--wait`.
- **Hardcoding version in project.yml:** The version should come from the git tag via xcodebuild overrides (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), not from hardcoded values in project.yml.
- **Building Debug configuration for release:** Always use `-configuration Release` for distribution builds. Debug builds have `CODE_SIGN_IDENTITY="-"` (ad-hoc) which cannot be notarized.
- **Skipping xcodegen in CI:** The .xcodeproj is generated from project.yml. CI must run `xcodegen generate` before `xcodebuild` to ensure the project is up to date.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DMG creation | hdiutil + AppleScript for window layout | create-dmg | Background images, icon positioning, and Applications alias require complex AppleScript; create-dmg handles it in one command |
| Notarization | Custom polling loop for notarization status | `xcrun notarytool submit --wait` | `--wait` blocks until notarization completes or fails; handles retries and timeout internally |
| EdDSA signing | OpenSSL ed25519 signing | Sparkle's `sign_update` tool | Sparkle uses a specific signature format that `sign_update` produces; OpenSSL output is incompatible |
| Appcast XML | Custom XML builder | Template + `sign_update` output | The appcast format is simple RSS; a shell script template with variable substitution is sufficient |
| Certificate management | Manual codesign commands | xcodebuild archive + exportArchive | xcodebuild handles the full signing chain (app binary + frameworks + plugins) automatically |
| Version injection | Sed/awk on Info.plist | xcodebuild `MARKETING_VERSION` override | Build setting overrides are the standard Xcode mechanism; modifying plist files is fragile |

**Key insight:** The distribution pipeline is a chain of well-documented Apple tools (`xcodebuild`, `notarytool`, `stapler`) plus two community tools (`create-dmg`, Sparkle's `sign_update`). Each tool does one thing. The CI workflow is the orchestrator that chains them together.

---

## Common Pitfalls

### Pitfall 1: Hardened Runtime Entitlements Confusion
**What goes wrong:** Developers assume CGWindowListCreateImage or CGEventTap require specific Hardened Runtime entitlements and add unnecessary exceptions that could raise notarization flags.
**Why it happens:** Confusion between Hardened Runtime entitlements (which control code integrity) and TCC permissions (which control resource access). Screen recording permission is a TCC permission granted at runtime by the user, not a code-signing entitlement.
**How to avoid:** Use a minimal entitlements file with zero Hardened Runtime exceptions. CGWindowListCreateImage and CGEventTap are controlled by TCC (the system prompts the user for Screen Recording permission at runtime). The Hardened Runtime just needs to be enabled -- no special exceptions are needed for screen capture tools. The six Hardened Runtime exceptions (allow-jit, allow-unsigned-executable-memory, disable-library-validation, etc.) are for code execution modifications, not resource access.
**Warning signs:** Notarization warnings about "unnecessary entitlements" or unexpected entitlement flags.

### Pitfall 2: Notarizing .app Instead of .dmg
**What goes wrong:** The notarization ticket is attached to the .app inside the DMG, but the DMG itself is not stapled. Users still get Gatekeeper warnings because the download is a .dmg, not a .app.
**Why it happens:** Misunderstanding of what gets stapled.
**How to avoid:** Submit the final .dmg to `notarytool`, then `stapler staple` the .dmg. The notary service processes the .dmg and all its contents (including the .app inside). Stapling attaches the ticket to the .dmg itself.
**Warning signs:** Users report "unidentified developer" or "app is damaged" warnings despite successful notarization logs.

### Pitfall 3: EdDSA Public Key Not in Built App Bundle
**What goes wrong:** Sparkle update checks fail with signature verification errors even though the DMG was signed correctly.
**Why it happens:** The `SUPublicEDKey` placeholder in Info.plist was never replaced with the real public key, or the xcodegen/build process doesn't inject the key into the final bundle.
**How to avoid:** Replace `PLACEHOLDER_EDDSA_PUBLIC_KEY` in both project.yml's info.properties and Info.plist with the actual base64 public key from `generate_keys`. Verify after build: `defaults read "path/to/Design Ruler.app/Contents/Info.plist" SUPublicEDKey`.
**Warning signs:** Sparkle shows "Update has invalid signature" errors; `generate_appcast` warnings about key mismatch.

### Pitfall 4: SUFeedURL Points to Wrong Location
**What goes wrong:** Sparkle checks for updates but gets 404 errors because the appcast.xml URL is wrong.
**Why it happens:** The current placeholder URL `https://github.com/haythem/design-ruler/releases/latest/download/appcast.xml` may not match the actual repository name or asset name.
**How to avoid:** The SUFeedURL must point to the raw appcast.xml file as a GitHub Release asset. The URL format for a release asset is: `https://github.com/{owner}/{repo}/releases/latest/download/appcast.xml`. Verify the exact repository URL before setting this value.
**Warning signs:** Sparkle shows "An error occurred" or "Can't check for updates" messages.

### Pitfall 5: Git Tag Does Not Match Expected Format
**What goes wrong:** CI workflow doesn't trigger, or version extraction produces empty/malformed strings.
**Why it happens:** Tag created without the `v` prefix, or with extra characters.
**How to avoid:** Document the exact tag creation command: `git tag v1.0.0 && git push origin v1.0.0`. The workflow trigger pattern `on: push: tags: ['v*']` matches any tag starting with `v`. Version extraction: `${GITHUB_REF_NAME#v}` strips the `v` prefix.
**Warning signs:** No CI run appears after pushing a tag; or the DMG filename contains an empty version string.

### Pitfall 6: Signing Identity Name Mismatch
**What goes wrong:** xcodebuild fails with "No signing certificate ... found" even though the certificate was imported.
**Why it happens:** The `CODE_SIGN_IDENTITY` string must exactly match the certificate's Common Name. For Developer ID, it is `"Developer ID Application: Your Name (TEAM_ID)"` -- but using just `"Developer ID Application"` works as a prefix match if only one Developer ID certificate is in the keychain.
**How to avoid:** Use `CODE_SIGN_IDENTITY="Developer ID Application"` in xcodebuild -- it matches by prefix. The full name is only needed when multiple Developer ID certificates exist in the keychain. In CI with a dedicated temporary keychain, there is only one.
**Warning signs:** `errSecInternalComponent` or "no identity found" errors during archive.

### Pitfall 7: Sparkle Framework Not Re-Signed
**What goes wrong:** Notarization rejects the app because the Sparkle.framework inside the app bundle has an invalid or missing signature.
**Why it happens:** When Xcode exports with Developer ID, it should re-sign all embedded frameworks. But if the export process is misconfigured or frameworks are copied manually, they may retain their original (development) signatures.
**How to avoid:** Use `xcodebuild -exportArchive` with the ExportOptions.plist -- it automatically re-signs all embedded frameworks and XPC services with the Developer ID certificate. Never manually copy frameworks into the app bundle after export.
**Warning signs:** Notarization log shows "invalid signature" for a framework path inside the .app bundle.

### Pitfall 8: macos-15 Runner is ARM64 Only
**What goes wrong:** Universal binary build fails or produces ARM64-only binary when `ONLY_ACTIVE_ARCH` is YES.
**Why it happens:** GitHub's macos-15 runners are Apple Silicon (ARM64). With `ONLY_ACTIVE_ARCH=YES` (Debug default), xcodebuild only builds for the host architecture.
**How to avoid:** Set `ONLY_ACTIVE_ARCH=NO` explicitly for Release builds (or ensure it's the default in Release config, which it normally is). Use `ARCHS="arm64 x86_64"` or `ARCHS="$(ARCHS_STANDARD)"` which on Xcode 16 includes both architectures. Verify with `lipo -archs "Design Ruler.app/Contents/MacOS/Design Ruler"` after export.
**Warning signs:** `lipo` shows only `arm64` instead of `arm64 x86_64`.

---

## Code Examples

### Complete xcodebuild Archive + Export Sequence
```bash
# Source: Apple developer documentation + verified CI patterns

# Archive
xcodebuild archive \
  -project "Design Ruler.xcodeproj" \
  -scheme "Design Ruler" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$RUNNER_TEMP/DesignRuler.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

# Export
xcodebuild -exportArchive \
  -archivePath "$RUNNER_TEMP/DesignRuler.xcarchive" \
  -exportPath "$RUNNER_TEMP/export" \
  -exportOptionsPlist "App/ExportOptions.plist"
```

### Notarization + Stapling Sequence
```bash
# Source: Apple notarytool documentation

# Store credentials (once per workflow run)
xcrun notarytool store-credentials "notary-profile" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$NOTARY_PASSWORD"

# Submit DMG and wait for result
xcrun notarytool submit "Design-Ruler-$VERSION.dmg" \
  --keychain-profile "notary-profile" \
  --wait

# Staple the ticket to the DMG
xcrun stapler staple "Design-Ruler-$VERSION.dmg"
```

### Sparkle EdDSA Key Generation (One-Time, Local)
```bash
# Source: Sparkle documentation

# Download Sparkle release
curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz" \
  -o Sparkle.tar.xz
tar xf Sparkle.tar.xz

# Generate key pair (saves private key to Keychain, prints public key)
./bin/generate_keys
# Output: "Your public key (SUPublicEDKey) is: pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ="

# Export private key to file (for storing in GitHub Secret)
./bin/generate_keys -x private_key_file
# Store contents of private_key_file as SPARKLE_PRIVATE_KEY GitHub Secret
# Then delete the file: rm private_key_file
```

### Sparkle sign_update in CI
```bash
# Source: Sparkle CI documentation + GitHub discussions

# Pipe private key from environment -- never write to disk
SIGN_OUTPUT=$(echo "$SPARKLE_PRIVATE_KEY" | ./bin/sign_update --ed-key-file - "Design-Ruler-$VERSION.dmg")
# SIGN_OUTPUT contains: sparkle:edSignature="abc123..." length="12345678"

# Parse signature and length
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
```

### Appcast XML Template
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Design Ruler Updates</title>
    <link>https://github.com/OWNER/REPO</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version VERSION</title>
      <pubDate>PUB_DATE</pubDate>
      <sparkle:version>BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/OWNER/REPO/releases/download/vVERSION/Design-Ruler-VERSION.dmg"
        sparkle:edSignature="ED_SIGNATURE"
        length="FILE_LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

### Entitlements File (Minimal)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

No Hardened Runtime exceptions are needed. CGWindowListCreateImage and CGEventTap access is controlled by TCC (runtime permission prompt), not by code-signing entitlements. The empty entitlements file with Hardened Runtime enabled is the cleanest configuration for notarization.

### xcodegen project.yml Updates (Release Config)
```yaml
# Add to targets."Design Ruler".settings:
settings:
  base:
    PRODUCT_BUNDLE_IDENTIFIER: cv.haythem.designruler
    PRODUCT_NAME: "Design Ruler"
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ARCHS: "$(ARCHS_STANDARD)"
    ENABLE_HARDENED_RUNTIME: YES
    CODE_SIGN_ENTITLEMENTS: Sources/DesignRuler.entitlements
  configs:
    Debug:
      CODE_SIGN_IDENTITY: "-"
      CODE_SIGN_STYLE: Automatic
    Release:
      CODE_SIGN_IDENTITY: "Developer ID Application"
      CODE_SIGN_STYLE: Manual
      DEVELOPMENT_TEAM: "$(DEVELOPMENT_TEAM)"
```

### Required GitHub Secrets
```
DEVELOPER_ID_CERT_BASE64     - Base64-encoded Developer ID Application .p12 certificate
DEVELOPER_ID_CERT_PASSWORD   - Password for the .p12 file
KEYCHAIN_PASSWORD            - Random password for temporary CI keychain
APPLE_ID                     - Apple Developer account email
NOTARY_PASSWORD              - App-specific password (from appleid.apple.com)
TEAM_ID                      - Apple Developer Team ID (from Membership page)
SPARKLE_PRIVATE_KEY          - EdDSA private key (base64 string from generate_keys -x)
```

---

## Discretion Recommendations

### Universal Binary: Build arm64 + x86_64
**Recommendation:** Universal binary.
**Rationale:** GitHub's macos-15 runners support building Universal binaries via `ARCHS="$(ARCHS_STANDARD)"` which includes both arm64 and x86_64. The size increase is marginal (~10MB for a utility app). Intel Macs are still in use, and providing Universal support requires zero extra CI complexity -- it is the default behavior of Xcode's Release configuration. Apple Silicon-only would exclude a non-trivial user base for no benefit.

### Hardened Runtime Entitlements: Empty File
**Recommendation:** Empty entitlements dict (no exceptions).
**Rationale:** The six Hardened Runtime exceptions (allow-jit, allow-unsigned-executable-memory, disable-library-validation, disable-executable-page-protection, allow-dyld-environment-variables, debugger) control code execution restrictions, not resource access. CGWindowListCreateImage and CGEventTap are governed by TCC (Transparency, Consent, and Control) -- the system prompts the user for Screen Recording permission at runtime. No entitlement grants or bypasses this. An empty entitlements file with `ENABLE_HARDENED_RUNTIME=YES` is the cleanest path to notarization.

### DMG Creation: create-dmg via Homebrew
**Recommendation:** `create-dmg` (the `create-dmg/create-dmg` project, not sindresorhus/create-dmg).
**Rationale:** `create-dmg` is a pure shell script requiring only a standard macOS installation. It supports all the required features: `--background`, `--window-size`, `--icon`, `--app-drop-link`, `--volname`, `--volicon`, `--hide-extension`. Available via `brew install create-dmg`. The sindresorhus variant auto-detects many settings but provides less control over the exact layout.

### EdDSA Key Management: Private Key in GitHub Secret, Public Key in Info.plist
**Recommendation:** Generate keys locally once with Sparkle's `generate_keys` tool. Export private key with `generate_keys -x`, store the file's content as `SPARKLE_PRIVATE_KEY` GitHub Secret. Copy the printed public key into both `project.yml` (info.properties.SUPublicEDKey) and `Info.plist`. In CI, pipe the secret to `sign_update --ed-key-file -` (stdin, never disk).

### Appcast XML Generation: Shell Script Template
**Recommendation:** A simple shell script that reads version/signature/size and renders the appcast XML using heredoc or sed substitution. No need for `generate_appcast` in CI.
**Rationale:** `generate_appcast` is designed to process a folder of archives and build delta updates. For a single-release pipeline with no delta updates (stable channel only), a template-based approach is simpler and more transparent. The script outputs a valid Sparkle appcast XML with one `<item>` per release. For future releases, the script downloads the existing appcast.xml from the latest release and prepends the new item.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `xcrun altool --notarize-app` | `xcrun notarytool submit --wait` | Xcode 14 (2022) | altool deprecated; notarytool is faster and synchronous with --wait |
| DSA signatures (Sparkle 1) | EdDSA/ed25519 (Sparkle 2) | Sparkle 2.0 (2022) | Stronger signatures, smaller keys, faster verification |
| macos-12/13 Intel runners | macos-15 ARM64 runners | April 2025 | Default GitHub runners are now Apple Silicon; Intel runners deprecated by fall 2027 |
| `-s` flag for EdDSA key | `--ed-key-file` stdin pipe | Sparkle 2.x | `-s` (passing key as CLI argument) deprecated; `--ed-key-file -` for stdin is current |
| `CODE_SIGN_STYLE: Automatic` for release | `Manual` with explicit identity | Always best practice for CI | Automatic signing requires Xcode to resolve identity; Manual is deterministic in CI |

**Deprecated/outdated:**
- `xcrun altool --notarize-app`: Deprecated since Xcode 14. Use `notarytool`.
- Sparkle's `-s` flag for sign_update/generate_appcast: Deprecated. Use `--ed-key-file`.
- `macos-12` GitHub Actions runner: Being retired. Use `macos-15`.

---

## Open Questions

1. **Exact GitHub repository URL for release assets**
   - What we know: The current SUFeedURL placeholder is `https://github.com/haythem/design-ruler/releases/latest/download/appcast.xml`. The actual repo may have a different name.
   - What's unclear: The exact `{owner}/{repo}` path for the GitHub repository where releases will be published.
   - Recommendation: The plan should use a placeholder (`OWNER/REPO`) and include a step where the user confirms the repository URL before setting SUFeedURL. This is a configuration step, not a code change.

2. **DMG background image creation**
   - What we know: The user wants a custom branded background with app name/logo. The DMG window is ~600x400.
   - What's unclear: Who creates the background image -- is this a design task or should the plan include generating a simple programmatic background?
   - Recommendation: Create a simple branded background programmatically (white/light gray background with app name centered and a subtle arrow pointing from app icon to Applications). This can be a PNG generated with a simple script or a manually created asset. The plan should include creating this asset.

3. **Sparkle updater re-enable (`startingUpdater: true`)**
   - What we know: Phase 21 set `startingUpdater: false` to defer EdDSA key validation. This phase needs to re-enable it.
   - What's unclear: Whether simply changing to `startingUpdater: true` is sufficient, or whether additional configuration is needed.
   - Recommendation: Change to `startingUpdater: true` after setting real SUPublicEDKey. This should be the last step -- after keys are generated and Info.plist is updated. Verify by building and launching the app locally.

---

## Sources

### Primary (HIGH confidence)
- [Apple: Installing certificates on macOS runners](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development) -- Complete keychain setup workflow for GitHub Actions
- [Apple: Configuring the Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) -- Six runtime exceptions listed; confirmed no screen capture entitlement exists
- [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/) -- Appcast XML format, sign_update usage, enclosure attributes, minimumSystemVersion
- [Sparkle: Documentation index](https://sparkle-project.org/documentation/) -- EdDSA key generation, generate_keys tool, SUPublicEDKey setup
- [create-dmg GitHub](https://github.com/create-dmg/create-dmg) -- Full CLI options verified: --background, --window-size, --icon, --app-drop-link, --volname, --volicon
- [GitHub Actions runner-images macos-15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) -- macos-15 runner is ARM64, Xcode 16.x, Homebrew available

### Secondary (MEDIUM confidence)
- [Federico Terzi: Automatic Code-signing and Notarization](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/) -- Complete signing + notarization workflow with GitHub Secrets setup
- [defn.io: Distributing Mac Apps with GitHub Actions](https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/) -- End-to-end workflow including create-dmg, notarytool, ExportOptions.plist
- [Sparkle Discussion #2308: GitHub Actions workflow](https://github.com/sparkle-project/Sparkle/discussions/2308) -- EdDSA key piping via `--ed-key-file -`, CI recommendations
- [Sparkle Discussion #2597: DMG signing](https://github.com/sparkle-project/Sparkle/discussions/2597) -- Confirmed DMG and ZIP signing are identical; SUPublicEDKey must be in built app bundle
- [Eclectic Light: Notarization and Hardened Runtime](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/) -- Six runtime exception entitlements enumerated
- [GitHub Actions macos-latest migration](https://github.com/actions/runner-images/issues/12520) -- macos-latest = macos-15 from August 2025; ARM64 architecture confirmed
- [VibeTunnel: Sparkle Keys](https://docs.vibetunnel.sh/mac/docs/sparkle-keys) -- Private key format (single base64 line), CI pipeline integration pattern

### Tertiary (LOW confidence)
- Hardened Runtime entitlements for screen capture: No authoritative source explicitly states "no entitlement is needed for CGWindowListCreateImage with Hardened Runtime." This is inferred from (a) the six listed Hardened Runtime exceptions none mentioning screen capture, (b) Apple's documentation stating screen recording is a TCC permission, and (c) the absence of any `com.apple.security.screen-capture` or similar entitlement in public documentation. HIGH confidence in the conclusion but LOW confidence in finding a single definitive source.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools (xcodebuild, notarytool, create-dmg, Sparkle sign_update) verified against official documentation and established CI patterns
- Architecture: HIGH -- Two-workflow pattern is established; keychain setup verified against GitHub's official docs; version injection via xcodebuild overrides is standard
- Pitfalls: HIGH -- Notarization, signing, and Sparkle integration pitfalls well-documented across multiple sources; entitlements analysis verified against Apple's Hardened Runtime documentation
- Discretion recommendations: HIGH -- Universal binary supported by default on macos-15 runners; empty entitlements verified against Hardened Runtime exception list; create-dmg capabilities verified from README

**Research date:** 2026-02-19
**Valid until:** 2026-05-19 (stable tooling; Sparkle and notarytool APIs stable; GitHub runner images update but patterns remain)
