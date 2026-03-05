# Phase 24: Zoom Transform Infrastructure - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

User can press Z to cycle overlay zoom (1x → 2x → 4x → 1x) centered on cursor, with smooth animation and cursor-following panning. Per-window zoom on multi-monitor. Resets to 1x on ESC. Applies to both Measure and Alignment Guides overlays. Zoom is a pure view transform — all existing interactions (edge detection, arrow skipping, drag-select, guide placement) continue to work while zoomed.

</domain>

<decisions>
## Implementation Decisions

### Zoom animation feel
- Duration: ~0.25s (medium — visible but not sluggish)
- Easing: easeOut (fast start, gentle landing — consistent with existing pill flip animations)
- Zoom anchor: always toward cursor position (cursor stays fixed on screen during zoom)
- Overlays during animation: crosshair, guides, and all layers animate with the zoom transform (scale + translate together), not freeze-and-reappear

### Panning at screen edges
- Edge behavior: hard stop at screen boundary — view stops panning, cursor can still move to the edge
- Tracking mode: 1:1 cursor tracking (view always keeps cursor centered) as the baseline implementation
- Experimental: dead zone variant (cursor moves freely in center ~30%, panning starts when approaching edges) — try as stretch goal after baseline works
- Monitor transitions: when cursor leaves a zoomed monitor, that monitor resets to 1x
- Pan range: full capture bounds — user can pan to reach any part of the screen while zoomed (magnifying glass you slide anywhere)

### Visual treatment when zoomed
- Screenshot scaling: nearest-neighbor / crisp — individual pixels visible at 4x, true pixel inspection
- No pixel grid overlay at any zoom level
- Crosshair lines: stay 1px screen-space regardless of zoom (precision feel, thin lines)
- UI elements (dimension pill, hint bar, position pills, color indicator): stay at normal size, independent of zoom — always readable

### Interaction while zoomed
- Edge detection: works while zoomed, operates on original capture data, results display correctly in zoomed coordinates
- Arrow-key edge skipping: works while zoomed, view pans to follow the skip
- Drag-to-select (Measure): works in zoomed coordinates, selection snaps to edges as normal
- Guide line placement (Alignment Guides): works at zoomed position, click places guides as normal
- All existing features remain fully functional — zoom is a view transform, not a mode change

### Claude's Discretion
- CALayer transform vs redraw approach for the zoom implementation
- How to handle the coordinate mapping between zoomed view and original capture
- Pan momentum / smoothness tuning
- Memory management for scaled content at 4x

</decisions>

<specifics>
## Specific Ideas

- Zoom should feel like a view transform layered on top of everything — not a separate mode. The user shouldn't have to "exit zoom" to use any feature.
- 1:1 cursor tracking first, but the dead zone approach (cursor free in center, panning at edges) could be better UX — worth prototyping after the baseline is solid.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 24-zoom-transform-infrastructure*
*Context gathered: 2026-03-05*
