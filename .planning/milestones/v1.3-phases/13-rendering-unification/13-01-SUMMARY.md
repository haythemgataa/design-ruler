---
phase: 13-rendering-unification
plan: 01
subsystem: ui
tags: [swift, pill-renderer, calayer, cashapelayer, catextlayer, quartz-core]

# Dependency graph
requires:
  - phase: 12-leaf-utilities
    provides: "DesignTokens enum with Pill, Shadow, Color, Animation constants"
provides:
  - "PillRenderer enum with 3 factory methods (makeDimensionPill, makePositionPill, makeSelectionPill)"
  - "Shared squirclePath and sectionPath continuous-corner path generators"
  - "Shared labelText and valueText attributed string formatters"
  - "Public makeDesignFont for SF Pro Semibold with 8 OpenType tags"
  - "Public applyCircleShadow preset for ColorCircleIndicator"
affects: [13-rendering-unification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pill factory returns struct with pre-configured layer hierarchy"
    - "Shadow applied automatically inside factory (not by caller)"
    - "Caseless enum namespace matching DesignTokens pattern"

key-files:
  created:
    - swift/Ruler/Sources/Rendering/PillRenderer.swift
  modified: []

key-decisions:
  - "makeDesignFont is public so SelectionOverlay can create size-11 font variant"
  - "SelectionPill factory sets font to size-11 NSFont with fontSize=12 override matching existing SelectionOverlay behavior"
  - "applyCircleShadow is a separate public preset (distinct shadow values from pill shadow)"

patterns-established:
  - "PillRenderer.makeDimensionPill pattern: factory returns struct, caller only sets position/content"
  - "PillRenderer.squirclePath for all continuous-corner paths"
  - "PillRenderer.labelText/valueText for all pill text formatting"

# Metrics
duration: 2min 18s
completed: 2026-02-16
---

# Phase 13 Plan 01: PillRenderer Summary

**PillRenderer pill factory with 3 variant factories, shared squircle paths, text formatters, and shadow presets for unified pill rendering**

## Performance

- **Duration:** 2min 18s
- **Started:** 2026-02-16T22:40:47Z
- **Completed:** 2026-02-16T22:43:05Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Created PillRenderer.swift with 3 factory methods returning fully configured layer hierarchy structs (DimensionPill, PositionPill, SelectionPill)
- Unified squirclePath (uniform radius) and sectionPath (independent left/right radii) as public static methods
- Unified labelText and valueText formatters with identical output to CrosshairView and GuideLine originals
- Verified all factories produce visually identical layer configurations to current inline implementations

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PillRenderer.swift with pill factory and shared rendering code** - `db81c7f` (feat)
2. **Task 2: Verify PillRenderer output matches existing implementations** - no changes needed (verification only)

## Files Created/Modified
- `swift/Ruler/Sources/Rendering/PillRenderer.swift` - Caseless enum with 3 pill factories, path generators, text formatters, font factory, and shadow presets

## Decisions Made
- makeDesignFont is public (not private) so SelectionOverlay can create its size-11 font variant
- SelectionPill factory preserves the intentional font=size11/fontSize=12 override from existing SelectionOverlay
- applyCircleShadow remains a separate named preset with distinct shadow values (opacity 0.25 vs 1.0 for pills)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- PillRenderer.swift compiles and is ready for Plan 02 to wire CrosshairView, GuideLine, SelectionOverlay, and ColorCircleIndicator as consumers
- No existing files were modified; all consumer wiring deferred to Plan 02

## Self-Check: PASSED

All files and commits verified:
- FOUND: swift/Ruler/Sources/Rendering/PillRenderer.swift
- FOUND: commit db81c7f (Task 1)

---
*Phase: 13-rendering-unification*
*Completed: 2026-02-16*
