import AppKit
import DesignRulerCore
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var settingsWindowController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prevent macOS from auto-terminating agent app when no windows are open
        ProcessInfo.processInfo.disableAutomaticTermination("standalone menu bar app")

        // Configure coordinators for standalone mode (event loop already running)
        MeasureCoordinator.shared.runMode = .standalone
        AlignmentGuidesCoordinator.shared.runMode = .standalone

        // First launch: enable launch at login by default
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            try? SMAppService.mainApp.register()
        }

        // Create settings window controller
        settingsWindowController = SettingsWindowController()

        // Create menu bar and wire overlay launch callbacks
        menuBarController = MenuBarController()
        menuBarController.onMeasure = {
            let prefs = AppPreferences.shared
            MeasureCoordinator.shared.run(hideHintBar: prefs.hideHintBar, corrections: prefs.corrections)
        }
        menuBarController.onAlignmentGuides = {
            AlignmentGuidesCoordinator.shared.run(hideHintBar: AppPreferences.shared.hideHintBar)
        }
        menuBarController.onOpenSettings = { [weak self] in
            self?.settingsWindowController.showSettings()
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
