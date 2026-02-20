# Phase 15: Window Base + Cursor - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract shared overlay window configuration, event handling, and hint bar management from RulerWindow and AlignmentGuidesWindow into a common base class. Extend CursorManager with resize cursor states used by Alignment Guides. Both commands must exhibit identical window behavior after refactoring.

</domain>

<decisions>
## Implementation Decisions

### Override boundary
- Base window owns ALL NSWindow configuration (level, styleMask, backgroundColor, acceptsMouseMoved) — subclasses cannot customize these
- Base handles activate/deactivate lifecycle fully (cursor position init, key window, hint bar) — subclasses get no hooks for this
- Subclasses own clicks entirely — mouseDown/mouseUp stay in subclasses with no base involvement
- Base handles ESC in keyDown — all other key events forwarded to subclass
- Base owns mouseEntered/mouseExited completely for multi-monitor activation — subclasses never see these events

### Event dispatch split
- Base handles: throttle (0.014s guard), first-move detection, ESC key, mouseEntered/mouseExited
- Subclasses handle: all other keyDown events (arrows for Ruler, tab/space for Guides), mouseDown/mouseUp, mouseDragged
- Base calls subclass `handleMouseMoved(to:)` after throttle and first-move processing

### Cursor resize states
- CursorManager gains `resizeUpDown` and `resizeLeftRight` as first-class states with proper push/pop transitions
- Resize cursor is the resting state in Alignment Guides (preview line always follows cursor) — switches to pointingHand only when hovering a placed line
- No "resting state" concept in CursorManager — each subclass explicitly drives the right transitions at the right time
- Design Ruler flow: systemCrosshair → hidden (first move) → pointingHand (hover selection) → hidden
- Alignment Guides flow: systemCrosshair → resize (first move) → pointingHand (hover placed line) → resize

### HintBar ownership
- Base window owns ALL hint bar logic: creation, collapse timer, 3-second expanded display, bottom/top position sliding
- Subclass only provides the mode (ruler vs guides) — never interacts with hint bar directly
- Base reads hideHintBar preference and conditionally skips all hint bar setup if true
- Base window init takes `hideHintBar: Bool` and `mode: HintBarMode` as parameters — multi-monitor coordinator passes hideHintBar: true for non-cursor screens

### Claude's Discretion
- Override pattern choice (single entry point vs multiple hooks for mouse move)
- Whether base creates PassthroughView contentView or leaves it to subclasses
- Whether mouseDragged gets a base stub or stays purely in RulerWindow
- Hint bar slide check placement (before subclass handleMouseMoved or as separate method)
- How hideHintBar preference flows from coordinator to window init

</decisions>

<specifics>
## Specific Ideas

- "The resize cursor is the default cursor for alignment guides view — it's always visible since there's always a preview line following the cursor. It only disappears when reaching a placed line to remove it."
- Resize cursor states should match the existing push/pop pattern used by pointingHand in CursorManager

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 15-window-base-cursor*
*Context gathered: 2026-02-17*
