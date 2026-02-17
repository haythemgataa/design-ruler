import AppKit
import QuartzCore

/// Fullscreen overlay window for the Design Ruler command.
/// Subclasses OverlayWindow for shared window config, tracking, throttle, hint bar, and ESC.
/// Contains only: edge detection, crosshair rendering, selection/drag lifecycle, arrow keys.
final class RulerWindow: OverlayWindow {
    private var edgeDetector: EdgeDetector!
    private var crosshairView: CrosshairView!
    private var selectionManager: SelectionManager!
    private var isDragging = false
    private var isHoveringSelection = false

    // Typed callback for multi-monitor activation
    var onActivate: ((RulerWindow) -> Void)?

    /// Create a fullscreen ruler window for the given screen
    static func create(for screen: NSScreen, edgeDetector: EdgeDetector, hideHintBar: Bool, screenshot: CGImage? = nil) -> RulerWindow {
        let window = RulerWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        OverlayWindow.configureOverlay(window, for: screen)
        window.edgeDetector = edgeDetector
        window.setupViews(screenFrame: screen.frame, edgeDetector: edgeDetector, hideHintBar: hideHintBar, screenshot: screenshot)
        window.setupTrackingArea()
        return window
    }

    private func setupViews(screenFrame: CGRect, edgeDetector: EdgeDetector, hideHintBar: Bool, screenshot: CGImage? = nil) {
        let size = screenFrame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))

        let cv = CrosshairView(frame: NSRect(origin: .zero, size: size))
        cv.screenFrame = screenFrame
        self.crosshairView = cv
        containerView.addSubview(cv)

        let scale = backingScaleFactor
        self.selectionManager = SelectionManager(
            parentLayer: cv.layer!,
            edgeDetector: edgeDetector,
            scale: scale
        )

        contentView = containerView

        // Use base's shared hint bar setup (mode defaults to .inspect)
        setupHintBar(mode: .inspect, screenSize: size, screenshot: screenshot, hideHintBar: hideHintBar, container: containerView)
    }

    /// Set frozen screenshot as background below the crosshair view.
    func setBackground(_ cgImage: CGImage) {
        setBackground(cgImage, below: crosshairView)
    }

    var hasSelections: Bool { selectionManager.hasSelections }

    // MARK: - Overridable Hooks

    override func handleActivation() {
        onActivate?(self)
    }

    override func showInitialState() {
        CursorManager.shared.hide()
        let mouseLocation = NSEvent.mouseLocation
        let windowPoint = NSPoint(
            x: mouseLocation.x - screenBounds.origin.x,
            y: mouseLocation.y - screenBounds.origin.y
        )
        crosshairView.showInitialPill(at: windowPoint)
        hintBarEntrance()
    }

    override func handleMouseMoved(to windowPoint: NSPoint) {
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )

        guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }

        // Selection hover state
        if selectionManager.hasSelections, let _ = selectionManager.hitTest(windowPoint) {
            if !isHoveringSelection {
                isHoveringSelection = true
                crosshairView.hideForDrag()
                CursorManager.shared.transitionToPointingHand()
            }
            selectionManager.updateHover(at: windowPoint)
            return
        } else if isHoveringSelection {
            isHoveringSelection = false
            crosshairView.showAfterDrag()
            CursorManager.shared.transitionBack()
            selectionManager.updateHover(at: windowPoint)
        }

        crosshairView.update(cursor: windowPoint, edges: edges)
    }

    override func handleKeyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let hintVisible = hintBarView.superview != nil

        switch Int(event.keyCode) {
        case 123: // Left arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.left) }
            let edges = shift ? edgeDetector.decrementSkip(.right) : edgeDetector.incrementSkip(.left)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 124: // Right arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.right) }
            let edges = shift ? edgeDetector.decrementSkip(.left) : edgeDetector.incrementSkip(.right)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 125: // Down arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.down) }
            let edges = shift ? edgeDetector.decrementSkip(.top) : edgeDetector.incrementSkip(.bottom)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 126: // Up arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.up) }
            let edges = shift ? edgeDetector.decrementSkip(.bottom) : edgeDetector.incrementSkip(.top)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        default:
            break
        }
    }

    override func deactivate() {
        crosshairView.hideForDrag()
        if isHoveringSelection {
            isHoveringSelection = false
            CursorManager.shared.transitionBack()
            selectionManager.updateHover(at: .zero)
        }
        if isDragging {
            selectionManager.cancelDrag()
            isDragging = false
            CursorManager.shared.transitionBack()
        }
    }

    // MARK: - Multi-monitor Activation

    func activate(firstMoveAlreadyReceived: Bool) {
        if firstMoveAlreadyReceived && !hasReceivedFirstMove {
            markFirstMoveReceived()
        }
        crosshairView.showAfterDrag()

        let mouse = NSEvent.mouseLocation
        let wp = NSPoint(x: mouse.x - screenBounds.origin.x, y: mouse.y - screenBounds.origin.y)
        let sp = NSPoint(x: screenBounds.origin.x + wp.x, y: screenBounds.origin.y + wp.y)
        if let edges = edgeDetector.onMouseMoved(at: sp) {
            crosshairView.update(cursor: wp, edges: edges)
        }
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: wp.y, screenHeight: screenBounds.height)
        }
    }

    // MARK: - Event Handling (Subclass-specific)

    // Route mouse events directly to the window, bypassing view hit-testing.
    // No subview in this overlay needs mouse events — handling them here
    // prevents views from silently consuming mouseDown (which caused an
    // intermittent bug where drags wouldn't start).
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:  mouseDown(with: event)
        case .leftMouseDragged: mouseDragged(with: event)
        case .leftMouseUp:    mouseUp(with: event)
        default: super.sendEvent(event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        let windowPoint = event.locationInWindow

        // Reset stale drag state — if mouseUp was never delivered (e.g., system stole the event),
        // isDragging could be stuck true, preventing new drags from starting correctly
        if isDragging {
            isDragging = false
            crosshairView.showAfterDrag()
            CursorManager.shared.transitionBack()
        }

        // Click on a hovered selection -> remove it and restore crosshair
        if let hovered = selectionManager.hitTest(windowPoint), hovered.state == .hovered {
            selectionManager.removeSelection(hovered)
            if isHoveringSelection {
                isHoveringSelection = false
                CursorManager.shared.transitionBack()
            }
            // Restore crosshair at current position
            crosshairView.showAfterDrag()
            let appKitScreenPoint = NSPoint(
                x: screenBounds.origin.x + windowPoint.x,
                y: screenBounds.origin.y + windowPoint.y
            )
            if let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) {
                crosshairView.update(cursor: windowPoint, edges: edges)
            }
            return
        }

        // Start drag
        isDragging = true
        if isHoveringSelection {
            isHoveringSelection = false
            CursorManager.shared.transitionBack()
        }
        crosshairView.hideForDrag()
        selectionManager.startDrag(at: windowPoint)
        CursorManager.shared.transitionToCrosshairDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        onActivity?()
        if !isDragging { return }
        let windowPoint = event.locationInWindow
        selectionManager.updateDrag(to: windowPoint)
    }

    override func mouseUp(with event: NSEvent) {
        onActivity?()
        if !isDragging { return }
        isDragging = false

        let windowPoint = event.locationInWindow
        _ = selectionManager.endDrag(at: windowPoint, screenBounds: screenBounds)

        // Restore crosshair at current cursor position
        crosshairView.showAfterDrag()
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )
        if let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) {
            crosshairView.update(cursor: windowPoint, edges: edges)
        }

        // Hide system cursor again (custom crosshair takes over)
        CursorManager.shared.transitionBack()
    }

    override func keyUp(with event: NSEvent) {
        guard hintBarView.superview != nil else { return }
        switch Int(event.keyCode) {
        case 123: hintBarView.releaseKey(.left)
        case 124: hintBarView.releaseKey(.right)
        case 125: hintBarView.releaseKey(.down)
        case 126: hintBarView.releaseKey(.up)
        default: break
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard hintBarView.superview != nil else { return }
        if event.modifierFlags.contains(.shift) {
            hintBarView.pressKey(.shift)
        } else {
            hintBarView.releaseKey(.shift)
        }
    }

}
