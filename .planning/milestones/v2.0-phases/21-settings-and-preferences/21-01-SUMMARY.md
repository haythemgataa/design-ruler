---
phase: 21-settings-and-preferences
plan: 01
subsystem: App Settings / Preferences
tags: [SwiftUI, UserDefaults, SMAppService, NSHostingView, NSWindow, settings]
dependency_graph:
  requires:
    - 20-menu-bar-shell/20-01 (MenuBarController with NSStatusItem and callback pattern)
  provides:
    - AppPreferences singleton with UserDefaults-backed hideHintBar and corrections
    - SettingsView SwiftUI Form with 4 grouped sections (General, Measure, Shortcuts, About)
    - SettingsWindowController with persistent NSWindow lifecycle
    - Settings menu item enabled with Cmd+, shortcut
    - First-launch auto-registration of login item via SMAppService
  affects:
    - 21-settings-and-preferences/21-02 (Sparkle integration adds update toggle + button to SettingsView)
    - 22 (Shortcuts section populated with hotkey recorders)
tech_stack:
  added: [ServiceManagement (SMAppService)]
  patterns:
    - SwiftUI Form in NSWindow via NSHostingView (settings window)
    - AppPreferences.shared read at coordinator invocation time (not hardcoded)
    - SettingsWindowController reuses NSWindow across open/close (isReleasedWhenClosed=false)
    - updateConstraintsIfNeeded() before center() for macOS Sequoia centering fix
    - First-launch detection via hasLaunchedBefore UserDefaults key
key_files:
  created:
    - App/Sources/AppPreferences.swift
    - App/Sources/SettingsView.swift
    - App/Sources/SettingsWindowController.swift
  modified:
    - App/Sources/MenuBarController.swift
    - App/Sources/AppDelegate.swift
    - App/Design Ruler.xcodeproj/project.pbxproj
key_decisions:
  - "AppPreferences uses computed properties over UserDefaults (not @AppStorage) for cross-context access from AppKit and SwiftUI"
  - "Launch at Login toggle reads SMAppService.mainApp.status directly (not UserDefaults) to stay in sync with System Settings"
  - "SettingsWindowController has three code paths: visible (bring to front), exists but hidden (update constraints + center + show), first time (create)"
  - "First-launch auto-registers login item since app distributes outside App Store (no review rules apply)"
metrics:
  duration: "2min 54s"
  completed: "2026-02-19"
  tasks_completed: 2
  files_changed: 6
---

# Phase 21 Plan 01: Settings and Preferences Summary

**SwiftUI grouped settings window with UserDefaults-backed hideHintBar/corrections, SMAppService launch-at-login toggle, and preferences read at coordinator invocation time via AppPreferences singleton.**

## Performance

- **Duration:** 2min 54s
- **Started:** 2026-02-19T04:23:58Z
- **Completed:** 2026-02-19T04:26:52Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Settings window with 4 grouped sections (General, Measure, Shortcuts placeholder, About) using SwiftUI Form + `.formStyle(.grouped)` in NSHostingView
- AppPreferences singleton reads/writes UserDefaults for hideHintBar and corrections, consumed by both coordinators at overlay launch time
- Launch at Login toggle uses SMAppService.mainApp directly (register/unregister/status) and auto-enables on first launch
- Settings menu item enabled with Cmd+, standard shortcut, wired via onOpenSettings callback

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AppPreferences, SettingsView, and SettingsWindowController** - `98f080e` (feat)
2. **Task 2: Wire settings into MenuBarController and AppDelegate, add first-launch login** - `678bc49` (feat)

## Files Created/Modified
- `App/Sources/AppPreferences.swift` - @Observable singleton wrapping UserDefaults for hideHintBar (Bool) and corrections (String)
- `App/Sources/SettingsView.swift` - SwiftUI Form with General (login + hint bar toggles), Measure (corrections radio group), Shortcuts (placeholder), About (icon + version + copyright + GitHub link)
- `App/Sources/SettingsWindowController.swift` - NSWindow lifecycle with persistent window, Sequoia centering fix, isReleasedWhenClosed=false
- `App/Sources/MenuBarController.swift` - Settings item enabled with action, Cmd+, keyEquivalent, onOpenSettings callback
- `App/Sources/AppDelegate.swift` - Reads AppPreferences at invocation time, first-launch SMAppService registration, SettingsWindowController wiring
- `App/Design Ruler.xcodeproj/project.pbxproj` - Regenerated to include 3 new source files

## Decisions Made
- AppPreferences uses computed getter/setter over UserDefaults rather than @AppStorage, since coordinators in AppDelegate (AppKit context) also need to read values
- Launch at Login toggle reads SMAppService.mainApp.status on every access (not a cached UserDefaults boolean) so it stays in sync if user changes login items in System Settings
- SettingsWindowController has three branches: visible window (bring to front), closed-but-alive window (re-center + show), no window yet (create from scratch)
- Comments left in SettingsView for Plan 02 Sparkle integration points (auto-check toggle in General, check button in About)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- SettingsView has placeholder comments for Sparkle integration (Plan 02): auto-check toggle in General section, Check for Updates button in About section
- Shortcuts section ready for Phase 22 hotkey recorders
- Both xcodebuild and swift build pass

## Self-Check: PASSED

All files found:
- FOUND: App/Sources/AppPreferences.swift
- FOUND: App/Sources/SettingsView.swift
- FOUND: App/Sources/SettingsWindowController.swift
- FOUND: App/Sources/MenuBarController.swift
- FOUND: App/Sources/AppDelegate.swift

All commits found:
- FOUND: 98f080e (Task 1)
- FOUND: 678bc49 (Task 2)

---
*Phase: 21-settings-and-preferences*
*Completed: 2026-02-19*
