# Phase 13: Rendering Unification - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract duplicated pill rendering code (font, paths, text formatting, shadows) from CrosshairView, GuideLine, and SelectionOverlay into a single shared PillRenderer. Both commands render pills identically to before — this is a pure refactoring phase with no user-facing changes.

</domain>

<decisions>
## Implementation Decisions

### Shared module structure
- Single `PillRenderer.swift` file containing all shared pill rendering: font factory, path generators, text formatters, shadow configuration, and pill layer creation
- Lives in the existing `Rendering/` folder alongside CrosshairView, SelectionOverlay, HintBarView
- Namespace style (enum vs struct) is Claude's discretion — match DesignTokens pattern if appropriate

### Pill factory scope
- Full pill factory — `PillRenderer.makePill()` returns a configured layer hierarchy with shadow, paths, and text layers already wired up
- Callers (CrosshairView, GuideLine, SelectionOverlay) receive ready-to-use pill layers and only set position and text content
- Enum-based variants for different pill types:
  - Dimension pill (split W/H sections with divider — CrosshairView)
  - Position pill (single value — GuideLine)
  - Remove pill (red styling, "Remove" text — GuideLine hover state)
  - Selection pill (dimension display — SelectionOverlay)

### Text formatting
- Unified `labelText()` and `valueText()` formatters shared by all three callers
- Formatter enforces styling: label text uses lighter weight, value text uses regular weight — no caller-controlled variation
- All pixel values rendered as integers (no decimals, no unit suffixes)
- SelectionOverlay uses the same formatters as CrosshairView and GuideLine

### Shadow standardization
- One standard shadow applied to all pills — visual consistency enforced
- If current shadows differ between callers, standardize to one value (minor visual difference acceptable)
- Shadow is part of the pill factory — applied automatically when PillRenderer creates a pill, not a separate helper
- ColorCircleIndicator's shadow is also consolidated into PillRenderer (even though it's visually distinct from pill shadows — may become a named preset)

### Claude's Discretion
- Enum vs struct for PillRenderer namespace
- Exact shadow values to standardize on (pick the best config)
- Internal implementation of squircle path generation
- How pill variants share internal code (composition vs conditional)
- Whether ColorCircleIndicator shadow becomes a separate preset or gets unified

</decisions>

<specifics>
## Specific Ideas

- Pill factory should follow the DesignTokens pattern established in Phase 12 — centralized, single source of truth
- The dimension pill's split design (W section + H section with divider) is a first-class variant, not a composition of two pills

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-rendering-unification*
*Context gathered: 2026-02-16*
