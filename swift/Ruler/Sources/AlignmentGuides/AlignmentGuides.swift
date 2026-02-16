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
    private weak var cursorWindow: AlignmentGuidesWindow?
    private var firstMoveReceived = false
    private var launchTime: CFAbsoluteTime = 0
    private let minExpandedDuration: TimeInterval = 3
    private var inactivityTimer: Timer?
    private let inactivityTimeout: TimeInterval = 600 // 10 minutes
    private var sigTermSource: DispatchSourceSignal?
    private(set) var currentStyle: GuideLineStyle = .dynamic
    private var currentDirection: Direction = .vertical

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
        currentDirection = .vertical

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
            window.onSpacebarPressed = { [weak self] in
                self?.handleSpacebar()
            }
            window.onSpacebarReleased = { [weak self] in
                self?.activeWindow?.releaseSpaceKey()
            }
            window.onTabPressed = { [weak self] in
                self?.handleTab()
            }
            window.onTabReleased = { [weak self] in
                self?.activeWindow?.releaseTabKey()
            }

            windows.append(window)
        }

        // Show all windows
        for window in windows {
            window.orderFrontRegardless()
        }

        // Make cursor screen window key and show initial state
        let cw = windows.first { $0.targetScreen === cursorScreen } ?? windows.first!
        cw.makeKey()
        cw.showInitialState()
        activeWindow = cw
        cursorWindow = cw

        launchTime = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        setupSignalHandler()
        resetInactivityTimer()
        app.run()
    }

    private func captureScreen(_ screen: NSScreen) -> CGImage? {
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let frame = screen.frame
        let mainHeight = mainScreen.frame.height

        // Convert AppKit coords (bottom-left origin) to CG coords (top-left origin)
        let cgRect = CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )

        return CGWindowListCreateImage(
            cgRect,
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
        window.activate(firstMoveAlreadyReceived: firstMoveReceived, currentStyle: currentStyle, currentDirection: currentDirection)
    }

    private func handleSpacebar() {
        guard let window = activeWindow else { return }
        window.performCycleStyle()
        currentStyle = window.currentGuideLineStyle
    }

    private func handleTab() {
        activeWindow?.performToggleDirection()
        if let window = activeWindow {
            currentDirection = window.currentGuideLineDirection
        }
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
                self?.cursorWindow?.collapseHintBar()
            }
        } else {
            cursorWindow?.collapseHintBar()
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
