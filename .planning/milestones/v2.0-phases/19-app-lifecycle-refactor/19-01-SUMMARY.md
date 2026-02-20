---
phase: 19-app-lifecycle-refactor
plan: 01
subsystem: infra
tags: [swift, overlay-coordinator, lifecycle, run-mode, session-guard]

# Dependency graph
requires:
  - phase: 18-build-system
    provides: DesignRulerCore open class OverlayCoordinator as cross-module base
provides:
  - RunMode enum (.raycast / .standalone) in OverlayCoordinator
  - isSessionActive per-coordinator session guard
  - anySessionActive cross-coordinator session guard
  - Gated app.run() (only in .raycast mode)
  - Gated NSApp.terminate(nil) (only in .raycast mode)
  - CursorManager.restore() at start of every new session
  - Full window/state teardown in handleExit() without killing process
affects: [20-menu-bar, appdelegate, standalone-invocation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - RunMode enum pattern for dual-context lifecycle gating
    - Cross-coordinator anySessionActive static guard for mutual exclusion
    - Session guard ordering: guards first (no side effects), then restore(), then mark active

key-files:
  created: []
  modified:
    - swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift

key-decisions:
  - "Default runMode is .raycast — zero changes to RaycastBridge files; existing Raycast behavior identical"
  - "isSessionActive = false set as first line of handleExit() — allows instant re-invocation"
  - "CursorManager.restore() placed AFTER guards in run() — never runs mid-session on rejected re-invocations"
  - "orderOut(nil) added before close() in handleExit() — instant visual vanish per user requirement"
  - "sigTermSource?.cancel() in handleExit() — prevents stale SIGTERM handler calling handleExit() on next session"
  - "setActivationPolicy(.accessory) kept in run() — Raycast binary has no AppDelegate, removal would break Raycast"

patterns-established:
  - "RunMode gating: if runMode == .raycast { process-lifetime-call } for all app.run()/terminate() calls"
  - "Session guard ordering in run(): guards first → restore() → mark active — prevents side effects on rejection"
  - "handleExit() teardown: clear flags first → restore cursor → invalidate timers → cancel signals → close windows → gate terminate"

# Metrics
duration: 1min 46s
completed: 2026-02-18
---

# Phase 19 Plan 01: App Lifecycle Refactor Summary

**RunMode enum and dual-context session lifecycle added to OverlayCoordinator — coordinator can now be invoked from a persistent app without starting or killing the event loop**

## Performance

- **Duration:** 1min 46s
- **Started:** 2026-02-18T14:26:17Z
- **Completed:** 2026-02-18T14:28:03Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added `RunMode` enum (`.raycast` / `.standalone`) to `OverlayCoordinator.swift` — gates both `app.run()` and `NSApp.terminate(nil)` behind the mode check
- Added `isSessionActive` and `anySessionActive` guards that prevent same-coordinator and cross-coordinator overlapping invocations
- Added `CursorManager.shared.restore()` at session start (after guards) to prevent cursor state leaks between sessions
- Rewrote `handleExit()` to do full state teardown without killing the process in standalone mode (clears flags first, `orderOut(nil)` before `close()`, cancels sigTermSource, gates `NSApp.terminate`)
- Both `ray build` and `xcodebuild build` pass with zero changes to RaycastBridge files

## Task Commits

Each task was committed atomically:

1. **Task 1: Add RunMode enum, session guard, and gated lifecycle to OverlayCoordinator** - `53c1a30` (feat)

**Plan metadata:** TBD (docs commit follows)

## Files Created/Modified
- `swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift` - Added RunMode enum, session guards, gated lifecycle calls, enhanced handleExit()

## Decisions Made
- Default `runMode` is `.raycast` — all existing Raycast bridge code requires zero changes; the singleton coordinators simply never set `runMode`, so they stay `.raycast` and behavior is identical to before
- `isSessionActive = false` is the FIRST line of `handleExit()` — synchronous clearing before any async cleanup ensures instant re-invocation works correctly
- `CursorManager.shared.restore()` placed AFTER the session guards in `run()` — calling it before the guards would unhide the cursor mid-session if a re-invocation is rejected
- `orderOut(nil)` added before `close()` — consistent with "instant vanish" requirement; previously `handleExit()` called `close()` without `orderOut(nil)` first
- `sigTermSource?.cancel()` added to `handleExit()` — prevents dangling SIGTERM handler from calling `handleExit()` again on the next session's coordinator instance
- `setActivationPolicy(.accessory)` kept in `run()` — Raycast binary has no `AppDelegate`; removing it from coordinator would break Raycast mode

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `OverlayCoordinator` is now standalone-aware; `AppDelegate` can set `runMode = .standalone` on coordinator instances and call `run()` without starting a nested event loop
- Phase 20 (menu bar) can wire up the menu bar item and trigger coordinator runs via `runMode = .standalone`
- The `Measure` and `AlignmentGuides` coordinator subclasses remain in `RaycastBridge` (executable); Phase 20 will need to address how `AppDelegate` accesses them (open question from RESEARCH.md #1)

---
*Phase: 19-app-lifecycle-refactor*
*Completed: 2026-02-18*
