---
status: complete
phase: 23-distribution
source: 23-01-SUMMARY.md, 23-02-SUMMARY.md, 23-03-SUMMARY.md
started: 2026-02-20T12:00:00Z
updated: 2026-02-20T12:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Debug Build Compiles
expected: Running xcodebuild for Debug configuration completes without errors. The signing/entitlements changes from 23-01 should not break the ad-hoc Debug build.
result: pass

### 2. Sparkle Updater Active on Launch
expected: Launching the app, Sparkle updater initializes on startup (startingUpdater: true). No crash on launch related to EdDSA key validation. The "Check for Updates..." menu item is functional.
result: pass

### 3. CI Build-Release Workflow
expected: `.github/workflows/build-release.yml` exists and triggers on tag pushes matching `v*`. The workflow archives, signs, notarizes, packages into DMG, and creates a draft GitHub Release. Reviewing the workflow file shows the correct sequence of steps.
result: skipped
reason: Apple Developer account not yet active (pending payment). CI workflows exist but cannot be end-to-end tested.

### 4. CI Update-Appcast Workflow
expected: `.github/workflows/update-appcast.yml` exists and triggers on release publish. It downloads the DMG, signs with EdDSA, generates appcast.xml via `scripts/generate-appcast.sh`, and uploads both as release assets.
result: skipped
reason: Apple Developer account not yet active (pending payment). CI workflows exist but cannot be end-to-end tested.

### 5. Real EdDSA Public Key Configured
expected: `App/Sources/Info.plist` contains the real EdDSA public key (`nQlHBasrae63Ai7buw0NQAWV7wMXI70LCFLFbnULImw=`), not the placeholder value. Same key in `App/project.yml`.
result: pass

### 6. Correct Appcast Feed URL
expected: `SUFeedURL` in Info.plist points to `https://github.com/haythemgataa/design-ruler/releases/latest/download/appcast.xml` (matching the actual GitHub remote), not any other repository.
result: pass

## Summary

total: 6
passed: 4
issues: 0
pending: 0
skipped: 2

## Gaps

[none yet]
