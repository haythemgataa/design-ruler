import AppKit
import RaycastSwiftMacros

@raycast func alignmentGuides(hideHintBar: Bool) {
    AlignmentGuides.shared.run(hideHintBar: hideHintBar)
}

final class AlignmentGuides: OverlayCoordinator {
    static let shared = AlignmentGuides()
    private(set) var currentStyle: GuideLineStyle = .dynamic
    private var currentDirection: Direction = .vertical

    override func resetCommandState() {
        currentStyle = .dynamic
        currentDirection = .vertical
    }

    override func createWindow(for screen: NSScreen, image: CGImage?, isCursorScreen: Bool, hideHintBar: Bool) -> NSWindow {
        let window = AlignmentGuidesWindow.create(
            for: screen,
            screenshot: image,
            hideHintBar: isCursorScreen ? hideHintBar : true
        )
        return window
    }

    override func wireCallbacks(for window: NSWindow) {
        guard let guidesWindow = window as? AlignmentGuidesWindow else { return }

        // Standard 4 callbacks
        guidesWindow.onActivate = { [weak self] window in
            self?.activateWindow(window)
        }
        guidesWindow.onRequestExit = { [weak self] in
            self?.handleExit()
        }
        guidesWindow.onFirstMove = { [weak self] in
            self?.handleFirstMove()
        }
        guidesWindow.onActivity = { [weak self] in
            self?.resetInactivityTimer()
        }

        // AlignmentGuides-specific callbacks
        guidesWindow.onSpacebarPressed = { [weak self] in
            self?.handleSpacebar()
        }
        guidesWindow.onSpacebarReleased = { [weak self] in
            (self?.activeWindow as? AlignmentGuidesWindow)?.releaseSpaceKey()
        }
        guidesWindow.onTabPressed = { [weak self] in
            self?.handleTab()
        }
        guidesWindow.onTabReleased = { [weak self] in
            (self?.activeWindow as? AlignmentGuidesWindow)?.releaseTabKey()
        }
    }

    override func activateWindow(_ window: NSWindow) {
        super.activateWindow(window)
        guard let guidesWindow = window as? AlignmentGuidesWindow else { return }
        guidesWindow.activate(
            firstMoveAlreadyReceived: firstMoveReceived,
            currentStyle: currentStyle,
            currentDirection: currentDirection
        )
    }

    // MARK: - Command-specific methods

    private func handleSpacebar() {
        guard let window = activeWindow as? AlignmentGuidesWindow else { return }
        window.performCycleStyle()
        currentStyle = window.currentGuideLineStyle
    }

    private func handleTab() {
        guard let window = activeWindow as? AlignmentGuidesWindow else { return }
        window.performToggleDirection()
        currentDirection = window.currentGuideLineDirection
    }
}
