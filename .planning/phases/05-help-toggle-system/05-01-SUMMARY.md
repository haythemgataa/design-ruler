---
phase: 05-help-toggle-system
plan: 01
subsystem: ui
tags: [core-animation, calayer, catextlayer, cashapelayer, userdefaults, nswindow, keyboard-events]

# Dependency graph
requires:
  - phase: 02-cursor-state-machine
    provides: CursorManager and RulerWindow keyDown structure
provides:
  - "Help toggle system: backspace dismisses hint bar + shows transient message, ? re-enables it"
  - "Session persistence of dismissed state via UserDefaults"
  - "Launch-with-dismissed path showing transient 'Press ? for help' message"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generation counter pattern for cancelling stale DispatchQueue.main.asyncAfter callbacks"
    - "CAShapeLayer + CATextLayer transient overlay (lighter than SwiftUI hosting)"
    - "event.characters for layout-independent key detection"

key-files:
  created: []
  modified:
    - swift/Ruler/Sources/RulerWindow.swift
    - swift/Ruler/Sources/Ruler.swift

key-decisions:
  - "Used CAShapeLayer + CATextLayer for transient message instead of SwiftUI hosting -- matches existing pill pattern, lighter weight"
  - "event.characters == '?' for layout-independent detection -- works on US, French AZERTY, German QWERTZ keyboards"
  - "Duplicate kHintBarDismissedKey constants in both files -- lesser evil than cross-file coupling for a single string"

patterns-established:
  - "Generation counter: increment counter, capture in closure, guard on match before executing delayed work"
  - "Transient CALayer overlay: create layers, add to contentView.layer, fade in via CATransaction, auto-fade via asyncAfter"

# Metrics
duration: 3min
completed: 2026-02-13
---

# Phase 5 Plan 1: Help Toggle System Summary

**Backspace-dismiss with transient "Press ? for help" overlay, "?" re-enable, and UserDefaults session persistence using CAShapeLayer + CATextLayer**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-13T11:48:56Z
- **Completed:** 2026-02-13T11:51:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Transient "Press ? for help" label using CAShapeLayer (rounded rect bg) + CATextLayer (white text), with 0.3s fade-in and 2.3s+0.5s auto-fade
- "?" key handler using `event.characters` for keyboard-layout independence, re-enables hint bar with fade-in animation
- Enhanced backspace handler: after hint bar fade-out, shows transient message and resets alphaValue for potential re-add
- Launch-with-dismissed path: detects UserDefaults dismissed state and shows transient message on startup
- Generation counter prevents stale asyncAfter callbacks from interfering after "?" restores the hint bar
- Extracted `kHintBarDismissedKey` constant in both files, eliminating raw string literals

## Task Commits

Each task was committed atomically:

1. **Task 1: Add transient help label and "?" key handler to RulerWindow** - `0b3edb6` (feat)
2. **Task 2: Update Ruler.swift UserDefaults key and verify full build** - `3036d40` (refactor)

## Files Created/Modified
- `swift/Ruler/Sources/RulerWindow.swift` - Added showTransientHelp(), fadeOutTransientHelp(), showHintBar() methods; enhanced backspace handler; added launch-with-dismissed logic; extracted UserDefaults key constant
- `swift/Ruler/Sources/Ruler.swift` - Extracted kHintBarDismissedKey constant replacing raw string literal

## Decisions Made
- Used CAShapeLayer + CATextLayer for transient message instead of SwiftUI NSHostingView -- same pattern as CrosshairView pill, zero view-hierarchy overhead
- Checked `event.characters == "?"` after the keyCode switch block so it fires regardless of which physical key produces "?"
- Duplicate `kHintBarDismissedKey` private constants in both files rather than shared internal constant -- avoids coupling for a single string

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 5 is the final phase -- all 5 phases complete
- Full help toggle lifecycle implemented: dismiss, rediscover, persist, launch-with-dismissed

## Self-Check: PASSED

- FOUND: swift/Ruler/Sources/RulerWindow.swift
- FOUND: swift/Ruler/Sources/Ruler.swift
- FOUND: .planning/phases/05-help-toggle-system/05-01-SUMMARY.md
- FOUND: commit 0b3edb6
- FOUND: commit 3036d40

---
*Phase: 05-help-toggle-system*
*Completed: 2026-02-13*
