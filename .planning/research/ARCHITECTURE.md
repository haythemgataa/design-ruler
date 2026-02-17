# Architecture Patterns: Standalone macOS App Integration

**Domain:** macOS menu bar app sharing Swift overlay/detection code with a Raycast extension
**Researched:** 2026-02-17
**Confidence:** HIGH (analysis derived directly from existing source code + well-established macOS patterns)

---

## 1. The Core Integration Question

The existing Swift code is structured around one hard constraint: `@raycast func` declarations
are the **only** entry points, and `app.run()` is called from inside `OverlayCoordinator.run()`.
For the standalone app, two things must change:

1. The overlay coordinators (`Measure.shared`, `AlignmentGuides.shared`) must be callable from
   an `AppDelegate` instead of from a `@raycast` function.
2. The `NSApplication.shared.run()` call in `OverlayCoordinator.run()` must NOT be called — the
   standalone app's own run loop already owns `NSApp`.

Both changes are localized. The overlay windows, edge detection, cursor management, rendering,
and hint bar are completely unchanged.

---

## 2. Repo Structure for Dual Targets

### Current Structure (Raycast only)

```
porto/
├── src/                         # TypeScript entry points (Raycast only)
│   ├── measure.ts
│   └── alignment-guides.ts
├── swift/
│   └── DesignRuler/             # Single Swift Package with one executableTarget
│       ├── Package.swift
│       ├── Package.resolved
│       └── Sources/             # All Swift code (single flat target)
│           ├── Measure/
│           ├── AlignmentGuides/
│           ├── Rendering/
│           ├── Cursor/
│           ├── Utilities/
│           └── Permissions/
└── package.json                 # Raycast extension manifest
```

### Recommended Structure (Dual target)

```
porto/
├── src/                                    # TypeScript (Raycast only, unchanged)
│   ├── measure.ts
│   └── alignment-guides.ts
├── swift/
│   └── DesignRuler/
│       ├── Package.swift                   # MODIFIED: adds library + app targets
│       ├── Package.resolved
│       └── Sources/
│           ├── DesignRulerCore/            # NEW: renamed from flat Sources/ layout
│           │   ├── Measure/                # Unchanged Swift files
│           │   ├── AlignmentGuides/        # Unchanged Swift files
│           │   ├── Rendering/              # Unchanged Swift files
│           │   ├── Cursor/                 # Unchanged Swift files
│           │   ├── Utilities/              # Unchanged Swift files (minus app.run())
│           │   └── Permissions/            # Unchanged Swift files
│           ├── DesignRulerRaycast/         # NEW: Raycast entry point shim
│           │   ├── Measure.swift           # @raycast func inspect() → Measure.shared.run()
│           │   └── AlignmentGuides.swift   # @raycast func alignmentGuides() → ...
│           └── DesignRulerApp/             # NEW: Standalone app shell
│               ├── main.swift              # NSApplicationMain entry
│               ├── AppDelegate.swift       # NSStatusItem, menu, hotkey wiring
│               ├── MenuBarController.swift # NSStatusItem setup and menu
│               ├── HotkeyManager.swift     # CGEventTap or Carbon hotkey registration
│               ├── SettingsWindow.swift    # Preferences: hint bar, corrections, hotkeys
│               └── LoginItemManager.swift  # SMAppService launch-at-login (macOS 13+)
└── DesignRulerApp.xcodeproj/              # NEW: Xcode project for standalone app build
    └── (standard Xcode project files)
```

### Why This Structure

**The `DesignRulerCore` library target** contains all existing Swift code verbatim. No overlay
file is modified to support the standalone app. The library is a pure `.library` target — no
`@raycast` imports, no `app.run()`, no TypeScript bridge.

**The `DesignRulerRaycast` executable target** contains only the two `@raycast func` entry
points (currently inline in `Measure.swift` and `AlignmentGuides.swift`). These are extracted
into their own target that depends on `DesignRulerCore` and `RaycastSwiftMacros`. This is the
only target Raycast builds.

**The `DesignRulerApp` executable target** is the standalone macOS app shell. It depends only
on `DesignRulerCore`. It contains no Raycast dependencies.

**The Xcode project** exists alongside the Swift Package. The standalone app needs code signing,
entitlements (screen recording, accessibility if needed), and macOS app bundle structure — none
of which Swift Package Manager handles for app targets. The Xcode project references
`DesignRulerCore` as a local package dependency.

---

## 3. Package.swift Changes

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesignRuler",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/raycast/extensions-swift-tools", from: "1.0.4"),
    ],
    targets: [
        // Library: all shared overlay/detection code. No Raycast dependency.
        .target(
            name: "DesignRulerCore",
            path: "Sources/DesignRulerCore"
        ),

        // Raycast executable: @raycast entry points only. Depends on Core + Raycast macros.
        .executableTarget(
            name: "DesignRuler",
            dependencies: [
                "DesignRulerCore",
                .product(name: "RaycastSwiftMacros", package: "extensions-swift-tools"),
                .product(name: "RaycastSwiftPlugin", package: "extensions-swift-tools"),
                .product(name: "RaycastTypeScriptPlugin", package: "extensions-swift-tools"),
            ],
            path: "Sources/DesignRulerRaycast"
        ),
    ]
)
```

The standalone app target is NOT in Package.swift — it lives in the Xcode project, which
references `DesignRulerCore` via `File > Add Package Dependencies > Add Local...`.

---

## 4. The `app.run()` Problem and Fix

`OverlayCoordinator.run()` currently calls `app.run()` at the end of its startup sequence.
This is correct for the Raycast context (where `@raycast func` is called on a background thread
and the run loop must be started explicitly). It is wrong for the standalone app (where
`NSApplicationMain` already owns the run loop).

### Fix: `runMode` Parameter

Add a `RunMode` enum to `OverlayCoordinator`:

```swift
// In OverlayCoordinator.swift (DesignRulerCore)

enum RunMode {
    case raycast    // starts app.run() — Raycast path
    case standalone // no app.run() — app's existing run loop continues
}

class OverlayCoordinator {
    // ...

    func run(hideHintBar: Bool, runMode: RunMode = .raycast) {
        // Steps 1-10 unchanged ...

        // 11. Launch time, activate, signal handler, inactivity timer
        launchTime = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        setupSignalHandler()
        resetInactivityTimer()

        // 12. ONLY start run loop for Raycast (standalone already has one)
        if runMode == .raycast {
            app.run()
        }
    }
}
```

Existing `Measure.run()` and `AlignmentGuides.run()` call `super.run(hideHintBar:)` with the
default `.raycast` mode — no change to either class.

Standalone app calls: `Measure.shared.run(hideHintBar: ..., runMode: .standalone)`

The `handleExit()` method also calls `NSApp.terminate(nil)` — this is correct for Raycast
(terminates the extension process) but wrong for the standalone app (terminates the entire app).
Apply the same pattern:

```swift
func handleExit() {
    CursorManager.shared.restore()
    for window in windows {
        window.close()
    }
    if runMode == .raycast {
        NSApp.terminate(nil)
    }
    // Standalone: run loop continues, status item remains, ready for next invocation
}
```

Store `runMode` as an instance variable set in `run()`.

---

## 5. Standalone App Architecture

### Component Map

```
DesignRulerApp (NSApplicationMain)
    │
    ├── AppDelegate (NSApplicationDelegate)
    │       • applicationDidFinishLaunching: sets up MenuBarController + HotkeyManager
    │       • applicationWillTerminate: CursorManager.shared.restore()
    │
    ├── MenuBarController
    │       • Owns NSStatusItem with icon in menu bar
    │       • Builds NSMenu: "Measure", "Alignment Guides", separator, "Settings...", "Quit"
    │       • "Measure" action → Measure.shared.run(hideHintBar:, runMode: .standalone)
    │       • "Alignment Guides" action → AlignmentGuides.shared.run(hideHintBar:, runMode: .standalone)
    │       • Reads preferences from AppPreferences for hideHintBar / corrections
    │
    ├── HotkeyManager
    │       • Registers global event tap via CGEventTap (no third-party dependency)
    │       • Two configurable hotkeys: one for Measure, one for Alignment Guides
    │       • On trigger: calls same methods as MenuBarController actions
    │       • Requires Accessibility permission (prompt on first use)
    │       • Stores hotkey bindings in UserDefaults via AppPreferences
    │
    ├── AppPreferences (UserDefaults wrapper)
    │       • hideHintBar: Bool
    │       • corrections: String ("smart" / "include" / "none")
    │       • measureHotkey: HotkeyBinding (keyCode + modifiers)
    │       • alignmentGuidesHotkey: HotkeyBinding
    │       • launchAtLogin: Bool
    │
    ├── SettingsWindow
    │       • NSWindowController hosting SwiftUI Settings view
    │       • Sections: Hotkeys, Behavior (hideHintBar, corrections), General (launch at login)
    │       • Live-updates AppPreferences; HotkeyManager re-registers on change
    │
    └── LoginItemManager
            • Uses SMAppService.mainApp (macOS 13+)
            • SMAppService.mainApp.register() / unregister()
            • Reads/writes AppPreferences.launchAtLogin
```

### Data Flow: Hotkey Press to Overlay Launch

```
User presses global hotkey
    │
    ▼
CGEventTap callback (HotkeyManager, runs on main thread via DispatchQueue.main.async)
    │
    ▼
HotkeyManager checks: which hotkey matched?
    │
    ├── measureHotkey → Measure.shared.run(hideHintBar: prefs.hideHintBar,
    │                                      corrections: prefs.corrections,
    │                                      runMode: .standalone)
    │
    └── alignmentGuidesHotkey → AlignmentGuides.shared.run(hideHintBar: prefs.hideHintBar,
                                                            runMode: .standalone)
    │
    ▼
OverlayCoordinator.run() executes (steps 1-11, skips app.run())
    │
    ▼
Fullscreen overlay windows appear (identical behavior to Raycast version)
    │
    ▼
User presses ESC
    │
    ▼
handleExit() called → CursorManager.shared.restore() → windows.close()
    │   (no NSApp.terminate for standalone)
    │
    ▼
App returns to menu bar state, ready for next invocation
```

### Data Flow: Overlay Re-entry Guard

The overlay coordinators use `static let shared` singletons. If the user triggers a hotkey
while an overlay is already active, the second call to `run()` will close existing windows
(step 7 in `OverlayCoordinator.run()`) and restart. This is acceptable behavior — the same
thing happens in Raycast if the command is triggered twice.

Add an optional guard to skip the second call if preferred:

```swift
// In OverlayCoordinator (optional):
private var isRunning = false

func run(hideHintBar: Bool, runMode: RunMode = .raycast) {
    guard !isRunning else { return }
    isRunning = true
    // ... existing startup ...
}

func handleExit() {
    isRunning = false
    // ... existing exit ...
}
```

---

## 6. New vs Modified Components

### New Files (in DesignRulerApp target only)

| File | Purpose | Notes |
|------|---------|-------|
| `main.swift` | `NSApplicationMain` entry | Minimal — just instantiates AppDelegate |
| `AppDelegate.swift` | App lifecycle + wiring | `applicationDidFinishLaunching`, `applicationWillTerminate` |
| `MenuBarController.swift` | `NSStatusItem` + `NSMenu` | Reads preferences, calls coordinators |
| `HotkeyManager.swift` | `CGEventTap` hotkey registration | Accessibility permission prompt |
| `AppPreferences.swift` | `UserDefaults` typed wrapper | Shared by all app components |
| `SettingsWindow.swift` | `NSWindowController` + SwiftUI | Binds to `AppPreferences` |
| `LoginItemManager.swift` | `SMAppService.mainApp` | macOS 13+ only, no fallback needed |
| `CoexistenceDetector.swift` | Detect running Raycast extension | Check for Raycast process + extension |
| `DesignRulerApp.entitlements` | Entitlements plist | Screen recording capability |

### New Files (in DesignRulerCore target, small additions)

| File | Purpose | Notes |
|------|---------|-------|
| _(none)_ | No new core files needed | Only modifications to existing files |

### Modified Files (DesignRulerCore)

| File | Change | Scope |
|------|--------|-------|
| `OverlayCoordinator.swift` | Add `RunMode` enum + `runMode` instance var; gate `app.run()` and `NSApp.terminate()` | ~15 lines added |

### Extracted Files (rename/move only)

| Current Location | New Location | Change |
|-----------------|--------------|--------|
| `Sources/Measure.swift` | `Sources/DesignRulerRaycast/Measure.swift` | Move `@raycast func inspect()` out; keep `class Measure` in Core |
| `Sources/AlignmentGuides.swift` | `Sources/DesignRulerRaycast/AlignmentGuides.swift` | Move `@raycast func alignmentGuides()` out; keep `class AlignmentGuides` in Core |

The `@raycast func` declarations are the only parts that go into the Raycast shim. The
coordinator classes (`class Measure`, `class AlignmentGuides`) stay in Core.

---

## 7. HotkeyManager: CGEventTap vs Carbon

Two options exist for global hotkeys on macOS:

**Option A: Carbon `RegisterEventHotKey`** (legacy)
- Simplest API, no Accessibility permission required
- Deprecated but functional on macOS 13+
- Works only when app is frontmost OR has `LSUIElement = YES`
- Cannot detect all modifier combinations (missing some key codes)

**Option B: `CGEventTap`** (recommended)
- Modern, supported, works system-wide
- Requires Accessibility permission (`AXIsProcessTrusted()`)
- Full key code + modifier access
- Works in background (app does not need to be frontmost)

**Use `CGEventTap`.** The standalone app is a background-running menu bar tool — it must respond
to hotkeys regardless of which app is in front. Carbon hotkeys are unreliable in this context.
Accessibility permission is a one-time prompt, identical to what users accept for other developer
tools (Rectangle, Moom, etc.).

```swift
// HotkeyManager.swift skeleton

final class HotkeyManager {
    private var eventTap: CFMachPort?

    func register(measureHotkey: HotkeyBinding, guidesHotkey: HotkeyBinding,
                  onMeasure: @escaping () -> Void, onGuides: @escaping () -> Void) {
        guard AXIsProcessTrusted() else {
            promptAccessibilityPermission()
            return
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            // Check keyCode + modifiers against registered bindings
            // Dispatch to main: DispatchQueue.main.async { handler() }
            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: nil
        )
        // Add to run loop via CFRunLoopAddSource
    }
}
```

---

## 8. Settings Window

Use `NSWindowController` hosting a SwiftUI view via `NSHostingController`. Do NOT use the
`SwiftUI.Settings` scene — that requires the app to be structured as a `@main App`, which
conflicts with the `AppDelegate`-based menu bar pattern.

```swift
// SettingsWindow.swift

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Design Ruler Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 300))
        self.init(window: window)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

The `SettingsView` (SwiftUI) reads and writes `AppPreferences` via `@AppStorage` with the same
`UserDefaults` suite as `AppPreferences`. This keeps the settings view stateless and eliminates
manual binding.

---

## 9. Launch at Login

Use `SMAppService.mainApp` (macOS 13+). This API requires the app to be in `/Applications` or
the user's `~/Applications` folder — i.e., it requires a proper app bundle, not a debug build.

```swift
import ServiceManagement

enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Show alert: requires app to be in Applications folder
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

**Confidence: HIGH** — `SMAppService` is the Apple-recommended API since macOS 13, replacing
the deprecated `LSRegisterURL` and `SMLoginItemSetEnabled` approaches.

---

## 10. Coexistence Detection

When both the standalone app and Raycast extension are installed, both can trigger the same
overlays via different entry points. Coexistence is harmless — the singleton coordinators
handle re-entry. However, showing the user a notice prevents confusion.

```swift
// CoexistenceDetector.swift

enum CoexistenceDetector {
    /// Returns true if the Raycast extension "design-ruler" appears to be installed.
    /// Checks by looking for the extension in Raycast's known extensions directory.
    static func isRaycastExtensionInstalled() -> Bool {
        let raycastExtensionsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/com.raycast.macos/extensions")
        let designRulerURL = raycastExtensionsURL.appendingPathComponent("design-ruler")
        return FileManager.default.fileExists(atPath: designRulerURL.path)
    }
}
```

Show a one-time banner in Settings: "Design Ruler Raycast extension detected. Both work
independently — you may want to remove one to avoid duplicate hotkeys."

Suppress after user dismisses via a UserDefaults flag.

---

## 11. Component Boundaries

| Component | Owns | Does NOT Own |
|-----------|------|--------------|
| `DesignRulerCore` | All overlay logic, windows, detection, rendering, cursor | App lifecycle, hotkeys, menu bar, preferences UI |
| `AppDelegate` | App startup/shutdown, wiring coordinators to UI | Overlay behavior, window management |
| `MenuBarController` | `NSStatusItem` + `NSMenu` setup | Hotkey detection, overlay logic |
| `HotkeyManager` | `CGEventTap` lifecycle, key binding matching | Overlay invocation details (delegates to AppDelegate) |
| `AppPreferences` | `UserDefaults` read/write | UI rendering, overlay logic |
| `SettingsWindow` | Settings UI presentation | Preference storage (delegates to AppPreferences) |
| `LoginItemManager` | `SMAppService` calls | UI for toggle (Settings owns that) |

---

## 12. Build Order Recommendation

The dependency graph is strictly layered:

```
Phase 1: Core Library Extraction
    Rename flat Sources/ → Sources/DesignRulerCore/
    Add RunMode to OverlayCoordinator
    Extract @raycast funcs to Sources/DesignRulerRaycast/
    Update Package.swift
    Verify: ray build still passes
    │
    ▼
Phase 2: Xcode Project + App Shell
    Create DesignRulerApp.xcodeproj
    Reference DesignRulerCore as local package
    Add AppDelegate, main.swift
    Verify: app builds and quits cleanly
    │
    ▼
Phase 3: Menu Bar + Manual Invoke
    Add MenuBarController (NSStatusItem + NSMenu)
    Wire "Measure" and "Alignment Guides" menu items to coordinators
    Verify: overlays launch from menu, ESC returns to menu bar
    │
    ▼
Phase 4: AppPreferences + Settings Window
    Add AppPreferences (UserDefaults wrapper)
    Add SettingsWindow (NSWindowController + SwiftUI)
    Wire hideHintBar, corrections to Measure.run() call
    Verify: preferences persist across launches
    │
    ▼
Phase 5: Global Hotkeys
    Add HotkeyManager (CGEventTap)
    Add hotkey binding UI to SettingsWindow
    Verify: hotkeys trigger overlays when any app is frontmost
    │
    ▼
Phase 6: Launch at Login + Polish
    Add LoginItemManager (SMAppService)
    Add CoexistenceDetector
    Wire status item icon states (active/idle)
    Verify: launch at login works from /Applications
    │
    ▼
Phase 7: Distribution
    Configure code signing + notarization
    Build DMG via create-dmg or Xcode archive
    GitHub Actions release workflow
```

**Phase 1 is the critical dependency** — all subsequent phases require the library target
separation to be correct. The Raycast build must still pass after Phase 1 before any app
shell work begins.

---

## 13. Anti-Patterns to Avoid

### Anti-Pattern 1: Modifying Overlay Code for App Concerns

**What:** Adding menu bar state, hotkey checks, or preference reads into `OverlayCoordinator`,
`Measure`, or `AlignmentGuides`.
**Why bad:** Couples the pure overlay logic to app-shell concerns. Makes the Raycast path
depend on app constructs. Breaks the single-responsibility boundary.
**Instead:** App shell reads preferences and passes them as parameters to `run()`. Overlay
coordinators remain ignorant of how they were invoked.

### Anti-Pattern 2: Calling `NSApp.terminate()` from Overlay Exit in Standalone Mode

**What:** Letting `handleExit()` call `NSApp.terminate(nil)` unconditionally.
**Why bad:** Terminates the entire standalone app instead of just closing the overlay. The
user's menu bar icon disappears; they must relaunch.
**Instead:** Gate `NSApp.terminate()` behind `runMode == .raycast` as described in Section 4.

### Anti-Pattern 3: Using `SwiftUI.App` / `@main` for the Standalone App

**What:** Restructuring the app as a `SwiftUI.App` with `WindowGroup` and `Settings` scenes.
**Why bad:** SwiftUI app lifecycle fights with the existing AppKit fullscreen overlay architecture.
`OverlayCoordinator.run()` calls `NSApp.setActivationPolicy(.accessory)` and manipulates the
run loop — these are incompatible with SwiftUI's managed app lifecycle.
**Instead:** Use `AppDelegate`-based `NSApplicationMain`. SwiftUI is used only for content
views inside `NSWindowController` (Settings), not for app structure.

### Anti-Pattern 4: Putting `@raycast` Import into DesignRulerCore

**What:** Keeping `import RaycastSwiftMacros` in any Core file so `@raycast` func declarations
can stay alongside the coordinator classes.
**Why bad:** Makes `DesignRulerCore` depend on the Raycast Swift tools package. The standalone
app target would then transitively depend on Raycast, which adds unnecessary build complexity
and could break if the Raycast package is unavailable.
**Instead:** Extract the two `@raycast func` lines into the `DesignRulerRaycast` shim target.
Core has zero knowledge of Raycast.

### Anti-Pattern 5: Registering Global Hotkeys with Carbon `RegisterEventHotKey`

**What:** Using the legacy Carbon hotkey API to avoid the Accessibility permission prompt.
**Why bad:** Carbon hotkeys only fire when the app is frontmost or has special LSUIElement
behavior. A background menu bar app will miss hotkeys while other apps are active.
**Instead:** Use `CGEventTap`. Accept the one-time Accessibility permission prompt.

### Anti-Pattern 6: Creating a Second `NSWindow` for the Status Item Popover

**What:** Using an `NSPopover` or auxiliary window to show a popover from the status item
instead of an `NSMenu`.
**Why bad:** Adds significant complexity (popover positioning, dismiss on click-outside,
content state management) for no functional gain. The two actions are simple command triggers,
not browsable content.
**Instead:** Use a plain `NSMenu` attached to the status item. `NSStatusItem.menu = myMenu`
is the standard pattern for this type of tool.

### Anti-Pattern 7: Sharing `UserDefaults.standard` Between App and Extension

**What:** Using the default `UserDefaults.standard` suite for both the standalone app preferences
and expecting Raycast to read them.
**Why bad:** Raycast extension preferences are managed by Raycast's own system (declared in
`package.json`) and are not stored in the app's `UserDefaults`. Cross-reading is not possible.
**Instead:** Standalone app has its own `UserDefaults` store. Raycast extension reads from
Raycast's preference system via the TypeScript entry point. The two are independent.

---

## 14. Entitlements and Permissions

| Capability | API Used | Required By | Notes |
|------------|----------|-------------|-------|
| Screen Recording | `CGPreflightScreenCaptureAccess()` | Both targets | Same as current; prompted on first overlay launch |
| Accessibility | `AXIsProcessTrusted()` | Standalone only | Required for `CGEventTap` global hotkeys |
| Launch at Login | `SMAppService` | Standalone only | No entitlement required; uses service management |
| Hardened Runtime | Xcode setting | Standalone only | Required for notarization |
| App Sandbox | Disabled | Standalone only | Sandboxed apps cannot use `CGEventTap` for global hotkeys |

**App Sandbox must be disabled** for the standalone app. Global hotkey capture via `CGEventTap`
requires Accessibility permission and a non-sandboxed environment. This is standard for developer
tools in this category (Rectangle, BetterTouchTool, Moom all require disabling sandbox).

---

## 15. Confidence Assessment

| Area | Confidence | Basis |
|------|------------|-------|
| Package.swift multi-target structure | HIGH | Direct SPM documentation pattern; library + executable targets are standard |
| `RunMode` fix for `app.run()` | HIGH | Derived from direct code reading of `OverlayCoordinator.run()`; the call is the only structural incompatibility |
| `NSStatusItem` + `NSMenu` pattern | HIGH | Well-established macOS menu bar app pattern used since macOS 10.0 |
| `CGEventTap` for hotkeys | HIGH | Standard approach for system-wide hotkeys; Accessibility permission requirement is documented |
| `SMAppService` for launch at login | HIGH | Apple-documented replacement for deprecated APIs; macOS 13+ matches project minimum |
| App Sandbox must be disabled | HIGH | `CGEventTap` is explicitly excluded from sandbox; documented constraint |
| Coexistence via directory check | MEDIUM | Raycast's extension storage path is not officially documented; path may change across Raycast versions |

---

## Sources

- Direct source analysis: `OverlayCoordinator.swift`, `Measure.swift`, `AlignmentGuides.swift`,
  `OverlayWindow.swift`, `CursorManager.swift`, `Package.swift` (all in this repo)
- Apple Developer Documentation: `NSStatusItem`, `NSMenu`, `SMAppService`, `CGEventTap`,
  `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`
- Swift Package Manager: multi-target package structure (.target + .executableTarget pattern)
- macOS App Sandbox entitlement restrictions (CGEventTap exclusion)

---
*Architecture research for: standalone macOS menu bar app sharing Swift overlay code with Raycast extension*
*Researched: 2026-02-17*
