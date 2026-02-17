import AppKit
import QuartzCore

/// Transparent view that passes events through to the window.
private class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// Fullscreen overlay window for the Alignment Guides command.
/// Subclasses OverlayWindow for shared window config, tracking, throttle, hint bar, and ESC.
/// Contains only: guide line management, direction/style cycling, cursor direction state.
/// All resize cursor management goes through CursorManager (no resetCursorRects/NSCursor.set).
final class AlignmentGuidesWindow: OverlayWindow {
    private var guideLineManager: GuideLineManager!
    private var cursorDirection: Direction = .vertical

    // Typed callback for multi-monitor activation
    var onActivate: ((AlignmentGuidesWindow) -> Void)?

    // Command-specific callbacks
    var onSpacebarPressed: (() -> Void)?
    var onSpacebarReleased: (() -> Void)?
    var onTabPressed: (() -> Void)?
    var onTabReleased: (() -> Void)?

    /// Create a fullscreen alignment guides window for the given screen.
    static func create(for screen: NSScreen, screenshot: CGImage?, hideHintBar: Bool) -> AlignmentGuidesWindow {
        let window = AlignmentGuidesWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        OverlayWindow.configureOverlay(window, for: screen)
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

        let scale = backingScaleFactor
        self.guideLineManager = GuideLineManager(
            parentLayer: guidelineView.layer!,
            scale: scale,
            screenSize: size
        )

        contentView = containerView

        // Use base's shared hint bar setup with alignment guides mode
        setupHintBar(mode: .alignmentGuides, screenSize: size, screenshot: screenshot, hideHintBar: hideHintBar, container: containerView)
    }

    // MARK: - Coordinator-dispatched actions

    /// Cycle color style (called by coordinator on the active window).
    func performCycleStyle() {
        if hintBarView.superview != nil { hintBarView.pressKey(.space) }
        guideLineManager.cycleStyle(cursorPosition: lastCursorPosition)
    }

    func releaseSpaceKey() {
        if hintBarView.superview != nil { hintBarView.releaseKey(.space) }
    }

    /// Toggle line direction (called by coordinator on the active window).
    func performToggleDirection() {
        if hintBarView.superview != nil { hintBarView.pressKey(.tab) }
        guideLineManager.toggleDirection()
        cursorDirection = guideLineManager.direction
        // Switch resize cursor via CursorManager
        CursorManager.shared.switchResize(to: cursorDirection)
    }

    func releaseTabKey() {
        if hintBarView.superview != nil { hintBarView.releaseKey(.tab) }
    }

    var currentGuideLineStyle: GuideLineStyle {
        guideLineManager.currentStyleValue
    }

    var currentGuideLineDirection: Direction {
        guideLineManager.direction
    }

    // MARK: - Overridable Hooks

    override func handleActivation() {
        onActivate?(self)
    }

    override func showInitialState() {
        initCursorPosition()
        guideLineManager.showPreview()
        guideLineManager.updatePreview(at: lastCursorPosition)
        // Show resize cursor immediately via CursorManager (replaces resetCursorRects approach)
        if cursorDirection == .vertical {
            CursorManager.shared.transitionToResizeLeftRight()
        } else {
            CursorManager.shared.transitionToResizeUpDown()
        }
        hintBarEntrance()
    }

    override func handleMouseMoved(to windowPoint: NSPoint) {
        // Check hover first so preview knows whether to show "Remove" or coordinates
        guideLineManager.updateHover(at: windowPoint)
        guideLineManager.updatePreview(at: windowPoint)

        // Cursor transitions for hover state — use CursorManager resize states
        if guideLineManager.hasHoveredLine {
            if CursorManager.shared.state != .pointingHand {
                CursorManager.shared.transitionToPointingHandFromResize()
            }
        } else {
            if CursorManager.shared.state == .pointingHand {
                CursorManager.shared.transitionToResize(cursorDirection)
            }
        }
    }

    override func handleKeyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 48: onTabPressed?()
        case 49: onSpacebarPressed?()
        default: break
        }
    }

    override func deactivate() {
        guideLineManager.hidePreview()
        if guideLineManager.hasHoveredLine {
            guideLineManager.updateHover(at: NSPoint(x: -100, y: -100))
            if CursorManager.shared.state == .pointingHand {
                CursorManager.shared.transitionToResize(cursorDirection)
            }
        }
    }

    // MARK: - Multi-monitor Activation

    func activate(firstMoveAlreadyReceived: Bool, currentStyle: GuideLineStyle, currentDirection: Direction) {
        initCursorPosition()
        guideLineManager.setPreviewStyle(currentStyle)
        guideLineManager.setDirection(currentDirection)
        cursorDirection = currentDirection
        // Restore resize cursor via CursorManager
        CursorManager.shared.switchResize(to: cursorDirection)
        guideLineManager.showPreview()
        guideLineManager.updatePreview(at: lastCursorPosition)
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: lastCursorPosition.y, screenHeight: screenBounds.height)
        }
    }

    // MARK: - Event Handling (Subclass-specific)

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown(with: event)
        default: super.sendEvent(event)
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
            // Revert to resize cursor via CursorManager
            CursorManager.shared.transitionToResize(cursorDirection)
            return
        }

        guideLineManager.placeGuide()
    }

    override func keyUp(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 48: onTabReleased?()
        case 49: onSpacebarReleased?()
        default: break
        }
    }
}
