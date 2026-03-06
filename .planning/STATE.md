# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-05)

**Core value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.
**Current focus:** Phase 27 — Zoom UX Polish (v2.1)

## Current Position

Phase: 27 of 27 (Zoom UX Polish)
Plan: 1 of 1 in current phase
Status: Plan Complete
Last activity: 2026-03-06 — Completed 27-01 (Zoom level hint bar feedback)

Progress: [███████░░░] 35% (v2.1)

## Performance Metrics

**Velocity (v1.0):**
- Total plans completed: 5 | Average: 2min | Total: 0.2 hours

**Velocity (v1.1):**
- Total plans completed: 4 | Average: 13min | Total: ~53min

**Velocity (v1.2):**
- Total plans completed: 9 | Average: 2min 38s | Total: ~24min 57s

**Velocity (v1.3):**
- Total plans completed: 10 | Average: 2min 53s | Total: ~28min 49s

**Velocity (v2.0):**
- Total plans completed: 14 | Average: ~4min | Total: ~56min

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table.

- [24-01] ZoomState is a value type struct for per-window independent zoom (SHUX-02)
- [24-01] Coordinate mapping via package-level free functions for cleaner call sites
- [24-01] Pan offset in capture-space, translate applied in scaled-space via CATransform3DTranslate
- [24-02] Z key handled at OverlayWindow base level because zoom is shared infrastructure
- [24-02] Content layer hosted inside dedicated bgView for clean NSView-to-CALayer ownership
- [24-02] Zoom reset uses direct OverlayWindow cast rather than protocol extension (simpler)
- [25-01] captureScreenPoint/capturePoint helpers in MeasureWindow for DRY coordinate conversion
- [25-01] SelectionOverlay dual-rect pattern: captureRect (canonical) + rect (derived for rendering)
- [25-01] zoomDidChange() hook in OverlayWindow base for subclass zoom reactions
- [25-01] Selection layers stay in screen-space with manual coordinate conversion (consistent stroke width)
- [25-02] Three-phase DispatchWorkItem chain for peek pan (pan-out 0.2s + hold 0.6s + return 0.2s)
- [25-02] animatePanOffset helper on OverlayWindow for reusable smooth pan transitions
- [25-02] Shift+arrow peeks in the actual edge direction being un-skipped, not the arrow direction
- [27-01] ZoomKeyCap is standalone SwiftUI view (not reusing KeyCap) for clean flash animation with ZStack
- [27-01] Scale+opacity transition instead of scale+blur (SwiftUI AnyTransition has no .blur member)
- [27-01] AlignmentGuides fallback pill positioned below cursor (no dimension pill to anchor to)

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-06
Stopped at: Completed 27-01-PLAN.md (Zoom level hint bar feedback)
Resume: Phase 27 complete, proceed to next phase or manual testing
