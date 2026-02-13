# Architecture

**Analysis Date:** 2026-02-13

## Pattern Overview

**Overall:** Thin TypeScript wrapper → Swift backend with multi-layered separation of concerns.

**Key Characteristics:**
- TypeScript entry point acts only as preference bridge; all logic in Swift
- Fullscreen overlay architecture: captures screenshot before window creation to avoid self-interference
- Coordinate system duality: AppKit (bottom-left origin) for UI, AX/CG (top-left origin) for pixel scanning
- Pixel-perfect edge detection via color-difference scanning with stabilization algorithm
- GPU-composited rendering using CALayers (no CPU-intensive draw() calls)
- Multi-monitor support: one window per screen with inter-window coordination
- Selection snappping via inward edge scanning from user-drawn rectangles

## Layers

**TypeScript Entry Point:**
- Purpose: Bridge between Raycast and Swift; read preferences, call Swift function
- Location: `src/design-ruler.ts`
- Contains: Single async command handler, preference extraction
- Depends on: `@raycast/api`, Swift binary `inspect()` function
- Used by: Raycast framework

**Swift Entry Point & Orchestration (Ruler):**
- Purpose: Application lifecycle, permission checks, multi-monitor coordination, event routing
- Location: `swift/Ruler/Sources/Ruler.swift`
- Contains: `@raycast func inspect()`, singleton `Ruler` class managing windows and state
- Depends on: `PermissionChecker`, `RulerWindow`, `EdgeDetector`, `NSApplication`
- Used by: Swift macro bridge, receives raycast invocation

**Window & Event Handling (RulerWindow):**
- Purpose: Fullscreen borderless window for single screen; mouse/keyboard event capture and dispatch
- Location: `swift/Ruler/Sources/RulerWindow.swift`
- Contains: `NSWindow` subclass, event handlers (mouseMoved, mouseDown/Up/Dragged, keyDown/Up)
- Depends on: `EdgeDetector`, `CrosshairView`, `HintBarView`, `SelectionManager`, `CoordinateConverter`
- Used by: `Ruler` (creates one per screen), coordinates multi-monitor activation

**Edge Detection & Analysis:**
- Purpose: Scan pixel buffer for color changes; track skip state; snap user selections
- Location: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift`
- Contains: Single `EdgeDetector` class with capture, scan, skip increment/decrement, snap methods
- Depends on: `ColorMap`, `DirectionalEdges`, `EdgeHit`, `CorrectionMode`
- Used by: `RulerWindow` on every mouse move, selection snapping

**Pixel Scanning Engine:**
- Purpose: Build pixel buffer from CGImage; scan in cardinal directions with stabilization; snap inward
- Location: `swift/Ruler/Sources/EdgeDetection/ColorMap.swift`
- Contains: `ColorMap` class wrapping raw RGBA pixel array, coordinate scaling, directional scan logic
- Depends on: `EdgeHit` (return type)
- Used by: `EdgeDetector`, called per coordinate lookup

**Edge Models:**
- Purpose: Represent detected edges and cursor state
- Location: `swift/Ruler/Sources/EdgeDetection/DirectionalEdges.swift`
- Contains: `EdgeHit` (distance + screen position + border absorbed flag), `DirectionalEdges` (all 4 directions + cursor)
- Depends on: None
- Used by: `ColorMap` (builds them), `RulerWindow` (passes to `CrosshairView` for rendering)

**Rendering (Crosshair):**
- Purpose: GPU-composited crosshair overlay with adaptive pill positioning and animations
- Location: `swift/Ruler/Sources/Rendering/CrosshairView.swift`
- Contains: `CrosshairView` (NSView subclass), CAShapeLayer-based lines and feet, CATextLayer pill
- Depends on: `CAShapeLayer`, `CATextLayer`, CoreText for font features
- Used by: `RulerWindow` as main content view

**Rendering (Selection Overlays):**
- Purpose: Manage visible selection boxes and drag-to-snap interactions
- Location: `swift/Ruler/Sources/Rendering/SelectionManager.swift`, `SelectionOverlay.swift`
- Contains: `SelectionManager` (drag lifecycle, hit testing), `SelectionOverlay` (individual rect visualization)
- Depends on: `EdgeDetector` (snap), `CALayer` (rendering)
- Used by: `RulerWindow` on mouse interactions

**Rendering (Hint Bar):**
- Purpose: Bottom-sliding keyboard shortcut hints; auto-repositioning away from notch
- Location: `swift/Ruler/Sources/Rendering/HintBarView.swift`, `HintBarContent.swift`
- Contains: `HintBarView` (NSView with layer-cached rendering), `HintBarContent` (key cap drawing)
- Depends on: NSBezierPath (key caps), CAAnimation (slide), UserDefaults (dismissal state)
- Used by: `RulerWindow` when not hidden by preference

**Utilities:**
- Purpose: Coordinate system conversion and permissions
- Location: `swift/Ruler/Sources/Utilities/CoordinateConverter.swift`, `Permissions/PermissionChecker.swift`
- Contains: Static enum `CoordinateConverter` (AppKit ↔ AX), enum `PermissionChecker` (screen recording check)
- Depends on: CoreGraphics (for permission APIs)
- Used by: `EdgeDetector`, `RulerWindow`, `Ruler`

## Data Flow

**Initialization Flow:**

1. User invokes extension from Raycast
2. `src/design-ruler.ts`: Read hideHintBar + corrections preferences, call Swift `inspect()`
3. `Ruler.inspect()` (Swift macro entry point): 1x1 warmup CGWindowListCreateImage, delegate to `Ruler.shared.run()`
4. `Ruler.run()`: Check permissions, enumerate all screens, capture each screen BEFORE creating windows
5. Create one `RulerWindow` per screen, wire callbacks, show all windows
6. Activate cursor screen's window; show initial pill state ("0000 × 0000")

**Mouse Move Flow:**

1. `RulerWindow.mouseMoved()`: Throttle to ~60fps, capture event
2. Convert window-local coords to screen AppKit coords
3. Call `edgeDetector.onMouseMoved()` at AppKit screen point
4. `EdgeDetector.onMouseMoved()`: Convert AppKit → AX, call `currentEdges()` (respects skip counts)
5. `ColorMap.scan()`: Lookup 4 direction edge hits in pixel buffer, return `DirectionalEdges`
6. `CrosshairView.update()`: Animate lines to edges, update pill W×H dimensions

**Edge Detection Process:**

1. Scan pixel-by-pixel in cardinal direction from cursor
2. On first color exceeding tolerance: enter "edge transition" mode
3. Track "candidate" color (first pixel of new region)
4. Accumulate stable count (3 consecutive pixels matching candidate within stabilizationTolerance=3)
5. On stability: lock new reference color, increment edges found, continue scanning
6. If skip count > edges found: return nil (skip this edge, keep scanning)
7. Final result: `EdgeHit` with distance + screen position + borderAbsorbed flag

**Selection Drag & Snap Flow:**

1. `RulerWindow.mouseDown()`: Start drag, create `SelectionOverlay` with zero size
2. `RulerWindow.mouseDragged()`: Update selection rect to cursor position
3. `RulerWindow.mouseUp()`: Call `SelectionManager.endDrag()`, trigger snap
4. `SelectionManager.endDrag()`: Pass user-drawn rect to `EdgeDetector.snapSelection()`
5. `EdgeDetector.snapSelection()`: Convert coords AppKit → AX, call `ColorMap.scanInward()`
6. `ColorMap.scanInward()`: Sample 7 points per side, scan inward from each, use min/max to find bounding box
7. Return snapped rect in AX coords; `SelectionManager` animates selection to snapped position

**Event Exit Flow:**

1. User presses ESC or `Ruler` initiates shutdown
2. `RulerWindow` calls `onRequestExit` callback
3. `Ruler.handleExit()`: Unhide cursor if first move received, close all windows, call `NSApp.terminate()`

## Key Abstractions

**EdgeDetector:**
- Purpose: Single source of truth for edge detection state (colorMap, skip counts, correction mode)
- Examples: `swift/Ruler/Sources/EdgeDetection/EdgeDetector.swift`
- Pattern: Singleton instance per screen, holds captured ColorMap, stateful skip counts reset on mouse move

**ColorMap:**
- Purpose: Encapsulate pixel buffer scanning with scale-aware coordinate conversion
- Examples: `swift/Ruler/Sources/EdgeDetection/ColorMap.swift`
- Pattern: Immutable snapshot of one screen's pixels, reused for all cursor positions until next capture

**CrosshairView:**
- Purpose: Abstract rendering complexity behind single layer update
- Examples: `swift/Ruler/Sources/Rendering/CrosshairView.swift`
- Pattern: CAShapeLayer for lines/feet, CATextLayer for pill; no draw() override; animations via CATransaction

**RulerWindow:**
- Purpose: Encapsulate fullscreen overlay event handling, coordinate multi-monitor interaction
- Examples: `swift/Ruler/Sources/RulerWindow.swift`
- Pattern: Fullscreen NSWindow subclass, routes all events to handlers, callbacks to Ruler for coordination

## Entry Points

**Swift Macro Entry (Public API):**
- Location: `swift/Ruler/Sources/Ruler.swift` line 4
- Triggers: Raycast framework calls `inspect(hideHintBar: Bool, corrections: String)`
- Responsibilities: Warmup CGWindowListCreateImage, delegate to Ruler.run()

**Ruler.run() (Internal Orchestration):**
- Location: `swift/Ruler/Sources/Ruler.swift` line 22
- Triggers: From @raycast func inspect
- Responsibilities: Permission check, screen enumeration, capture all screens, window creation, callback wiring, app.run()

**RulerWindow Event Handlers:**
- mouseMoved: Update crosshair on every move
- keyDown: Handle arrow keys (skip), ESC (exit), Shift+arrow (decrement)
- mouseDown/Dragged/Up: Drag-to-snap selection workflow
- mouseEntered: Switch between screens (multi-monitor)

## Error Handling

**Strategy:** Silent failures with fallback behavior; debug output to stderr.

**Patterns:**
- Missing permission: Alert shown via system (PermissionChecker), app exits gracefully
- Capture fails: Window still created, no background image (app still usable)
- colorMap is nil: onMouseMoved returns nil, crosshair doesn't update (visual stasis, no crash)
- Snap fails (edges not detected on all 4 sides): Selection discarded, cursor returns to crosshair
- Coordinate conversion: Fallback to 0 or 0 if NSScreen lookup fails

## Cross-Cutting Concerns

**Logging:** Debug via `fputs(..., stderr)` to macOS console; visible in Xcode or Console.app

**Validation:** Input clamping: pixel coords always in `[0, width-1]`, `[0, height-1]`; skip counts never negative

**Authentication:** Screen recording permission checked at startup (PermissionChecker), request shown to user

**Coordinate System Conversion:** All entry points from NSWindow/NSEvent convert to AX before pixel scanning; reverse conversion for final EdgeHit.screenPosition
