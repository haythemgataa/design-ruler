# Testing Patterns

**Analysis Date:** 2026-02-13

## Current Testing Status

**Status:** No automated tests in production codebase

This is a single-command Raycast extension with no test files, test runners, or test configuration. Testing is entirely manual.

---

## Testing Framework (Not Used)

**Candidate frameworks (for reference):**
- XCTest (built into Swift, would be: `Tests/RulerTests/`)
- XCUITest (for UI automation)

**Why not currently used:**
- Raycast Swift extensions are tightly coupled to macOS AppKit APIs (NSWindow, NSEvent, CALayer)
- Heavy reliance on system state (screen geometry, cursor position, graphics capture)
- UI layer is synchronous (CAShapeLayer animations, NSWindow event handling)
- Manual testing on physical hardware was prioritized over unit test infrastructure

---

## Manual Testing Checklist

The codebase includes this checklist in `CLAUDE.md` (reference documentation):

**Functional Tests:**
- Launches on the screen where cursor is (not always main)
- No visible focus steal (screenshot captured before window creation)
- Screenshot is crisp (Retina @2x)
- Crosshair visible on both light and dark backgrounds
- Lines extend to edges or screen boundaries in all 4 directions
- Cross-foot marks only at detected edges (not screen boundaries)
- W×H pill correct, flips at screen edges
- Arrow keys skip edges; Shift+arrow reverses
- Mouse move resets skip counts
- ESC exits silently
- Hint bar at bottom, shifts to top when cursor near bottom
- `hideHintBar` preference works
- CPU stays low (<5%) during mouse movement

**Animation Tests:**
- System crosshair cursor visible on launch (before mouse move)
- Crosshair cursor disappears on first mouse move
- Pill shows "0000 × 0000" on launch, fades in (0.3s)
- Pill animates smoothly (background + text) when flipping sides near edges
- Hint bar slides (not jumps) when swapping top/bottom
- Hint bar clears MacBook notch when at top

---

## Debugging Infrastructure

### Debug Output

**Framework:** Direct `fputs()` to stderr (no logging library)

**Locations:**
- `EdgeDetector.swift` — screen coordinate conversions, edge detection state
- `RulerWindow.swift` — mouse event state (down/drag/up transitions)

**Examples:**
```swift
// EdgeDetector.swift
fputs("[DEBUG] screen.frame(AppKit)=\(frame) cgRect=\(cgRect) cgImage=\(cgImage.width)×\(cgImage.height) backing=\(screen.backingScaleFactor)\n", stderr)
fputs("[DEBUG] onMouseMoved: currentEdges returned nil (colorMap=\(colorMap == nil ? "nil" : "exists")) at \(axPoint)\n", stderr)

// RulerWindow.swift
fputs("[DEBUG] mouseDown: isDragging was still true, resetting stale state\n", stderr)
fputs("[DEBUG] mouseDown: starting drag at \(windowPoint), selections=\(selectionManager.hasSelections)\n", stderr)
fputs("[DEBUG] mouseDragged: rejected — isDragging is false\n", stderr)
fputs("[DEBUG] mouseUp: rejected — isDragging is false\n", stderr)
```

**Running locally:**
```bash
# Terminal 1: Start development version
npm run dev

# Terminal 2: Watch stderr output
# (stderr is printed to console after command completes)
```

### Zombie Process Cleanup

Because this is a macOS fullscreen overlay, processes may not auto-terminate:

```bash
# Check for stuck Ruler processes
ps aux | grep Ruler

# Kill stale process
pkill -9 -f "Ruler inspect"
```

---

## Testing Patterns (If Tests Were Added)

### Coordinate System Tests

The most critical area for testing — AppKit and CG have opposite origins:

**If unit tests existed, they would test:**

```swift
// Hypothetical test (pseudo-code)
func testCoordinateConversion() {
    let appKitPoint = NSPoint(x: 100, y: 200)
    let axPoint = CoordinateConverter.appKitToAX(appKitPoint)
    // Assert y-coordinate flipped
    XCTAssertEqual(axPoint.y, NSScreen.main!.frame.height - 200)
}
```

**Key invariants:**
- AppKit y-coordinate increases upward
- CG y-coordinate increases downward
- Conversion must be bidirectional (appKitToAX and axToAppKit are inverses)

### Edge Detection Tests

If testable, these would verify color comparison algorithm:

**Critical logic (ColorMap.swift):**
```swift
// Stabilization algorithm — hard to test without screenshot data
// Would need fixture screenshots of various UI patterns
// Tests would validate:
// 1. Edge detection accuracy (±1px tolerance)
// 2. Stabilization prevents flickering
// 3. Skip counts correctly increment/decrement
// 4. Border correction modes (smart/include/none) produce expected results
```

**Fragile areas:**
- `stabilizationTolerance = 3` — magic number, would benefit from property-based testing
- Skip count reset on mouse move — state machine hard to test without events
- Color comparison with Retina scale factor (pixel vs. point coordinates)

### Animation State Tests

If added, would test layer state transitions:

```swift
// Hypothetical tests
func testCrosshairVisibilityDuringDrag() {
    // Assert: all layer opacities set to 0
    view.hideForDrag()
    XCTAssertEqual(linesLayer.opacity, 0)
}

func testPillPositionAnimatesOnFlip() {
    // Assert: animation added to layer
    // Assert: animation duration = 0.15s
    // Assert: final position is correct
}
```

---

## Code Coverage

**No coverage reporting** — no test infrastructure exists.

---

## Static Analysis & Linting

**None used** — relied on Swift compiler warnings and manual code review.

**If enforced, would recommend:**
- SwiftLint (for style rules)
- SwiftFormat (for automatic formatting)
- Xcode's built-in warnings (address all by default)

---

## Integration Testing Approach

Because this is a Raycast extension, integration testing would require:

1. **Launch the extension from Raycast CLI:**
   ```bash
   npm run dev
   ```

2. **Verify behavior manually:**
   - Move mouse to different screens
   - Test edge detection on various UI elements
   - Verify hint bar appears/disappears correctly
   - Test keyboard shortcuts (arrows, Shift, ESC, Backspace)

3. **Monitor performance:**
   - Activity Monitor: CPU should stay <5% at rest
   - Memory: should not grow unbounded
   - Screenshot capture: first capture ~50ms (cold), subsequent ~3ms

4. **Test on multiple displays:**
   - Primary screen (built-in)
   - Secondary display (external monitor)
   - Retina (@2x) and non-Retina displays
   - Different refresh rates (60Hz, 120Hz, 144Hz)

---

## Performance Testing

**Manual profiling with Activity Monitor:**

1. **CPU usage:**
   - Idle: <1%
   - Mouse moving: <5%
   - During drag: <3%

2. **Screenshot capture (one-time):**
   - First `CGWindowListCreateImage` call: ~50ms cold start
   - After warmup (1x1 pixel capture): ~3ms per full screenshot
   - All screens captured before window creation

3. **Frame rate:**
   - Mouse move throttled to ~60fps (0.014s minimum between updates)
   - CALayer animations GPU-composited (no CPU cost)

**If regression detected:**
- Profile with Instruments (Time Profiler, System Trace)
- Common bottlenecks: pixel scanning, color comparison, screenshot capture

---

## End-to-End Testing Notes

### Multi-Monitor Setup

Testing critical paths with multiple displays:

1. **Screen selection at launch:**
   - Cursor on primary screen → window on primary
   - Cursor on secondary screen → window on secondary (background on primary still visible)

2. **Monitor disconnection:**
   - Current implementation: all windows close (NSScreen.screens array changes)
   - No graceful degradation tested

### Accessibility & Dark Mode

**Manual testing:**
- Light mode: orange crosshair visible (difference blend darkens it)
- Dark mode: orange crosshair visible (difference blend lightens it)
- High contrast mode: untested

**Hint bar:**
- Dark background text readable on all themes
- Keyboard key caps visible

### Edge Cases Not Tested Automatically

- Very small windows (<10px)
- Single-color regions (no edges)
- Transparency/RGBA backgrounds
- Animated content (GIFs, videos)
- Multiple selection overlays (new feature)
- Rapid mouse movement (cursor skips pixels)

---

## Continuous Integration

**Not configured** — no CI pipeline exists.

**If added, would need:**
- Xcode environment for Swift compilation
- macOS 13+ runner (AppKit is macOS-only)
- Manual testing step (UI automation not practical)
- Artifact building (`ray build` produces binary)

---

## Testing Strategy Going Forward

If unit tests were to be added, prioritize:

1. **Coordinate system conversions** (`CoordinateConverter.swift`)
   - Easiest to test (pure functions, no side effects)
   - Highest impact (bug here affects all rendering)

2. **Edge detection algorithm** (`ColorMap.scanDirection()`)
   - Requires fixture screenshot data
   - Property-based testing for tolerance thresholds

3. **State machine in RulerWindow**
   - Drag state transitions (down → dragging → up)
   - Hover state (selection underlay)
   - Mock NSEvent, NSScreen

**NOT worth testing (UI/system-dependent):**
- CALayer animation state (hard to observe, GPU-side)
- NSCursor visibility (system-managed, hard to verify)
- Screenshot capture (depends on what's on screen)
- Raycast preference reading (mock via test harness)

---

*Testing analysis: 2026-02-13*
