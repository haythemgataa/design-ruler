# Phase 27: Zoom UX Polish - Research

**Researched:** 2026-03-06
**Domain:** CALayer animation, SwiftUI hint bar layout, pill rendering
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- No separate on-screen indicator -- zoom level feedback lives **inside the hint bar's Z keycap**
- On Z press, the keycap text swaps from "Z" to the new zoom level ("x2", "x4", "x1") for ~0.5s, then reverts to "Z"
- Same flash behavior in both expanded and collapsed hint bar states
- No persistent visual cue after the flash
- **Scale-from-direction** animation with blur: zooming in (x2, x4) text starts small and scales up; zooming out (x1) text starts large and scales down; both include blur during transition; after ~0.5s zoom text blurs out and "Z" blurs in
- When hint bar is hidden, show a **second pill next to the cursor's dimension pill** -- same colors, size, and style as the dimension pill; moves with cursor; brief flash only (~0.5s); only shown when hint bar is hidden
- Z keycap placed **before ESC** (second to last) in hint bar layout
- Label text: "Toggle zoom"
- Appears in **both** Measure and Alignment Guides modes
- In expanded mode: keycap + label. In collapsed mode: keycap only

### Claude's Discretion
- Exact blur intensity and scale factor for the keycap flash animation
- Exact easing curve for the scale+blur transitions
- Standalone fallback pill positioning relative to the dimension pill (left/right/above)
- Whether the standalone fallback pill needs the same scale+blur animation or just a simple fade

### Deferred Ideas (OUT OF SCOPE)
None
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ZOOM-05 | Zoom level indicator visible on screen (shows "2x" or "4x") | Keycap flash in hint bar + standalone fallback pill when hint bar hidden. Architecture patterns section covers both paths. |
| SHUX-01 | Hint bar shows Z key shortcut for zoom | Z keycap addition to HintBarContent, CollapsedLeftContent, CollapsedAlignmentGuidesLeftContent, and HintBarGlassRoot. Code examples section shows exact insertion points. |
</phase_requirements>

## Summary

This phase adds two visual feedback mechanisms for zoom state: (1) a Z keycap in the hint bar with animated text flash on zoom toggle, and (2) a standalone fallback pill near the cursor when the hint bar is hidden. The work is entirely within the existing rendering infrastructure -- no new frameworks or libraries needed.

The hint bar Z keycap requires modifications to 6 SwiftUI views (HintBarContent expanded inspect, HintBarContent expanded guides, CollapsedLeftContent, CollapsedAlignmentGuidesLeftContent, CollapsedRightContent layout, and HintBarGlassRoot) plus a new `.zoom` entry in `HintBarView.KeyID`. The keycap flash animation (scale + blur) needs a new `ZoomFlashView` wrapper around the Z keycap that swaps between "Z" and the zoom level text with animated transitions. The standalone fallback pill reuses `PillRenderer` and lives in `CrosshairView` (Measure) and a new layer in `AlignmentGuidesWindow` (Guides).

**Primary recommendation:** Implement the Z keycap addition first (static, no animation), then layer on the flash animation, then add the standalone fallback pill as a separate concern.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ | Hint bar content views | Already used for all hint bar content |
| Core Animation | System | Pill rendering, scale/blur animation | Already used for all overlay animations |
| QuartzCore | System | CATransaction, CALayer transforms | Already used throughout |

No new dependencies needed. This phase uses only existing project infrastructure.

## Architecture Patterns

### Pattern 1: Z Keycap in Hint Bar
**What:** Add a Z `KeyCap` to all 6 hint bar layout views, positioned before ESC.
**When to use:** All hint bar states (expanded inspect, expanded guides, collapsed inspect, collapsed guides) and both code paths (morph for macOS 26+, fallback for older).

**Insertion points in HintBarContent.swift:**
- `HintBarContent` expanded inspect: before the ESC keycap, after "to reverse."
- `HintBarContent` expanded guides: before the ESC keycap, after "to change color."
- `CollapsedLeftContent`: add Z keycap after shift keycap
- `CollapsedAlignmentGuidesLeftContent`: add Z keycap after space keycap
- `HintBarGlassRoot` glassLayer: add Z keycap placeholder (opacity 0) in all branches
- `HintBarGlassRoot` keycapLayer: add Z keycap in all branches

**New KeyID:** Add `.zoom` case to `HintBarView.KeyID` enum.

### Pattern 2: Keycap Flash Animation (SwiftUI)
**What:** The Z keycap displays "Z" normally but on zoom toggle, swaps to "x2"/"x4"/"x1" with scale+blur animation for ~0.5s, then reverts.
**Architecture:** Use a new `@Published` property on `HintBarState` (e.g., `zoomFlashText: String?`) that HintBarView sets on zoom toggle. The KeyCap for Z reads this state and shows the flash text instead of "Z" when non-nil. A `DispatchWorkItem` clears it after ~0.5s.

**Why HintBarState, not a separate mechanism:** The hint bar already uses `HintBarState` as the single observable for all dynamic state (pressed keys, collapsed, mode, light/dark). Adding zoom flash text follows the same pattern.

**Animation approach:** SwiftUI `.transition()` with `.scale` + `.blur` modifiers on the text, triggered by the state change. The scale direction (small-to-normal vs large-to-normal) depends on whether zooming in or out.

### Pattern 3: Standalone Fallback Pill (CALayer)
**What:** When `hideHintBar` is true, show a small pill next to the dimension pill displaying "x2", "x4" on Z press, disappearing after ~0.5s.
**Architecture:** A new method on `CrosshairView` (for Measure) that creates/shows a temporary zoom pill using `PillRenderer`. For Alignment Guides, a similar temporary pill layer managed by `AlignmentGuidesWindow` or `GuideLineManager`.

**Positioning recommendation:** Place the zoom pill to the right of the dimension pill (or below if near right edge), with a small gap. This avoids visual collision and follows the existing pill placement logic.

**Animation recommendation:** Simple fade-in/fade-out for the fallback pill (not the full scale+blur). The scale+blur animation is designed for the keycap context where it reinforces the zoom metaphor within a keyboard key shape. A pill just needs to appear and disappear.

### Pattern 4: Wiring Z Key to Flash
**What:** The Z key press in `OverlayWindow.keyDown` already calls `handleZoomToggle()`. After toggling, the window needs to notify the hint bar of the new zoom level.
**Architecture:** After `handleZoomToggle()` in `OverlayWindow.keyDown`, call a new method on `HintBarView` (e.g., `flashZoomLevel(zoomState.level)`). This sets the flash text on `HintBarState` and schedules the revert. Also press/release the `.zoom` key for the keycap depression animation.

For the standalone fallback: `OverlayWindow` base checks `hintBarView.superview == nil` and if so, calls the subclass-specific fallback pill show method.

### Anti-Patterns to Avoid
- **Do NOT add a separate overlay view for the zoom indicator.** The user explicitly decided against a standalone indicator -- it lives in the hint bar keycap.
- **Do NOT make the zoom level persistent on screen.** The flash is brief (~0.5s) confirmation feedback only.
- **Do NOT use Core Animation for the keycap flash.** The keycap is SwiftUI -- use SwiftUI transitions/animations. CALayer animations are for the fallback pill only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Zoom pill rendering | Custom layer hierarchy | `PillRenderer.makeSelectionPill` or similar factory | Consistent styling, shadow, font, already exists |
| Keycap animation timing | Manual Timer/DispatchSource | `DispatchWorkItem` with `asyncAfter` | Same pattern used by ColorCircleIndicator's debounced hide |
| Text measurement for pill sizing | Manual font metrics | `NSAttributedString.size()` | Already used in `CrosshairView.layoutPill` |

## Common Pitfalls

### Pitfall 1: HintBarGlassRoot Dual-Layer Duplication
**What goes wrong:** The macOS 26+ glass morph path has TWO separate view trees (glassLayer and keycapLayer) that must both include the Z keycap. Missing it in one layer causes layout misalignment.
**Why it happens:** The glass morph design uses invisible placeholders in one layer and visible elements in the other for the morphing animation to work.
**How to avoid:** Add the Z keycap to BOTH the glassLayer (as `.opacity(0)` placeholder) and keycapLayer (as visible element) in every branch.
**Warning signs:** Keycap appears but layout is offset, or glass background doesn't cover the keycap.

### Pitfall 2: Collapsed Layout Sizing
**What goes wrong:** After adding the Z keycap to collapsed views, the `fittingSize` changes but the layout math in `HintBarView.configureFallback` uses cached sizes.
**Why it happens:** `configureFallback` computes panel positions from `leftHosting.fittingSize` and `rightHosting.fittingSize`.
**How to avoid:** The sizing is already dynamic (computed from hosting view fitting size). Just ensure the Z keycap is added to the left collapsed panel (alongside arrows+shift or tab+space), not the right panel (which is ESC only).

### Pitfall 3: Flash Timer Not Cancelled on Rapid Z Presses
**What goes wrong:** Pressing Z quickly causes overlapping flash timers. The first timer clears the flash text while the second flash should still be showing.
**Why it happens:** Each Z press schedules a new 0.5s revert timer without cancelling the previous one.
**How to avoid:** Store the `DispatchWorkItem` reference. Cancel the previous one before scheduling a new flash.
**Warning signs:** Flash text disappears too early when pressing Z rapidly.

### Pitfall 4: Z Keycap Flash When Hint Bar Is Hidden
**What goes wrong:** Code tries to flash the keycap text even when `hideHintBar` is true and the hint bar has no superview.
**Why it happens:** The flash method is called unconditionally after zoom toggle.
**How to avoid:** Guard the flash call with `hintBarView.superview != nil`. When the hint bar is hidden, use the standalone fallback pill instead.

### Pitfall 5: Standalone Pill Not Following Cursor
**What goes wrong:** The fallback pill appears at the initial position but doesn't move with the cursor.
**Why it happens:** The pill is created once and its position isn't updated in the mouse move handler.
**How to avoid:** Since the pill only lasts ~0.5s, position it once at creation time relative to the current cursor position. No need to track mouse moves during the brief flash -- the pill will naturally be near the cursor since zoom requires the cursor to be stationary (pressing Z).

### Pitfall 6: Fallback Pill in Alignment Guides
**What goes wrong:** Alignment Guides has no `CrosshairView` with a dimension pill, so the "next to dimension pill" positioning doesn't apply.
**Why it happens:** Only Measure has a dimension pill. Alignment Guides shows position pills on guide lines but no cursor-following pill.
**How to avoid:** For Alignment Guides with hidden hint bar, position the fallback pill directly at the cursor position (centered below or beside the cursor). Use a method on `AlignmentGuidesWindow` that manages a temporary CALayer-based pill.

## Code Examples

### Adding Z KeyCap to HintBarContent (Expanded Inspect)
```swift
// In HintBarContent.body, inspect mode branch:
HStack(spacing: 6) {
    style.text("Use")
    ArrowCluster(state: state)
    style.text("to skip edges, plus")
    KeyCap(.shift, symbol: "\u{21E7}", width: 40, height: 25,
           symbolFont: .system(size: 16, weight: .bold, design: .rounded),
           symbolTracking: -0.2, align: .bottomLeading, state: state)
    style.text("to reverse.")
    // NEW: Z keycap before ESC
    ZoomKeyCap(state: state)
    style.text("Toggle zoom")
    KeyCap(.esc, symbol: "esc", width: 32, height: 25,
           symbolFont: .system(size: 13, weight: .bold, design: .rounded),
           symbolTracking: -0.2, align: .center, state: state,
           tint: style.escTint, tintFill: style.escTintFill)
    style.exitText("to exit.")
}
```

### ZoomKeyCap View (Handles Flash Animation)
```swift
private struct ZoomKeyCap: View {
    @ObservedObject var state: HintBarState

    var body: some View {
        // When state.zoomFlashText is non-nil, show the zoom level
        // with scale+blur transition. Otherwise show "Z".
        KeyCap(.zoom, symbol: state.zoomFlashText ?? "Z",
               width: 25, height: 25,
               symbolFont: .system(size: 13, weight: .bold, design: .rounded),
               symbolTracking: -0.2, align: .center, state: state)
    }
}
```

### HintBarState Flash Properties
```swift
// Add to HintBarState:
@Published package var zoomFlashText: String? = nil
private var flashWorkItem: DispatchWorkItem?

package func flashZoomLevel(_ level: ZoomLevel) {
    flashWorkItem?.cancel()

    let text: String
    switch level {
    case .one:  text = "x1"
    case .two:  text = "x2"
    case .four: text = "x4"
    }

    zoomFlashText = text

    let revert = DispatchWorkItem { [weak self] in
        self?.zoomFlashText = nil
    }
    flashWorkItem = revert
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: revert)
}
```

### Wiring in OverlayWindow.keyDown
```swift
// In OverlayWindow.keyDown, after the Z key block:
if Int(event.keyCode) == 6 { // Z key
    if hintBarView.superview != nil {
        hintBarView.pressKey(.zoom)
    }
    handleZoomToggle()
    // Flash zoom level in hint bar or show fallback pill
    if hintBarView.superview != nil {
        hintBarView.flashZoomLevel(zoomState.level)
    } else {
        showZoomFallbackPill(level: zoomState.level)
    }
    return
}
```

### Standalone Fallback Pill (CrosshairView)
```swift
// Add to CrosshairView:
private var zoomPillBg: CAShapeLayer?
private var zoomPillText: CATextLayer?
private var zoomPillWorkItem: DispatchWorkItem?

package func showZoomFlash(level: ZoomLevel, at cursor: NSPoint) {
    zoomPillWorkItem?.cancel()
    removeZoomPill()

    guard level != .one else { return }  // No pill at 1x (it disappears)
    // Actually show for all levels including x1 as feedback

    let text = "x\(Int(level.rawValue))"
    // Create simple pill using PillRenderer patterns
    // Position relative to cursor (offset from dimension pill position)
    // Fade in, schedule fade out after 0.5s
}
```

## State of the Art

No external technology changes relevant to this phase. All work uses existing project patterns (SwiftUI for hint bar, CALayer for pills).

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Separate zoom indicator overlay | Keycap flash in hint bar | Phase 27 decision | Simpler, no extra UI element |

## Open Questions

1. **Scale factor for keycap flash animation**
   - What we know: Zooming in = small to normal, zooming out = large to normal
   - What's unclear: Exact scale values (0.5x to 1x? 0.7x to 1x? 1.5x to 1x?)
   - Recommendation: Start with 0.6x for zoom-in (small) and 1.4x for zoom-out (large). Tune visually.

2. **Blur intensity for keycap flash**
   - What we know: Both scale directions include blur during transition
   - What's unclear: Exact blur radius
   - Recommendation: Start with 4pt blur radius. SwiftUI `.blur(radius:)` applies during transition.

3. **SwiftUI scale+blur transition feasibility in KeyCap**
   - What we know: KeyCap is a private struct using standard SwiftUI. SwiftUI `.transition()` requires conditional view insertion/removal.
   - What's unclear: Whether the current KeyCap architecture supports animated text replacement smoothly
   - Recommendation: Use `.contentTransition(.interpolate)` with `.animation()` on the text change, or use two overlaid Text views with opacity/scale controlled by the flash state. The simpler approach: just change the `symbol` string and animate -- but SwiftUI `Text` content changes don't animate by default. A `ZStack` with two Text views (one for "Z", one for flash text) controlled by opacity is more reliable.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `HintBarContent.swift`, `HintBarView.swift`, `CrosshairView.swift`, `PillRenderer.swift`, `OverlayWindow.swift`, `DesignTokens.swift` -- all read and analyzed directly
- Existing codebase: `ZoomState.swift` -- zoom level enum and coordinate mapping
- Existing codebase: `MeasureWindow.swift`, `AlignmentGuidesWindow.swift` -- key handling and hint bar interaction patterns

### Secondary (MEDIUM confidence)
- SwiftUI `.contentTransition` and `.transition` APIs -- based on training knowledge of SwiftUI animation system. The exact API for text content transitions may need verification during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all existing project infrastructure
- Architecture: HIGH -- clear insertion points identified in actual source code
- Pitfalls: HIGH -- based on direct analysis of existing hint bar dual-layer architecture
- Animation details: MEDIUM -- SwiftUI scale+blur transition specifics may need tuning during implementation

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable, no external dependencies)
