import AppKit
import DesignRulerCore
import KeyboardShortcuts
import ServiceManagement
import Sparkle
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private var menuBarController: MenuBarController!
    private var hotkeyController: HotkeyController!
    private var settingsWindowController: SettingsWindowController!
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    // MARK: - SPUStandardUserDriverDelegate

    /// Declares support for gentle reminders so Sparkle doesn't warn about background update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Called when Sparkle finds an update in the background (scheduled check).
    /// Post a local notification so the user sees the alert even while in another app.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Design Ruler \(update.displayVersionString) Available"
            content.body = "Open Design Ruler to install the update."
            let request = UNNotificationRequest(
                identifier: "sparkle-update-\(update.versionString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

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

        // Create hotkey controller first so menu bar callbacks can reference it safely
        hotkeyController = HotkeyController()

        // Create menu bar and wire overlay launch callbacks
        menuBarController = MenuBarController()
        menuBarController.onMeasure = { [weak self] in
            self?.hotkeyController.sessionStarted(command: .measure)
            let prefs = AppPreferences.shared
            MeasureCoordinator.shared.run(hideHintBar: prefs.hideHintBar, corrections: prefs.corrections)
        }
        menuBarController.onAlignmentGuides = { [weak self] in
            self?.hotkeyController.sessionStarted(command: .alignmentGuides)
            AlignmentGuidesCoordinator.shared.run(hideHintBar: AppPreferences.shared.hideHintBar)
        }
        menuBarController.onCheckForUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
        menuBarController.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsWindowController.showSettings(updater: self.updaterController.updater)
        }
        hotkeyController.onLaunchMeasure = { [weak self] in
            self?.hotkeyController.sessionStarted(command: .measure)
            let prefs = AppPreferences.shared
            MeasureCoordinator.shared.run(hideHintBar: prefs.hideHintBar, corrections: prefs.corrections)
        }
        hotkeyController.onLaunchAlignmentGuides = { [weak self] in
            self?.hotkeyController.sessionStarted(command: .alignmentGuides)
            AlignmentGuidesCoordinator.shared.run(hideHintBar: AppPreferences.shared.hideHintBar)
        }
        hotkeyController.onSetActive = { [weak self] active in
            self?.menuBarController.setActive(active)
        }
        hotkeyController.registerHandlers()

        // Wire session-end callbacks to revert menu bar icon and hotkey state
        MeasureCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
            self?.hotkeyController.sessionEnded()
        }
        AlignmentGuidesCoordinator.shared.onSessionEnd = { [weak self] in
            self?.menuBarController.setActive(false)
            self?.hotkeyController.sessionEnded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
