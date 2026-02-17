---
phase: 14-coordinator-base
plan: 02
subsystem: architecture
tags: [swift, refactoring, coordinator, subclass, lifecycle-dedup]

# Dependency graph
requires:
  - phase: 14-coordinator-base
    plan: 01
    provides: OverlayCoordinator base class, ScreenCapture utility, OverlayWindowProtocol
provides:
  - Ruler as thin OverlayCoordinator subclass (command-specific factory + EdgeDetector capture)
  - AlignmentGuides as thin OverlayCoordinator subclass (style/direction state + spacebar/tab handlers)
  - EdgeDetector delegating to ScreenCapture.captureScreen() for screen capture
  - Both window types conforming to OverlayWindowProtocol
affects: [15-window-base]

# Tech tracking
tech-stack:
  added: []
  patterns: [subclass-as-factory pattern for coordinator, ObjectIdentifier keying for per-screen detector storage]

key-files:
  modified:
    - swift/Ruler/Sources/Ruler.swift
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift
    - swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift
    - swift/Ruler/Sources/RulerWindow.swift
    - swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift

key-decisions:
  - "Ruler stores detectors in [ObjectIdentifier: EdgeDetector] dictionary for retrieval during window creation"
  - "wireCallbacks() fully overridden by each subclass since onActivate is typed to concrete window class"
  - "AlignmentGuides uses base default captureAllScreens() since it needs no command-specific capture logic"
  - "activateWindow() calls super for common logic then adds command-specific activation (Ruler passes firstMoveAlreadyReceived, AlignmentGuides passes style+direction)"

patterns-established:
  - "Subclass-as-factory: subclass overrides captureAllScreens, createWindow, wireCallbacks, activateWindow"
  - "Callback wiring: subclass wires all callbacks including standard 4 plus any command-specific ones"

# Metrics
duration: 2min 28s
completed: 2026-02-17
---

# Phase 14 Plan 02: Coordinator Wiring Summary

**Ruler and AlignmentGuides refactored as thin OverlayCoordinator subclasses with zero duplicated lifecycle code**

## Performance

- **Duration:** 2min 28s
- **Started:** 2026-02-17T08:54:48Z
- **Completed:** 2026-02-17T08:57:16Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Rewrote Ruler.swift as a 65-line OverlayCoordinator subclass (down from 170 lines) with only EdgeDetector capture, correction mode, and window factory
- Rewrote AlignmentGuides.swift as an 80-line OverlayCoordinator subclass (down from 205 lines) with only style/direction state, spacebar/tab handlers, and window factory
- Refactored EdgeDetector.capture() to delegate to ScreenCapture.captureScreen() instead of inline CGWindowListCreateImage with manual coordinate conversion
- Added OverlayWindowProtocol conformance to both RulerWindow and AlignmentGuidesWindow

## Task Commits

Each task was committed atomically:

1. **Task 1: Refactor Ruler.swift and EdgeDetector.swift to use shared base and capture** - `308f0d3` (refactor)
2. **Task 2: Refactor AlignmentGuides.swift to use shared base** - `055bd28` (refactor)

## Files Created/Modified
- `swift/Ruler/Sources/Ruler.swift` - Thin OverlayCoordinator subclass with EdgeDetector capture and RulerWindow factory
- `swift/Ruler/Sources/AlignmentGuides/AlignmentGuides.swift` - Thin OverlayCoordinator subclass with style/direction state and spacebar/tab handlers
- `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift` - capture() now delegates to ScreenCapture.captureScreen()
- `swift/Ruler/Sources/RulerWindow.swift` - Added OverlayWindowProtocol conformance
- `swift/Ruler/Sources/AlignmentGuides/AlignmentGuidesWindow.swift` - Added OverlayWindowProtocol conformance

## Decisions Made
- Used `ObjectIdentifier(screen)` as dictionary key for per-screen EdgeDetector storage in Ruler, enabling retrieval during createWindow() without storing captures as a class property
- Each subclass fully overrides wireCallbacks() since onActivate is typed to the concrete window class (RulerWindow vs AlignmentGuidesWindow)
- AlignmentGuides relies on base's default captureAllScreens() implementation since it needs no command-specific capture logic (just ScreenCapture.captureScreen)
- activateWindow() uses super.activateWindow() for common logic (timer reset, guard, deactivate old, makeKey) then adds command-specific activation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 14 complete: both commands share all lifecycle code via OverlayCoordinator
- handleExit, handleFirstMove, setupSignalHandler, resetInactivityTimer each appear exactly once (in OverlayCoordinator.swift)
- captureScreen logic appears exactly once (in ScreenCapture.swift, called by EdgeDetector and base)
- Ready for Phase 15 (window base) which can extract shared window setup patterns

## Self-Check: PASSED

All files exist, all commits verified.

---
*Phase: 14-coordinator-base*
*Completed: 2026-02-17*
