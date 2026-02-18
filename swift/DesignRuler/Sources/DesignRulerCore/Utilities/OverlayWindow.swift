import AppKit
import QuartzCore

/// Base class for fullscreen overlay windows shared by both Measure and Alignment Guides.
///
/// Provides: shared NSWindow configuration (10 properties), tracking area setup,
/// hint bar creation/positioning/collapse, throttled mouse move with first-move detection,
/// ESC key handling, and mouseEntered delegation. Subclasses override hook methods
/// (handleMouseMoved, handleKeyDown, handleActivation, showInitialState, deactivate)
/// for command-specific behavior.
package class OverlayWindow: NSWindow, OverlayWindowProtocol {
    package private(set) var targetScreen: NSScreen!
    package var hintBarView: HintBarView!
    package var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0
    package private(set) var hasReceivedFirstMove = false
    package private(set) var lastCursorPosition: NSPoint = .zero

    // Callbacks for multi-monitor coordination
    package var onRequestExit: (() -> Void)?
    package var onFirstMove: (() -> Void)?
    package var onActivity: (() -> Void)?

    // MARK: - Shared Configuration

    /// Apply standard overlay window properties. Called by subclass `create()` factories
    /// immediately after NSWindow init.
    package static func configureOverlay(_ window: OverlayWindow, for screen: NSScreen) {
        window.setFrame(screen.frame, display: false)
        window.targetScreen = screen
        window.screenBounds = screen.frame
        window.level = .statusBar
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // MARK: - Tracking Area

    package func setupTrackingArea() {
        guard let cv = contentView else { return }
        // `.cursorUpdate` enables cursorUpdate(with:) callbacks — without it, the system
        // would apply its own cursor logic and our CursorManager state would be overridden.
        let area = NSTrackingArea(
            rect: cv.bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
            owner: self, userInfo: nil
        )
        cv.addTrackingArea(area)
    }

    /// Take over cursor management from the system. With `.cursorUpdate` on the tracking
    /// area, the system calls this instead of applying its own cursor logic. Not calling
    /// super is intentional — it prevents the system from resetting our managed cursor.
    override package func cursorUpdate(with event: NSEvent) {
        CursorManager.shared.applyCursor()
    }

    // MARK: - Hint Bar

    /// Collapse the hint bar from expanded to compact keycap-only layout.
    package func collapseHintBar() {
        guard hintBarView.superview != nil else { return }
        hintBarView.animateToCollapsed()
    }

    /// Create and configure the hint bar. Parameterized by mode so both commands share one path.
    /// Critical: setMode() MUST be called BEFORE configure() per CLAUDE.md.
    package func setupHintBar(mode: HintBarMode, screenSize: CGSize, screenshot: CGImage?, hideHintBar: Bool, container: NSView) {
        let hv = HintBarView(frame: .zero)
        self.hintBarView = hv
        if !hideHintBar {
            if mode != .inspect { hv.setMode(mode) }
            hv.configure(screenWidth: screenSize.width, screenHeight: screenSize.height, screenshot: screenshot)
            container.addSubview(hv)
        }
    }

    /// Show hint bar entrance animation.
    package func hintBarEntrance() {
        if hintBarView.superview != nil { hintBarView.animateEntrance() }
    }

    // MARK: - Background

    /// Set frozen screenshot as background using CALayer (bypasses NSImage DPI scaling).
    package func setBackground(_ cgImage: CGImage, below referenceView: NSView) {
        guard let container = contentView else { return }
        let bgView = NSView(frame: NSRect(origin: .zero, size: screenBounds.size))
        bgView.wantsLayer = true
        bgView.layer?.contents = cgImage
        bgView.layer?.contentsGravity = .resize
        container.addSubview(bgView, positioned: .below, relativeTo: referenceView)
    }

    // MARK: - Window Properties

    override package var canBecomeKey: Bool { true }
    override package var canBecomeMain: Bool { true }

    // MARK: - Event Handling

    override package func mouseEntered(with event: NSEvent) {
        handleActivation()
    }

    override package func mouseMoved(with event: NSEvent) {
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= 0.014 else { return }
        lastMoveTime = now
        onActivity?()

        if !hasReceivedFirstMove {
            hasReceivedFirstMove = true
            onFirstMove?()
        }

        let windowPoint = event.locationInWindow
        lastCursorPosition = windowPoint

        handleMouseMoved(to: windowPoint)

        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: windowPoint.y, screenHeight: screenBounds.height)
        }
    }

    override package func keyDown(with event: NSEvent) {
        onActivity?()
        if Int(event.keyCode) == 53 { // ESC
            if hintBarView.superview != nil { hintBarView.pressKey(.esc) }
            onRequestExit?()
            return
        }
        handleKeyDown(with: event)
    }

    // MARK: - Subclass Helpers

    /// Mark first move as received. For subclass activation paths where a sibling window
    /// already processed the first move.
    package func markFirstMoveReceived() {
        hasReceivedFirstMove = true
    }

    /// Initialize lastCursorPosition from current mouse location (window-local coords).
    /// Used by subclasses in showInitialState/activate to avoid (0,0) artifacts.
    package func initCursorPosition() {
        let mouse = NSEvent.mouseLocation
        lastCursorPosition = NSPoint(
            x: mouse.x - screenBounds.origin.x,
            y: mouse.y - screenBounds.origin.y
        )
    }

    // MARK: - Overridable Hooks

    /// Called on mouseEntered. Subclasses override to call their typed onActivate callback.
    package func handleActivation() {
        // Subclasses override to call their typed onActivate callback
    }

    /// Called on mouseMoved after throttle, first-move detection, and cursor position tracking.
    /// Hint bar positioning runs AFTER this so the subclass processes the point first.
    package func handleMouseMoved(to windowPoint: NSPoint) {
        // Subclasses override for command-specific mouse move handling
    }

    /// Called on keyDown for all non-ESC keys.
    package func handleKeyDown(with event: NSEvent) {
        // Subclasses override for command-specific key handling
    }

    /// Show command-specific initial state on launch.
    package func showInitialState() {
        // Subclasses override for command-specific initial state
    }

    /// Deactivate this window when cursor leaves for another screen.
    package func deactivate() {
        // Subclasses override for command-specific deactivation
    }
}
