import AppKit
import DesignRulerCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prevent macOS from auto-terminating agent app when no windows are open
        ProcessInfo.processInfo.disableAutomaticTermination("standalone menu bar app")

        // Configure coordinators for standalone mode (event loop already running)
        MeasureCoordinator.shared.runMode = .standalone
        AlignmentGuidesCoordinator.shared.runMode = .standalone

        // Create menu bar and wire overlay launch callbacks
        menuBarController = MenuBarController()
        menuBarController.onMeasure = {
            MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")
        }
        menuBarController.onAlignmentGuides = {
            AlignmentGuidesCoordinator.shared.run(hideHintBar: false)
        }

        // Wire session-end callbacks to revert menu bar icon to idle state
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
