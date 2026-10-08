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
    private let onboardingWindowController = OnboardingWindowController()
    private var updaterController: SPUStandardUpdaterController!

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

        // Start Sparkle at launch so scheduled update checks run without opening Settings. Unsigned
        // beta builds can't update themselves, so their updater never starts (see AppBuild)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: AppBuild.canAutoUpdate,
            updaterDelegate: nil,
            userDriverDelegate: self
        )

        // First launch: enable launch at login by default
        let prefs = AppPreferences.shared
        let isFirstLaunch = !prefs.hasLaunchedBefore
        if isFirstLaunch {
            prefs.hasLaunchedBefore = true
            try? SMAppService.mainApp.register()
        }

        // Create settings window controller
        settingsWindowController = SettingsWindowController()

        // Create hotkey controller first so menu bar callbacks can reference it safely
        hotkeyController = HotkeyController()

        // Create menu bar and wire overlay launch callbacks
        menuBarController = MenuBarController()
        menuBarController.onMeasure = { [weak self] in
            self?.launchMeasure()
        }
        menuBarController.onAlignmentGuides = { [weak self] in
            self?.launchAlignmentGuides()
        }
        menuBarController.onCheckForUpdates = { [weak self] in
            if AppBuild.canAutoUpdate {
                self?.updaterController.checkForUpdates(nil)
            } else {
                NSWorkspace.shared.open(AppBuild.releasesURL)
            }
        }
        menuBarController.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsWindowController.showSettings(updater: self.updaterController.updater)
        }
        hotkeyController.onLaunchMeasure = { [weak self] in
            self?.launchMeasure()
        }
        hotkeyController.onLaunchAlignmentGuides = { [weak self] in
            self?.launchAlignmentGuides()
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
            // Save the color and direction the session ended with even while Remember is off,
            // so turning it on later resumes the last-used ones
            let prefs = AppPreferences.shared
            prefs.guideStyle = AlignmentGuidesCoordinator.shared.styleName
            prefs.guideDirection = AlignmentGuidesCoordinator.shared.directionName
            self?.menuBarController.setActive(false)
            self?.hotkeyController.sessionEnded()
        }

        // Onboarding until it's finished. Decided once: an install from before it existed that can
        // already record the screen is set up. Never again after that, or reopening the app for the
        // permission (not a first launch, permission on) would end onboarding before its last page
        if prefs.hasCompletedOnboarding == nil {
            prefs.hasCompletedOnboarding = !isFirstLaunch && CGPreflightScreenCaptureAccess()
        }
        if prefs.hasCompletedOnboarding == false {
            onboardingWindowController.show(.onboarding)
        }
    }

    // MARK: - Overlay Launch

    /// Overlays need Screen Recording. Without it, the onboarding window shows how to turn it on
    /// (onboarding's own page while it's open) instead of an overlay that can't start.
    private func canRecordScreen() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        onboardingWindowController.show(.permission)
        return false
    }

    /// Shared by the menu bar and the global hotkey. Preferences are read here, at invocation
    /// time, so changes made in Settings apply to the next session
    private func launchMeasure() {
        guard canRecordScreen() else { return }
        hotkeyController.sessionStarted(command: .measure)
        let prefs = AppPreferences.shared
        MeasureCoordinator.shared.run(hideHintBar: !prefs.showHintBar, corrections: prefs.corrections)
    }

    /// Starts with the remembered color and direction when Remember is on, else dynamic and vertical
    private func launchAlignmentGuides() {
        guard canRecordScreen() else { return }
        hotkeyController.sessionStarted(command: .alignmentGuides)
        let prefs = AppPreferences.shared
        let remembers = prefs.remembersGuideStyle
        AlignmentGuidesCoordinator.shared.run(
            hideHintBar: !prefs.showHintBar,
            style: remembers ? prefs.guideStyle : "dynamic",
            direction: remembers ? prefs.guideDirection : "vertical"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
