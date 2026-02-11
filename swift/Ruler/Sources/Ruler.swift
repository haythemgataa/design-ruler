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
    private let edgeDetector = EdgeDetector()
    private var window: RulerWindow?

    private init() {}

    func run(hideHintBar: Bool, corrections: String) {
        // Check permissions
        if !PermissionChecker.hasScreenRecordingPermission() {
            PermissionChecker.requestScreenRecordingPermission()
        }

        // Find screen where cursor is
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main!

        // When hideHintBar is toggled on, clear the backspace-dismiss flag
        // so toggling the preference off→on→off re-enables the hint bar
        if hideHintBar {
            UserDefaults.standard.removeObject(forKey: "com.raycast.design-ruler.hintBarDismissed")
        }

        // Configure edge detector
        edgeDetector.correctionMode = CorrectionMode(rawValue: corrections) ?? .smart

        // Capture BEFORE creating window — CG connection is warm, this takes ~3ms
        let cgImage = edgeDetector.capture(screen: cursorScreen)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Create window with screenshot already available
        let rulerWindow = RulerWindow.create(
            for: cursorScreen,
            edgeDetector: edgeDetector,
            hideHintBar: hideHintBar
        )
        self.window = rulerWindow

        if let cgImage = cgImage {
            rulerWindow.setBackground(cgImage)
        }

        rulerWindow.orderFrontRegardless()
        rulerWindow.makeKey()
        rulerWindow.showInitialState()
        NSApp.activate(ignoringOtherApps: true)
        app.run()
    }
}
