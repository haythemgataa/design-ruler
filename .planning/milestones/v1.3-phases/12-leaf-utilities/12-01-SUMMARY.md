---
phase: 12-leaf-utilities
plan: 01
subsystem: ui
tags: [swift, design-tokens, catransaction, quartz-core]

# Dependency graph
requires: []
provides:
  - "DesignTokens enum with centralized pill, shadow, color, and animation constants"
  - "BlendMode enum with single source of truth for differenceBlendMode string"
  - "CATransaction.instant {} and .animated(duration:timing:) {} helpers"
affects: [12-leaf-utilities]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Caseless enum namespaces for design constants"
    - "CATransaction extension helpers for animation boilerplate"

key-files:
  created:
    - swift/Ruler/Sources/Utilities/DesignTokens.swift
    - swift/Ruler/Sources/Utilities/TransactionHelpers.swift
  modified: []

key-decisions:
  - "BlendMode is a separate top-level enum (not nested in DesignTokens) per user decision"
  - "CATransaction.animated defaults to easeOut (dominant timing in codebase ~90%)"
  - "Helpers intentionally omit setCompletionBlock support to stay simple"

patterns-established:
  - "DesignTokens.Pill.height pattern for all shared constants"
  - "BlendMode.difference instead of raw string literals"
  - "CATransaction.instant {} instead of begin/setDisableActions/commit"

# Metrics
duration: 1min 23s
completed: 2026-02-16
---

# Phase 12 Plan 01: Leaf Utilities Summary

**DesignTokens and BlendMode enums plus CATransaction helpers as shared foundation for codebase-wide refactoring**

## Performance

- **Duration:** 1min 23s
- **Started:** 2026-02-16T21:43:16Z
- **Completed:** 2026-02-16T21:44:39Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Centralized all repeated pill, shadow, color, and animation constants into DesignTokens enum with nested namespaces
- Created BlendMode.difference as the single source of truth for the "differenceBlendMode" compositing filter string
- Added CATransaction.instant {} and .animated(duration:timing:) {} helpers to eliminate transaction boilerplate

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DesignTokens.swift and BlendMode enum** - `8dcde60` (feat)
2. **Task 2: Create TransactionHelpers.swift** - `38507f9` (feat)

## Files Created/Modified
- `swift/Ruler/Sources/Utilities/DesignTokens.swift` - Caseless enums: DesignTokens (Pill, Shadow, Color, Animation) and BlendMode
- `swift/Ruler/Sources/Utilities/TransactionHelpers.swift` - CATransaction extension with instant and animated helpers

## Decisions Made
- BlendMode is a separate top-level caseless enum, not nested in DesignTokens, per prior user decision
- CATransaction.animated defaults to .easeOut since ~90% of animated transactions in the codebase use that timing
- Helpers intentionally do not support setCompletionBlock; those blocks remain raw begin/commit

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Both utility files compile and are ready for Plan 02's codebase-wide sweep to replace hardcoded values with DesignTokens/BlendMode references and CATransaction helpers
- No existing files were modified; Plan 02 handles all wiring

## Self-Check: PASSED

All files and commits verified:
- FOUND: swift/Ruler/Sources/Utilities/DesignTokens.swift
- FOUND: swift/Ruler/Sources/Utilities/TransactionHelpers.swift
- FOUND: commit 8dcde60 (Task 1)
- FOUND: commit 38507f9 (Task 2)

---
*Phase: 12-leaf-utilities*
*Completed: 2026-02-16*
