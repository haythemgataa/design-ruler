---
phase: 27-zoom-ux-polish
plan: 01
subsystem: ui
tags: [swiftui, core-animation, hint-bar, zoom, keycap, pill-renderer]

requires:
  - phase: 24-zoom-transform-infrastructure
    provides: ZoomState, ZoomLevel enum, Z key handling in OverlayWindow
provides:
  - Z keycap in all hint bar layouts with flash animation
  - Standalone fallback zoom pill for hideHintBar mode
  - flashZoomLevel API on HintBarView and HintBarState
affects: [zoom-ux-polish]

tech-stack:
  added: []
  patterns: [ZoomKeyCap SwiftUI view with scale+opacity flash transition, DispatchWorkItem-based flash timer pattern, fallback pill via PillRenderer CALayers]

key-files:
  created: []
  modified:
    - swift/DesignRuler/Sources/DesignRulerCore/Rendering/HintBarContent.swift
    - swift/DesignRuler/Sources/DesignRulerCore/Rendering/HintBarView.swift
    - swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayWindow.swift
    - swift/DesignRuler/Sources/DesignRulerCore/Measure/CrosshairView.swift
    - swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureWindow.swift
    - swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesWindow.swift

key-decisions:
  - "ZoomKeyCap is a standalone SwiftUI view (not reusing KeyCap) for clean flash animation via ZStack with two text layers"
  - "Flash animation uses scale+opacity transition (not blur -- SwiftUI AnyTransition has no .blur member)"
  - "Fallback pill in AlignmentGuides positioned below cursor (no dimension pill to anchor to)"

patterns-established:
  - "ZoomKeyCap pattern: ZStack with 'Z' base text and conditional flash text, animated via SwiftUI .animation on state change"
  - "HintBarState flash pattern: @Published zoomFlashText with DispatchWorkItem cancellation for rapid-press safety"

requirements-completed: [ZOOM-05, SHUX-01]

duration: 3min
completed: 2026-03-06
---

# Phase 27 Plan 01: Zoom UX Polish - Hint Bar Z Keycap Summary

**Z keycap with scale+opacity flash animation in all hint bar layouts, plus standalone fallback pill for hideHintBar mode**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-06T22:25:24Z
- **Completed:** 2026-03-06T22:29:21Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Z keycap with "Toggle zoom" label in expanded hint bar for both Measure and Alignment Guides modes
- Collapsed hint bar shows Z keycap in both modes (inspect: after shift, guides: after space)
- Z key press flashes zoom level text (x2/x4/x1) with directional scale animation for ~0.5s
- Standalone fallback pill near cursor when hint bar is hidden, auto-fading after 0.5s
- macOS 26+ glass morph path includes Z keycap in both glass and keycap layers

## Task Commits

Each task was committed atomically:

1. **Task 1: Z keycap in hint bar with flash animation** - `2b447e1` (feat)
2. **Task 2: Wire Z key to flash and add standalone fallback pill** - `c74f2cb` (feat)

## Files Created/Modified
- `swift/DesignRuler/Sources/DesignRulerCore/Rendering/HintBarContent.swift` - ZoomKeyCap view, HintBarState flash properties, Z keycap in all 6 layout views
- `swift/DesignRuler/Sources/DesignRulerCore/Rendering/HintBarView.swift` - .zoom KeyID, flashZoomLevel delegation
- `swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayWindow.swift` - Z key wiring to flash/fallback, showZoomFallbackPill hook
- `swift/DesignRuler/Sources/DesignRulerCore/Measure/CrosshairView.swift` - showZoomFlash with temporary pill layers
- `swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureWindow.swift` - showZoomFallbackPill override
- `swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesWindow.swift` - showZoomFallbackPill with cursor-centered pill

## Decisions Made
- ZoomKeyCap is its own SwiftUI view (not reusing KeyCap) because it needs a ZStack with two text layers for the flash animation, which doesn't fit KeyCap's single-symbol architecture
- Used scale+opacity transition instead of scale+blur because SwiftUI's AnyTransition has no .blur member -- the visual effect is similar (text appears to zoom in/out)
- Fallback pill in AlignmentGuides is positioned below cursor (offset -30pt y) since there's no dimension pill to anchor beside

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced .blur transition with .opacity**
- **Found during:** Task 1 (Z keycap flash animation)
- **Issue:** Plan specified `.combined(with: .blur)` on the removal transition, but SwiftUI `AnyTransition` has no `.blur` member
- **Fix:** Replaced with `.opacity` only on the removal path; the scale effect still communicates zoom direction
- **Files modified:** HintBarContent.swift
- **Verification:** Build succeeds
- **Committed in:** 2b447e1

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor -- blur was decorative, scale+opacity still provides clear directional feedback.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Zoom level feedback is complete for both hint bar and hideHintBar modes
- Ready for manual testing of flash animation timing and visual appearance

---
*Phase: 27-zoom-ux-polish*
*Completed: 2026-03-06*
