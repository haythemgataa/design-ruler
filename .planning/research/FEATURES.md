# Feature Landscape: Standalone macOS Menu Bar App

**Domain:** macOS menu bar utility with global keyboard shortcuts and settings window
**Researched:** 2026-02-17
**Milestone context:** Adding standalone macOS app distribution alongside existing Raycast extension
**Confidence:** MEDIUM — training knowledge (August 2025 cutoff); WebSearch unavailable for this session

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that define a "real" macOS menu bar app. Missing = product feels half-baked.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Menu bar icon (NSStatusItem) | The entire delivery mechanism — without it, the app is invisible. Every menu bar app on macOS has one. | LOW | `NSStatusBar.system.statusItem(withLength:)`. Template image (black/white) auto-adapts to light/dark mode and active state. Size: 18×18pt logical, 36×36px @2x. |
| Dropdown menu with both commands | Users click the icon expecting to see what the app does. A blank or single-item menu frustrates. | LOW | `NSMenu` with two `NSMenuItem`s: "Measure" and "Alignment Guides". Keyboard shortcut displayed inline (right side of menu item). Separator + "Settings..." + "Quit". |
| Global keyboard shortcuts | Without hotkeys, users must click the menu bar icon every time — friction kills utility apps. This is the primary trigger mechanism. | MEDIUM | Carbon `RegisterEventHotKey` or `CGEventTap`. MASShortcut library (MIT) is the established AppKit approach. Raycast-assigned hotkeys don't carry over to standalone; user must configure. |
| Settings window with hotkey binding | Users need to assign their own shortcuts. No UI = no way to configure. | MEDIUM | Standard `NSWindow` opened via "Settings..." menu item. `Cmd+,` is the macOS convention for opening preferences. |
| Configuring existing preferences | `hideHintBar` and `corrections` already exist in Raycast; standalone must expose them too. | LOW | Add to settings window. Persist via `UserDefaults`. Same behavior as Raycast prefs. |
| Graceful missing-permission UX | Screen recording permission is required. If denied, overlay silently fails. | LOW | Permission check already implemented (`PermissionChecker.swift`). Surface the error with a dialog pointing to System Settings instead of silently doing nothing. |
| Quit menu item | Users expect "Quit Design Ruler" or just "Quit" at the bottom of every menu bar app's menu. | LOW | `NSMenuItem` with `NSApp.terminate`. |
| App does NOT appear in Dock or Cmd-Tab | Menu bar utility apps use `.accessory` or `.prohibited` activation policy — no Dock icon. Users would be confused by a Dock icon for a tool that runs in the menu bar. | LOW | `NSApp.setActivationPolicy(.accessory)` at launch. Remove `NSPrincipalClass` from Info.plist if using the agent pattern. Already used in `OverlayCoordinator.run()` — must apply on app launch, not just during overlay activation. |
| Persistent between uses | App stays running in menu bar after each command invocation (unlike the Raycast pattern where the process exits). | MEDIUM | The current `OverlayCoordinator` + `app.run()` loop exits after ESC. Standalone must NOT exit — must return to idle menu bar presence after overlay dismisses. This is an architectural change to the lifecycle. |

### Differentiators (Competitive Advantage)

Features that make this standalone app worth using instead of always going through Raycast.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Configurable global hotkeys | Users pick their own shortcuts (e.g., Ctrl+Shift+M). This is what standalone gives you over Raycast. | MEDIUM | Hotkey recorder UI (text field that captures keystrokes) + conflict detection. MASShortcut or Sauce (newer) handle the recorder pattern. Store in UserDefaults. |
| Coexistence nudge (detect Raycast extension installed) | If both are active, user may trigger commands from two places and see conflicts. A clear one-time nudge reduces confusion without being preachy. | LOW | At launch, check if Raycast.app is running AND extension is installed via file existence at `~/Library/Application Support/com.raycast.macos/extensions/` path. Show an informational alert once (not on every launch). |
| Launch at Login | Expected by power users who rely on the tool daily. Not having it requires manual intervention. | LOW | `SMAppService.mainApp.register()` (macOS 13+). Checkbox in settings window. Replaces the deprecated `SMLoginItemSetEnabled` pattern. |
| App icon in menu bar reflects state | During active overlay, icon changes to filled/highlighted version. Communicates tool is "in use". | LOW | `statusItem.button?.image` swap when overlay is running vs. idle. Standard pattern in recording apps (e.g., CleanMyMac, Codeshot). |
| Hotkey conflict detection with system shortcuts | If user tries to assign Cmd+Space (Spotlight) or another reserved shortcut, warn them instead of silently failing. | MEDIUM | Carbon APIs report registration failure when a hotkey is in use. Surface the conflict by name if possible. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Auto-detect "best" default hotkeys | Users want zero configuration on first run. | There are NO safe default global hotkeys. Any hardcoded default WILL conflict with something on some machine (Raycast, Alfred, 1Password, Window managers). Silently failing hotkey registration with no feedback is worse than no default. | Ship with NO default hotkeys. Prompt user on first launch to set them. Make the flow frictionless, not invisible. |
| Background dock icon during overlay | Seems helpful (shows the app is running). | `.statusBar` activation policy already brings the app forward correctly. Adding Dock presence confuses users who expect menu bar apps to be invisible in Dock. macOS norms: menu bar only OR Dock+menubar, not hybrid during overlay. | Keep activation policy `.accessory` throughout. The overlay itself is the full-screen UX. |
| Automatic sync of settings between Raycast extension and standalone | Convenient if you use both. | Raycast extensions store preferences in their own sandboxed container with no public read API. Cross-reading another app's sandbox is blocked by macOS security. Implementing sync requires a shared App Group container, which adds complexity for minimal value when the nudge already recommends choosing one. | Show the coexistence nudge. Let users migrate manually. Keep settings namespaces separate. |
| Menubar icon with badge/count | Some apps show measurement counts or guide counts in the icon badge. | NSStatusItem badges are NOT supported by AppKit (unlike Dock icons). Custom badge rendering on the status item button is fragile and looks unprofessional. | Position pill and W×H measurement are already displayed in the overlay itself. No badge needed. |
| System tray "live preview" on icon hover | Show last measurement or guide count in a tooltip on icon hover. | `NSStatusItem` tooltip is supported but purely text. A live preview would require a `NSPopover` triggered by hover — adding a hover state machine that must not conflict with click-to-open-menu. | Tooltip with app name only (or none). The measurement information is in the overlay. |
| Auto-dismiss after copy to clipboard | "Copy W×H value to clipboard on ESC" is often requested. | Scope creep. This is a Raycast extension feature (Raycast handles clipboard history). The standalone overlay already has the W×H pill visible. Clipboard copy belongs in the Raycast extension or as a v2+ feature. | ESC exits cleanly. No clipboard side effects in v1. |
| Multiple shortcut profiles | Power users want context-aware shortcuts (work vs. home). | Complex UI for marginal benefit. Adds a profile management layer to a simple settings window. | Single hotkey pair per command. If demand emerges, add in v2+. |

---

## Feature Dependencies

```
NSStatusItem (menu bar presence)
    └──required by──> Dropdown Menu
                          └──required by──> Settings... menu item
                                                └──required by──> Settings Window
                                                                      └──required by──> Hotkey Configuration
                                                                      └──required by──> Launch at Login Toggle
                                                                      └──required by──> hideHintBar pref
                                                                      └──required by──> corrections pref

Global Hotkey Registration
    └──depends on──> Hotkey Configuration (knows WHAT to register)
    └──depends on──> Persistent App Lifecycle (app must be running when hotkey fires)

Persistent App Lifecycle (overlay exits but app stays running)
    └──required by──> Global Hotkey Registration
    └──required by──> Menu Bar Presence (stays in menu bar after overlay closes)
    └──CONFLICT WITH──> Current OverlayCoordinator lifecycle (exits app on ESC)

Launch at Login
    └──independent of all above──> SMAppService (OS-level API)
    └──UI depends on──> Settings Window

Coexistence Detection
    └──depends on──> App startup sequence
    └──independent of──> All overlay features
```

### Dependency Notes

- **Persistent App Lifecycle conflicts with current OverlayCoordinator**: The existing `app.run()` call in `OverlayCoordinator.run()` combined with ESC calling exit/terminate is designed for the Raycast one-shot model. For the standalone app, the lifecycle must be inverted: the app runs continuously; the overlay is a modal session that starts and ends while the app persists. This is the highest-complexity architectural change.

- **Global Hotkey Registration requires Persistent App Lifecycle**: A `CGEventTap` or `RegisterEventHotKey` callback can only fire if the app process is running. The app must stay alive in the background at all times.

- **Hotkey Configuration requires Settings Window**: There is no standard macOS mechanism for configuring global hotkeys other than a dedicated UI. The hotkey recorder (a text field that captures keystrokes) is the established UX pattern used by every major utility app.

- **Coexistence Detection is independent**: It reads the filesystem, not any overlay state. It runs once at startup and shows a one-time informational nudge.

---

## MVP Definition

### Launch With (v1)

Minimum viable standalone app.

- [ ] **NSStatusItem menu bar icon** — app is inaccessible without it
- [ ] **Dropdown menu** — "Measure", "Alignment Guides", separator, "Settings...", "Quit"
- [ ] **Persistent app lifecycle** — overlay exits, app stays running in menu bar
- [ ] **Global hotkey registration** — the primary trigger mechanism; without this, standalone offers no advantage over Raycast
- [ ] **Hotkey configuration UI in settings** — no default hotkeys; user must assign; recorder pattern
- [ ] **Settings window** — exposes `hideHintBar`, `corrections`, hotkey bindings, launch-at-login
- [ ] **Launch at Login** — SMAppService; checkbox in settings
- [ ] **Screen recording permission UX** — surface error if missing, direct to System Settings
- [ ] **Coexistence nudge** — one-time informational alert if Raycast extension is detected

### Add After Validation (v1.x)

- [ ] **Menu bar icon state change during overlay** — visual polish; low effort; add when v1 is stable
- [ ] **Hotkey conflict detection with system shortcuts** — UX improvement; currently hidden error

### Future Consideration (v2+)

- [ ] **Clipboard copy on ESC** — feature request, not core utility
- [ ] **Multiple hotkey profiles** — power user edge case
- [ ] **Native Liquid Glass settings window** — visual polish, macOS 26+ only

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| NSStatusItem + dropdown menu | HIGH | LOW | P1 |
| Persistent app lifecycle (architectural) | HIGH | HIGH | P1 |
| Global hotkey registration | HIGH | MEDIUM | P1 |
| Settings window | HIGH | MEDIUM | P1 |
| Hotkey configuration UI (recorder) | HIGH | MEDIUM | P1 |
| Launch at Login | HIGH | LOW | P1 |
| hideHintBar + corrections in settings | MEDIUM | LOW | P1 |
| Screen recording permission UX | MEDIUM | LOW | P1 |
| Coexistence nudge | MEDIUM | LOW | P1 |
| Icon state change during overlay | LOW | LOW | P2 |
| Hotkey conflict detection | MEDIUM | MEDIUM | P2 |
| Clipboard copy on ESC | LOW | LOW | P3 |

---

## Expected UX Patterns for Each Feature Area

These are behavioral expectations users have based on macOS conventions. Deviating from them causes friction.

### Menu Bar Presence

**Expected behavior:**
- Single icon, no text label (text wastes menu bar space)
- Template image only (NSImage with `isTemplate = true`) — system applies correct tinting for active/inactive/dark mode
- Click opens dropdown menu (not a popover); this is the simplest pattern
- Menu stays open until user clicks away or selects item
- Icon does not animate except during active overlay (optional)

**What breaks expectations:**
- Non-template image that looks wrong in dark mode
- Menu that opens a popover instead of a dropdown (unexpected for utility apps)
- Icon that disappears from menu bar after some time

### Global Hotkey Registration

**Expected behavior:**
- Hotkey fires from ANY application context (global, not just when app is focused)
- If hotkey is already taken, registration silently fails at the OS level (Carbon) — must surface this to user
- Standard modifier key combinations: Ctrl+Shift+letter, Ctrl+Cmd+letter, Hyper (Ctrl+Opt+Cmd+Shift) are common choices for developer tools
- No modifier key conflicts with Cmd+single letter (those are app-scoped shortcuts)

**Implementation approaches (confidence: MEDIUM from training):**
1. **Carbon `RegisterEventHotKey`** — the traditional low-level approach. Works system-wide. Returns failure if hotkey is in use. Requires importing Carbon.
2. **`CGEventTap`** — lower level, requires Accessibility permission (additional barrier). Overkill for simple hotkeys.
3. **MASShortcut** (GitHub: nicklockwood/MASShortcut, LGPL-2.1) — AppKit wrapper around Carbon hotkeys. Provides the recorder view, conflict detection, and UserDefaults persistence. Well-maintained, widely used (Mango, Tot, etc.). The recommended approach.
4. **Sauce** (GitHub: Clipy/Sauce, MIT) — more recent alternative to MASShortcut. Less battle-tested.
5. **KeyboardShortcuts** (GitHub: sindresorhus/KeyboardShortcuts, MIT) — SwiftUI-first, wraps Carbon. Good for SwiftUI settings window.

**Recommendation:** MASShortcut or KeyboardShortcuts. Either eliminates the need to implement the recorder UI and conflict detection manually. Pick based on whether settings window is AppKit (MASShortcut) or SwiftUI (KeyboardShortcuts).

### Settings Window

**Expected behavior:**
- Opens with `Cmd+,` from anywhere in the app (macOS standard)
- Settings... menu item also opens it
- Brings existing window to front if already open (do not create duplicate windows)
- Standard NSWindow with toolbar or tab-based layout if multiple sections
- Non-modal (does not block overlay usage if somehow both are open)
- Closes with the standard window close button; does not quit the app
- Changes take effect immediately (live update), not "Apply" button

**Standard sections for this app:**
- General: launch at login, hide hint bar
- Measure: corrections mode
- Shortcuts: hotkey bindings (Measure, Alignment Guides)
- About: version, Raycast extension link

**Implementation note:** SwiftUI `Settings {}` scene in SwiftUI App lifecycle provides `Cmd+,` binding automatically. But this app uses AppKit lifecycle for the overlay system, so `Cmd+,` must be wired manually via `NSMenuItem` with `keyEquivalent: ","`.

### Launch at Login

**Expected behavior:**
- Checkbox labeled "Launch at Login" or "Open at Login"
- Checking it registers the app; unchecking removes it
- Works without admin password
- Survives app updates (SMAppService-based registration is path-independent)
- If user drags app to new location, registration may break — acceptable edge case

**API:** `SMAppService.mainApp.register()` and `.unregister()` (macOS 13+, HIGH confidence). Replaces deprecated `SMLoginItemSetEnabled` and the Login Item helper app pattern (used before macOS 13). No helper app target needed.

**Permission note:** `SMAppService` requires the app to be code-signed (at minimum ad-hoc for development). DMG distribution requires proper signing for launch-at-login to persist across reboots reliably.

### Coexistence with Raycast Extension

**Problem:** If both the standalone app and Raycast extension are active, user may have two different hotkeys triggering the same overlay, or get confused about which is "the real one."

**Detection approach (confidence: MEDIUM):**
- Check if Raycast.app exists at `/Applications/Raycast.app` (common location)
- Check if this extension is installed by looking for extension manifest in Raycast's extensions directory (path varies by Raycast version; typically `~/Library/Application Support/com.raycast.macos/extensions/`)
- Both checks failing = Raycast not installed; show no nudge
- Raycast installed but extension not found = Raycast installed but extension not active; maybe no nudge
- Both found = show one-time nudge

**Nudge content:** "Design Ruler is available both as a Raycast extension and this standalone app. You can use both, but assigning hotkeys in only one place avoids conflicts. Prefer this app if you use it outside of Raycast."

**UX:** Show as `NSAlert` on first launch only. Store shown state in `UserDefaults`. Do not nag on every launch.

### Detecting Raycast Extension Is Installed

**Confidence: LOW** — Raycast's internal storage path is not publicly documented. The approach of checking filesystem paths is a heuristic, not a reliable API.

**Alternative approach:** Instead of detecting Raycast, detect hotkey conflicts. If the user tries to assign a global hotkey that is already registered (by Raycast or anything else), the registration will fail. Surface "This shortcut is already in use by another application" and suggest the user reassign their Raycast extension shortcut or leave one unbound. This is more robust than trying to detect Raycast specifically.

---

## Competitor Feature Analysis

Reference apps in the menu bar pixel inspection / developer tool space:

| Feature | xScope 4 (Iconfactory) | Pixelmator Pro | Our Approach |
|---------|------------------------|----------------|--------------|
| Menu bar presence | Yes, NSStatusItem | No (Dock app) | NSStatusItem, utility pattern |
| Global hotkeys | Yes, configurable | No | Yes, user-configurable required |
| Launch at login | Yes | No | Yes, SMAppService |
| Settings window | Full preferences window | Preferences window | Standard NSWindow, sections |
| Raycast integration | No | No | Coexistence nudge |
| Overlay triggers | Menu + hotkey | N/A | Menu + hotkey |

xScope 4 is the closest reference point. It is a well-regarded developer tool with a menu bar presence and configurable hotkeys. Its UX patterns are worth studying for the settings window layout.

---

## Sources

**HIGH confidence** (training knowledge, stable macOS APIs):
- NSStatusItem API (available since macOS 10.0, stable)
- NSMenu/NSMenuItem for dropdown menus (stable)
- SMAppService.mainApp.register() (macOS 13+, released 2022, confirmed stable pattern)
- NSApp.setActivationPolicy(.accessory) (stable)
- Carbon RegisterEventHotKey (available since macOS 10.0, deprecated intent but still functional)
- UserDefaults for preference persistence (stable)

**MEDIUM confidence** (training knowledge, ecosystem-based):
- MASShortcut / KeyboardShortcuts library recommendations (widely used as of training cutoff)
- Raycast extension detection via filesystem paths (heuristic)
- Settings window UX patterns (based on macOS HIG and observed conventions)
- Coexistence nudge as one-time NSAlert (common pattern in dual-distribution apps)

**LOW confidence** (needs verification before implementation):
- Exact Raycast extension storage path for detection
- MASShortcut current maintenance status (verify on GitHub before committing)
- SMAppService behavior with ad-hoc signed DMG builds (verify code signing requirements)

---
*Feature research for: Standalone macOS menu bar app distribution of Design Ruler*
*Researched: 2026-02-17*
*Replaces: Previous FEATURES.md (hint bar redesign milestone)*
