# Phase 21: Settings and Preferences - Research

**Researched:** 2026-02-19
**Domain:** macOS Settings Window (SwiftUI in AppKit host), UserDefaults, SMAppService, Sparkle 2
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Single scrollable page, no tabs -- all sections visible at once
- 4 sections on the page: General, Measure, Shortcuts, About
- macOS grouped style -- rounded boxes with section headers (like System Settings groups)
- Always centered on screen when opened (no position memory)
- Shortcuts section exists as a placeholder in Phase 21 -- populated with hotkey recorders in Phase 22
- Hide Hint Bar: toggle switch (On/Off, macOS System Settings style)
- Corrections Mode: radio buttons showing all three options (Smart, Include, None)
- Storage: UserDefaults only, local -- no iCloud sync
- **General section:** Launch at Login (toggle, top of page), Hide Hint Bar (toggle), Auto-check for Updates (toggle)
- **Measure section:** Corrections Mode (radio buttons: Smart, Include, None)
- **Shortcuts section:** Placeholder for Phase 22 global hotkey recorders
- **About section:** App icon, name, version, copyright, GitHub link, website/contact, Check for Updates button
- Launch at Login enabled by default on first launch (standard for menu bar apps)
- Launch at Login toggle lives in the General section at the top of the settings page
- Uses SMAppService.mainApp (decided in PROJECT.md)
- About section shows: app icon, name, version number, copyright, GitHub link, website/contact
- Check for Updates: both a menu bar dropdown item AND a button in the About section
- Auto-check for updates: user choice via toggle in General section (Sparkle's SUUpdater automaticallyChecksForUpdates)

### Claude's Discretion
- Exact spacing, padding, and typography within sections
- Settings window dimensions
- SwiftUI vs AppKit implementation choice for the settings window
- How the Shortcuts placeholder section communicates "configure in Phase 22"

### Deferred Ideas (OUT OF SCOPE)
- Welcome window / first-launch onboarding -- user wants a one-time window explaining the app on first launch. This is a separate capability requiring its own design (layout, content, illustrations, dismiss behavior). Consider as a future phase or part of Phase 24 (Distribution).
</user_constraints>

## Summary

Phase 21 adds a Settings window accessible from the menu bar dropdown, wires UserDefaults-backed preferences to the overlay coordinators, integrates SMAppService for launch-at-login, and integrates Sparkle 2 for update checking. The settings window is a single scrollable SwiftUI Form hosted in an NSWindow via NSHostingView, styled with `.formStyle(.grouped)` to achieve the macOS System Settings grouped appearance.

The three main integration points are: (1) a `SettingsWindowController` that creates/manages the NSWindow lifecycle (show/bring to front/center), (2) an `AppPreferences` class backed by UserDefaults that the coordinators read at session start, and (3) Sparkle's `SPUStandardUpdaterController` initialized in AppDelegate and wired to both the menu bar "Check for Updates" item and the settings About section button.

**Primary recommendation:** Use SwiftUI `Form` with `.formStyle(.grouped)` hosted in an NSWindow via NSHostingView. This gives native macOS grouped appearance (rounded boxes with section headers) with minimal code. The Settings library (sindresorhus) is unnecessary overhead for a single-page settings view.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI `Form` | macOS 14+ built-in | Settings UI with grouped sections | Native grouped style matches System Settings appearance; `.formStyle(.grouped)` on macOS 14+ |
| NSHostingView | macOS 14+ built-in | Host SwiftUI Form inside NSWindow | Standard bridge pattern for embedding SwiftUI in AppKit apps |
| UserDefaults | macOS built-in | Preference storage | Simplest persistence for key-value settings; survives app restart; no sync needed |
| SMAppService | macOS 13+ (ServiceManagement) | Launch at login | Apple's current API replacing SMJobBless/SMLoginItemSetEnabled; no helper bundle needed |
| Sparkle | 2.x (latest stable) | Update checking | De facto standard for macOS app auto-updates outside App Store |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Combine | macOS built-in | Observe Sparkle's canCheckForUpdates | KVO publisher for SPUUpdater property binding to SwiftUI |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftUI Form in NSWindow | sindresorhus/Settings library | Adds dependency for tab management we don't need (single page); Form + NSHostingView is simpler |
| SwiftUI Form in NSWindow | Pure AppKit (NSStackView + NSTextField) | Much more code for same result; no native grouped style; harder to maintain |
| UserDefaults direct | @AppStorage in SwiftUI | @AppStorage is great for SwiftUI-only views but we need AppDelegate/coordinator to read values too; UserDefaults works everywhere |

**Installation:**
Sparkle is added as an SPM dependency to the Xcode project (File > Add Packages > `https://github.com/sparkle-project/Sparkle`). This adds an `XCRemoteSwiftPackageReference` to the .pbxproj. No changes to the SPM Package.swift (Raycast build path stays untouched).

## Architecture Patterns

### Recommended Project Structure
```
App/Sources/
  AppDelegate.swift          -- Sparkle controller init, settings window creation, menu wiring
  MenuBarController.swift    -- Enable Settings + Check for Updates items, wire actions
  SettingsWindowController.swift  -- NSWindow lifecycle (create, show, center, close)
  SettingsView.swift         -- SwiftUI Form with all 4 sections
  AppPreferences.swift       -- UserDefaults wrapper (hideHintBar, corrections, etc.)
```

### Pattern 1: NSWindow + NSHostingView for Settings
**What:** Create a plain NSWindow, set its contentView to `NSHostingView(rootView: SettingsView())`, configure window properties (title, style, size, non-resizable), and center on screen.
**When to use:** Any time you need a SwiftUI view in an AppKit-lifecycle app that doesn't use SwiftUI App protocol.
**Example:**
```swift
// SettingsWindowController.swift
import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func showSettings(updater: SPUUpdater) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(updater: updater)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Design Ruler Settings"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        // macOS Sequoia fix: resolve constraints before centering
        window.updateConstraintsIfNeeded()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
```

### Pattern 2: AppPreferences with UserDefaults
**What:** A centralized class reading/writing UserDefaults keys, consumed by both SwiftUI views (via @Observable or bindings) and AppKit code (AppDelegate reading values for coordinator invocation).
**When to use:** When preferences need to be accessed from both SwiftUI and imperative AppKit code paths.
**Example:**
```swift
// AppPreferences.swift
import Foundation

@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    var hideHintBar: Bool {
        get { UserDefaults.standard.bool(forKey: "hideHintBar") }
        set { UserDefaults.standard.set(newValue, forKey: "hideHintBar") }
    }

    var corrections: String {
        get { UserDefaults.standard.string(forKey: "corrections") ?? "smart" }
        set { UserDefaults.standard.set(newValue, forKey: "corrections") }
    }
}
```

### Pattern 3: Sparkle Programmatic Setup
**What:** Create `SPUStandardUpdaterController` in AppDelegate init (or applicationDidFinishLaunching), wire menu item via target/action, pass `updater` to SwiftUI settings view.
**When to use:** Non-IB apps that need Sparkle without storyboards.
**Example:**
```swift
// In AppDelegate
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire menu item for "Check for Updates..."
        menuBarController.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }
}
```

### Pattern 4: SMAppService Launch at Login
**What:** Read status from `SMAppService.mainApp.status`, call `.register()` / `.unregister()` on toggle change. Always read from system status (not local UserDefaults) because user can change login items in System Settings.
**When to use:** macOS 13+ apps that want launch-at-login without a helper bundle.
**Example:**
```swift
// In SettingsView
import ServiceManagement

Toggle("Launch at Login", isOn: Binding(
    get: { SMAppService.mainApp.status == .enabled },
    set: { newValue in
        if newValue {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
))
```

### Pattern 5: SwiftUI Grouped Form
**What:** `Form { ... }.formStyle(.grouped)` gives macOS System Settings-style rounded grouped boxes with section headers.
**When to use:** macOS 14+ settings windows that should match System Settings visual language.
**Example:**
```swift
Form {
    Section("General") {
        Toggle("Launch at Login", isOn: ...)
        Toggle("Hide Hint Bar", isOn: ...)
        Toggle("Automatically Check for Updates", isOn: ...)
    }
    Section("Measure") {
        Picker("Border Corrections", selection: ...) {
            Text("Smart").tag("smart")
            Text("Include").tag("include")
            Text("None").tag("none")
        }
        .pickerStyle(.radioGroup)
    }
    Section("Shortcuts") {
        Text("Configure in a future update")
            .foregroundStyle(.secondary)
    }
    Section("About") {
        // App icon, version, links, update button
    }
}
.formStyle(.grouped)
```

### Anti-Patterns to Avoid
- **Storing launch-at-login state in UserDefaults:** Users can change login items in System Settings at any time. Always read from `SMAppService.mainApp.status`, not a local boolean. The toggle binding should call `.register()` / `.unregister()` and read `.status` directly.
- **Creating a new NSWindow on every "Settings" click:** Reuse the existing window instance. Check `window.isVisible` and bring to front instead of creating a new one. Set `isReleasedWhenClosed = false` to keep the window alive after close.
- **Calling `window.center()` before constraints resolve on macOS 15+:** On Sequoia, SwiftUI view layout computes lazily. Call `window.updateConstraintsIfNeeded()` before `window.center()` to get correct centering.
- **Overriding Sparkle's initial defaults programmatically:** Set initial values via Info.plist keys (SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks). Only modify `updater.automaticallyChecksForUpdates` in response to user preference changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Launch at login | Custom LaunchAgent plist or helper app | SMAppService.mainApp | Apple's supported API; no helper bundle; works without sandbox; shows in System Settings Login Items |
| Auto-update | Custom download + replace logic | Sparkle 2 (SPUStandardUpdaterController) | Delta updates, EdDSA signing, appcast protocol, UI for update progress; decades of battle-testing |
| Grouped form styling | Custom NSStackView with rounded backgrounds | SwiftUI Form + `.formStyle(.grouped)` | Native System Settings appearance for free; responsive layout; accessibility built-in |
| Preference persistence | Custom plist writing or Core Data | UserDefaults | Simple key-value store with automatic disk persistence; KVO-compatible |

**Key insight:** The settings window is a SwiftUI form in an NSWindow shell. All the complex parts (update checking, login item management) have established Apple/community solutions that handle edge cases we shouldn't recreate.

## Common Pitfalls

### Pitfall 1: NSWindow Released on Close
**What goes wrong:** The settings window disappears and the NSWindow is deallocated when the user clicks the close button. Next time they open settings, a new window must be created from scratch, or worse, the app crashes accessing a nil reference.
**Why it happens:** NSWindow's `isReleasedWhenClosed` defaults to `true` for non-document windows.
**How to avoid:** Set `window.isReleasedWhenClosed = false`. Store the window as a strong property on the controller. On subsequent "open settings" calls, check `window.isVisible` and call `makeKeyAndOrderFront` instead of creating a new window.
**Warning signs:** Window appears but controls lose state between open/close cycles.

### Pitfall 2: SMAppService Status Not Refreshed
**What goes wrong:** User disables the login item in System Settings > Login Items while the app's settings window is open. The toggle still shows "enabled."
**Why it happens:** The SwiftUI view doesn't re-read `SMAppService.mainApp.status` unless explicitly triggered.
**How to avoid:** Re-read status in `onAppear` and when the window becomes active (monitor `NSApplication.didBecomeActiveNotification` or use SwiftUI's `scenePhase` / `appearsActive` environment). The nilcoalescing.com pattern uses `appearsActive` environment value.
**Warning signs:** Toggle is out of sync with System Settings after switching between apps.

### Pitfall 3: Sparkle Requires Info.plist Keys
**What goes wrong:** Sparkle silently does nothing or crashes because required Info.plist keys are missing.
**Why it happens:** SUFeedURL and SUPublicEDKey must be in Info.plist for Sparkle to function.
**How to avoid:** Add placeholder SUFeedURL (can be updated before distribution in Phase 24) and generate EdDSA keys using Sparkle's `generate_keys` tool. At minimum, SUFeedURL must point to a valid URL (even if appcast doesn't exist yet).
**Warning signs:** "Check for Updates" does nothing; no network requests visible.

### Pitfall 4: Window Centering Fails on macOS 15+
**What goes wrong:** Settings window appears off-center or in the top-left corner.
**Why it happens:** macOS Sequoia (15+) computes SwiftUI view layout lazily. Calling `window.center()` before constraints resolve uses wrong dimensions.
**How to avoid:** Call `window.updateConstraintsIfNeeded()` before `window.center()`.
**Warning signs:** Window position is wrong on Sequoia but correct on Sonoma.

### Pitfall 5: Menu Bar Items Still Disabled After Phase 20
**What goes wrong:** The "Settings..." menu item from Phase 20 has `action: nil` and `isEnabled = false`. Forgetting to update these means the menu item stays grayed out.
**Why it happens:** Phase 20 intentionally created a disabled placeholder. Phase 21 must enable it.
**How to avoid:** Update setupMenu() in MenuBarController: set action to a `@objc func openSettings()` method and set `isEnabled = true` (or simply provide a non-nil action and a target). Also add a new "Check for Updates..." menu item.

### Pitfall 6: Coordinator Reads Stale Preferences
**What goes wrong:** User changes hideHintBar to true in Settings, then invokes Measure. The hint bar still appears.
**Why it happens:** AppDelegate's `onMeasure` closure hardcodes `hideHintBar: false, corrections: "smart"` (Phase 20 state). It needs to read from AppPreferences at invocation time.
**How to avoid:** Change the closure to read `AppPreferences.shared.hideHintBar` and `AppPreferences.shared.corrections` at call time, not at wire time.

### Pitfall 7: Launch at Login "Enabled by Default" on First Launch
**What goes wrong:** User wants launch at login enabled by default, but Apple guidelines say apps should not auto-launch without consent.
**Why it happens:** Tension between user expectation (menu bar apps should auto-start) and Apple's review rules.
**How to avoid:** This app is distributed outside the App Store (via DMG/GitHub, Phase 24), so App Store review rules don't apply. For first launch, check if a `hasLaunchedBefore` UserDefaults key exists. If not, call `SMAppService.mainApp.register()` and set the flag. The user can always disable it in Settings.

## Code Examples

### Complete SwiftUI SettingsView Structure
```swift
import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsView: View {
    let updater: SPUUpdater

    @State private var hideHintBar: Bool
    @State private var corrections: String
    @State private var automaticallyChecksForUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        // Read initial values from UserDefaults
        _hideHintBar = State(initialValue: UserDefaults.standard.bool(forKey: "hideHintBar"))
        _corrections = State(initialValue: UserDefaults.standard.string(forKey: "corrections") ?? "smart")
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            // --- General ---
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                ))
                Toggle("Hide Hint Bar", isOn: $hideHintBar)
                    .onChange(of: hideHintBar) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "hideHintBar")
                    }
                Toggle("Automatically Check for Updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }
            }

            // --- Measure ---
            Section("Measure") {
                Picker("Border Corrections", selection: $corrections) {
                    Text("Smart").tag("smart")
                    Text("Include").tag("include")
                    Text("None").tag("none")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: corrections) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "corrections")
                }
            }

            // --- Shortcuts (placeholder) ---
            Section("Shortcuts") {
                Text("Shortcuts will be available in a future update.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            // --- About ---
            Section("About") {
                HStack(spacing: 12) {
                    // App icon from NSApp.applicationIconImage
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Design Ruler")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Version \(Bundle.main.shortVersionString)")
                            .foregroundStyle(.secondary)
                        Text("Copyright ... Haythem")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Link("GitHub", destination: URL(string: "https://github.com/...")!)
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
```

### Menu Bar Updates (MenuBarController changes)
```swift
// In setupMenu(), replace the disabled Settings item:
let settingsItem = menu.addItem(
    withTitle: "Settings\u{2026}",
    action: #selector(openSettings),
    keyEquivalent: ","   // Cmd+, standard
)
settingsItem.target = self

// Add Check for Updates before Quit
let updateItem = menu.addItem(
    withTitle: "Check for Updates\u{2026}",
    action: #selector(checkForUpdates),
    keyEquivalent: ""
)
updateItem.target = self

// Callbacks
var onOpenSettings: (() -> Void)?
var onCheckForUpdates: (() -> Void)?

@objc private func openSettings() {
    onOpenSettings?()
}
@objc private func checkForUpdates() {
    onCheckForUpdates?()
}
```

### AppDelegate Wiring Updates
```swift
// AppDelegate.swift additions
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var settingsWindowController: SettingsWindowController!
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ... existing code ...

        // First launch: enable launch at login by default
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            try? SMAppService.mainApp.register()
        }

        // Settings window controller
        settingsWindowController = SettingsWindowController()

        // Wire menu callbacks (existing + new)
        menuBarController.onMeasure = {
            let prefs = AppPreferences.shared
            MeasureCoordinator.shared.run(
                hideHintBar: prefs.hideHintBar,
                corrections: prefs.corrections
            )
        }
        menuBarController.onAlignmentGuides = {
            let prefs = AppPreferences.shared
            AlignmentGuidesCoordinator.shared.run(hideHintBar: prefs.hideHintBar)
        }
        menuBarController.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsWindowController.showSettings(updater: self.updaterController.updater)
        }
        menuBarController.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
    }
}
```

### Sparkle Info.plist Keys Required
```xml
<!-- Add to App/Sources/Info.plist -->
<key>SUFeedURL</key>
<string>https://example.com/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>PLACEHOLDER_BASE64_EDDSA_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SMLoginItemSetEnabled (deprecated) | SMAppService.mainApp | macOS 13 (2022) | No helper bundle needed; shows in System Settings Login Items |
| SUUpdater (Sparkle 1) | SPUStandardUpdaterController (Sparkle 2) | Sparkle 2.0 (2022) | XPC service support, EdDSA signing, better sandboxing |
| NSPreferencesModule (private API) | SwiftUI Settings scene / NSHostingView | macOS 14+ | Native grouped form styling matches System Settings |
| .formStyle(.insetGrouped) on macOS | .formStyle(.grouped) | macOS Ventura beta rename | Same visual result, different name on macOS |

**Deprecated/outdated:**
- `SMLoginItemSetEnabled`: Replaced by SMAppService in macOS 13+
- Sparkle 1 `SUUpdater`: Replaced by SPUStandardUpdaterController in Sparkle 2
- Manual NSGridView settings layout: SwiftUI Form with .grouped does this natively

## Open Questions

1. **Sparkle SUFeedURL and EdDSA key setup**
   - What we know: Sparkle requires SUFeedURL and SUPublicEDKey in Info.plist. Keys are generated via Sparkle's `generate_keys` tool.
   - What's unclear: The actual appcast URL and key generation are distribution concerns (Phase 24). Should we use placeholder values now?
   - Recommendation: Use placeholder SUFeedURL (e.g., `https://github.com/USER/design-ruler/releases/latest/appcast.xml`) and a placeholder SUPublicEDKey. The actual values will be configured in Phase 24. The "Check for Updates" button and auto-check toggle should work correctly with the Sparkle API even if the feed URL returns a 404 (Sparkle handles this gracefully with an error dialog).

2. **Window dimensions**
   - What we know: The user wants a single scrollable page with 4 sections.
   - What's unclear: Exact height needed to show all content without scrolling (or minimal scrolling).
   - Recommendation: Set width to 480pt (similar to System Settings panels). Let SwiftUI's `.fixedSize(horizontal: false, vertical: true)` determine content height. Set a reasonable min/max height or let the window size to content. Test and adjust.

3. **Sparkle XPC services for non-sandboxed app**
   - What we know: Sparkle documentation says XPC services can be removed for non-sandboxed apps "to save space."
   - What's unclear: Whether SPM binary target includes XPC services by default.
   - Recommendation: Accept whatever SPM delivers. XPC services are harmless in non-sandboxed apps. Optimization is a Phase 24 concern if needed.

## Sources

### Primary (HIGH confidence)
- [Apple SMAppService documentation](https://developer.apple.com/documentation/servicemanagement/smappservice) - API reference for register/unregister/status
- [Sparkle documentation - Programmatic Setup](https://sparkle-project.org/documentation/programmatic-setup/) - SPUStandardUpdaterController init, checkForUpdates, canCheckForUpdates
- [Sparkle documentation - Customization](https://sparkle-project.org/documentation/customization/) - Info.plist keys: SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks
- [Sparkle documentation - Settings UI](https://sparkle-project.github.io/documentation/preferences-ui/) - SwiftUI binding pattern for automaticallyChecksForUpdates
- [Sparkle 2.x Package.swift](https://github.com/sparkle-project/Sparkle/blob/2.x/Package.swift) - SPM binaryTarget with XCFramework URL pattern
- [Apple NSHostingView documentation](https://developer.apple.com/documentation/swiftui/nshostingview) - Bridge SwiftUI into NSView
- [Apple GroupedFormStyle documentation](https://developer.apple.com/documentation/swiftui/groupedformstyle) - macOS grouped form appearance

### Secondary (MEDIUM confidence)
- [Nil Coalescing - Launch at Login Setting](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) - Complete SMAppService SwiftUI implementation with appearsActive refresh
- [Furnace Creek - Centering NSWindows on Sequoia](https://furnacecreek.org/blog/2024-12-07-centering-nswindows-with-nshostingcontrollers-on-sequoia) - updateConstraintsIfNeeded() before center() fix
- Existing codebase: `App/Sources/MenuBarController.swift`, `App/Sources/AppDelegate.swift` - Current menu structure and coordinator wiring

### Tertiary (LOW confidence)
- None. All findings verified against official docs or existing codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components are Apple frameworks or Sparkle (industry standard), verified against official docs
- Architecture: HIGH - NSHostingView bridge pattern is well-documented; code examples verified against existing codebase structure
- Pitfalls: HIGH - Sequoia centering issue verified via multiple sources; SMAppService status refresh pattern from official samples; window lifecycle issues from AppKit fundamentals

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable APIs, low churn risk)
