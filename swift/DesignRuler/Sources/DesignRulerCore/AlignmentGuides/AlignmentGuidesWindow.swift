import AppKit
import QuartzCore

/// Fullscreen overlay window for the Alignment Guides command.
/// Subclasses OverlayWindow for shared window config, tracking, throttle, hint bar, and ESC.
/// Contains only: guide line management, direction/style cycling, cursor direction state.
/// Cursor management via CursorManager (resize ↔ pointingHand).
package final class AlignmentGuidesWindow: OverlayWindow {
    private var guideLineManager: GuideLineManager!
    private var cursorDirection: Direction = .vertical

    // Typed callback for multi-monitor activation
    package var onActivate: ((AlignmentGuidesWindow) -> Void)?

    // Command-specific callbacks
    package var onSpacebarPressed: (() -> Void)?
    package var onSpacebarReleased: (() -> Void)?
    package var onTabPressed: (() -> Void)?
    package var onTabReleased: (() -> Void)?

    /// Create a fullscreen alignment guides window for the given screen.
    package static func create(for screen: NSScreen, screenshot: CGImage?, hideHintBar: Bool) -> AlignmentGuidesWindow {
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

        // Guideline view (transparent, no hit testing needed)
        let guidelineView = NSView(frame: NSRect(origin: .zero, size: size))
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
    package func performCycleStyle() {
        if hintBarView.superview != nil { hintBarView.pressKey(.space) }
        guideLineManager.cycleStyle(cursorPosition: lastCursorPosition)
    }

    package func releaseSpaceKey() {
        if hintBarView.superview != nil { hintBarView.releaseKey(.space) }
    }

    /// Toggle line direction (called by coordinator on the active window).
    package func performToggleDirection() {
        if hintBarView.superview != nil { hintBarView.pressKey(.tab) }
        guideLineManager.toggleDirection()
        cursorDirection = guideLineManager.direction
        let newCursor: NSCursor = cursorDirection == .vertical ? .resizeLeftRight : .resizeUpDown
        CursorManager.shared.updateResize(newCursor)
    }

    package func releaseTabKey() {
        if hintBarView.superview != nil { hintBarView.releaseKey(.tab) }
    }

    package var currentGuideLineStyle: GuideLineStyle {
        guideLineManager.currentStyleValue
    }

    package var currentGuideLineDirection: Direction {
        guideLineManager.direction
    }

    // MARK: - Overridable Hooks

    override package func handleActivation() {
        onActivate?(self)
    }

    override package func showInitialState() {
        initCursorPosition()
        guideLineManager.showPreview()
        guideLineManager.updatePreview(at: lastCursorPosition)
        let resizeCursor: NSCursor = cursorDirection == .vertical ? .resizeLeftRight : .resizeUpDown
        CursorManager.shared.showResize(resizeCursor)
        hintBarEntrance()
    }

    override package func handleMouseMoved(to windowPoint: NSPoint) {
        let wasHovering = guideLineManager.hasHoveredLine

        // Check hover first so preview knows whether to show "Remove" or coordinates
        guideLineManager.updateHover(at: windowPoint)
        guideLineManager.updatePreview(at: windowPoint)

        // Cursor transitions via CursorManager (only on state change)
        let isHovering = guideLineManager.hasHoveredLine
        if isHovering != wasHovering {
            if isHovering {
                CursorManager.shared.transitionToPointingHand()
            } else {
                CursorManager.shared.transitionBack()
            }
        }
    }

    override package func handleKeyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 48: onTabPressed?()
        case 49: onSpacebarPressed?()
        default: break
        }
    }

    override package func deactivate() {
        guideLineManager.hidePreview()
        if guideLineManager.hasHoveredLine {
            guideLineManager.updateHover(at: NSPoint(x: -100, y: -100))
            CursorManager.shared.transitionBack()
        }
    }

    // MARK: - Multi-monitor Activation

    package func activate(firstMoveAlreadyReceived: Bool, currentStyle: GuideLineStyle, currentDirection: Direction) {
        initCursorPosition()
        guideLineManager.setPreviewStyle(currentStyle)
        guideLineManager.setDirection(currentDirection)
        cursorDirection = currentDirection
        let resizeCursor: NSCursor = cursorDirection == .vertical ? .resizeLeftRight : .resizeUpDown
        CursorManager.shared.updateResize(resizeCursor)
        guideLineManager.showPreview()
        guideLineManager.updatePreview(at: lastCursorPosition)
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: lastCursorPosition.y, screenHeight: screenBounds.height)
        }
    }

    // MARK: - Event Handling (Subclass-specific)

    override package func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: mouseDown(with: event)
        default: super.sendEvent(event)
        }
    }

    override package func mouseDown(with event: NSEvent) {
        onActivity?()
        let windowPoint = event.locationInWindow

        // Hover-first conflict resolution: if hovering a line, remove it instead of placing
        if guideLineManager.hasHoveredLine {
            guideLineManager.removeLine(guideLineManager.hoveredLine!, clickPoint: windowPoint)
            guideLineManager.resetRemoveMode()
            guideLineManager.updatePreview(at: windowPoint)
            CursorManager.shared.transitionBack()
            return
        }

        guideLineManager.placeGuide()
    }

    override package func keyUp(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 48: onTabReleased?()
        case 49: onSpacebarReleased?()
        default: break
        }
    }
}
