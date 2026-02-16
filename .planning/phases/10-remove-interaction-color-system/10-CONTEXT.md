# Phase 10: Remove Interaction + Color System - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Two interaction layers on placed guide lines: (1) hover-to-remove interaction with visual feedback and removal animation, and (2) spacebar color cycling with a visual color circle indicator. Does NOT include hint bar updates, multi-monitor support, or new placement mechanics.

</domain>

<decisions>
## Implementation Decisions

### Remove hover feedback
- Hover zone is ~5px from a placed line
- Full line turns red + dashed instantly (no transition) when cursor enters hover zone
- Position pill text replaces coordinates with "Remove" text
- Pointing hand cursor when in hover zone (REQ-AG-08)
- On click to remove: line shrinks toward the click point then disappears
- Cursor reverts to previous state after line is removed

### Color circle indicator
- Color circles appear in a small arc/semicircle above the cursor on first spacebar press
- Each circle is ~12px diameter (medium, clearly visible)
- Active color shown as larger circle with white border ring; others at normal size
- Circles stay visible while user continues pressing spacebar
- After ~1s of no spacebar presses: circles fade out with a slight scale-down animation

### Color preset behavior
- Cycling order: dynamic (difference blend) → red → green → orange → blue → wraps to dynamic
- Dynamic preset shown as half-black half-white circle in the picker (representing contrast/adaptivity)
- Color is per-line: only NEW lines placed after a color change use the new color — existing lines keep their original color
- Preview line (following cursor) matches the current selected color
- First spacebar press both changes color AND shows the circle indicator

### Overlapping line handling
- When multiple lines are within hover range: nearest line to cursor (pixel distance) is targeted
- Click within ~5px of an existing line = hover/remove interaction, NOT a new placement
- No limit on number of placed lines — user manages their own
- Vertical and horizontal lines that cross receive no special treatment (they just visually overlap)

### Claude's Discretion
- Shrink animation duration and easing for line removal
- Exact arc layout geometry for color circles
- How color circles position themselves when cursor is near screen edges
- Transition animation when switching between normal and hover cursor states

</decisions>

<specifics>
## Specific Ideas

- The half-black/half-white circle for "dynamic" mode should clearly communicate that this mode adapts to the background
- Line removal shrink animation should feel satisfying — the line collapses toward where the user clicked, reinforcing direct manipulation
- Color circles arc should feel like a subtle radial menu, not a toolbar

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-remove-interaction-color-system*
*Context gathered: 2026-02-16*
