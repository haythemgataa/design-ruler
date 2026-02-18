# Phase 20: Menu Bar Shell - Research

**Researched:** 2026-02-18
**Domain:** NSStatusItem + NSMenu AppKit pattern in a persistent macOS agent app (LSUIElement)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Menu bar icon**
- Use an SF Symbol as placeholder icon (user will provide custom asset later)
- Template-style image — adapts to light/dark menu bar automatically
- Standard 18x18pt size (matches Bartender, Rectangle, iStat conventions)
- Active-overlay state: filled variant of the same SF Symbol (e.g. ruler → ruler.fill)
- Icon reverts to idle state instantly on ESC (no delay)
- Since all screens are captured by the overlay, the icon state change is only observable during brief setup/teardown — not while the overlay is running

**Dropdown menu content**
- Menu structure (top to bottom):
  1. Measure
  2. Alignment Guides
  3. Separator
  4. Settings... (disabled/grayed out — wired in Phase 21)
  5. Separator
  6. Quit Design Ruler
- Labels match Raycast command names exactly: "Measure" and "Alignment Guides"
- No header or app name at top of menu (jump straight to commands)
- No keyboard shortcut hints in this phase (added in Phase 22)

**Session-active behavior**
- Fullscreen overlay captures ALL screens — menu bar is inaccessible during a session
- No need for in-session menu interaction (ESC is the only exit)
- Icon state (idle → filled) changes before overlay starts, reverts instantly on ESC

**Menu interaction style**
- Standard NSMenu dropdown (not custom NSPopover)
- Left-click opens the menu — user picks which command (like Rectangle, Bartender)
- Quit immediately — no confirmation dialog
- No special double-click or right-click behavior

### Claude's Discretion
- Tooltip text (whether to show "Design Ruler" on hover or skip it)
- Exact SF Symbol choice for the placeholder icon
- Any minor polish details (menu item icons, etc.)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 20 adds the NSStatusItem menu bar icon with a dropdown NSMenu to `AppDelegate`. This is a self-contained AppKit pattern: create one `NSStatusItem` stored as a strong property on AppDelegate, assign an SF Symbol template image, build an `NSMenu` programmatically with the six items from the spec, and wire Measure/Alignment Guides items to call the existing coordinator `run()` methods. The icon swap (idle ↔ filled SF Symbol) updates in the coordinator callbacks: `onSessionStart` (before `run()`) and `onSessionEnd` (in `handleExit()`).

The biggest implementation risk is the Phase 19 test scaffolding that must be stripped: `logToFile`, the `asyncAfter` test invocation, `applicationDidBecomeActive` re-invocation, and `applicationShouldTerminate → .terminateCancel`. That last one is critical — it blocks NSApp.terminate, which means the "Quit Design Ruler" menu item won't work until it is removed or replaced with proper quit logic (call NSApp.terminate only when no session is active, or always allow terminate with CursorManager.restore() cleanup first).

The `OverlayCoordinator` also needs two debug-only items cleaned up: the `drLog` function and its call sites. CLAUDE.md explicitly bans `fputs`/debug logging in production.

**Primary recommendation:** One new file `MenuBarController.swift` in `App/Sources/` owns the NSStatusItem lifecycle. AppDelegate holds a strong reference and creates it in `applicationDidFinishLaunching`. Icon state changes fire from AppDelegate callbacks that wrap the coordinator `run()` calls.

---

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `NSStatusBar.system.statusItem(withLength:)` | AppKit (macOS 14) | Creates the menu bar item | Only AppKit API for status items |
| `NSStatusItem.squareLength` | AppKit | Standard square icon width | Matches system apps (Bartender, Rectangle) |
| `NSImage(systemSymbolName:accessibilityDescription:)` | AppKit macOS 11+ | SF Symbol image for button | Template-compatible, no Bundle.module required |
| `NSMenu` + `NSMenuItem` | AppKit | Dropdown menu structure | Standard dropdown, matches spec |
| `NSMenuItem.separator()` | AppKit | Visual separators in menu | Standard pattern |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `isTemplate = true` on NSImage | Makes icon adapt to light/dark menu bar | Always — required for any menu bar icon |
| `statusItem.button?.toolTip` | Hover tooltip "Design Ruler" | Claude's discretion — recommended yes |
| `menu.addItem(withTitle:action:keyEquivalent:)` | Convenience factory for menu items | When key equiv is empty string "" |
| `NSMenuItem(title:action:keyEquivalent:)` | Full constructor | When setting target separately |

### No Alternatives Needed
The NSStatusItem API is the only macOS API for menu bar items. SwiftUI `MenuBarExtra` was introduced in macOS 13 but requires SwiftUI lifecycle (`@main App` struct), which conflicts with the existing `AppDelegate`-based entry point in `main.swift`. NSStatusItem is the correct choice here.

---

## Architecture Patterns

### Recommended Structure

```
App/Sources/
├── main.swift           # Unchanged — NSApplication.shared.run()
├── AppDelegate.swift    # Holds MenuBarController strongly, wires it up
├── Info.plist           # Unchanged — LSUIElement already YES
└── MenuBarController.swift  # NEW — owns NSStatusItem + NSMenu lifecycle
```

**Why a separate `MenuBarController.swift`:** AppDelegate is already growing (runMode setup, terminate guard). Extracting the status item logic keeps AppDelegate focused on app lifecycle and keeps MenuBarController testable in isolation. This matches how Rectangle, Clocker, and other menu bar apps structure their code.

### Pattern 1: NSStatusItem Ownership

**What:** Store NSStatusItem as a strong property. If it goes out of scope (local variable in a method), ARC releases it and the icon vanishes from the menu bar instantly.

**When to use:** Always.

```swift
// MenuBarController.swift — in App/Sources/
import AppKit
import DesignRulerCore

final class MenuBarController {
    private let statusItem: NSStatusItem
    private var settingsItem: NSMenuItem!

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        setupMenu()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = idleImage()
        button.image?.isTemplate = true
        button.toolTip = "Design Ruler"
    }

    private func idleImage() -> NSImage? {
        NSImage(systemSymbolName: "ruler", accessibilityDescription: "Design Ruler")
    }

    private func activeImage() -> NSImage? {
        let img = NSImage(systemSymbolName: "ruler.fill", accessibilityDescription: "Design Ruler active")
        img?.isTemplate = true
        return img
    }

    func setActive(_ active: Bool) {
        // Must run on main thread (called from coordinator callbacks)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.button?.image = active ? self?.activeImage() : self?.idleImage()
        }
    }
}
```

**Source:** NSStatusBar documentation, verified via polpiella.dev tutorial (MEDIUM confidence for isTemplate pattern, HIGH for NSStatusBar.system API)

### Pattern 2: NSMenu Construction

**What:** Build NSMenu programmatically. `addItem(withTitle:action:keyEquivalent:)` returns the new NSMenuItem for further configuration (like setting `isEnabled = false`).

```swift
private func setupMenu() {
    let menu = NSMenu()

    // Measure
    let measureItem = menu.addItem(
        withTitle: "Measure",
        action: #selector(launchMeasure),
        keyEquivalent: ""
    )
    measureItem.target = self

    // Alignment Guides
    let guidesItem = menu.addItem(
        withTitle: "Alignment Guides",
        action: #selector(launchAlignmentGuides),
        keyEquivalent: ""
    )
    guidesItem.target = self

    menu.addItem(NSMenuItem.separator())

    // Settings (disabled)
    settingsItem = menu.addItem(
        withTitle: "Settings...",
        action: nil,
        keyEquivalent: ""
    )
    settingsItem.isEnabled = false

    menu.addItem(NSMenuItem.separator())

    // Quit
    let quitItem = menu.addItem(
        withTitle: "Quit Design Ruler",
        action: #selector(quitApp),
        keyEquivalent: ""
    )
    quitItem.target = self

    statusItem.menu = menu
}

@objc private func launchMeasure() {
    setActive(true)
    MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")
}

@objc private func launchAlignmentGuides() {
    setActive(true)
    AlignmentGuidesCoordinator.shared.run(hideHintBar: false)
}

@objc private func quitApp() {
    NSApp.terminate(nil)
}
```

**Note on `action: nil` for disabled items:** Setting `action: nil` with `isEnabled = false` is the standard pattern for placeholder menu items. The item is grayed out and unclickable.

**Source:** NSMenu/NSMenuItem documentation, verified via multiple tutorial sources

### Pattern 3: Icon State Wiring

**What:** The icon changes state when a session starts (set filled) and when it ends (set idle). Since `handleExit()` already fires on ESC, the revert callback hooks there.

**Implementation choice:** The cleanest hook is an `onSessionEnd` callback on `OverlayCoordinator` (similar to existing `onRequestExit` on windows). However, the coordinator already has `handleExit()` and the session lifecycle is managed there. The simplest approach that avoids touching `OverlayCoordinator`:

- **Before `run()`**: call `setActive(true)` in the menu action selector
- **After ESC**: add an `onSessionEnd` closure property on `OverlayCoordinator` that `handleExit()` calls before returning

This requires a one-line addition to `OverlayCoordinator.handleExit()` and a new `public var onSessionEnd: (() -> Void)?` property — minimal change.

```swift
// In OverlayCoordinator.swift — add property:
public var onSessionEnd: (() -> Void)?

// In handleExit() — add at the END (after all cleanup):
onSessionEnd?()

// In AppDelegate / MenuBarController wiring:
MeasureCoordinator.shared.onSessionEnd = { [weak self] in
    self?.menuBarController.setActive(false)
}
AlignmentGuidesCoordinator.shared.onSessionEnd = { [weak self] in
    self?.menuBarController.setActive(false)
}
```

**Why not wire via existing window callbacks:** Window callbacks (`onRequestExit`) fire from the window, not the coordinator. The coordinator's `handleExit()` is the single true exit point (also handles inactivity timer and SIGTERM). Using `onSessionEnd` on the coordinator is the single-point hook.

### Pattern 4: AppDelegate Wiring

**What:** AppDelegate holds MenuBarController strongly and wires callbacks after creating it.

```swift
// AppDelegate.swift
import AppKit
import DesignRulerCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("standalone menu bar app")

        MeasureCoordinator.shared.runMode = .standalone
        AlignmentGuidesCoordinator.shared.runMode = .standalone

        menuBarController = MenuBarController()
        menuBarController.onMeasure = {
            MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")
        }
        menuBarController.onAlignmentGuides = {
            AlignmentGuidesCoordinator.shared.run(hideHintBar: false)
        }

        MeasureCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
        }
        AlignmentGuidesCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

**Note:** Prefer passing closures from AppDelegate into MenuBarController rather than having MenuBarController import coordinator types directly. This keeps `MenuBarController` decoupled and easier to test/replace.

### Anti-Patterns to Avoid

- **Local variable NSStatusItem:** If `statusItem` is a local `let` in `applicationDidFinishLaunching`, ARC releases it immediately after the method returns and the icon vanishes. It MUST be a stored property.
- **`NSApp.terminate` blocked by `applicationShouldTerminate → .terminateCancel`:** The Phase 19 test scaffold returns `.terminateCancel` unconditionally. This must be removed — otherwise the "Quit Design Ruler" menu item does nothing.
- **Thread safety:** Menu bar icon updates must happen on the main thread. `DispatchQueue.main.async` wrapper in `setActive(_:)` covers callbacks that fire from coordinator's exit path.
- **`action: #selector(NSApplication.shared.terminate(_:))`:** This is an alternative for the Quit item that routes through NSApp directly. It works but bypasses any cleanup in `quitApp()`. For now with no cleanup needed, either approach works.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Menu bar icon light/dark adaptation | Custom drawing for dark/light mode | `isTemplate = true` on NSImage | AppKit handles the inversion automatically |
| Disabled menu item visual state | Custom gray color | `isEnabled = false` on NSMenuItem | AppKit applies correct system gray |
| Icon state tracking | Custom state enum on MenuBarController | Direct image swap in `setActive(_:)` | Coordinator already tracks `isSessionActive`; icon just mirrors it |

---

## Common Pitfalls

### Pitfall 1: NSStatusItem Released Too Early (ARC)
**What goes wrong:** The menu bar icon appears briefly then vanishes. The app is running but there's no icon.
**Why it happens:** `NSStatusItem` created as a local `let` constant is released when the method returns.
**How to avoid:** Store as a `private let statusItem: NSStatusItem` property on a class that lives for the app's lifetime (MenuBarController, AppDelegate).
**Confidence:** HIGH (verified by multiple sources, common beginner mistake)

### Pitfall 2: applicationShouldTerminate Blocks Quit
**What goes wrong:** "Quit Design Ruler" menu item does nothing.
**Why it happens:** Phase 19 test scaffold has `applicationShouldTerminate → .terminateCancel`. This was needed to prevent accidental quit during testing, but must be removed in Phase 20.
**How to avoid:** Remove the `applicationShouldTerminate` override entirely (or replace with `.terminateNow`). The default behavior calls `applicationWillTerminate` then exits cleanly.
**Confidence:** HIGH (directly visible in existing AppDelegate.swift)

### Pitfall 3: Debug Logging Left in Production
**What goes wrong:** CLAUDE.md explicitly bans `fputs`/debug logging in production code. Build succeeds but violates project rules.
**Why it happens:** Phase 19 left `logToFile` in `AppDelegate.swift` and `drLog` in `OverlayCoordinator.swift` — both marked "TEMP: Phase 19 debug logging — remove after testing."
**How to avoid:** This phase must remove all debug logging from both files as part of cleanup.
**Confidence:** HIGH (directly visible in code, explicit CLAUDE.md rule)

### Pitfall 4: Phase 19 Test Invocation Still Active
**What goes wrong:** On app launch, Measure fires automatically (Phase 19 test behavior) instead of waiting for menu bar click.
**Why it happens:** `applicationDidFinishLaunching` has a `DispatchQueue.main.asyncAfter` call and `applicationDidBecomeActive` has a re-invocation stub — both marked "TEMP: Phase 19 test."
**How to avoid:** Remove both blocks. MenuBarController becomes the only invocation path.
**Confidence:** HIGH (directly visible in existing AppDelegate.swift)

### Pitfall 5: Icon State Not Reverting on Inactivity Timer
**What goes wrong:** After 10 minutes idle, the session ends but the icon stays in "filled/active" state.
**Why it happens:** The inactivity timer fires `handleExit()` but if `onSessionEnd` callback is not set or the icon update isn't wired, the icon doesn't revert.
**How to avoid:** `onSessionEnd` callback in `handleExit()` fires for ALL exit paths (ESC, inactivity, SIGTERM). Wire it once in AppDelegate and all paths are covered.
**Confidence:** HIGH (by inspection of `handleExit()` — it's the single exit point)

### Pitfall 6: `setActive(true)` Called but Session Rejected
**What goes wrong:** Icon shows "active" state but the coordinator's guard rejected the invocation (e.g., `anySessionActive` is true from a concurrent session). Icon is stuck active forever.
**Why it happens:** The menu action calls `setActive(true)` before `run()`, and `run()` might return early.
**How to avoid:** Don't call `setActive(true)` unconditionally. Two options:
  1. Call `setActive(true)` only after `run()` returns without rejection — but since `.standalone` mode returns immediately, this works only if we check `isSessionActive` after calling `run()`.
  2. Check `OverlayCoordinator.anySessionActive` before calling `setActive(true)`.

  **Recommended:** Keep it simple — call `setActive(true)` inside the menu action, accept the brief flicker if rejected. The `onSessionEnd` callback will revert it immediately after rejection since `handleExit()` isn't called on rejection. Actually: on rejection, `run()` returns early WITHOUT calling `handleExit()`, so `onSessionEnd` never fires. Fix: either check the session guard first, or set icon based on `isSessionActive` after the call.

  **Cleanest fix:** In the menu action: check `!OverlayCoordinator.anySessionActive` before `setActive(true)` and `run()`.
**Confidence:** HIGH (by reading the run() guard logic)

### Pitfall 7: NSMenu Target Must Be Retained
**What goes wrong:** Menu item action selectors fire on a target that has been deallocated.
**Why it happens:** If MenuBarController is the target of menu items (`menuItem.target = self`) but MenuBarController is deallocated, the pointer is dangling.
**How to avoid:** MenuBarController is stored as a strong property on AppDelegate, which lives for the app's entire lifetime. This is safe.
**Confidence:** HIGH

---

## Code Examples

Verified patterns from research:

### Complete NSStatusItem Setup

```swift
// Source: Apple NSStatusBar API + polpiella.dev tutorial pattern
import AppKit
import DesignRulerCore

final class MenuBarController {
    // CRITICAL: must be stored property (not local) — ARC releases local vars
    private let statusItem: NSStatusItem
    private weak var settingsItem: NSMenuItem?

    // Callbacks wired by AppDelegate
    var onMeasure: (() -> Void)?
    var onAlignmentGuides: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        setupMenu()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Design Ruler")
        image?.isTemplate = true          // adapts to light/dark menu bar automatically
        button.image = image
        button.toolTip = "Design Ruler"
    }

    func setActive(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            let symbolName = active ? "ruler.fill" : "ruler"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let measure = menu.addItem(withTitle: "Measure", action: #selector(launchMeasure), keyEquivalent: "")
        measure.target = self

        let guides = menu.addItem(withTitle: "Alignment Guides", action: #selector(launchAlignmentGuides), keyEquivalent: "")
        guides.target = self

        menu.addItem(NSMenuItem.separator())

        let settings = menu.addItem(withTitle: "Settings...", action: nil, keyEquivalent: "")
        settings.isEnabled = false
        settingsItem = settings

        menu.addItem(NSMenuItem.separator())

        let quit = menu.addItem(withTitle: "Quit Design Ruler", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self

        statusItem.menu = menu
    }

    @objc private func launchMeasure() {
        guard !OverlayCoordinator.anySessionActive else { return }
        setActive(true)
        onMeasure?()
    }

    @objc private func launchAlignmentGuides() {
        guard !OverlayCoordinator.anySessionActive else { return }
        setActive(true)
        onAlignmentGuides?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
```

### onSessionEnd Hook in OverlayCoordinator

```swift
// In OverlayCoordinator.swift — add:
public var onSessionEnd: (() -> Void)?

// In handleExit() — append at the end of the method body:
onSessionEnd?()
```

### AppDelegate After Phase 20

```swift
import AppKit
import DesignRulerCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("standalone menu bar app")

        MeasureCoordinator.shared.runMode = .standalone
        AlignmentGuidesCoordinator.shared.runMode = .standalone

        menuBarController = MenuBarController()
        menuBarController.onMeasure = {
            MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")
        }
        menuBarController.onAlignmentGuides = {
            AlignmentGuidesCoordinator.shared.run(hideHintBar: false)
        }

        MeasureCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
        }
        AlignmentGuidesCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

### Xcode Project: Adding MenuBarController.swift

Adding a new Swift file to the Xcode project requires editing `project.pbxproj` in three places:
1. A `PBXFileReference` entry for the new file
2. A `PBXBuildFile` entry linking it to the Sources build phase
3. Adding both IDs to the correct group (`A91DD6835439210DEA39A9ED`) and Sources build phase (`A682E2A40E8DB529D122EB58`)

UUIDs are generated as 24-character hex strings. The existing project uses this format throughout (e.g., `0817E139A5A2DB98BDB9E54B`).

---

## Exact File Changes Required

### Files to CREATE
- `App/Sources/MenuBarController.swift` — new class (see Code Examples above)
- Must be added to `App/Design Ruler.xcodeproj/project.pbxproj` in 3 places (PBXFileReference, PBXBuildFile, PBXGroup + Sources build phase)

### Files to MODIFY

**`App/Sources/AppDelegate.swift`** — Replace entirely:
- Remove: `logToFile` function and all calls
- Remove: `asyncAfter` test invocation of Measure (Phase 19 test)
- Remove: `applicationDidBecomeActive` re-invocation (Phase 19 test)
- Remove: `applicationShouldTerminate → .terminateCancel` (Phase 19 guard)
- Remove: `applicationWillTerminate` log stub
- Add: `private var menuBarController: MenuBarController!` property
- Add: `menuBarController = MenuBarController()` creation + callback wiring

**`swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift`**:
- Remove: `drLog` function and all call sites (~10 lines total)
- Add: `public var onSessionEnd: (() -> Void)?` property
- Add: `onSessionEnd?()` at the end of `handleExit()`

### Files NOT changed
- `App/Sources/main.swift` — unchanged
- `App/Sources/Info.plist` — unchanged (LSUIElement already YES)
- `swift/DesignRuler/Sources/RaycastBridge/Measure.swift` — unchanged
- `swift/DesignRuler/Sources/RaycastBridge/AlignmentGuides.swift` — unchanged
- `swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureCoordinator.swift` — unchanged
- `swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift` — unchanged
- `swift/DesignRuler/Package.swift` — unchanged

---

## SF Symbol Recommendation (Claude's Discretion)

For the placeholder icon, `"ruler"` (idle) / `"ruler.fill"` (active) is a natural fit for a pixel ruler tool. Both exist in SF Symbols and are available on macOS 14+. The template image behavior handles dark/light adaptation automatically.

**Tooltip:** Set `button.toolTip = "Design Ruler"` — this provides the hover label that Rectangle and other menu bar apps show. Low cost, high quality-of-life benefit. Recommend yes.

**Menu item icons:** Not adding per-item icons in this phase — they would need SF Symbol decorations on NSMenuItem which adds complexity. The menu items have clear text labels. Leave for Phase 22 or polish passes.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| AppKit-only NSStatusItem (pre-macOS 13) | SwiftUI `MenuBarExtra` available macOS 13+ | We use AppKit due to existing `main.swift` entry point; SwiftUI lifecycle would require rewrite |
| `statusItem.image` (deprecated) | `statusItem.button?.image` | Use button property — the old image property is deprecated |
| `statusItem.menu = nil` + click action | `statusItem.menu = menu` (auto-shows on click) | When menu is set, left-click shows it automatically; no need for custom click handler |

**Deprecated/outdated:**
- `NSStatusItem.image` property: Deprecated in favor of `statusItem.button?.image`
- `statusItem.popUpStatusItemMenu(_:)`: Deprecated; assigning `statusItem.menu` handles this automatically
- `NSStatusItem.length` constants like `NSVariableStatusItemWidth`: Use `NSStatusItem.squareLength` (static property)

---

## Open Questions

1. **Should `onSessionEnd` be added to `OverlayCoordinator` or handled differently?**
   - What we know: `handleExit()` is the single exit point for all session end paths. Adding `onSessionEnd?()` at the end covers ESC, inactivity, and SIGTERM.
   - What's unclear: Whether there are other early-exit paths in `run()` (permission check failure) that should also call `onSessionEnd`. Currently if screen recording permission is denied and `runMode == .standalone`, `run()` returns early after setting `isSessionActive = false` but never sets it to `true` first — so `onSessionEnd` would never fire for rejected runs, which is correct behavior (icon was never set active).
   - Recommendation: One `onSessionEnd?()` call at the end of `handleExit()` only. Rejection paths (guard returns) never set the icon active, so they don't need to reset it.
   - Confidence: HIGH

2. **Should the Xcode project file be hand-edited or regenerated?**
   - What we know: The project file is hand-maintained (no `project.yml` or `xcodegen` in the App directory — Phase 18 established this). Adding a file requires editing `project.pbxproj` directly.
   - Recommendation: Hand-edit `project.pbxproj` with correctly formatted UUIDs. The planner should produce the exact diff. This is low risk given only 3 sections need changes.
   - Confidence: HIGH

---

## Sources

### Primary (HIGH confidence)
- Direct code reading: `App/Sources/AppDelegate.swift` — Phase 19 test stubs identified for removal
- Direct code reading: `swift/DesignRuler/Sources/DesignRulerCore/Utilities/OverlayCoordinator.swift` — `handleExit()` structure, `drLog` cleanup scope
- Direct code reading: `swift/DesignRuler/Sources/DesignRulerCore/Measure/MeasureCoordinator.swift` — public API surface
- Direct code reading: `swift/DesignRuler/Sources/DesignRulerCore/AlignmentGuides/AlignmentGuidesCoordinator.swift` — public API surface
- Direct code reading: `App/Design Ruler.xcodeproj/project.pbxproj` — file reference structure for adding new source
- `CLAUDE.md` — MENU requirements, architecture constraints, "NO fputs/Debug Logging" rule
- Apple Developer Documentation (via WebSearch): NSStatusItem, NSStatusBar, NSMenu, NSMenuItem — current API patterns
- polpiella.dev tutorial (verified against Apple docs): NSStatusItem full AppKit pattern

### Secondary (MEDIUM confidence)
- WebSearch: NSStatusItem ARC retention pitfall — multiple consistent sources confirming stored property requirement
- WebSearch: isTemplate image pattern — consistent across all sources, matches Apple docs description

### Tertiary (LOW confidence)
- None required — all key claims verified

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — NSStatusItem API is stable, well-documented, directly applicable
- Architecture: HIGH — pattern is simple (one new file, one new coordinator property, AppDelegate cleanup)
- Pitfalls: HIGH — all identified from direct code reading of current state
- SF Symbol choice: MEDIUM — "ruler"/"ruler.fill" is reasonable but user may prefer different symbol; marked as Claude's discretion

**Research date:** 2026-02-18
**Valid until:** Stable — NSStatusItem API has not changed materially since macOS 11; no external library dependencies
