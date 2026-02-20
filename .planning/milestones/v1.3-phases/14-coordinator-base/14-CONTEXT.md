# Phase 14: Coordinator Base - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract shared lifecycle operations (warmup, permissions, signal handling, window management, capture, exit) from Ruler.swift and AlignmentGuides.swift into a common coordinator base. Each command retains only command-specific logic. Runtime behavior stays identical.

</domain>

<decisions>
## Implementation Decisions

### Extraction scope
- Extract the 5 success criteria items PLUS any other clearly duplicated code discovered along the way
- For code that's almost-identical with small differences: Claude decides case-by-case whether to parameterize or leave split
- The base orchestrates the full multi-monitor window creation loop (capture screens -> create windows -> show). Commands provide a window factory

### Capture unification
- Shared capture utility returns CGImage only — EdgeDetector wraps it into ColorMap separately
- Warmup capture (1x1 pixel cold-start absorber) moves from PermissionChecker into the coordinator base's startup sequence
- The base enforces the critical capture order: warmup -> permissions -> detect cursor screen -> capture all screens -> create windows -> .accessory policy. Commands cannot reorder this sequence

### Claude's Discretion
- **Inheritance model**: Base class vs protocol vs composition — Claude decides what fits best
- **Run loop ownership**: Whether the base owns NSApplication setup or commands keep theirs
- **Entry point file structure**: Whether @raycast funcs stay in Ruler.swift/AlignmentGuides.swift or move; whether coordinator subclasses get separate files
- **Singleton structure**: How Ruler.shared/AlignmentGuides.shared relate to the base
- **Entry point thickness**: How thin vs substantial command files should be after extraction
- **Almost-identical code**: Whether to parameterize or leave split, judged per case

</decisions>

<specifics>
## Specific Ideas

- Base should be an orchestrator, not just a bag of helpers — it owns the startup sequence and enforces ordering
- Commands should feel like "configuration + factory" — they tell the base what kind of windows to make, the base handles everything else

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-coordinator-base*
*Context gathered: 2026-02-17*
