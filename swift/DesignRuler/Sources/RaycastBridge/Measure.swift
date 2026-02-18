import AppKit
import RaycastSwiftMacros
import DesignRulerCore

@raycast func inspect(hideHintBar: Bool, corrections: String) {
    Measure.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}

final class Measure: OverlayCoordinator {
    static let shared = Measure()
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
        let measureWindow = MeasureWindow.create(
            for: screen,
            edgeDetector: detector,
            hideHintBar: isCursorScreen ? hideHintBar : true,
            screenshot: image
        )

        if let cgImage = image {
            measureWindow.setBackground(cgImage)
        }

        return measureWindow
    }

    override func wireCallbacks(for window: NSWindow) {
        guard let measureWindow = window as? MeasureWindow else { return }
        measureWindow.onActivate = { [weak self] window in
            self?.activateWindow(window)
        }
        measureWindow.onRequestExit = { [weak self] in
            self?.handleExit()
        }
        measureWindow.onFirstMove = { [weak self] in
            self?.handleFirstMove()
        }
        measureWindow.onActivity = { [weak self] in
            self?.resetInactivityTimer()
        }
    }

    override func activateWindow(_ window: NSWindow) {
        super.activateWindow(window)
        guard let measureWindow = window as? MeasureWindow else { return }
        measureWindow.activate(firstMoveAlreadyReceived: firstMoveReceived)
    }
}
