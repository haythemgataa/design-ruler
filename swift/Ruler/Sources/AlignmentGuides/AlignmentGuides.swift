import AppKit
import RaycastSwiftMacros

@raycast func alignmentGuides(hideHintBar: Bool) {
    // Warm up CGWindowListCreateImage connection (1x1 capture absorbs cold-start penalty)
    _ = CGWindowListCreateImage(
        CGRect(x: 0, y: 0, width: 1, height: 1),
        .optionOnScreenOnly, kCGNullWindowID, .bestResolution
    )

    AlignmentGuides.shared.run(hideHintBar: hideHintBar)
}

final class AlignmentGuides {
    static let shared = AlignmentGuides()
    private var windows: [AlignmentGuidesWindow] = []
    private weak var activeWindow: AlignmentGuidesWindow?
    private var firstMoveReceived = false
    private var launchTime: CFAbsoluteTime = 0
    private let minExpandedDuration: TimeInterval = 3
    private var inactivityTimer: Timer?
    private let inactivityTimeout: TimeInterval = 600 // 10 minutes
    private var sigTermSource: DispatchSourceSignal?
    private(set) var currentStyle: GuideLineStyle = .dynamic

    private init() {}

    func run(hideHintBar: Bool) {
        // Check permissions
        if !PermissionChecker.hasScreenRecordingPermission() {
            PermissionChecker.requestScreenRecordingPermission()
        }

        // Find screen where cursor is
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main!

        // CRITICAL: Capture ALL screens BEFORE creating ANY windows
        var captures: [(screen: NSScreen, image: CGImage?)] = []
        for screen in NSScreen.screens {
            let cgImage = captureScreen(screen)
            captures.append((screen, cgImage))
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Close any previous windows
        for oldWindow in windows {
            oldWindow.orderOut(nil)
            oldWindow.close()
        }
        windows.removeAll()
        activeWindow = nil
        firstMoveReceived = false
        currentStyle = .dynamic  // Reset shared color state

        // Create one window per screen
        for capture in captures {
            let isCursorScreen = capture.screen === cursorScreen
            let window = AlignmentGuidesWindow.create(
                for: capture.screen,
                screenshot: capture.image,
                hideHintBar: isCursorScreen ? hideHintBar : true  // Hint bar only on cursor screen
            )

            // Wire callbacks
            // Wire callbacks
            window.onActivate = { [weak self] window in
                self?.activateWindow(window)
            }
            window.onRequestExit = { [weak self] in
                self?.handleExit()
            }
            window.onFirstMove = { [weak self] in
                self?.handleFirstMove()
            }
            window.onActivity = { [weak self] in
                self?.resetInactivityTimer()
            }
            window.onStyleChanged = { [weak self] newStyle in
                self?.currentStyle = newStyle
            }

            windows.append(window)
        }

        // Show all windows
        for window in windows {
            window.orderFrontRegardless()
        }

        // Make cursor screen window key and show initial state
        let cursorWindow = windows.first { $0.targetScreen === cursorScreen } ?? windows.first!
        cursorWindow.makeKey()
        cursorWindow.showInitialState()
        activeWindow = cursorWindow

        launchTime = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        setupSignalHandler()
        resetInactivityTimer()
        app.run()
    }

    private func captureScreen(_ screen: NSScreen) -> CGImage? {
        let screenRect = screen.frame
        return CGWindowListCreateImage(
            screenRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }

    private func activateWindow(_ window: AlignmentGuidesWindow) {
        resetInactivityTimer()
        guard window !== activeWindow else { return }

        activeWindow?.deactivate()
        activeWindow = window
        window.makeKey()
        window.activate(firstMoveAlreadyReceived: firstMoveReceived, currentStyle: currentStyle)
    }

    private func handleExit() {
        CursorManager.shared.restore()
        for window in windows {
            window.close()
        }
        NSApp.terminate(nil)
    }

    private func handleFirstMove() {
        firstMoveReceived = true
        let elapsed = CFAbsoluteTimeGetCurrent() - launchTime
        let remaining = minExpandedDuration - elapsed
        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.activeWindow?.collapseHintBar()
            }
        } else {
            activeWindow?.collapseHintBar()
        }
    }

    private func setupSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.handleExit()
        }
        source.resume()
        sigTermSource = source
    }

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(
            withTimeInterval: inactivityTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleExit()
        }
    }
}
