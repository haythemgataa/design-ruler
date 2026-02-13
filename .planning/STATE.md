# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-13)

**Core value:** Instant, accurate pixel inspection of anything on screen — zero friction from Raycast invoke to dimension readout.
**Current focus:** Phase 5 - Help Toggle System

## Current Position

Phase: 5 of 5 (Help Toggle System) -- COMPLETE
Plan: 1 of 1 in current phase
Status: All phases complete
Last activity: 2026-02-13 — Phase 5 executed and complete

Progress: [##########] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 2min
- Total execution time: 0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-debug-cleanup | 1 | 2min | 2min |
| 02-cursor-state-machine | 1 | 3min | 3min |
| 03-snap-failure-shake | 1 | 1min | 1min |
| 04-selection-pill-clamping | 1 | 1min | 1min |
| 05-help-toggle-system | 1 | 3min | 3min |

**Recent Trend:**
- Last 5 plans: 01-01 (2min), 02-01 (3min), 03-01 (1min), 04-01 (1min), 05-01 (3min)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Refactor-first strategy — centralize cursor management (Phase 2) before adding features that interact with cursors
- [Roadmap]: Phases 3 and 4 are independent; both depend only on Phase 1 completion
- [Roadmap]: Phase 5 depends on Phase 2 (touches RulerWindow.keyDown, already modified by cursor refactor)
- [01-01]: Removed fputs entirely rather than gating with #if DEBUG (Raycast always builds debug config)
- [01-01]: Timer placed in Ruler (lifecycle coordinator) not RulerWindow (event handler)
- [01-01]: resetInactivityTimer called before app.run() so timer runs on main run loop
- [02-01]: Singleton CursorManager.shared pattern matching existing Ruler.shared convention
- [02-01]: State enum with 4 cases replacing scattered boolean flags for cursor state
- [02-01]: Track own hideCount/pushCount for unconditional restore() on all exit paths
- [02-01]: resetCursorRects stays in CrosshairView (AppKit framework callback exception)
- [03-01]: Used isAdditive=true with relative offsets for shake -- same animation object shared across all 4 layers
- [03-01]: Chained shake into existing remove(animated:true) via CATransaction completion block
- [03-01]: Applied shake to all 4 layers even though pill is invisible on snap failure -- harmless and future-proof
- [04-01]: 4px clampMargin derived from shadowRadius(3) + abs(shadowOffset.height)(1)
- [04-01]: Uniform margin on all sides rather than per-edge shadow extent computation
- [04-01]: Vertical flip threshold changed from hardcoded 8 to clampMargin for consistency
- [05-01]: CAShapeLayer + CATextLayer for transient message instead of SwiftUI hosting -- matches existing pill pattern
- [05-01]: event.characters == "?" for layout-independent detection (US, AZERTY, QWERTZ)
- [05-01]: Duplicate kHintBarDismissedKey constants in both files -- lesser evil than cross-file coupling

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-13
Stopped at: Completed 05-01-PLAN.md (All phases complete)
Resume file: None
