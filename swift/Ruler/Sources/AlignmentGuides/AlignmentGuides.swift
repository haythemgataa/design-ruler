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
    private var inactivityTimer: Timer?
    private let inactivityTimeout: TimeInterval = 600 // 10 minutes
    private var sigTermSource: DispatchSourceSignal?

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

        // Capture cursor screen BEFORE creating window
        let screenshot = captureScreen(cursorScreen)

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

        // Create single AlignmentGuidesWindow for cursor screen (phase 9)
        // Phase 11 will add multi-monitor support
        let window = AlignmentGuidesWindow.create(
            for: cursorScreen,
            screenshot: screenshot,
            hideHintBar: hideHintBar
        )

        if let img = screenshot {
            window.setBackground(img)
        }

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

        windows.append(window)

        // Show window
        window.orderFrontRegardless()
        window.makeKey()
        activeWindow = window

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
        window.activate(firstMoveAlreadyReceived: firstMoveReceived)
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
        // Phase 11: hint bar collapse logic
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
