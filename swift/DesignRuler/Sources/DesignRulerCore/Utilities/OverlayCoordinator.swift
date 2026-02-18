import AppKit

/// Protocol for overlay windows that both MeasureWindow and AlignmentGuidesWindow conform to.
/// Allows the coordinator base to call common methods without knowing the concrete window type.
package protocol OverlayWindowProtocol: AnyObject {
    var targetScreen: NSScreen! { get }
    func showInitialState()
    func collapseHintBar()
    func deactivate()
}

/// Base class encapsulating the shared lifecycle for fullscreen overlay commands.
///
/// Both Measure and AlignmentGuides delegate startup orchestration, signal handling,
/// inactivity timeout, first-move hint bar collapse, and exit to this base.
/// Each subclass provides its window factory and command-specific callback wiring.
///
/// The `run()` method enforces the locked startup order:
///   warmup capture (1x1) -> permission check -> detect cursor screen ->
///   captureScreens() -> createWindows() -> .accessory policy -> cleanup old windows ->
///   show all windows -> make key window -> launchTime -> activate -> signal handler ->
///   inactivity timer -> app.run()
package class OverlayCoordinator {
    package var windows: [NSWindow] = []
    package weak var activeWindow: NSWindow?
    package weak var cursorWindow: NSWindow?
    package var firstMoveReceived = false
    package var launchTime: CFAbsoluteTime = 0
    package let minExpandedDuration: TimeInterval = 3
    package var inactivityTimer: Timer?
    package let inactivityTimeout: TimeInterval = 600 // 10 minutes
    package var sigTermSource: DispatchSourceSignal?

    package init() {}

    // MARK: - Orchestrated Startup Sequence

    /// Run the overlay command. Enforces the locked startup order.
    /// Subclasses should NOT override this — override the hook methods instead.
    package func run(hideHintBar: Bool) {
        // 1. Warmup capture (1x1 pixel, absorbs CGWindowListCreateImage cold-start penalty)
        _ = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly, kCGNullWindowID, .bestResolution
        )

        // 2. Permission check
        if !PermissionChecker.hasScreenRecordingPermission() {
            PermissionChecker.requestScreenRecordingPermission()
        }

        // 3. Detect cursor screen
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main!

        // 4. Reset command-specific state from previous run (before new captures)
        resetCommandState()

        // 5. Capture all screens (subclass may override for command-specific capture)
        let captures = captureAllScreens()

        // 6. Create windows from captures (subclass provides window factory)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // 7. Cleanup old windows
        for oldWindow in windows {
            oldWindow.orderOut(nil)
            oldWindow.close()
        }
        windows.removeAll()
        activeWindow = nil
        firstMoveReceived = false

        // 8. Create one window per screen
        for capture in captures {
            let isCursorScreen = capture.screen === cursorScreen
            let window = createWindow(
                for: capture.screen,
                image: capture.image,
                isCursorScreen: isCursorScreen,
                hideHintBar: hideHintBar
            )
            wireCallbacks(for: window)
            windows.append(window)
        }

        // 9. Show all windows
        for window in windows {
            window.orderFrontRegardless()
        }

        // 10. Make cursor screen window key and show initial state
        let cw = windows.first { window in
            (window as? OverlayWindowProtocol)?.targetScreen === cursorScreen
        } ?? windows.first!
        cw.makeKey()
        (cw as? OverlayWindowProtocol)?.showInitialState()
        activeWindow = cw
        cursorWindow = cw

        // 11. Launch time, activate, signal handler, inactivity timer, run loop
        launchTime = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        setupSignalHandler()
        resetInactivityTimer()
        app.run()
    }

    // MARK: - Overridable Methods (subclass hooks)

    /// Capture all screens. Default uses ScreenCapture.captureScreen() for each.
    /// Measure overrides to capture via EdgeDetector instead.
    package func captureAllScreens() -> [(screen: NSScreen, image: CGImage?)] {
        var captures: [(screen: NSScreen, image: CGImage?)] = []
        for screen in NSScreen.screens {
            let cgImage = ScreenCapture.captureScreen(screen)
            captures.append((screen, cgImage))
        }
        return captures
    }

    /// Create a window for the given screen. Subclasses MUST override.
    package func createWindow(for screen: NSScreen, image: CGImage?, isCursorScreen: Bool, hideHintBar: Bool) -> NSWindow {
        fatalError("Subclasses must override createWindow(for:image:isCursorScreen:hideHintBar:)")
    }

    /// Wire callbacks for common coordination events.
    /// Default wires onRequestExit, onFirstMove, onActivity.
    /// The onActivate callback is command-specific (typed to the window subclass),
    /// so subclasses override this to add onActivate and any additional callbacks.
    package func wireCallbacks(for window: NSWindow) {
        // Base does nothing — subclasses wire typed callbacks
    }

    /// Activate a window during multi-monitor cursor transitions.
    /// Default handles timer reset, guard, deactivate old, makeKey.
    /// AlignmentGuides overrides to pass currentStyle/currentDirection.
    package func activateWindow(_ window: NSWindow) {
        resetInactivityTimer()
        guard window !== activeWindow else { return }

        // Deactivate old window
        (activeWindow as? OverlayWindowProtocol)?.deactivate()

        // Activate new window
        activeWindow = window
        window.makeKey()
    }

    /// Reset command-specific state between runs.
    /// AlignmentGuides overrides to reset currentStyle/currentDirection.
    package func resetCommandState() {
        // Default: no command-specific state to reset
    }

    // MARK: - Shared Methods (not overridden)

    /// Clean exit: restore cursor, close all windows, terminate app.
    package func handleExit() {
        CursorManager.shared.restore()
        for window in windows {
            window.close()
        }
        NSApp.terminate(nil)
    }

    /// Handle first mouse move: set flag, collapse hint bar after minimum display duration.
    package func handleFirstMove() {
        firstMoveReceived = true
        let elapsed = CFAbsoluteTimeGetCurrent() - launchTime
        let remaining = minExpandedDuration - elapsed
        if remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                (self?.cursorWindow as? OverlayWindowProtocol)?.collapseHintBar()
            }
        } else {
            (cursorWindow as? OverlayWindowProtocol)?.collapseHintBar()
        }
    }

    /// Install SIGTERM handler for clean cursor restoration on process kill.
    package func setupSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.handleExit()
        }
        source.resume()
        sigTermSource = source
    }

    /// Reset the 10-minute inactivity watchdog timer.
    package func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(
            withTimeInterval: inactivityTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleExit()
        }
    }
}
