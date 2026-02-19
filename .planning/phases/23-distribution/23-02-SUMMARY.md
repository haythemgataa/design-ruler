---
phase: 23-distribution
plan: 02
subsystem: infra
tags: [github-actions, ci, code-signing, notarization, dmg, sparkle, appcast, create-dmg]

# Dependency graph
requires:
  - phase: 23-distribution-01
    provides: Entitlements file, ExportOptions.plist, Release signing settings in project.yml
provides:
  - GitHub Actions build-release workflow (tag-push -> archive -> sign -> notarize -> DMG -> draft release)
  - GitHub Actions update-appcast workflow (release-publish -> EdDSA sign -> appcast.xml -> upload)
  - Appcast generation shell script (scripts/generate-appcast.sh)
  - Branded DMG background asset (scripts/assets/dmg-background.png)
affects: [23-distribution-03]

# Tech tracking
tech-stack:
  added: [create-dmg, Sparkle sign_update, notarytool, GitHub Actions]
  patterns: [two-workflow CI, keychain-in-CI, version-from-tag, EdDSA-stdin-piping]

key-files:
  created:
    - .github/workflows/build-release.yml
    - .github/workflows/update-appcast.yml
    - scripts/generate-appcast.sh
    - scripts/assets/dmg-background.png
  modified: []

key-decisions:
  - "Two-workflow architecture: build on tag-push, appcast on release-publish"
  - "EdDSA key piped via stdin in CI (never written to disk)"
  - "create-dmg || true to handle exit code 2 warnings, with post-check for DMG existence"
  - "Single-item appcast (not cumulative history) sufficient for v1 pipeline"
  - "DMG background generated with Pillow (1200x800 @2x, light gray gradient with centered text)"

patterns-established:
  - "Tag-push workflow: version extraction -> xcodegen -> archive -> export -> DMG -> notarize -> draft release"
  - "Release-publish workflow: download DMG -> EdDSA sign -> generate appcast -> upload to release"
  - "Temporary keychain pattern with if: always() cleanup"

# Metrics
duration: 2min 56s
completed: 2026-02-19
---

# Phase 23 Plan 02: CI Pipeline Summary

**Two GitHub Actions workflows for automated build/sign/notarize/package on tag push, and Sparkle appcast generation on release publish, with branded DMG background asset**

## Performance

- **Duration:** 2min 56s
- **Started:** 2026-02-19T17:09:57Z
- **Completed:** 2026-02-19T17:12:53Z
- **Tasks:** 2
- **Files created:** 4

## Accomplishments
- Build-release workflow: full CI pipeline from tag push to notarized DMG in draft GitHub Release
- Update-appcast workflow: EdDSA signing and Sparkle appcast.xml generation on release publish
- Appcast generation script produces valid XML with version, signature, download URL, and minimum system version
- Branded DMG background image (1200x800 @2x) with "Design Ruler" text on subtle gradient

## Task Commits

Each task was committed atomically:

1. **Task 1: Create build-release workflow and branded DMG background asset** - `d290686` (feat)
2. **Task 2: Create update-appcast workflow and appcast generation script** - `499aa67` (feat)

## Files Created/Modified
- `.github/workflows/build-release.yml` - CI workflow: tag-push -> archive -> sign -> notarize -> DMG -> draft release
- `.github/workflows/update-appcast.yml` - CI workflow: release-publish -> download DMG -> EdDSA sign -> generate appcast -> upload
- `scripts/generate-appcast.sh` - Shell script generating Sparkle appcast.xml from env vars
- `scripts/assets/dmg-background.png` - Branded DMG background (1200x800 @2x, light gray gradient, "Design Ruler" text)

## Decisions Made
- Two-workflow architecture separates build (tag-push) from appcast generation (release-publish), allowing manual review of draft releases
- EdDSA private key piped via stdin (`--ed-key-file -`) to Sparkle's sign_update, never written to disk in CI
- `create-dmg || true` handles exit code 2 warnings (cosmetic), followed by explicit `test -f` to verify DMG was created
- Single-item appcast (latest release only) is sufficient for stable-channel-only v1 pipeline
- Sparkle 2.8.1 tools downloaded from GitHub Releases in update-appcast workflow (deterministic version)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

Before the CI pipeline can run, the following GitHub Secrets must be configured:
- `DEVELOPER_ID_CERT_BASE64` - Base64-encoded .p12 certificate
- `DEVELOPER_ID_CERT_PASSWORD` - .p12 password
- `KEYCHAIN_PASSWORD` - Random password for temporary CI keychain
- `APPLE_ID` - Apple Developer account email
- `NOTARY_PASSWORD` - App-specific password for notarytool
- `TEAM_ID` - Apple Developer Team ID
- `SPARKLE_PRIVATE_KEY` - EdDSA private key from Sparkle's generate_keys

## Next Phase Readiness
- CI workflows ready; requires GitHub Secrets configuration before first tag push
- Plan 23-03 can wire SUFeedURL and SUPublicEDKey into the app after EdDSA key generation
- Workflows reference ExportOptions.plist and project.yml Release signing settings from Plan 23-01

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 23-distribution*
*Completed: 2026-02-19*
