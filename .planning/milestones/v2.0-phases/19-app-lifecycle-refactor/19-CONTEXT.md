# Phase 19: App Lifecycle Refactor - Context

**Gathered:** 2026-02-18
**Status:** Ready for planning

<domain>
## Phase Boundary

OverlayCoordinator can be invoked from a persistent app without starting or killing the event loop. ESC ends the overlay session and returns to idle — the app process stays alive. Cursor state is clean at the start of every session. Raycast extension behavior is unchanged (ESC still terminates the Raycast process).

</domain>

<decisions>
## Implementation Decisions

### Session dismiss behavior
- Instant vanish on ESC — same behavior as Raycast, windows removed immediately (no fade/transition)
- Cursor restoration identical in both app mode and Raycast mode — no mode-specific cursor logic
- No visual feedback on dismiss — the menu bar icon (always visible) is sufficient indication the app is alive
- 10-minute inactivity timer ends the overlay session (returns to idle) but does NOT quit the app process

### State reset between sessions
- Completely fresh state every session for both Measure and Alignment Guides
- Measure: no selections, no skip counts, no residual edge detection state carried over
- Alignment Guides: no guide lines carried over, blank canvas every session
- Guide color and direction reset to defaults (dynamic color, vertical) — do not persist last-used values
- Hint bar always starts expanded and collapses automatically — this is existing behavior, not a per-session preference

### Re-invocation guard
- If the same command is triggered while already active: silently ignore (running session continues undisturbed)
- If a different command is triggered while one is active: silently ignore (active session takes priority)
- No feedback on ignored invocations — the active overlay is already visible on screen
- No cooldown between ESC and next invocation — allow instant re-invocation (success criteria #2 requires this)

### Claude's Discretion
- Internal implementation of RunMode detection (enum shape, where it's checked)
- Cleanup ordering and teardown sequence details
- Whether to use a boolean guard or a state enum for the "session active" lock

</decisions>

<specifics>
## Specific Ideas

- The behavioral contract is simple: ESC = instant dismiss + full state reset + process stays alive (app mode) or process exits (Raycast mode). No transitions, no persistence, no feedback beyond what's already visible.
- Re-invocation guard is a simple "is session active?" boolean — reject all invocations while true, clear it synchronously on ESC before any async cleanup.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 19-app-lifecycle-refactor*
*Context gathered: 2026-02-18*
