import AppKit
import KeyboardShortcuts
import SwiftUI

/// What the onboarding window shows and where the user is in it.
@Observable
final class OnboardingModel {
    enum Page { case welcome, permission, shortcuts }

    /// The full flow, or only the Screen Recording page (after onboarding, when an overlay can't
    /// start without it).
    enum Mode { case onboarding, permission }

    let mode: Mode
    let pages: [Page]
    private(set) var page: Page
    private(set) var hasPermission: Bool
    private(set) var hasRequestedPermission: Bool
    /// The command whose shortcut changed last, and when: the menu bar artwork highlights it.
    private(set) var lastShortcutChange: (name: KeyboardShortcuts.Name, date: Date)?

    var onFinish: () -> Void = {}

    init(mode: Mode) {
        let granted = CGPreflightScreenCaptureAccess()
        let asked = AppPreferences.shared.hasRequestedScreenRecording
        self.mode = mode
        hasPermission = granted
        hasRequestedPermission = asked
        switch mode {
        case .permission:
            pages = [.permission]
            page = .permission
        case .onboarding:
            // Already allowed before ever asking (a reinstall): nothing to do on that page. Asked
            // before (the app was reopened for it to apply): pick up on that page
            pages = granted && !asked ? [.welcome, .shortcuts] : [.welcome, .permission, .shortcuts]
            page = asked ? .permission : .welcome
        }
    }

    var isLastPage: Bool { page == pages.last }

    func advance() {
        guard !isLastPage, let index = pages.firstIndex(of: page) else {
            onFinish()
            return
        }
        page = pages[index + 1]
    }

    /// Jumps to the Screen Recording page, when the user tries an overlay from the welcome page.
    func showPermissionPage() {
        guard pages.contains(.permission), page == .welcome else { return }
        page = .permission
    }

    /// Asks macOS, which shows its prompt and adds Design Ruler to the Screen Recording list only
    /// while the app isn't in it: the first time, or after its entry was removed (each beta build
    /// needs that). When no prompt takes the focus, opens the list in System Settings instead.
    func requestPermission() {
        AppPreferences.shared.hasRequestedScreenRecording = true
        hasRequestedPermission = true
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if NSApp.isActive { NSWorkspace.shared.open(Self.screenRecordingSettingsURL) }
        }
    }

    func refreshPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasPermission { hasPermission = granted }
    }

    func shortcutChanged(_ name: KeyboardShortcuts.Name) {
        lastShortcutChange = (name, Date())
    }

    /// macOS applies a new Screen Recording permission to an app only once it reopens. Waits for
    /// this process to exit before opening the app again, so the two never run side by side.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"",
            Bundle.main.bundlePath,
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    )!
}

/// The first-launch window: welcome, Screen Recording, shortcuts. Also reopened on the Screen
/// Recording page alone when an overlay can't start without it.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?
    private var permissionTimer: Timer?

    func show(_ mode: OnboardingModel.Mode) {
        if let model {
            if mode == .permission { model.showPermissionPage() }
        } else {
            createWindow(mode)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow(_ mode: OnboardingModel.Mode) {
        let model = OnboardingModel(mode: mode)
        model.onFinish = { [weak self] in self?.window?.close() }

        let content = NSHostingController(rootView: OnboardingView(model: model))
        content.sizingOptions = []  // the window's content size, set below, includes the title bar
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = mode == .permission ? "Screen Recording" : "Welcome to Design Ruler"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: OnboardingLayout.width, height: OnboardingLayout.height))

        // macOS Sequoia fix: resolve constraints before centering
        window.updateConstraintsIfNeeded()
        window.center()

        self.window = window
        self.model = model

        // Screen Recording changes in System Settings, so check while the window is open (cheap)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.model?.refreshPermission()
        }
        permissionTimer?.tolerance = 0.5
    }

    func windowWillClose(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil

        // Shortcuts are optional (Settings has them too), so closing counts once the overlays can run
        if let model, model.mode == .onboarding, model.hasPermission {
            AppPreferences.shared.hasCompletedOnboarding = true
        }

        // Released on the next turn: the close can come from a button inside this window's view
        DispatchQueue.main.async { [weak self] in
            self?.window = nil
            self?.model = nil
        }
    }
}
