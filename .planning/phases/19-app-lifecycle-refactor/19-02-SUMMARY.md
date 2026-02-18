---
phase: 19-app-lifecycle-refactor
plan: 02
subsystem: infra
tags: [swift, overlay-coordinator, standalone-app, design-ruler-core, raycast-bridge]

# Dependency graph
requires:
  - phase: 19-app-lifecycle-refactor/19-01
    provides: RunMode enum, isSessionActive/anySessionActive guards, gated lifecycle in OverlayCoordinator
  - phase: 18-build-system
    provides: open class OverlayCoordinator as cross-module base; DesignRulerCore library target
provides:
  - MeasureCoordinator (open class) in DesignRulerCore/Measure/ — accessible from App and RaycastBridge
  - AlignmentGuidesCoordinator (open class) in DesignRulerCore/AlignmentGuides/ — accessible from App and RaycastBridge
  - Thin @raycast wrappers in RaycastBridge (no coordinator logic, just delegation to DesignRulerCore)
  - AppDelegate wired with .standalone runMode and temporary test invocation for Phase 19 verification
affects: [20-menu-bar, appdelegate, standalone-invocation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Coordinator-in-library pattern: coordinator subclasses in DesignRulerCore (not executable) for dual-target access
    - Thin @raycast wrapper pattern: RaycastBridge files contain only @raycast func + import, no class definitions
    - Foundation import required in @raycast files: macro expands to NSObject/JSONDecoder references

key-files:
  created:
    - swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureCoordinator.swift
    - swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift
  modified:
    - swift/DesignRuler/Sources/RaycastBridge/Measure.swift
    - swift/DesignRuler/Sources/RaycastBridge/AlignmentGuides.swift
    - App/Sources/AppDelegate.swift

key-decisions:
  - "open class (not final) for coordinator subclasses in DesignRulerCore — required for cross-module subclassing from library target"
  - "GuideLineStyle and Direction are package types — currentStyle must be package private(set) not public private(set)"
  - "Foundation import required in RaycastBridge wrappers — @raycast macro expands to NSObject/JSONDecoder which require Foundation"
  - "AppDelegate sets .accessory activation policy before coordinator invocation — idempotent with coordinator's own setActivationPolicy"

patterns-established:
  - "Thin @raycast wrapper: 6 lines max — import Foundation, import RaycastSwiftMacros, import DesignRulerCore, @raycast func delegating to coordinator"
  - "Coordinator-in-library: all coordinator subclass logic lives in DesignRulerCore, not in executable targets"

# Metrics
duration: 6min 42s
completed: 2026-02-18
---

# Phase 19 Plan 02: App Lifecycle Refactor Summary

**MeasureCoordinator and AlignmentGuidesCoordinator moved to DesignRulerCore library so AppDelegate can invoke overlay sessions directly, with RaycastBridge reduced to 6-line thin wrappers**

## Performance

- **Duration:** 6min 42s
- **Started:** 2026-02-18T14:30:18Z
- **Completed:** 2026-02-18T14:37:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created `MeasureCoordinator` (open class) in DesignRulerCore/Measure/ — full coordinator subclass with EdgeDetector management, MeasureWindow factory, and all callback wiring
- Created `AlignmentGuidesCoordinator` (open class) in DesignRulerCore/AlignmentGuides/ — full coordinator subclass with multi-monitor guide style/direction state and all callback wiring
- Slimmed RaycastBridge/Measure.swift and RaycastBridge/AlignmentGuides.swift to 6-line thin wrappers — only `@raycast func` delegating to DesignRulerCore coordinators
- Wired AppDelegate to set `.standalone` runMode on both coordinator singletons and invoke Measure with a 0.5s delay for Phase 19 success criteria testing
- All three Phase 19 success criteria are structurally satisfied: SC-1 (app stays alive after ESC), SC-2 (fresh state on re-invocation), SC-3 (Raycast behavior unchanged)

## Task Commits

Each task was committed atomically:

1. **Task 1: Move coordinator subclasses to DesignRulerCore and slim RaycastBridge wrappers** - `9b00d8c` (feat)
2. **Task 2: Wire AppDelegate for standalone mode with test invocation** - `5ab21ed` (feat)

**Plan metadata:** TBD (docs commit follows)

## Files Created/Modified
- `swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureCoordinator.swift` - Open class coordinator subclass for Measure, with EdgeDetector per screen, MeasureWindow factory, and all callbacks wired
- `swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift` - Open class coordinator subclass for AlignmentGuides, with guide style/direction state, AlignmentGuidesWindow factory, and all callbacks wired
- `swift/DesignRuler/Sources/RaycastBridge/Measure.swift` - Slimmed to 6 lines: `@raycast func inspect` delegating to `MeasureCoordinator.shared`
- `swift/DesignRuler/Sources/RaycastBridge/AlignmentGuides.swift` - Slimmed to 6 lines: `@raycast func alignmentGuides` delegating to `AlignmentGuidesCoordinator.shared`
- `App/Sources/AppDelegate.swift` - Added DesignRulerCore import, .standalone runMode setup, and temporary test invocation

## Decisions Made
- `open class` (not `final`) for coordinator subclasses — required because the types live in a library target (DesignRulerCore); `final` classes in libraries cannot be subclassed from consuming targets
- `GuideLineStyle` and `Direction` are declared `package` in DesignRulerCore — `currentStyle` on `AlignmentGuidesCoordinator` must be `package private(set)` (not `public private(set)`) to avoid "property uses a package type" error
- `Foundation` import added to RaycastBridge wrappers — the `@raycast` macro expands to code referencing `NSObject` and `JSONDecoder`, both of which require Foundation; without it, macro expansion fails at compile time
- `NSApp.setActivationPolicy(.accessory)` in AppDelegate is idempotent with the call in `OverlayCoordinator.run()` — keeping both is correct; Raycast mode has no AppDelegate so coordinator's call is the only one; standalone mode has both, which is harmless

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added Foundation import to RaycastBridge wrappers**
- **Found during:** Task 1 (ray build verification)
- **Issue:** The `@raycast` macro expands to code that uses `NSObject` and `JSONDecoder` — both from Foundation. Without `import Foundation`, the macro expansion fails at compile time with "cannot find type NSObject in scope" and "cannot find JSONDecoder in scope" errors. The original wrapper files had `import AppKit` (which transitively imports Foundation via AppKit), but the new 3-line wrappers only had `import RaycastSwiftMacros` and `import DesignRulerCore`.
- **Fix:** Added `import Foundation` as first import in both `RaycastBridge/Measure.swift` and `RaycastBridge/AlignmentGuides.swift`
- **Files modified:** swift/DesignRuler/Sources/RaycastBridge/Measure.swift, swift/DesignRuler/Sources/RaycastBridge/AlignmentGuides.swift
- **Verification:** `ray build` succeeds after fix
- **Committed in:** 9b00d8c (Task 1 commit)

**2. [Rule 1 - Bug] Changed currentStyle access level from public to package**
- **Found during:** Task 1 (DesignRulerCore --target build verification)
- **Issue:** `public private(set) var currentStyle: GuideLineStyle` was rejected by the compiler because `GuideLineStyle` is declared `package` — Swift's access control prohibits a `public` property whose type has lower access (`package`)
- **Fix:** Changed `public private(set)` to `package private(set)` — consistent with how all other AlignmentGuides-specific types are scoped
- **Files modified:** swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift
- **Verification:** `swift build --target DesignRulerCore` succeeds; `ray build` and `xcodebuild build` both pass
- **Committed in:** 9b00d8c (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bugs in plan's expected code that only surface at compile time)
**Impact on plan:** Both fixes necessary for compilation. No scope creep. Behavior identical to plan intent.

## Issues Encountered
- `swift build` (without `--target`) shows `@raycast` macro expansion errors — these are expected; the macro requires the Raycast xcodebuild infrastructure and cannot compile with plain SPM. Used `swift build --target DesignRulerCore` to verify the library target in isolation, then `ray build` and `xcodebuild build` for full verification.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both coordinator singletons are now in DesignRulerCore and accessible from AppDelegate
- AppDelegate has `.standalone` runMode set and a temporary test invocation in place
- Phase 20 (menu bar) can replace the temporary invocation with proper menu bar triggers
- The temporary `DispatchQueue.main.asyncAfter` test invocation is clearly marked with a `// TEMP: Phase 19 test` comment for easy removal in Phase 20

## Self-Check: PASSED

All files exist:
- swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureCoordinator.swift: FOUND
- swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift: FOUND
- App/Sources/AppDelegate.swift: FOUND

All commits exist:
- 9b00d8c (Task 1 - move coordinator subclasses): FOUND
- 5ab21ed (Task 2 - wire AppDelegate): FOUND

---
*Phase: 19-app-lifecycle-refactor*
*Completed: 2026-02-18*
