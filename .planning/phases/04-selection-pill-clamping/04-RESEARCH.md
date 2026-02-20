# Phase 4: Selection Pill Clamping - Research

**Researched:** 2026-02-13
**Domain:** CALayer position clamping within screen bounds (macOS/Swift)
**Confidence:** HIGH

## Summary

The selection overlay's dimension pill (`SelectionOverlay.layoutPill()`) currently positions itself centered horizontally on the selection rectangle and below it (or above if near the bottom). It has no awareness of screen bounds, so selections near screen edges produce pills that render partially or fully off-screen. The fix is a straightforward geometric clamp applied after the initial position calculation but before setting layer frames.

The implementation requires two changes to `SelectionOverlay`: (1) pass the parent layer's bounds (which equals the screen size in window-local coords) into `layoutPill()` so it knows the available area, and (2) add horizontal and vertical clamping with a margin that accounts for the pill's drop shadow (shadowRadius=3, shadowOffset=(0,-1), meaning ~4px visual extent below the pill and ~3px on other sides). The parent layer bounds are already available at construction time via the `parentLayer` parameter, and the window content fills the entire screen, so `parentLayer.bounds` gives the full screen area in the same coordinate space the pill uses.

All three call sites of `layoutPill()` -- `animateSnap()`, `setHovered()` (un-hover path), and `setClearText()` -- go through the single method, so clamping in one place fixes all scenarios. No new files, no new dependencies, no architectural changes.

**Primary recommendation:** Store the parent layer bounds at init time. In `layoutPill()`, after computing the unclamped `pillX`/`pillY`, clamp them so that the pill (plus shadow margin) stays within `[0, screenWidth]` x `[0, screenHeight]`. Apply clamping after the above/below flip logic so both positions are clamped.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| QuartzCore (Core Animation) | System | CALayer frame positioning | Already used -- pill is composed of CAShapeLayer + CATextLayer |
| CoreGraphics | System | CGRect clamping math | Already used -- `CGRect`, `CGFloat` arithmetic |

### Supporting
No additional libraries needed. This is pure geometry applied to existing CALayer frames.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Clamping in `layoutPill()` | `CALayer.masksToBounds` on parent | Masks would clip the pill but also clip its shadow, violating success criterion 3. Also masks the selection rect stroke that intentionally sits outside the fill. Not viable. |
| Storing bounds at init | Passing bounds to every `layoutPill()` call | More parameters to thread through 3 call sites. Storing once is simpler since the screen bounds never change during the overlay's lifetime. |
| Static margin constant | Computing margin from shadow properties | Shadow properties are set once and never change. A constant is simpler and avoids coupling pill layout to shadow configuration. |

## Architecture Patterns

### Current layoutPill() Flow (No Clamping)
```
1. Compute pill width from text size
2. pillX = rect.midX - pillW/2  (centered)
3. pillY = rect.minY - gap - height  (below selection)
4. if pillY < 8: pillY = rect.maxY + gap  (flip above)
5. Set layer frames at (pillX, pillY)
```

### Proposed layoutPill() Flow (With Clamping)
```
1. Compute pill width from text size
2. pillX = rect.midX - pillW/2  (centered)
3. pillY = rect.minY - gap - height  (below selection)
4. if pillY < margin: pillY = rect.maxY + gap  (flip above)
5. Clamp pillX to [margin, screenWidth - pillW - margin]
6. Clamp pillY to [margin, screenHeight - pillHeight - margin]
7. Set layer frames at (pillX, pillY)
```

### Pattern 1: Shadow-Aware Margin Clamping
**What:** Clamp layer positions with a margin that accounts for the drop shadow's visual extent beyond the layer bounds.
**When to use:** Whenever a decorated (shadowed) element must stay fully visible within a container.
**Example:**
```swift
// Shadow config: radius=3, offset=(0,-1)
// Visual extent: 3px on left/right/top, 4px below (radius + abs(offset.y))
// Use a uniform margin >= max extent for simplicity
private let clampMargin: CGFloat = 4  // accounts for shadow

private func layoutPill() {
    // ... compute pillW, pillX, pillY as before ...

    // Clamp horizontal: keep pill + shadow within screen
    let maxX = screenSize.width - pillW - clampMargin
    pillX = min(max(pillX, clampMargin), maxX)

    // Clamp vertical: keep pill + shadow within screen
    let maxY = screenSize.height - pillHeight - clampMargin
    pillY = min(max(pillY, clampMargin), maxY)

    // ... set layer frames ...
}
```

### Pattern 2: Store Screen Bounds at Init
**What:** Capture the screen dimensions from the parent layer at construction time.
**When to use:** When a sublayer needs to know its container's bounds but doesn't have a reference to the container.
**Example:**
```swift
final class SelectionOverlay {
    private let screenSize: CGSize

    init(rect: CGRect, parentLayer: CALayer, scale: CGFloat) {
        self.rect = rect
        self.screenSize = parentLayer.bounds.size
        setupLayers(parentLayer: parentLayer, scale: scale)
        updateRect(rect, animated: false)
    }
}
```

### Anti-Patterns to Avoid
- **Using `masksToBounds` on the parent layer:** This clips ALL sublayers (selection rect, fill, other overlays) and clips shadows. It solves the visual problem by hiding it rather than positioning correctly.
- **Clamping only horizontal or only vertical:** A selection in a screen corner needs both axes clamped simultaneously. Missing one axis means the pill is still partially off-screen in corners.
- **Forgetting the shadow margin:** The pill's shadow extends beyond its frame. Clamping to `[0, screenWidth]` still allows the shadow to render off-screen. Must account for `shadowRadius` + `shadowOffset`.
- **Clamping before the above/below flip:** The vertical flip logic (`if pillY < 8, flip above`) should run first, then clamping ensures the flipped position is also within bounds. Clamping before the flip could prevent the flip from triggering.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rect clamping | Custom edge-detection logic with multiple if/else branches | `min(max(value, lower), upper)` two-liner | The clamping is literally two lines of arithmetic per axis. Any more complex approach is overengineering. |

**Key insight:** This entire phase is ~10 lines of meaningful code change. The research validates that the approach is correct and identifies the shadow margin concern, which is the only non-obvious detail.

## Common Pitfalls

### Pitfall 1: Shadow Clipped at Screen Edge
**What goes wrong:** Pill body stays on-screen but its drop shadow renders partially off-screen, creating an asymmetric or clipped shadow.
**Why it happens:** Clamping pill position to `[0, screenWidth/screenHeight]` without accounting for shadow extent. The shadow extends `shadowRadius` (3px) beyond the layer frame on all sides, plus `shadowOffset.height` (-1px, meaning 1px further below).
**How to avoid:** Use a clamping margin of at least 4px (`shadowRadius + abs(shadowOffset.height)` rounded up). Using a uniform 4px margin on all sides is simpler than computing per-edge shadow extent.
**Warning signs:** Shadow appears flat/truncated on one side when the pill is near a screen edge.

### Pitfall 2: Pill Position Jumps on Hover State Change
**What goes wrong:** When the user hovers a selection (changing text to "Clear") and the pill is near an edge, the pill jumps because the text width change causes a re-layout with different clamping.
**Why it happens:** "Clear" text is narrower than dimension text (e.g., "1234 x 567"). The pill width shrinks, which changes the horizontal centering, which may change whether clamping kicks in.
**How to avoid:** This is expected and acceptable behavior. The pill width changes on hover anyway (dimensions -> "Clear"). The clamping just ensures the narrower pill also stays on-screen. No special handling needed.
**Warning signs:** N/A -- this is expected behavior, not a bug.

### Pitfall 3: Vertical Flip and Clamp Interact Badly
**What goes wrong:** For a selection near the very bottom of the screen, the pill flips above but the selection is also very tall, pushing the pill off the top of the screen.
**Why it happens:** The flip logic moves the pill to `rect.maxY + pillGap`, and if `rect.maxY` is near `screenHeight`, the pill goes off-screen at the top.
**How to avoid:** The vertical clamp (step 6 in the proposed flow) handles this automatically. After flipping above, `pillY` is clamped to `screenHeight - pillHeight - margin` if needed. In extreme cases (selection fills the screen), the pill overlaps the selection, which is acceptable.
**Warning signs:** Pill invisible on very tall selections near the bottom edge.

### Pitfall 4: Negative Clamp Range on Tiny Screens
**What goes wrong:** If `screenWidth < pillW + 2*margin`, the `maxX` clamp value is less than `clampMargin`, creating an invalid range.
**Why it happens:** Extremely small window/screen where the pill is wider than the available space.
**How to avoid:** Use `max(clampMargin, maxX)` as the upper bound, or simply accept that on impossibly small screens the pill may overflow. In practice, the minimum macOS screen is 1024x768 and the pill is ~80-120px wide, so this cannot happen.
**Warning signs:** N/A -- cannot occur in practice.

## Code Examples

Verified patterns from codebase analysis:

### Complete layoutPill() with Clamping
```swift
// Source: Codebase analysis of SelectionOverlay.swift lines 265-285
// Modified to add screen-bounds clamping with shadow margin

private let clampMargin: CGFloat = 4  // shadow: radius=3, offset.y=-1

private func layoutPill() {
    guard let str = pillTextLayer.string as? NSAttributedString else { return }
    let textSize = str.size()
    let pillW = ceil(textSize.width) + pillPadH * 2
    let textH = ceil(textSize.height)

    // Position pill below the selection rect (or above if near bottom)
    var pillX = round(rect.midX - pillW / 2)
    var pillY = round(rect.minY - pillGap - pillHeight)
    if pillY < clampMargin {
        pillY = round(rect.maxY + pillGap)
    }

    // Clamp to screen bounds (accounting for shadow)
    let maxX = screenSize.width - pillW - clampMargin
    pillX = min(max(pillX, clampMargin), max(clampMargin, maxX))

    let maxY = screenSize.height - pillHeight - clampMargin
    pillY = min(max(pillY, clampMargin), max(clampMargin, maxY))

    let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillHeight)
    pillBgLayer.frame = pillRect
    pillBgLayer.path = squirclePath(rect: CGRect(origin: .zero, size: pillRect.size),
                                     radius: pillRadius)

    let textY = round(pillY + (pillHeight - textH) / 2)
    pillTextLayer.frame = CGRect(x: pillX, y: textY, width: pillW, height: textH)
}
```

### Storing Screen Size at Init
```swift
// Source: Codebase analysis of SelectionOverlay init (line 53)
// parentLayer.bounds.size == screen size in window-local coords

private let screenSize: CGSize

init(rect: CGRect, parentLayer: CALayer, scale: CGFloat) {
    self.rect = rect
    self.screenSize = parentLayer.bounds.size
    setupLayers(parentLayer: parentLayer, scale: scale)
    updateRect(rect, animated: false)
}
```

### Vertical Flip Threshold Change
```swift
// BEFORE (line 274): hardcoded 8px threshold
if pillY < 8 {
    pillY = round(rect.maxY + pillGap)
}

// AFTER: use clampMargin for consistency
if pillY < clampMargin {
    pillY = round(rect.maxY + pillGap)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No clamping (current) | Clamp with shadow margin | This phase | Pill always visible |

**Deprecated/outdated:**
- None. CGRect arithmetic and CALayer frame positioning are stable APIs.

## Open Questions

1. **Should the clamp margin be exactly 4px or more generous?**
   - What we know: Shadow extends max 4px (radius 3 + offset 1). The original code used `8` for the vertical flip threshold.
   - What's unclear: Whether 4px looks too tight visually (pill shadow touching screen edge).
   - Recommendation: Use 4px. The shadow at 3px from the edge is barely visible (it's 30% opacity, gaussian). If it looks too tight in testing, trivially adjustable to 6 or 8.

2. **Should the crosshair pill (CrosshairView) also be clamped?**
   - What we know: The crosshair pill already flips left/right and above/below based on cursor position near edges. Since it follows the cursor (which is always within the screen), it cannot go off-screen unless the cursor is within ~12px of a corner.
   - What's unclear: Whether extreme corner positions could push the crosshair pill partially off-screen.
   - Recommendation: Out of scope for VFBK-02 which specifies "Selection overlay dimension pill." The crosshair pill has its own flip logic that works well in practice. If needed, it can be addressed separately.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `SelectionOverlay.swift` -- full `layoutPill()` method (lines 265-285), shadow configuration (lines 76-79), all 3 call sites (lines 140, 184, 260), init signature (line 53)
- Codebase analysis: `SelectionManager.swift` -- `SelectionOverlay` construction (line 27), showing `parentLayer` is `cv.layer!` (CrosshairView's layer)
- Codebase analysis: `RulerWindow.swift` -- window frame equals screen frame (line 36), CrosshairView fills window (line 59), parentLayer is CrosshairView's layer (lines 66-69)
- Codebase analysis: `CrosshairView.swift` -- reference pill flip implementation (lines 277-343) showing the flip-with-animate pattern

### Secondary (MEDIUM confidence)
- [Apple CALayer.shadowRadius documentation](https://developer.apple.com/documentation/quartzcore/calayer/1410819-shadowradius) -- shadow extends beyond layer bounds by shadowRadius in all directions
- [Apple CALayer.shadowOffset documentation](https://developer.apple.com/documentation/quartzcore/calayer/1410970-shadowoffset) -- shadow displaced by offset from layer center

### Tertiary (LOW confidence)
- None. All findings are from direct codebase analysis.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies; pure arithmetic on existing CALayer frames
- Architecture: HIGH - Single method change in single file; all call sites identified; coordinate system verified (window-local, origin bottom-left)
- Pitfalls: HIGH - Shadow margin is the only non-obvious concern; all edge cases enumerated (corner, tall selection, hover text change)

**Research date:** 2026-02-13
**Valid until:** Indefinite -- CGRect arithmetic and CALayer frame positioning are stable; no version-dependent behavior
