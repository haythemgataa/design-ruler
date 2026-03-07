# Phase 26: Guides Zoom Integration - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Make Alignment Guides work correctly at 2x and 4x zoom levels: preview line follows cursor, click placement uses correct screen coordinates, hover-to-remove hit testing works in screen space, and existing guide lines render at correct positions when zoom changes. This is the Alignment Guides counterpart to Phase 25 (Measure Zoom Integration).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

User deferred all decisions — follow Phase 25 patterns consistently:

- **UI chrome sizing**: All guide-related UI (position pills, remove pills, color circle indicator, line thickness) stays constant screen size — does not scale with zoom
- **Coordinate display**: Position pills show screen-space coordinates (same values at any zoom level for the same screen position)
- **Hit testing**: 5px hover-to-remove threshold in screen space, not zoomed space (already specified in success criteria)
- **Coordinate mapping**: Use the same screen-to-content coordinate conversion established in Phase 24/25 (ZoomState model) to map mouse events to correct screen positions
- **Preview line**: Follows cursor at correct screen coordinate, not offset by zoom transform
- **Placed guide lines**: Store screen coordinates; render positions derived through zoom transform so they don't shift when zoom level changes

</decisions>

<specifics>
## Specific Ideas

- Follow Phase 25 patterns exactly — Measure Zoom Integration established the coordinate conversion approach, apply the same pattern to all Alignment Guides interactions
- Phase 24 ZoomState model and coordinate mapping are the foundation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 26-guides-zoom-integration*
*Context gathered: 2026-03-06*
