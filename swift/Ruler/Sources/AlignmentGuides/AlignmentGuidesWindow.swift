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
    private var hintBarView: HintBarView!
    private var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0
    private var hasReceivedFirstMove = false
    private var cursorDirection: Direction = .vertical
    private var lastCursorPosition: NSPoint = .zero

    // Callbacks
    var onActivate: ((AlignmentGuidesWindow) -> Void)?
    var onRequestExit: (() -> Void)?
    var onFirstMove: (() -> Void)?
    var onActivity: (() -> Void)?
    var onStyleChanged: ((GuideLineStyle) -> Void)?

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

        // Hint bar
        let hv = HintBarView(frame: .zero)
        self.hintBarView = hv
        if !hideHintBar {
            hv.setMode(.alignmentGuides)
            hv.configure(screenWidth: size.width, screenHeight: size.height, screenshot: screenshot)
            containerView.addSubview(hv)
        }

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

    /// Show initial state on launch.
    func showInitialState() {
        // Initialize cursor position so spacebar before mouse move works correctly
        let mouse = NSEvent.mouseLocation
        lastCursorPosition = NSPoint(
            x: mouse.x - screenBounds.origin.x,
            y: mouse.y - screenBounds.origin.y
        )
        if hintBarView.superview != nil { hintBarView.animateEntrance() }
    }

    /// Collapse hint bar from expanded to compact keycap-only layout.
    func collapseHintBar() {
        guard hintBarView.superview != nil else { return }
        hintBarView.animateToCollapsed()
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
        if guideLineManager.hasHoveredLine {
            guideLineManager.updateHover(at: NSPoint(x: -100, y: -100))
            if CursorManager.shared.state == .pointingHand {
                CursorManager.shared.transitionBackToSystem()
                updateCursor()
            }
        }
    }

    func activate(firstMoveAlreadyReceived: Bool, currentStyle: GuideLineStyle) {
        guideLineManager.setPreviewStyle(currentStyle)
        let mouse = NSEvent.mouseLocation
        let wp = NSPoint(x: mouse.x - screenBounds.origin.x, y: mouse.y - screenBounds.origin.y)
        guideLineManager.updatePreview(at: wp)
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: wp.y, screenHeight: screenBounds.height)
        }
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
        lastCursorPosition = windowPoint

        // Check hover first so preview knows whether to show "Remove" or coordinates
        guideLineManager.updateHover(at: windowPoint)
        guideLineManager.updatePreview(at: windowPoint)

        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: windowPoint.y, screenHeight: screenBounds.height)
        }

        // Cursor transitions for hover state
        if guideLineManager.hasHoveredLine {
            if CursorManager.shared.state != .pointingHand {
                CursorManager.shared.transitionToPointingHandFromSystem()
            }
        } else {
            if CursorManager.shared.state == .pointingHand {
                CursorManager.shared.transitionBackToSystem()
                updateCursor()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        let windowPoint = event.locationInWindow

        // Hover-first conflict resolution: if hovering a line, remove it instead of placing
        if guideLineManager.hasHoveredLine {
            guideLineManager.removeLine(guideLineManager.hoveredLine!, clickPoint: windowPoint)
            guideLineManager.resetRemoveMode()
            guideLineManager.updatePreview(at: windowPoint)
            // Revert cursor after removal
            CursorManager.shared.transitionBackToSystem()
            updateCursor()
            return  // Early return — do NOT place a new guide
        }

        guideLineManager.placeGuide()
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        let hintVisible = hintBarView.superview != nil

        switch Int(event.keyCode) {
        case 48: // Tab
            if hintVisible { hintBarView.pressKey(.tab) }
            guideLineManager.toggleDirection()
            cursorDirection = guideLineManager.direction
            updateCursor()
        case 49: // Spacebar
            if hintVisible { hintBarView.pressKey(.space) }
            guideLineManager.cycleStyle(cursorPosition: lastCursorPosition)
            onStyleChanged?(guideLineManager.currentStyleValue)
        case 53: // ESC
            if hintVisible { hintBarView.pressKey(.esc) }
            onRequestExit?()
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        guard hintBarView.superview != nil else { return }
        switch Int(event.keyCode) {
        case 48: hintBarView.releaseKey(.tab)
        case 49: hintBarView.releaseKey(.space)
        default: break
        }
    }
}
