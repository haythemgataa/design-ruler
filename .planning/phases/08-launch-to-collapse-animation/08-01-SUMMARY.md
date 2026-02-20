---
phase: 08-launch-to-collapse-animation
plan: 01
subsystem: ui
tags: [nsanimationcontext, crossfade, hint-bar, accessibility, reduce-motion]

# Dependency graph
requires:
  - phase: 07-hint-bar-visual-redesign
    provides: "Expanded + collapsed bar states, BarState enum, glass panels"
provides:
  - "animateToCollapsed() crossfade in HintBarView"
  - "collapseHintBar() trigger chain through RulerWindow and Ruler"
  - "Accessibility-aware instant collapse for Reduce Motion users"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "NSAnimationContext.runAnimationGroup for coordinated crossfade animations"
    - "isAnimatingCollapse guard to prevent animation overlap between collapse and slide"
    - "Pre-set alphaValue to 0 before unhiding to prevent single-frame flash"

key-files:
  created: []
  modified:
    - "swift/Ruler/Sources/Rendering/HintBarView.swift"
    - "swift/Ruler/Sources/RulerWindow.swift"
    - "swift/Ruler/Sources/Ruler.swift"

key-decisions:
  - "0.35s easeOut crossfade duration for expanded-to-collapsed transition"
  - "Guard updatePosition() during collapse to prevent slide/collapse animation overlap"
  - "Instant setBarState(.collapsed) when Reduce Motion accessibility setting is enabled"

patterns-established:
  - "Animation overlap prevention via boolean guard (isAnimatingCollapse blocks updatePosition)"
  - "Flash prevention by setting alphaValue=0 before isHidden=false"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 8 Plan 1: Launch-to-Collapse Animation Summary

**NSAnimationContext crossfade from expanded hint bar to collapsed keycap-only bars on first mouse move, with Reduce Motion accessibility fallback**

## Performance

- **Duration:** ~2 min (implementation) + human verification checkpoint
- **Started:** 2026-02-14T16:46:00Z
- **Completed:** 2026-02-14T16:53:00Z
- **Tasks:** 2 (1 auto + 1 human-verify)
- **Files modified:** 3

## Accomplishments

- Added animateToCollapsed() to HintBarView with synchronized NSAnimationContext crossfade (expanded fades out, collapsed panels fade in, 0.35s easeOut)
- Wired collapse trigger chain: Ruler.handleFirstMove() -> RulerWindow.collapseHintBar() -> HintBarView.animateToCollapsed()
- Prevented animation overlap via isAnimatingCollapse guard blocking updatePosition() during collapse
- Prevented single-frame flash by pre-setting collapsed panel alphaValue to 0 before unhiding
- Added Reduce Motion accessibility check for instant (non-animated) collapse
- Human-verified: smooth crossfade, no flash, slide animation works after collapse, keycap press animations preserved

## Task Commits

Each task was committed atomically:

1. **Task 1: Add animateToCollapsed() and wire trigger through RulerWindow and Ruler** - `731bae9` (feat)
2. **Task 2: Verify collapse animation visually** - checkpoint:human-verify (approved, no commit)

## Files Created/Modified

- `swift/Ruler/Sources/Rendering/HintBarView.swift` - Added animateToCollapsed() method with NSAnimationContext crossfade, isAnimatingCollapse guard in updatePosition()
- `swift/Ruler/Sources/RulerWindow.swift` - Added collapseHintBar() public method forwarding to hintBarView
- `swift/Ruler/Sources/Ruler.swift` - Added activeWindow?.collapseHintBar() call in handleFirstMove()

## Decisions Made

- Used 0.35s easeOut for the crossfade duration -- long enough to be noticeable, short enough to not delay inspection
- Guard updatePosition() with isAnimatingCollapse to prevent slide animation from fighting the collapse crossfade (research Pitfall 2)
- Pre-set alphaValue to 0 on collapsed panels before unhiding to prevent single-frame flash (research Pitfall 3)
- Instant setBarState(.collapsed) fallback when NSWorkspace.shared.accessibilityDisplayShouldReduceMotion is true

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- v1.1 Hint Bar Redesign milestone is complete
- All hint bar states (expanded, collapsed) working with glass panels, keycap animations, slide repositioning, and launch-to-collapse crossfade
- Extension is feature-complete for the v1.1 scope

## Self-Check: PASSED

All files verified present. Commit 731bae9 verified in git log.

---
*Phase: 08-launch-to-collapse-animation*
*Completed: 2026-02-14*
