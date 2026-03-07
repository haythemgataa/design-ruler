# Phase 27: Zoom UX Polish - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual feedback for zoom state: a zoom level indicator and Z key shortcut in the hint bar. No new zoom functionality — phases 24-26 handle the zoom mechanics. This phase adds the UX layer so users know what zoom level they're at and how to activate zoom.

</domain>

<decisions>
## Implementation Decisions

### Zoom level feedback — keycap flash
- No separate on-screen indicator — zoom level feedback lives **inside the hint bar's Z keycap**
- On Z press, the keycap text swaps from "Z" to the new zoom level ("x2", "x4", "x1") for ~0.5s, then reverts to "Z"
- Same flash behavior in both expanded and collapsed hint bar states
- No persistent visual cue after the flash — the brief flash is sufficient, user can see the zoom visually

### Zoom flash animation
- **Scale-from-direction** animation with blur:
  - Zooming in (x2, x4): text starts small and scales up to normal size (expansion feel)
  - Zooming out (x1): text starts large and scales down to normal size (contraction feel)
  - Both directions include blur during transition
  - After ~0.5s, the zoom text blurs out and "Z" blurs in
- Animation reinforces the zoom direction metaphor

### Standalone fallback (hideHintBar mode)
- When hint bar is hidden entirely, show a **second pill next to the cursor's dimension pill**
- Same colors, size, and style as the existing dimension pill
- Moves with the cursor just like the dimension pill
- Brief flash only (appears on Z press, disappears after ~0.5s) — not persistent
- Only shown when hint bar is hidden; otherwise the keycap flash is sufficient

### Hint bar Z keycap placement
- Z keycap placed **before ESC** (second to last) in the hint bar layout
- Label text: "Toggle zoom"
- Appears in **both** Measure and Alignment Guides modes
- No extra detail about zoom cycle — just "Z" + "Toggle zoom", consistent with other keycaps
- In expanded mode: keycap + label. In collapsed mode: keycap only (same pattern as other keys)

### Claude's Discretion
- Exact blur intensity and scale factor for the keycap flash animation
- Exact easing curve for the scale+blur transitions
- Standalone fallback pill positioning relative to the dimension pill (left/right/above)
- Whether the standalone fallback pill needs the same scale+blur animation or just a simple fade

</decisions>

<specifics>
## Specific Ideas

- The zoom flash animation should feel physical: zooming in = expansion (small to normal), zooming out = contraction (large to normal)
- The standalone fallback pill mirrors the dimension pill's visual language — same rounded rect, same colors, same cursor-following behavior
- Keep the keycap flash quick (~0.5s) — it's confirmation feedback, not a persistent status display

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 27-zoom-ux-polish*
*Context gathered: 2026-03-06*
