# Phase 1: Debug Cleanup and Process Safety - Research

**Researched:** 2026-02-13
**Domain:** Swift debug output gating, macOS process lifecycle safety
**Confidence:** HIGH

## Summary

This phase addresses two independent concerns: (1) removing debug `fputs` output from production builds and (2) adding a 10-minute inactivity watchdog to prevent zombie processes.

There are exactly 6 `fputs` statements across 2 Swift files (EdgeDetector.swift and RulerWindow.swift). The critical finding is that **Raycast always builds Swift extensions in `debug` configuration** -- the build logs confirm `Building workspace Ruler with scheme Ruler and configuration debug` and the only products directory is `debug/`. This means `#if DEBUG` is always true, so it **cannot** be used to gate debug output. The requirement RBST-01 specifies `#if DEBUG` gating, but that approach is a no-op in this build system. The simplest correct solution is to remove the `fputs` calls entirely, since they were temporary development aids, not structured logging worth preserving.

For process safety, the app uses `NSApp.run()` which starts the main run loop. A `Timer.scheduledTimer` on the main run loop will fire correctly alongside the event loop. The timer must reset on every user interaction (mouse move, key press) and call `NSApp.terminate(nil)` via the existing `handleExit()` path when it fires.

**Primary recommendation:** Remove all `fputs` calls outright (they are development-only diagnostics with no production value). Add a single `Timer` in the `Ruler` class that resets on every event and terminates after 10 minutes of inactivity.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation `Timer` | macOS 13+ | Inactivity watchdog | Built-in, runs on NSRunLoop, no dependencies, trivial to reset |
| AppKit `NSApp.terminate` | macOS 13+ | Clean process exit | Already used in existing `handleExit()` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Timer` (Foundation) | `DispatchSourceTimer` | More flexible but overkill -- Timer works fine since NSApp.run() drives the main run loop |
| Removing fputs | `#if DEBUG` gating | Does NOT work -- Raycast always builds in debug config |
| Removing fputs | Environment variable check | Adds runtime overhead on every mouse move for no benefit |
| Removing fputs | Custom `-D` compile flag in Package.swift | Would require modifying Package.swift build settings; fragile since Raycast controls the build |

## Architecture Patterns

### Debug Output Removal Pattern
**What:** Delete all `fputs(...)` calls, do not gate them
**Why:** These are development-only diagnostics. The build system makes compile-time gating impossible. Runtime gating adds overhead in the hot path (mouse move) for no benefit.

**Files and exact locations:**

1. `EdgeDetector.swift:36` -- capture dimensions logging
2. `EdgeDetector.swift:75` -- nil edges warning
3. `RulerWindow.swift:226` -- stale drag state warning
4. `RulerWindow.swift:252` -- drag start logging
5. `RulerWindow.swift:272` -- drag rejected logging
6. `RulerWindow.swift:281` -- mouseUp rejected logging

### Inactivity Timer Pattern
**What:** A single non-repeating `Timer` that fires after 10 minutes. Reset on every user interaction. On fire, call `handleExit()`.
**When to use:** Processes that run an event loop and must self-terminate.

```swift
// In Ruler class
private var inactivityTimer: Timer?
private let inactivityTimeout: TimeInterval = 600 // 10 minutes

private func resetInactivityTimer() {
    inactivityTimer?.invalidate()
    inactivityTimer = Timer.scheduledTimer(
        withTimeInterval: inactivityTimeout,
        repeats: false
    ) { [weak self] _ in
        self?.handleExit()
    }
}
```

**Key design decisions:**
- Non-repeating timer (fires once after deadline, recreated on reset)
- `weak self` in closure to avoid retain cycles
- Reset from existing event paths (no new event monitoring needed)
- Same exit path as ESC key (`handleExit()`) for consistent cleanup

### Event Reset Points
The timer must be reset whenever the user interacts. The existing callback architecture routes all events through `Ruler`:

| Event | Current Handler | Reset Location |
|-------|----------------|----------------|
| Mouse move | `RulerWindow.mouseMoved` -> calls `edgeDetector.onMouseMoved` | Add callback or reset in Ruler |
| Arrow keys | `RulerWindow.keyDown` -> calls `edgeDetector.incrementSkip` | Existing `onKeyPress` or new callback |
| Mouse drag | `RulerWindow.mouseDown/Dragged/Up` | Already routes through window |
| Screen switch | `RulerWindow.mouseEntered` -> `onActivate` | Already calls into Ruler |

**Simplest approach:** Add a single `onActivity` callback to `RulerWindow` that fires on any user event, or reset the timer directly in `Ruler` from the existing `onActivate` callback and add one new callback for general activity. Alternatively, since `Ruler` already has `activateWindow`, the timer can be reset there and a lightweight `onActivity` callback added for same-window events.

### Anti-Patterns to Avoid
- **DO NOT use `#if DEBUG`:** Always true in Raycast builds -- provides zero protection
- **DO NOT use a repeating timer:** A repeating timer that checks "time since last activity" is more complex and uses more CPU than a non-repeating timer that gets invalidated and recreated
- **DO NOT put the timer in RulerWindow:** The timer belongs in `Ruler` (the singleton coordinator) since it manages process lifecycle and there are multiple windows
- **DO NOT use `DispatchQueue.main.asyncAfter`:** Cannot be cancelled/reset; would require tracking work items

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timer scheduling | Custom GCD timer wrapper | `Timer.scheduledTimer(withTimeInterval:repeats:block:)` | Foundation Timer integrates with the run loop that `NSApp.run()` already drives |
| Process exit | Custom signal handlers / `exit()` | `NSApp.terminate(nil)` via `handleExit()` | Existing clean exit path handles cursor restoration, window cleanup |

## Common Pitfalls

### Pitfall 1: `#if DEBUG` is always true in Raycast
**What goes wrong:** Developer wraps fputs in `#if DEBUG`, tests locally, sees it works -- but Raycast builds with `configuration debug` always, so the code runs in production too.
**Why it happens:** Raycast's `ray build` / `ray develop` both use xcodebuild with `-configuration debug`. The build products directory is `debug/`. There is no release build path.
**How to avoid:** Do not use `#if DEBUG` for anything that must differ between dev and production in Raycast extensions. Remove debug code outright or use a runtime check (e.g., environment variable).
**Warning signs:** Build logs at `.raycast-swift-build/Logs/Build/LogStoreManifest.plist` show `configuration debug`.

### Pitfall 2: Timer not firing because run loop isn't running
**What goes wrong:** Timer is scheduled before `NSApp.run()` or on a background queue without a run loop.
**Why it happens:** `Timer.scheduledTimer` schedules on the current thread's run loop. If called before the run loop starts or from a background thread, the timer never fires.
**How to avoid:** Schedule the timer after `NSApp.run()` begins (e.g., from within the event handling flow), or ensure it's scheduled on the main thread. In this codebase, `Ruler.run()` calls `app.run()` at the end, so the timer should be started just before that call or from a `DispatchQueue.main.async` block.
**Warning signs:** Process never self-terminates despite 10 minutes of inactivity.

### Pitfall 3: Timer invalidation from wrong thread
**What goes wrong:** Timer is scheduled on main thread but invalidated from a callback on a different thread.
**Why it happens:** Foundation Timer must be invalidated on the same thread/run loop it was scheduled on.
**How to avoid:** All timer operations (schedule, invalidate, reset) happen on the main thread. In this app, all event callbacks are already on the main thread (AppKit event handling).

### Pitfall 4: Zombie process from failed exit
**What goes wrong:** `NSApp.terminate(nil)` is called but the process doesn't actually exit (e.g., a delegate blocks termination, or `app.run()` hasn't started yet).
**Why it happens:** If `NSApp.terminate` is called before the run loop starts, or if a window delegate returns `.terminateCancel` from `applicationShouldTerminate`, the process stays alive.
**How to avoid:** The existing `handleExit()` already works (ESC key exits cleanly). The timer just needs to call the same path. Verify that no window delegate or `applicationShouldTerminate` blocks exit.

### Pitfall 5: Cursor left hidden after timeout exit
**What goes wrong:** Timer fires, process exits, but cursor remains hidden because `NSCursor.unhide()` was never called.
**Why it happens:** The timer bypasses the normal ESC-key exit flow that includes cursor restoration.
**How to avoid:** Route timeout through the existing `handleExit()` method, which already handles `NSCursor.unhide()` conditionally based on `firstMoveReceived`.

## Code Examples

### Complete inactivity timer integration

```swift
// In Ruler class — add these properties
private var inactivityTimer: Timer?
private let inactivityTimeout: TimeInterval = 600 // 10 minutes

// Call this from run(), just before app.run()
private func startInactivityTimer() {
    resetInactivityTimer()
}

// Call this from any user activity
private func resetInactivityTimer() {
    inactivityTimer?.invalidate()
    inactivityTimer = Timer.scheduledTimer(
        withTimeInterval: inactivityTimeout,
        repeats: false
    ) { [weak self] _ in
        self?.handleExit()
    }
}
```

### Wiring the reset into existing events

```swift
// In Ruler.run(), when setting up window callbacks:
rulerWindow.onActivity = { [weak self] in
    self?.resetInactivityTimer()
}

// In RulerWindow — add callback property:
var onActivity: (() -> Void)?

// In RulerWindow.mouseMoved:
onActivity?()

// In RulerWindow.keyDown:
onActivity?()

// In RulerWindow.mouseDown:
onActivity?()
```

### Removing fputs (before/after)

```swift
// BEFORE (EdgeDetector.swift:36)
fputs("[DEBUG] screen.frame(AppKit)=\(frame) cgRect=\(cgRect) cgImage=\(cgImage.width)x\(cgImage.height) backing=\(screen.backingScaleFactor)\n", stderr)

// AFTER
// (line removed entirely)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `#if DEBUG` for build gating | Remove debug code or use env vars | N/A (Raycast limitation) | `#if DEBUG` is unusable in Raycast Swift extensions |
| `print()` for debugging | `fputs(_, stderr)` for stderr | N/A | Both produce output; neither is gated in Raycast builds |

## Open Questions

1. **Should we preserve any fputs as structured logging?**
   - What we know: All 6 statements are diagnostic/development aids. None are error conditions that a user would act on.
   - What's unclear: Whether any of these indicate error states worth logging.
   - Recommendation: Remove all 6. The nil-edges warning (EdgeDetector.swift:75) could be re-added later behind a proper logging framework if needed, but it fires frequently during normal operation (cursor near screen edge) and is not an error.

2. **Timer precision for 10-minute timeout**
   - What we know: `Timer` has ~50-100ms tolerance by default. Foundation may apply tolerance to save power.
   - What's unclear: Whether exact 10-minute precision matters.
   - Recommendation: 50-100ms tolerance on a 10-minute timer is irrelevant. Use default Timer behavior.

3. **Does `NSApp.terminate(nil)` always work after `NSApp.run()`?**
   - What we know: The existing ESC exit path uses `NSApp.terminate(nil)` and works reliably.
   - What's unclear: Edge cases (e.g., modal dialogs, sheets).
   - Recommendation: This app has no modal dialogs or sheets. The existing path is proven. No concern here.

## Sources

### Primary (HIGH confidence)
- Local build logs: `.raycast-swift-build/Logs/Build/LogStoreManifest.plist` -- confirms `configuration debug`
- Local build products: `.raycast-swift-build/Build/Products/` -- only `debug/` directory exists
- Local codebase: All 6 `fputs` calls enumerated via grep
- [Apple Timer docs](https://developer.apple.com/documentation/foundation/timer/2091889-scheduledtimer) -- Timer.scheduledTimer API
- [Apple NSApp.terminate docs](https://developer.apple.com/documentation/appkit/nsapplication/1428417-terminate) -- terminate behavior

### Secondary (MEDIUM confidence)
- [Raycast CLI docs](https://developers.raycast.com/information/developer-tools/cli) -- `ray build` creates production build, but no mention of release config for Swift
- [Raycast extensions-swift-tools](https://github.com/raycast/extensions-swift-tools) -- build toolchain reference
- [Design patterns for safe timer usage](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html) -- Timer invalidation patterns

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Debug output removal: HIGH -- confirmed via grep, all 6 locations identified, build system behavior verified from local logs
- `#if DEBUG` unusability: HIGH -- verified from actual build artifacts and logs on this machine
- Inactivity timer: HIGH -- Timer + NSApp.run() is a well-understood Foundation pattern; existing exit path is proven
- Process cleanup: HIGH -- existing `handleExit()` already handles all cleanup; timer just triggers the same path

**Research date:** 2026-02-13
**Valid until:** 2026-03-15 (stable -- no moving parts, all Foundation/AppKit APIs)
