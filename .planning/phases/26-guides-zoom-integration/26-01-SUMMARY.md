---
phase: 26-guides-zoom-integration
plan: 01
subsystem: alignment-guides
tags: [zoom, coordinate-conversion, capture-space, guide-lines]

# Dependency graph
requires:
  - phase: 24-zoom-transform-infrastructure
    provides: ZoomState, windowPointToCapturePoint, capturePointToWindowPoint, contentLayer, handleZoomToggle, updateZoomPan
  - phase: 25-measure-zoom-integration
    provides: zoomDidChange() hook in OverlayWindow, capture-space storage pattern
provides:
  - Zoom-aware Alignment Guides: preview line, placement, hover-remove, existing line rendering
  - Capture-space guide storage with window-space rendering in GuideLine and GuideLineManager
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [capture-space storage with window-space rendering applied to guide lines]

key-files:
  created: []
  modified:
    - swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/GuideLine.swift
    - swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/GuideLineManager.swift
    - swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesWindow.swift

key-decisions:
  - "GuideLine stores capturePosition (renamed from position), derives renderPosition via zoom conversion"
  - "GuideLineManager accepts capture-space points for all operations, converts to window-space for rendering"
  - "Pill displays capturePosition value (true screen coordinate) regardless of zoom level"
  - "Hit testing threshold is zoom-adjusted: 5px screen-space / zoomScale for capture-space comparison"
  - "updatePreview and cycleStyle take dual points (capture + window) to serve both coordinate needs"
  - "toggleDirection takes windowPoint for pill positioning in window-space"

patterns-established:
  - "Dual-point API: methods that need both capture-space logic and window-space UI positioning accept both coordinate spaces"

requirements-completed: [GUID-01, GUID-02, GUID-03, GUID-04]

# Metrics
duration: 5min
completed: 2026-03-06
---

# Phase 26 Plan 01: Guides Zoom Integration Summary

**Zoom-aware coordinate conversion for preview line, guide placement, hover-to-remove, and existing line rendering in Alignment Guides**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-06
- **Completed:** 2026-03-06
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- GuideLine stores positions in capture-space (`capturePosition`) and renders in window-space via `renderPosition(zoomState:)` conversion
- GuideLineManager tracks zoom state and accepts capture-space points for all operations
- Preview line follows cursor at correct screen coordinate while zoomed
- Placed guide lines render at correct positions when zoom level changes via `updateRenderPosition`
- Hover-to-remove hit testing uses zoom-adjusted threshold (5px screen-space / zoom scale)
- Position pill displays capture-space values (same coordinate at any zoom for same screen position)
- AlignmentGuidesWindow converts all mouse coordinates to capture-space before passing to GuideLineManager
- `zoomDidChange()` override triggers guide line repositioning on zoom/pan changes

## Files Modified
- `GuideLine.swift` — Renamed `position` to `capturePosition`, added `renderPosition(zoomState:)`, `updateRenderPosition(zoomState:screenSize:)`, updated `update()` and `layoutPill()` for dual capture/window-space, updated `shrinkToPoint` to accept `renderPos`
- `GuideLineManager.swift` — Added `zoomState` property, updated `updatePreview` / `cycleStyle` / `toggleDirection` to dual-point APIs, zoom-adjusted hover threshold, `updateForZoom()` for bulk repositioning, `findNearestLine` uses `capturePosition`, simplified `removeLine`
- `AlignmentGuidesWindow.swift` — Added `capturePoint(from:)` helper, converted `handleMouseMoved` / `mouseDown` / `showInitialState` / `activate` to capture-space, added `zoomDidChange()` override, syncs zoom state on activation

## Decisions Made
- Used dual-point API pattern (capturePoint + windowPoint) where methods need both coordinate spaces
- Simplified `removeLine` to drop unused clickPoint parameter (shrinkToPoint not currently called)
- Preview pill cursorAlongAxis uses window-space for correct visual positioning while capturePosition is used for displayed values

## Deviations from Plan
- `removeLine` simplified to not require click point (shrink animation not wired in current codebase)
- `toggleDirection` and `cycleStyle` take window-space point directly instead of dual capture+window (manager derives what it needs internally)

## Issues Encountered
None

## Self-Check: PASSED
All 3 modified files exist. `swift build` compiles without errors. `capturePosition` in GuideLine, `zoomState` in GuideLineManager, `zoomDidChange` override in AlignmentGuidesWindow all verified.

---
*Phase: 26-guides-zoom-integration*
*Completed: 2026-03-06*
