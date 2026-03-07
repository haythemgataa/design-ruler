# Phase 24: Zoom Transform Infrastructure - Research

**Researched:** 2026-03-05
**Domain:** Core Animation layer transforms, coordinate remapping, per-window zoom state
**Confidence:** HIGH

## Summary

The zoom infrastructure requires transforming the captured screenshot layer while keeping all UI elements (crosshair, pills, hint bar, guide lines) at their original screen-space size and position relative to the cursor. The recommended approach uses a **two-layer architecture**: a "content layer" that holds the screenshot (and receives the `CATransform3D` scale+translate), and a separate "overlay layer" that renders all interactive elements untransformed. This avoids inverse-transform gymnastics and keeps the existing rendering code nearly unchanged.

The core challenge is **coordinate mapping**: mouse events arrive in untransformed window coordinates, but the zoomed content layer shows a different viewport of the original capture. Every interaction (edge detection, guide placement, selection drag) must convert between "screen-space cursor position" and "original capture position" to remain accurate. This is a single, well-defined mapping function that factors into zoom level and pan offset.

**Primary recommendation:** Introduce a `ZoomState` value type owned per-window, a content container layer with `magnificationFilter = .nearest` for the screenshot, and a coordinate mapping utility. Apply zoom via `CATransform3D` on the content layer only. UI layers stay in the window's root layer, unaffected by zoom transforms.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Zoom animation feel: ~0.25s duration, easeOut, cursor stays fixed on screen during zoom, all layers animate with the zoom transform (scale + translate together)
- Panning at screen edges: hard stop at screen boundary, 1:1 cursor tracking as baseline, dead zone variant as stretch goal
- Monitor transitions: when cursor leaves a zoomed monitor, that monitor resets to 1x
- Visual treatment: nearest-neighbor scaling (crisp pixels at 4x), no pixel grid overlay, crosshair lines stay 1px screen-space, UI elements (pill, hint bar, position pills) stay at normal size independent of zoom
- Interaction while zoomed: edge detection on original capture data, arrow-key skipping works, drag-to-select works, guide placement works, all features fully functional -- zoom is a view transform not a mode change

### Claude's Discretion
- CALayer transform vs redraw approach for the zoom implementation
- How to handle the coordinate mapping between zoomed view and original capture
- Pan momentum / smoothness tuning
- Memory management for scaled content at 4x

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ZOOM-01 | User can press Z to zoom overlay to 2x centered on cursor | ZoomState cycle logic + CATransform3D scale/translate applied to content layer, Z keyCode handling in OverlayWindow |
| ZOOM-02 | User can press Z again to cycle to 4x, then back to 1x | ZoomState enum with .one/.two/.four and .next() cycle method |
| ZOOM-03 | Zoom transitions are animated (smooth scale, not instant jump) | CATransaction.animated(duration: 0.25) wrapping transform change; easeOut timing matches existing project patterns |
| ZOOM-04 | View pans to follow cursor movement while zoomed | Pan offset calculation in handleMouseMoved: translate content layer so cursor position maps to correct capture coordinate |
| SHUX-02 | Zoom state is per-window (multi-monitor independent) | ZoomState stored as instance property on OverlayWindow, not on coordinator or as static |
| SHUX-03 | Zoom resets to 1x on session exit | OverlayCoordinator.handleExit() or resetCommandState() sets all window zoom states to .one |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| CATransform3D | macOS 14+ (built-in) | Scale+translate the content layer | GPU-composited, zero CPU cost, animatable via CATransaction |
| CALayer.magnificationFilter | macOS 14+ (built-in) | Nearest-neighbor upscaling for crisp pixels | `.nearest` filter gives exact pixel inspection at 2x/4x |
| CATransaction | macOS 14+ (built-in) | Animated and instant transform updates | Already used throughout codebase via TransactionHelpers.swift |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| CATransform3DConcat | Built-in | Combine scale + translate into single transform | Every zoom/pan update |
| CATransform3DIdentity | Built-in | Reset to 1x zoom | ESC exit, monitor transition reset |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CALayer transform | Redraw CGImage at zoomed resolution | CPU-expensive, stuttery on 4x Retina, no animation for free |
| sublayerTransform on parent | transform on content layer | sublayerTransform would require inverse transforms on UI layers; separate content layer is cleaner |
| NSScrollView magnification | CALayer transform | NSScrollView is for scroll-based UIs; overlay windows don't use scroll views, would require major restructuring |

## Architecture Patterns

### Recommended Layer Hierarchy (per window)

```
NSWindow.contentView
  |
  +-- containerView (NSView, frame = screen size)
  |     |
  |     +-- contentLayer (CALayer)                    <-- ZOOM TRANSFORM APPLIED HERE
  |     |     +-- screenshotLayer (contents = CGImage, magnificationFilter = .nearest)
  |     |
  |     +-- overlayView (CrosshairView / guidelineView)   <-- NO TRANSFORM (screen-space)
  |     |     +-- linesLayer, feet, pill layers...
  |     |
  |     +-- hintBarView                               <-- NO TRANSFORM (screen-space)
```

The key insight: **separate the screenshot from the interactive overlay**. The screenshot is the only thing that zooms. All CAShapeLayers (crosshair lines, feet, pills, guide lines, selections) stay in untransformed screen-space.

### Pattern 1: ZoomState Value Type

**What:** A lightweight struct or enum that tracks current zoom level and computes transforms.
**When to use:** Every window owns one instance. Queried on every mouse move, key press, and animation.

```swift
package enum ZoomLevel: CGFloat {
    case one = 1.0
    case two = 2.0
    case four = 4.0

    package func next() -> ZoomLevel {
        switch self {
        case .one:  return .two
        case .two:  return .four
        case .four: return .one
        }
    }
}

package struct ZoomState {
    package var level: ZoomLevel = .one
    package var panOffset: CGPoint = .zero  // In points, how far the content is shifted

    /// The content-layer transform: scale around origin then translate for pan.
    package var contentTransform: CATransform3D {
        let s = level.rawValue
        var t = CATransform3DMakeScale(s, s, 1)
        t = CATransform3DTranslate(t, panOffset.x, panOffset.y, 0)
        return t
    }

    /// Is zoomed (not 1x)?
    package var isZoomed: Bool { level != .one }
}
```

### Pattern 2: Coordinate Mapping (Screen-Space to Capture-Space)

**What:** Convert a window-local cursor point to the corresponding point in the original (unzoomed) capture.
**When to use:** Every edge detection call, guide placement click, selection drag point while zoomed.

```swift
/// Convert a window-local point to the corresponding point in the original capture.
/// At 1x zoom with no pan, this is identity. At 2x zoom centered on (cx, cy),
/// the visible area is half the screen, so a point at the window center maps to (cx, cy)
/// in the original capture.
func windowPointToCapturePoint(_ windowPoint: NSPoint, zoomState: ZoomState, screenSize: CGSize) -> NSPoint {
    let s = zoomState.level.rawValue
    // The content layer is scaled by s and translated by panOffset.
    // A point in the window corresponds to:
    //   captureX = (windowPoint.x / s) - panOffset.x
    //   captureY = (windowPoint.y / s) - panOffset.y
    return NSPoint(
        x: (windowPoint.x / s) - zoomState.panOffset.x,
        y: (windowPoint.y / s) - zoomState.panOffset.y
    )
}

/// Inverse: convert a capture-space point to window-space.
/// Used to position UI elements (crosshair, guide lines) at the correct screen location.
func capturePointToWindowPoint(_ capturePoint: NSPoint, zoomState: ZoomState) -> NSPoint {
    let s = zoomState.level.rawValue
    return NSPoint(
        x: (capturePoint.x + zoomState.panOffset.x) * s,
        y: (capturePoint.y + zoomState.panOffset.y) * s
    )
}
```

### Pattern 3: Zoom Anchor at Cursor

**What:** When zooming in, the cursor position should remain fixed on screen. The pan offset must be recalculated so the point under the cursor before zoom is still under the cursor after zoom.
**When to use:** On every Z keypress.

```swift
/// Calculate new pan offset so that the cursor position remains fixed on screen
/// when changing zoom level.
func panOffsetForZoom(
    cursorWindowPoint: NSPoint,
    currentZoom: ZoomState,
    newLevel: ZoomLevel,
    screenSize: CGSize
) -> CGPoint {
    // What capture-space point is currently under the cursor?
    let capturePoint = windowPointToCapturePoint(cursorWindowPoint, zoomState: currentZoom, screenSize: screenSize)

    // After zoom change, what pan offset keeps capturePoint at cursorWindowPoint?
    let newScale = newLevel.rawValue
    // capturePointToWindowPoint: windowX = (captureX + panX) * scale
    // We want windowX = cursorWindowPoint.x
    // So: panX = (cursorWindowPoint.x / newScale) - captureX
    let newPanX = (cursorWindowPoint.x / newScale) - capturePoint.x
    let newPanY = (cursorWindowPoint.y / newScale) - capturePoint.y

    return CGPoint(x: newPanX, y: newPanY)
}
```

### Pattern 4: Pan Clamping at Screen Boundaries

**What:** Prevent the user from panning beyond the capture bounds.
**When to use:** On every mouse move while zoomed, after computing new pan offset.

```swift
/// Clamp pan offset so the visible viewport stays within capture bounds.
func clampPanOffset(_ offset: CGPoint, zoomLevel: ZoomLevel, screenSize: CGSize) -> CGPoint {
    let s = zoomLevel.rawValue
    let viewportW = screenSize.width / s
    let viewportH = screenSize.height / s

    // Pan offset represents the capture-space origin of the viewport.
    // The visible capture rect is: origin = (-panX, -panY), size = (viewportW, viewportH)
    // Clamp so that: 0 <= -panX and -panX + viewportW <= screenSize.width
    // Which means: -(screenSize.width - viewportW) <= panX <= 0
    let minPanX = -(screenSize.width - viewportW)
    let minPanY = -(screenSize.height - viewportH)
    return CGPoint(
        x: max(minPanX, min(0, offset.x)),
        y: max(minPanY, min(0, offset.y))
    )
}
```

### Pattern 5: 1:1 Cursor Tracking Pan

**What:** On every mouse move while zoomed, recalculate pan offset so the capture point under the cursor matches the actual cursor position.
**When to use:** In `handleMouseMoved` when `zoomState.isZoomed`.

```swift
// In handleMouseMoved:
if zoomState.isZoomed {
    // Keep the cursor position in capture-space stable:
    // The cursor should always be "over" the capture pixel it would be at 1x.
    // At 1x, cursor at windowPoint maps to capturePoint = windowPoint (identity).
    // So the capture point under the cursor is simply the windowPoint (unzoomed coordinates).
    let capturePoint = windowPoint  // At 1x, window coords = capture coords

    // Calculate pan offset to keep this capturePoint at the current windowPoint
    let s = zoomState.level.rawValue
    let newPanX = (windowPoint.x / s) - capturePoint.x
    let newPanY = (windowPoint.y / s) - capturePoint.y
    zoomState.panOffset = clampPanOffset(CGPoint(x: newPanX, y: newPanY), ...)

    // Update content layer transform
    CATransaction.instant {
        contentLayer.transform = zoomState.contentTransform
    }
}
```

### Anti-Patterns to Avoid

- **Scaling the overlay/UI layers with the content:** This would make crosshair lines thicker at 2x/4x, pills would grow and overlap, hit test areas would be wrong. The user decision explicitly requires UI elements at normal size.
- **Using sublayerTransform with inverse transforms:** Applying sublayerTransform to a parent and then inverting on each UI layer is error-prone, requires updating every new layer added, and makes the code fragile. Two separate layer trees is simpler.
- **Redrawing the screenshot at a different resolution on zoom:** CPU-expensive (especially 4x on Retina = 8x pixel density), would stutter, and gains nothing since the capture data is already at native resolution.
- **Storing zoom state on the coordinator:** The coordinator spans multiple windows. Zoom is per-window per the requirement. Store on OverlayWindow instances.
- **Modifying anchorPoint for zoom anchor:** Changing anchorPoint moves the layer's position, requiring compensation. Instead, compute the correct translate offset algebraically to anchor at cursor. This is the math in Pattern 3.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Layer scaling with animation | Custom keyframe animation | `CATransaction.animated(duration: 0.25)` + set `layer.transform` | CATransaction already used throughout project; transform property is implicitly animatable |
| Nearest-neighbor upscaling | Custom CGImage redraw | `layer.magnificationFilter = .nearest` | Built into Core Animation, zero code, GPU-accelerated |
| Transform math | Manual matrix manipulation | `CATransform3DMakeScale` + `CATransform3DTranslate` + `CATransform3DConcat` | Apple's API handles matrix composition correctly |

**Key insight:** Core Animation already provides every building block for zoom: animatable transforms, filter modes, and GPU compositing. The only custom logic is the coordinate mapping math, which is straightforward algebra.

## Common Pitfalls

### Pitfall 1: Coordinate Confusion Between Window-Space and Capture-Space
**What goes wrong:** Edge detection returns wrong positions, guide lines placed at wrong coordinates, crosshair draws in wrong location when zoomed.
**Why it happens:** The window receives mouse events in screen-space, but the zoomed view shows a subset of the capture. Without consistent conversion, positions are off by the zoom factor.
**How to avoid:** Create a single `ZoomCoordinateMapper` utility (or methods on ZoomState) used by ALL interaction paths. Never do ad-hoc division/multiplication by zoom factor in window code.
**Warning signs:** Things work at 1x but are offset at 2x/4x. Values are "close but doubled" or "close but halved."

### Pitfall 2: Transform Order Matters (Scale Then Translate vs Translate Then Scale)
**What goes wrong:** Content zooms toward the wrong anchor point or pans at the wrong speed.
**Why it happens:** `CATransform3D` operations are composed right-to-left. `Scale * Translate` and `Translate * Scale` produce different results.
**How to avoid:** The correct order for "zoom centered at cursor" is: translate to center, then scale. Specifically: `CATransform3DTranslate(CATransform3DMakeScale(s, s, 1), panX, panY, 0)` applies translate-in-scaled-space, which is what we want (pan offset in capture-space coordinates).
**Warning signs:** Panning speed changes with zoom level, or zoom anchor drifts.

### Pitfall 3: Edge Detection Still Uses Original Capture Coordinates
**What goes wrong:** Edges are detected at zoomed positions instead of original positions, giving wrong measurements.
**Why it happens:** Passing window-space coordinates directly to EdgeDetector.onMouseMoved() while zoomed.
**How to avoid:** Always convert window-space cursor to capture-space (original screen coordinates) before calling EdgeDetector. Then convert the resulting edge positions back to window-space for rendering. The EdgeDetector/ColorMap never know about zoom.
**Warning signs:** Measurements change (double or quadruple) when zoomed vs not zoomed for the same region.

### Pitfall 4: UI Elements Scaling With Content
**What goes wrong:** Dimension pills, hint bar, and crosshair lines appear 2x/4x larger when zoomed.
**Why it happens:** UI layers are children of the transformed layer.
**How to avoid:** Keep UI layers in the untransformed root layer tree. Only the screenshot/content layer receives the zoom transform.
**Warning signs:** Visual inspection -- pills are huge at 4x zoom.

### Pitfall 5: Pan Offset Not Clamped
**What goes wrong:** User sees black/empty space beyond the capture bounds when moving cursor to screen edges while zoomed.
**Why it happens:** Pan offset allows the viewport to extend beyond the capture area.
**How to avoid:** Clamp pan offset so the visible viewport rectangle stays within `[0, 0, screenWidth, screenHeight]` in capture-space.
**Warning signs:** Black bars or solid-color fill visible at screen edges while zoomed.

### Pitfall 6: Zoom Animation and Ongoing Mouse Move Conflict
**What goes wrong:** During the 0.25s zoom animation, mouse moves update the transform to the final zoom level immediately, causing a jarring jump.
**Why it happens:** The animated transform is a presentation-layer interpolation, but the model-layer value is set to the final state immediately. If handleMouseMoved recalculates the transform based on the model-layer zoom level, it overwrites the animation.
**How to avoid:** Set a `isAnimatingZoom` flag during the 0.25s animation. During this flag, suppress pan updates (or let the animation complete before starting cursor-following). The animation is short enough (0.25s) that a brief pause in panning is acceptable.
**Warning signs:** Zoom animation visually jumps to final state instead of smoothly transitioning.

### Pitfall 7: Monitor Transition Zoom Reset Race
**What goes wrong:** Cursor enters a new monitor, old monitor should reset to 1x, but the zoom state persists or partially resets.
**Why it happens:** The `mouseEntered` → `activateWindow` path doesn't reset the old window's zoom.
**How to avoid:** In `OverlayCoordinator.activateWindow()`, when deactivating the old window, reset its zoom to 1x (animated or instant). Each window's `deactivate()` method should handle zoom reset.
**Warning signs:** Returning to a previously zoomed monitor still shows zoomed state.

## Code Examples

Verified patterns from project codebase and Apple documentation:

### Transform Application with Animation
```swift
// Matches existing project pattern (TransactionHelpers.swift)
func applyZoomTransform(to contentLayer: CALayer, zoomState: ZoomState, animated: Bool) {
    if animated {
        // 0.25s easeOut per user decision, matches DesignTokens.Animation.standard (0.2)
        // but slightly longer for zoom feel
        CATransaction.animated(duration: 0.25) {
            contentLayer.transform = zoomState.contentTransform
        }
    } else {
        CATransaction.instant {
            contentLayer.transform = zoomState.contentTransform
        }
    }
}
```

### Nearest-Neighbor Setup for Screenshot Layer
```swift
// Set on the background layer that holds the CGImage
screenshotLayer.magnificationFilter = .nearest  // Crisp pixels at 2x/4x
screenshotLayer.minificationFilter = .nearest   // Also crisp when zooming out (if ever)
screenshotLayer.contents = cgImage
screenshotLayer.contentsGravity = .resize
screenshotLayer.frame = NSRect(origin: .zero, size: screenSize)
```

### Z Key Handling in OverlayWindow
```swift
// In handleKeyDown(with:) -- keyCode 6 is Z on US keyboard layout
override package func handleKeyDown(with event: NSEvent) {
    switch Int(event.keyCode) {
    case 6: // Z key
        handleZoomToggle()
    // ... existing keys ...
    default: break
    }
}
```

### Zoom State Reset on Exit
```swift
// In OverlayCoordinator.handleExit()
// or OverlayWindow.deactivate() for monitor transitions
func resetZoom() {
    zoomState = ZoomState()  // Resets to .one with zero pan
    CATransaction.instant {
        contentLayer.transform = CATransform3DIdentity
    }
}
```

### Edge Detection with Zoom Coordinate Conversion
```swift
// In MeasureWindow.handleMouseMoved(to:)
override package func handleMouseMoved(to windowPoint: NSPoint) {
    // Convert window-space cursor to capture-space for edge detection
    let capturePoint: NSPoint
    if zoomState.isZoomed {
        capturePoint = windowPointToCapturePoint(windowPoint, zoomState: zoomState, screenSize: screenBounds.size)
    } else {
        capturePoint = windowPoint  // Identity at 1x
    }

    let appKitScreenPoint = NSPoint(
        x: screenBounds.origin.x + capturePoint.x,
        y: screenBounds.origin.y + capturePoint.y
    )
    guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }

    // Convert edge distances back to window-space for rendering
    // At zoom, distances are in capture-space points. Crosshair renders in window-space.
    // Scale edge distances by zoom factor for correct visual display.
    // ... (see Architecture Patterns for full mapping)

    crosshairView.update(cursor: windowPoint, edges: scaledEdges)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSView frame/bounds resize for zoom | CALayer.transform with CATransform3D | Core Animation since macOS 10.5+ | GPU-composited, animatable, no CPU redraw |
| Linear interpolation (default magnificationFilter) | .nearest for pixel inspection | Available since CA inception | Crisp pixel boundaries instead of blurry upscaling |
| Anchor point manipulation for zoom origin | Algebraic pan offset calculation | Best practice | Avoids position compensation bugs when changing anchorPoint |

**Deprecated/outdated:**
- None relevant. CATransform3D and CALayer.magnificationFilter are stable, unchanged APIs.

## Open Questions

1. **Crosshair line width at zoom levels**
   - What we know: User decided crosshair lines stay 1px screen-space regardless of zoom.
   - What's unclear: When the content is zoomed, do the crosshair lines need to span the full window as they do now, or should they span only the visible capture bounds? Answer: they should still span the full window since the crosshair is a UI element, not part of the content.
   - Recommendation: Keep crosshair behavior identical to current. Lines go to window edges (or detected edges scaled to window-space). No change needed to CrosshairView line rendering.

2. **Edge distances display at zoom**
   - What we know: W/H pill should show accurate point values at any zoom level (this is Phase 25's MEAS-02, but infrastructure must support it).
   - What's unclear: Do edge distances from EdgeDetector (which are in capture-space points) need scaling for pill display, or do they display as-is?
   - Recommendation: Edge distances from EdgeDetector are already in original points (what the user cares about). The pill should display these unmodified values. Only the crosshair line positions need zoom-scaling for correct visual placement. This is a Phase 25 concern but the infrastructure must not break it.

3. **Performance of transform updates at 60fps mouse moves**
   - What we know: Setting `layer.transform` inside `CATransaction.instant{}` is GPU-composited and effectively free.
   - What's unclear: Does the combined cost of coordinate conversion + edge detection + transform update stay under 5% CPU at 4x zoom?
   - Recommendation: Likely fine since edge detection CPU cost is unchanged (same ColorMap scan) and transform update is GPU-only. The mouse throttle in OverlayWindow (14ms = ~70fps cap) already limits update frequency. Monitor during implementation.

## Sources

### Primary (HIGH confidence)
- Project codebase: `OverlayWindow.swift`, `MeasureWindow.swift`, `AlignmentGuidesWindow.swift`, `CrosshairView.swift`, `EdgeDetector.swift`, `ColorMap.swift`, `TransactionHelpers.swift`, `DesignTokens.swift`
- [Apple: anchorPoint documentation](https://developer.apple.com/documentation/quartzcore/calayer/1410817-anchorpoint) - transform anchor behavior
- [Apple: magnificationFilter documentation](https://developer.apple.com/documentation/quartzcore/calayer/magnificationfilter) - nearest-neighbor scaling
- [Apple: Scaling Filters documentation](https://developer.apple.com/documentation/quartzcore/calayer/scaling_filters) - `.nearest` filter constant
- [Apple: sublayerTransform documentation](https://developer.apple.com/documentation/quartzcore/calayer/sublayertransform) - alternative approach (rejected)
- [Apple: Core Animation Basics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html) - transform composition

### Secondary (MEDIUM confidence)
- [Hacking with Swift: anchor point](https://www.hackingwithswift.com/example-code/calayer/how-to-change-a-views-anchor-point-without-moving-it) - practical anchorPoint guidance
- [Understanding CALayer Anchor Point](https://ikyle.me/blog/2022/understanding-uikit-calayer-anchor-point) - detailed anchor point explainer

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- CATransform3D and CALayer.magnificationFilter are stable, well-documented APIs used for exactly this purpose
- Architecture: HIGH -- two-layer split (zoomed content vs unzoomed UI) is the standard approach; the project's existing layer hierarchy makes this straightforward
- Coordinate mapping: HIGH -- the math is elementary algebra (divide by scale, subtract offset); the tricky part is ensuring all code paths use the same conversion, which is an implementation discipline issue
- Pitfalls: HIGH -- all identified pitfalls come from direct analysis of the existing codebase interaction patterns

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable APIs, no expected changes)
