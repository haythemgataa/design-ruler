import AppKit
import DesignRulerCore

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Configure coordinators for standalone mode (event loop already running)
        MeasureCoordinator.shared.runMode = .standalone
        AlignmentGuidesCoordinator.shared.runMode = .standalone

        // TEMP: Phase 19 test — remove in Phase 20 when menu bar triggers overlays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MeasureCoordinator.shared.run(hideHintBar: false, corrections: "smart")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
