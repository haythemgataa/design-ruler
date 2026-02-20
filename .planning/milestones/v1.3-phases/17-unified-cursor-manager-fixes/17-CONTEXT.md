# Phase 17: Unified cursor manager fixes - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Audit cursor management code post-v1.3 unification. The cursor bugs originally motivating this phase were caused by an external app, not our code. Scope is now: verify correctness, remove any unnecessary defensive code, fix inaccurate documentation, and make minor optimizations.

</domain>

<decisions>
## Implementation Decisions

### Audit findings
- CursorManager state machine (5 states) is correct and minimal — all states are actively used
- `cursorUpdate(with:)` override in OverlayWindow is the correct pattern for borderless overlay windows, not a workaround
- `applyCursor()` is correctly called from `cursorUpdate`, not from `mouseMoved` — but the doc comment says otherwise
- `hideCount` tracking is good defensive practice for balanced NSCursor.hide/unhide — keep it
- `baseState` pattern cleanly separates Ruler (.hidden) vs Guides (.resize) return states
- RulerWindow stale drag reset in `mouseDown` is a real edge case fix, not a cursor workaround — keep it

### Cleanup targets
- `reset()` method is identical to `restore()` — consolidate into one method
- CursorManager class doc comment is inaccurate: references `disableCursorRects()` (not used) and says `applyCursor()` runs on every `mouseMoved` (actually runs on `cursorUpdate`)
- Fix doc comment to accurately describe the `cursorUpdate(with:)` mechanism

### Claude's Discretion
- Whether to rename `reset()` call sites to `restore()` or vice versa
- Any additional doc comment improvements discovered during implementation
- Whether the `.cursorUpdate` tracking area option comment in OverlayWindow needs clarification

</decisions>

<specifics>
## Specific Ideas

- The cursor bugs were caused by an external macOS app affecting the whole OS cursor system
- Once that app was closed, both Design Ruler and Alignment Guides worked perfectly
- This phase is a lightweight cleanup pass, not a redesign

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 17-unified-cursor-manager-fixes*
*Context gathered: 2026-02-17*
