import AppKit
import RaycastSwiftMacros

@raycast func inspect(hideHintBar: Bool, corrections: String) {
    Ruler.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}

final class Ruler: OverlayCoordinator {
    static let shared = Ruler()
    private var correctionMode: CorrectionMode = .smart
    private var detectors: [ObjectIdentifier: EdgeDetector] = [:]

    func run(hideHintBar: Bool, corrections: String) {
        correctionMode = CorrectionMode(rawValue: corrections) ?? .smart
        super.run(hideHintBar: hideHintBar)
    }

    override func resetCommandState() {
        detectors.removeAll()
    }

    override func captureAllScreens() -> [(screen: NSScreen, image: CGImage?)] {
        var captures: [(screen: NSScreen, image: CGImage?)] = []
        for screen in NSScreen.screens {
            let detector = EdgeDetector()
            detector.correctionMode = correctionMode
            let cgImage = detector.capture(screen: screen)
            detectors[ObjectIdentifier(screen)] = detector
            captures.append((screen, cgImage))
        }
        return captures
    }

    override func createWindow(for screen: NSScreen, image: CGImage?, isCursorScreen: Bool, hideHintBar: Bool) -> NSWindow {
        let detector = detectors[ObjectIdentifier(screen)] ?? EdgeDetector()
        let rulerWindow = RulerWindow.create(
            for: screen,
            edgeDetector: detector,
            hideHintBar: isCursorScreen ? hideHintBar : true,
            screenshot: image
        )

        if let cgImage = image {
            rulerWindow.setBackground(cgImage)
        }

        return rulerWindow
    }

    override func wireCallbacks(for window: NSWindow) {
        guard let rulerWindow = window as? RulerWindow else { return }
        rulerWindow.onActivate = { [weak self] window in
            self?.activateWindow(window)
        }
        rulerWindow.onRequestExit = { [weak self] in
            self?.handleExit()
        }
        rulerWindow.onFirstMove = { [weak self] in
            self?.handleFirstMove()
        }
        rulerWindow.onActivity = { [weak self] in
            self?.resetInactivityTimer()
        }
    }

    override func activateWindow(_ window: NSWindow) {
        super.activateWindow(window)
        guard let rulerWindow = window as? RulerWindow else { return }
        rulerWindow.activate(firstMoveAlreadyReceived: firstMoveReceived)
    }
}
