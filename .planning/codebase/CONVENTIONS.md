# Coding Conventions

**Analysis Date:** 2026-02-13

## Language Overview

This project uses two languages:
- **TypeScript** (entry point and preferences bridge, minimal code)
- **Swift** (all application logic, ~1800 lines)

## TypeScript Conventions

### File Organization

**Single entry file:**
- `src/design-ruler.ts` — thin wrapper that reads preferences and calls Swift

**Naming:**
- Files: lowercase with hyphens (e.g., `design-ruler.ts`)
- Interfaces: PascalCase (e.g., `Preferences`)

### Code Style

**Configuration:**
- ESLint: `eslint.config.js` uses `@raycast/eslint-config`
- TypeScript: `tsconfig.json` with `strict: true`, `target: ES2023`
- Prettier: v3.5.3 (auto-formatted via ESLint)

**Patterns:**
```typescript
// Type definitions for preferences
interface Preferences {
  hideHintBar: boolean;
  corrections: string;
}

// Default values with nullish coalescing
const { hideHintBar, corrections } = getPreferenceValues<Preferences>();
await inspect(hideHintBar ?? false, corrections ?? "smart");
```

### Import Order

1. External packages (`@raycast/api`)
2. Swift bridge (`swift:../swift/Ruler`)

**Example:**
```typescript
import { closeMainWindow, getPreferenceValues } from "@raycast/api";
import { inspect } from "swift:../swift/Ruler";
```

### Error Handling

TypeScript does not use try/catch. No error handling is performed in TypeScript layer — Raycast will catch and handle any exceptions from the Swift bridge.

---

## Swift Conventions

### File Organization

**Structure:**
```
swift/Ruler/Sources/
├── Ruler.swift                      # Entry point + singleton manager
├── RulerWindow.swift                # NSWindow subclass, event handling
├── EdgeDetection/
│   ├── EdgeDetector.swift           # Capture + edge detection logic
│   ├── ColorMap.swift               # Pixel buffer operations
│   └── DirectionalEdges.swift       # Data models (EdgeHit, DirectionalEdges)
├── Rendering/
│   ├── CrosshairView.swift          # GPU-composited crosshair (CAShapeLayer)
│   ├── HintBarView.swift            # Hint bar positioning + animation
│   ├── HintBarContent.swift         # SwiftUI hint bar visual
│   └── SelectionManager.swift       # Selection overlay management
├── Utilities/
│   └── CoordinateConverter.swift     # AppKit ↔ AX coordinate conversion
└── Permissions/
    └── PermissionChecker.swift      # Screen recording permission
```

### Naming Conventions

**Classes and Structs:** PascalCase
- Classes: `EdgeDetector`, `RulerWindow`, `ColorMap`
- Structs: `DirectionalEdges`, `EdgeHit`
- Enums: `CorrectionMode`, `CoordinateConverter` (enum as namespace)

**Functions and Variables:** camelCase
- Public functions: `capture()`, `scan()`, `update()`
- Private functions: `setupLayers()`, `currentEdges()`, `scanDirection()`
- Properties: `skipCounts`, `colorMap`, `screenBounds`

**Constants:** lowercase with underscores (file-scoped) or UPPER_CASE (compile-time)
```swift
private let crossFootHalf: CGFloat = 4.0
private let pillHeight: CGFloat = 24
private let toleranceTolerance = 3
```

**Enum cases:** camelCase
```swift
enum CorrectionMode: String {
    case smart = "smart"
    case include = "include"
    case none = "none"
}
```

### Class Design

**Singletons:**
- `Ruler.shared` — owns all windows and coordinates multi-monitor behavior
```swift
final class Ruler {
    static let shared = Ruler()
    private init() {}
}
```

**Final classes (prevent subclassing):**
```swift
final class RulerWindow: NSWindow { ... }
final class EdgeDetector { ... }
final class CrosshairView: NSView { ... }
```

**Access Control:**
- `private` — default for implementation details
- `private(set)` — read-only public access (e.g., `targetScreen`, `skipCounts`)
- `public` — only on exposed types (rarely used; most classes are internal)
- No `internal` keyword (default visibility)

**Example:**
```swift
final class EdgeDetector {
    private var colorMap: ColorMap?
    private(set) var skipCounts = (left: 0, right: 0, top: 0, bottom: 0)
    private var lastCursorPosition: CGPoint?
    var correctionMode: CorrectionMode = .smart  // public property

    private func currentEdges(at point: CGPoint) -> DirectionalEdges? { ... }
}
```

### Property Patterns

**Initialization:**
```swift
// Required properties (nil-checked before use)
private var colorMap: ColorMap?

// Forced unwrap (set before use, safe context)
private var edgeDetector: EdgeDetector!

// Value properties with defaults
private var skipCounts = (left: 0, right: 0, top: 0, bottom: 0)
private var screenBounds: CGRect = .zero
private var lastMoveTime: Double = 0
```

**Computed properties (rarely used in this codebase):**
```swift
var hasSelections: Bool { selectionManager.hasSelections }
```

**Lazy initialization:**
```swift
private static let font: NSFont = {
    let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
    // ... complex setup ...
    return ctFont as NSFont
}()
```

### Function Design

**Parameter naming:** Explicit, descriptive
```swift
func scan(from point: CGPoint, tolerance: UInt8 = 1,
          skipLeft: Int = 0, skipRight: Int = 0,
          skipTop: Int = 0, skipBottom: Int = 0,
          includeBorders: Bool = true) -> DirectionalEdges
```

**Return types:** Optionals for nullable results
```swift
func capture(screen: NSScreen) -> CGImage?
func onMouseMoved(at appKitPoint: NSPoint) -> DirectionalEdges?
func incrementSkip(_ direction: SkipDirection) -> DirectionalEdges?
```

**Void methods:** Rare; most methods return DirectionalEdges for chaining
```swift
func update(cursor: NSPoint, edges: DirectionalEdges)
func hideForDrag()  // Side effect only
```

**Size guidelines:**
- Functions ~10–50 lines typical (few exceed 100 lines)
- `RulerWindow.swift` is largest file (~370 lines) — event handling concentrated there

### Error Handling

**No explicit error handling** — single points of failure return `nil`:

```swift
// capture() returns nil if permission denied or CGWindowListCreateImage fails
func capture(screen: NSScreen) -> CGImage? {
    guard let cgImage = CGWindowListCreateImage(...) else { return nil }
    // ...
    return cgImage
}

// onMouseMoved() returns nil if colorMap not yet initialized
func onMouseMoved(at appKitPoint: NSPoint) -> DirectionalEdges? {
    guard let map = colorMap else { return nil }
    // ...
}
```

**Guard statements used for early exit:**
```swift
guard let hosting = hostingView else { return }
guard let container = contentView else { return }
guard !isAnimating else { return }
guard x >= 0, x < width, y >= 0, y < height else { ... }
```

**No try/catch** — Raycast Swift bridge handles exceptions.

### Logging & Debugging

**Debug output to stderr** (does not affect Raycast UI):
```swift
fputs("[DEBUG] screen.frame(AppKit)=\(frame) cgRect=\(cgRect) cgImage=\(cgImage.width)×\(cgImage.height) backing=\(screen.backingScaleFactor)\n", stderr)
```

**Format:**
- `[DEBUG]` prefix for classification
- Human-readable variable dumps with labels
- Newline terminator (`\n`)
- Stderr destination (not stdout)

**Common debug messages:**
- Screen coordinate conversions
- Edge detection success/failure
- Mouse state transitions (down→drag→up)
- Animation timing

**No `os.log` or `Logger`** — this codebase uses bare `fputs()` for simplicity.

### Comments & Documentation

**Rule:** Comments explain *why*, not *what* (code is self-documenting)

**Doc comments (three slashes):**
```swift
/// Capture full screen before window exists. Returns CGImage for window background.
func capture(screen: NSScreen) -> CGImage?

/// Fullscreen borderless window that captures mouse and keyboard events.
final class RulerWindow: NSWindow {
```

**Inline comments (rarely used):**
```swift
// Warm up CGWindowListCreateImage connection (1x1 capture absorbs cold-start penalty)
_ = CGWindowListCreateImage(...)

// When hideHintBar is toggled on, clear the backspace-dismiss flag
if hideHintBar {
    UserDefaults.standard.removeObject(forKey: "com.raycast.design-ruler.hintBarDismissed")
}
```

**Multi-line explanations:**
```swift
// Window is opaque — we have a fullscreen screenshot as background,
// no need for the compositor to blend with the actual desktop.
window.isOpaque = true
```

### Module Imports

**Organization:**
1. Foundation frameworks (AppKit, QuartzCore, etc.)
2. SwiftUI (if used)
3. Custom frameworks (RaycastSwiftMacros)

**Example:**
```swift
import AppKit
import QuartzCore

import RaycastSwiftMacros

@raycast func inspect(hideHintBar: Bool, corrections: String) { ... }
```

### Coordinate System Conventions

**Critical:** AppKit and CG use opposite origins — handled consistently via `CoordinateConverter`

**Where coordinates come from:**
- `NSPoint` from `NSEvent` → AppKit coords (bottom-left origin)
- `CGPoint` from pixel buffer → CG coords (top-left origin)
- `NSScreen.frame` → AppKit coords
- `CGWindowListCreateImage` arguments → CG coords

**Conversion pattern:**
```swift
// Mouse event (AppKit) → edge detection (AX)
let axPoint = CoordinateConverter.appKitToAX(appKitPoint)
let edges = currentEdges(at: axPoint)

// Back to window coords (AppKit)
let windowPoint = event.locationInWindow  // AppKit relative
crosshairView.update(cursor: windowPoint, edges: edges)
```

### CALayer Animation Patterns

**Transaction-based (instant updates):**
```swift
CATransaction.begin()
CATransaction.setDisableActions(true)
linesLayer.opacity = 0
CATransaction.commit()
```

**Explicit animation (0.15s easeOut):**
```swift
let anim = CABasicAnimation(keyPath: "position.y")
anim.fromValue = currentPos
anim.toValue = finalY
anim.duration = 0.15
anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
layer.add(anim, forKey: "pillSlide")
```

**Keyframe animation (multi-phase):**
```swift
let anim = CAKeyframeAnimation(keyPath: "position.y")
anim.values = [currentPos, offscreenExit, offscreenEntry, finalY]
anim.keyTimes = [0, 0.1, 0.1, 1]  // phase timing
anim.timingFunctions = [easeOut, easeOut, easeOut]
```

### Callback Patterns

**Weak self + optional chaining** (prevent retain cycles):
```swift
rulerWindow.onActivate = { [weak self] window in
    self?.activateWindow(window)
}

rulerWindow.onRequestExit = { [weak self] in
    self?.handleExit()
}
```

**Non-optional closures where safe:**
```swift
rulerWindow.onFirstMove = { [weak self] in
    self?.handleFirstMove()
}
```

### Type Aliases

**Tuple aliases for skip counts:**
```swift
private var skipCounts = (left: 0, right: 0, top: 0, bottom: 0)
```

**No custom type aliases** for simple types (Int, CGFloat, etc.) — use native types directly.

---

## Code Quality Patterns

### Force-Unwrapping

**Allowed only when safe:**
```swift
final class Ruler {
    private init() {}
    // Safe: init is private, shared is constant
    static let shared = Ruler()
}

let cursorScreen = ... ?? NSScreen.main!
// Safe: NSScreen.main is guaranteed if no external screens
```

**Avoided otherwise:**
```swift
// ✓ Safe unwrap
guard let map = colorMap else { return nil }
let edges = map.scan(...)

// ✗ Force unwrap avoided
let edges = colorMap!.scan(...)  // never do this
```

### Nil Coalescing

**For preference defaults:**
```swift
await inspect(hideHintBar ?? false, corrections ?? "smart")
```

**For screen selection:**
```swift
let cursorScreen = NSScreen.screens.first { ... } ?? NSScreen.main!
```

### Enum Pattern Matching

**Exhaustive switching:**
```swift
switch Int(event.keyCode) {
case 123: // Left arrow
    let edges = shift ? edgeDetector.decrementSkip(.right) : edgeDetector.incrementSkip(.left)
case 124: // Right arrow
    let edges = shift ? edgeDetector.decrementSkip(.left) : edgeDetector.incrementSkip(.right)
// ... more cases
default: break
}
```

**No default for enum exhaustiveness:**
```swift
switch correctionMode {
case .smart: ...
case .include: ...
case .none: ...
}  // Compiler error if any case missing
```

### Code Organization Within Files

**Typical file structure:**
1. Imports
2. Type definition (class/struct)
3. Public interface (init, main public methods)
4. MARK: sections for private helpers (e.g., `// MARK: - Event Handling`)
5. Private implementation

**Example:**
```swift
import AppKit

final class RulerWindow: NSWindow {
    // MARK: - Public properties
    private(set) var targetScreen: NSScreen!
    var onActivate: ((RulerWindow) -> Void)?

    // MARK: - Init & setup
    static func create(for screen: NSScreen, ...) -> RulerWindow { ... }

    // MARK: - Multi-monitor coordination
    override func mouseEntered(with event: NSEvent) { ... }

    // MARK: - Event Handling
    override func mouseMoved(with event: NSEvent) { ... }

    private func setupViews(...) { ... }
}
```

---

## Build & Configuration

**Swift tools version:** 5.9
**macOS minimum:** 13
**Dependencies:** RaycastSwiftMacros (v1.0.4+)

**No SwiftFormat/SwiftLint** — code style is ad-hoc, manually maintained.

---

*Convention analysis: 2026-02-13*
