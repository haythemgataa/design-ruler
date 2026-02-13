# Technology Stack: UI Enhancement APIs

**Project:** Design Ruler (macOS pixel inspector)
**Researched:** 2026-02-13
**Deployment Target:** macOS 13+ (Swift 5.9)
**Scope:** APIs for five specific enhancements to existing Raycast extension

---

## 1. CALayer Shake Animation (macOS Login Rejection Style)

### Recommended: `CAKeyframeAnimation` on `transform.translation.x` (additive)

| Property | Value | Why |
|----------|-------|-----|
| `keyPath` | `"transform.translation.x"` | Translates relative to current position without touching `frame`/`position` |
| `isAdditive` | `true` | Values are offsets from current position, not absolute coordinates |
| `values` | `[0, -10, 10, -8, 8, -4, 4, 0]` | Decreasing amplitude mimics macOS login rejection damping |
| `keyTimes` | `[0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1.0]` | Even distribution with slightly longer settle |
| `duration` | `0.35` | Matches macOS system shake feel |
| `timingFunction` | `.easeOut` | Natural deceleration |

**Confidence:** HIGH -- CAKeyframeAnimation has been in Core Animation since macOS 10.5. The additive + translation.x pattern is the standard approach. The existing codebase already uses CAKeyframeAnimation for the hint bar slide (`HintBarView.animateSlide`).

**Usage pattern (for a CALayer, not NSView):**

```swift
func shake(layer: CALayer) {
    let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
    anim.values = [0, -10, 10, -8, 8, -4, 4, 0]
    anim.keyTimes = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1.0].map { NSNumber(value: $0) }
    anim.duration = 0.35
    anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    anim.isAdditive = true
    anim.isRemovedOnCompletion = true
    layer.add(anim, forKey: "shake")
}
```

### What NOT to use

| Approach | Why Not |
|----------|---------|
| `NSView.animator().frame.origin` | Triggers layout; not GPU-composited; visually laggy |
| `CAKeyframeAnimation(keyPath: "position.x")` | Non-additive `position.x` is absolute -- the layer jumps to each value instead of offsetting from current position. Would need manual calculation of current position + offsets |
| `CABasicAnimation` with spring | Springs overshoot; the macOS login shake is a damped oscillation, not a spring bounce |
| `NSAnimationContext.runAnimationGroup` | AppKit-level animation; not as precise for layer-backed overlays; mixes abstraction layers |
| `CASpringAnimation` | Produces a single damped oscillation in one direction, not the back-and-forth shake pattern. Would need to chain multiple spring animations |

### Applying to sublayer groups

The existing pill layers (wBgLayer, hBgLayer, text layers) are all direct children of the root layer. To shake the pill as a unit, either:

1. **Add a container CALayer** wrapping all pill sublayers, then shake the container (cleanest)
2. **Apply the same animation to each pill layer** (simpler for retrofit but duplicates animation objects)

Recommendation: **Option 1** (container layer). The existing `pillLayers` computed property already groups them. Adding a `pillContainer` CALayer that parents all pill sublayers means one `shake()` call moves everything coherently.

---

## 2. NSCursor State Management

### Current Problem

The existing `RulerWindow.swift` has scattered NSCursor calls:
- `NSCursor.hide()` / `NSCursor.unhide()` in `CrosshairView`
- `NSCursor.crosshair.push()` / `NSCursor.pop()` in mouseDown/mouseUp
- `NSCursor.pointingHand.push()` / `NSCursor.pop()` in mouseMoved hover
- `NSCursor.pop()` + `NSCursor.hide()` in deactivate
- `NSCursor.unhide()` in `Ruler.handleExit()`

This is fragile. `hide()`/`unhide()` use a **reference-counted counter** internally -- each `hide()` increments, each `unhide()` decrements. An extra `hide()` without matching `unhide()` leaves the cursor permanently hidden. Same with `push()`/`pop()` -- unbalanced calls corrupt the cursor stack.

### Recommended: Centralized CursorState enum with balanced tracking

**Confidence:** HIGH -- NSCursor's push/pop/hide/unhide APIs have been stable since macOS 10.0. The counter behavior for hide/unhide is documented in Apple's API reference.

```swift
/// Centralized cursor state management.
/// Ensures balanced push/pop and hide/unhide calls.
final class CursorManager {
    enum CursorState {
        case systemCrosshair  // resetCursorRects provides crosshair
        case hidden           // custom CAShapeLayer crosshair drawn, system cursor hidden
        case pointingHand     // hovering over a selection
        case dragCrosshair    // dragging to create a selection
    }

    private(set) var state: CursorState = .systemCrosshair
    private var pushCount = 0
    private var hideCount = 0

    func transition(to newState: CursorState, window: NSWindow?, crosshairView: CrosshairView?) {
        guard newState != state else { return }
        let old = state
        state = newState

        // Undo old state
        switch old {
        case .systemCrosshair: break  // Nothing to undo
        case .hidden:
            balancedUnhide()
        case .pointingHand:
            balancedPop()
            balancedHide()
        case .dragCrosshair:
            balancedPop()
            balancedHide()
        }

        // Apply new state
        switch newState {
        case .systemCrosshair:
            break
        case .hidden:
            crosshairView?.invalidateSystemCursor()
            balancedHide()
        case .pointingHand:
            balancedUnhide()
            NSCursor.pointingHand.push()
            pushCount += 1
        case .dragCrosshair:
            balancedUnhide()
            NSCursor.crosshair.push()
            pushCount += 1
        }
    }

    func reset() {
        while pushCount > 0 { NSCursor.pop(); pushCount -= 1 }
        while hideCount > 0 { NSCursor.unhide(); hideCount -= 1 }
        state = .systemCrosshair
    }

    private func balancedHide() {
        NSCursor.hide()
        hideCount += 1
    }

    private func balancedUnhide() {
        if hideCount > 0 { NSCursor.unhide(); hideCount -= 1 }
    }

    private func balancedPop() {
        if pushCount > 0 { NSCursor.pop(); pushCount -= 1 }
    }
}
```

### Critical pitfalls

| Pitfall | Detail |
|---------|--------|
| **hide/unhide counter imbalance** | `hide()` increments an internal counter; `unhide()` decrements. If you call `hide()` twice but `unhide()` once, cursor stays hidden. The `reset()` method above fixes this on exit |
| **push/pop stack imbalance** | `pop()` with an empty stack is undefined behavior (no crash, but cursor state corrupts). Track count manually |
| **resetCursorRects timing** | `invalidateCursorRects(for:)` does not take effect immediately -- it posts an event for the next event loop iteration. Do not check cursor state immediately after calling it |
| **NSCursor.set() is ephemeral** | As documented in CLAUDE.md -- `set()` is overridden by the window's cursor rect management in the same event cycle. Always use `resetCursorRects` + `addCursorRect` for persistent cursors |

### What NOT to use

| Approach | Why Not |
|----------|---------|
| `NSCursor.set()` for persistent cursors | Overridden immediately by window cursor rect management |
| Calling `hide()`/`unhide()` without tracking | Counter imbalance leads to stuck hidden cursor on exit |
| Global `NSCursor.currentCursor` checks | Not reliable -- may not reflect actual visibility state |

---

## 3. DispatchSourceTimer for Process Lifetime Management

### Context

The existing app uses `NSApp.run()` which blocks. If the process gets stuck (e.g., edge detection infinite loop, capture hang), it becomes a zombie. A watchdog timer can detect this and force-terminate.

### Recommended: `DispatchSource.makeTimerSource` on a background queue

**Confidence:** HIGH -- DispatchSourceTimer is available since macOS 10.12 (our target is macOS 13+). Stable API, no deprecation notices.

```swift
final class ProcessWatchdog {
    private var timer: DispatchSourceTimer?
    private var lastHeartbeat: CFTimeInterval = CACurrentMediaTime()
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.raycast.design-ruler.watchdog")

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5.0, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = CACurrentMediaTime() - self.lastHeartbeat
            if elapsed > self.timeout {
                fputs("[WATCHDOG] No heartbeat for \(elapsed)s — force-terminating\n", stderr)
                exit(1)
            }
        }
        timer.resume()
        self.timer = timer
    }

    func heartbeat() {
        // Called from mouseMoved or other frequent events
        lastHeartbeat = CACurrentMediaTime()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }
}
```

### Critical pitfalls

| Pitfall | Detail |
|---------|--------|
| **Must resume before use** | Timer starts in suspended state. Forgetting `timer.resume()` means it never fires |
| **Cancel before dealloc** | Deallocating a suspended DispatchSource crashes (`EXC_BAD_INSTRUCTION`). Always `cancel()` first, or `resume()` then `cancel()` |
| **Never over-resume/over-suspend** | Calling `resume()` on an already resumed source or `suspend()` on an already suspended source crashes. Track state manually |
| **Retain cycle in event handler** | Use `[weak self]` in the event handler closure. The timer retains its handler, which would retain `self` strongly |
| **`exit(1)` vs `NSApp.terminate`** | `exit(1)` is immediate -- no cleanup, no delegate callbacks. Use for genuine zombie scenarios only. For graceful shutdown, dispatch to main queue and call `NSApp.terminate(nil)` |

### Alternative considered: `Timer.scheduledTimer`

`Timer` runs on the run loop, which means it won't fire if the main run loop is blocked (which is exactly the scenario we want to detect). `DispatchSourceTimer` runs on its own dispatch queue, independent of the main run loop. Use DispatchSourceTimer.

---

## 4. CALayer Bounds Clamping for Overlay Elements

### Context

The crosshair pill and selection overlay pills can extend beyond screen bounds when the cursor is near edges. Need to clamp layer positions within the visible area.

### Recommended: Manual frame clamping (NOT `masksToBounds`)

**Confidence:** HIGH -- This is a straightforward math operation. The existing codebase already does partial clamping in `layoutPill` (checking `pillX + totalPillW > vw - 12`), but it only handles left/right flip, not hard clamping to bounds.

**Why NOT `masksToBounds`:**
- `masksToBounds` clips rendering, it does not reposition. A pill at x=-20 would be cropped, not moved to x=0
- When combined with `cornerRadius`, `masksToBounds` triggers offscreen rendering (GPU performance hit)
- The pill has shadows (`shadowRadius`, `shadowOpacity`). `masksToBounds = true` clips shadows, making the pill look wrong

**Clamping pattern:**

```swift
/// Clamp a rect to stay within container bounds with padding.
func clampedFrame(_ frame: CGRect, within bounds: CGRect, padding: CGFloat = 8) -> CGRect {
    var result = frame
    // Horizontal
    if result.maxX > bounds.maxX - padding {
        result.origin.x = bounds.maxX - padding - result.width
    }
    if result.minX < bounds.minX + padding {
        result.origin.x = bounds.minX + padding
    }
    // Vertical
    if result.maxY > bounds.maxY - padding {
        result.origin.y = bounds.maxY - padding - result.height
    }
    if result.minY < bounds.minY + padding {
        result.origin.y = bounds.minY + padding
    }
    return result
}
```

Apply after computing pill position but before setting `layer.frame`. This is a pure function with zero performance cost.

### Where to apply

| Element | Current behavior | Fix |
|---------|-----------------|-----|
| Crosshair pill (CrosshairView) | Flips left/right and above/below, but can still clip at extreme corners | Clamp after flip logic |
| Selection pill (SelectionOverlay) | Flips above/below rect, no horizontal clamping | Clamp horizontally to screen width |
| Hint bar (HintBarView) | Already handles top/bottom, no edge clamping | Low priority -- centered, unlikely to overflow |

---

## 5. UserDefaults-Backed Preference Toggling with Transient UI Hints

### Context

The app already uses `UserDefaults.standard.bool(forKey:)` for the hint bar dismiss state (`com.raycast.design-ruler.hintBarDismissed`). Need a pattern for toggling preferences at runtime and showing brief visual feedback.

### Recommended: Direct `UserDefaults.standard` + transient CATextLayer overlay

**Confidence:** HIGH -- UserDefaults is the standard persistence API. The existing codebase already uses it.

**For reading/writing preferences:**

```swift
// Key constants
private enum PrefKey {
    static let hintBarDismissed = "com.raycast.design-ruler.hintBarDismissed"
    static let someNewPref = "com.raycast.design-ruler.someNewPref"
}

// Toggle
let current = UserDefaults.standard.bool(forKey: PrefKey.someNewPref)
UserDefaults.standard.set(!current, forKey: PrefKey.someNewPref)
```

**For transient UI feedback (brief "toast" overlay):**

```swift
/// Show a brief text hint that fades out after a delay.
func showTransientHint(_ text: String, on parentLayer: CALayer) {
    let bg = CAShapeLayer()
    let label = CATextLayer()

    // Configure bg + label (same style as pill)
    // ...

    parentLayer.addSublayer(bg)
    parentLayer.addSublayer(label)

    // Fade in
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.15)
    bg.opacity = 1
    label.opacity = 1
    CATransaction.commit()

    // Auto-remove after delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setCompletionBlock {
            bg.removeFromSuperlayer()
            label.removeFromSuperlayer()
        }
        bg.opacity = 0
        label.opacity = 0
        CATransaction.commit()
    }
}
```

### What NOT to use

| Approach | Why Not |
|----------|---------|
| `@AppStorage` / SwiftUI | The main overlay is AppKit + CALayer; mixing SwiftUI observation for a simple bool adds complexity for no benefit. HintBarView already uses SwiftUI hosting but that's encapsulated |
| `NotificationCenter` for pref changes | Overkill for in-process toggle. The toggling code and the UI code are in the same event handler |
| `KVO on UserDefaults` | Same -- unnecessary reactive machinery when the toggle is synchronous |
| Sindresorhus `Defaults` library | External dependency for something trivially handled by Foundation |

### Pattern for keyboard-triggered toggle

```swift
// In RulerWindow.keyDown:
case 42: // Backslash or some key
    let key = PrefKey.someFeature
    let newValue = !UserDefaults.standard.bool(forKey: key)
    UserDefaults.standard.set(newValue, forKey: key)
    applyPreference(key, value: newValue)
    showTransientHint(newValue ? "Feature On" : "Feature Off", on: crosshairView.layer!)
```

---

## API Availability Summary

| API | Minimum macOS | Our Target | Status |
|-----|---------------|------------|--------|
| `CAKeyframeAnimation` | 10.5 | 13.0 | Available |
| `NSCursor.push()`/`pop()` | 10.0 | 13.0 | Available |
| `NSCursor.hide()`/`unhide()` | 10.0 | 13.0 | Available |
| `DispatchSource.makeTimerSource` | 10.12 | 13.0 | Available |
| `CALayer.masksToBounds` | 10.5 | 13.0 | Available (but not recommended) |
| `UserDefaults.standard` | 10.0 | 13.0 | Available |
| `CATransaction` | 10.5 | 13.0 | Available |

All recommended APIs are well within our macOS 13+ deployment target. No availability concerns.

---

## No New Dependencies Required

All five enhancements use frameworks already imported in the project:

- **QuartzCore** (Core Animation) -- CAKeyframeAnimation, CATransaction, CALayer
- **AppKit** -- NSCursor, NSView
- **Dispatch** -- DispatchSource, DispatchQueue
- **Foundation** -- UserDefaults

Zero new packages or imports needed.

---

## Sources

- [CAKeyframeAnimation - Apple Developer Documentation](https://developer.apple.com/documentation/quartzcore/cakeyframeanimation)
- [NSCursor - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nscursor)
- [NSCursor.hide() - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nscursor/hide())
- [NSCursor.push() - Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nscursor/1532500-push)
- [DispatchSourceTimer - Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcetimer)
- [masksToBounds - Apple Developer Documentation](https://developer.apple.com/documentation/quartzcore/calayer/1410896-maskstobounds)
- [How to shake NSView in macOS - Swift Discovery](https://onmyway133.com/posts/how-to-shake-nsview-in-macos/)
- [Shake animation with Swift (GitHub Gist)](https://gist.github.com/mourad-brahim/cf0bfe9bec5f33a6ea66)
- [Aggressively Hiding the Cursor - Sam Soffes](https://soff.es/blog/aggressively-hiding-the-cursor)
- [A Background Repeating Timer in Swift - Daniel Galasko](https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9)
- [Design patterns for safe timer usage - Cocoa with Love](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html)
- [Improving Animation Performance - Apple Archive](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html)
- [UserDefaults - Apple Developer Documentation](https://developer.apple.com/documentation/foundation/userdefaults)
- [Shaking a macOS Window - Eric Dolecki](https://blog.ericd.net/2016/09/30/shaking-a-macos-window/)
