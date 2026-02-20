# Phase 22: Global Hotkeys - Research

**Researched:** 2026-02-19
**Domain:** macOS global keyboard shortcut registration, Carbon Event Manager, SwiftUI recorder UI
**Confidence:** HIGH

## Summary

Phase 22 adds configurable global keyboard shortcuts that trigger Measure and Alignment Guides overlays from any application. The locked decision is to use [KeyboardShortcuts 2.4.0](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, which uses Carbon's `RegisterEventHotKey` API (not CGEventTap as originally suspected). This is significant because it means the library does NOT require Accessibility permission -- Carbon hotkeys work without any extra entitlements, even in sandboxed apps.

The library provides a complete solution: `KeyboardShortcuts.Name` for defining shortcut identifiers, `KeyboardShortcuts.Recorder` (SwiftUI) for inline recording controls with built-in conflict detection, `KeyboardShortcuts.onKeyUp/onKeyDown` for handling events, automatic UserDefaults persistence, and `NSMenuItem.setShortcut(for:)` for displaying shortcuts in menus. The recorder automatically pauses hotkey monitoring while recording (`isPaused` flag), prevents system/menu conflicts with user-facing alerts, and requires at least one modifier key.

Critical architectural finding: Carbon `RegisterEventHotKey` **swallows the key event** before it reaches `NSWindow.keyDown`. This means global hotkeys will fire even while our fullscreen overlays are active, and the overlay will NOT see the same keystroke as a `keyDown` event. This is ideal for the toggle-off behavior (pressing the same hotkey to dismiss). The hotkey handler can call `handleExit()` directly without any conflict with the overlay's own key handling.

**Primary recommendation:** Add KeyboardShortcuts 2.4.0 as SPM dependency in project.yml, define two `KeyboardShortcuts.Name` values (measure, alignmentGuides), register `onKeyUp` handlers in AppDelegate, add `KeyboardShortcuts.Recorder` controls to SettingsView, and use `NSMenuItem.setShortcut(for:)` for menu bar display.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Inline recorder control (macOS System Settings style) -- text field-like, says "Record Shortcut" when unassigned, captures next key combo when clicked
- At least one modifier key required (Cmd, Ctrl, Option, Shift) -- prevents accidental triggers from bare keys
- Clear shortcut via X button next to recorder OR pressing Delete/Backspace while recorder is focused (both work)
- Remove the existing Shortcuts tab from Settings -- each shortcut recorder lives in its respective mode section (Measure shortcut in Measure section, Alignment Guides shortcut in Alignment Guides section)
- Internal conflicts (same shortcut for both commands): block with inline message "Already assigned to [other command]" and reject
- System shortcut conflicts (Cmd+Space, Cmd+Tab, etc.): warn with yellow warning "This may conflict with [system feature]" but allow user to proceed
- External app conflicts (registration failure): show a notice in Settings that the shortcut couldn't be registered
- Use KeyboardShortcuts 2.4.0 built-in conflict detection -- trust library defaults, no custom validation layer
- Same-command hotkey (e.g., Measure hotkey while Measure active): toggle off -- dismiss overlay instantly (same as ESC, no fade-out)
- Cross-command hotkey (e.g., Alignment Guides hotkey while Measure active): seamless switch reusing existing screen captures if technically feasible. Fallback if not: close current overlay, re-capture, open the other command (small delay acceptable)
- Menu bar dropdown: non-interactive during overlays (overlays capture all input)
- Hotkey toggle-off: instant dismiss, same behavior as ESC
- No first-launch nudge in this phase -- user discovers shortcuts in Settings (onboarding window deferred to separate phase)
- Recorder shows "Record Shortcut" placeholder text when unassigned
- Menu bar dropdown shows assigned hotkey next to each command (e.g., "Measure  Cmd+Shift+M") -- matches native macOS menu conventions
- When no shortcut assigned, dropdown just shows the command name without a shortcut hint

### Claude's Discretion
- Keycap rendering style for assigned shortcuts in Settings (styled caps vs plain text)
- Exact layout/spacing of recorder controls within mode sections
- How to surface the "couldn't register" notice (inline vs toast vs alert)

### Deferred Ideas (OUT OF SCOPE)
- First-launch onboarding window combining screen recording permission request + shortcut setup -- separate phase/effort
- Keycap-style shortcut rendering in settings (could be enhanced later)
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.4.0 | Global hotkey registration, recorder UI, UserDefaults persistence | De facto standard for macOS global shortcuts. Carbon-based, no Accessibility permission. Used by Dato, Jiffy, Plash, Lungo. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SwiftUI (built-in) | macOS 14+ | Recorder control integration in SettingsView | Already used for SettingsView |
| AppKit (built-in) | macOS 14+ | NSMenuItem shortcut display in menu bar | Already used for MenuBarController |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| KeyboardShortcuts | MASShortcut | Older, Objective-C, less maintained, similar Carbon approach |
| KeyboardShortcuts | CGEventTap manual | Lower level, requires Accessibility permission, complex lifecycle management |
| KeyboardShortcuts | NSEvent.addGlobalMonitorForEvents | Cannot intercept/swallow events, only observe -- not suitable for hotkeys |

**Installation (project.yml):**
```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.4.0"

targets:
  "Design Ruler":
    dependencies:
      - package: KeyboardShortcuts
```

**Note:** KeyboardShortcuts 2.4.0 uses `swift-tools-version: 6.1` but specifies `swiftLanguageMode: [.v5]`. The system has Swift 6.2.3, so this is fully compatible.

## Architecture Patterns

### Recommended File Changes
```
App/Sources/
  AppDelegate.swift          # Wire hotkey handlers + enable/disable lifecycle
  MenuBarController.swift    # NSMenuItem.setShortcut(for:) for dropdown display
  SettingsView.swift         # Replace Shortcuts placeholder with recorder controls
  HotkeyNames.swift          # NEW: KeyboardShortcuts.Name extensions
  HotkeyController.swift     # NEW: Centralized hotkey registration + session-aware dispatch
```

### Pattern 1: Shortcut Name Definition
**What:** Define strongly-typed shortcut identifiers as static Name extensions
**When to use:** Once, in a shared file imported by both Settings and hotkey handler

```swift
// HotkeyNames.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let measure = Self("measure")
    static let alignmentGuides = Self("alignmentGuides")
}
```

No default shortcuts -- both start unassigned per requirements.

### Pattern 2: Global Hotkey Handler Registration
**What:** Register `onKeyUp` handlers that dispatch to the overlay coordinators
**When to use:** In AppDelegate.applicationDidFinishLaunching, after coordinator setup

```swift
// In AppDelegate or HotkeyController
KeyboardShortcuts.onKeyUp(for: .measure) { [weak self] in
    self?.handleHotkey(command: .measure)
}
KeyboardShortcuts.onKeyUp(for: .alignmentGuides) { [weak self] in
    self?.handleHotkey(command: .alignmentGuides)
}
```

**Why `onKeyUp` not `onKeyDown`:** Prevents repeated triggering from key-repeat if user holds the shortcut. `onKeyUp` fires once per press.

### Pattern 3: Session-Aware Hotkey Dispatch (Toggle + Cross-Switch)
**What:** Centralized handler that checks overlay state before dispatching
**When to use:** Every hotkey event goes through this dispatcher

```swift
func handleHotkey(command: Command) {
    if command == currentActiveCommand {
        // Same command: toggle off (instant dismiss)
        activeCoordinator?.handleExit()
    } else if OverlayCoordinator.anySessionActive {
        // Different command: cross-switch
        activeCoordinator?.handleExit()
        // After exit completes, launch other command
        launchCommand(command)
    } else {
        // No overlay active: normal launch
        menuBarController.setActive(true)
        launchCommand(command)
    }
}
```

### Pattern 4: NSMenuItem Shortcut Display
**What:** Connect keyboard shortcuts to menu items for right-aligned display
**When to use:** During menu setup in MenuBarController

```swift
// In MenuBarController.setupMenu()
measureItem.setShortcut(for: .measure)
guidesItem.setShortcut(for: .alignmentGuides)
```

This automatically: (a) shows the shortcut symbols right-aligned in the dropdown, (b) updates dynamically when the user changes shortcuts in Settings, (c) shows nothing when unassigned.

### Pattern 5: Inline Recorder in SettingsView
**What:** KeyboardShortcuts.Recorder in each command's settings section
**When to use:** In SettingsView, replacing the Shortcuts placeholder section

```swift
// In SettingsView
Section("Measure") {
    Picker("Border Corrections", selection: $corrections) { ... }
    KeyboardShortcuts.Recorder("Shortcut:", name: .measure)
}

Section("Alignment Guides") {
    KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides)
}
```

The Recorder handles everything: recording state, modifier validation, system conflict warnings, UserDefaults persistence, and clear button.

### Pattern 6: Internal Conflict Detection
**What:** Prevent assigning the same shortcut to both commands
**When to use:** Via onChange callback on each Recorder

The library's built-in conflict detection handles system shortcuts and main menu conflicts. For internal conflicts (same shortcut assigned to both commands), use the `onChange` callback to compare against the other command's shortcut:

```swift
KeyboardShortcuts.Recorder("Shortcut:", name: .measure) { newShortcut in
    if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: .alignmentGuides) {
        // Block: show inline warning "Already assigned to Alignment Guides"
        KeyboardShortcuts.setShortcut(nil, for: .measure)
    }
}
```

### Anti-Patterns to Avoid
- **Custom Carbon event handling:** Do NOT manually call `RegisterEventHotKey`. KeyboardShortcuts wraps this cleanly.
- **CGEventTap for hotkeys:** The research flag mentioned CGEventTap session cleanup, but KeyboardShortcuts uses Carbon Event Manager, not CGEventTap. No CGEventTap involvement at all.
- **NSEvent.addGlobalMonitorForEvents for hotkeys:** This only observes events, does not intercept/swallow them. The hotkey would also reach the frontmost app.
- **Default shortcut values:** Do NOT set default shortcuts. Users find it annoying when apps steal existing shortcuts (library author's explicit guidance).
- **Disabling shortcuts during overlays:** Do NOT call `KeyboardShortcuts.disable()` while overlays are active. We WANT hotkeys to fire during overlays for toggle-off and cross-switch behavior.
- **isPaused manipulation:** Do NOT set `KeyboardShortcuts.isPaused` manually. The library manages this automatically when the recorder is active.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Global shortcut registration | Custom Carbon RegisterEventHotKey wrapper | KeyboardShortcuts library | Handles Carbon lifecycle, modifier normalization, menu tracking mode, sandbox compat |
| Shortcut recorder UI | Custom NSSearchField with key event monitor | KeyboardShortcuts.Recorder | Built-in conflict detection, modifier validation, clear button, localization |
| UserDefaults persistence | Manual encode/decode of shortcut data | Library's automatic persistence | Uses `KeyboardShortcuts_` prefixed keys, JSON encoding, handles migration |
| Menu item shortcut display | Manual keyEquivalent + modifierMask setting | NSMenuItem.setShortcut(for:) | Auto-updates when user changes shortcut, handles nil (unassigned) |
| System conflict detection | Custom check against system keyboard shortcuts | Library's built-in isTakenBySystem | Queries Carbon APIs for system hotkeys, shows user-friendly alert |
| Modifier key validation | Custom event filtering for bare keys | Library's built-in validation | Rejects shift-only, beeps on invalid, requires real modifier(s) |

**Key insight:** KeyboardShortcuts 2.4.0 handles every aspect of the hotkey lifecycle that we need. The only custom code is: (1) the session-aware dispatch logic (toggle-off, cross-switch), (2) internal conflict detection between our two commands, and (3) registration failure notices.

## Common Pitfalls

### Pitfall 1: Menu Tracking Mode Blocks Hotkeys
**What goes wrong:** When NSMenu is open (user clicked menu bar icon), keyboard events enter NSMenu's tracking mode. Global hotkeys registered via Carbon are delivered but in a special queue.
**Why it happens:** NSMenu takes over the event loop during tracking.
**How to avoid:** KeyboardShortcuts 2.4.0 handles this internally (PR #122, merged Feb 2023). It uses `softUnregisterAll()` when menus open and re-registers when they close. No action needed from our code.
**Warning signs:** Hotkeys not firing while menu bar dropdown is visible (would indicate library not handling this).

### Pitfall 2: Hotkey Events During Overlay Conflict with keyDown
**What goes wrong:** Developer assumes global hotkey and NSWindow.keyDown both fire for the same keystroke.
**Why it happens:** Misunderstanding of event dispatch order.
**How to avoid:** Carbon `RegisterEventHotKey` **swallows the event** before it reaches NSApplication dispatch. The overlay's `keyDown` will NOT see the hotkey keystroke. This is correct behavior -- the hotkey handler fires, not the overlay.
**Warning signs:** If both handlers fire, something is wrong with the registration.

### Pitfall 3: Cross-Command Switch Race Condition
**What goes wrong:** Pressing Alignment Guides hotkey while Measure is active: `handleExit()` clears `anySessionActive`, but the new `run()` call may happen before cleanup completes.
**Why it happens:** `handleExit()` sets `isSessionActive = false` synchronously (first line), but window cleanup (orderOut, cursor restore) runs in the same call.
**How to avoid:** The current `handleExit()` design sets the flags synchronously at the top, which explicitly enables "instant re-invocation." However, for cross-command switching, use `DispatchQueue.main.async` for the new command launch to allow the current exit's autorelease pool to drain. The fallback approach (close + re-capture + open) is simpler and more reliable than trying to reuse captures.
**Warning signs:** Stale windows from old session visible behind new session, or `anySessionActive` guard rejecting the new launch.

### Pitfall 4: Capture Reuse Not Feasible for Cross-Switch
**What goes wrong:** Developer tries to pass CGImage captures from one coordinator to another for "seamless" cross-command switching.
**Why it happens:** The context decision says "reuse existing screen captures if technically feasible."
**How to avoid:** Capture reuse is NOT technically feasible. MeasureCoordinator creates `EdgeDetector` instances that wrap captures into `ColorMap` pixel buffers. AlignmentGuidesCoordinator only needs `CGImage` backgrounds. These are different types built during `captureAllScreens()`. The coordinator's `createWindow()` factory takes `CGImage?` but MeasureCoordinator needs the EdgeDetector from the capture phase. More fundamentally, the overlays are already showing a frozen screenshot -- re-capturing will capture those same frozen pixels (identical result). **The fallback is actually the correct approach:** close current overlay, re-capture (fast -- screens are static), open the other command. The delay is imperceptible because: (1) handleExit is instant (orderOut, no fade), (2) re-capture captures the same static image (fast path), (3) new windows appear immediately.
**Warning signs:** Trying to share state between coordinator subclasses or bypass the `captureAllScreens()` override pattern.

### Pitfall 5: Shortcut Storage Key Collision
**What goes wrong:** KeyboardShortcuts stores under `KeyboardShortcuts_measure` and `KeyboardShortcuts_alignmentGuides` in UserDefaults. If the app also uses those key prefixes for other purposes, collision occurs.
**Why it happens:** The library uses a hardcoded prefix.
**How to avoid:** Our existing UserDefaults keys (`hideHintBar`, `corrections`, `hasLaunchedBefore`) have no prefix collision. The `.` restriction in Name rawValues is enforced by the library with a runtime warning. Use simple camelCase names.
**Warning signs:** Name validation warnings in console.

### Pitfall 6: macOS 15.0-15.1 Option-Only Shortcuts
**What goes wrong:** Users on macOS 15.0-15.1 find that Option-only or Option+Shift-only shortcuts don't work.
**Why it happens:** Apple temporarily restricted these modifiers in macOS 15.0 to combat keylogger malware. Fixed in macOS 15.2.
**How to avoid:** Our app is not sandboxed (documented decision), and the issue was fixed in macOS 15.2. The recorder's `isTakenBySystem` check may warn about Option-only shortcuts on affected versions. No action needed -- just awareness.
**Warning signs:** User reports of specific modifier combinations not working on Sequoia 15.0/15.1.

### Pitfall 7: Registration Failure Goes Unnoticed
**What goes wrong:** Another app already holds the same global hotkey. KeyboardShortcuts silently fails to register.
**Why it happens:** Carbon's `RegisterEventHotKey` succeeds but the event tap doesn't fire because another app has priority.
**How to avoid:** The user decision says to show a notice in Settings for registration failures. The library's `enable()` method can be checked via `isEnabled(for:)`. After recording a shortcut, verify registration succeeded. If not, show inline notice.
**Warning signs:** User assigns a shortcut, sees it saved, but pressing it does nothing.

## Code Examples

Verified patterns from official sources:

### Define Shortcut Names (No Defaults)
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts README
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let measure = Self("measure")
    static let alignmentGuides = Self("alignmentGuides")
}
```

### Register Global Handlers
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts README
KeyboardShortcuts.onKeyUp(for: .measure) { [weak self] in
    self?.handleMeasureHotkey()
}

KeyboardShortcuts.onKeyUp(for: .alignmentGuides) { [weak self] in
    self?.handleAlignmentGuidesHotkey()
}
```

### SwiftUI Recorder Control
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts README
KeyboardShortcuts.Recorder("Shortcut:", name: .measure)
```

The recorder automatically:
- Shows "Record Shortcut" placeholder when unassigned
- Captures next valid key combo on click
- Requires at least one modifier (Cmd, Ctrl, Option, Shift)
- Shows X button to clear when assigned
- Clears on Delete/Backspace press while focused
- Warns about system conflicts (modal dialog)
- Warns about app menu conflicts (modal dialog)
- Pauses all global hotkeys while recording (isPaused)
- Persists to UserDefaults automatically

### NSMenuItem Shortcut Display
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts NSMenuItem++.swift
let measureItem = menu.addItem(withTitle: "Measure", action: #selector(launchMeasure), keyEquivalent: "")
measureItem.setShortcut(for: .measure)  // Shows shortcut or nothing if unassigned
```

### Check If Shortcut Exists
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts KeyboardShortcuts.swift
if let shortcut = KeyboardShortcuts.getShortcut(for: .measure) {
    // Shortcut is assigned
}
```

### Disable/Enable Specific Shortcuts
```swift
// Source: https://github.com/sindresorhus/KeyboardShortcuts KeyboardShortcuts.swift
KeyboardShortcuts.disable(.measure)  // Unregisters Carbon hotkey
KeyboardShortcuts.enable(.measure)   // Re-registers Carbon hotkey
```

### Internal Conflict Check
```swift
// Custom code (not from library -- library handles system/menu conflicts only)
KeyboardShortcuts.Recorder("Shortcut:", name: .measure) { newShortcut in
    if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: .alignmentGuides) {
        KeyboardShortcuts.setShortcut(nil, for: .measure)
        // Show inline warning: "Already assigned to Alignment Guides"
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CGEventTap for global hotkeys | Carbon RegisterEventHotKey (via KeyboardShortcuts) | Always -- Carbon predates CGEventTap | No Accessibility permission needed |
| Manual NSSearchField recorder | KeyboardShortcuts.Recorder (SwiftUI) | Library v1.0+ | Built-in validation, conflict detection |
| NSEvent.addGlobalMonitor | Carbon via KeyboardShortcuts | N/A -- different purpose | Global monitor can't swallow events |
| MASShortcut (ObjC) | KeyboardShortcuts (Swift) | ~2020 | Modern Swift API, active maintenance |

**Deprecated/outdated:**
- CGEventTap research flag: The STATE.md flag "Phase 22: CGEventTap session cleanup -- verify disable/re-enable pattern between sessions" is **not applicable**. KeyboardShortcuts uses Carbon Event Manager (`RegisterEventHotKey` + `InstallEventHandler`), not CGEventTap. The library handles its own registration lifecycle via `register()`/`unregister()` and `softRegisterAll()`/`softUnregisterAll()` for menu tracking.

## Open Questions

1. **Cross-command switch timing**
   - What we know: `handleExit()` sets `isSessionActive = false` synchronously, enabling immediate re-invocation. Window cleanup (orderOut) also runs synchronously.
   - What's unclear: Whether a `DispatchQueue.main.async` delay is needed between exit and re-launch to allow autorelease pool drainage, or if synchronous dispatch works reliably.
   - Recommendation: Start with `DispatchQueue.main.async` for safety. If the delay is imperceptible (expected), keep it. If noticeable, try synchronous and test for stability.

2. **Registration failure detection**
   - What we know: `KeyboardShortcuts.isEnabled(for:)` can check if a shortcut is active. The library's `register()` calls `RegisterEventHotKey` which returns an `OSStatus`.
   - What's unclear: Whether the library exposes registration failure to callers, or silently succeeds. The `isEnabled` check may only reflect the disable/enable flag, not actual Carbon registration status.
   - Recommendation: Test empirically by assigning a shortcut already held by another app (e.g., Spotlight's Cmd+Space). Check if `isEnabled` returns true but the shortcut doesn't fire. If detection isn't reliable, the "couldn't register" notice may need to be deferred or simplified to documentation guidance.

3. **Recorder control internal conflict UI**
   - What we know: The library handles system and menu conflicts with modal dialogs. It does NOT handle internal conflicts (two names with the same shortcut).
   - What's unclear: The exact SwiftUI pattern for showing inline warning text below a Recorder when an internal conflict is detected.
   - Recommendation: Use SwiftUI `@State` flag + conditional `Text` view below the Recorder. The `onChange` callback sets the flag; clearing or changing the shortcut clears it.

## Architectural Analysis: Cross-Command Switching

The user's preferred UX is "seamless switch reusing existing screen captures if technically feasible." After analyzing the architecture:

**Technical Assessment: NOT feasible to reuse captures. Fallback approach is correct.**

Reasons:
1. **Different capture types:** MeasureCoordinator creates `EdgeDetector` per screen during `captureAllScreens()`, which wraps CGImage into ColorMap pixel buffers. AlignmentGuidesCoordinator only uses raw `CGImage`. These are incompatible.
2. **Coordinator isolation:** Each coordinator owns its window array, stale window cleanup, and callback wiring. Transferring windows between coordinators would require a shared window pool that neither coordinator currently supports.
3. **Captures are trivially fast:** When the overlay is visible (fullscreen static screenshots), re-capturing produces the identical image because CGWindowListCreateImage captures what's on screen (which is our frozen overlay). The re-capture adds <50ms.
4. **Simple fallback works:** `handleExit()` (instant) + `DispatchQueue.main.async { launchOtherCommand() }`. Total perceived delay: one frame (~16ms of async dispatch + ~50ms capture). Indistinguishable from instantaneous.

**Recommended implementation:**
```swift
// Cross-command switch in HotkeyController
func handleHotkey(command: Command) {
    let currentCommand = activeCommand()
    if command == currentCommand {
        // Toggle off
        coordinatorFor(currentCommand).handleExit()
    } else if let current = currentCommand {
        // Cross-switch: close current, then launch other
        coordinatorFor(current).handleExit()
        DispatchQueue.main.async {
            self.menuBarController.setActive(true)
            self.launchCommand(command)
        }
    } else {
        // Normal launch
        menuBarController.setActive(true)
        launchCommand(command)
    }
}
```

## Claude's Discretion Recommendations

### Keycap rendering style for assigned shortcuts in Settings
**Recommendation:** Use plain text. The `KeyboardShortcuts.Recorder` already renders the assigned shortcut in its standard NSSearchField style, which matches macOS System Settings conventions. Adding styled keycaps would require custom rendering on top of the library's built-in display, adding complexity for minimal visual benefit. This is also explicitly deferred in the user's deferred ideas.

### Exact layout/spacing of recorder controls within mode sections
**Recommendation:** Place the `KeyboardShortcuts.Recorder` as the last item in each section, below existing controls. Use the library's built-in label support (`"Shortcut:"` label parameter). This matches the existing Form layout patterns in SettingsView (each setting is a row in its section).

```swift
Section("Measure") {
    Picker("Border Corrections", selection: $corrections) { ... }
    KeyboardShortcuts.Recorder("Shortcut:", name: .measure)
}

Section("Alignment Guides") {
    KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides)
}
```

### How to surface the "couldn't register" notice
**Recommendation:** Inline text below the recorder, styled as `.foregroundStyle(.orange)` with `.font(.caption)`. This is consistent with the internal conflict warning pattern and doesn't require a modal or toast infrastructure. Example: "This shortcut may not work if another app is using it."

Given the uncertainty about whether registration failures are reliably detectable (Open Question #2), a simpler approach may be warranted: skip the automatic detection notice entirely for this phase, and instead rely on the library's built-in system conflict warning (which catches the most common cases like Cmd+Space, Cmd+Tab). If a user assigns a shortcut held by a third-party app and it doesn't fire, there's no great way to detect that programmatically anyway.

## Sources

### Primary (HIGH confidence)
- [KeyboardShortcuts GitHub README](https://github.com/sindresorhus/KeyboardShortcuts) - API overview, usage patterns, installation
- [KeyboardShortcuts.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/KeyboardShortcuts.swift) - disable/enable/isPaused implementation, onKeyUp/onKeyDown signatures
- [CarbonKeyboardShortcuts.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/CarbonKeyboardShortcuts.swift) - Carbon RegisterEventHotKey usage confirmed (NOT CGEventTap)
- [RecorderCocoa.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/RecorderCocoa.swift) - Recorder behavior, conflict detection, modifier validation, clear/delete
- [NSMenuItem++.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/NSMenuItem%2B%2B.swift) - Menu item shortcut display and observation
- [Name.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/Name.swift) - Name struct, default shortcut support, UserDefaults key naming
- [Shortcut.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/Shortcut.swift) - isTakenBySystem, takenByMainMenu, modifier handling
- [ViewModifiers.swift source](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Sources/KeyboardShortcuts/ViewModifiers.swift) - SwiftUI onGlobalKeyboardShortcut modifier
- [Package.swift at 2.4.0](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/Package.swift) - swift-tools-version 6.1, macOS 10.15+, swiftLanguageMode v5
- Codebase: OverlayCoordinator.swift, MeasureCoordinator.swift, AlignmentGuidesCoordinator.swift, OverlayWindow.swift, MenuBarController.swift, SettingsView.swift, AppDelegate.swift, project.yml

### Secondary (MEDIUM confidence)
- [Issue #20: Disable/re-enable shortcuts](https://github.com/sindresorhus/KeyboardShortcuts/issues/20) - Confirmed auto-pause during recording (PR #25)
- [Issue #1: NSMenu support](https://github.com/sindresorhus/KeyboardShortcuts/issues/1) - Confirmed menu tracking mode handling (PR #122)
- [macOS 15 Option key issue](https://github.com/feedback-assistant/reports/issues/552) - Fixed in macOS 15.2
- [CocoaDev RegisterEventHotKey](https://cocoadev.github.io/RegisterEventHotKey/) - Confirms Carbon hotkeys swallow events before NSApplication dispatch

### Tertiary (LOW confidence)
- Carbon hotkey event swallowing behavior: verified via CocoaDev community documentation, but no official Apple documentation explicitly states this. Empirical testing recommended during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - KeyboardShortcuts 2.4.0 verified via GitHub source code, API confirmed
- Architecture: HIGH - Overlay lifecycle well-understood from codebase, integration points clear
- Pitfalls: HIGH for library pitfalls (verified from source), MEDIUM for cross-command switch timing (needs empirical validation)
- Cross-command switching: HIGH - Architecture analysis conclusive (capture reuse not feasible, fallback is the right approach)

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable library, unlikely to change)

**CGEventTap research flag resolution:** The STATE.md flag "Phase 22: CGEventTap session cleanup -- verify disable/re-enable pattern between sessions" has been RESOLVED. KeyboardShortcuts uses Carbon Event Manager, not CGEventTap. The library manages its own Carbon hotkey lifecycle. No CGEventTap cleanup is needed.
