# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-05)

**Core value:** Instant, accurate pixel inspection of anything on screen — zero friction from invoke to dimension readout, whether launched from Raycast or a global hotkey.
**Current focus:** Phase 25 — Measure Zoom Integration (v2.1)

## Current Position

Phase: 25 of 27 (Measure Zoom Integration) -- COMPLETE
Plan: 2 of 2 in current phase
Status: Phase Complete
Last activity: 2026-03-06 — Completed 25-02 (Peek pan for arrow key edge skipping)

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

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-06
Stopped at: Completed 25-02-PLAN.md (Peek pan for arrow key edge skipping) -- Phase 25 complete
Resume: Execute phase 26
