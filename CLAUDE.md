# Ruler v2 — Build Blueprint

Complete guide for building this Raycast extension from scratch.

---

## 1. What This Extension Does

A macOS pixel inspector launched from Raycast. The user invokes it, a
fullscreen overlay appears (frozen screenshot of the current screen), and
a crosshair follows the cursor showing detected edges in 4 directions
with live "W × H" dimensions. Arrow keys skip past edges. ESC exits.

No measurement between two points. No dragging. Just inspect and see.

---

## 2. Architecture Overview

```
TypeScript (thin wrapper, ~10 lines)
  └─ import { inspect } from "swift:../swift/Ruler"
       └─ Swift (all logic)
            ├─ Ruler.swift          — entry point, window setup, event wiring
            ├─ RulerWindow.swift    — NSWindow subclass, mouseMoved + keyDown only
            ├─ EdgeDetection/
            │   ├─ EdgeDetector.swift   — capture + scan + skip state (single class)
            │   ├─ ColorMap.swift       — pixel buffer, color comparison scanning
            │   └─ DirectionalEdges.swift — EdgeHit + DirectionalEdges models
            ├─ Rendering/
            │   ├─ CrosshairView.swift  — 4 lines, cross-feet, W×H pill
            │   └─ HintBarView.swift    — keyboard shortcut hints, layer-cached
            ├─ Utilities/
            │   └─ CoordinateConverter.swift
            └─ Permissions/
                └─ PermissionChecker.swift
```

### Key Design Principles
- TypeScript does NOTHING except call Swift. No preferences passed.
- No measurement state — no start/end points, no distance calculation.
- Single class for edge detection (no ImageEdgeDetector wrapper).
- EdgeHit is minimal: just `distance` and `screenPosition`. No `source`
  enum, no `confidence` float.

---

## 3. What NOT To Do

### NO Bundle.module Resources
Raycast only deploys the Swift **binary** — not `.bundle` directories.
`Bundle.module` crashes at runtime.
- Do NOT add `resources:` to Package.swift
- Embed everything inline in Swift source code

### NO SVG Rendering via NSImage
NSImage from SVG with filter effects (drop shadows, blur) causes **80%+
CPU** because AppKit re-renders the SVG on every draw call.
- Draw everything natively with NSBezierPath
- For static overlays, render once into `layer.contents` bitmap

### NO AX Detection
Adds complexity with minimal benefit over image-based detection.

### NO Snap Engine
Snapping cursor to edges is disorienting. Arrow-key skipping is better.

---

## 4. Coordinate Systems — The #1 Source of Bugs

- **AppKit**: origin at BOTTOM-LEFT (y increases upward)
- **CG (CoreGraphics)**: origin at TOP-LEFT (y increases downward)

### Rules
- Mouse events from NSWindow → AppKit coords
- CGWindowListCreateImage → CG coords
- ColorMap pixel buffer → CG coords
- CrosshairView draws in AppKit coords
- EdgeHit.screenPosition → CG coords

### Conversion
```swift
let appKitY = screenHeight - cgY
```

---

## 5. Screenshot-Before-Window Pattern

Creating a fullscreen window steals focus — title bars gray out. Fix:

1. Capture the screen where the cursor is BEFORE creating the window
2. Use the captured image as the window background (NSImageView)
3. Use the same capture data (ColorMap) for edge detection
4. User sees a frozen frame — no visible disruption

```swift
func run() {
    let cursorScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                       ?? NSScreen.main!
    let screenshot = edgeDetector.capture(screen: cursorScreen)
    let window = RulerWindow(for: cursorScreen)
    if let img = screenshot { window.setBackground(img) }
    window.makeKeyAndOrderFront(nil)
}
```

### Screen Selection
Capture the screen where the cursor is located at launch time, NOT always
the main screen. Use `NSEvent.mouseLocation` + `NSMouseInRect` to find it.

---

## 6. Edge Detection Algorithm

### Core: Color Comparison Scanning
From cursor, walk pixel-by-pixel in 4 cardinal directions. Stop when
color difference exceeds tolerance.

```
tolerance = 1 (max sensitivity)
difference = max(|dR|, |dG|, |dB|)
if difference > tolerance → edge found
```

### Retina Scale Factor
```swift
let scale = CGFloat(pixelWidth) / screenFrame.width  // 2.0 on Retina
```
- Point-to-pixel: multiply by scale
- Pixel-to-point: divide by scale
- Clamp pixel coords to `[0, width-1]` / `[0, height-1]`

### Edge Skipping (Arrow Keys)
Skip counts per direction. Arrow key increments, shift+arrow decrements,
mouse move resets all to 0.

**Stabilization algorithm**:
```
1. Detect edge (color exceeds tolerance vs current reference)
2. Enter "transition" mode
3. Track a "candidate" color (first pixel of potential new region)
4. Compare subsequent pixels to the CANDIDATE (not old reference!)
5. If 3 consecutive pixels match candidate (within stabilizationTolerance=3):
   → Accept as new region, update reference color, increment edgesFound
6. If pixel differs from candidate: reset candidate to this pixel, count=1
```

**Critical bug to avoid**: Do NOT compare stabilization pixels against the
OLD reference color. The new region always differs from old with tolerance=1
→ stabilization never succeeds → returns nil → lines disappear.

### Screen Boundary Handling
- Clamp cursor pixel coords: `min(max(px, 0), width - 1)`
- When no edge detected (nil), use screen boundary as endpoint
- Always draw all 4 crosshair lines (to edge or to screen boundary)
- Only draw cross-foot marks at detected edges, not screen boundaries
- Dimension pill: `edges.left?.distance ?? (cursor.x - bounds.minX)`

---

## 7. Crosshair Color — Always Visible

Use orange with `CGBlendMode.difference` to invert against the background.
Dark backgrounds get bright lines, bright backgrounds get dark lines.

```swift
// In CrosshairView draw():
context.setBlendMode(.difference)
NSColor.orange.setStroke()
// draw lines + cross-feet...
context.setBlendMode(.normal)  // restore for pill/text
```

The W×H pill and hint bar use normal blend with a dark background so
text stays readable.

---

## 8. Rendering Performance Rules

### CrosshairView (redraws every mouse move)
- Minimal drawing: 4 lines + 4 optional cross-feet + 1 pill
- 0.5px offset for crisp 1pt strokes on Retina
- Sets `needsDisplay = true` in property didSet

### HintBarView (static, renders ONCE)
- Override `wantsUpdateLayer` → `true`
- Render into NSBitmapImageRep, set as `layer.contents`
- Guard: `if layer.contents != nil { return }`
- Set `wantsLayer = true` when creating the view
- Draw key caps with NSBezierPath

---

## 9. Hint Bar Behavior

- Always visible (default position: bottom center)
- When cursor gets near the bottom, shift hint bar to the top
- When cursor moves away, shift back to bottom
- One user preference: hide hint bar entirely
- Content: "Use [arrow keys] to skip an edge. Add [⇧] to invert."

---

## 10. User Preferences

| Name | Type | Default | Description |
|------|------|---------|-------------|
| hideHintBar | checkbox | false | Hide the keyboard shortcut hint bar |

Single preference. Passed to Swift as a parameter.

---

## 11. Key Behaviors

- **Launch**: captures cursor's screen, fullscreen overlay appears
- **Mouse move**: crosshair follows cursor, edges detected, W×H updates
- **Arrow keys**: skip to next edge in that direction
- **Shift+arrow**: un-skip (bring edge closer)
- **Mouse move**: resets all skip counts
- **ESC**: exits silently
- **Hint bar**: bottom (or top when cursor is near bottom)

---

## 12. Implementation Phases

### Phase 1: Project Scaffold
- `package.json` — 1 command (no-view), 1 preference (hideHintBar)
- `swift/Ruler/Package.swift` — macOS 12+, extensions-swift-tools
- `src/ruler.ts` — Read hideHintBar pref, call Swift

### Phase 2: Capture + Edge Detection
- `PermissionChecker.swift` — Screen recording check
- `EdgeDetector.swift` — Capture screen at `.bestResolution`, build ColorMap,
  scan method, skip state (all in one class)
- `ColorMap.swift` — Pixel buffer, scale factor, scanDirection with stabilization
- `DirectionalEdges.swift` — EdgeHit (distance + screenPosition) + DirectionalEdges

### Phase 3: Window + Crosshair
- `CoordinateConverter.swift` — AppKit ↔ CG conversion
- `RulerWindow.swift` — Fullscreen borderless window for cursor's screen,
  background image, mouseMoved + keyDown (arrows + ESC) only
- `Ruler.swift` — Entry point, capture-before-window, event wiring
- `CrosshairView.swift` — 4 lines (difference blend), cross-feet, W×H pill

### Phase 4: Edge Skipping
- Add skip counts + increment/decrement to EdgeDetector
- Add skip parameters to ColorMap.scan() and scanDirection()
- Implement stabilization algorithm
- Arrow key handling in RulerWindow

### Phase 5: Hint Bar
- `HintBarView.swift` — NSBezierPath drawing, layer-cached
- Position logic: bottom ↔ top based on cursor proximity
- Respect hideHintBar preference

---

## 13. Swift Bridge Pattern

TypeScript:
```typescript
import { inspect } from "swift:../swift/Ruler";
await inspect(preferences.hideHintBar);
```

Swift:
```swift
import RaycastSwiftMacros

@raycast func inspect(hideHintBar: Bool) {
    Ruler.shared.run(hideHintBar: hideHintBar)
}
```

---

## 14. Testing Checklist

- [ ] Launches on the screen where cursor is (not always main)
- [ ] No visible focus steal
- [ ] Screenshot is crisp (Retina)
- [ ] Crosshair visible on both light and dark backgrounds
- [ ] Lines extend to edges or screen boundaries in all 4 directions
- [ ] Cross-foot marks only at detected edges
- [ ] W×H pill correct, flips at screen edges
- [ ] Arrow keys skip edges; shift+arrow reverses
- [ ] Mouse move resets skip counts
- [ ] ESC exits silently
- [ ] Hint bar at bottom, shifts to top when cursor near bottom
- [ ] hideHintBar preference works
- [ ] CPU stays low (<5%) during mouse movement
