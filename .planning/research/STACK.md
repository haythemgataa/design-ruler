# Technology Stack: Standalone macOS Menu Bar App

**Project:** Design Ruler — standalone macOS app alongside Raycast extension
**Researched:** 2026-02-17
**Scope:** New dependencies and integration decisions for menu bar, global hotkeys, settings window, launch-at-login, coexistence detection, DMG distribution. Existing overlay/detection system already validated — not re-researched.

---

## What Changes vs. What Stays

### Stays Exactly the Same (zero changes needed)
All overlay logic: `OverlayCoordinator`, `OverlayWindow`, `Measure`, `AlignmentGuides`, `EdgeDetector`, `ColorMap`, `CrosshairView`, `CursorManager`, `PillRenderer`, `HintBarView`, `PermissionChecker`, `ScreenCapture`, `DesignTokens` — every Swift file under `Sources/` compiles unchanged into the standalone target.

### What the Standalone App Adds
An app shell around the existing coordinator subclasses: NSStatusItem menu bar icon, global hotkey registration, settings window, launch-at-login toggle, Raycast coexistence detection, and a DMG/notarization CI pipeline.

---

## New Runtime Dependencies

### KeyboardShortcuts — Global Hotkeys

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| KeyboardShortcuts | 2.4.0 | User-customizable global hotkeys (Cmd+Shift+M / Cmd+Shift+G defaults) | Uses Carbon `RegisterEventHotKey` internally, which fires system-wide without requiring Accessibility permission. Wraps the raw Carbon API in a type-safe Swift interface and persists the user's chosen shortcut to `UserDefaults` automatically. Also provides a ready-made `KeyboardShortcuts.Recorder` SwiftUI view for the settings pane. Alternative: raw `RegisterEventHotKey` (verified working — see below) but you get none of the persistence, conflict handling, or recorder UI for free. |

**Verification:** `RegisterEventHotKey` tested in Swift REPL — `result == noErr`, `kVK_ANSI_M`, `cmdKey | shiftKey`, round-trip `UnregisterEventHotKey` OK. KeyboardShortcuts 2.4.0 released 2025-09-18 on GitHub (`sindresorhus/KeyboardShortcuts`). `Package.swift` declares `platforms: [.macOS(.v10_15)]` — compatible with our macOS 13+ target. Confidence: HIGH.

**Critical constraint:** `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` requires Accessibility permission granted by the user. `RegisterEventHotKey` (Carbon) does NOT. KeyboardShortcuts uses Carbon for its core, so no Accessibility permission is needed for hotkey activation.

**SPM integration:**
```swift
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0")
```

---

### Sparkle — Auto-Update (Optional but Expected)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Sparkle | 2.8.1 | In-app software updates for DMG-distributed app | DMG-distributed apps have no App Store update channel. Users expect update prompts. Sparkle is the de-facto standard for non-App-Store macOS apps. Version 2.x is XPC-based with privilege separation. Works without App Sandbox (only requires hardened runtime for notarization). |

**Verification:** Stable release 2.8.1 published 2025-11-15. SPM distribution via `binaryTarget` with `Sparkle-for-Swift-Package-Manager.zip`. Non-sandboxed apps need no extra entitlements beyond hardened runtime. Confidence: HIGH (industry standard for 15+ years).

**SPM integration:**
```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1")
```

**If skipping Sparkle:** Users must manually check GitHub releases. Acceptable for v1.0, defer to v1.1.

---

## Native SDK (No New Dependencies)

All of these are available from system frameworks already linked. Zero new Package.swift entries required.

### Menu Bar Icon — AppKit NSStatusItem

```swift
import AppKit

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Design Ruler")
statusItem.menu = buildMenu()
```

`NSStatusItem` + `NSStatusBarButton` verified in Swift REPL. Provides the icon, click target, and menu attachment. Use `NSMenu` (not `NSPopover`) for the dropdown — menus are native, keyboard-navigable, and do not require `NSApplication.activate()`. Confidence: HIGH.

**Activation policy for a menu-bar-only app:** Set `LSUIElement = YES` in `Info.plist` (equivalent to `.prohibited` at launch — no dock icon, no Cmd+Tab entry). When showing the Settings window, switch to `.accessory` so the window can be brought forward; revert when the window closes. Tested: `setActivationPolicy(.accessory)` returns `true`.

---

### Launch at Login — ServiceManagement SMAppService

```swift
import ServiceManagement

// Register
try SMAppService.mainApp.register()

// Unregister
try SMAppService.mainApp.unregister()

// Status check
let status = SMAppService.mainApp.status
// .notRegistered / .enabled / .requiresApproval / .notFound
```

`SMAppService.mainApp` registers the running app bundle itself as a login item — no helper app bundle needed (the old `SMLoginItemSetEnabled` pattern). Available macOS 13.0+, which matches our deployment target exactly. Verified in Swift REPL: `SMAppService available at macOS 13.0`, `SMAppService.mainApp: OK`. Confidence: HIGH.

**User-facing:** If `status == .requiresApproval`, direct the user to System Settings → General → Login Items to approve. Show this in the Settings window when toggle is on but approval is pending.

---

### Settings Window — AppKit NSWindowController + SwiftUI content

No library needed. Use `NSWindowController` containing a SwiftUI `NSHostingView`. This is the same hybrid pattern already used for `HintBarView`. A two-tab Settings window (General | About) with `NSToolbar` covers all needed settings:

- General tab: hotkey recorders (`KeyboardShortcuts.Recorder`), Launch at Login toggle, Hide Hint Bar checkbox, Corrections picker
- About tab: version, link to GitHub releases

The native SwiftUI `Settings {}` scene (available macOS 13+) is designed for the `@main` SwiftUI App protocol, which this app does not use (it uses `NSApplicationDelegate`). Stick with `NSWindowController`.

**sindresorhus/Settings library:** Adds toolbar-tab boilerplate reduction. Adds one more dependency. Not worth it for two tabs — build the `NSWindowController` directly (20-30 lines). Skip this library.

---

### Coexistence Detection — AppKit NSWorkspace

```swift
import AppKit

func isRaycastRunning() -> Bool {
    NSWorkspace.shared.runningApplications
        .contains { $0.bundleIdentifier == "com.raycast.macos" }
}

// Subscribe to launch/quit notifications
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil, queue: .main
) { _ in updateMenuBarState() }
```

Verified in Swift REPL: query returns Raycast instance when Raycast is running. `NSWorkspace.didLaunchApplicationNotification` and `didTerminateApplicationNotification` allow reactive updates.

**Strategy:** If Raycast is running when the user triggers a hotkey, show a non-blocking warning in the menu bar dropdown ("Raycast extension also active — hotkeys may conflict"). Do not disable the standalone hotkey or unregister it. Carbon `RegisterEventHotKey` conflict behavior: the most-recently-registered app typically wins, but behavior is non-deterministic. Warning is the right UX; suppression is not.

---

### Settings Persistence — Foundation UserDefaults

```swift
UserDefaults.standard.set(true, forKey: "hideHintBar")
UserDefaults.standard.set("smart", forKey: "corrections")
```

Verified in Swift REPL. `UserDefaults.standard` automatically scoped to the app's bundle ID. No `synchronize()` call needed (deprecated pattern — macOS persists automatically). Confidence: HIGH.

---

## Build Infrastructure (CI Tooling, Not App Dependencies)

### Xcode Project

**Required.** The current codebase is a Swift Package Manager `.executableTarget` built by Raycast's toolchain. A standalone `.app` bundle needs:
- `Info.plist` (bundle ID, version, `LSUIElement = YES`, `NSHighResolutionCapable`)
- Entitlements file (hardened runtime, no App Sandbox)
- App icon (`AppIcon.icns`)
- Proper code signing configuration

SPM does not support entitlements natively on executable targets. The standalone target must be an Xcode project (`.xcodeproj`) alongside the existing SPM package.

**Do NOT use XcodeGen** (2.44.1, 2025-07-22). It adds a YAML-to-project build step to CI with no meaningful payoff for a single-target app. A checked-in `.xcodeproj` is simpler and more transparent. The `.xcodeproj` references the same Swift source files from `swift/DesignRuler/Sources/` directly.

### Source Sharing Strategy

The `@raycast` entry-point functions in `Measure.swift` and `AlignmentGuides.swift` cannot be compiled into the standalone target (they depend on `RaycastSwiftMacros`). Use separate entry files:

```
swift/DesignRuler/Sources/Measure/Measure.swift        ← shared (coordinator logic)
swift/DesignRuler/Sources/Measure/MeasureEntry.swift   ← Raycast target only (@raycast func inspect)
StandaloneApp/AppDelegate.swift                        ← standalone only (calls Measure.shared.run)
```

No `#if canImport(RaycastSwiftMacros)` conditional compilation. Two separate files targeting two separate compilation units. Clean, no build-time surprises.

### OverlayCoordinator Refactoring

`OverlayCoordinator.run()` currently calls `app.run()` (which blocks, correct for a Raycast process that owns the run loop). `handleExit()` calls `NSApp.terminate(nil)` (kills the process, correct for Raycast).

In the standalone app, the run loop is already running (the app is always alive). Two changes needed:

```swift
// Add to OverlayCoordinator:
var isStandaloneMode = false
var onCommandComplete: (() -> Void)?

func run(hideHintBar: Bool) {
    // ... existing startup sequence ...
    if !isStandaloneMode {
        app.run()  // blocks for Raycast only
    }
}

func handleExit() {
    CursorManager.shared.restore()
    for window in windows { window.close() }
    if isStandaloneMode {
        onCommandComplete?()   // notify menu bar app
    } else {
        NSApp.terminate(nil)   // Raycast: kill process
    }
}
```

This is a two-line addition to `OverlayCoordinator` — not a rewrite. The Raycast path is unchanged.

### DMG Packaging

**create-dmg 1.2.3** (released 2025-11-18). A bash script (not a binary) that wraps `hdiutil` to produce a styled DMG with background image, icon positioning, and `/Applications` symlink. Install via `brew install create-dmg` in CI. Do not vendor it into the repository.

```bash
# CI packaging step
create-dmg \
  --volname "Design Ruler" \
  --background "Assets/dmg-background.png" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "DesignRuler.app" 180 170 \
  --hide-extension "DesignRuler.app" \
  --app-drop-link 480 170 \
  "DesignRuler-{VERSION}.dmg" \
  "build/Release/"
```

### Code Signing and Notarization

```bash
# Archive
xcodebuild archive \
  -project DesignRuler.xcodeproj \
  -scheme DesignRuler \
  -archivePath build/DesignRuler.xcarchive

# Export signed .app
xcodebuild -exportArchive \
  -archivePath build/DesignRuler.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/Release

# Notarize
xcrun notarytool submit DesignRuler.dmg \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple DesignRuler.dmg
```

`xcrun notarytool` version 1.1.0 confirmed available. No new tooling needed beyond standard Xcode CLI tools.

**Entitlements file** (non-sandboxed, hardened runtime):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><false/>
  <key>com.apple.security.cs.disable-library-validation</key><false/>
</dict></plist>
```

No special entitlements for `CGWindowListCreateImage` (screen recording is a TCC permission, not an entitlement). `SMAppService` works with hardened runtime and no sandbox.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Global hotkeys | KeyboardShortcuts 2.4.0 | Raw Carbon `RegisterEventHotKey` | Raw Carbon works but requires manual persistence, conflict handling, and a custom recorder UI — all of which KeyboardShortcuts provides for free |
| Global hotkeys | KeyboardShortcuts 2.4.0 | `NSEvent.addGlobalMonitorForEvents` | Requires Accessibility permission granted by user — an extra permission prompt that CGWindowListCreateImage does not require |
| Settings window | NSWindowController + SwiftUI | sindresorhus/Settings | Adds a dependency for boilerplate reduction; two tabs do not justify it |
| Settings window | NSWindowController + SwiftUI | SwiftUI Settings scene | Designed for `@main` SwiftUI App; this app uses NSApplicationDelegate; mixing paradigms adds complexity |
| Launch at login | SMAppService | LaunchAgent plist | LaunchAgent requires writing to `/Library/LaunchAgents` (needs privilege escalation) or `~/Library/LaunchAgents` (manual management). SMAppService handles everything through the OS safely |
| Launch at login | SMAppService | SMLoginItemSetEnabled + helper bundle | Deprecated in macOS 13; helper bundle adds build complexity |
| Auto-update | Sparkle 2.8.1 | None (manual check GitHub) | Acceptable for v1.0 release; users expect update prompts for paid/free tools |
| Auto-update | Sparkle 2.8.1 | Custom update checker | Sparkle handles delta updates, EdDSA signing, background download, progress UI — reimplementing all of this is wasteful |
| Project structure | Xcode .xcodeproj | XcodeGen YAML | One extra CI step with no meaningful benefit for a single-target project |
| DMG | create-dmg | hdiutil directly | hdiutil requires 15+ manual steps for a polished DMG; create-dmg encapsulates them |

---

## What NOT to Add

| Avoid | Why | Instead |
|-------|-----|---------|
| App Sandbox | Adds entitlement complexity for no distribution benefit (not App Store). CGWindowListCreateImage works without sandbox; adding sandbox would break it or require additional entitlements | Do not sandbox. Use hardened runtime only. |
| Accessibility permission request | `NSEvent.addGlobalMonitorForEvents` for hotkeys requires Accessibility. KeyboardShortcuts uses Carbon, which does not. | Use KeyboardShortcuts — zero extra permission prompts |
| LoginItemHelper target | Old pattern (pre-macOS 13). Helper bundle adds a second build target, extra code signing, and notarization surface. | Use `SMAppService.mainApp` |
| NSPopover for menu | Popovers need app activation; menus do not. Menu bar apps using NSPopover require `NSApp.activate(ignoringOtherApps:)` which causes dock-bounce and disrupts the active app. | Use `NSMenu` attached to `statusItem.menu` |
| Dock icon | `LSUIElement = NO` would show the app in the dock and Cmd+Tab. This is wrong UX for a tool that lives in the menu bar and should be invisible until invoked. | `LSUIElement = YES` in `Info.plist`, activate only when showing Settings |

---

## API Availability Summary

| API | Min macOS | Our Target | Conditional? | Purpose |
|-----|-----------|------------|-------------|---------|
| `NSStatusItem` / `NSStatusBar` | 10.0 | 13.0 | No | Menu bar icon |
| `NSStatusBarButton` | 10.10 | 13.0 | No | Icon button with action |
| `RegisterEventHotKey` (Carbon) | 10.0 | 13.0 | No | System-wide hotkey registration |
| `SMAppService.mainApp` | 13.0 | 13.0 | No | Launch at login (no helper) |
| `NSWorkspace.runningApplications` | 10.0 | 13.0 | No | Coexistence detection |
| `NSWorkspace.didLaunchApplicationNotification` | 10.0 | 13.0 | No | Reactive coexistence updates |
| `UserDefaults.standard` | 10.0 | 13.0 | No | Settings persistence |
| `NSWindowController` | 10.0 | 13.0 | No | Settings window shell |
| `NSHostingView` | 10.15 | 13.0 | No | SwiftUI content in settings |
| `setActivationPolicy(_:)` | 10.6 | 13.0 | No | Hide/show dock icon |

**Everything available unconditionally at macOS 13+. No `#available` guards needed for any new capability.**

---

## Package.swift Changes (New Standalone Target)

The existing `Package.swift` for the Raycast target stays unchanged. The standalone app uses an Xcode project (`.xcodeproj`) with Swift Package dependencies:

```swift
// StandaloneApp dependencies in Xcode project:
// - KeyboardShortcuts (required)
// - Sparkle (optional, can add later)
// NO RaycastSwiftMacros (standalone does not use @raycast)
```

---

## Sources

- `RegisterEventHotKey` — verified in Swift REPL, Carbon framework, macOS 10.0+ — HIGH confidence
- `NSStatusItem` / `NSStatusBarButton` — verified in Swift REPL, AppKit — HIGH confidence
- `SMAppService.mainApp` — verified in Swift REPL, ServiceManagement, macOS 13.0+ — HIGH confidence
- `NSWorkspace.runningApplications` — verified in Swift REPL, AppKit — HIGH confidence
- `KeyboardShortcuts` 2.4.0 — [github.com/sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) releases/latest, Package.swift inspected via GitHub API — HIGH confidence
- `Sparkle` 2.8.1 — [github.com/sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) releases inspected via GitHub API, Installation.md and Security.md read — HIGH confidence
- `create-dmg` 1.2.3 — [github.com/create-dmg/create-dmg](https://github.com/create-dmg/create-dmg) releases/latest, `brew info create-dmg` — HIGH confidence
- `xcrun notarytool` 1.1.0 — confirmed via `xcrun notarytool --version` on local system — HIGH confidence
- LinearMouse CI workflow — [github.com/linearmouse/linearmouse](https://github.com/linearmouse/linearmouse) `.github/workflows/build.yml` inspected — MEDIUM confidence (real-world validation of xcodebuild + create-dmg + notarytool pipeline)
- OverlayCoordinator integration analysis — codebase inspection of `OverlayCoordinator.swift` lines 109, 167 — HIGH confidence

---
*Stack research for: standalone macOS menu bar app addition to Design Ruler*
*Researched: 2026-02-17*
