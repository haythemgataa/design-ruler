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

        measureItem = menu.addItem(
            withTitle: "Measure",
            action: #selector(launchMeasure),
            keyEquivalent: ""
        )
        measureItem.target = self

        guidesItem = menu.addItem(
            withTitle: "Alignment Guides",
            action: #selector(launchAlignmentGuides),
            keyEquivalent: ""
        )
        guidesItem.target = self

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
            keyEquivalent: ""
        )
        updateItem.target = self

        menu.addItem(NSMenuItem.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit Design Ruler",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            Self.applyShortcut(to: measureItem, baseTitle: "Measure", for: .measure)
            Self.applyShortcut(to: guidesItem, baseTitle: "Alignment Guides", for: .alignmentGuides)
        }
    }

    @MainActor
    private static func applyShortcut(to item: NSMenuItem, baseTitle: String, for name: KeyboardShortcuts.Name) {
        if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
            item.title = "\(baseTitle)\t\(shortcut.description)"
        } else {
            item.title = baseTitle
        }
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
