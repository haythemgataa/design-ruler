# Pitfalls Research: Standalone macOS Menu Bar App

**Domain:** Adding a persistent menu bar app alongside an existing Raycast extension (spawn-run-exit model)
**Researched:** 2026-02-17
**Confidence:** HIGH — based on direct codebase analysis of `OverlayCoordinator`, `CursorManager`, `PermissionChecker`, `Package.swift`, and deep knowledge of macOS process/permission/build-system APIs

---

## Critical Pitfalls

Mistakes that cause crashes, permission denial loops, broken cursor state, or require architectural rewrites.

---

### Pitfall 1: NSApp.terminate(nil) in a Persistent App Kills the Whole Process

**What goes wrong:**
`OverlayCoordinator.handleExit()` calls `NSApp.terminate(nil)` (line 168 of OverlayCoordinator.swift). In the Raycast extension, this is correct: the process should die when the user presses ESC or the inactivity timer fires. In a persistent menu bar app, `NSApp.terminate(nil)` exits the entire process — quitting the app, not just ending one overlay session.

**Why it happens:**
The existing lifecycle equates "overlay done" with "process done." This worked when Raycast spawned a fresh process per invocation. In a persistent app, the process lives continuously and each Measure/Alignment Guides invocation is one session within that process.

**How to avoid:**
Refactor `handleExit()` into two distinct behaviors:
```swift
// OLD (Raycast): kill the process
func handleExit() {
    CursorManager.shared.restore()
    for window in windows { window.close() }
    NSApp.terminate(nil)  // <- WRONG for persistent app
}

// NEW (persistent): teardown session, return to idle
func endSession() {
    CursorManager.shared.restore()
    for window in windows { window.orderOut(nil); window.close() }
    windows.removeAll()
    activeWindow = nil
    inactivityTimer?.invalidate()
    // Return control to the menu bar — do NOT call NSApp.terminate
}
```

The `OverlayCoordinator` base class needs a mode flag (`isEmbeddedInPersistentApp`) or a full subclass/protocol split so Raycast and standalone share the session teardown but diverge on process termination.

**Warning signs:**
- Pressing ESC while using Measure from the menu bar app quits the entire app
- Activity Monitor shows the app process disappearing on ESC
- The menu bar icon vanishes after one invocation

**Phase to address:** App shell / lifecycle foundation — the very first phase that wires `NSStatusItem` to overlay invocation.

---

### Pitfall 2: app.run() Already Called — Cannot Call It Again Per Session

**What goes wrong:**
`OverlayCoordinator.run()` ends with `app.run()` (line 109 of OverlayCoordinator.swift). In the Raycast model, `NSApplication.shared.run()` is called once and the process runs until exit. In a persistent menu bar app, `NSApplication.shared.run()` is already running (started by the app delegate in `main.swift`). Calling it again from a second Measure invocation is a no-op at best; at worst it blocks on the already-running event loop and the second invocation never returns.

**Why it happens:**
`NSApplication.run()` starts the main run loop. If the run loop is already running (which it always is in a persistent app), the call returns immediately or re-enters the loop in a nested fashion. The overlay appears but the coordinator's post-`app.run()` teardown never executes, leaving ghost windows and corrupted `CursorManager` state.

**How to avoid:**
Remove `app.run()` from `OverlayCoordinator.run()` entirely in the standalone build. The event loop is already managed by the `NSApplicationDelegate`. Structure the coordinator's `run()` method so it only:
1. Sets up capture, windows, callbacks
2. Calls `makeKeyAndOrderFront` / `makeKey`
3. Returns immediately (does NOT start a run loop)

Use compile-time or runtime flags:
```swift
// Option A: compile-time (cleanest)
#if STANDALONE_APP
    // do not call app.run()
#else
    app.run()  // Raycast only
#endif

// Option B: runtime flag on OverlayCoordinator
var shouldRunEventLoop: Bool = true
// ... at end of run():
if shouldRunEventLoop { app.run() }
```

**Warning signs:**
- Second invocation of Measure never shows an overlay
- Console shows `NSApplication.run` being called repeatedly
- Windows from the first invocation persist into the second session

**Phase to address:** App shell / lifecycle foundation.

---

### Pitfall 3: Screen Recording Permission Request Has No UI in a Persistent App

**What goes wrong:**
`PermissionChecker.requestScreenRecordingPermission()` calls `CGRequestScreenCaptureAccess()`. In the Raycast model, if denied, the overlay simply fails silently and the process exits. In a standalone app, a denied permission requires showing the user actionable UI (a dialog explaining why, a button to open System Settings). If the app just silently fails to capture and shows a blank overlay, users think it's broken and quit.

**Why it happens:**
`CGRequestScreenCaptureAccess()` does trigger a system prompt on first run, but:
- It only triggers once per app bundle. Subsequent calls when denied return `false` with no prompt.
- The system prompt appears asynchronously and the app must handle the case where the user clicks "Don't Allow."
- A persistent app needs to recover gracefully from denial and guide users to System Settings → Privacy & Security → Screen Recording.

**How to avoid:**
1. Add `NSPrivacyAccessDescription` key `NSScreenCaptureUsageDescription` to Info.plist with a clear reason string.
2. Wrap all permission-gated actions in a check with fallback UI:
```swift
if !PermissionChecker.hasScreenRecordingPermission() {
    showPermissionDeniedAlert(
        for: "Screen Recording",
        openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    )
    return
}
```
3. Implement a `PermissionStatusView` that the menu bar popover shows when permission is missing, with a "Open System Settings" button.
4. Do NOT attempt to show an overlay when permission is denied — `CGWindowListCreateImage` returns nil, the background is black, and edge detection is non-functional.

**Warning signs:**
- App shows a black overlay silently when screen recording is denied
- No user guidance after denying the permission prompt
- App crashes with force-unwrap nil from `captureScreen`

**Phase to address:** Permission handling (early, before any overlay work).

---

### Pitfall 4: Global Hotkeys Require Accessibility Permission — Different From Screen Recording

**What goes wrong:**
Registering global hotkeys (to invoke Measure or Alignment Guides from any app, not just the menu bar) requires the Accessibility permission (`AXIsProcessTrusted()`), which is completely separate from Screen Recording. Many developers assume screen recording permission is sufficient. The app fails to receive keydown events from other apps' contexts, and the hotkey silently does nothing.

**Why it happens:**
Global keyboard event monitoring via `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` or `CGEventTap` requires the Accessibility entitlement. Without it, the monitor is registered (no error) but global key events are never delivered. Local monitors (within the app) work without it, but "global" means intercepting events regardless of which app has focus.

**How to avoid:**
1. Request Accessibility permission separately with clear UI: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)`.
2. Add a secondary check at hotkey registration time:
```swift
guard AXIsProcessTrusted() else {
    showPermissionDeniedAlert(for: "Accessibility (required for global hotkeys)",
        openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    return
}
```
3. Treat the Accessibility permission as optional — the app must still work via menu bar clicks if the user declines hotkeys.
4. Do NOT hardcode hotkeys — let users configure them to avoid conflicts with other apps' global shortcuts.
5. The Info.plist must include `NSAppleEventsUsageDescription` (if using AppleEvents) but Accessibility permission itself is user-granted via System Settings, not an entitlement that goes in the binary.

**Warning signs:**
- Hotkey works when Design Ruler is frontmost but not when other apps are focused
- `NSEvent.addGlobalMonitorForEvents` returns a non-nil token (looks registered) but events never fire
- No runtime error — the failure is completely silent

**Phase to address:** Hotkey system (dedicated phase, after basic menu bar shell works).

---

### Pitfall 5: setActivationPolicy(.accessory) Called Every Invocation Causes Window Ordering Chaos

**What goes wrong:**
`OverlayCoordinator.run()` calls `app.setActivationPolicy(.accessory)` (line 66). In the Raycast model, this is fine — it runs once before the app loop. In a persistent menu bar app, this is called on every Measure/Alignment Guides invocation. Calling `setActivationPolicy` at runtime is documented to have side effects: it can cause windows to lose their front-most status, cause the Dock icon to flicker in/out, and occasionally make the key window change unexpectedly.

**Why it happens:**
A persistent menu bar app should set its activation policy once at startup in the `NSApplicationDelegate.applicationDidFinishLaunching`. The policy for a menu bar app without a Dock icon is `.accessory`. Calling `setActivationPolicy(.accessory)` repeatedly during the session lifecycle is a no-op in the best case but actively harmful in some macOS versions (13/14 have had regressions here).

**How to avoid:**
Set activation policy once in `applicationDidFinishLaunching`:
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    // ... setup NSStatusItem ...
}
```
Remove the `app.setActivationPolicy(.accessory)` call from `OverlayCoordinator.run()` in the standalone build.

**Warning signs:**
- Dock icon appears briefly when invoking Measure then disappears
- Overlay window loses key status immediately after appearing
- Other app's windows intermittently come to front during overlay creation

**Phase to address:** App shell / lifecycle foundation.

---

### Pitfall 6: SIGTERM Handler Conflicts With Normal App Termination

**What goes wrong:**
`OverlayCoordinator.setupSignalHandler()` installs a SIGTERM handler (line 186 of OverlayCoordinator.swift). In the Raycast model, SIGTERM is how Raycast kills the process on user cancellation. In a persistent menu bar app, SIGTERM is the normal shutdown signal. The handler calls `handleExit()` which (currently) calls `NSApp.terminate(nil)` — creating a SIGTERM → terminate → SIGTERM loop. Additionally, the DispatchSourceSignal for SIGTERM must be torn down when the session ends, or it leaks and intercepts legitimate SIGTERM on app quit.

**Why it happens:**
The signal handler is designed for process lifetime, not session lifetime. In a persistent app, the signal handler must either:
- Not be installed per-session (install once at app startup with different logic)
- Be torn down explicitly at session end

**How to avoid:**
1. Move SIGTERM handling to the app delegate level, not the coordinator.
2. The app delegate's SIGTERM handler should: call `endSession()` on any active coordinator, then call `NSApp.terminate(nil)`.
3. Remove `setupSignalHandler()` from `OverlayCoordinator.run()` in the standalone build.
4. Store `sigTermSource` at the app delegate level and cancel it on `applicationWillTerminate`.

**Warning signs:**
- App cannot be quit cleanly from the command line with `kill <pid>`
- On app quit, the SIGTERM is intercepted by the session handler and the process restarts instead of terminating
- Memory leak: `sigTermSource` DispatchSource keeps running after session ends

**Phase to address:** App shell / lifecycle foundation.

---

### Pitfall 7: Inactivity Timer Fires and Quits the App Instead of Ending the Session

**What goes wrong:**
The 10-minute inactivity watchdog in `OverlayCoordinator.resetInactivityTimer()` calls `handleExit()` (line 202 of OverlayCoordinator.swift). In the Raycast model, this is correct: a forgotten overlay should exit the process. In a persistent menu bar app, the inactivity timer should dismiss the overlay and return to the menu bar state — not quit the app.

**How to avoid:**
Same fix as Pitfall 1: refactor `handleExit()` into `endSession()` that does NOT call `NSApp.terminate`. The inactivity timer callback becomes:
```swift
Timer.scheduledTimer(...) { [weak self] _ in
    self?.endSession()  // dismiss overlay, return to menu bar
}
```

**Warning signs:**
- App quits after 10 minutes of idle Measure use
- Menu bar icon disappears after prolonged sessions

**Phase to address:** App shell / lifecycle foundation (fix alongside Pitfall 1 — same root cause).

---

### Pitfall 8: CursorManager.shared State Leaks Between Sessions

**What goes wrong:**
`CursorManager` is a singleton (`CursorManager.shared`). If a session ends abnormally (crash, force-quit of overlay) without calling `restore()`, the cursor remains hidden and `hideCount > 0`. The next session starts with a corrupted state: `hide()` guards on `state == .idle` (line 41 of CursorManager.swift) and does nothing — cursor stays hidden from the previous session.

**Why it happens:**
In the Raycast model, the process dies on abnormal exit — the OS restores the cursor automatically because `NSCursor.hide()` is process-scoped. In a persistent app, the process survives abnormal session exits, so singleton state must be explicitly reset.

**How to avoid:**
1. Call `CursorManager.shared.restore()` at the START of every new session (before `hide()` or `showResize()`), not just at the end.
2. Add a `reset()` method that unconditionally resets state without unhiding (for cases where the OS already restored the cursor):
```swift
func resetForNewSession() {
    // Force-restore to clean state regardless of previous session
    restore()  // unhides all levels, sets arrow cursor, resets state
}
```
3. Call `resetForNewSession()` as the first action in `OverlayCoordinator.run()`.

**Warning signs:**
- After one session crash, subsequent Measure sessions show the CAShapeLayer crosshair but the hardware cursor is also visible (double cursor), OR the cursor stays hidden after the overlay dismisses
- `hideCount` is non-zero when `run()` starts

**Phase to address:** App shell / lifecycle foundation.

---

### Pitfall 9: SPM Package.swift Cannot Build an NSStatusItem App — Wrong Target Type

**What goes wrong:**
The existing `Package.swift` declares an `.executableTarget` with the Raycast Swift macros as dependencies. This compiles to a command-line executable that Raycast runs. A standalone menu bar app requires an `.app` bundle with:
- `Info.plist` (for entitlements, privacy usage descriptions, LSUIElement)
- `NSApplicationDelegate`
- `NSStatusItem` setup
- Code signing identity
- Notarization workflow

SPM `.executableTarget` produces a raw binary — no `.app` bundle, no Info.plist, no code signing. Trying to ship this as a menu bar app fails at every distribution step.

**How to avoid:**
The standalone app MUST be an Xcode project (`.xcodeproj`) or Xcode workspace, not an SPM-only build. The correct architecture is:
- Keep the existing SPM `Package.swift` for the Raycast extension (unchanged)
- Create a new `DesignRulerApp.xcodeproj` that:
  - Has an App target with proper bundle structure
  - Imports the shared Swift logic as either: (a) a local SPM package dependency, or (b) compiled shared source files
  - Manages Info.plist, entitlements, and code signing

Do NOT try to add the menu bar app as a second SPM target. SPM does not support `.app` bundles.

**Warning signs:**
- Attempting to `open` the SPM build output as a `.app` fails ("not a recognized app package")
- No code signing step in the build
- Gatekeeper rejects the binary on first launch

**Phase to address:** Build system setup — must be resolved before any standalone code is written.

---

### Pitfall 10: Code Signing Identity Mismatch Between SPM (Raycast) and Xcode App

**What goes wrong:**
The Raycast extension's Swift binary is signed by Raycast's build system using Raycast's code signing identity. The standalone `.app` must be signed by the developer's own Apple Developer certificate. If the standalone app imports or ships the Raycast-compiled binary, the signature is invalid. If the shared Swift source files are compiled separately for the Xcode target, they work correctly — but any confusion between the two binaries causes Gatekeeper to reject the app.

**Why it happens:**
SPM builds for Raycast use `RaycastSwiftMacros`, `RaycastSwiftPlugin`, and `RaycastTypeScriptPlugin` as dependencies (Package.swift lines 9-17). These are Raycast-specific and must NOT be compiled into the standalone app. The `@raycast` macro on `inspect()` and `alignmentGuides()` functions (Measure.swift line 4, AlignmentGuides.swift line 4) must not appear in the standalone target.

**How to avoid:**
1. The shared Swift source files (everything EXCEPT `Measure.swift` entry point and `AlignmentGuides.swift` entry point) can be compiled into both targets. The entry point files that use `@raycast` are excluded from the Xcode target.
2. The standalone app has its OWN entry points that call `Measure.shared.run(...)` and `AlignmentGuides.shared.run(...)` directly — no `@raycast` macro needed.
3. Do NOT add `RaycastSwiftMacros` as a dependency to the Xcode app target.
4. Validate signing with `codesign --verify --deep --strict` before notarization.

**Warning signs:**
- Xcode reports "undefined symbol: __RaycastSwiftMacros..." at link time
- App passes local testing but Gatekeeper rejects on another machine ("damaged and can't be opened")
- `codesign --verify` shows mixed signing identities in the app bundle

**Phase to address:** Build system setup (Pitfall 9 and 10 must be solved together in the same phase).

---

### Pitfall 11: Notarization Fails Due to Missing Entitlements for Screen Recording

**What goes wrong:**
A notarized macOS app that uses `CGWindowListCreateImage` or `ScreenCaptureKit` must declare `com.apple.security.temporary-exception.mach-lookup.global-name` or use the hardened runtime with the correct entitlements. Without `com.apple.security.screencapture` entitlement (or equivalent), notarization either rejects the binary or it passes notarization but the API returns nil at runtime because the hardened runtime sandbox blocks it.

**Why it happens:**
The hardened runtime (required for notarization since macOS 10.15) restricts process capabilities. `CGWindowListCreateImage` requires the Screen Recording TCC permission, which in a sandboxed app additionally requires the `com.apple.security.screen-capture` entitlement. Apps distributed outside the Mac App Store (DMG) use the hardened runtime but NOT the App Sandbox — this is the typical choice for developer tools.

**How to avoid:**
1. Do NOT enable App Sandbox for the standalone app (incompatible with `CGWindowListCreateImage` + global event taps).
2. DO enable Hardened Runtime (required for notarization).
3. Required entitlements for this app:
```xml
<!-- DesignRulerApp.entitlements -->
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<false/>
<!-- NO App Sandbox -->
<key>com.apple.security.cs.disable-library-validation</key>
<false/>
```
4. Screen Recording permission is user-granted at runtime via `CGRequestScreenCaptureAccess()` — this is a TCC permission, NOT an entitlement. No additional entitlement is needed beyond hardened runtime.
5. If using `CGEventTap` for global hotkeys: this also does NOT need a special entitlement — it needs the Accessibility TCC permission at runtime.
6. Validate entitlements pre-notarization: `codesign -d --entitlements - DesignRulerApp.app`

**Warning signs:**
- Notarization tool returns "The executable does not have the hardened runtime enabled"
- App passes notarization but `CGWindowListCreateImage` returns nil on a clean machine
- Apple's notarization log shows rejected entitlements

**Phase to address:** Distribution / notarization phase (after core functionality works).

---

### Pitfall 12: LSUIElement=YES in Info.plist Is Mandatory — Missing It Shows a Dock Icon

**What goes wrong:**
Without `LSUIElement = YES` in `Info.plist`, the app shows a Dock icon on launch and appears in the Cmd+Tab switcher, even if using `.accessory` activation policy. `NSApp.setActivationPolicy(.accessory)` only hides the Dock icon at runtime — the Dock icon flashes briefly on launch before the policy takes effect. For a menu bar utility that should be invisible in the Dock, the Info.plist key is essential.

**How to avoid:**
Add to Info.plist:
```xml
<key>LSUIElement</key>
<true/>
```
This hides the Dock icon from process launch, not just after `NSApplicationDelegate` runs. Combined with `.accessory` activation policy, the app is fully invisible in Dock and Cmd+Tab from the moment it launches.

**Warning signs:**
- Dock icon appears briefly on launch then disappears
- App shows up in Cmd+Tab switcher

**Phase to address:** App shell setup (Info.plist configuration).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Duplicate OverlayCoordinator with `#if STANDALONE` guards | Ship quickly | Two divergent code paths, bugs in one that don't appear in the other, maintenance burden grows with each feature | Only for a proof-of-concept prototype; never for shipped code |
| Skip Accessibility permission check for hotkeys | Simpler onboarding | Silent hotkey failure frustrates users; impossible to debug without clear permission UI | Never |
| Skip notarization, distribute un-notarized app | Faster first release | Gatekeeper blocks on Apple Silicon and modern macOS; most users cannot open the app | Never for public distribution |
| Hard-code global hotkey (e.g., Cmd+Shift+R) | No settings UI needed | Conflicts with other apps (Sketch, Figma use similar shortcuts) | Never — always user-configurable |
| Reuse same `@raycast` entry point files for standalone | Avoids duplication | RaycastSwiftMacros dependency leaks into the standalone build; link errors | Never |

---

## Integration Gotchas

Common mistakes when connecting the existing Raycast code to the standalone app target.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Shared Swift sources | Compile all files including `@raycast` annotated entry points | Exclude `Measure.swift` and `AlignmentGuides.swift` from Xcode target; create standalone-specific entry points |
| `OverlayCoordinator.handleExit()` | Call unchanged — exits the whole app | Refactor to `endSession()` that tears down windows without `NSApp.terminate` |
| `CursorManager.shared` singleton | Assume it resets between sessions automatically | Explicitly call `restore()` at the start of every new session |
| Inactivity timer (10 min) | Let it call `handleExit()` unchanged | Route timer to `endSession()` instead |
| SIGTERM handler | Install per-session from coordinator | Install once at app delegate level; coordinator does not manage signals |
| Screen recording permission | Call `requestScreenRecordingPermission()` and proceed | Check first; show actionable UI with System Settings link on denial |
| Accessibility permission | Not requested — assumes not needed | Request separately for hotkey registration; handle denial gracefully |

---

## Performance Traps

Patterns that work during development but degrade in persistent operation.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Not releasing window references after session | Memory grows ~50-100MB per session over time | Explicitly `nil` all window references in `endSession()` | After 5-10 sessions |
| Warmup CGWindowListCreateImage on every invocation (current behavior) | 100-200ms stall on every Measure launch | Move warmup to app startup, not per-session; subsequent captures are already warm | Every invocation |
| NSStatusItem menu building on main thread with complex layout | Menu bar icon click has visible delay | Build menu in background; use static NSMenu structure | With complex dynamic menus |
| CursorManager `hide()` guard fails silently for second session | Cursor stays visible during Measure mode | Reset CursorManager at session start (see Pitfall 8) | On second invocation |
| EventTap created but not destroyed between sessions | Keydown events received even when no overlay is active | Disable/destroy EventTap in `endSession()`, re-enable in next session start | Accumulates with each session |

---

## Security Mistakes

Domain-specific security issues for a macOS developer tool.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Shipping without notarization | Gatekeeper blocks all users on Apple Silicon + macOS 13+ | Notarize before any external distribution — no exceptions |
| Storing user preferences (hotkey config) in NSUserDefaults without app group | Raycast extension and standalone app cannot share preferences | Use `UserDefaults(suiteName:)` with a shared app group if preferences should sync; otherwise keep them separate |
| Requesting Accessibility permission at launch unconditionally | macOS privacy prompt appears before user understands why | Only request Accessibility when user first tries to configure a hotkey, with explanation |
| Using `CGEventTap` without proper cleanup | EventTap continues monitoring after session ends — privacy concern (logs keystrokes to the existing handler) | Always disable EventTap in `endSession()`; never leave a global key monitor running when overlays are not active |

---

## UX Pitfalls

Common UX mistakes specific to adding a persistent menu bar app to a tool designed for on-demand use.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No visual indicator that Measure/Guides is running from the status bar | Users activate, the overlay appears, but if dismissed they don't know how to re-invoke | Status bar icon changes state when overlay is active; tooltip explains keyboard shortcut |
| Permission request appears as an opaque system dialog with no context | Users click "Don't Allow" reflexively, then tools silently fail | Show an in-app explanation BEFORE triggering the system permission prompt |
| ESC quits the app (Pitfall 1 manifestation) | Users lose all open app state | ESC ends session, returns to menu bar; Cmd+Q quits the app |
| Hotkey conflicts with Figma/Sketch shortcuts on designer machines | Designer's primary tool becomes unreliable | Default to no hotkey; let users assign their own; validate for common conflicts |
| Launch at login enabled by default | App appears in startup without user consent — feels like malware | Launch at login is OFF by default; user explicitly enables from menu bar menu |

---

## "Looks Done But Isn't" Checklist

Things that appear complete in development but are missing critical pieces for production.

- [ ] **ESC handling:** ESC calls `endSession()` not `NSApp.terminate` — verify app stays in Dock/menu bar after pressing ESC
- [ ] **Second invocation:** Invoke Measure, press ESC, invoke Measure again — verify the second session works correctly with no cursor glitch
- [ ] **Permission denial:** Remove Screen Recording permission in System Settings, invoke Measure — verify a clear, actionable dialog appears (not a blank/black overlay)
- [ ] **Permission denial (Accessibility):** Remove Accessibility permission, trigger hotkey — verify graceful fallback with guidance, not silent failure
- [ ] **Notarization:** Run `spctl --assess --type execute DesignRulerApp.app` on a clean machine — verify Gatekeeper approves
- [ ] **Hardened runtime:** Run `codesign -d --entitlements - DesignRulerApp.app` — verify no unexpected entitlements and hardened runtime is enabled
- [ ] **Dock icon absent:** Launch app fresh — verify no Dock icon appears even momentarily (`LSUIElement = YES` is set)
- [ ] **Launch at login OFF by default:** Fresh install — verify app does not appear in Login Items
- [ ] **CursorManager reset:** Force-quit mid-session, relaunch, invoke Measure — verify cursor hides correctly (no ghost state from previous session)
- [ ] **Memory:** Run 20 Measure sessions in a row — verify memory is stable (Activity Monitor, no growth)
- [ ] **EventTap cleanup:** Register hotkey, invoke and dismiss Measure 5 times — verify no duplicate hotkey events (EventTap not accumulating)
- [ ] **App quit:** Cmd+Q while overlay is active — verify overlay dismisses cleanly and cursor is restored before process exits

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NSApp.terminate in persistent app (Pitfall 1/7) | LOW | Find all `NSApp.terminate` calls in coordinator, replace with `endSession()`; add mode flag |
| app.run() called per session (Pitfall 2) | LOW | Remove `app.run()` from coordinator in standalone build; guard with compile flag |
| Screen recording no UI on denial (Pitfall 3) | LOW | Add permission check + alert before each capture attempt |
| CursorManager state leak (Pitfall 8) | LOW | Add `CursorManager.shared.restore()` at start of `run()` |
| Wrong build system — SPM-only (Pitfall 9) | HIGH | Create Xcode project from scratch; configure shared sources manually; cannot avoid this work |
| Code signing mismatch (Pitfall 10) | MEDIUM | Identify which files use `@raycast`; exclude from Xcode target; create standalone entry points |
| Notarization failure (Pitfall 11) | MEDIUM | Check entitlements, enable hardened runtime, re-sign, re-submit; Apple's turnaround is 5-30 min |
| Missing LSUIElement (Pitfall 12) | LOW | Add key to Info.plist, rebuild — trivial fix but annoying if discovered after distribution |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NSApp.terminate quits persistent app (P1) | App shell / lifecycle | ESC during Measure keeps menu bar icon active |
| app.run() called per session (P2) | App shell / lifecycle | Second invocation shows overlay without hang |
| Permission denial has no UI (P3) | Permission handling | Deny permission, invoke Measure, see actionable dialog |
| Accessibility permission for hotkeys (P4) | Hotkey system | Global hotkey works from Figma context |
| setActivationPolicy repeated calls (P5) | App shell / lifecycle | No Dock icon flicker on invocation |
| SIGTERM handler conflicts (P6) | App shell / lifecycle | `kill <pid>` quits app cleanly |
| Inactivity timer quits app (P7) | App shell / lifecycle | Wait 10 min idle in Measure — overlay dismisses, app stays |
| CursorManager state leaks (P8) | App shell / lifecycle | Force-quit session, re-invoke — cursor behaves correctly |
| SPM cannot produce .app bundle (P9) | Build system setup | Xcode project builds and runs .app |
| Code signing identity mismatch (P10) | Build system setup | `codesign --verify --deep` passes on all targets |
| Notarization entitlements (P11) | Distribution | `spctl --assess` approves on clean machine |
| Missing LSUIElement (P12) | App shell setup | No Dock icon on fresh launch |

---

## Sources

- Direct analysis: `OverlayCoordinator.swift` — `handleExit()`, `app.run()`, `setupSignalHandler()`, `resetInactivityTimer()`
- Direct analysis: `CursorManager.swift` — singleton state machine, `hide()` guard on `.idle`
- Direct analysis: `PermissionChecker.swift` — `CGPreflightScreenCaptureAccess()`, `CGRequestScreenCaptureAccess()`
- Direct analysis: `Package.swift` — `.executableTarget` with Raycast-specific dependencies
- Direct analysis: `Measure.swift`, `AlignmentGuides.swift` — `@raycast` macro usage
- Apple Developer Documentation: `NSApplication.ActivationPolicy` — `.regular`, `.accessory`, `.prohibited`
- Apple Developer Documentation: `LSUIElement` Info.plist key — hides Dock icon from process launch
- Apple Developer Documentation: Notarizing macOS software — hardened runtime requirements
- Apple Developer Documentation: `SMAppService` — launch-at-login on macOS 13+
- Apple Developer Documentation: `AXIsProcessTrusted` — Accessibility permission for global event monitoring
- Apple Developer Documentation: `CGRequestScreenCaptureAccess` — TCC screen capture permission flow
- Known macOS behavior: `setActivationPolicy` side effects when called repeatedly at runtime
- Known macOS behavior: `NSCursor.hide()` is process-scoped — survives session boundaries in a persistent process

---
*Pitfalls research for: Adding standalone macOS menu bar app to Design Ruler Raycast extension*
*Researched: 2026-02-17*
