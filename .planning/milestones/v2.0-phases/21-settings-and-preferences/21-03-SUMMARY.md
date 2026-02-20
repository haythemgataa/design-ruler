---
phase: 21-settings-and-preferences
plan: 03
subsystem: ui
tags: [swiftui, smappservice, sparkle, settings, login-item]

# Dependency graph
requires:
  - phase: 21-settings-and-preferences (01, 02)
    provides: SettingsView with Launch at Login toggle and Sparkle updater integration
provides:
  - Fixed Launch at Login toggle sync using @State + .onAppear pattern
  - Deferred Sparkle updater startup to avoid placeholder key validation error
affects: [24-distribution]

# Tech tracking
tech-stack:
  added: []
  patterns: [@State + .onAppear for non-observable service status refresh]

key-files:
  created: []
  modified:
    - App/Sources/SettingsView.swift
    - App/Sources/AppDelegate.swift

key-decisions:
  - "@State + .onAppear over Binding(get:set:) for SMAppService status — SwiftUI cannot observe SMAppService directly"
  - "startingUpdater: false defers EdDSA key validation — Phase 24 will set real keys and re-enable"

patterns-established:
  - "@State + .onAppear refresh: for system services not observable by SwiftUI, use @State with .onAppear to re-read on window appearance"

# Metrics
duration: 1min 22s
completed: 2026-02-19
---

# Phase 21 Plan 03: UAT Gap Closure Summary

**Fixed Launch at Login toggle desync and Sparkle placeholder key error dialog -- two UAT-blocking bugs in Settings and AppDelegate**

## Performance

- **Duration:** 1min 22s
- **Started:** 2026-02-19T05:03:45Z
- **Completed:** 2026-02-19T05:05:07Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Launch at Login toggle now correctly reflects actual SMAppService registration status every time Settings window is reopened
- Sparkle updater no longer shows error dialog on launch caused by placeholder EdDSA key
- Info.plist and project.yml placeholders preserved for Phase 24 distribution setup

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix Launch at Login toggle desync with @State + .onAppear** - `b032624` (fix)
2. **Task 2: Fix Sparkle updater startup failure with deferred initialization** - `24de60f` (fix)

## Files Created/Modified
- `App/Sources/SettingsView.swift` - Replaced Binding(get:set:) with @State launchAtLogin + .onAppear refresh from SMAppService.mainApp.status
- `App/Sources/AppDelegate.swift` - Changed SPUStandardUpdaterController init to startingUpdater: false

## Decisions Made
- **@State + .onAppear over Binding(get:set:):** SMAppService.mainApp.status is not observable by SwiftUI. When the Settings window is reused (not recreated), Binding's get closure is never re-evaluated. @State with .onAppear ensures re-read on every window appearance.
- **startingUpdater: false:** Defers Sparkle's EdDSA key validation. The placeholder "PLACEHOLDER_EDDSA_PUBLIC_KEY" fails base64 decode when validated immediately. Phase 24 will set real keys and can switch back to startingUpdater: true.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 21 UAT gaps closed -- both major issues from UAT testing resolved
- Phase 24 will need to replace placeholder EdDSA key and SUFeedURL, then re-enable startingUpdater: true
- Ready for Phase 22 (Global Hotkeys)

## Self-Check: PASSED

All files exist, all commits verified, all content claims confirmed.

---
*Phase: 21-settings-and-preferences*
*Completed: 2026-02-19*
