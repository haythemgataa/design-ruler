import AppKit
import Sparkle
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?

    func showSettings(updater: SPUUpdater) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if let window {
            window.updateConstraintsIfNeeded()
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Preferences-style toolbar tabs: symbol above label, tinted selection
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        addTab("General", symbol: "gearshape", to: tabs, GeneralSettingsView(updater: updater))
        addTab("Measure", symbol: "ruler", to: tabs, MeasureSettingsView())
        addTab("Alignment", symbol: "rectangle.split.3x1", to: tabs, AlignmentSettingsView())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        // The title row shows the selected tab's name, with the close button beside it and the tabs
        // below. titleVisibility .hidden would drop the row and center the close button on the tabs
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        tabs.fitWindowToSelectedTab(animated: false)

        // macOS Sequoia fix: resolve constraints before centering
        window.updateConstraintsIfNeeded()
        window.center()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func addTab<Content: View>(_ title: String, symbol: String, to tabs: SettingsTabViewController,
                                       _ content: Content) {
        let controller = NSHostingController(rootView: content.environment(\.settingsPaneDidResize) { [weak tabs] in
            // Not from inside SwiftUI's update: the animated resize runs its own event loop
            DispatchQueue.main.async { tabs?.fitWindowToSelectedTab(animated: true) }
        })
        // The tab controller sizes the window from the pane's fittingSize, which needs the intrinsic
        // size (empty options make it zero). Never .preferredContentSize: AppKit turns it into
        // constraints that outrank the window's own size, so they resize it instantly and snap an
        // animated resize to its end
        controller.sizingOptions = .standardBounds
        controller.title = title  // the tab controller passes the selected tab's title to the window
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}

/// Resizes the window to the selected tab's Form, keeping the top edge in place, and animates
/// the change like a classic preferences window.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        // Next turn: the toolbar draws its new selection first (the animation blocks the main thread)
        DispatchQueue.main.async { [weak self] in self?.fitWindowToSelectedTab(animated: true) }
    }

    func fitWindowToSelectedTab(animated: Bool) {
        guard let window = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              let pane = tabViewItems[selectedTabViewItemIndex].viewController?.view
        else { return }

        // The Form's ideal size, only accurate once the tab is in the window (the selected one is).
        // Rounded up to whole points, as the window frame is, or every check would see a change
        let size = pane.fittingSize
        let contentRect = NSRect(x: 0, y: 0, width: size.width.rounded(.up), height: size.height.rounded(.up))
        var frame = window.frameRect(forContentRect: contentRect)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        guard frame.size != window.frame.size else { return }

        let animate = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
    }
}
