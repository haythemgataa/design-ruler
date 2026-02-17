# Design Ruler — Build Blueprint

Complete guide for building and maintaining this Raycast extension.

---

## 1. What This Extension Does

Two Raycast commands for macOS pixel inspection and alignment verification:

**Design Ruler** — Fullscreen overlay (frozen screenshot), crosshair follows
cursor showing detected edges in 4 directions with live "W × H" dimensions.
Arrow keys skip past edges. Drag to select regions (snap-to-edges). ESC exits.

**Alignment Guides** — Fullscreen overlay, click to place guide lines
(vertical/horizontal). Tab toggles direction, spacebar cycles color (5
presets). Hover a line to see "Remove" state, click to delete. ESC exits.

Both commands support multi-monitor (one window per screen, cursor activates).

---

## 2. Architecture Overview

```
TypeScript (thin wrappers, ~13 lines each)
  ├─ src/design-ruler.ts  → import { inspect } from "swift:../swift/Ruler"
  └─ src/alignment-guides.ts → import { alignmentGuides } from "swift:../swift/Ruler"
       └─ Swift (all logic)
            ├─ Ruler.swift              — OverlayCoordinator subclass, design-ruler entry
            ├─ RulerWindow.swift        — OverlayWindow subclass, edge detection + drag
            ├─ EdgeDetection/
            │   ├─ EdgeDetector.swift       — capture + scan + skip state + smart corrections
            │   ├─ ColorMap.swift           — pixel buffer, color scanning, stabilization
            │   └─ DirectionalEdges.swift   — EdgeHit + DirectionalEdges models
            ├─ Rendering/
            │   ├─ PillRenderer.swift       — shared pill factories, font, paths, text, shadows
            │   ├─ CrosshairView.swift      — 4 lines, cross-feet, W×H pill (via PillRenderer)
            │   ├─ HintBarView.swift        — glass hint bar, slide animation, expand/collapse
            │   ├─ HintBarContent.swift     — SwiftUI keycap layouts, HintBarTextStyle
            │   ├─ SelectionManager.swift   — drag lifecycle, edge snapping, hover tracking
            │   └─ SelectionOverlay.swift   — selection rendering, snap animation, shake
            ├─ AlignmentGuides/
            │   ├─ AlignmentGuides.swift    — OverlayCoordinator subclass, alignment-guides entry
            │   ├─ AlignmentGuidesWindow.swift — OverlayWindow subclass, guide line management
            │   ├─ GuideLineManager.swift   — preview line, placed lines, hover detection
            │   ├─ GuideLine.swift          — line rendering, position pills (via PillRenderer)
            │   ├─ GuideLineStyle.swift     — 5 color presets (dynamic, red, green, orange, blue)
            │   └─ ColorCircleIndicator.swift — arc-based color indicator, debounced auto-hide
            ├─ Cursor/
            │   └─ CursorManager.swift      — state machine, 5 states, cursorUpdate pattern
            ├─ Utilities/
            │   ├─ OverlayCoordinator.swift — shared lifecycle base (warmup, permissions, exit)
            │   ├─ OverlayWindow.swift      — shared window base (config, tracking, throttle)
            │   ├─ ScreenCapture.swift      — shared CGWindowListCreateImage wrapper
            │   ├─ DesignTokens.swift       — centralized colors, radii, durations, BlendMode
            │   ├─ TransactionHelpers.swift  — CATransaction.instant{} and .animated{}
            │   └─ CoordinateConverter.swift — AppKit ↔ CG point + rect conversion
            └─ Permissions/
                └─ PermissionChecker.swift  — screen recording check/request
```

### Key Design Principles
- TypeScript does NOTHING except read preferences and call Swift.
- Shared base classes: `OverlayCoordinator` (lifecycle) and `OverlayWindow` (window setup).
  Each command subclasses both, providing only command-specific factory/hook overrides.
- Single class for edge detection (no ImageEdgeDetector wrapper).
- EdgeHit is minimal: just `distance` and `screenPosition`.
- Multi-monitor: `OverlayCoordinator.run()` captures all screens before creating any windows.
- CursorManager: centralized state machine using `NSCursor.set()` + `cursorUpdate(with:)`.
- Global state (color, direction) lives in coordinator subclasses, synced via callbacks.
- Design tokens: all shared colors, radii, durations, blend mode in `DesignTokens.swift`.
- Pill rendering: `PillRenderer` provides factories for all pill types (dimension, position, selection).

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
- Draw everything natively with NSBezierPath / CAShapeLayer
- For static overlays, render once into `layer.contents` bitmap

### NO AX Detection
Adds complexity with minimal benefit over image-based detection.

### NO Snap Engine
Snapping cursor to edges is disorienting. Arrow-key skipping is better.

### NO NSCursor push/pop or resetCursorRects
Pushed cursors and cursor rects get overridden by the system on borderless
windows. `CursorManager` uses `NSCursor.set()` directly and `OverlayWindow`
overrides `cursorUpdate(with:)` (via `.cursorUpdate` tracking area option)
to re-apply the correct cursor on every system callback.

### NO Absolute-Coordinate Paths for Animated Layers
`CAShapeLayer.path` with absolute screen coordinates morphs point-by-point
instead of sliding. Use `layer.frame` for position + local-origin `path`
so Core Animation can interpolate the frame's position.

### NO masksToBounds + Shadows on Same Layer
`masksToBounds = true` clips shadows. Use a parent "wrapper" layer for the
shadow, with the clipped content layer as a sublayer.

### NO fputs/Debug Logging in Production Code
Raycast may build debug configurations. Remove debug logging entirely
instead of gating with `#if DEBUG`.

### NO configure() Before setMode() on HintBarView
`HintBarView.setMode()` must be called BEFORE `configure()`. Calling
`configure()` first instantiates the wrong SwiftUI content views.

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

### Multi-Monitor
Use `mainScreen.frame.height` as the reference height for conversions:
```swift
let mainHeight = NSScreen.screens.first!.frame.height
let cgY = mainHeight - appKitY - height
```

---

## 5. Capture-Before-Window Pattern

Creating fullscreen windows steals focus — title bars gray out. Fix:

1. Capture ALL screens BEFORE creating ANY windows
2. Use captured images as window backgrounds (NSImageView)
3. Use the same capture data (ColorMap/CGImage) for edge detection
4. User sees frozen frames — no visible disruption

`OverlayCoordinator.run()` enforces the full sequence:

```swift
// Base run() orchestrates:
// 1. Warmup capture (1x1 pixel)
// 2. Permission check
// 3. Detect cursor screen (NSEvent.mouseLocation + NSMouseInRect)
// 4. resetCommandState()
// 5. captureAllScreens() — Ruler overrides to use EdgeDetector
// 6. setActivationPolicy(.accessory)
// 7. Cleanup old windows
// 8. createWindow() per screen — subclass factory
// 9. wireCallbacks() — subclass wiring
// 10. Show all windows, makeKey cursor screen, showInitialState()
// 11. Signal handler, inactivity timer, app.run()
```

The cursor screen gets the hint bar; other screens get `hideHintBar: true`.

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

### Smart Border Corrections
Three modes (`corrections` preference):
- **smart** — tries all 4 absorption combinations for 1px borders, picks
  the one landing on a 4px grid alignment
- **include** — always includes 1px borders in measurements
- **none** — no corrections, raw edge detection

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
// In CrosshairView — line layers use:
lineLayer.compositingFilter = BlendMode.difference  // from DesignTokens.swift
```

The W×H pill and hint bar use normal blend with a dark background so
text stays readable.

---

## 8. Rendering Performance Rules

### CAShapeLayer Updates (GPU-composited)
- No `draw()` override — only CALayer property updates on mouse move
- `CATransaction.instant { }` for instant updates (every mouse move)
- `CATransaction.animated(duration:) { }` for animated transitions
- `contentsScale = backingScaleFactor` on ALL layers for Retina sharpness
- Lines + feet in one `CATransaction.instant` block
- Pill in a separate block (animated on flip via `CATransaction.animated`, instant otherwise)
- Pill bg layers: use `frame` + local-origin `path` so `frame` animates
  on flip (absolute-coordinate paths morph instead of sliding)
- Raw `CATransaction.begin()`/`commit()` only for blocks needing `setCompletionBlock`

### Wrapper Layer Pattern for Shadows
When `masksToBounds = true` is needed for clipping (e.g., rounded corners),
shadows cannot render on the same layer. Use a parent wrapper layer for the
shadow, with the clipped content layer as a sublayer.

### HintBarView (static, renders ONCE)
- Override `wantsUpdateLayer` → `true`
- Render into NSBitmapImageRep, set as `layer.contents`
- Guard: `if layer.contents != nil { return }`
- Set `wantsLayer = true` when creating the view

### Target: <5% CPU During Mouse Movement

---

## 9. Hint Bar Behavior

### Layout
- Glass panel with adaptive brightness sampling (dark/light mode aware)
- macOS 26+: liquid glass morph via SwiftUI `GlassEffectContainer`
- Older macOS: `NSVisualEffectView` fallback
- Keycaps drawn with NSBezierPath (arrows, shift, space, tab, escape)

### States
- **Expanded**: full instructional text with keycap illustrations
- **Collapsed**: compact keycap-only bar
- Minimum 3-second expanded display before auto-collapse on first mouse move

### Positioning
- Default: bottom center, 20px margin
- When cursor near bottom: slide to top (48px margin to clear MacBook notch)
- Slide animation: two-phase CAAnimationGroup (slide-out 0.1s + slide-in
  0.15s), both easeOut. `isAnimating` guard prevents overlapping animations.

### Modes
- Design Ruler mode: arrow key hints
- Alignment Guides mode: tab, spacebar, click hints

### Critical Setup Order
`HintBarView.setMode()` MUST be called BEFORE `configure()`.
`OverlayWindow.setupHintBar()` enforces this order automatically.

### Preference
- `hideHintBar`: hides hint bar entirely
- Hint bar only shown on cursor's screen (multi-monitor)

---

## 10. User Preferences

| Name | Type | Default | Scope | Description |
|------|------|---------|-------|-------------|
| hideHintBar | checkbox | false | both commands | Hide the keyboard shortcut hint bar |
| corrections | dropdown | smart | design-ruler only | How to handle 1px borders: smart, include, none |

---

## 11. Key Behaviors

### Design Ruler
- **Launch**: captures all screens, fullscreen overlays appear, cursor hidden,
  CAShapeLayer crosshair renders, pill fades in at cursor with "0000 × 0000"
- **Mouse move**: crosshair follows cursor, edges detected, W×H updates.
- **Arrow keys**: skip to next edge in that direction
- **Shift+arrow**: un-skip (bring edge closer)
- **Mouse move**: resets all skip counts
- **Drag**: select region with snap-to-edges (minimum 4x4px, shake on too-small)
- **Hover selection**: pointing hand cursor, click to remove
- **ESC**: exits silently (unhides cursor only if mouse had moved)
- **Pill flip**: animates 0.15s easeOut when swapping sides near edges

### Alignment Guides
- **Launch**: captures all screens, fullscreen overlays, preview line follows cursor
- **Tab**: toggle preview direction (vertical ↔ horizontal)
- **Spacebar**: cycle color (dynamic → red → green → orange → blue)
- **Click**: place guide line at cursor (with position pill showing X or Y coord)
- **Hover placed line**: 5px threshold, line turns red+dashed, "Remove" pill,
  pointing hand cursor
- **Click hovered line**: removes it (shrink-to-click-point animation)
- **Conflict resolution**: hover-first — clicking a hovered line removes it;
  clicking where no line is hovered places a new one
- **ESC**: exits

### Shared
- Multi-monitor: one window per screen, mouse enter/exit activates
- Hint bar: expanded → collapsed after 3s, bottom ↔ top slide
- 10-minute inactivity watchdog auto-exits
- SIGTERM handler for clean cursor restoration
- CGWindowListCreateImage warmup capture on launch (1x1 pixel, absorbs cold-start)

---

## 12. Animations

All animations use Core Animation (GPU-composited, ~0 CPU cost).

### Pill Position Swap (CrosshairView)
When the pill flips sides (right↔left near screen edge, above↔below near
top), the translation animates 0.15s easeOut instead of jumping instantly.
Implemented by splitting `update()` into two CATransaction blocks: lines/feet
always instant, pill conditionally animated when flip detected via
`pillIsOnLeft`/`pillIsBelow` state booleans.

### Hint Bar Slide (HintBarView)
Two-phase `CAAnimationGroup` on `position.y`: slide-out (0.1s easeOut) then
slide-in (0.15s easeOut, `beginTime` 0.1). Model value (`frame.origin.y`)
set immediately; animation overrides presentation layer. `isAnimating` flag
prevents overlapping animations.

### Cursor on Launch
- **Design Ruler**: `CursorManager.shared.hide()` called in
  `RulerWindow.showInitialState()`. Cursor is hidden immediately; the
  CAShapeLayer crosshair renders from the start.
- **Alignment Guides**: `CursorManager.shared.showResize(cursor)` called in
  `AlignmentGuidesWindow.showInitialState()`. Resize cursor visible immediately.

Both use `OverlayWindow`'s `cursorUpdate(with:)` override to maintain cursor
state against system resets.

### Pill Initialization (CrosshairView)
On launch, pill appears at cursor position with "0000 × 0000" and fades in
over 0.3s easeOut. `showInitialPill(at:)` sets all pill layer opacities to 0
in `CATransaction.instant { }`, calls `layoutPill()`, then animates
opacity to 1.

### Selection Snap (SelectionOverlay)
When a drag-to-select snaps to a detected edge, the selection boundary
animates to the snapped position.

### Selection Shake (SelectionOverlay)
When a selection is too small (< 4x4px), a shake animation provides
feedback before the selection is dismissed.

### Guide Line Shrink-to-Point (GuideLine)
On removal, the guide line shrinks toward the click point. Anchor point
is adjusted so the shrink animation moves toward the specific click
position rather than the layer center.

### Color Circle Indicator (ColorCircleIndicator)
Arc layout (~108 degrees, 5 circles). Active circle is larger with white
border. Fade-in on appearance, debounced auto-hide after ~1s via
`DispatchWorkItem`.

### Fade-In Pattern
Standard pattern used across the codebase:
```swift
setOpacity(0, animated: false)  // instant transparent
setOpacity(1, animated: true)   // fade in
```

---

## 13. Multi-Monitor Coordination

### Window Lifecycle
Managed by `OverlayCoordinator.run()`:
1. Capture ALL screens before creating ANY windows
2. Create one window per screen via subclass `createWindow()` factory
3. Hint bar only on cursor's launch screen
4. `orderFrontRegardless()` all windows, then `makeKey()` cursor screen

### Activation
- `OverlayWindow.mouseEntered` → `handleActivation()` → typed `onActivate` callback
- `OverlayCoordinator` base tracks `activeWindow`
- `deactivate()` old window → `activate()` new window
- `firstMoveAlreadyReceived` passed to new window on activation

### Global State Sync (Alignment Guides)
- `currentStyle` and `currentDirection` live in `AlignmentGuides` coordinator subclass
- On spacebar/tab: active window performs action, coordinator reads back state
- On activation: new window receives current style/direction via `activate()`

### Cursor Position Initialization
`OverlayWindow.initCursorPosition()` initializes `lastCursorPosition` from
`NSEvent.mouseLocation - screenBounds.origin` to avoid (0,0) artifacts.
Called by subclasses in `showInitialState()` and `activate()`.

---

## 14. CursorManager

Centralized state machine (`CursorManager.swift`) with 5 states:

```
Ruler:  idle ─hide()─▶ hidden ◀─transitionBack()─ pointingHand / crosshairDrag
Guides: idle ─showResize()─▶ resize ◀─transitionBack()─ pointingHand
```

- **idle**: default, no cursor modifications active
- **hidden**: Ruler mode — cursor hidden, CAShapeLayer crosshair renders
- **resize**: Guides mode — resize cursor (left-right or up-down)
- **pointingHand**: hovering a selection/guide line
- **crosshairDrag**: during drag-to-select (Ruler only)

Uses `NSCursor.set()` (not push/pop) because borderless overlay windows
override pushed cursors. `OverlayWindow.cursorUpdate(with:)` calls
`CursorManager.applyCursor()` to re-apply on every system callback.

Key methods:
- `hide()` — Ruler launch (sets base state to .hidden)
- `showResize(_:)` — Guides launch (sets base state to .resize)
- `updateResize(_:)` — swap resize cursor direction (Tab toggle)
- `transitionToPointingHand()` — hover (from .hidden or .resize)
- `transitionToCrosshairDrag()` — drag start (from .hidden)
- `transitionBack()` — return to base state (.hidden or .resize)
- `applyCursor()` — re-apply current cursor (called by cursorUpdate)
- `restore()` — unconditional cleanup for exit (unhide all, arrow cursor)

SIGTERM handler in `OverlayCoordinator` base calls `CursorManager.shared.restore()`.

---

## 15. Swift Bridge Pattern

TypeScript:
```typescript
// design-ruler.ts
import { inspect } from "swift:../swift/Ruler";
await inspect(hideHintBar ?? false, corrections ?? "smart");

// alignment-guides.ts
import { alignmentGuides } from "swift:../swift/Ruler";
await alignmentGuides(hideHintBar ?? false);
```

Swift:
```swift
// Ruler.swift
@raycast func inspect(hideHintBar: Bool, corrections: String) {
    Ruler.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}

// AlignmentGuides.swift
@raycast func alignmentGuides(hideHintBar: Bool) {
    AlignmentGuides.shared.run(hideHintBar: hideHintBar)
}
```

---

## 16. Learned Anti-Patterns

Bugs encountered and fixed — avoid re-introducing these:

- **Stabilization vs old reference**: In `ColorMap.scanDirection()`, compare
  stabilization pixels against the CANDIDATE color, not the old reference.
  With tolerance=1, the old reference always differs → stabilization never
  succeeds → lines disappear.

- **Remove-state stuck after deletion**: After `removeLine()`, immediately
  call `resetRemoveMode()` and `updatePreview()` to correctly reset the
  preview state. Otherwise the preview line stays in "Remove" mode.

- **Cursor position (0,0) on non-cursor monitors**: Initialize
  `lastCursorPosition` in `activate()` using `NSEvent.mouseLocation`
  converted to window-local coords. Without this, UI elements appear at
  (0,0) until the first mouse move on that screen.

---

## 17. Testing Checklist

### Design Ruler
- [ ] Launches on the screen where cursor is (not always main)
- [ ] No visible focus steal (capture-before-window works)
- [ ] Screenshot is crisp (Retina)
- [ ] Crosshair visible on both light and dark backgrounds
- [ ] Lines extend to edges or screen boundaries in all 4 directions
- [ ] Cross-foot marks only at detected edges
- [ ] W×H pill correct, flips at screen edges
- [ ] Arrow keys skip edges; shift+arrow reverses
- [ ] Mouse move resets skip counts
- [ ] Drag-to-select snaps to edges, minimum 4x4px enforced
- [ ] Hover selection shows pointing hand, click removes
- [ ] Smart/include/none corrections preference works
- [ ] ESC exits silently

### Alignment Guides
- [ ] Preview line follows cursor (vertical by default)
- [ ] Tab toggles vertical ↔ horizontal
- [ ] Click places guide line with position pill
- [ ] Spacebar cycles through 5 color presets
- [ ] Color circle indicator appears and auto-hides
- [ ] Hover placed line: red+dashed, "Remove" pill, pointing hand cursor
- [ ] Click hovered line removes with shrink animation
- [ ] ESC exits silently

### Shared
- [ ] Multi-monitor: windows on all screens, cursor activates correct one
- [ ] Hint bar expanded → collapsed after 3s
- [ ] Hint bar at bottom, shifts to top when cursor near bottom
- [ ] Hint bar clears MacBook notch when at top
- [ ] hideHintBar preference works (both commands)
- [ ] CPU stays low (<5%) during mouse movement
- [ ] Ruler: cursor hidden on launch, CAShapeLayer crosshair visible
- [ ] Guides: resize cursor visible on launch
- [ ] 10-minute inactivity auto-exit works
- [ ] SIGTERM restores cursor state cleanly
- [ ] Pill shows "0000 × 0000" on launch, fades in (design ruler)
- [ ] Pill animates smoothly when flipping sides near edges
- [ ] Hint bar slides (not jumps) when swapping top/bottom
