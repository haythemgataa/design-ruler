import AppKit
import QuartzCore

/// Transparent view that passes events through to the window.
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// Fullscreen borderless window for alignment guides feature.
/// Routes mouse + keyboard events to GuideLineManager.
final class AlignmentGuidesWindow: NSWindow {
    private(set) var targetScreen: NSScreen!
    private var guideLineManager: GuideLineManager!
    private var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0
    private var hasReceivedFirstMove = false
    private var cursorDirection: Direction = .vertical

    // Callbacks
    var onActivate: ((AlignmentGuidesWindow) -> Void)?
    var onRequestExit: (() -> Void)?
    var onFirstMove: (() -> Void)?
    var onActivity: (() -> Void)?

    /// Create a fullscreen alignment guides window for the given screen.
    static func create(for screen: NSScreen, screenshot: CGImage?, hideHintBar: Bool) -> AlignmentGuidesWindow {
        let window = AlignmentGuidesWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
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

        window.setupViews(screenFrame: screen.frame, screenshot: screenshot, hideHintBar: hideHintBar)
        window.setupTrackingArea()
        return window
    }

    private func setupViews(screenFrame: CGRect, screenshot: CGImage?, hideHintBar: Bool) {
        let size = screenFrame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))

        // Background image view
        if let img = screenshot {
            let bgView = NSView(frame: NSRect(origin: .zero, size: size))
            bgView.wantsLayer = true
            bgView.layer?.contents = img
            bgView.layer?.contentsGravity = .resize
            containerView.addSubview(bgView)
        }

        // Guideline view (transparent, passes events through)
        let guidelineView = PassthroughView(frame: NSRect(origin: .zero, size: size))
        guidelineView.wantsLayer = true
        containerView.addSubview(guidelineView)

        // GuideLineManager
        let scale = backingScaleFactor
        self.guideLineManager = GuideLineManager(
            parentLayer: guidelineView.layer!,
            scale: scale,
            screenSize: size
        )

        // Hint bar (phase 11)
        // if !hideHintBar { ... }

        contentView = containerView
    }

    private func setupTrackingArea() {
        guard let cv = contentView else { return }
        let area = NSTrackingArea(
            rect: cv.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        cv.addTrackingArea(area)
    }

    /// Set frozen screenshot as background.
    func setBackground(_ cgImage: CGImage) {
        guard let container = contentView else { return }

        let bgView = NSView(frame: NSRect(origin: .zero, size: screenBounds.size))
        bgView.wantsLayer = true
        bgView.layer?.contents = cgImage
        bgView.layer?.contentsGravity = .resize

        container.addSubview(bgView, positioned: .below, relativeTo: container.subviews.first)
    }

    // MARK: - Cursor Management

    override func resetCursorRects() {
        guard let cv = contentView else { return }
        let cursor: NSCursor = cursorDirection == .vertical ? .resizeLeftRight : .resizeUpDown
        cv.addCursorRect(cv.bounds, cursor: cursor)
    }

    private func updateCursor() {
        guard let cv = contentView else { return }
        invalidateCursorRects(for: cv)
    }

    // MARK: - Multi-monitor activation (phase 11)

    override func mouseEntered(with event: NSEvent) {
        onActivate?(self)
    }

    func deactivate() {
        // Phase 11: handle multi-monitor deactivation
    }

    func activate(firstMoveAlreadyReceived: Bool) {
        // Phase 11: handle multi-monitor activation
    }

    // MARK: - Event Handling

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown(with: event)
        default: super.sendEvent(event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // Throttle to ~60fps
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= 0.014 else { return }
        lastMoveTime = now
        onActivity?()

        if !hasReceivedFirstMove {
            hasReceivedFirstMove = true
            onFirstMove?()
        }

        let windowPoint = event.locationInWindow
        guideLineManager.updatePreview(at: windowPoint)
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        guideLineManager.placeGuide()
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()

        switch Int(event.keyCode) {
        case 48: // Tab
            guideLineManager.toggleDirection()
            cursorDirection = guideLineManager.direction
            updateCursor()
        case 49: // Spacebar (stub for phase 10)
            // guideLineManager.cycleStyle()
            break
        case 53: // ESC
            onRequestExit?()
        default:
            break
        }
    }
}
