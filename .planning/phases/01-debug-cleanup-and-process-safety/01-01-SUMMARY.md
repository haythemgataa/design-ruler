---
phase: 01-debug-cleanup-and-process-safety
plan: 01
subsystem: process-lifecycle
tags: [swift, debug-cleanup, watchdog-timer, zombie-prevention]

# Dependency graph
requires: []
provides:
  - "Clean production builds with zero stderr debug output"
  - "10-minute inactivity watchdog timer preventing zombie processes"
  - "onActivity callback pattern for user interaction tracking"
affects: [02-cursor-management-refactor]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inactivity watchdog via Foundation Timer on main run loop"
    - "onActivity callback from RulerWindow event handlers to Ruler lifecycle coordinator"

key-files:
  created: []
  modified:
    - swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift
    - swift/Ruler/Sources/RulerWindow.swift
    - swift/Ruler/Sources/Ruler.swift

key-decisions:
  - "Removed fputs entirely rather than gating with #if DEBUG (Raycast always builds debug config)"
  - "Timer placed in Ruler (lifecycle coordinator) not RulerWindow (event handler)"
  - "resetInactivityTimer called before app.run() so timer runs on main run loop"

patterns-established:
  - "onActivity callback: RulerWindow fires on every user event, Ruler resets watchdog"

# Metrics
duration: 2min
completed: 2026-02-13
---

# Phase 1 Plan 1: Debug Cleanup and Process Safety Summary

**Removed all 6 fputs debug calls from production code and added 600s inactivity watchdog timer routing through handleExit()**

## Performance

- **Duration:** 2 min 25s
- **Started:** 2026-02-13T09:51:11Z
- **Completed:** 2026-02-13T09:53:36Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Eliminated all stderr debug noise from production builds (6 fputs calls removed)
- Added automatic self-termination after 10 minutes of inactivity via Foundation Timer
- Wired onActivity callback from all 5 user event handlers in RulerWindow to Ruler's timer reset

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove all fputs debug output** - `e3ca327` (fix)
2. **Task 2: Add 10-minute inactivity watchdog timer** - `a262a72` (feat)

## Files Created/Modified
- `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` - Removed 2 fputs calls and nil-check wrapper block
- `swift/Ruler/Sources/RulerWindow.swift` - Removed 4 fputs calls, added onActivity callback property, added onActivity?() in 5 event handlers
- `swift/Ruler/Sources/Ruler.swift` - Added inactivityTimer/resetInactivityTimer(), wired onActivity to each window, reset timer on screen switch and before app.run()

## Decisions Made
- Removed fputs entirely rather than gating with `#if DEBUG` -- Raycast always builds in debug config so the flag provides zero protection
- Placed timer logic in Ruler (lifecycle coordinator) not RulerWindow, since Ruler owns handleExit() and coordinates multi-window lifecycle
- Used non-repeating Foundation Timer with weak self to avoid retain cycles; invalidate-and-reschedule pattern on each activity event

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All debug output removed, extension produces clean stderr
- Watchdog timer prevents zombie processes from accumulating
- Ready for Phase 2 (cursor management refactor) -- RulerWindow now has onActivity callback pattern established

## Self-Check: PASSED

- All 3 modified files exist on disk
- Commit e3ca327 verified in git log
- Commit a262a72 verified in git log
- Zero fputs calls confirmed across all Swift sources
- 5 onActivity?() calls confirmed in RulerWindow.swift
- Swift build succeeds with no errors

---
*Phase: 01-debug-cleanup-and-process-safety*
*Completed: 2026-02-13*
