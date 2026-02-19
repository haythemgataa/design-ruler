import AppKit
import DesignRulerCore
import KeyboardShortcuts

final class MenuBarController: NSObject, NSMenuDelegate {
    // CRITICAL: must be stored property — ARC releases local NSStatusItem immediately
    private let statusItem: NSStatusItem

    // Stored for menuNeedsUpdate to re-apply shortcuts on every menu open
    private var measureItem: NSMenuItem!
    private var guidesItem: NSMenuItem!

    // Callbacks wired by AppDelegate (keeps this class decoupled from coordinators)
    var onMeasure: (() -> Void)?
    var onAlignmentGuides: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupButton()
        setupMenu()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Design Ruler")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Design Ruler"
    }

    /// Update the menu bar icon to reflect active/idle session state.
    /// Safe to call from any thread — dispatches to main.
    func setActive(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button else { return }
            let symbolName = active ? "ruler.fill" : "ruler"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Design Ruler")
            image?.isTemplate = true
            button.image = image
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Read any previously-recorded shortcuts so keyEquivalent is set at
        // creation time (NSMenu renders key equivalents set during addItem).
        let (mKey, mMods) = MainActor.assumeIsolated { Self.shortcutParts(for: .measure) }
        let (gKey, gMods) = MainActor.assumeIsolated { Self.shortcutParts(for: .alignmentGuides) }

        measureItem = menu.addItem(
            withTitle: "Measure",
            action: #selector(launchMeasure),
            keyEquivalent: mKey
        )
        measureItem.target = self
        measureItem.keyEquivalentModifierMask = mMods

        guidesItem = menu.addItem(
            withTitle: "Alignment Guides",
            action: #selector(launchAlignmentGuides),
            keyEquivalent: gKey
        )
        guidesItem.target = self
        guidesItem.keyEquivalentModifierMask = gMods

        menu.addItem(NSMenuItem.separator())

        let settingsItem = menu.addItem(
            withTitle: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let updateItem = menu.addItem(
            withTitle: "Check for Updates\u{2026}",
            action: #selector(checkForUpdates),
            keyEquivalent: "r"
        )
        updateItem.target = self

        menu.addItem(NSMenuItem.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit Design Ruler",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            Self.applyShortcut(to: measureItem, for: .measure)
            Self.applyShortcut(to: guidesItem, for: .alignmentGuides)
        }
    }

    // Numpad key codes → characters (nsMenuItemKeyEquivalent returns nil for these)
    private static let numpadKeys: [Int: String] = [
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4",
        87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        65: ".", 67: "*", 69: "+", 75: "/", 78: "-", 81: "=",
    ]

    @MainActor
    private static func shortcutParts(for name: KeyboardShortcuts.Name) -> (String, NSEvent.ModifierFlags) {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return ("", [])
        }
        if let key = shortcut.nsMenuItemKeyEquivalent {
            return (key, shortcut.modifiers)
        }
        if let key = numpadKeys[shortcut.carbonKeyCode] {
            return (key, shortcut.modifiers)
        }
        return ("", [])
    }

    @MainActor
    private static func applyShortcut(to item: NSMenuItem, for name: KeyboardShortcuts.Name) {
        let (key, mods) = shortcutParts(for: name)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = mods
    }

    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(.measure)
        KeyboardShortcuts.disable(.alignmentGuides)
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.measure)
        KeyboardShortcuts.enable(.alignmentGuides)
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

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
