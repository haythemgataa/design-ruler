---
phase: quick
plan: 1
subsystem: ui
tags: [nscursor, loading-feedback, cold-start]

# Dependency graph
requires:
  - phase: 02-cursor-state-machine
    provides: CursorManager for post-window cursor lifecycle
provides:
  - Wait cursor shown during cold-start warmup and multi-screen capture
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [NSCursor push/pop stack for pre-window loading state]

key-files:
  created: []
  modified:
    - swift/Ruler/Sources/Ruler.swift

key-decisions:
  - "Used busyButClickableCursor via perform(selector:) instead of nonexistent NSCursor.wait"
  - "Arrow cursor fallback if busyButClickableCursor unavailable on future macOS"
  - "push/pop placed in inspect()/run() respectively to cover entire slow path"

patterns-established:
  - "Pre-window cursor state uses NSCursor push/pop stack (not CursorManager)"

# Metrics
duration: 4min
completed: 2026-02-13
---

# Quick Task 1: Show Loading Cursor Summary

**Busy cursor (spinning disc) shown during CGWindowListCreateImage cold-start warmup and multi-screen capture via NSCursor push/pop stack**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-13T13:49:09Z
- **Completed:** 2026-02-13T13:53:25Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Busy-but-clickable cursor appears immediately when Raycast command is invoked
- Cursor removed cleanly before overlay windows appear, handing off to CursorManager lifecycle
- Fallback to arrow cursor if private API unavailable on future macOS versions

## Task Commits

Each task was committed atomically:

1. **Task 1: Add wait cursor during warmup and capture** - `4fceda3` (feat)

## Files Created/Modified
- `swift/Ruler/Sources/Ruler.swift` - Added `busyCursor()` helper, push at start of `inspect()`, pop in `run()` before window creation

## Decisions Made
- **Used `busyButClickableCursor` instead of `NSCursor.wait`**: The plan specified `NSCursor.wait` which does not exist in the macOS AppKit SDK. The `busyButClickableCursor` is a semi-public API (available via `perform(selector:)`) that shows the spinning disc with arrow cursor -- the standard macOS busy indicator for responsive apps.
- **Arrow cursor fallback**: If `busyButClickableCursor` is removed in a future macOS version, falls back gracefully to the default arrow cursor rather than crashing.
- **push/pop placement**: `push()` in `inspect()` (before warmup) and `pop()` in `run()` (after all captures) covers the entire slow path: warmup 1x1 capture + permission check + screen detection + all multi-screen captures.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] NSCursor.wait does not exist in macOS AppKit SDK**
- **Found during:** Task 1 (Add wait cursor)
- **Issue:** Plan specified `NSCursor.wait.push()` but `NSCursor` has no `.wait` property -- Swift build fails with "type 'NSCursor' has no member 'wait'"
- **Fix:** Created `busyCursor()` helper that retrieves `busyButClickableCursor` via `NSCursor.perform(NSSelectorFromString("busyButClickableCursor"))` with fallback to `.arrow`
- **Files modified:** swift/Ruler/Sources/Ruler.swift
- **Verification:** `swift build` and `ray build` both succeed
- **Committed in:** 4fceda3 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary fix for nonexistent API. Same behavior achieved with correct API. No scope creep.

## Issues Encountered
- Pre-existing unstaged changes in working tree required careful commit isolation (checkout HEAD version, re-apply only wait cursor changes, stash/unstash unrelated files)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Wait cursor feature complete and self-contained
- No follow-up work required

## Self-Check: PASSED

- [x] swift/Ruler/Sources/Ruler.swift exists and contains busyCursor() + NSCursor.pop()
- [x] 1-SUMMARY.md exists
- [x] Commit 4fceda3 exists in git log

---
*Quick Task: 1-show-a-loading-cursor-when-waiting-for-t*
*Completed: 2026-02-13*
