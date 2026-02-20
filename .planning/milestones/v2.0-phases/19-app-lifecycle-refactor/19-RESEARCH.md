# Phase 19: App Lifecycle Refactor - Research

**Researched:** 2026-02-18
**Domain:** Swift AppKit lifecycle — `NSApplication.run()`, `NSApp.terminate()`, and `OverlayCoordinator` session control
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Session dismiss behavior**
- Instant vanish on ESC — same behavior as Raycast, windows removed immediately (no fade/transition)
- Cursor restoration identical in both app mode and Raycast mode — no mode-specific cursor logic
- No visual feedback on dismiss — the menu bar icon (always visible) is sufficient indication the app is alive
- 10-minute inactivity timer ends the overlay session (returns to idle) but does NOT quit the app process

**State reset between sessions**
- Completely fresh state every session for both Measure and Alignment Guides
- Measure: no selections, no skip counts, no residual edge detection state carried over
- Alignment Guides: no guide lines carried over, blank canvas every session
- Guide color and direction reset to defaults (dynamic color, vertical) — do not persist last-used values
- Hint bar always starts expanded and collapses automatically — this is existing behavior, not a per-session preference

**Re-invocation guard**
- If the same command is triggered while already active: silently ignore (running session continues undisturbed)
- If a different command is triggered while one is active: silently ignore (active session takes priority)
- No feedback on ignored invocations — the active overlay is already visible on screen
- No cooldown between ESC and next invocation — allow instant re-invocation (success criteria #2 requires this)

### Claude's Discretion
- Internal implementation of RunMode detection (enum shape, where it's checked)
- Cleanup ordering and teardown sequence details
- Whether to use a boolean guard or a state enum for the "session active" lock

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 19 is a surgical refactor of `OverlayCoordinator` and its two subclasses (`Measure`, `AlignmentGuides`). The core problem is that `OverlayCoordinator.run()` currently calls `app.run()` to start the event loop and `NSApp.terminate(nil)` to end the process. In a standalone app the event loop is already running (started by `AppDelegate`/`@main`), so calling `app.run()` again would nest a second run loop — which is wrong. `NSApp.terminate(nil)` would also kill the persistent process. Both calls must become conditional on whether we are in Raycast mode or standalone app mode.

The three requirements map to exactly three targeted changes: (1) add a `RunMode` enum with `.raycast` / `.standalone` cases to `OverlayCoordinator` and gate `app.run()` / `NSApp.terminate(nil)` behind it, (2) replace `NSApp.terminate(nil)` in `handleExit()` with a session-teardown path for `.standalone` mode that closes windows and resets state without killing the process, and (3) call `CursorManager.shared.restore()` at the *start* of every `run()` call (already partially in place via SIGTERM handler; needs to be explicit at the top of `run()`). A simple boolean `isSessionActive` flag on the coordinator satisfies the re-invocation guard requirement with zero complexity.

**Primary recommendation:** Add `RunMode` enum and `isSessionActive` bool to `OverlayCoordinator`; gate the two calls that touch the process lifetime (`app.run()`, `NSApp.terminate(nil)`) with a single `if runMode == .raycast` check; add `CursorManager.shared.restore()` as the first line of `run()`; `AppDelegate` sets `.standalone` on the coordinator singletons and calls `run()` directly.

---

## Standard Stack

### Core
| Component | What it is | Purpose |
|-----------|------------|---------|
| `OverlayCoordinator` (existing) | Swift open class in `DesignRulerCore` | Lifecycle base; modified in this phase |
| `CursorManager.shared` (existing) | Package-final singleton | Cursor state machine; `restore()` called at session start |
| `AppDelegate` (existing stub) | `@main` class in `App/Sources/` | Calls coordinator run methods; sets run mode |
| `RunMode` enum (new, ~5 lines) | Nested or standalone enum | Gates `app.run()` / `NSApp.terminate()` |

### Supporting
| Component | Purpose |
|-----------|---------|
| `isSessionActive: Bool` flag | Re-invocation guard; set true at `run()` entry, false at `handleExit()` completion |
| `setActivationPolicy(.accessory)` | Called once in `applicationDidFinishLaunching`, not inside coordinator (prior decision) |

---

## Architecture Patterns

### Current Lifecycle (Raycast)

```
Measure.shared.run(hideHintBar:corrections:)
  → OverlayCoordinator.run(hideHintBar:)
      → [startup sequence steps 1-11]
      → app.run()              ← BLOCKS until terminate
      → (never returns)
  → (never returns)
```

On ESC:
```
handleExit()
  → CursorManager.shared.restore()
  → window.close() × N
  → NSApp.terminate(nil)       ← KILLS PROCESS
```

### Target Lifecycle (RunMode-aware)

```
// Standalone — AppDelegate path
AppDelegate.applicationDidFinishLaunching:
    OverlayCoordinator.runMode = .standalone   // set before calling run()
    setActivationPolicy(.accessory)            // set once here, not in coordinator
    Measure.shared.run(...)                    // or triggered by menu bar item later

OverlayCoordinator.run():
    CursorManager.shared.restore()             // always — LIFE-03
    guard !isSessionActive else { return }     // re-invocation guard
    isSessionActive = true
    ... [startup steps 1-10, unchanged] ...
    if runMode == .raycast { app.run() }       // LIFE-01: only blocks in Raycast mode
    // standalone: returns immediately, event loop already running

handleExit():
    isSessionActive = false                    // clear BEFORE any async work
    CursorManager.shared.restore()
    windows.forEach { $0.orderOut(nil); $0.close() }
    windows.removeAll()
    activeWindow = nil
    inactivityTimer?.invalidate()
    sigTermSource?.cancel()
    if runMode == .raycast { NSApp.terminate(nil) }  // LIFE-02: only terminates in Raycast mode
    // standalone: returns, process stays alive

// Inactivity timer (standalone):
inactivityTimer fires → handleExit()          // same path, process stays alive
```

### RunMode Enum Placement

The `RunMode` enum belongs in `OverlayCoordinator.swift` as a public/open-access type. It does not need to be in a separate file.

```swift
// In OverlayCoordinator.swift (DesignRulerCore)
public enum RunMode {
    case raycast    // Event loop owned by this coordinator; terminate kills process
    case standalone // Event loop owned by AppDelegate; terminate would kill app
}
```

`runMode` defaults to `.raycast` so all existing Raycast bridge code (`Measure.swift`, `AlignmentGuides.swift` in `RaycastBridge/`) requires zero changes — they never set `runMode`, it stays `.raycast`, behavior is identical to today.

### Re-invocation Guard Shape

The phase context notes that "a simple boolean guard" is preferred over a state enum. The boolean `isSessionActive` is correct:

```swift
// At top of run():
CursorManager.shared.restore()      // LIFE-03: always reset cursor state first
guard !isSessionActive else { return }
isSessionActive = true

// At top of handleExit():
isSessionActive = false             // synchronous, before any async cleanup
```

Setting `isSessionActive = false` synchronously at the very start of `handleExit()` ensures instant re-invocation works: by the time the `run()` method is called again, the guard is already cleared.

### setActivationPolicy(.accessory) — Where It Lives

**Current:** Inside `OverlayCoordinator.run()` (step 6 in the sequence).
**Target for standalone:** Must also be called in `AppDelegate.applicationDidFinishLaunching` — but calling it *again* inside `run()` is harmless (it's idempotent). The prior decision says "set once in applicationDidFinishLaunching, removed from coordinator." This means step 6 is deleted from `run()` and moved to `AppDelegate` only. This is a single-line removal from the coordinator.

**Risk:** If the Raycast bridge path still needs `.accessory` policy, removing it from `run()` would break Raycast. Verify: In Raycast mode, the process is launched fresh for each command invocation, so `applicationDidFinishLaunching` runs anyway (implicitly via app startup). But `AppDelegate` is in the `App` target, not in `RaycastBridge`. The Raycast binary has its own entry point — the `@raycast` macro generates its own main. So the `App` target's `AppDelegate` does NOT run in Raycast mode.

**Conclusion:** The `setActivationPolicy(.accessory)` call must remain in `OverlayCoordinator.run()` for Raycast to work correctly. The prior decision to "remove from coordinator" only applies if the app always starts with it set — but since Raycast has no AppDelegate, the coordinator must keep it. The safest approach: keep it in `run()` AND add it to `AppDelegate`. Idempotent calls are safe.

### SIGTERM Handler — Session Lifetime

Currently `setupSignalHandler()` is called in `run()` and `sigTermSource` is stored on the coordinator. In standalone mode with multiple sessions, the SIGTERM handler is registered once per session. Each call to `setupSignalHandler()` creates a new `DispatchSourceSignal` and replaces `sigTermSource`, cancelling the previous one when reassigned (if `sigTermSource` is a stored property, the old source is deallocated when replaced — DispatchSource cancels on dealloc). This is safe.

Alternatively, `setupSignalHandler()` could be called once in `applicationDidFinishLaunching`. Either approach works; keeping it in `run()` is the lowest-diff change.

### Inactivity Timer — Standalone Behavior

In `.standalone` mode the inactivity timer fires `handleExit()`, which closes windows and returns (process stays alive). No special handling needed — the same `handleExit()` path works correctly because `NSApp.terminate(nil)` is gated.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Detecting if event loop is running | Custom NSRunLoop inspection | Just check `runMode` — coordinator knows which context it was called in |
| Cursor state cleanup between sessions | Custom cursor reset logic | `CursorManager.shared.restore()` already handles all edge cases (hideCount, state enum) |

---

## Common Pitfalls

### Pitfall 1: Calling app.run() When Event Loop Already Running
**What goes wrong:** Nested `NSApplication.run()` calls create a nested run loop. The second `run()` call does not block the same way — it may behave unexpectedly, but more importantly it prevents the coordinator from returning, trapping state.
**Why it happens:** `app.run()` was added to the coordinator assuming it always owns the event loop (Raycast context).
**How to avoid:** Gate with `if runMode == .raycast { app.run() }`.
**Confidence:** HIGH (AppKit documented behavior)

### Pitfall 2: NSApp.terminate() Kills the Persistent App
**What goes wrong:** ESC kills the menu bar app process entirely.
**Why it happens:** `handleExit()` unconditionally calls `NSApp.terminate(nil)`.
**How to avoid:** Gate with `if runMode == .raycast { NSApp.terminate(nil) }`.
**Confidence:** HIGH (obvious from code)

### Pitfall 3: isSessionActive Not Cleared Before Windows Close
**What goes wrong:** Re-invocation blocked even after exit completes.
**Why it happens:** If `isSessionActive = false` runs after async cleanup, there's a window where it's still true.
**How to avoid:** Set `isSessionActive = false` as the FIRST line of `handleExit()`, synchronously, before any window manipulation.
**Confidence:** HIGH

### Pitfall 4: CursorManager State Leaks Into Next Session
**What goes wrong:** Second session launches with cursor hidden or in resize state from previous session. Success criteria #2 specifically checks for "no cursor glitch."
**Why it happens:** If the previous session was interrupted without calling `CursorManager.shared.restore()` (e.g., app stayed alive but coordinator was not cleanly exited), `hideCount` > 0 and state != .idle.
**How to avoid:** Call `CursorManager.shared.restore()` at the very top of `run()`, before the `isSessionActive` guard check. This way it always runs even if a re-invocation is rejected.

Wait — actually calling restore() BEFORE the guard means it runs on rejected re-invocations too. That's wrong if a session is active: calling restore() mid-session would unhide the cursor. The correct ordering:

```swift
public func run(hideHintBar: Bool) {
    guard !isSessionActive else { return }  // fast-reject first
    CursorManager.shared.restore()          // then reset cursor — session not active
    isSessionActive = true
    ...
}
```

This matches the spec: "CursorManager state resets at the start of every new overlay session." A rejected invocation is not a new session, so restore() should not run on it.
**Confidence:** HIGH

### Pitfall 5: Windows Not Fully Torn Down Between Sessions
**What goes wrong:** Second session creates new windows but old windows are still in the `windows` array or still visible.
**Why it happens:** `handleExit()` in standalone mode might miss closing windows or clearing the array.
**How to avoid:** `handleExit()` must explicitly: `orderOut(nil)`, `close()`, `removeAll()`, `activeWindow = nil`. Verify this is complete. Currently `handleExit()` calls `window.close()` without `orderOut(nil)` first — in standalone mode, adding `orderOut(nil)` before `close()` ensures immediate visual removal (consistent with "instant vanish" requirement).
**Confidence:** HIGH (review of current `handleExit()` code shows it calls `close()` but not `orderOut(nil)`)

### Pitfall 6: setActivationPolicy Removed From Coordinator Breaks Raycast
**What goes wrong:** Raycast binary has no `AppDelegate`; if `.accessory` policy is only set in `AppDelegate`, Raycast sessions skip it.
**Why it happens:** The prior decision said "remove from coordinator, set once in applicationDidFinishLaunching" — but this only applies to the standalone app path.
**How to avoid:** Keep `setActivationPolicy(.accessory)` in `OverlayCoordinator.run()`. Also add it in `AppDelegate.applicationDidFinishLaunching`. Both are safe (idempotent call).
**Confidence:** HIGH

---

## Code Examples

### RunMode Enum + isSessionActive Property

```swift
// In OverlayCoordinator.swift

public enum RunMode {
    case raycast
    case standalone
}

open class OverlayCoordinator {
    public var runMode: RunMode = .raycast  // default: Raycast, no changes needed in RaycastBridge
    public var isSessionActive = false
    // ... existing properties unchanged ...
}
```

### Modified run() — Entry Guard + Cursor Reset

```swift
public func run(hideHintBar: Bool) {
    guard !isSessionActive else { return }     // LIFE-01 re-invocation guard
    isSessionActive = true
    CursorManager.shared.restore()             // LIFE-03 cursor reset at session start

    // 1. Warmup capture
    _ = CGWindowListCreateImage(...)

    // ... steps 2-10 unchanged ...

    // 11. Launch time, activate, signal handler, inactivity timer
    launchTime = CFAbsoluteTimeGetCurrent()
    NSApp.activate(ignoringOtherApps: true)
    setupSignalHandler()
    resetInactivityTimer()

    // Gate: only start the event loop in Raycast mode
    if runMode == .raycast {
        app.run()
    }
    // Standalone: returns immediately, AppDelegate's event loop continues
}
```

### Modified handleExit() — Session Teardown vs Process Kill

```swift
public func handleExit() {
    isSessionActive = false                   // synchronous first — allows instant re-invocation
    CursorManager.shared.restore()
    inactivityTimer?.invalidate()
    inactivityTimer = nil
    for window in windows {
        window.orderOut(nil)                  // instant visual removal
        window.close()
    }
    windows.removeAll()
    activeWindow = nil
    cursorWindow = nil

    if runMode == .raycast {
        NSApp.terminate(nil)                  // LIFE-02: only in Raycast mode
    }
    // Standalone: returns here, process stays alive
}
```

### AppDelegate — Standalone Entry Point

```swift
// App/Sources/AppDelegate.swift
import AppKit
import DesignRulerCore

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // TODO Phase 20+: menu bar item setup
        // For now, trigger Measure directly for testing success criteria
        // Measure.shared.runMode = .standalone
        // Measure.shared.run(hideHintBar: false, corrections: "smart")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

Note: `Measure` and `AlignmentGuides` classes are in `RaycastBridge` target (not `DesignRulerCore`), so `AppDelegate` cannot import them directly yet. For Phase 19, the coordinators being called are `OverlayCoordinator` subclasses. The `AppDelegate` may need to either:
- Call a thin wrapper in `DesignRulerCore` (e.g., a factory method), OR
- The `Measure`/`AlignmentGuides` coordinator subclasses be moved from `RaycastBridge` to `DesignRulerCore`

See Open Questions section.

---

## Exact File Changes Required

### `DesignRulerCore/Utilities/OverlayCoordinator.swift`

1. Add `public enum RunMode` before the class
2. Add `public var runMode: RunMode = .raycast` property
3. Add `public var isSessionActive = false` property
4. Modify `run()`: add guard + restore() at top, gate `app.run()` at bottom
5. Modify `handleExit()`: set `isSessionActive = false` first, add `orderOut(nil)` before `close()`, gate `NSApp.terminate(nil)`

Total: ~15 line changes across one file.

### `App/Sources/AppDelegate.swift`

1. Import `DesignRulerCore`
2. Add `NSApp.setActivationPolicy(.accessory)` in `applicationDidFinishLaunching`
3. Add invocation of coordinator's `run()` method for Phase 19 testing

### Files NOT changed

- `RaycastBridge/Measure.swift` — no changes needed, `runMode` defaults to `.raycast`
- `RaycastBridge/AlignmentGuides.swift` — no changes needed
- `DesignRulerCore/Cursor/CursorManager.swift` — no changes needed
- All window classes — no changes needed
- `Package.swift` — no changes needed
- `App/project.yml` — no changes needed

---

## State of the Art

| Old Approach | Target Approach | Impact |
|---|---|---|
| `OverlayCoordinator.run()` always calls `app.run()` | Gate with `if runMode == .raycast` | Allows coordinator invocation from persistent app |
| `handleExit()` always calls `NSApp.terminate(nil)` | Gate with `if runMode == .raycast` | Process stays alive after overlay dismissal |
| Cursor state assumed clean at entry | Explicit `CursorManager.shared.restore()` at `run()` start | Prevents cursor glitches between sessions |
| No re-invocation protection | `isSessionActive` boolean guard | Prevents double-invocation artifacts |

---

## Open Questions

1. **Where do `Measure` and `AlignmentGuides` coordinator subclasses live for Phase 19 invocation from AppDelegate?**
   - What we know: `Measure` and `AlignmentGuides` are currently in `Sources/RaycastBridge/` which is an executable target (not a library). `AppDelegate` is in the `App` target which depends on `DesignRulerCore` (a library), not `RaycastBridge` (an executable).
   - What's unclear: Can `AppDelegate` access `Measure.shared` / `AlignmentGuides.shared`? If these types remain in `RaycastBridge`, they're not importable by `App`.
   - Recommendation: For Phase 19, the simplest approach is to create thin `MeasureCoordinator` and `AlignmentGuidesCoordinator` subclasses *inside `DesignRulerCore`*, OR move the coordinator subclass logic to `DesignRulerCore` and keep only the `@raycast` func declarations in `RaycastBridge`. The `@raycast` macro requirements may constrain what can live in a library vs executable — this is worth verifying. However, since the phase description says "Invoke Measure from AppDelegate" in success criterion #1, *some* form of coordinator subclass must be accessible from `App`. The cleanest minimal change: add a `public` entry point function/type in `DesignRulerCore` that wraps the coordinator logic, callable from `AppDelegate`.
   - Confidence: MEDIUM (architectural constraint is clear; exact solution needs a decision)

2. **`app.setActivationPolicy(.accessory)` inside `run()` — safe to keep for Raycast?**
   - What we know: Currently in `run()` at step 6. Idempotent call. Prior decision says move to `applicationDidFinishLaunching`.
   - What's unclear: Whether keeping it in `run()` for Raycast mode causes any issue.
   - Recommendation: Keep in `run()` for both modes. Idempotent. No risk.
   - Confidence: HIGH

---

## Sources

### Primary (HIGH confidence)
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift` — full lifecycle code
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/swift/DesignRuler/Sources/DesignRulerCore/Cursor/CursorManager.swift` — cursor state machine
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/swift/DesignRuler/Sources/RaycastBridge/Measure.swift` — Raycast bridge pattern
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/swift/DesignRuler/Sources/RaycastBridge/AlignmentGuides.swift` — Raycast bridge pattern
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/App/Sources/AppDelegate.swift` — current stub
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/App/project.yml` — build target structure
- Direct code reading: `/Users/haythem/conductor/workspaces/design-ruler-v2/porto/swift/DesignRuler/Package.swift` — package structure
- `CLAUDE.md` — project LIFE requirements, prior decisions, architecture constraints

### Secondary (MEDIUM confidence)
- AppKit `NSApplication.run()` documented behavior: nested run loops are valid but behavior depends on context — the practical issue here is that `run()` blocks, which in standalone mode would trap coordinator state

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all code is read directly from the codebase; no external libraries involved
- Architecture patterns: HIGH — the RunMode + guard + gated terminate pattern is straightforward and directly derived from the existing code structure
- Pitfalls: HIGH — all pitfalls identified from direct code reading (what the current code does vs. what it needs to do)
- Open question #1 (coordinator subclass accessibility): MEDIUM — the constraint is clear but the exact implementation choice needs to be made during planning

**Research date:** 2026-02-18
**Valid until:** Stable — this is pure internal refactor research, no external library dependencies
