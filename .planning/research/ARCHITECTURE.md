# Architecture Patterns

**Domain:** macOS pixel inspector (Raycast extension) -- integration of enhancements into existing architecture
**Researched:** 2026-02-13

## Current Architecture (As-Is)

```
TypeScript (design-ruler.ts)
  |
  +-- inspect(hideHintBar, corrections) --> Swift binary
        |
        Ruler (singleton)
          +-- captures all screens
          +-- creates RulerWindow[] (one per monitor)
          +-- wires callbacks: onActivate / onRequestExit / onFirstMove
          +-- manages firstMoveReceived, NSCursor.unhide() on exit
          |
          RulerWindow (NSWindow subclass, per screen)
            +-- owns: CrosshairView, HintBarView, SelectionManager, EdgeDetector
            +-- routes: sendEvent() intercepts mouse events
            +-- state: isDragging, isHoveringSelection, hasReceivedFirstMove
            +-- cursor mgmt: push/pop/hide/unhide scattered across 9 call sites
            |
            CrosshairView (NSView, GPU-composited via CAShapeLayer)
              +-- linesLayer, 4x foot layers, pill layers (wBg, hBg, labels, values)
              +-- showSystemCrosshair bool + resetCursorRects()
              +-- hideSystemCrosshair() / skipSystemCrosshairPhase()
              +-- hideForDrag() / showAfterDrag()
              |
            HintBarView (NSView + NSHostingView<HintBarContent>)
              +-- slide animation (bottom <-> top)
              +-- key press/release visual feedback
              +-- backspace dismissal with UserDefaults persistence
              |
            SelectionManager
              +-- manages SelectionOverlay[] collection
              +-- drag lifecycle: start/update/end/cancel
              +-- hit testing + hover state
              |
            SelectionOverlay (pure CALayer composition)
              +-- rectLayer, fillLayer, pillBgLayer, pillTextLayer
              +-- snap animation, hover state transitions
              +-- added to CrosshairView.layer (parent)
```

### Key Design Invariants

1. **Ruler singleton** owns the lifecycle: capture -> window creation -> exit
2. **RulerWindow** is the sole event router (sendEvent override for mouse; keyDown/keyUp for keyboard)
3. **CrosshairView** never calls NSCursor directly except in `hideSystemCrosshair()` and `resetCursorRects()`
4. **SelectionOverlay** layers are children of CrosshairView's root layer
5. **No NSApplication delegate** -- Ruler calls `NSApp.run()` directly, `NSApp.terminate(nil)` to exit
6. **All rendering is GPU-composited** -- CAShapeLayer + CATextLayer, no `draw()` overrides

---

## Enhancement 1: Centralized CursorManager

### Problem

NSCursor push/pop/hide/unhide calls are scattered across 3 files with 18 total call sites:

| File | Call Sites | Operations |
|------|-----------|------------|
| `Ruler.swift` | 1 | `unhide()` on exit |
| `RulerWindow.swift` | 14 | `push()`, `pop()`, `hide()`, `unhide()` in mouseDown/Up/Moved, deactivate |
| `CrosshairView.swift` | 3 | `hide()` in hideSystemCrosshair, `resetCursorRects` + `invalidateCursorRects` |

The push/pop stack is fragile -- a missed `pop()` (e.g., when drag state gets stuck) leaves the wrong cursor visible. The existing `mouseDown` stale-state reset is evidence of this fragility.

### Recommended Architecture

```
CursorManager (new, in Utilities/)
  +-- enum CursorState: hidden, system, crosshair, pointingHand
  +-- private var stack: [CursorState] (replaces NSCursor stack)
  +-- transition(to:) -- handles all push/pop/hide/unhide
  +-- reset() -- force-unwind to known state (exit cleanup)
```

**Where it lives:** `swift/Ruler/Sources/Utilities/CursorManager.swift`

**Who owns it:** `Ruler` singleton creates it, passes it to each `RulerWindow` at creation time. This matches the existing pattern where Ruler owns shared state (like `firstMoveReceived`) and windows receive references.

**Integration points:**

| Current Call Site | New Call |
|-------------------|----------|
| `CrosshairView.hideSystemCrosshair()` | `cursorManager.transition(to: .hidden)` + invalidate cursor rects |
| `RulerWindow.mouseMoved` (hover enter) | `cursorManager.transition(to: .pointingHand)` |
| `RulerWindow.mouseMoved` (hover exit) | `cursorManager.transition(to: .hidden)` |
| `RulerWindow.mouseDown` (start drag) | `cursorManager.transition(to: .crosshair)` |
| `RulerWindow.mouseUp` (end drag) | `cursorManager.transition(to: .hidden)` |
| `RulerWindow.deactivate` | `cursorManager.transition(to: .hidden)` |
| `Ruler.handleExit` | `cursorManager.reset()` |

**API surface:**

```swift
final class CursorManager {
    enum CursorState { case system, hidden, crosshair, pointingHand }

    private(set) var state: CursorState = .system
    private var hideCount = 0  // tracks NSCursor.hide() balance

    /// Transition to a new cursor state. Handles all push/pop/hide/unhide.
    func transition(to newState: CursorState) {
        guard newState != state else { return }
        // Unhide if currently hidden and moving to visible cursor
        // Pop previous pushed cursor if needed
        // Push new cursor or hide as appropriate
        state = newState
    }

    /// Force-reset to clean state (call on exit).
    func reset() {
        // Unwind hideCount, pop all pushed cursors
        while hideCount > 0 { NSCursor.unhide(); hideCount -= 1 }
        state = .system
    }
}
```

**Critical detail:** `CrosshairView` still owns `resetCursorRects()` because that is an NSView override tied to the view's window. CursorManager does NOT handle cursor rects -- it only handles the imperative push/pop/hide/unhide stack. CrosshairView calls `window?.invalidateCursorRects(for: self)` as before, but instead of also calling `NSCursor.hide()`, it calls `cursorManager.transition(to: .hidden)`.

**What NOT to do:**
- Do NOT make CursorManager a global singleton. It should be passed as a dependency.
- Do NOT try to replace `resetCursorRects()` -- that is an NSView lifecycle method.
- Do NOT add cursor logic to SelectionManager. Keep SelectionManager focused on selection state.

### Breaking Change Risk: NONE

CursorManager wraps existing calls without changing any public API. RulerWindow and CrosshairView gain a `cursorManager` property but their existing public interfaces (`hideForDrag`, `showAfterDrag`, etc.) remain unchanged internally.

---

## Enhancement 2: Shake Animation on SelectionOverlay

### Problem

When a user drags a selection rectangle that is too small (< 4px) or fails to snap to edges, the selection simply disappears. There is no visual feedback explaining why.

### Current Layer Hierarchy

```
CrosshairView.layer (root)
  +-- linesLayer (CAShapeLayer, difference blend)
  +-- leftFoot, rightFoot, topFoot, bottomFoot (CAShapeLayer)
  +-- wBgLayer, hBgLayer (CAShapeLayer, pill backgrounds)
  +-- wLabelLayer, hLabelLayer, wValueLayer, hValueLayer (CATextLayer)
  +-- [SelectionOverlay layers, added by SelectionManager]
       +-- fillLayer (CAShapeLayer)
       +-- rectLayer (CAShapeLayer, difference blend)
       +-- pillBgLayer (CAShapeLayer)
       +-- pillTextLayer (CATextLayer)
```

### Recommended Architecture

Add the shake animation directly to `SelectionOverlay`. It already owns its layer hierarchy and has an `animateSnap(to:w:h:)` method -- a `shakeAndRemove()` method is the natural counterpart.

**Integration point:** `SelectionManager.endDrag()` currently calls `sel.remove(animated: true)` on snap failure. Replace with `sel.shakeAndRemove()`.

```swift
// In SelectionOverlay:
func shakeAndRemove() {
    // Remove dash pattern for visual consistency during shake
    rectLayer.lineDashPattern = nil

    // Shake uses CAKeyframeAnimation on position.x of all layers
    let duration: CFTimeInterval = 0.35
    let amplitude: CGFloat = 6.0

    // Group all 4 layers into a temporary container for single animation target
    let containerLayer = CALayer()
    containerLayer.frame = CGRect(
        x: rect.origin.x, y: rect.origin.y,
        width: rect.width, height: rect.height + pillHeight + pillGap
    )

    // ... OR animate each layer's position individually (simpler, no re-parenting):
    let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
    shake.values = [0, -amplitude, amplitude, -amplitude * 0.6, amplitude * 0.6, 0]
    shake.keyTimes = [0, 0.15, 0.35, 0.55, 0.75, 1.0]
    shake.duration = duration
    shake.timingFunction = CAMediaTimingFunction(name: .easeOut)

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1.0
    fade.toValue = 0.0
    fade.beginTime = duration * 0.5  // start fading halfway through shake
    fade.duration = duration * 0.5

    let group = CAAnimationGroup()
    group.animations = [shake, fade]
    group.duration = duration

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
        self?.removeLayers()
    }
    for layer in [rectLayer, fillLayer, pillBgLayer, pillTextLayer] as [CALayer] {
        layer.opacity = 0  // final model value
        layer.add(group, forKey: "shakeRemove")
    }
    CATransaction.commit()
}
```

**Why animate each layer individually instead of a container layer:**
SelectionOverlay's layers are added directly to CrosshairView's root layer (not grouped). Re-parenting them into a container layer during animation would require removing and re-adding sublayers, which risks flicker and complicates the layer tree. Applying the same animation to each layer independently is simpler and matches the existing pattern used in `animateSnap()` and `remove(animated:)`.

**What NOT to do:**
- Do NOT add a wrapper CALayer/CATransformLayer as a permanent parent for SelectionOverlay's layers. The flat hierarchy is intentional -- it keeps z-ordering simple and avoids nested coordinate transforms.
- Do NOT animate `position` directly -- use `transform.translation.x` to avoid conflicting with the layer's actual position (same pattern Core Animation uses for UIKit spring animations).

### Breaking Change Risk: NONE

`shakeAndRemove()` is a new method on SelectionOverlay. The only call site change is in `SelectionManager.endDrag()`.

---

## Enhancement 3: Process Timeout

### Problem

Per MEMORY.md: "Ruler processes don't auto-terminate if NSApp.terminate(nil) never fires." If the user switches away from the overlay via Mission Control or a system dialog steals focus, the process hangs forever consuming resources.

### Current Exit Flow

```
RulerWindow.keyDown(ESC) --> onRequestExit callback --> Ruler.handleExit()
  --> NSCursor.unhide()
  --> close all windows
  --> NSApp.terminate(nil)
```

There is no fallback if ESC is never pressed.

### Recommended Architecture

The timeout belongs in the **Ruler singleton**, not in RulerWindow or an NSApplication delegate. Rationale:

1. Ruler owns the lifecycle (`run()` and `handleExit()`)
2. Ruler has access to all windows (can check if any are key/visible)
3. No NSApplication delegate exists, and adding one would change the architecture unnecessarily
4. A simple DispatchSource timer in Ruler is lightweight and self-contained

```swift
// In Ruler:
private var watchdogTimer: DispatchSourceTimer?

func run(hideHintBar: Bool, corrections: String) {
    // ... existing setup ...
    startWatchdog()
    app.run()
}

private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 300, repeating: 60)  // first check at 5min, then every 1min
    timer.setEventHandler { [weak self] in
        guard let self else { return }
        // If no window is key, the user has navigated away -- exit
        let anyWindowKey = self.windows.contains { $0.isKeyWindow }
        if !anyWindowKey {
            self.handleExit()
        }
    }
    timer.resume()
    watchdogTimer = timer
}

private func handleExit() {
    watchdogTimer?.cancel()
    watchdogTimer = nil
    // ... existing exit logic ...
}
```

**Why 5 minutes initial delay:** The user might intentionally Cmd+Tab away briefly (e.g., to compare). A 5-minute grace period covers this. After that, 1-minute checks catch zombie processes quickly.

**Alternative considered -- NSApplication delegate:** Adding `NSApplicationDelegate` with `applicationDidResignActive()` would exit immediately when focus is lost. This is too aggressive -- the user might switch apps briefly. The timer approach is more forgiving.

**Alternative considered -- `applicationShouldTerminateAfterLastWindowClosed`:** Requires an NSApplication delegate and only fires when ALL windows close, not when focus is lost.

### Breaking Change Risk: NONE

Purely additive. Timer is created in `run()` and cancelled in `handleExit()`.

---

## Enhancement 4: "Press ? for help" Transient Hint

### Problem

The current HintBarView is always visible (unless dismissed). A lighter alternative is a transient "Press ? for help" hint that appears briefly, then fades out -- only showing the full hint bar when the user presses `?`.

### Current HintBarView Architecture

```
HintBarView (NSView)
  +-- NSHostingView<HintBarContent> (SwiftUI)
       +-- MainHintCard (arrows + shift explanation)
       +-- ExtraHintCard (ESC + backspace explanation)
  +-- slide animation (bottom <-> top)
  +-- pressKey/releaseKey for visual feedback
  +-- configure() sets initial frame
  +-- updatePosition() handles cursor proximity
```

HintBarView is created in `RulerWindow.setupViews()` and added to the container view if not hidden. It is a peer of CrosshairView in the view hierarchy (not a child).

### Recommended Architecture

Add a **separate lightweight layer** for the transient hint, NOT modify HintBarView. Rationale:

1. HintBarView is a full SwiftUI-hosted NSView with key press animations -- it is the "full help overlay"
2. The transient hint is a simple text that fades in/out -- it does not need SwiftUI
3. Mixing a transient fade-out into HintBarView's slide animation system would add complexity to an already-nuanced animation state machine

**New component:** `TransientHintLayer` -- a pair of CALayers (background + text) managed by RulerWindow.

```
CrosshairView.layer (root)
  +-- ... existing layers ...
  +-- transientHintBg (CAShapeLayer)
  +-- transientHintText (CATextLayer)
```

**Or, simpler:** Add it to the container view as a separate thin NSView (like HintBarView is), positioned at bottom center.

**Recommended approach:** CALayer on CrosshairView's root layer. This matches the pill pattern (CAShapeLayer bg + CATextLayer text) and avoids creating another NSView.

**Lifecycle:**

```
1. Ruler.run() creates windows
2. RulerWindow.showInitialState() shows transient hint: "Press ? for help" at bottom center
3. After 3s, fade out (CABasicAnimation opacity 1->0, duration 0.5)
4. On "?" keyDown: remove transient hint, show full HintBarView (add to containerView + configure)
5. Full HintBarView from that point behaves exactly as it does today
```

**Where to add the layers:** CrosshairView gets two new optional layers (`transientHintBg`, `transientHintText`). CrosshairView gets `showTransientHint()` and `hideTransientHint(animated:)` methods. RulerWindow calls these at the appropriate times and handles the `?` key in `keyDown`.

**Integration with existing hint bar dismissal:**

| State | Transient Hint | Full HintBar |
|-------|---------------|--------------|
| hideHintBar=true | Not shown | Not shown |
| hideHintBar=false, hintBarDismissed=false | Shown on launch, fades after 3s | Shown on "?" press |
| hideHintBar=false, hintBarDismissed=true | Shown on launch, fades after 3s | Not shown (dismissed) |

The transient hint is independent of the dismiss state. Even if the user previously dismissed the full hint bar, the transient "Press ? for help" still appears (it is non-intrusive).

**What NOT to do:**
- Do NOT make HintBarView responsible for the transient state. The two are different UI elements with different lifecycles.
- Do NOT use SwiftUI for the transient hint. It is 2 layers (bg + text). SwiftUI hosting overhead is not justified.
- Do NOT show the transient hint AND the full hint bar simultaneously.

### Breaking Change Risk: LOW

New layers on CrosshairView and new key handler in RulerWindow. The only subtle change is that `hideHintBar` preference now controls both systems, but the behavior is strictly additive.

---

## Enhancement 5: Debug Logging Strategy

### Current State

6 `fputs("[DEBUG]...", stderr)` calls in production code:

| File | Count | Content |
|------|-------|---------|
| `EdgeDetector.swift` | 2 | Screen capture diagnostics, nil edge detection |
| `RulerWindow.swift` | 4 | Drag state transitions |

### Recommended Architecture: `#if DEBUG` Guards

**Use `#if DEBUG` because:**

1. **Zero runtime cost in release builds.** The compiler strips guarded code entirely. `os_log` with `.debug` level still evaluates string interpolation arguments even when the log is not displayed.
2. **No import needed.** `os_log` requires `import os`, adding a framework dependency to files that currently only import AppKit.
3. **Matches Raycast extension constraints.** The Swift binary runs as a standalone process -- there is no persistent subsystem to log to. `os_log` is designed for long-running processes where Console.app filtering is valuable. For a tool that runs for seconds, stderr during development is more practical.
4. **Complete removal is the wrong choice.** These debug logs document important state transitions (drag lifecycle, capture diagnostics). Removing them means re-adding them every time debugging is needed.

**Implementation:**

```swift
// Replace all fputs calls with:
#if DEBUG
fputs("[DEBUG] mouseDown: starting drag at \(windowPoint)\n", stderr)
#endif
```

**What NOT to do:**
- Do NOT use `os_log`. The overhead of `import os` + subsystem/category setup + OSLogMessage formatting is not justified for 6 log statements in a short-lived process.
- Do NOT create a logging wrapper/protocol. 6 call sites do not warrant abstraction.
- Do NOT remove the logs entirely. They document non-obvious state transitions that will need debugging again.

**Alternative considered -- `os_log`:** Would be appropriate if the extension had persistent background processes, many logging call sites, or needed Console.app filtering. None of these apply.

### Breaking Change Risk: NONE

Purely a code change within method bodies. No API changes.

---

## Component Boundaries Summary

```
Ruler (singleton)
  |-- owns: CursorManager (NEW), windows[], watchdogTimer (NEW)
  |-- creates: RulerWindow per screen
  |-- provides: CursorManager to each RulerWindow
  |
  RulerWindow
    |-- owns: CrosshairView, HintBarView, SelectionManager, EdgeDetector
    |-- receives: CursorManager from Ruler
    |-- routes: all events (sendEvent, mouseMoved, keyDown)
    |-- handles: "?" key for transient->full hint transition (NEW)
    |
    CrosshairView
      |-- owns: crosshair layers, pill layers, transient hint layers (NEW)
      |-- receives: CursorManager from RulerWindow
      |-- provides: showTransientHint() / hideTransientHint() (NEW)
      |
    HintBarView (unchanged)
      |
    SelectionManager
      |-- owns: SelectionOverlay[]
      |-- calls: SelectionOverlay.shakeAndRemove() on failed snap (NEW)
      |
    SelectionOverlay
      |-- provides: shakeAndRemove() (NEW)
```

## Data Flow for New Interactions

### Shake on Failed Selection

```
User drags < 4px or snap fails
  --> SelectionManager.endDrag()
    --> SelectionOverlay.shakeAndRemove()
      --> CAKeyframeAnimation on all 4 layers
      --> CATransaction completionBlock removes layers
    --> SelectionManager removes from selections[]
```

### Cursor State Transitions

```
Launch: .system (resetCursorRects shows crosshair)
First mouse move: .hidden (CursorManager.transition)
Hover selection: .pointingHand (CursorManager.transition)
Leave selection: .hidden (CursorManager.transition)
Start drag: .crosshair (CursorManager.transition)
End drag: .hidden (CursorManager.transition)
Deactivate window: .hidden (CursorManager.transition)
Exit: CursorManager.reset() (unwinds everything)
```

### Transient Hint Flow

```
Launch: showTransientHint() on cursor screen's CrosshairView
3s timer: hideTransientHint(animated: true) -- fades out
User presses "?": hideTransientHint(animated: false) + add HintBarView to container
ESC: handleExit() (no special cleanup needed -- layers removed with window)
```

---

## Build Order (Dependencies Between Enhancements)

```
1. #if DEBUG guards        -- Zero dependencies, trivial, do first
2. Process timeout         -- Zero dependencies on other enhancements
3. CursorManager           -- Zero dependencies but touches many files
4. Shake animation         -- Independent of CursorManager
5. Transient hint          -- Should be done after CursorManager (new key handler
                              in RulerWindow benefits from cleaner cursor state)
```

**Rationale:**
- Items 1-2 are isolated changes that reduce noise and risk
- Item 3 (CursorManager) is the most invasive refactor -- doing it before items 4-5 means those enhancements write against the cleaner cursor API from the start
- Item 4 (shake) is self-contained within SelectionOverlay/SelectionManager
- Item 5 (transient hint) touches RulerWindow's keyDown handler and CrosshairView, which are the same files CursorManager modifies -- so doing it after CursorManager avoids merge conflicts

**Items 1 and 2 can be done in parallel.** Items 3, 4, 5 should be sequential.

---

## Scalability Considerations

| Concern | Current (1-3 monitors) | At 6+ monitors | Notes |
|---------|----------------------|----------------|-------|
| Window count | 1 RulerWindow per screen | Same | No issue -- each window is independent |
| CursorManager | Shared across windows | Same | Single instance, transitions are serialized on main thread |
| Watchdog timer | 1 timer in Ruler | Same | Checks all windows in array |
| Memory | ~50MB per screen capture | ~100MB+ | Already the main constraint, not affected by enhancements |

## Sources

- All findings derived from direct codebase analysis of the existing source files
- NSCursor documentation: Apple Developer Documentation (push/pop/hide/unhide stack semantics)
- CAKeyframeAnimation: Apple Developer Documentation (keyPath, values, keyTimes)
- `#if DEBUG` vs `os_log`: Swift compiler documentation (conditional compilation blocks are stripped at compile time; os_log evaluates arguments at runtime even when level is filtered)

**Confidence: HIGH** -- all recommendations are based on reading the actual source code and understanding the existing patterns. No external libraries or APIs are being introduced.
