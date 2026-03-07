# Phase 25: Measure Zoom Integration - Research

**Researched:** 2026-03-06
**Domain:** Coordinate mapping for zoomed edge detection, crosshair rendering, dimension readout, arrow key skipping, and drag-to-select
**Confidence:** HIGH

## Summary

Phase 24 built the zoom transform infrastructure: a two-layer architecture (zoomed content layer + untransformed UI), ZoomState with coordinate mapping functions, Z key toggle, pan tracking, and zoom reset. Phase 25 wires the Measure command's features into that zoomed coordinate space so edge detection, crosshair, dimensions, arrow keys, and drag-to-select all produce correct results at 2x and 4x.

The core challenge is that MeasureWindow currently passes window-local cursor coordinates directly to EdgeDetector, and CrosshairView renders edge positions in window-space. When zoomed, the window-space cursor no longer maps 1:1 to capture-space. Five interaction paths must be updated: (1) mouse-move edge detection, (2) crosshair line rendering at zoomed edge positions, (3) dimension pill display, (4) arrow key edge skipping with "peek" pan, and (5) drag-to-select with snapping. Each must correctly convert between window-space and capture-space using the existing `windowPointToCapturePoint` / `capturePointToWindowPoint` utilities.

The dimension pill and selection overlay already correctly display capture-space (unzoomed) point values. The crosshair already accepts a `zoomScale` parameter and scales edge positions for rendering. The existing code has **partial zoom support** from Phase 24 -- the `handleMouseMoved` in MeasureWindow already passes `zoomState.level.rawValue` to `crosshairView.update()` as `zoomScale`. However, it does NOT convert the cursor to capture-space before calling EdgeDetector, which means edge detection itself is wrong when zoomed. This is the primary gap.

**Primary recommendation:** Convert cursor to capture-space in MeasureWindow.handleMouseMoved before calling EdgeDetector, convert drag coordinates for selection, and implement the "peek" pan animation for arrow key skipping. No new files needed -- all changes are in existing MeasureWindow.swift, CrosshairView.swift, SelectionManager.swift, and SelectionOverlay.swift.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Crosshair lines stay at 1px width regardless of zoom -- crisp hairline overlay, not scaled
- Cross-foot marks at detected edges stay fixed size -- same visual size at all zoom levels
- Blend mode: black/white with difference blend, identical behavior at all zoom levels (NOTE: crosshair is black/white, not orange -- changed prior to this phase)
- Lines extend all the way to screen edges at zoom, same as 1x behavior
- When arrow key skips to an edge outside the visible zoomed area, auto-pan just enough to bring the edge into view, hold briefly (~0.5-0.7s), then pan back to center on cursor -- a "peek" behavior
- Pan animation is smooth, same style as mouse-driven panning
- Crosshair stays at cursor position -- measurement lines extend to the new edge (same as 1x behavior)
- Skip distances are in point values -- same point distance at any zoom level (bigger visual jump at higher zoom, consistent measurements)
- Selection rectangle renders in screen-space -- smooth, crisp lines at all zoom levels
- When an existing selection is present and user zooms in/out, the selection scales with content (stays aligned to the selected region)
- Selection W x H pill always shows point values (real screen measurements), not zoomed-pixel counts
- W x H dimension pill stays at fixed screen-space offset from cursor -- unaffected by zoom
- Pill flip logic uses same screen-edge thresholds -- flips based on cursor proximity to physical screen edges
- Pill text size remains constant at all zoom levels -- never scales
- Pill repositions to stay fully visible within the zoomed viewport (avoids being clipped at zoom boundary)

### Claude's Discretion
- Snap-to-edge threshold during drag-select at zoom (same points vs scale with zoom)
- Selection snap animation details at zoom
- Exact "peek" pan easing curve and return animation timing

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MEAS-01 | Edge detection works correctly on zoomed pixel data | Convert window-space cursor to capture-space via `windowPointToCapturePoint` before calling `edgeDetector.onMouseMoved()`. EdgeDetector/ColorMap always operate on original capture buffer -- they never know about zoom. |
| MEAS-02 | W x H dimensions show accurate point values at any zoom level | EdgeDetector already returns distances in capture-space points. CrosshairView.update() already uses unscaled distances (`edges.left?.distance`) for the dimension pill. No change needed for pill values -- only rendering positions need zoom scaling. |
| MEAS-03 | Arrow key edge skipping works while zoomed | Arrow keys call `edgeDetector.incrementSkip/decrementSkip` which use `lastCursorPosition` (capture-space). At zoom, must ensure lastCursorPosition is set to capture-space point. Add "peek" pan animation when skipped edge is outside visible viewport. |
| MEAS-04 | Drag-to-select and snap-to-edges work at zoom level | Drag start/update/end points must be converted from window-space to capture-space before passing to SelectionManager. SelectionOverlay rendering at zoom: selection rect in capture-space, rendered by scaling to window-space. Snap coordinates from EdgeDetector are in capture-space. |
| MEAS-05 | Dimension pill renders correctly and stays readable while zoomed | Pill is rendered in CrosshairView (untransformed screen-space). Already stays at fixed offset from cursor. Pill flip uses window bounds (screen edges). Pill text uses capture-space values. All correct by architecture. |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| ZoomState (existing) | N/A | Per-window zoom level + pan offset | Built in Phase 24, owns all zoom state |
| windowPointToCapturePoint (existing) | N/A | Convert window cursor to capture-space | Built in Phase 24, used by all zoom-aware paths |
| capturePointToWindowPoint (existing) | N/A | Convert capture-space to window-space | Built in Phase 24, used for rendering at zoom |
| CATransaction helpers (existing) | N/A | Instant and animated layer updates | Project standard pattern |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| clampPanOffset (existing) | N/A | Keep viewport within capture bounds | During "peek" pan animation to ensure panned viewport is valid |
| DesignTokens.Animation (existing) | N/A | Timing constants | For "peek" pan animation duration |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Converting coordinates at MeasureWindow level | Converting inside EdgeDetector | EdgeDetector should remain zoom-unaware per architecture; conversion at the call site keeps EdgeDetector pure |
| Moving selection to content layer (zooms with content) | Keeping selection in screen-space with manual coordinate conversion | Decision says selection scales with content -- moving to content layer is simpler than manual tracking, but selection pill must stay readable (screen-space) |

## Architecture Patterns

### Pattern 1: Cursor Coordinate Conversion in handleMouseMoved

**What:** Convert window-space cursor to capture-space before edge detection, then use zoomScale to render crosshair lines at correct zoomed positions.

**When to use:** Every mouse move while zoomed.

**Current code (MeasureWindow.handleMouseMoved):**
```swift
override package func handleMouseMoved(to windowPoint: NSPoint) {
    let appKitScreenPoint = NSPoint(
        x: screenBounds.origin.x + windowPoint.x,
        y: screenBounds.origin.y + windowPoint.y
    )
    guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }
    // ... selection hover ...
    crosshairView.update(cursor: windowPoint, edges: edges, zoomScale: zoomState.level.rawValue)
}
```

**Required change:**
```swift
override package func handleMouseMoved(to windowPoint: NSPoint) {
    // Convert window-space to capture-space when zoomed (MEAS-01)
    let capturePoint = windowPointToCapturePoint(
        windowPoint, zoomState: zoomState, screenSize: screenBounds.size
    )
    let appKitScreenPoint = NSPoint(
        x: screenBounds.origin.x + capturePoint.x,
        y: screenBounds.origin.y + capturePoint.y
    )
    guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }
    // ... selection hover (also needs capturePoint for hit testing at zoom) ...
    crosshairView.update(cursor: windowPoint, edges: edges, zoomScale: zoomState.level.rawValue)
}
```

**Key insight:** The cursor position passed to CrosshairView stays as `windowPoint` (screen-space) because the crosshair renders in screen-space. Only the EdgeDetector call needs capture-space input. The `zoomScale` parameter on `crosshairView.update()` already handles scaling edge distances for visual rendering.

### Pattern 2: "Peek" Pan for Arrow Key Edge Skipping

**What:** When an arrow key skip moves an edge outside the visible zoomed viewport, auto-pan to reveal the edge, hold briefly, then pan back to center on cursor.

**When to use:** Arrow key press while zoomed, when the resulting edge position falls outside the visible viewport.

**Approach:**
```swift
// After edgeDetector.incrementSkip returns new edges:
if zoomState.isZoomed, let edge = edges.left {  // (example for left arrow)
    // Convert edge screen position to window-space to check visibility
    let edgeWindowX = (edge.screenPosition - screenBounds.origin.x + zoomState.panOffset.x) * zoomState.level.rawValue
    if edgeWindowX < 0 || edgeWindowX > screenBounds.width {
        // Edge is outside visible viewport -- animate "peek" pan
        peekPanToEdge(edgeWindowPosition: ..., direction: .left)
    }
}

func peekPanToEdge(edgePosition: CGFloat, direction: Direction) {
    // 1. Calculate pan offset that brings edge just into view (with small margin)
    // 2. Animate pan to that offset (smooth, ~0.2s)
    // 3. Hold at that position (~0.5-0.7s)
    // 4. Animate pan back to cursor-centered position (~0.2s)
}
```

**Critical detail:** During the peek animation, mouse moves should still work (updating the crosshair and edges at the peeked position), but the pan should not be overridden by the normal cursor-following pan. Use a flag similar to `isAnimatingZoom` to suppress normal pan updates during the peek sequence.

### Pattern 3: Selection in Content-Space (Scales with Zoom)

**What:** The locked decision says "selection scales with content (stays aligned to the selected region)." This means selection layers should be children of the content layer (zoomed), not the CrosshairView (unzoomed).

**Current architecture:** SelectionManager creates SelectionOverlay layers as sublayers of `cv.layer!` (CrosshairView's root layer) -- this is in the untransformed overlay space.

**Required change:** Move selection layers to be sublayers of contentLayer so they automatically scale with zoom. However, the selection pill (W x H text) must remain readable -- it should NOT scale with zoom per the locked decision. This requires the pill layers to live outside the content layer (in screen-space).

**Approach:**
- Selection rect/fill layers -> sublayers of contentLayer (zoom with content)
- Selection pill (bg + text) -> sublayers of CrosshairView's layer or a separate overlay layer (stay in screen-space)
- This requires splitting SelectionOverlay's layer ownership: rect/fill are content-space, pill is screen-space
- OR: keep all selection layers in screen-space and manually convert positions on zoom change

**Recommended approach:** Keep all selection layers in screen-space (current architecture) but track selection rect in capture-space coordinates. When zoom changes, recalculate the window-space rect from the stored capture-space rect. This avoids splitting layer ownership and keeps the SelectionOverlay code simpler.

```swift
// SelectionOverlay stores rect in capture-space (point values)
// On zoom change or when rendering, convert to window-space:
let windowRect = CGRect(
    x: (captureRect.origin.x + zoomState.panOffset.x) * scale,
    y: (captureRect.origin.y + zoomState.panOffset.y) * scale,
    width: captureRect.width * scale,
    height: captureRect.height * scale
)
```

### Pattern 4: Drag Coordinate Conversion

**What:** Drag start, update, and end points must be in capture-space for EdgeDetector.snapSelection, but the drag visual feedback should be in window-space.

**When to use:** mouseDown/mouseDragged/mouseUp in MeasureWindow.

**Approach:**
- On mouseDown: convert windowPoint to capturePoint, store as drag origin in capture-space
- On mouseDragged: convert windowPoint to capturePoint, update drag rect in capture-space, render in window-space by multiplying by zoomScale
- On mouseUp: convert windowPoint to capturePoint, call snapSelection with capture-space rect
- The live drag visual (SelectionOverlay) renders in window-space using the scaled rect

### Anti-Patterns to Avoid

- **Converting edge distances by zoomScale for dimension pill:** The pill already shows capture-space distances. DO NOT multiply distances by zoomScale for display -- only for visual line rendering.
- **Moving selection layers to contentLayer without pill separation:** The pill text would become unreadable at 4x (48pt apparent size). Keep pill in screen-space.
- **Modifying EdgeDetector to know about zoom:** EdgeDetector and ColorMap must remain zoom-unaware. All coordinate conversion happens at the call site (MeasureWindow).
- **Suppressing crosshair during peek pan:** The user decision says "Crosshair stays at cursor position" during skip. The crosshair should remain visible; only the pan changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window-to-capture coordinate conversion | Manual division by zoom factor | `windowPointToCapturePoint()` from ZoomState.swift | Already built, handles pan offset correctly |
| Capture-to-window coordinate conversion | Manual multiplication by zoom factor | `capturePointToWindowPoint()` from ZoomState.swift | Already built, inverse of above |
| Pan offset clamping | Manual min/max bounds checking | `clampPanOffset()` from ZoomState.swift | Already built, handles viewport-to-capture-bounds math |
| Animated pan | Manual CABasicAnimation on contentLayer.transform | `CATransaction.animated(duration:)` + set `contentLayer.transform` | Project standard pattern, transform is implicitly animatable |

**Key insight:** The Phase 24 infrastructure already provides every coordinate conversion utility. This phase's primary work is wiring those utilities into the correct call sites, not building new math.

## Common Pitfalls

### Pitfall 1: Edge Detection at Wrong Coordinates When Zoomed
**What goes wrong:** Edges are detected at zoomed screen positions instead of original capture positions. Measurements change (double or quadruple) when zoomed.
**Why it happens:** `handleMouseMoved` passes `windowPoint` directly to build the AppKit screen point for EdgeDetector. At zoom, windowPoint is in zoomed screen-space, not capture-space.
**How to avoid:** Always convert `windowPoint` to capture-space via `windowPointToCapturePoint` before constructing the AppKit screen point for EdgeDetector.
**Warning signs:** W x H values change when pressing Z (zoom) without moving the cursor. At 2x, dimensions might appear halved or doubled.

### Pitfall 2: Crosshair Cursor Position vs Edge Rendering Position
**What goes wrong:** Crosshair lines appear at wrong positions -- either the cursor position is wrong or the edge endpoints are wrong.
**Why it happens:** Confusion between cursor rendering position (window-space) and edge distances (capture-space). The cursor position for CrosshairView must be in window-space (where to draw the crosshair center), while edge distances are in capture-space (how far from cursor to edge in points). The zoomScale parameter on `update()` handles the visual scaling of edge distances.
**How to avoid:** Pass `windowPoint` as cursor to CrosshairView, and pass capture-space edges with `zoomScale` for rendering. The existing `zoomScale` parameter in CrosshairView.update() already multiplies edge distances for visual positioning.
**Warning signs:** Crosshair center is offset from the actual cursor, or lines end at wrong positions relative to the zoomed content.

### Pitfall 3: Selection Hit-Testing at Wrong Scale
**What goes wrong:** Clicking on a selection while zoomed misses, or clicking empty space triggers a selection removal.
**Why it happens:** SelectionOverlay.contains() uses the stored `rect` which might be in capture-space, but the hit-test point is in window-space (or vice versa).
**How to avoid:** Ensure consistent coordinate space for both the stored rect and the hit-test point. If selection rect is stored in capture-space, convert the hit-test point to capture-space before testing. If stored in window-space, keep both in window-space.
**Warning signs:** Hit testing works at 1x but breaks at 2x/4x.

### Pitfall 4: Peek Pan Overridden by Cursor-Following Pan
**What goes wrong:** The "peek" animation starts but immediately gets overridden by the next mouse move's pan update, making the peek invisible.
**Why it happens:** `updateZoomPan` in OverlayWindow.mouseMoved runs on every mouse event and overwrites panOffset.
**How to avoid:** Use a flag (e.g., `isPeekAnimating`) to suppress `updateZoomPan` during the peek sequence. Clear the flag when the peek's return animation completes.
**Warning signs:** Arrow key press at zoom causes a brief flicker instead of a smooth peek.

### Pitfall 5: Selection Snap Coordinates Wrong at Zoom
**What goes wrong:** After drag-to-select at zoom, the snapped selection appears at the wrong position or with wrong dimensions.
**Why it happens:** `edgeDetector.snapSelection` expects window-local AppKit coords for the rect and screen AppKit frame for bounds. At zoom, the drag rect is in window-space (zoomed), but snapSelection needs capture-space coordinates.
**How to avoid:** Convert the drag rect from window-space to capture-space before passing to snapSelection. The returned snapped rect will be in capture-space -- convert back to window-space for rendering.
**Warning signs:** Snap works at 1x but selects wrong region at 2x/4x, or snap fails (shake animation) on regions that would snap at 1x.

### Pitfall 6: Selection Not Updating Position on Zoom Change
**What goes wrong:** Existing selections stay at their window-space positions when user presses Z to zoom, appearing to "float" away from the content they were aligned to.
**Why it happens:** SelectionOverlay stores its rect in window-space and nothing updates it when zoom changes.
**How to avoid:** Store selection rect in capture-space. On zoom change, recalculate window-space positions from capture-space rect. Wire a zoom-change notification from handleZoomToggle to the selection update logic.
**Warning signs:** Selections visually separate from the content they're attached to when zooming in/out.

## Code Examples

Verified patterns from the current codebase:

### Edge Detection with Zoom Coordinate Conversion (MEAS-01)
```swift
// MeasureWindow.handleMouseMoved -- the key change for MEAS-01
override package func handleMouseMoved(to windowPoint: NSPoint) {
    // At 1x, windowPointToCapturePoint is identity (no performance cost)
    let capturePoint = windowPointToCapturePoint(
        windowPoint, zoomState: zoomState, screenSize: screenBounds.size
    )
    let appKitScreenPoint = NSPoint(
        x: screenBounds.origin.x + capturePoint.x,
        y: screenBounds.origin.y + capturePoint.y
    )
    guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }
    // cursor: windowPoint (screen-space for rendering position)
    // edges: capture-space distances
    // zoomScale: multiplier for visual edge positions
    crosshairView.update(cursor: windowPoint, edges: edges, zoomScale: zoomState.level.rawValue)
}
```

### Crosshair Edge Position Scaling (Already Implemented)
```swift
// CrosshairView.update() -- already handles zoomScale
// Window-space edge positions (scaled by zoom, clamped to window bounds)
let leftX = max(0, edges.left.map { cx - $0.distance * zoomScale } ?? 0)
let rightX = min(vw, edges.right.map { cx + $0.distance * zoomScale } ?? vw)
let topY = min(vh, edges.top.map { cy + $0.distance * zoomScale } ?? vh)
let bottomY = max(0, edges.bottom.map { cy - $0.distance * zoomScale } ?? 0)

// W x H pill always uses capture-space distances (unscaled)
let w = Int(leftDist + rightDist)  // leftDist = edges.left?.distance ?? cx
let h = Int(topDist + bottomDist)
```

### Peek Pan Animation for Arrow Key Skip (MEAS-03)
```swift
// Conceptual implementation for MeasureWindow.handleKeyDown
// After getting new edges from incrementSkip:
func peekToEdge(_ edge: EdgeHit, direction: EdgeDetector.Direction) {
    guard zoomState.isZoomed else { return }

    // Check if edge is visible in current viewport
    let edgeCapturePos = edge.screenPosition  // AX coords
    let edgeCapturePt: NSPoint  // capture-space point on the relevant axis
    // Convert to window-space to check visibility
    // ... (axis-dependent conversion)

    // If outside viewport, animate pan:
    // 1. Calculate target pan offset (bring edge into view with margin)
    // 2. Set isPeekAnimating = true (suppress normal pan updates)
    // 3. CATransaction.animated { contentLayer.transform = peekTransform }
    // 4. After hold delay (~0.5s), animate back
    // 5. After return animation, set isPeekAnimating = false
}
```

### Drag-to-Select with Zoom Conversion (MEAS-04)
```swift
// MeasureWindow.mouseDown -- convert to capture-space for drag
override package func mouseDown(with event: NSEvent) {
    let windowPoint = event.locationInWindow
    let capturePoint = windowPointToCapturePoint(
        windowPoint, zoomState: zoomState, screenSize: screenBounds.size
    )
    // Use capturePoint for SelectionManager drag origin
    // SelectionManager needs to know about zoom for rendering
    selectionManager.startDrag(at: capturePoint)
}

// MeasureWindow.mouseUp -- snap in capture-space
override package func mouseUp(with event: NSEvent) {
    let windowPoint = event.locationInWindow
    let capturePoint = windowPointToCapturePoint(
        windowPoint, zoomState: zoomState, screenSize: screenBounds.size
    )
    _ = selectionManager.endDrag(at: capturePoint, screenBounds: screenBounds)
}
```

### Selection Position Update on Zoom Change
```swift
// When zoom changes, update selection positions:
// Option A: Store capture-space rect, recalculate window-space on zoom
// Option B: Move selection rect/fill layers into contentLayer (auto-zoom)

// Option A (recommended for simplicity):
func updateSelectionsForZoom() {
    let zs = zoomState.level.rawValue
    for sel in selectionManager.selections {
        let captureRect = sel.captureRect  // stored in capture-space
        let windowRect = CGRect(
            x: (captureRect.origin.x + zoomState.panOffset.x) * zs,
            y: (captureRect.origin.y + zoomState.panOffset.y) * zs,
            width: captureRect.width * zs,
            height: captureRect.height * zs
        )
        sel.updateRect(windowRect, animated: true)
    }
}
```

## State of the Art

| Old Approach (Phase 24) | Current Approach (Phase 25) | Impact |
|--------------------------|----------------------------|--------|
| handleMouseMoved passes windowPoint directly to EdgeDetector | Convert via windowPointToCapturePoint first | Correct edge detection at any zoom level |
| CrosshairView.update zoomScale parameter unused at 1x | zoomScale actively used at 2x/4x for visual edge positions | Crosshair lines align with zoomed content |
| Selection stored in window-space only | Selection stored in capture-space, rendered at zoom | Selections survive zoom changes |
| Arrow keys work only in 1x context | Arrow keys + peek pan at zoom | Full edge navigation while zoomed |

## Open Questions

1. **Selection layer ownership: content-space vs screen-space**
   - What we know: Decision says "selection scales with content." This could mean (A) move rect/fill layers into contentLayer, or (B) manually track capture-space rect and update window-space positions on zoom.
   - What's unclear: If we move rect/fill to contentLayer, the dashed stroke and line width would also scale (2px line at 2x zoom). Is that desired?
   - Recommendation: Use approach B (keep all selection layers in screen-space, track capture-space rect). This keeps stroke width consistent at all zoom levels and avoids layer-split complexity. The selection "scales with content" visually because its position and size follow the content, even though the layers are in screen-space.

2. **Arrow key skip: capture-space or window-space cursor for crosshair update**
   - What we know: After skip, crosshairView.update() is called with `crosshairView.cursorPosition` (which is in window-space). The edges come from EdgeDetector using the capture-space lastCursorPosition.
   - What's unclear: Does the cursor need to be re-derived after peek pan (since pan offset changes)?
   - Recommendation: During peek, the crosshair center stays at the cursor's window position (locked decision: "Crosshair stays at cursor position"). After the peek returns, the cursor position hasn't changed. Pass `crosshairView.cursorPosition` unchanged.

3. **Performance of "peek" pan with three animated phases**
   - What we know: CATransaction.animated on contentLayer.transform is GPU-composited (~0 CPU).
   - What's unclear: Three sequential DispatchQueue.main.asyncAfter callbacks for pan-out, hold, pan-back -- will this feel smooth?
   - Recommendation: Use a single CAKeyframeAnimation on `contentLayer.transform` with keyTimes for the three phases (out, hold, back). This runs entirely on the GPU without main-thread scheduling jitter.

## Sources

### Primary (HIGH confidence)
- Project codebase: All files read directly during research
  - `ZoomState.swift` - zoom model + coordinate mapping functions
  - `OverlayWindow.swift` - zoom infrastructure (toggle, pan, reset)
  - `MeasureWindow.swift` - current handleMouseMoved, drag lifecycle, arrow keys
  - `CrosshairView.swift` - current update() with zoomScale parameter
  - `EdgeDetector.swift` - edge detection API, snapSelection
  - `SelectionManager.swift` - drag lifecycle, hit testing
  - `SelectionOverlay.swift` - selection rendering, snap animation
  - `ColorMap.swift` - pixel scanning (zoom-unaware)
  - `DirectionalEdges.swift` - EdgeHit model (distance, screenPosition)
  - `CoordinateConverter.swift` - AppKit/CG conversion utilities
  - `MeasureCoordinator.swift` - coordinator lifecycle
  - `OverlayCoordinator.swift` - base coordinator with zoom reset
- Phase 24 artifacts: 24-RESEARCH.md, 24-02-PLAN.md, 24-02-SUMMARY.md

### Secondary (MEDIUM confidence)
- Apple Core Animation documentation - CAKeyframeAnimation for multi-phase transforms (training data, standard API)

## Metadata

**Confidence breakdown:**
- Coordinate conversion (MEAS-01, MEAS-02): HIGH - the math is straightforward and the utility functions already exist in ZoomState.swift. The code gap is clearly identifiable (windowPoint vs capturePoint in handleMouseMoved).
- Crosshair rendering (MEAS-05): HIGH - CrosshairView.update() already has zoomScale parameter that correctly scales edge positions for visual rendering. Dimension pill already uses unscaled distances.
- Arrow key peek (MEAS-03): HIGH for the edge detection part (same coordinate conversion). MEDIUM for the peek animation UX (new interaction pattern, but straightforward Core Animation).
- Drag-to-select (MEAS-04): HIGH - coordinate conversion is the same pattern applied to mouseDown/mouseDragged/mouseUp. Selection rendering with zoom tracking is a known pattern.
- Pitfalls: HIGH - all identified from direct analysis of the existing code paths and their interaction with zoom state.

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable internal architecture, no external dependencies)
