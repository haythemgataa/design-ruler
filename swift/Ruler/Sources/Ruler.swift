import AppKit
import RaycastSwiftMacros

@raycast func inspect(hideHintBar: Bool, corrections: String) {
    // Warm up CGWindowListCreateImage connection (1x1 capture absorbs cold-start penalty)
    _ = CGWindowListCreateImage(
        CGRect(x: 0, y: 0, width: 1, height: 1),
        .optionOnScreenOnly, kCGNullWindowID, .bestResolution
    )

    Ruler.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}

final class Ruler {
    static let shared = Ruler()
    private var windows: [RulerWindow] = []
    private weak var activeWindow: RulerWindow?
    private var firstMoveReceived = false

    private init() {}

    func run(hideHintBar: Bool, corrections: String) {
        // Check permissions
        if !PermissionChecker.hasScreenRecordingPermission() {
            PermissionChecker.requestScreenRecordingPermission()
        }

        // When hideHintBar is toggled on, clear the backspace-dismiss flag
        // so toggling the preference off→on→off re-enables the hint bar
        if hideHintBar {
            UserDefaults.standard.removeObject(forKey: "com.raycast.design-ruler.hintBarDismissed")
        }

        let correctionMode = CorrectionMode(rawValue: corrections) ?? .smart

        // Find screen where cursor is
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main!

        // Capture ALL screens BEFORE creating any windows
        // (preserves "capture before window" pattern — no overlay in screenshots)
        var captures: [(screen: NSScreen, detector: EdgeDetector, image: CGImage?)] = []
        for screen in NSScreen.screens {
            let detector = EdgeDetector()
            detector.correctionMode = correctionMode
            let cgImage = detector.capture(screen: screen)
            captures.append((screen, detector, cgImage))
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

        // Create one RulerWindow per screen
        // Hint bar only on the screen where the cursor was at launch
        for capture in captures {
            let isCursorScreen = capture.screen === cursorScreen
            let rulerWindow = RulerWindow.create(
                for: capture.screen,
                edgeDetector: capture.detector,
                hideHintBar: isCursorScreen ? hideHintBar : true
            )

            if let cgImage = capture.image {
                rulerWindow.setBackground(cgImage)
            }

            // Wire callbacks
            rulerWindow.onActivate = { [weak self] window in
                self?.activateWindow(window)
            }
            rulerWindow.onRequestExit = { [weak self] in
                self?.handleExit()
            }
            rulerWindow.onFirstMove = { [weak self] in
                self?.handleFirstMove()
            }

            windows.append(rulerWindow)
        }

        // Show all windows
        for window in windows {
            window.orderFrontRegardless()
        }

        // Make cursor's screen window key and show initial state
        let cursorWindow = windows.first { $0.targetScreen === cursorScreen } ?? windows.first!
        cursorWindow.makeKey()
        cursorWindow.showInitialState()
        activeWindow = cursorWindow

        NSApp.activate(ignoringOtherApps: true)
        app.run()
    }

    private func activateWindow(_ window: RulerWindow) {
        guard window !== activeWindow else { return }

        // Deactivate old window
        activeWindow?.deactivate()

        // Activate new window
        activeWindow = window
        window.makeKey()
        window.activate(firstMoveAlreadyReceived: firstMoveReceived)
    }

    private func handleExit() {
        if firstMoveReceived {
            NSCursor.unhide()
        }
        for window in windows {
            window.close()
        }
        NSApp.terminate(nil)
    }

    private func handleFirstMove() {
        firstMoveReceived = true
    }
}
