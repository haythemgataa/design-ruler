# Domain Pitfalls

**Domain:** macOS pixel inspector enhancement (Raycast extension, Swift/AppKit/CoreAnimation)
**Researched:** 2026-02-13

---

## Critical Pitfalls

Mistakes that cause hard-to-debug regressions, stuck UI state, or crashes.

---

### Pitfall 1: NSCursor Push/Pop Stack Imbalance

**Enhancement affected:** Any code path that changes cursors (drag mode, hover mode, deactivate, exit)

**What goes wrong:** `NSCursor.push()` and `NSCursor.pop()` maintain a stack. Every `push()` MUST have exactly one matching `pop()`. If a code path pushes a cursor but skips the pop (e.g., an early return, a guard clause, a deactivate call that interrupts a drag), the cursor stack accumulates stale entries. The visible symptom is either (a) the wrong cursor showing after an operation, or (b) `pop()` restoring a cursor you pushed three states ago instead of the one you expect.

**Why it happens in THIS codebase:** RulerWindow already has 10+ NSCursor.push/pop/hide/unhide call sites across `deactivate()`, `mouseMoved()`, `mouseDown()`, `mouseUp()`, and the stale-drag-state reset. Adding new cursor states (e.g., a "shake feedback" state or additional interaction modes) multiplies the paths through this state machine. The existing code already has a defensive reset in `mouseDown` for stale drag state -- proof that event delivery can be interrupted by the system, leaving push/pop unbalanced.

**Consequences:**
- Cursor stuck as crosshair, pointing hand, or arrow after exiting the overlay
- Cursor permanently hidden after exit (user has to wiggle mouse violently to recover)
- Silent corruption: the stack seems fine during testing but breaks in edge cases (multi-monitor transition mid-drag, system alert interrupting the app)

**Prevention:**
1. Track cursor state with an enum, not implicit push/pop pairing:
   ```swift
   enum CursorState { case hidden, system, crosshair, pointingHand }
   private var cursorState: CursorState = .system

   private func setCursor(_ newState: CursorState) {
       guard newState != cursorState else { return }
       // Pop previous push if needed
       if cursorState == .crosshair || cursorState == .pointingHand {
           NSCursor.pop()
       }
       // Hide/unhide balance
       if cursorState == .hidden && newState != .hidden {
           NSCursor.unhide()
       }
       // Apply new state
       switch newState {
       case .hidden: NSCursor.hide()
       case .system: break  // unhide already handled above
       case .crosshair: NSCursor.crosshair.push(); NSCursor.unhide()
       case .pointingHand: NSCursor.pointingHand.push(); NSCursor.unhide()
       }
       cursorState = newState
   }
   ```
2. In `handleExit()`, forcefully reset: pop any pushed cursor, call `NSCursor.unhide()` to zero-out the hide counter
3. Add a debug assertion that `cursorState == .system` after exit in debug builds

**Detection:** After any interaction sequence (drag, hover selection, multi-monitor switch, ESC), check that the macOS cursor is visible and correct. Automate by logging cursor state transitions.

**Confidence:** HIGH -- the existing code already has a defensive reset for stale drag state at RulerWindow.swift line 225, confirming that event delivery interruptions happen in practice.

---

### Pitfall 2: NSCursor.hide()/unhide() Counter Mismatch

**Enhancement affected:** Exit path, any new feature that hides/shows cursor

**What goes wrong:** `NSCursor.hide()` and `NSCursor.unhide()` maintain an internal counter (not documented publicly, but confirmed by observed behavior and third-party investigation). Calling `hide()` twice requires calling `unhide()` twice. If the counts do not match at exit, the user's cursor remains invisible system-wide until they wiggle the mouse aggressively (which triggers macOS's "lost cursor" enlargement).

**Why it happens in THIS codebase:** The code calls `NSCursor.hide()` in `hideSystemCrosshair()` (CrosshairView.swift line 117). Separately, various paths in RulerWindow call `NSCursor.hide()` when exiting hover state (lines 126, 132, 210, 238, 302). The exit handler in Ruler.swift line 121 calls `NSCursor.unhide()` only once. If the hide counter is 2 at exit, one unhide is insufficient.

**Consequences:**
- User's cursor disappears after closing the overlay
- No crash, no error -- just an invisible cursor
- Especially bad because this is a Raycast extension -- the user expects to return to normal desktop usage immediately

**Prevention:**
1. Centralize hide/unhide through the cursor state enum described in Pitfall 1 -- only one code path ever calls `hide()`, so the counter is always 0 or 1
2. In the exit handler, use `CGDisplayShowCursor(CGMainDisplayID())` as a nuclear reset that ignores the AppKit counter (call it in a loop if needed, or once since CGDisplay calls bypass the NSCursor counter)
3. Never call `NSCursor.hide()` directly from multiple code paths -- route through a single function that tracks a local counter, so you can forcefully unhide by calling unhide that many times on exit

**Detection:** Test the exit path from every possible state: mid-drag, hovering selection, normal crosshair mode, initial state before first mouse move.

**Confidence:** HIGH -- based on [Apple's NSCursor documentation](https://developer.apple.com/documentation/appkit/nscursor/hide()), [Sam Soffes's investigation](https://soff.es/blog/aggressively-hiding-the-cursor), and observed behavior in the existing codebase.

---

### Pitfall 3: DispatchSourceTimer Deallocation Crash ("BUG IN CLIENT OF LIBDISPATCH")

**Enhancement affected:** Any feature using DispatchSourceTimer (e.g., auto-dismiss timer, delayed animation trigger, process watchdog)

**What goes wrong:** Deallocating a `DispatchSourceTimer` while it is suspended crashes with: `"BUG IN CLIENT OF LIBDISPATCH: Release of an inactive object"`. Similarly, calling `cancel()` on a suspended timer without first resuming it crashes. Calling `resume()` on an already-resumed timer crashes with `"Over-resume of an object"`.

**Why it happens:** DispatchSource uses a suspend/resume reference counting model inherited from libdispatch. Suspending increments a retain count; resuming decrements it. If the source is deallocated while suspended (retain count > 0), libdispatch considers this a bug and traps. This is not an edge case -- it happens any time the object holding the timer is deallocated before the timer fires (e.g., user presses ESC quickly after triggering the timer).

**Consequences:**
- Hard crash (SIGABRT) with a confusing libdispatch error message
- Crash happens during deallocation, so stack traces point to ARC release code, not your logic
- Difficult to reproduce because it depends on timing (fast ESC after starting a timer)

**Prevention:**
1. Always resume a timer immediately after creation. Never leave it in a suspended state:
   ```swift
   private var timer: DispatchSourceTimer?

   func startTimer() {
       let t = DispatchSource.makeTimerSource(queue: .main)
       t.schedule(deadline: .now() + 2.0)
       t.setEventHandler { [weak self] in self?.timerFired() }
       t.resume()  // MUST resume immediately
       timer = t
   }

   func cleanup() {
       timer?.cancel()  // safe because timer was resumed
       timer = nil
   }
   ```
2. If implementing pause/resume, track state with a boolean:
   ```swift
   private var timerIsSuspended = false
   func cancelTimer() {
       if timerIsSuspended { timer?.resume() }
       timer?.cancel()
       timer = nil
   }
   ```
3. Prefer `DispatchQueue.main.asyncAfter` for one-shot delays -- it has no suspend/resume lifecycle and cannot crash on deallocation

**Detection:** Test rapid ESC during any timed operation. Run with Address Sanitizer enabled.

**Confidence:** HIGH -- [documented libdispatch behavior](https://github.com/apple/swift-corelibs-libdispatch/issues/604) and [Apple Developer Forums](https://developer.apple.com/forums/thread/15902).

---

### Pitfall 4: CALayer Shake Animation Position Drift

**Enhancement affected:** Shake animation on the dimension pill (error feedback, invalid selection feedback)

**What goes wrong:** After a CAKeyframeAnimation completes, the layer snaps back to its model-layer position, which was never updated by the animation. If `isRemovedOnCompletion` is set to `false` and `fillMode` to `.forwards` to "fix" the snap-back, the model layer and presentation layer diverge permanently. Subsequent frame calculations use the wrong (model) position, causing the layer to appear in one place but report coordinates from another.

**Why it happens:** Core Animation maintains two parallel layer trees. Explicit animations (CABasicAnimation, CAKeyframeAnimation) only affect the presentation layer. The model layer retains whatever value it had before the animation started. When the animation is removed (default behavior), the presentation layer reverts to the model layer's values.

**Consequences for a shake animation specifically:**
- If you animate `position` with absolute values, the layer teleports to the shake's starting position, shakes, then snaps back to its pre-animation position
- If you use `fillMode = .forwards` + `isRemovedOnCompletion = false`, hit-testing and subsequent layout calculations use the stale model-layer position
- The pill's flip animation (which relies on `pillIsOnLeft`/`pillIsBelow` and frame calculations in CrosshairView.swift `layoutPill()`) breaks because the pill's actual position no longer matches its model position

**Prevention:** Use `isAdditive = true` with zero-centered values. This is the correct approach for shake:
```swift
func shake(layer: CALayer) {
    let anim = CAKeyframeAnimation(keyPath: "position.x")
    anim.values = [0, 10, -10, 10, -5, 5, -2, 0]
    anim.keyTimes = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1.0]
    anim.duration = 0.4
    anim.isAdditive = true  // KEY: offsets added to current position
    // isRemovedOnCompletion defaults to true -- leave it
    // No fillMode needed -- animation returns to 0 offset naturally
    layer.add(anim, forKey: "shakeEffect")
}
```
With `isAdditive = true`:
- Values are offsets from the model layer's current position, not absolute positions
- The final value of 0 means "no offset" -- the layer naturally returns to its correct position
- No model/presentation divergence
- Works regardless of where the layer is positioned (pill can be on left or right side)

**Critical detail for this codebase:** The pill uses `layer.frame` for positioning (CrosshairView.swift lines 316-341), which sets both `position` and `bounds`. An additive shake on `position.x` is safe because it does not interfere with the frame-based layout. But do NOT shake using `transform.translation.x` while the code sets `frame` -- the `frame` property is undefined when `transform` is not identity.

**Detection:** After a shake animation completes, verify that `layer.position` and `layer.presentation()?.position` match. Log both in debug builds.

**Confidence:** HIGH -- well-documented Core Animation behavior. See [objc.io Animations Explained](https://www.objc.io/issues/12-animations/animations-explained/) and [Ole Begemann's snap-back prevention](https://oleb.net/blog/2012/11/prevent-caanimation-snap-back/).

---

## Moderate Pitfalls

---

### Pitfall 5: CATransaction Completion Block Timing with Nested Transactions

**Enhancement affected:** Shake animation, any animation that chains with existing pill flip animation

**What goes wrong:** `CATransaction.setCompletionBlock` fires when ALL animations in that transaction complete. If you nest transactions (the codebase already uses two separate CATransaction blocks in `update()` -- one for lines/feet at line 191, one for the pill at line 305), a completion block on an outer transaction waits for inner animations too. If you add a shake animation inside the pill transaction, the completion block fires after the longer of the shake and the flip animation, not just the shake.

**Prevention:**
- Add shake animations in a separate `CATransaction.begin()/commit()` block, not inside the existing pill transaction
- Use the animation's `delegate` (`animationDidStop(_:finished:)`) instead of `CATransaction.setCompletionBlock` when you need per-animation completion
- Keep the existing two-transaction structure (lines instant, pill animated) and add shake as a third transaction

**Detection:** Log timestamps in completion blocks. Verify they fire at expected times.

**Confidence:** MEDIUM -- based on [CATransaction documentation](https://www.calayer.com/core-animation/2016/05/17/catransaction-in-depth.html) and the codebase's existing multi-transaction pattern.

---

### Pitfall 6: DispatchSourceTimer on Main Queue During Heavy Event Processing

**Enhancement affected:** Any timer-based feature (auto-dismiss, delayed feedback, watchdog)

**What goes wrong:** `DispatchSourceTimer` on `DispatchQueue.main` fires by posting a message to the main run loop. This works in common run loop modes (including event tracking). However, when the run loop is heavily loaded with mouse events (60fps+ mouse tracking, as in this app), timer callbacks can be delayed significantly -- [500ms delays on a 15ms timer have been reported](https://developer.apple.com/forums/thread/106501).

**Why it matters for THIS app:** The app uses `NSApplication.shared.run()` as its event loop (Ruler.swift line 104). Mouse events arrive at 60fps+ with throttling to ~60fps (RulerWindow.swift line 179). A timer intended to fire after 2 seconds for auto-dismiss might fire 2.5 seconds later, or not at all if the user exits before it fires.

**Prevention:**
1. For one-shot delays, prefer `DispatchQueue.main.asyncAfter` -- same queue behavior but simpler lifecycle
2. For repeating timers, use `DispatchSourceTimer` on `DispatchQueue.main` but accept ~100ms timing imprecision
3. Do NOT use `Timer.scheduledTimer` -- it only fires in `.default` mode and will NOT fire during mouse dragging (the run loop enters event tracking mode during drags)
4. For time-critical operations, schedule on a background queue and dispatch UI updates back to main

**Detection:** Add logging around timer creation, expected fire time, and actual fire time. Test while rapidly moving the mouse.

**Confidence:** MEDIUM -- based on [Lapcat Software's investigation](https://lapcatsoftware.com/articles/dispatch-queues-and-run-loop-modes.html) and [Apple Developer Forums reports](https://developer.apple.com/forums/thread/106501). The specific interaction with `NSApplication.run()` in a no-view Raycast extension is not widely documented.

---

### Pitfall 7: UserDefaults Domain in Raycast Swift Extension Process

**Enhancement affected:** Persisting user state (e.g., hint bar dismissed flag)

**What goes wrong:** The Raycast Swift binary runs as a child process spawned by Raycast. `UserDefaults.standard` writes to the process's default domain, which is determined by the process's bundle identifier. For Raycast extension Swift binaries, this is NOT `com.raycast.macos` -- it is the binary's own identifier (or the generic domain if no bundle identifier is set). This means:
1. Preferences written via `UserDefaults.standard` in Swift are invisible to the TypeScript side (which uses Raycast's `LocalStorage` API)
2. The UserDefaults plist file may be written to an unexpected location
3. Different launches of the same extension may or may not share the same defaults domain depending on how the binary is invoked

**Why it matters for THIS app:** The codebase already uses `UserDefaults.standard` for `"com.raycast.design-ruler.hintBarDismissed"` (RulerWindow.swift line 339, Ruler.swift line 31). This DOES work in practice because the key is fully qualified and `UserDefaults.standard` persists to the same plist across launches. But the mechanism is fragile -- if Raycast changes how it spawns Swift binaries, or if the binary's bundle identifier changes, the defaults could be lost.

**Consequences:**
- Data loss: user dismisses hint bar, next launch it reappears (defaults written to wrong domain or file gets cleaned up)
- Not a crash, but a degraded user experience
- Silent failure -- no error, just lost state

**Prevention:**
1. The current approach (fully qualified key with `UserDefaults.standard`) works and is the pragmatic choice for simple boolean flags
2. For anything more complex, use a file-based approach: write to a known path (e.g., `~/.config/design-ruler/state.json`) that is independent of the process's bundle identifier
3. Do NOT use `UserDefaults(suiteName:)` with the Raycast bundle identifier -- the extension process likely lacks entitlements for app group containers
4. Do NOT try to synchronize with Raycast's own preference storage -- the TypeScript preferences API is read-only from the extension's perspective

**Detection:** After writing to UserDefaults, read back immediately and log. Test across extension reinstalls and `ray build` cycles (specifically after `rm -rf swift/Ruler/.raycast-swift-build`).

**Confidence:** MEDIUM -- the current code works empirically, but the UserDefaults domain for Raycast Swift binaries is not officially documented. Based on [Raycast blog on extension architecture](https://www.raycast.com/blog/how-raycast-api-extensions-work) and [Apple documentation on sandbox UserDefaults](https://developer.apple.com/forums/thread/659448).

---

### Pitfall 8: Removing fputs Debug Calls -- Accidentally Removing Diagnostic Context

**Enhancement affected:** Code cleanup, production hardening

**What goes wrong:** Bulk-removing all `fputs("[DEBUG]..."` lines seems safe because they are "just debug output." But some of these calls are inside error-handling paths that provide the ONLY diagnostic information when something goes wrong in production. Removing them means that when a user reports "the ruler didn't appear" or "the crosshair disappeared," you have zero information about what happened.

**Current fputs calls in the codebase and their actual value:**

| Location | Content | Diagnostic Value |
|----------|---------|-----------------|
| EdgeDetector.swift:36 | screen.frame, cgRect, cgImage size, backing | **HIGH** -- critical for diagnosing multi-monitor capture bugs |
| EdgeDetector.swift:75 | currentEdges returned nil | **HIGH** -- the only diagnostic for the "crosshair disappears" bug class |
| RulerWindow.swift:226 | isDragging was still true, resetting stale state | **MEDIUM** -- detects stale state (already a known issue) |
| RulerWindow.swift:252 | starting drag at point, selection count | **LOW** -- pure trace, safe to remove |
| RulerWindow.swift:272 | mouseDragged rejected, isDragging is false | **LOW** -- informational, rare |
| RulerWindow.swift:281 | mouseUp rejected, isDragging is false | **LOW** -- informational, rare |

**Prevention:**
1. Do NOT blanket-remove all fputs calls. Evaluate each one against the table above.
2. Keep the HIGH-value diagnostics but gate them behind a compile-time flag:
   ```swift
   #if DEBUG
   fputs("[DEBUG] ...\n", stderr)
   #endif
   ```
3. For the stale-state detection in mouseDown (`isDragging was still true` at line 226), the fputs is secondary -- the real risk is accidentally removing the `isDragging = false` reset and `crosshairView.showAfterDrag()` call on the lines immediately following it when cleaning up debug output. These lines FIX a real bug. The fputs is just the diagnostic; the code around it is the fix.
4. Consider replacing fputs with `os_log` for production diagnostics -- it has negligible performance cost when not actively observed, persists to the unified log, and can be filtered:
   ```swift
   import os
   private let log = Logger(subsystem: "com.raycast.design-ruler", category: "EdgeDetection")
   log.debug("capture: screen=\(frame) cgImage=\(cgImage.width)x\(cgImage.height)")
   ```

**Detection:** Before removing any fputs line, check if the surrounding code contains error handling or state correction. If the fputs is the only way to know that code path executed, keep it (or replace with os_log).

**Confidence:** HIGH -- direct analysis of the codebase. This is a code review concern, not a research question.

---

## Minor Pitfalls

---

### Pitfall 9: CAKeyframeAnimation Key Collision with Existing Animations

**Enhancement affected:** Shake animation on the pill

**What goes wrong:** Adding an animation with the same key as an existing animation replaces it. If you use `layer.add(anim, forKey: "position")` for the shake, and the pill flip animation also animates position (it currently uses implicit animations via `CATransaction`), the animations can collide.

**Prevention:**
- Use a unique, descriptive key: `layer.add(anim, forKey: "shakeEffect")`
- The existing pill flip uses `CATransaction`-based implicit animations (no explicit key), so explicit animations with any custom key will coexist -- but verify this assumption
- If a second shake is triggered while the first is still running, the key-based replacement actually prevents double-shake (desirable behavior)

**Confidence:** MEDIUM -- standard Core Animation behavior.

---

### Pitfall 10: Shake Animation During Pill Flip Transition

**Enhancement affected:** Shake animation timing

**What goes wrong:** If the user triggers a shake (e.g., invalid edge skip) while the pill is mid-flip-animation (transitioning from right to left side via the `flipped` path in `layoutPill()`), the shake's `isAdditive` offsets are added to the in-flight animation position. This creates a visually jarring compound motion instead of a clean shake.

**Prevention:**
- Check if a flip is in progress before starting a shake (track via `isFlipping` boolean set in `layoutPill` and cleared in a CATransaction completion block)
- Alternatively, apply the shake to a wrapper layer that contains all pill layers, so the shake and flip operate on different layers in the hierarchy
- Or: simply do not shake -- if the pill just flipped, the user is near a screen edge and the shake feedback is less important

**Confidence:** LOW -- theoretical concern, would need to be tested visually.

---

### Pitfall 11: CAKeyframeAnimation keyTimes/values Count Mismatch

**Enhancement affected:** Any CAKeyframeAnimation (shake, bounce, etc.)

**What goes wrong:** If the `keyTimes` array count does not match the `values` array count, Core Animation falls back to equal spacing or produces unexpected interpolation. No runtime error -- just wrong animation.

**Prevention:** Define values and keyTimes as paired constants. Assert `values.count == keyTimes.count` in debug builds.

**Detection:** Animation looks jerky or has unexpected pauses.

**Confidence:** HIGH -- standard Core Animation behavior.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Shake animation on pill | Position drift (Pitfall 4), key collision (Pitfall 9), flip conflict (Pitfall 10) | Use `isAdditive = true` with zero-centered values. Use unique animation keys. Check for in-progress flip. |
| Cursor state management | Push/pop imbalance (Pitfall 1), hide/unhide counter (Pitfall 2) | Centralize cursor management behind a state enum. Force-unhide on exit. |
| Timer-based features | Deallocation crash (Pitfall 3), timing imprecision (Pitfall 6) | Use `asyncAfter` for one-shot delays. Always resume before cancel. |
| UserDefaults persistence | Domain fragility (Pitfall 7) | Keep fully-qualified keys. Accept empirical behavior. Use files for complex state. |
| Debug cleanup | Losing diagnostics (Pitfall 8) | Evaluate each fputs individually. Migrate HIGH-value calls to `#if DEBUG` or `os_log`. |
| Animation chaining | Transaction completion timing (Pitfall 5) | Use separate CATransaction blocks for independent animations. |

---

## Sources

- [Apple NSCursor.hide() documentation](https://developer.apple.com/documentation/appkit/nscursor/hide())
- [Apple NSCursor.push() documentation](https://developer.apple.com/documentation/appkit/nscursor/1532500-push)
- [Aggressively Hiding the Cursor -- Sam Soffes](https://soff.es/blog/aggressively-hiding-the-cursor)
- [Apple DispatchSourceTimer documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcetimer)
- [libdispatch issue #604: Crash when deallocating never-resumed timer](https://github.com/apple/swift-corelibs-libdispatch/issues/604)
- [Apple Developer Forums: Dispatch Source deallocated](https://developer.apple.com/forums/thread/15902)
- [Apple Developer Forums: GCD Timer not calling Event Handler](https://developer.apple.com/forums/thread/106501)
- [objc.io: Animations Explained](https://www.objc.io/issues/12-animations/animations-explained/)
- [Ole Begemann: Prevent CAAnimation Snap Back](https://oleb.net/blog/2012/11/prevent-caanimation-snap-back/)
- [CALayer: CATransaction in Depth](https://www.calayer.com/core-animation/2016/05/17/catransaction-in-depth.html)
- [Lapcat Software: Dispatch Queues and Run Loop Modes](https://lapcatsoftware.com/articles/dispatch-queues-and-run-loop-modes.html)
- [Raycast Blog: How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- [Apple Developer Forums: UserDefaults in sandboxed apps](https://developer.apple.com/forums/thread/659448)
- [Cocoa with Love: Design patterns for safe timer usage](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html)
- [NSCursor push/pop stack discussion -- GNUstep](https://lists.gnu.org/archive/html/gnustep-dev/2013-10/msg00012.html)
- [Apple Developer Forums: Assertion failure during deinit due to DispatchSourceTimer](https://developer.apple.com/forums/thread/759042)
