import AppKit
import DesignRulerCore

final class MenuBarController {
    // CRITICAL: must be stored property — ARC releases local NSStatusItem immediately
    private let statusItem: NSStatusItem

    // Callbacks wired by AppDelegate (keeps this class decoupled from coordinators)
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

        let measureItem = menu.addItem(
            withTitle: "Measure",
            action: #selector(launchMeasure),
            keyEquivalent: ""
        )
        measureItem.target = self

        let guidesItem = menu.addItem(
            withTitle: "Alignment Guides",
            action: #selector(launchAlignmentGuides),
            keyEquivalent: ""
        )
        guidesItem.target = self

        menu.addItem(NSMenuItem.separator())

        let settingsItem = menu.addItem(
            withTitle: "Settings\u{2026}",
            action: nil,
            keyEquivalent: ""
        )
        settingsItem.isEnabled = false

        menu.addItem(NSMenuItem.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit Design Ruler",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self

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
