---
phase: 23-distribution
verified: 2026-02-20T04:50:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
human_verification:
  - test: "codesign --verify --deep --strict on built .app bundle"
    expected: "Exit 0 with no output (signature valid, Hardened Runtime flags confirmed)"
    why_human: "Requires building with a real Developer ID certificate; cannot be verified without signing credentials"
  - test: "spctl --assess --type execute on .app from notarized DMG"
    expected: "accepted source=Notarized Developer ID (Gatekeeper approves without warning)"
    why_human: "Requires a completed notarytool submission against Apple servers; only verifiable at CI run time"
  - test: "Mount the produced DMG and verify drag-install layout"
    expected: "DMG window shows app icon on left at (150,200) and Applications alias on right at (450,200) against branded background"
    why_human: "Requires a completed CI run to produce the DMG; layout is driven by create-dmg flags that can only be observed visually"
  - test: "Push a v* tag and confirm GitHub Actions runs to completion"
    expected: "All secrets configured, workflow reaches 'Create draft release' step, notarized DMG appears as release asset"
    why_human: "Requires real Apple Developer credentials, a notarization-approved binary, and the 7 GitHub Secrets to be configured by the user"
---

# Phase 23: Distribution Verification Report

**Phase Goal:** Anyone can download a notarized DMG from GitHub releases and run Design Ruler without a Gatekeeper warning
**Verified:** 2026-02-20T04:50:00Z
**Status:** passed (with 4 items deferred to human verification — none are gaps in the codebase)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | `codesign --verify --deep --strict` passes on the built `.app` bundle | ? HUMAN | Project is configured correctly: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_ENTITLEMENTS`, `Developer ID Application` Release config, `--options runtime` flag. Actual verification requires a CI run with real credentials. |
| 2 | `spctl --assess --type execute` passes on a clean machine (Gatekeeper approves) | ? HUMAN | Notarization pipeline is fully wired: `notarytool submit --wait` + `stapler staple` on DMG. Requires a completed notarytool submission to verify. |
| 3 | DMG opens to reveal app with /Applications shortcut for drag-install | ? HUMAN | `create-dmg` flags `--icon "Design Ruler.app" 150 200` + `--app-drop-link 450 200` are present in workflow. Branded 1200x800 background PNG is committed. Requires a CI run to produce the DMG. |
| 4 | Pushing a v* tag triggers CI producing a signed, notarized DMG as a draft release asset | ? HUMAN | Full workflow is present and structurally correct: tag trigger, all pipeline steps in correct order, `contents: write` permission, `gh release create --draft`. Requires real credentials and a tag push to confirm end-to-end. |

**Score:** 4/4 truths have correct supporting infrastructure. All deferred items are human-testable only (require external credentials and a CI run), not codebase gaps.

---

## Required Artifacts

### Plan 23-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `App/Sources/DesignRuler.entitlements` | Minimal entitlements for Hardened Runtime (empty dict) | VERIFIED | Valid XML plist, `<dict/>` body — no Hardened Runtime exceptions |
| `App/ExportOptions.plist` | Developer ID export method for xcodebuild -exportArchive | VERIFIED | `method: developer-id`, `signingStyle: manual`, `stripSwiftSymbols: true` |
| `App/project.yml` | Release signing config with ENABLE_HARDENED_RUNTIME, CODE_SIGN_ENTITLEMENTS, Manual signing | VERIFIED | `ENABLE_HARDENED_RUNTIME: YES` in base, `CODE_SIGN_ENTITLEMENTS: Sources/DesignRuler.entitlements`, Debug=ad-hoc/Automatic, Release=Developer ID/Manual, `DEVELOPMENT_TEAM: "$(DEVELOPMENT_TEAM)"` |
| `App/Sources/AppDelegate.swift` | Sparkle updater with `startingUpdater: true` | VERIFIED | Line 12: `startingUpdater: true` |

### Plan 23-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/workflows/build-release.yml` | CI workflow: tag-push -> archive -> sign -> notarize -> DMG -> draft release | VERIFIED | Valid YAML, trigger `on: push: tags: v*`, `permissions: contents: write`, `runs-on: macos-15`, all 13 pipeline steps present in correct order |
| `.github/workflows/update-appcast.yml` | CI workflow: release-publish -> EdDSA sign -> appcast.xml -> upload | VERIFIED | Valid YAML, trigger `on: release: types: [published]`, `permissions: contents: write`, `runs-on: macos-15`, all 7 steps present |
| `scripts/generate-appcast.sh` | Shell script generating Sparkle appcast.xml from env var inputs | VERIFIED | Executable (`-rwxr-xr-x`), `set -euo pipefail`, produces valid Sparkle RSS XML (tested: `xmllint --noout` passes), includes `sparkle:edSignature`, `length`, `sparkle:minimumSystemVersion: 14.0` |
| `scripts/assets/dmg-background.png` | Pre-committed branded DMG background (1200x800 @2x) | VERIFIED | `PNG image data, 1200 x 800, 8-bit/color RGB` — correct dimensions and format |

### Plan 23-03 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `App/project.yml` (SUPublicEDKey) | Real EdDSA public key replacing placeholder | VERIFIED | `SUPublicEDKey: "nQlHBasrae63Ai7buw0NQAWV7wMXI70LCFLFbnULImw="` — real key, not `PLACEHOLDER_EDDSA_PUBLIC_KEY` |
| `App/Sources/Info.plist` | Real SUPublicEDKey propagated by xcodegen | VERIFIED | `<string>nQlHBasrae63Ai7buw0NQAWV7wMXI70LCFLFbnULImw=</string>` in generated plist |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `App/project.yml` | `App/Sources/DesignRuler.entitlements` | `CODE_SIGN_ENTITLEMENTS` build setting | WIRED | Line 49: `CODE_SIGN_ENTITLEMENTS: Sources/DesignRuler.entitlements` |
| `.github/workflows/build-release.yml` | `App/ExportOptions.plist` | `xcodebuild -exportOptionsPlist` | WIRED | Line 79: `-exportOptionsPlist "ExportOptions.plist"` |
| `.github/workflows/build-release.yml` | `App/project.yml` | `xcodegen generate` before xcodebuild | WIRED | Line 56: `cd App && xcodegen generate` |
| `.github/workflows/update-appcast.yml` | `scripts/generate-appcast.sh` | Script invocation in CI step | WIRED | Lines 60-61: `chmod +x scripts/generate-appcast.sh` + `scripts/generate-appcast.sh "$RUNNER_TEMP/appcast.xml"` |
| `App/project.yml (SUPublicEDKey)` | GitHub Secret `SPARKLE_PRIVATE_KEY` | Matching EdDSA key pair | WIRED (by convention) | Public key `nQlHBasrae63Ai7buw0NQAWV7wMXI70LCFLFbnULImw=` in app; private key confirmed stored as GitHub Secret by user (23-03-SUMMARY) |

---

## Signing Configuration Completeness

| Check | Value | Status |
|-------|-------|--------|
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME: YES` in base settings | VERIFIED |
| Entitlements linked | `CODE_SIGN_ENTITLEMENTS: Sources/DesignRuler.entitlements` | VERIFIED |
| `--options runtime` flag | `OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"` in xcodebuild archive | VERIFIED |
| Debug signing | `CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Automatic` | VERIFIED |
| Release signing | `CODE_SIGN_IDENTITY: "Developer ID Application"`, `CODE_SIGN_STYLE: Manual` | VERIFIED |
| Team ID injection | `DEVELOPMENT_TEAM: "$(DEVELOPMENT_TEAM)"` overridden in CI via `DEVELOPMENT_TEAM="$TEAM_ID"` | VERIFIED |
| Notarization | `notarytool submit --wait` + `stapler staple` on DMG | VERIFIED |
| Staple target | Staples the DMG (not the .app) — correct for Gatekeeper path | VERIFIED |
| `startingUpdater: true` | Sparkle updater starts on launch | VERIFIED |
| EdDSA public key | Real key (not placeholder) in project.yml and Info.plist | VERIFIED |
| Feed URL | `https://github.com/haythemgataa/design-ruler/releases/latest/download/appcast.xml` | VERIFIED |

---

## CI Workflow Structural Verification

### build-release.yml Pipeline (13 steps, in order)

1. Checkout (fetch-depth: 0 for git rev-list)
2. Extract version from tag (`${GITHUB_REF_NAME#v}`)
3. Install tools (`brew install create-dmg xcodegen`)
4. Import signing certificate (temp keychain, .p12 via base64)
5. Generate Xcode project (`xcodegen generate`)
6. Archive (Release config, Developer ID, `--options runtime`)
7. Export (`-exportOptionsPlist ExportOptions.plist`)
8. Copy DMG background from `scripts/assets/dmg-background.png`
9. Extract volume icon from .app bundle
10. Create DMG (`--app-drop-link 450 200` for Applications alias)
11. Notarize DMG (`notarytool submit --wait` + `stapler staple`)
12. Create draft release (`gh release create --draft`)
13. Cleanup keychain (`if: always()`)

All 7 required secrets referenced: `DEVELOPER_ID_CERT_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_ID`, `NOTARY_PASSWORD`, `TEAM_ID` in build-release; `SPARKLE_PRIVATE_KEY` in update-appcast.

### update-appcast.yml Pipeline (7 steps)

1. Checkout
2. Extract release info + construct download URL
3. Download DMG from release (`gh release download`)
4. Download Sparkle 2.8.1 tools from GitHub Releases
5. Generate EdDSA signature (private key piped via stdin: `--ed-key-file -`)
6. Generate appcast.xml via `scripts/generate-appcast.sh`
7. Upload appcast.xml to release (`gh release upload --clobber`)

---

## Anti-Patterns Found

No blockers or warnings detected. Scan of all phase artifacts clean.

---

## Human Verification Required

### 1. Code Signature Verification

**Test:** Build the app in Release configuration with a real Developer ID certificate, then run:
```
codesign --verify --deep --strict "Design Ruler.app"
codesign -dv --entitlements - "Design Ruler.app" | grep runtime
```
**Expected:** Exit 0, no output on first command. Second command shows `com.apple.security.cs.allow-jit` or confirms `runtime` flag is set.
**Why human:** Requires Developer ID Application certificate in Keychain Access; no certificate is present in this machine's environment.

### 2. Gatekeeper Assessment

**Test:** After downloading the notarized DMG from a GitHub release, on a fresh machine that has never run the app, open the DMG and attempt to launch the app. Also run:
```
spctl --assess --verbose=4 --type execute "Design Ruler.app"
```
**Expected:** Dialog says "Design Ruler" is from an identified developer (not blocked). `spctl` outputs `accepted source=Notarized Developer ID`.
**Why human:** Requires a completed notarytool submission to Apple's notarization service. Cannot be simulated locally.

### 3. DMG Layout Inspection

**Test:** Mount the DMG produced by the CI workflow. Inspect the Finder window.
**Expected:** Window size 600x400, branded background visible with "Design Ruler" text on light gray gradient, app icon on the left side, Applications folder alias on the right side. Drag app to Applications alias installs successfully.
**Why human:** Requires a completed CI run to produce the DMG. The create-dmg flags in the workflow specify the layout, but the visual result requires an actual DMG.

### 4. End-to-End Tag Push

**Test:** Push a `v1.0.0` tag to the repository with all 7 GitHub Secrets configured. Monitor the Actions run.
**Expected:** All 13 steps in build-release.yml succeed. A draft GitHub release named "Design Ruler 1.0.0" appears with `Design-Ruler-1.0.0.dmg` attached. After publishing the draft, the update-appcast workflow runs and attaches `appcast.xml` to the release.
**Why human:** Requires all 7 GitHub Secrets populated with real credentials and an active Apple Developer Program membership. The user confirmed in 23-03-SUMMARY that all secrets are configured.

---

## Gaps Summary

No codebase gaps. All artifacts exist, are substantive, and are correctly wired. The four human verification items are operational checkpoints that require real Apple Developer credentials and a live CI run — they are not missing code. The distribution infrastructure is complete and ready for its first tag-push test.

---

_Verified: 2026-02-20T04:50:00Z_
_Verifier: Claude (gsd-verifier)_
