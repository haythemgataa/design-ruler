---
phase: 15-window-base-cursor
plan: 01
subsystem: ui
tags: [nswindow, base-class, cursor-management, overlay, swift]

# Dependency graph
requires:
  - phase: 14-coordinator-base
    provides: OverlayCoordinator base class and OverlayWindowProtocol
provides:
  - OverlayWindow base class with shared window configuration, tracking, throttling, hint bar, events
  - CursorManager resize cursor states (resizeUpDown, resizeLeftRight) with full transition graph
affects: [15-02-PLAN (window subclassing), alignment-guides cursor management]

# Tech tracking
tech-stack:
  added: []
  patterns: [OverlayWindow base class with overridable hooks, static configureOverlay factory helper, resize cursor state machine]

key-files:
  created: [swift/Ruler/Sources/Utilities/OverlayWindow.swift]
  modified: [swift/Ruler/Sources/Cursor/CursorManager.swift]

key-decisions:
  - "Static configureOverlay() instead of init override due to NSWindow init patterns"
  - "setupHintBar parameterized by HintBarMode; skips setMode for default .inspect"
  - "handleActivation/handleMouseMoved/handleKeyDown as overridable hooks, not protocol methods"

patterns-established:
  - "OverlayWindow base: subclasses call configureOverlay() after NSWindow init, override hooks for behavior"
  - "CursorManager resize transitions: resizeUpDown/resizeLeftRight with switchResize for tab toggle"

# Metrics
duration: 2min 6s
completed: 2026-02-17
---

# Phase 15 Plan 01: OverlayWindow Base Class + CursorManager Resize States Summary

**OverlayWindow base class consolidating 10 shared NSWindow properties, tracking area, hint bar lifecycle, throttled mouse move, and ESC handling; CursorManager extended with 6 states and 5 new resize cursor transitions**

## Performance

- **Duration:** 2min 6s
- **Started:** 2026-02-17T09:50:10Z
- **Completed:** 2026-02-17T09:52:16Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created OverlayWindow base class with all shared window configuration (configureOverlay, setupTrackingArea, collapseHintBar, setupHintBar, setBackground, hintBarEntrance)
- Base owns throttled mouseMoved with first-move detection, ESC key handling, and mouseEntered delegation via overridable hooks
- Extended CursorManager from 4 to 6 states with 5 new transition methods for alignment guides resize cursors

## Task Commits

Each task was committed atomically:

1. **Task 1: Create OverlayWindow base class** - `a0a63b9` (feat)
2. **Task 2: Extend CursorManager with resize cursor states** - `471629b` (feat)

## Files Created/Modified
- `swift/Ruler/Sources/Utilities/OverlayWindow.swift` - Base class with shared NSWindow config, tracking, hint bar, events, hooks
- `swift/Ruler/Sources/Cursor/CursorManager.swift` - Added resizeUpDown/resizeLeftRight states and 5 transition methods

## Decisions Made
- Static `configureOverlay()` instead of init override -- NSWindow's init patterns make subclass init impractical; subclass factories call the static method after creating the window
- `setupHintBar` parameterized by `HintBarMode` -- skips `setMode()` for default `.inspect` mode, preserving the critical setup order (setMode before configure)
- Overridable hooks (handleActivation, handleMouseMoved, handleKeyDown) as regular methods -- simpler than protocol-based approach, subclasses just override

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- OverlayWindow base class ready for RulerWindow and AlignmentGuidesWindow to subclass in Plan 02
- CursorManager resize states ready for alignment guides to use when Plan 02 rewires cursor management
- No changes to existing window files -- they remain functional until Plan 02 refactors them

## Self-Check: PASSED

- All created files exist on disk
- All commit hashes verified in git log

---
*Phase: 15-window-base-cursor*
*Completed: 2026-02-17*
