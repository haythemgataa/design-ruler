# Phase 12: Leaf Utilities - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract shared design tokens, animation constants, blend mode constants, and CATransaction helpers into a single source of truth. Both commands (Design Ruler + Alignment Guides) reference these shared utilities. Zero behavioral change — pure internal refactoring.

</domain>

<decisions>
## Implementation Decisions

### Token structure
- Caseless enums for namespacing (prevents accidental instantiation)
- Top-level grouping is Claude's discretion (by purpose vs by component — pick what fits the codebase best)
- Animation durations live inside DesignTokens (e.g., `DesignTokens.Animation.fast`)
- BlendMode is a separate top-level caseless enum, NOT nested inside DesignTokens — but lives in the same file

### Naming conventions
- Animation duration tiers use speed words: `.instant`, `.fast`, `.standard`, `.slow` (as needed)
- Token properties use design terminology: `.cornerRadius`, `.kerning`, `.lineHeight` — not descriptive renames
- Blend mode constant: `BlendMode.difference` — namespaced enum, extensible
- CATransaction helper naming: Claude's discretion (CATransaction extension, wrapper type, or free function — pick what reads best)

### File organization
- New files go in `Utilities/` alongside `CoordinateConverter.swift`
- Separate files: `DesignTokens.swift` (tokens + BlendMode enum) and `TransactionHelpers.swift` (CATransaction helpers)
- CoordinateConverter.swift stays in place — Utilities/ becomes the shared code directory

### Extraction scope
- Convert ALL CATransaction boilerplate blocks across the entire codebase — comprehensive one-time sweep
- Animated transaction helper supports both duration and timing function: `CATransaction.animated(duration:timing:) { }`
- Which values to extract (only duplicated vs all magic numbers): Claude's discretion — judge per value whether extraction improves clarity
- Trivial values (0, 1, standard padding): Claude's discretion on whether these need named constants

### Claude's Discretion
- Top-level token grouping strategy (by purpose vs by component)
- CATransaction helper naming style
- Per-value judgment on what qualifies as a "design value" worth extracting vs a trivial inline constant
- Exact set of animation duration tiers needed (inspect codebase to determine)

</decisions>

<specifics>
## Specific Ideas

- BlendMode.difference for the `"differenceBlendMode"` string — single source of truth
- `CATransaction.animated(duration: 0.15, timing: .easeOut) { }` pattern for animated blocks
- Speed words for durations align with how the codebase already thinks about animations (fast pill flip, standard slide, etc.)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-leaf-utilities*
*Context gathered: 2026-02-16*
