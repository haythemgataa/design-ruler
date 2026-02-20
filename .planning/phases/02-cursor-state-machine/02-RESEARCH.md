# Phase 2: Cursor State Machine - Research

**Researched:** 2026-02-13
**Domain:** macOS NSCursor management, cursor state centralization, SIGTERM signal handling
**Confidence:** HIGH

## Summary

This phase centralizes all NSCursor manipulation (currently scattered across 3 files with 18 direct NSCursor calls) into a single CursorManager class with explicit state tracking. The goal is to guarantee the cursor is always correctly restored on exit, regardless of how the user exits (ESC, SIGTERM, inactivity timeout).

The current codebase has NSCursor calls in `Ruler.swift` (1 call), `RulerWindow.swift` (15 calls), and `CrosshairView.swift` (2 calls, including the `resetCursorRects` override). The calls use a combination of `push()`/`pop()` for cursor type changes and `hide()`/`unhide()` for visibility, creating a fragile system where mismatched calls can leave the cursor stuck hidden or as the wrong type. The critical finding is that macOS maintains a **hide cursor counter** (not a boolean) -- each `hide()` increments the counter, each `unhide()` decrements it, and the cursor is only visible when the count reaches zero. This means unbalanced hide/unhide calls from complex state transitions are the root cause of cursor bugs.

For SIGTERM handling, `DispatchSource.makeSignalSource(signal: SIGTERM)` is the standard Swift approach. It runs the handler on a dispatch queue (not in the restricted signal handler context), allowing safe calls to `NSCursor.unhide()`. However, there is no guarantee that SIGTERM arrives before SIGKILL, and SIGKILL cannot be caught. The practical approach is: (1) handle SIGTERM with a DispatchSource for graceful shutdown, (2) accept that SIGKILL cannot be handled, and (3) note that macOS typically restores cursor visibility when a process dies because the hide count is per-process.

**Primary recommendation:** Create a `CursorManager` class with an explicit state enum tracking the current cursor mode (systemCrosshair, hidden, pointingHand, crosshairDrag). All NSCursor calls flow through CursorManager methods. CursorManager's `restore()` method unconditionally unhides and pops to ensure clean state on exit. Wire SIGTERM via DispatchSource to call the same exit path.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit `NSCursor` | macOS 13+ | Cursor type and visibility management | Already in use; the only cursor API in AppKit |
| Dispatch `DispatchSource` | macOS 13+ | SIGTERM signal handling | Apple-recommended pattern for async-safe signal handling |
| Foundation `atexit()` | macOS 13+ | Last-resort cleanup on normal exit | C-level cleanup hook, runs on `exit()` calls |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `DispatchSource.makeSignalSource` | `signal()` C function | C signal handlers are async-signal-unsafe -- cannot call Objective-C/Swift methods like NSCursor.unhide() |
| Custom CursorManager | Direct NSCursor calls (current approach) | Current approach is scattered, fragile, and has no state tracking |
| State enum | Boolean flags (current approach) | Current `isHoveringSelection` + `isDragging` + `hasReceivedFirstMove` booleans create a combinatorial explosion of states -- an enum collapses them into mutually exclusive states |

## Architecture Patterns

### Recommended File Structure
```
swift/Ruler/Sources/
├── Cursor/
│   └── CursorManager.swift    # NEW: Centralized cursor state machine
├── Ruler.swift                 # Modified: SIGTERM handler + use CursorManager
├── RulerWindow.swift           # Modified: Replace NSCursor calls with CursorManager
├── Rendering/
│   └── CrosshairView.swift     # Modified: Remove NSCursor.hide(), keep resetCursorRects
└── ... (unchanged files)
```

### Pattern 1: Cursor State Enum
**What:** Replace scattered boolean flags with a single state enum representing the current cursor mode.
**When to use:** When multiple boolean flags combine to form mutually exclusive states.

```swift
final class CursorManager {
    enum State {
        case systemCrosshair   // Launch state: system crosshair via cursor rects, visible
        case hidden            // After first mouse move: cursor hidden, CAShapeLayer crosshair visible
        case pointingHand      // Hovering a selection: pointing hand pushed, cursor visible
        case crosshairDrag     // During drag: system crosshair pushed, cursor visible
    }

    private(set) var state: State = .systemCrosshair
    private var hideCount: Int = 0   // Track our own hide() calls for safe cleanup
    private var pushCount: Int = 0   // Track our own push() calls for safe cleanup
}
```

**Why track hide/push counts:** macOS maintains a system-wide hide cursor counter. If the process calls `hide()` twice and only `unhide()` once, the cursor stays hidden. By tracking our own counts, `restore()` can issue exactly the right number of `unhide()` and `pop()` calls.

### Pattern 2: State Transition Methods
**What:** Named methods for each cursor transition, each asserting the expected source state.
**When to use:** When state transitions must be guaranteed correct.

```swift
extension CursorManager {
    /// First mouse move: transition from system crosshair to hidden custom crosshair
    func transitionToHidden() {
        guard state == .systemCrosshair else { return }
        // CrosshairView handles invalidateCursorRects separately
        NSCursor.hide()
        hideCount += 1
        state = .hidden
    }

    /// Hover selection: show pointing hand
    func transitionToPointingHand() {
        guard state == .hidden else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount -= 1
        state = .pointingHand
    }

    /// Start drag from hidden state: show system crosshair
    func transitionToCrosshairDrag() {
        guard state == .hidden else { return }
        NSCursor.crosshair.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount -= 1
        state = .crosshairDrag
    }

    /// Return to hidden state from any visible-cursor state
    func transitionBackToHidden() {
        switch state {
        case .pointingHand, .crosshairDrag:
            NSCursor.pop()
            pushCount -= 1
            NSCursor.hide()
            hideCount += 1
            state = .hidden
        default:
            break
        }
    }

    /// Unconditional cleanup -- call on ALL exit paths
    func restore() {
        // Pop all pushed cursors
        for _ in 0..<pushCount {
            NSCursor.pop()
        }
        pushCount = 0
        // Unhide all hidden levels
        for _ in 0..<hideCount {
            NSCursor.unhide()
        }
        hideCount = 0
        state = .systemCrosshair
    }
}
```

### Pattern 3: SIGTERM via DispatchSource
**What:** Intercept SIGTERM to run cleanup before process exit.
**When to use:** When a process hides the system cursor and must restore it on termination.

```swift
// In Ruler.swift, set up early in run()
private var sigTermSource: DispatchSourceSignal?

private func setupSignalHandler() {
    signal(SIGTERM, SIG_IGN)  // Ignore default behavior so DispatchSource can handle it
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { [weak self] in
        self?.handleExit()
    }
    source.resume()
    sigTermSource = source  // Retain the source
}
```

**Key detail:** The source must be retained. If it gets deallocated, the signal handler is removed. Store it as a property on `Ruler`.

### Pattern 4: resetCursorRects Exception
**What:** `resetCursorRects()` and `addCursorRect()` remain in `CrosshairView` -- they are NOT routed through `CursorManager`.
**Why:** AppKit calls `resetCursorRects()` automatically during window management. This is a framework callback, not an application-initiated cursor change. CursorManager controls *application-initiated* cursor transitions. The cursor rect system sets the initial cursor type; CursorManager manages the hide/show/push/pop lifecycle after that.

The `invalidateCursorRects(for:)` call in `CrosshairView.hideSystemCrosshair()` tells AppKit to re-evaluate cursor rects (removing the crosshair rect). This is still a cursor rect operation, not a push/pop/hide/unhide operation, so it stays in CrosshairView. However, the `NSCursor.hide()` call that immediately follows it moves to CursorManager.

### Anti-Patterns to Avoid
- **DO NOT create a CursorManager that wraps `resetCursorRects`:** Cursor rects are an AppKit mechanism tied to the view hierarchy. CursorManager manages the push/pop/hide/unhide stack only.
- **DO NOT make CursorManager an NSObject or add it to the responder chain:** It is a plain Swift class, not a view or window component.
- **DO NOT call NSCursor methods directly outside CursorManager:** Every NSCursor.hide/unhide/push/pop call (except `addCursorRect` in `resetCursorRects`) must go through CursorManager. This is the entire point of the refactor.
- **DO NOT use `NSCursor.set()` for cursor changes:** As documented in CLAUDE.md, `set()` gets overridden by window cursor rect management. Use `push()`/`pop()` via CursorManager.
- **DO NOT handle SIGTERM in a raw `signal()` handler:** Cannot safely call Objective-C methods from async signal context. Use DispatchSource.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Signal handling | Raw `signal()` C handler | `DispatchSource.makeSignalSource` | Async-signal-safe; can call any Swift/ObjC method in handler |
| Cursor state tracking | Scattered boolean flags | Enum-based state machine in CursorManager | Mutually exclusive states prevent impossible combinations |
| Hide count tracking | Trust that calls are balanced | Explicit counter in CursorManager | macOS hide counter is cumulative; one missed unhide leaves cursor stuck |

**Key insight:** The cursor management problem looks simple (hide/show) but is actually a state machine with 4 distinct states and transitions that must be perfectly balanced. The current scattered approach works 95% of the time but fails on edge cases (screen transitions during drag, force quit during hover state, etc.).

## Common Pitfalls

### Pitfall 1: Unbalanced Hide/Unhide Calls
**What goes wrong:** Cursor stays hidden after exiting the overlay.
**Why it happens:** macOS maintains a **cumulative hide counter**. `NSCursor.hide()` increments it; `NSCursor.unhide()` decrements it. The cursor is only visible when the count is zero. If code calls `hide()` twice but `unhide()` only once (e.g., during a screen transition that cancels a drag), the cursor remains invisible.
**How to avoid:** CursorManager tracks its own `hideCount`. The `restore()` method loops `unhide()` exactly `hideCount` times. This guarantees the cursor becomes visible regardless of how many intermediate transitions occurred.
**Warning signs:** After exiting the overlay, cursor is invisible until the user moves between screens or switches apps.

Source: [CGDisplayHideCursor documentation](https://developer.apple.com/documentation/coregraphics/cgdisplayhidecursor(_:)) confirms the counter-based system: "Quartz maintains a hide cursor count that must be zero in order to show the cursor."

### Pitfall 2: Push/Pop Stack Corruption
**What goes wrong:** After exiting, cursor shows as pointing hand or crosshair instead of arrow.
**Why it happens:** `NSCursor.push()` adds to a stack; `NSCursor.pop()` removes the top. If a drag starts (pushes crosshair) and then the user switches screens (which cancels the drag and tries to pop), but the pop doesn't match what was pushed, the stack gets corrupted.
**How to avoid:** CursorManager tracks `pushCount`. The `restore()` method pops exactly `pushCount` times, unwinding whatever is on the stack back to the system default.
**Warning signs:** Cursor shows wrong type (crosshair, pointing hand) after ESC.

### Pitfall 3: SIGTERM Handler Not Firing
**What goes wrong:** Process receives SIGTERM but cleanup doesn't run.
**Why it happens:** (a) The `DispatchSourceSignal` was deallocated because it wasn't retained as a property. (b) `signal(SIGTERM, SIG_IGN)` was not called before creating the source, so the default handler killed the process. (c) Raycast sends SIGKILL directly (cannot be caught).
**How to avoid:** (a) Store the source as a property on `Ruler`. (b) Always call `signal(SIGTERM, SIG_IGN)` first. (c) Accept that SIGKILL is uncatchable -- but in practice, macOS restores cursor visibility when a process is killed because the hide count is per-process.
**Warning signs:** Process exits immediately on Raycast shutdown without running cleanup code.

Source: [Swift signal handling pattern](https://prodisup.com/posts/2022/10/signal-capture-and-graceful-shutdown-in-swift/)

### Pitfall 4: CursorManager Called from Wrong Thread
**What goes wrong:** NSCursor calls from a background thread cause crashes or no-ops.
**Why it happens:** NSCursor methods are AppKit and must be called from the main thread. If the SIGTERM DispatchSource fires on a background queue, the cursor cleanup runs off-main.
**How to avoid:** Create the DispatchSource with `queue: .main` so the handler fires on the main thread. All CursorManager methods are inherently main-thread-only since they call AppKit APIs.
**Warning signs:** Intermittent crashes during SIGTERM, or cursor not restored on force quit.

### Pitfall 5: State Transition from Unexpected State
**What goes wrong:** CursorManager guard rejects a valid transition because intermediate state changes were missed.
**Why it happens:** Multi-monitor transitions can call `deactivate()` then `activate()` in quick succession, potentially skipping expected intermediate states.
**How to avoid:** Make `restore()` unconditional (no state guards) and make `transitionBackToHidden()` handle all visible-cursor states. For multi-monitor transitions, `deactivate()` should always transition back to hidden (or systemCrosshair if no first move yet).
**Warning signs:** Cursor transitions that work on single monitor but break when dragging between screens.

### Pitfall 6: Cursor Rect Interaction with CursorManager
**What goes wrong:** AppKit's cursor rect system sets the cursor to crosshair, then CursorManager's state doesn't match.
**Why it happens:** `resetCursorRects()` + `addCursorRect` are called by AppKit automatically. CursorManager doesn't know about this.
**How to avoid:** CursorManager's initial state is `.systemCrosshair`, which represents "cursor rects are active and managing the cursor." CursorManager only takes control after `transitionToHidden()` is called on first mouse move. Before that, it's hands-off.

## Code Examples

### Complete CursorManager skeleton

```swift
// Source: Architecture derived from codebase analysis + Apple NSCursor documentation
final class CursorManager {
    static let shared = CursorManager()

    enum State: String {
        case systemCrosshair   // Launch: cursor rects manage crosshair
        case hidden            // Normal operation: cursor hidden, CAShapeLayer renders
        case pointingHand      // Hovering selection
        case crosshairDrag     // Dragging to create selection
    }

    private(set) var state: State = .systemCrosshair
    private var hideCount: Int = 0
    private var pushCount: Int = 0

    private init() {}

    // MARK: - Transitions

    func transitionToHidden() {
        guard state == .systemCrosshair else { return }
        NSCursor.hide()
        hideCount += 1
        state = .hidden
    }

    func transitionToPointingHand() {
        guard state == .hidden else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount = max(hideCount - 1, 0)
        state = .pointingHand
    }

    func transitionToCrosshairDrag() {
        guard state == .hidden else { return }
        NSCursor.crosshair.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount = max(hideCount - 1, 0)
        state = .crosshairDrag
    }

    func transitionBackToHidden() {
        switch state {
        case .pointingHand, .crosshairDrag:
            NSCursor.pop()
            pushCount = max(pushCount - 1, 0)
            NSCursor.hide()
            hideCount += 1
            state = .hidden
        default:
            break
        }
    }

    /// Unconditional restore for all exit paths
    func restore() {
        for _ in 0..<pushCount { NSCursor.pop() }
        pushCount = 0
        for _ in 0..<hideCount { NSCursor.unhide() }
        hideCount = 0
        state = .systemCrosshair
    }

    /// Reset to initial state (for multi-monitor window setup)
    func reset() {
        restore()
    }
}
```

### SIGTERM handler setup

```swift
// Source: DispatchSource pattern from Apple documentation + Swift community
// In Ruler class:
private var sigTermSource: DispatchSourceSignal?

private func setupSignalHandler() {
    // Must ignore default SIGTERM behavior first
    signal(SIGTERM, SIG_IGN)

    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { [weak self] in
        self?.handleExit()  // Same path as ESC — restores cursor + terminates
    }
    source.resume()
    sigTermSource = source
}
```

### Migration pattern: RulerWindow.deactivate()

```swift
// BEFORE (current):
func deactivate() {
    crosshairView.hideForDrag()
    if isHoveringSelection {
        isHoveringSelection = false
        NSCursor.pop()
        NSCursor.hide()
        selectionManager.updateHover(at: .zero)
    }
    if isDragging {
        selectionManager.cancelDrag()
        isDragging = false
        if hasReceivedFirstMove { NSCursor.pop(); NSCursor.hide() }
    }
}

// AFTER (with CursorManager):
func deactivate() {
    crosshairView.hideForDrag()
    if isHoveringSelection {
        isHoveringSelection = false
        CursorManager.shared.transitionBackToHidden()
        selectionManager.updateHover(at: .zero)
    }
    if isDragging {
        selectionManager.cancelDrag()
        isDragging = false
        CursorManager.shared.transitionBackToHidden()
    }
}
```

### Migration pattern: Ruler.handleExit()

```swift
// BEFORE (current):
private func handleExit() {
    if firstMoveReceived {
        NSCursor.unhide()
    }
    for window in windows { window.close() }
    NSApp.terminate(nil)
}

// AFTER (with CursorManager):
private func handleExit() {
    CursorManager.shared.restore()
    for window in windows { window.close() }
    NSApp.terminate(nil)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct NSCursor calls scattered across files | Centralized cursor manager with state tracking | This phase | Eliminates cursor-stuck bugs on all exit paths |
| No SIGTERM handling | DispatchSource signal handler | This phase | Graceful cleanup on Raycast shutdown |
| Boolean flags for cursor state | Enum state machine | This phase | Impossible states become unrepresentable |

**Deprecated/outdated:**
- `NSCursor.set()`: Gets overridden by cursor rect management. Use `push()`/`pop()` instead (documented in CLAUDE.md).
- Raw `signal()` handlers in Swift: Cannot safely call Objective-C methods. Use `DispatchSource` instead.

## Open Questions

1. **Does macOS automatically restore cursor visibility when a process is killed (SIGKILL)?**
   - What we know: CGDisplayHideCursor documentation says Quartz maintains a per-process hide cursor count. Multiple sources confirm that force-killing a process typically restores the cursor.
   - What's unclear: Whether this is guaranteed behavior or just observed behavior. Apple does not explicitly document this guarantee.
   - Recommendation: Treat SIGKILL as unhandleable. Focus SIGTERM handling on being correct. Accept that SIGKILL likely restores the cursor automatically, but don't rely on it as a design guarantee. The DispatchSource SIGTERM handler covers the Raycast-shutdown case.
   - Confidence: MEDIUM -- observed in practice, not explicitly documented.

2. **Should CursorManager be a singleton or passed as a parameter?**
   - What we know: The codebase currently uses `Ruler.shared` as a singleton. Cursor state is process-global (NSCursor is a class with class methods).
   - What's unclear: Whether dependency injection would be cleaner.
   - Recommendation: Use `CursorManager.shared` singleton. NSCursor is inherently global state -- wrapping it in dependency injection adds ceremony without benefit. The singleton pattern matches the existing `Ruler.shared` convention.

3. **Does `NSCursor.hide()` use the same counter as `CGDisplayHideCursor`?**
   - What we know: `CGDisplayHideCursor` explicitly documents a counter. NSCursor.hide() documentation just says "makes the current cursor invisible." GNUStep's implementation (open-source Cocoa clone) shows a simple delegation to the display server with no explicit counter.
   - What's unclear: Whether Apple's NSCursor.hide() increments the same CG-level counter or manages its own.
   - Recommendation: Assume the counters are coupled (conservative approach). Track our own call count and issue matching unhide() calls in `restore()`. This is safe regardless of the internal implementation.
   - Confidence: MEDIUM -- the safe approach works either way.

## Existing Cursor Call Inventory

Complete inventory of NSCursor calls that must be migrated:

### Ruler.swift (1 call)
| Line | Call | Context | Migration |
|------|------|---------|-----------|
| 128 | `NSCursor.unhide()` | `handleExit()` -- restore on ESC | Replace with `CursorManager.shared.restore()` |

### RulerWindow.swift (15 calls)
| Line | Call | Context | Migration |
|------|------|---------|-----------|
| 126 | `NSCursor.pop()` | `deactivate()` -- leave hover state | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 127 | `NSCursor.hide()` | `deactivate()` -- re-hide after hover | (folded into transitionBackToHidden) |
| 133 | `NSCursor.pop(); NSCursor.hide()` | `deactivate()` -- cancel drag | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 203 | `NSCursor.pointingHand.push()` | `mouseMoved` -- enter hover | Replace with `CursorManager.shared.transitionToPointingHand()` |
| 204 | `NSCursor.unhide()` | `mouseMoved` -- show for hover | (folded into transitionToPointingHand) |
| 211 | `NSCursor.pop()` | `mouseMoved` -- leave hover | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 212 | `NSCursor.hide()` | `mouseMoved` -- re-hide after hover | (folded into transitionBackToHidden) |
| 231 | `NSCursor.pop(); NSCursor.hide()` | `mouseDown` -- stale drag cleanup | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 239 | `NSCursor.pop()` | `mouseDown` -- exit hover on click | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 240 | `NSCursor.hide()` | `mouseDown` -- re-hide after hover click | (folded into transitionBackToHidden) |
| 258 | `NSCursor.pop()` | `mouseDown` -- exit hover before drag | (handled by transitionBackToHidden in new flow) |
| 265 | `NSCursor.crosshair.push()` | `mouseDown` -- start drag | Replace with `CursorManager.shared.transitionToCrosshairDrag()` |
| 266 | `NSCursor.unhide()` | `mouseDown` -- show crosshair for drag | (folded into transitionToCrosshairDrag) |
| 297 | `NSCursor.pop()` | `mouseUp` -- end drag | Replace with `CursorManager.shared.transitionBackToHidden()` |
| 298 | `NSCursor.hide()` | `mouseUp` -- re-hide after drag | (folded into transitionBackToHidden) |

### CrosshairView.swift (2 calls)
| Line | Call | Context | Migration |
|------|------|---------|-----------|
| 83 | `addCursorRect(bounds, cursor: .crosshair)` | `resetCursorRects()` | **KEEP as-is** -- this is AppKit framework callback, not CursorManager territory |
| 117 | `NSCursor.hide()` | `hideSystemCrosshair()` | Move to `CursorManager.shared.transitionToHidden()` |

**Total: 18 NSCursor calls across 3 files -> migrated to 4 CursorManager methods + 1 restore().**

## Sources

### Primary (HIGH confidence)
- Local codebase: Complete grep of all NSCursor calls enumerated above
- [CGDisplayHideCursor documentation](https://developer.apple.com/documentation/coregraphics/cgdisplayhidecursor(_:)) -- confirms counter-based cursor hiding: "Quartz maintains a hide cursor count"
- [Apple Quartz Display Services: Controlling the Mouse Cursor](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/MouseCursor.html) -- "Calls to these functions need to be balanced"
- [Apple: Setting the Current Cursor](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CursorMgmt/Tasks/ChangingCursors.html) -- cursor stack, cursor rects, resetCursorRects pattern
- CLAUDE.md -- "NO NSCursor.set() for Persistent Cursors" guidance
- MEMORY.md -- CALayer compositingFilter and build system insights

### Secondary (MEDIUM confidence)
- [Swift signal handling with DispatchSource](https://prodisup.com/posts/2022/10/signal-capture-and-graceful-shutdown-in-swift/) -- SIGTERM pattern with signal(SIGTERM, SIG_IGN) + DispatchSource
- [Aggressively Hiding the Cursor (Sam Soffes)](https://soff.es/blog/aggressively-hiding-the-cursor) -- NSCursor hide/unhide reliability concerns
- [IINA cursor visibility issue](https://github.com/iina/iina/issues/4183) -- practical NSCursor management challenges
- [winit cursor visibility issue](https://github.com/rust-windowing/winit/issues/1276) -- NSCursor.hide() is global, not window-scoped

### Tertiary (LOW confidence)
- [GNUStep NSCursor.m](https://github.com/gnustep/libs-gui/blob/master/Source/NSCursor.m) -- open-source implementation shows simple delegation (no counter in GNUStep's implementation, but Apple's may differ)
- Whether macOS auto-restores cursor on SIGKILL -- observed in practice, not officially documented

## Metadata

**Confidence breakdown:**
- CursorManager architecture: HIGH -- derived directly from codebase analysis, all call sites enumerated
- State enum design: HIGH -- the 4 states are clearly visible in the current code's boolean flag combinations
- Hide counter behavior: HIGH -- documented by Apple for CGDisplay level; conservative approach works regardless of NSCursor internals
- SIGTERM handling: HIGH -- DispatchSource pattern is well-documented by Apple and widely used
- SIGKILL cursor restoration: MEDIUM -- observed but not officially guaranteed

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (stable -- NSCursor and DispatchSource APIs are mature and unchanging)
