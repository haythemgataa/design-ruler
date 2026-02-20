---
phase: 21-settings-and-preferences
plan: 02
subsystem: infra
tags: [sparkle, auto-update, spm, macos]

# Dependency graph
requires:
  - phase: 21-settings-and-preferences/01
    provides: "Settings window with SettingsView, SettingsWindowController, AppDelegate menu wiring"
provides:
  - "Sparkle 2 SPM dependency in project.yml"
  - "SPUStandardUpdaterController initialized at app launch"
  - "Check for Updates menu item in menu bar dropdown"
  - "Check for Updates button in Settings About section"
  - "Automatically Check for Updates toggle in Settings General section"
  - "SUFeedURL and SUPublicEDKey placeholder keys in Info.plist"
affects: [24-distribution]

# Tech tracking
tech-stack:
  added: [Sparkle 2.8.1]
  patterns: [SPUStandardUpdaterController singleton in AppDelegate, SPUUpdater passed to SwiftUI views]

key-files:
  modified:
    - App/project.yml
    - App/Sources/Info.plist
    - App/Sources/AppDelegate.swift
    - App/Sources/MenuBarController.swift
    - App/Sources/SettingsWindowController.swift
    - App/Sources/SettingsView.swift
    - App/Design Ruler.xcodeproj/project.pbxproj

key-decisions:
  - "SPUStandardUpdaterController initialized as inline let property with startingUpdater: true (starts updater immediately at launch)"
  - "SPUUpdater reference passed through SettingsWindowController to SettingsView (not global/singleton access)"
  - "Placeholder SUFeedURL and SUPublicEDKey in Info.plist (real values configured in Phase 24)"

patterns-established:
  - "Sparkle updater wiring: AppDelegate owns SPUStandardUpdaterController, passes SPUUpdater to settings views"

# Metrics
duration: 4min 8s
completed: 2026-02-19
---

# Phase 21 Plan 02: Sparkle Update Integration Summary

**Sparkle 2 integrated with SPUStandardUpdaterController, Check for Updates in menu bar and Settings, and auto-check toggle in General section**

## Performance

- **Duration:** 4min 8s
- **Started:** 2026-02-19T04:29:18Z
- **Completed:** 2026-02-19T04:33:26Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Sparkle 2.8.1 added as SPM dependency via project.yml (resolved and linked)
- SPUStandardUpdaterController initialized at app launch in AppDelegate
- "Check for Updates..." menu item added to menu bar dropdown (between Settings and Quit)
- "Check for Updates..." button added to About section in Settings
- "Automatically Check for Updates" toggle added to General section in Settings
- Info.plist configured with SUFeedURL, SUPublicEDKey (placeholder), and SUEnableAutomaticChecks
- Raycast SPM build unaffected (Sparkle only in project.yml, not Package.swift)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Sparkle SPM dependency and Info.plist keys** - `5a8f71d` (chore)
2. **Task 2: Wire Sparkle into AppDelegate, MenuBarController, and SettingsView** - `d081ff8` (feat)

## Files Created/Modified
- `App/project.yml` - Added Sparkle SPM package and target dependency, SUFeedURL/SUPublicEDKey/SUEnableAutomaticChecks in info properties
- `App/Sources/Info.plist` - Added SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks keys
- `App/Sources/AppDelegate.swift` - Added Sparkle import, SPUStandardUpdaterController, onCheckForUpdates wiring, updater pass-through to settings
- `App/Sources/MenuBarController.swift` - Added onCheckForUpdates callback and "Check for Updates..." menu item
- `App/Sources/SettingsWindowController.swift` - Added Sparkle import, showSettings now accepts SPUUpdater parameter
- `App/Sources/SettingsView.swift` - Added Sparkle import, SPUUpdater property, auto-check toggle, Check for Updates button
- `App/Design Ruler.xcodeproj/project.pbxproj` - Regenerated with Sparkle package reference

## Decisions Made
- SPUStandardUpdaterController initialized as inline `let` property with `startingUpdater: true` -- starts the updater immediately at launch, which is Sparkle's recommended pattern
- SPUUpdater reference passed through SettingsWindowController to SettingsView rather than using global/singleton access -- keeps dependency injection clean and testable
- Placeholder SUFeedURL and SUPublicEDKey in Info.plist -- real values will be configured in Phase 24 (distribution)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Sparkle update infrastructure complete with placeholder appcast URL
- Phase 24 (distribution) will configure real SUFeedURL, SUPublicEDKey, and appcast generation
- All other settings and preferences functionality (shortcuts) deferred to Phase 22

## Self-Check: PASSED
- FOUND: 21-02-SUMMARY.md
- FOUND: 5a8f71d (Task 1 commit)
- FOUND: d081ff8 (Task 2 commit)

---
*Phase: 21-settings-and-preferences*
*Completed: 2026-02-19*
