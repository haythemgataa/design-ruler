---
phase: 22-global-hotkeys
plan: 03
subsystem: ui
tags: [swiftui, keyboard-shortcuts, nsmenudelegate, settings, menu-bar]

# Dependency graph
requires:
  - phase: 22-global-hotkeys/01
    provides: "Global hotkey infrastructure (KeyboardShortcuts integration, shortcut names, menu bar setShortcut)"
  - phase: 22-global-hotkeys/02
    provides: "Settings shortcut recorder UI with conflict detection"
provides:
  - "Persistent conflict warning on duplicate shortcut assignment"
  - "Menu bar dropdown always displays current shortcut key combinations"
  - "Hotkey disable/enable around menu open lifecycle"
affects: [23-raycast-detection, 24-distribution]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NSMenuDelegate for defensive shortcut refresh on every menu open"
    - "Guard nil callback in onChange to survive double-fire rejection chain"
    - "menuWillOpen/menuDidClose to disable/enable global hotkeys during menu tracking"

key-files:
  created: []
  modified:
    - "App/Sources/SettingsView.swift"
    - "App/Sources/MenuBarController.swift"

key-decisions:
  - "Guard else-branch on newShortcut != nil (not unconditional clear) to survive onChange double-fire from setShortcut(nil) rejection"
  - "NSMenuDelegate with menuNeedsUpdate for defensive shortcut refresh (supplements library observer chain)"
  - "menuWillOpen/menuDidClose disable/enable hotkeys to prevent buffered events during NSMenu tracking mode"

patterns-established:
  - "onChange double-fire guard: when rejecting a value by setting nil, the nil callback must not undo the rejection side-effect"

# Metrics
duration: 1min 40s
completed: 2026-02-19
---

# Phase 22 Plan 03: Global Hotkeys Gap Closure Summary

**Fix conflict warning persistence via nil-callback guard and menu bar shortcut display via NSMenuDelegate refresh**

## Performance

- **Duration:** 1min 40s
- **Started:** 2026-02-19T10:45:11Z
- **Completed:** 2026-02-19T10:46:51Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Conflict detection warning no longer disappears when onChange fires with nil after setShortcut(nil) rejection
- Menu bar dropdown always shows current shortcut key combinations via menuNeedsUpdate delegate
- Global hotkeys disabled during menu tracking to prevent buffered key events

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix conflict detection warning disappearing immediately** - `c64af8b` (fix)
2. **Task 2: Fix menu bar dropdown not showing shortcut symbols** - `fef8bec` (fix)

## Files Created/Modified
- `App/Sources/SettingsView.swift` - Guard conflict warning clear on `newShortcut != nil` in both recorder onChange closures
- `App/Sources/MenuBarController.swift` - NSObject + NSMenuDelegate conformance, stored menu items, menuNeedsUpdate/menuWillOpen/menuDidClose

## Decisions Made
- Guard else-branch on `newShortcut != nil` rather than adding a debounce timer or flag -- simplest fix that directly addresses the double-fire root cause
- NSMenuDelegate with `menuNeedsUpdate` as defensive refresh -- supplements (does not replace) the library's observer-based auto-update
- `menuWillOpen`/`menuDidClose` disable/enable hotkeys per KeyboardShortcuts library recommendation for NSMenu tracking mode

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 22 (Global Hotkeys) fully complete with all UAT gaps closed
- Ready for Phase 23 (Raycast Detection) or Phase 24 (Distribution)

## Self-Check: PASSED

All files verified present. All commit hashes found in git log.

---
*Phase: 22-global-hotkeys*
*Completed: 2026-02-19*
