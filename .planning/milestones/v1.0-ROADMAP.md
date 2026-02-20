# Roadmap: Design Ruler Enhancement Milestone

## Overview

This milestone hardens the existing Design Ruler extension with robustness improvements, visual polish, and discoverability features. The work starts with zero-risk cleanup (debug logging, process safety), then tackles the most invasive refactor (cursor management centralization) before adding independent visual enhancements (shake animation, bounds clamping) and finishing with the hint bar toggle system. All 10 requirements are enhancements to an already-functional extension — no architectural rewrites, no new dependencies.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Debug Cleanup and Process Safety** - Gate debug output and add inactivity timeout to prevent zombie processes
- [x] **Phase 2: Cursor State Machine** - Centralize all NSCursor management into a single state-tracked manager
- [x] **Phase 3: Snap Failure Shake** - Shake animation for selection overlays when edge snap fails
- [x] **Phase 4: Selection Pill Clamping** - Clamp selection overlay dimension pill to screen bounds
- [x] **Phase 5: Help Toggle System** - Backspace to dismiss hint bar, "?" to re-enable, with session persistence

## Phase Details

### Phase 1: Debug Cleanup and Process Safety
**Goal**: Production builds produce zero debug output and the process never becomes a zombie
**Depends on**: Nothing (first phase)
**Requirements**: RBST-01, RBST-04
**Success Criteria** (what must be TRUE):
  1. Running the extension in production mode produces no output on stderr
  2. Leaving the extension idle for 10 minutes causes it to exit cleanly without user intervention
  3. After timeout exit, no Ruler processes remain visible in `ps aux`
**Plans:** 1 plan

Plans:
- [x] 01-01-PLAN.md — Remove debug fputs output and add 10-minute inactivity watchdog timer

### Phase 2: Cursor State Machine
**Goal**: Cursor is always correctly restored regardless of how the user exits the overlay
**Depends on**: Phase 1
**Requirements**: RBST-02, RBST-03
**Success Criteria** (what must be TRUE):
  1. All NSCursor push/pop/hide/unhide calls go through CursorManager (no direct NSCursor manipulation outside CursorManager and resetCursorRects)
  2. Pressing ESC during any cursor state (hidden, crosshair, pointing hand) restores cursor to normal system arrow
  3. Force-killing the process via SIGTERM (Raycast shutdown) restores cursor visibility
  4. Cursor is never stuck hidden or stuck as wrong type after exiting the overlay
**Plans:** 1 plan

Plans:
- [x] 02-01-PLAN.md — Create CursorManager state machine, migrate all NSCursor call sites, add SIGTERM handler

### Phase 3: Snap Failure Shake
**Goal**: Users get clear macOS-native feedback when a selection snap fails
**Depends on**: Phase 1
**Requirements**: VFBK-01
**Success Criteria** (what must be TRUE):
  1. When drag-to-select fails to snap to edges, the selection overlay shakes horizontally before fading out
  2. The shake follows macOS convention (login rejection idiom — damped horizontal oscillation)
  3. The shake animation does not cause the overlay to jump to a wrong position after completing
**Plans:** 1 plan

Plans:
- [x] 03-01-PLAN.md — Add shakeAndRemove() to SelectionOverlay and wire into snap failure path

### Phase 4: Selection Pill Clamping
**Goal**: Selection overlay dimension pill is always fully visible regardless of selection position
**Depends on**: Phase 1
**Requirements**: VFBK-02
**Success Criteria** (what must be TRUE):
  1. Creating a selection near any screen edge keeps the dimension pill entirely within screen bounds
  2. Creating a selection in a screen corner keeps the dimension pill visible (not clipped or off-screen)
  3. Pill clamping does not clip drop shadows or other decorative elements
**Plans:** 1 plan

Plans:
- [x] 04-01-PLAN.md — Add screen-bounds clamping to selection pill in layoutPill()

### Phase 5: Help Toggle System
**Goal**: Users can dismiss the hint bar for a clean workspace and rediscover it when needed
**Depends on**: Phase 2
**Requirements**: DISC-01, DISC-02, DISC-03, DISC-04
**Success Criteria** (what must be TRUE):
  1. Pressing backspace dismisses the hint bar and briefly shows "Press ? for help" before auto-fading
  2. Pressing "?" after dismissal brings the hint bar back
  3. Quitting and relaunching remembers the dismissed state (hint bar stays hidden)
  4. Launching with a previously-dismissed hint bar shows "Press ? for help" briefly on startup
  5. The transient "Press ? for help" message auto-fades without user action
**Plans:** 1 plan

Plans:
- [x] 05-01-PLAN.md — Add transient help label, "?" re-enable, and session persistence

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5
(Phases 3 and 4 are independent and could execute in either order after Phase 1)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Debug Cleanup and Process Safety | 1/1 | ✓ Complete | 2026-02-13 |
| 2. Cursor State Machine | 1/1 | ✓ Complete | 2026-02-13 |
| 3. Snap Failure Shake | 1/1 | ✓ Complete | 2026-02-13 |
| 4. Selection Pill Clamping | 1/1 | ✓ Complete | 2026-02-13 |
| 5. Help Toggle System | 1/1 | ✓ Complete | 2026-02-13 |
