# Feature Landscape: Design Ruler Enhancement Milestone

**Domain:** macOS pixel inspector (Raycast extension) -- UX polish and robustness enhancements
**Researched:** 2026-02-13

---

## 1. Shake-to-Reject Animation

### What It Is

When a user drags a selection rectangle too small to snap (currently `< 4px` in either dimension), the selection should visually "reject" with a shake animation before disappearing -- the same idiom macOS uses for incorrect login passwords.

### Reference Implementations

**macOS Login Window** (the canonical reference):
- 3 horizontal oscillations
- Total duration: 0.3s
- Amplitude: 4% of the element's width (the "vigour" factor)
- Decaying envelope -- each oscillation is smaller than the previous

**Cocoa Is My Girlfriend implementation** ([source](https://www.cimgf.com/2008/02/27/core-animation-tutorial-window-shake-effect/)):
- `numberOfShakes = 3`, `durationOfShake = 0.3`, `vigourOfShake = 0.04`
- Uses `CAKeyframeAnimation` with a `CGMutablePath` that traces a horizontal zigzag

**Community-standard NSView extension** ([source](https://github.com/onmyway133/blog/issues/233)):
- `CAKeyframeAnimation` on `transform.translation.x`
- Damped values array: `[-5, 5, -5, 5, -3, 3, -2, 2, 0]`
- Duration: 0.4s with linear timing (the decay is baked into the values)

### Recommended Parameters for Design Ruler

Since the selection overlay is a `CAShapeLayer` (not an NSView or NSWindow), animate the layer's `position.x` directly.

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Animation type | `CAKeyframeAnimation` on `position.x` | Keyframes give precise control over damping envelope |
| `isAdditive` | `true` | Avoids needing to know absolute position; offsets from current |
| Values | `[0, -8, 8, -6, 6, -3, 3, -1, 1, 0]` | Damped oscillation; 8px initial amplitude appropriate for a ~100-200px selection rect |
| Duration | 0.35s | Slightly longer than macOS login (0.3s) because we animate then fade out |
| Timing | `linear` (decay baked into values) | Standard pattern -- the values array IS the easing |
| On completion | Fade out (0.15s easeOut) then remove layers | Chain: shake finishes, then `remove(animated: true)` |

**Confidence:** HIGH -- these parameters are well-documented across multiple independent sources and match the macOS system idiom.

### What Feels Wrong (Anti-Patterns)

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Single-frequency sine wave (no damping) | Feels mechanical, like an error buzzer not a gentle rejection |
| Vertical shake | macOS idiom is strictly horizontal; vertical feels like a rendering bug |
| Duration > 0.5s | Feels sluggish; the user wants to retry immediately |
| Duration < 0.2s | Too fast to register as intentional feedback |
| Amplitude > 15px | Feels aggressive/alarming for a non-critical rejection |
| Shaking then snapping back to original position and staying | Confusing -- the selection should disappear after rejection |

### Implementation Notes

Apply shake to ALL layers of the `SelectionOverlay` simultaneously: `rectLayer`, `fillLayer`, `pillBgLayer`, `pillTextLayer`. Group them using a shared parent `CALayer` if possible, or animate each independently with the same `CAKeyframeAnimation` instance (Core Animation copies the animation object on `add()`).

The existing `remove(animated:)` method already does a 0.15s opacity fade. Chain the shake as a predecessor: shake (0.35s) then trigger the existing fade-out in the completion block.

---

## 2. "Press ? for Help" Transient Hint Pattern

### What It Is

A brief, non-intrusive text hint that appears when the tool launches (or when the user seems stuck) and auto-dismisses after a few seconds. Different from the current persistent `HintBarView` -- this is a one-shot contextual nudge.

### Reference Implementations

**macOS Screenshot Tool (Cmd+Shift+5):**
- Shows a toolbar with controls immediately
- No transient "press ? for help" hint -- the controls ARE the help
- Cancel via ESC is discovered through convention

**CheatSheet app** ([source](https://www.cultofmac.com/news/cheatsheet-shows-mac-keyboard-shortcuts-at-the-press-of-a-button)):
- Hold Command key to see all shortcuts as an overlay
- Dismissed on release -- strictly hold-to-view, not toggle

**Keynote Presenter Display:**
- Shows transient "Press ? for keyboard shortcuts" text
- Fades in on activation, auto-fades after ~5s
- Can be recalled with `?` key

**Apple Human Interface Guidelines on Feedback** ([source](https://developer.apple.com/design/human-interface-guidelines/feedback)):
- "Provide clear and consistent feedback"
- Feedback should be proportional to the action
- Non-blocking -- never interrupt the primary workflow

### Recommended Pattern for Design Ruler

The current `HintBarView` already serves as persistent help. Rather than adding a second hint system, enhance the existing one with a transient auto-dismiss behavior for first-time users.

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Initial opacity | 0 | Fades in, not instant |
| Fade-in duration | 0.5s easeOut | Gentle appearance, not jarring |
| Visible duration | 5s | Long enough to read, short enough to not annoy |
| Fade-out duration | 0.3s easeOut | Smooth disappearance |
| Trigger | First launch only (no `hintBarDismissed` flag) | Experienced users should never see this |
| Content | Current hint bar content | No new text needed |
| Re-trigger | `?` key brings it back temporarily (5s again) | Discoverable recall mechanism |
| Persistence | `UserDefaults` flag after first auto-dismiss | Only auto-shows once per user lifetime |

**Confidence:** MEDIUM -- the pattern is well-established in pro apps but specific timing values are informed by convention rather than Apple documentation.

### What Feels Wrong

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Modal overlay that blocks interaction | This is an inspector tool -- blocking defeats the purpose |
| Text that stays forever until dismissed | Current behavior (backspace to dismiss) is actually reasonable for first release |
| Tooltip-style popup near cursor | Competes with the W x H pill for visual attention |
| Sound effect on appearance | macOS inspector tools are silent |

### Implementation Notes

The existing `HintBarView` is already layer-cached and rendered once. Adding auto-dismiss is straightforward:
1. After `configure()`, schedule `DispatchWorkItem` for 5s delay
2. On fire: animate `alphaValue` to 0 over 0.3s, then `removeFromSuperview()`
3. Cancel the work item if user presses backspace first (existing behavior)
4. If `?` key pressed after auto-dismiss: re-add the view, re-run the same sequence

---

## 3. Cursor State Management in Overlay Apps

### What It Is

Managing the system cursor lifecycle when the app owns the entire screen: when to show/hide, which cursor to display, how to handle cursor stealing by the system, and clean restoration on exit.

### Reference Implementations

**macOS Screenshot Tool (Cmd+Shift+4):**
- Immediately replaces arrow cursor with crosshair on activation
- Crosshair maintained throughout selection
- On ESC: cursor restored to arrow, overlay dismissed
- No intermediate states -- one cursor per mode

**Sam Soffes "Aggressively Hiding the Cursor"** ([source](https://soff.es/blog/aggressively-hiding-the-cursor)):
- Problem: `NSCursor.hide()` gets overridden when user moves mouse vigorously
- Solution: Call `NSCursor.hide()` inside `mouseMoved` event handler
- Quote: "Using NSCursor hide and unhide isn't super reliable unless you control everything"
- Having a fullscreen window was considered sufficient control

**Apple Documentation on NSCursor** ([source](https://developer.apple.com/documentation/appkit/nscursor)):
- `hide()` and `unhide()` are balanced -- each `hide()` must be matched by an `unhide()`
- Multiple unbalanced `hide()` calls require matching `unhide()` calls
- `push()` and `pop()` manage a cursor stack (used in Design Ruler for drag mode)

**Xcode Color Picker / Digital Color Meter:**
- Uses system loupe cursor (private API, not applicable)
- Always restores cursor on deactivation or ESC

### Current State in Design Ruler (from code review)

The existing cursor management is already sophisticated:

```
Launch:     resetCursorRects → system crosshair via addCursorRect
First move: hideSystemCrosshair() → invalidateCursorRects + NSCursor.hide()
Drag start: NSCursor.crosshair.push() + NSCursor.unhide()
Drag end:   NSCursor.pop() + NSCursor.hide()
Hover sel:  NSCursor.pointingHand.push() + NSCursor.unhide()
Leave sel:  NSCursor.pop() + NSCursor.hide()
Exit:       NSCursor.unhide() (only if firstMoveReceived)
```

### Identified Issues and Recommendations

| Issue | Severity | Recommendation |
|-------|----------|----------------|
| Unbalanced hide/unhide if exit during drag | Medium | Always unhide on exit regardless of state: track `hideCount` explicitly |
| Stale drag state (already partially handled) | Low | The `mouseDown` reset of stale `isDragging` is good; add same for hover |
| No cursor restoration if process crashes | High | Safety timeout (see section 4) should include cursor restoration |
| System can steal cursor during vigorous mouse movement | Low | Existing fullscreen window provides sufficient control (Soffes confirms) |

### Recommended Enhancement: Cursor Balance Tracking

```swift
private var cursorHideBalance: Int = 0

func safeCursorHide() {
    NSCursor.hide()
    cursorHideBalance += 1
}

func safeCursorUnhide() {
    guard cursorHideBalance > 0 else { return }
    NSCursor.unhide()
    cursorHideBalance -= 1
}

func restoreAllCursors() {
    while cursorHideBalance > 0 {
        NSCursor.unhide()
        cursorHideBalance -= 1
    }
}
```

Call `restoreAllCursors()` in the exit path, AND in a `deinit` safety net.

**Confidence:** HIGH -- `NSCursor.hide()`/`unhide()` balance semantics are officially documented by Apple and the fullscreen window control pattern is confirmed by multiple independent developers.

### What Feels Wrong

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| Hiding cursor immediately on launch (before first move) | User loses spatial context -- "where am I?" |
| Showing custom CALayer cursor AND system cursor simultaneously | Visual doubling, janky |
| Not restoring cursor on crash/force-quit | User must wiggle mouse or click to get cursor back -- frustrating |

---

## 4. Process Safety Timeouts

### What It Is

Ensuring the Ruler process terminates gracefully even if something goes wrong -- preventing zombie processes that leave the screen locked behind an overlay with no cursor.

### Reference Implementations

**Apple Watchdog Documentation** ([source](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations)):
- iOS watchdog kills apps that block the main thread for too long
- macOS has no equivalent system watchdog for third-party apps
- Developers must implement their own safety mechanisms

**Raycast Extension Context:**
- Raycast spawns the Swift binary as a child process
- If the binary hangs, Raycast can kill it, but the overlay may persist in weird states
- The MEMORY.md notes: "Ruler processes don't auto-terminate if `NSApp.terminate(nil)` never fires"
- The existing fix is manual: `pkill -9 -f "Ruler inspect"`

### Recommended Safety Mechanisms

#### A. Global Activity Timeout

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Timeout duration | 300s (5 minutes) | Long enough for any real inspection session; short enough to prevent indefinite zombies |
| Check mechanism | `DispatchWorkItem` rescheduled on every user interaction | Only fires if user goes completely idle |
| On fire | `NSApp.terminate(nil)` with cursor restoration | Clean exit |

```swift
private var safetyTimeout: DispatchWorkItem?

func resetSafetyTimeout() {
    safetyTimeout?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.handleExit()
    }
    safetyTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
}
```

Call `resetSafetyTimeout()` in `mouseMoved`, `keyDown`, `mouseDown`.

#### B. Startup Safety Timeout

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Timeout | 10s from launch | If no mouse move or key press within 10s, something went wrong |
| On fire | Clean exit with cursor restoration | Prevents invisible overlay trapping the screen |

#### C. Signal Handler for SIGTERM

```swift
signal(SIGTERM) { _ in
    DispatchQueue.main.async {
        NSCursor.unhide()
        NSApp.terminate(nil)
    }
}
```

This ensures Raycast's process management can cleanly shut down the overlay.

**Confidence:** MEDIUM -- the pattern is sound but specific timeout values are judgment calls. The 5-minute timeout may need tuning based on real usage patterns (designers might leave the overlay open while referencing other materials).

### What Feels Wrong

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| No timeout at all | Zombie processes are the #1 user-facing bug in overlay tools |
| Timeout < 60s | Designers often pause to think; premature exit is worse than no timeout |
| Hard kill without cleanup | Cursor stuck hidden, overlay layers orphaned |
| Timeout popup ("Are you still there?") | This is an inspector, not a banking app |

---

## 5. Debug Logging Best Practices

### What It Is

Replacing the current `fputs("[DEBUG]...", stderr)` pattern with structured, conditional logging that is useful during development and silent in production.

### Current State in Design Ruler

The codebase uses raw `fputs` to stderr:
```swift
fputs("[DEBUG] mouseDown: isDragging was still true, resetting stale state\n", stderr)
fputs("[DEBUG] screen.frame(AppKit)=\(frame) cgRect=\(cgRect)...\n", stderr)
```

This is always-on, has no categorization, and produces noise in production.

### Reference Implementations

**Apple's Logger (OSLog) framework** ([source](https://developer.apple.com/videos/play/wwdc2020/10168/)):
- Subsystem + category for filtering
- Log levels: `.debug`, `.info`, `.notice`, `.error`, `.fault`
- `.debug` messages are NOT persisted in release builds and cost near-zero when not observed
- String interpolation is lazy -- never evaluated if the log level is disabled
- Privacy annotations: `\(value, privacy: .private)`

**SwiftLee's recommended pattern** ([source](https://www.avanderlee.com/debugging/oslog-unified-logging/)):
```swift
import OSLog
extension Logger {
    private static var subsystem = "com.raycast.design-ruler"
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let edges   = Logger(subsystem: subsystem, category: "edges")
    static let window  = Logger(subsystem: subsystem, category: "window")
    static let cursor  = Logger(subsystem: subsystem, category: "cursor")
}
```

**Conditional Compilation** ([source](https://medium.com/@ipak.tulane/conditional-compilation-in-swift-with-if-debug-056a460ca686)):
```swift
#if DEBUG
Logger.capture.debug("screen.frame=\(frame)")
#endif
```

### Recommended Approach for Design Ruler

Use `os.Logger` (available macOS 11+, project targets macOS 12+) with categories matching the source file structure. Do NOT use `#if DEBUG` wrapping -- `Logger.debug()` is already compiled out in release builds at the system level.

| Category | Maps To | Example Messages |
|----------|---------|------------------|
| `capture` | `EdgeDetector.capture()` | Screen frame, image dimensions, scale factor |
| `edges` | `ColorMap.scan()`, `EdgeDetector` | Edge distances, skip counts, tolerance hits |
| `window` | `RulerWindow`, `Ruler` | Activation, deactivation, exit, multi-monitor |
| `cursor` | Cursor state transitions | Hide/unhide/push/pop with balance count |
| `selection` | `SelectionManager`, `SelectionOverlay` | Drag start/end, snap results, removal |
| `performance` | Timing-sensitive paths | Frame time, throttle skips |

#### Log Level Guide

| Level | When | Example |
|-------|------|---------|
| `.debug` | Verbose development info (compiled out in release) | Edge scan results on every mouse move |
| `.info` | Notable but expected events | Screen captured, window created |
| `.notice` | Default persistence -- important state changes | Extension launched, exit requested |
| `.error` | Something failed but we recovered | Capture returned nil, fallback used |
| `.fault` | Should never happen -- investigate | Unbalanced cursor hide/unhide detected |

**Confidence:** HIGH -- `os.Logger` is Apple's official recommendation, the API is stable since macOS 11, and `.debug` level messages are documented to be zero-cost in release builds.

### Migration Path

1. Add `import OSLog` to all source files
2. Add `Logger` extension with categories
3. Replace each `fputs("[DEBUG]..."` with appropriate `Logger.category.level(...)` call
4. Remove all `fputs` calls
5. Verify with `Console.app` filtering on `com.raycast.design-ruler` subsystem

### What Feels Wrong

| Anti-Pattern | Why It Fails |
|--------------|-------------|
| `print()` / `fputs()` in production | Always-on output, no filtering, potential performance cost in hot paths |
| `#if DEBUG` around every log call | Verbose, easy to forget, and `Logger.debug` already handles this |
| Custom logging framework | Unnecessary when `os.Logger` exists and integrates with Console.app |
| Logging pixel coordinates on every mouse move in `.info` | Creates massive log volume; use `.debug` which is discarded when not observed |
| Using `NSLog` | Slower than OSLog, always persists, legacy API |

---

## Table Stakes

Features users of a polished macOS inspector tool expect. Missing = product feels unfinished.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Shake-to-reject for invalid selections | macOS convention for "no" feedback; current silent disappearance feels broken | Low | Single `CAKeyframeAnimation`, ~20 lines |
| Cursor restoration on all exit paths | Losing cursor is the worst UX bug in overlay tools | Low | Balance tracking + cleanup in exit handler |
| Process self-termination on inactivity | Zombie processes are a known issue (MEMORY.md) | Low | `DispatchWorkItem` with reschedule |
| Structured logging (replace fputs) | Debug output in production is unprofessional; unstructured logs waste time | Medium | Mechanical refactor, ~30 call sites |

## Differentiators

Features that set the product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| "?" key to toggle help overlay | Discoverable help without permanent screen real estate | Low | Reuse existing `HintBarView` with toggle logic |
| Startup safety timeout (10s) | Prevents completely stuck states from bad captures | Low | Single `DispatchWorkItem` |
| SIGTERM handler for clean Raycast shutdown | Seamless integration with Raycast's process management | Low | 5 lines of signal handling code |
| Per-category logging with Console.app integration | Professional debugging experience, faster issue resolution | Medium | Architecture improvement, not user-facing |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Haptic feedback on rejection | MacBooks support haptics but it would require Force Touch APIs and feels unexpected in an inspector tool | Visual shake is sufficient |
| Audio feedback (error beep) on invalid selection | macOS inspector tools are silent; sound breaks focus | Visual shake only |
| "Are you still there?" timeout dialog | Interrupts workflow; inspector should just quietly exit | Silent exit after 5 min inactivity |
| Custom cursor images (PNG/SVG) | Performance cost (see CLAUDE.md warnings about SVG), fragile across Retina/non-Retina | System cursors + CAShapeLayer crosshair |
| Verbose logging to file | Disk I/O in mouse-move hot path would tank performance | OSLog handles persistence automatically |
| Shake animation on arrow key when no more edges to skip | Would fire too often and become annoying; silence is fine for "already at boundary" | No feedback needed -- lines already show at screen boundary |

## Feature Dependencies

```
Cursor Balance Tracking  --> Process Safety Timeout (timeout needs clean cursor restoration)
Structured Logging       --> All features (debug during development of other features)
Shake Animation          --> (independent, no dependencies)
Help Toggle ("?")        --> (independent, builds on existing HintBarView)
SIGTERM Handler          --> Cursor Balance Tracking (needs restoreAllCursors)
```

## MVP Recommendation

Prioritize in this order:

1. **Structured logging migration** -- Enables better debugging for all subsequent work. Replace `fputs` with `os.Logger`. Do this first.
2. **Cursor balance tracking** -- Prevents the most user-hostile bug (stuck hidden cursor). Small change, high impact.
3. **Process safety timeout** -- Prevents zombie processes (known issue from MEMORY.md). Depends on cursor tracking.
4. **SIGTERM handler** -- Trivial to add alongside safety timeout. Completes the "robustness" story.
5. **Shake-to-reject animation** -- Pure polish, independent of other work. Small, satisfying enhancement.
6. **"?" help toggle** -- Nice to have, lowest priority. Current hint bar already works.

**Defer:** Transient auto-dismiss hint bar. The current persistent-until-backspace pattern is already reasonable. Adding auto-dismiss creates new edge cases (what if user hasn't read it yet?) for minimal benefit. Revisit if user feedback requests it.

## Sources

- [Cocoa Is My Girlfriend: Window Shake Effect](https://www.cimgf.com/2008/02/27/core-animation-tutorial-window-shake-effect/) -- canonical macOS shake parameters
- [onmyway133/blog: Shake NSView](https://github.com/onmyway133/blog/issues/233) -- damped values array pattern
- [Sam Soffes: Aggressively Hiding the Cursor](https://soff.es/blog/aggressively-hiding-the-cursor) -- NSCursor reliability in fullscreen
- [Apple: NSCursor.hide() documentation](https://developer.apple.com/documentation/appkit/nscursor/hide()) -- balance semantics
- [Apple: NSCursor documentation](https://developer.apple.com/documentation/appkit/nscursor) -- push/pop cursor stack
- [Apple: Addressing Watchdog Terminations](https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations) -- process safety patterns
- [Apple: WWDC 2020 - Explore Logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/) -- os.Logger best practices
- [SwiftLee: OSLog and Unified Logging](https://www.avanderlee.com/debugging/oslog-unified-logging/) -- Logger extension pattern
- [Donny Wals: Modern Logging with OSLog](https://www.donnywals.com/modern-logging-with-the-oslog-framework-in-swift/) -- subsystem/category structure
- [Apple: Human Interface Guidelines - Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) -- animation feedback principles
- [Hacking with Swift: CAKeyframeAnimation](https://www.hackingwithswift.com/example-code/calayer/how-to-create-keyframe-animations-using-cakeyframeanimation) -- keyframe animation API
- [Swift by Sundell: Using DispatchWorkItem](https://www.swiftbysundell.com/tips/using-dispatchworkitem/) -- cancellable delayed work pattern
