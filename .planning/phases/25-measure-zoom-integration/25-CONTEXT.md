# Phase 25: Measure Zoom Integration - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Make edge detection, crosshair rendering, dimension readout, arrow key skipping, and drag-to-select all produce correct results at 2x and 4x zoom. Phase 24 built the zoom transform infrastructure (Z key toggle, pan, animation). This phase wires the Measure command's features into that zoomed coordinate space.

</domain>

<decisions>
## Implementation Decisions

### Crosshair rendering at zoom
- Crosshair lines stay at 1px width regardless of zoom — crisp hairline overlay, not scaled
- Cross-foot marks at detected edges stay fixed size — same visual size at all zoom levels
- Blend mode: black/white with difference blend, identical behavior at all zoom levels (NOTE: crosshair is black/white, not orange — changed prior to this phase)
- Lines extend all the way to screen edges at zoom, same as 1x behavior

### Pan-on-skip behavior (arrow key edge skipping while zoomed)
- When arrow key skips to an edge outside the visible zoomed area, auto-pan just enough to bring the edge into view, hold briefly (~0.5-0.7s), then pan back to center on cursor — a "peek" behavior
- Pan animation is smooth, same style as mouse-driven panning
- Crosshair stays at cursor position — measurement lines extend to the new edge (same as 1x behavior)
- Skip distances are in point values — same point distance at any zoom level (bigger visual jump at higher zoom, consistent measurements)

### Selection overlay at zoom
- Selection rectangle renders in screen-space — smooth, crisp lines at all zoom levels
- When an existing selection is present and user zooms in/out, the selection scales with content (stays aligned to the selected region)
- Selection W×H pill always shows point values (real screen measurements), not zoomed-pixel counts

### Pill positioning at zoom
- W×H dimension pill stays at fixed screen-space offset from cursor — unaffected by zoom
- Pill flip logic uses same screen-edge thresholds — flips based on cursor proximity to physical screen edges
- Pill text size remains constant at all zoom levels — never scales
- Pill repositions to stay fully visible within the zoomed viewport (avoids being clipped at zoom boundary)

### Claude's Discretion
- Snap-to-edge threshold during drag-select at zoom (same points vs scale with zoom)
- Selection snap animation details at zoom
- Exact "peek" pan easing curve and return animation timing

</decisions>

<specifics>
## Specific Ideas

- The "peek" on arrow-key skip is a distinctive UX choice: briefly pan to show the detected edge, then return to cursor. This helps the user confirm which edge was found without losing their place.
- All measurement values (W×H, selection dimensions) must always be in screen points — zoom is purely a visual aid, never alters the measurement semantics.
- Crosshair and pill are screen-space overlays (fixed size, fixed offset). Selection is content-space (scales with zoom). This separation keeps measurement tools crisp while the selection stays spatially correct.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 25-measure-zoom-integration*
*Context gathered: 2026-03-06*
