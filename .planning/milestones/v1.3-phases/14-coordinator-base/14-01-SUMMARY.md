---
phase: 14-coordinator-base
plan: 01
subsystem: architecture
tags: [swift, base-class, lifecycle, screen-capture, coordinator]

# Dependency graph
requires:
  - phase: 12-leaf-utilities
    provides: transaction helpers and tokens used by coordinator
provides:
  - OverlayCoordinator base class with orchestrated startup sequence
  - ScreenCapture.captureScreen() shared utility returning CGImage
  - CoordinateConverter rect conversion methods (appKitRectToCG, cgRectToAppKit)
  - OverlayWindowProtocol for type-safe access to shared window methods
affects: [14-02 (Ruler/AlignmentGuides subclassing), 15-window-base]

# Tech tracking
tech-stack:
  added: []
  patterns: [base-class coordinator with overridable hooks, protocol-based window abstraction]

key-files:
  created:
    - swift/Ruler/Sources/Utilities/OverlayCoordinator.swift
    - swift/Ruler/Sources/Utilities/ScreenCapture.swift
  modified:
    - swift/Ruler/Sources/Utilities/CoordinateConverter.swift

key-decisions:
  - "Class-based coordinator (not protocol) for shared stored state (windows, timers, flags)"
  - "OverlayWindowProtocol as lightweight protocol for base to call common window methods without downcasting to concrete types"
  - "resetCommandState() hook for subclass-specific state reset (e.g. AlignmentGuides color/direction)"
  - "Warmup capture moved into run() sequence rather than staying in @raycast entry point"

patterns-established:
  - "Orchestrated startup: warmup -> permissions -> capture -> windows -> run loop, enforced by base"
  - "Hook-based customization: subclasses override captureAllScreens, createWindow, wireCallbacks, activateWindow"

# Metrics
duration: 2min 27s
completed: 2026-02-17
---

# Phase 14 Plan 01: Coordinator Base Summary

**OverlayCoordinator base class with orchestrated startup sequence, ScreenCapture utility, and CoordinateConverter rect methods**

## Performance

- **Duration:** 2min 27s
- **Started:** 2026-02-17T08:50:03Z
- **Completed:** 2026-02-17T08:52:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created OverlayCoordinator base class encapsulating the full startup sequence with overridable hooks for command-specific behavior
- Extracted ScreenCapture.captureScreen() as a shared utility replacing inline capture code in both AlignmentGuides and EdgeDetector
- Added appKitRectToCG() and cgRectToAppKit() rect conversions to CoordinateConverter alongside existing point methods
- Defined OverlayWindowProtocol enabling the base to call showInitialState(), collapseHintBar(), and deactivate() without knowing concrete window types

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ScreenCapture utility and extend CoordinateConverter** - `bbb182e` (feat)
2. **Task 2: Create OverlayCoordinator base class** - `6410e49` (feat)

## Files Created/Modified
- `swift/Ruler/Sources/Utilities/OverlayCoordinator.swift` - Base class with run(), handleExit(), handleFirstMove(), setupSignalHandler(), resetInactivityTimer(), and overridable hooks
- `swift/Ruler/Sources/Utilities/ScreenCapture.swift` - Shared screen capture utility using CoordinateConverter.appKitRectToCG()
- `swift/Ruler/Sources/Utilities/CoordinateConverter.swift` - Added appKitRectToCG() and cgRectToAppKit() rect conversion methods

## Decisions Made
- Used a class (not protocol/composition) for OverlayCoordinator since both coordinators need shared stored state (windows array, timers, flags, firstMoveReceived)
- Defined OverlayWindowProtocol as a lightweight protocol with just the methods the base needs (showInitialState, collapseHintBar, deactivate, targetScreen) -- avoids casting to concrete types
- Added resetCommandState() as a hook for AlignmentGuides to reset currentStyle/currentDirection between runs
- Warmup capture (1x1 pixel cold-start absorber) moved from the @raycast entry functions into run() itself, keeping the full startup sequence in one place
- wireCallbacks() defaults to no-op since onActivate is typed to the specific window class -- subclasses wire all their callbacks in their override

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- OverlayCoordinator, ScreenCapture, and CoordinateConverter rect methods are ready for consumption
- Plan 14-02 will refactor Ruler.swift and AlignmentGuides.swift to subclass OverlayCoordinator
- Both window classes will need to conform to OverlayWindowProtocol (already satisfy the interface)

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 14-coordinator-base*
*Completed: 2026-02-17*
