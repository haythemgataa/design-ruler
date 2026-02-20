---
phase: 02-cursor-state-machine
plan: 01
subsystem: ui
tags: [nscursor, state-machine, sigterm, dispatch-source, appkit]

# Dependency graph
requires:
  - phase: 01-debug-cleanup
    provides: Clean codebase with debug output removed and inactivity timer
provides:
  - CursorManager class with explicit state enum and balanced hide/push counters
  - SIGTERM signal handler for graceful cursor restoration on process termination
  - All NSCursor calls centralized through single class (except addCursorRect in resetCursorRects)
affects: [03-multi-monitor, 04-edge-skipping, 05-hint-bar]

# Tech tracking
tech-stack:
  added: [DispatchSource signal handling]
  patterns: [cursor state machine, centralized cursor management, SIGTERM graceful shutdown]

key-files:
  created:
    - swift/Ruler/Sources/Cursor/CursorManager.swift
  modified:
    - swift/Ruler/Sources/Ruler.swift
    - swift/Ruler/Sources/RulerWindow.swift
    - swift/Ruler/Sources/Rendering/CrosshairView.swift

key-decisions:
  - "Singleton CursorManager.shared pattern matching existing Ruler.shared convention"
  - "State enum with 4 cases (systemCrosshair, hidden, pointingHand, crosshairDrag) replacing scattered boolean flags"
  - "Track own hideCount/pushCount for unconditional restore() on all exit paths"
  - "resetCursorRects stays in CrosshairView (AppKit framework callback, not application-initiated)"

patterns-established:
  - "All NSCursor push/pop/hide/unhide through CursorManager (except addCursorRect in resetCursorRects)"
  - "SIGTERM via DispatchSource on main queue for safe AppKit cleanup"

# Metrics
duration: 3min
completed: 2026-02-13
---

# Phase 2 Plan 1: Cursor State Machine Summary

**Centralized CursorManager with 4-state enum, balanced hide/push counters, and SIGTERM handler replacing 18 scattered NSCursor calls across 3 files**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-13T10:44:08Z
- **Completed:** 2026-02-13T10:47:58Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created CursorManager.swift with State enum (systemCrosshair, hidden, pointingHand, crosshairDrag), 4 transition methods, restore(), and reset()
- Migrated all 16 direct NSCursor push/pop/hide/unhide calls from RulerWindow.swift (15) and CrosshairView.swift (1) to CursorManager transitions
- Added SIGTERM DispatchSource handler in Ruler.swift for graceful cursor restoration on Raycast shutdown
- Only remaining NSCursor reference outside CursorManager is `addCursorRect(bounds, cursor: .crosshair)` in resetCursorRects() (AppKit framework callback)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create CursorManager and wire SIGTERM handler** - `36d698d` (feat)
2. **Task 2: Migrate all NSCursor call sites in RulerWindow and CrosshairView** - `5294ce9` (refactor)

## Files Created/Modified
- `swift/Ruler/Sources/Cursor/CursorManager.swift` - Centralized cursor state machine with explicit state enum, 4 transition methods, and unconditional restore()
- `swift/Ruler/Sources/Ruler.swift` - Added sigTermSource property, setupSignalHandler() method, replaced NSCursor.unhide() with CursorManager.shared.restore() in handleExit()
- `swift/Ruler/Sources/RulerWindow.swift` - Replaced 15 direct NSCursor calls with CursorManager transitions, removed hasReceivedFirstMove guards on cursor cleanup
- `swift/Ruler/Sources/Rendering/CrosshairView.swift` - Replaced NSCursor.hide() in hideSystemCrosshair() with CursorManager.shared.transitionToHidden()

## Decisions Made
- Used singleton CursorManager.shared pattern matching existing Ruler.shared convention (NSCursor is inherently global state)
- State enum with 4 mutually exclusive cases instead of scattered boolean flags (prevents impossible state combinations)
- Track own hideCount/pushCount counters for unconditional restore() that issues exactly the right number of unhide/pop calls
- resetCursorRects stays in CrosshairView -- it is an AppKit framework callback, not an application-initiated cursor change
- Removed hasReceivedFirstMove guards on cursor cleanup in RulerWindow -- CursorManager's state guards handle this correctly (transition methods are no-ops when state doesn't match)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CursorManager is ready for use by all future phases that interact with cursor state
- Phase 3 (multi-monitor) and Phase 4 (edge skipping) can proceed -- both depend only on Phase 1
- Phase 5 (hint bar) depends on Phase 2 completion (touches RulerWindow.keyDown) -- now unblocked

## Self-Check: PASSED

All files exist. All commits verified.

---
*Phase: 02-cursor-state-machine*
*Completed: 2026-02-13*
