import AppKit
import QuartzCore

/// Fullscreen borderless window that captures mouse and keyboard events.
final class RulerWindow: NSWindow {
    private let kHintBarDismissedKey = "com.raycast.design-ruler.hintBarDismissed"

    private(set) var targetScreen: NSScreen!
    private var edgeDetector: EdgeDetector!
    private var crosshairView: CrosshairView!
    private var hintBarView: HintBarView!
    private var selectionManager: SelectionManager!
    private var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0
    private var hasReceivedFirstMove = false
    private var isDragging = false
    private var isHoveringSelection = false

    // Transient "Press ? for help" message
    private var transientBgLayer: CAShapeLayer?
    private var transientTextLayer: CATextLayer?
    private var transientGeneration: Int = 0
    private var hideHintBarPref: Bool = false

    // Callbacks for multi-monitor coordination
    var onActivate: ((RulerWindow) -> Void)?
    var onRequestExit: (() -> Void)?
    var onFirstMove: (() -> Void)?
    var onActivity: (() -> Void)?

    /// Create a fullscreen ruler window for the given screen
    static func create(for screen: NSScreen, edgeDetector: EdgeDetector, hideHintBar: Bool) -> RulerWindow {
        // Use visibleFrame with zero origin for contentRect — when `screen:` is passed,
        // NSWindow interprets the origin relative to the screen's coordinate space,
        // so global coords would double-count the offset on secondary monitors.
        let window = RulerWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Explicitly set frame in global coords to guarantee correct placement
        window.setFrame(screen.frame, display: false)
        window.targetScreen = screen
        window.edgeDetector = edgeDetector
        window.screenBounds = screen.frame
        window.level = .statusBar
        // Window is opaque — we have a fullscreen screenshot as background,
        // no need for the compositor to blend with the actual desktop.
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window.setupViews(screenFrame: screen.frame, edgeDetector: edgeDetector, hideHintBar: hideHintBar)
        window.setupTrackingArea()
        return window
    }

    private func setupViews(screenFrame: CGRect, edgeDetector: EdgeDetector, hideHintBar: Bool) {
        self.hideHintBarPref = hideHintBar
        let size = screenFrame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))

        let cv = CrosshairView(frame: NSRect(origin: .zero, size: size))
        cv.screenFrame = screenFrame
        self.crosshairView = cv
        containerView.addSubview(cv)

        // Selection manager uses the crosshair view's layer as parent for selection overlays
        let scale = backingScaleFactor
        self.selectionManager = SelectionManager(
            parentLayer: cv.layer!,
            edgeDetector: edgeDetector,
            scale: scale
        )

        let hv = HintBarView(frame: .zero)
        self.hintBarView = hv
        let dismissed = UserDefaults.standard.bool(forKey: kHintBarDismissedKey)
        var showTransientOnLaunch = false
        if !hideHintBar && !dismissed {
            hv.configure(screenWidth: size.width, screenHeight: size.height)
            containerView.addSubview(hv)
        } else if !hideHintBar && dismissed {
            showTransientOnLaunch = true
        }

        contentView = containerView

        if showTransientOnLaunch {
            showTransientHelp()
        }
    }

    private func setupTrackingArea() {
        guard let cv = contentView else { return }
        let area = NSTrackingArea(
            rect: cv.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        cv.addTrackingArea(area)
    }

    /// Set frozen screenshot as background using CALayer (bypasses NSImage DPI scaling)
    func setBackground(_ cgImage: CGImage) {
        guard let container = contentView else { return }

        let bgView = NSView(frame: NSRect(origin: .zero, size: screenBounds.size))
        bgView.wantsLayer = true
        bgView.layer?.contents = cgImage
        bgView.layer?.contentsGravity = .resize

        container.addSubview(bgView, positioned: .below, relativeTo: crosshairView)
    }

    /// Show initial pill at cursor position before first mouse move.
    func showInitialState() {
        let mouseLocation = NSEvent.mouseLocation
        let windowPoint = NSPoint(
            x: mouseLocation.x - screenBounds.origin.x,
            y: mouseLocation.y - screenBounds.origin.y
        )
        crosshairView.showInitialPill(at: windowPoint)
    }

    // MARK: - Multi-monitor activation

    override func mouseEntered(with event: NSEvent) {
        onActivate?(self)
    }

    /// Deactivate this window when cursor leaves for another screen.
    func deactivate() {
        crosshairView.hideForDrag()
        if isHoveringSelection {
            isHoveringSelection = false
            CursorManager.shared.transitionBackToHidden()
            selectionManager.updateHover(at: .zero)
        }
        if isDragging {
            selectionManager.cancelDrag()
            isDragging = false
            CursorManager.shared.transitionBackToHidden()
        }
    }

    /// Activate this window when cursor enters from another screen.
    func activate(firstMoveAlreadyReceived: Bool) {
        if firstMoveAlreadyReceived && !hasReceivedFirstMove {
            hasReceivedFirstMove = true
            crosshairView.skipSystemCrosshairPhase()
        }
        crosshairView.showAfterDrag()

        // Trigger edge detection at current cursor position
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

    var hasSelections: Bool { selectionManager.hasSelections }

    // MARK: - Event Handling

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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

    override func mouseMoved(with event: NSEvent) {
        // Throttle to ~60fps
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= 0.014 else { return }
        lastMoveTime = now
        onActivity?()

        if !hasReceivedFirstMove {
            hasReceivedFirstMove = true
            crosshairView.hideSystemCrosshair()
            onFirstMove?()
        }

        let windowPoint = event.locationInWindow
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )

        guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }

        // Update selection hover state — hide crosshair and show hand cursor when hovering
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
            CursorManager.shared.transitionBackToHidden()
            selectionManager.updateHover(at: windowPoint)
        }

        crosshairView.update(cursor: windowPoint, edges: edges)
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: windowPoint.y, screenHeight: screenBounds.height)
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
            CursorManager.shared.transitionBackToHidden()
        }

        // Click on a hovered selection → remove it and restore crosshair
        if let hovered = selectionManager.hitTest(windowPoint), hovered.state == .hovered {
            selectionManager.removeSelection(hovered)
            if isHoveringSelection {
                isHoveringSelection = false
                CursorManager.shared.transitionBackToHidden()
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
            CursorManager.shared.transitionBackToHidden()
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
        CursorManager.shared.transitionBackToHidden()
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
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
        case 51: // Backspace — dismiss hint bar, show transient help
            if hintVisible {
                hintBarView.pressKey(.backspace)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, self.hintBarView.superview != nil else { return }
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.2
                        self.hintBarView.animator().alphaValue = 0
                    }, completionHandler: {
                        self.hintBarView.removeFromSuperview()
                        self.hintBarView.alphaValue = 1  // Reset for potential re-add
                        self.showTransientHelp()
                    })
                }
                UserDefaults.standard.set(true, forKey: kHintBarDismissedKey)
            }
        case 53: // ESC
            if hintVisible { hintBarView.pressKey(.esc) }
            onRequestExit?()
        default:
            break
        }

        // Layout-independent "?" detection (Shift+/ on US, varies by layout)
        if event.characters == "?" {
            showHintBar()
        }
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

    // MARK: - Help Toggle System

    /// Show transient "Press ? for help" message at bottom center.
    /// Auto-fades after ~2.5s. Generation counter prevents stale callbacks.
    private func showTransientHelp() {
        transientGeneration += 1
        let gen = transientGeneration

        // Remove any existing transient layers
        transientBgLayer?.removeFromSuperlayer()
        transientTextLayer?.removeFromSuperlayer()

        guard let parentLayer = contentView?.layer else { return }

        let text = "Press  ?  for help"
        let font = NSFont.systemFont(ofSize: 16, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: -0.4 as CGFloat,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()

        let padH: CGFloat = 16
        let padV: CGFloat = 10
        let bgWidth = ceil(textSize.width) + padH * 2
        let bgHeight = ceil(textSize.height) + padV * 2
        let bgX = floor((screenBounds.width - bgWidth) / 2)
        let bgY: CGFloat = 20  // Bottom margin (AppKit coords)

        let bgLayer = CAShapeLayer()
        bgLayer.frame = CGRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)
        bgLayer.path = CGPath(roundedRect: CGRect(origin: .zero, size: bgLayer.frame.size),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        bgLayer.fillColor = CGColor(gray: 0, alpha: 0.7)
        bgLayer.shadowColor = CGColor(gray: 0, alpha: 0.2)
        bgLayer.shadowOffset = CGSize(width: 0, height: -1)
        bgLayer.shadowRadius = 4
        bgLayer.shadowOpacity = 1

        let textLayer = CATextLayer()
        textLayer.string = attrStr
        textLayer.contentsScale = backingScaleFactor
        textLayer.frame = CGRect(
            x: bgX + padH,
            y: bgY + round((bgHeight - ceil(textSize.height)) / 2),
            width: ceil(textSize.width),
            height: ceil(textSize.height)
        )
        textLayer.alignmentMode = .center
        textLayer.isWrapped = false

        // Start invisible
        bgLayer.opacity = 0
        textLayer.opacity = 0

        parentLayer.addSublayer(bgLayer)
        parentLayer.addSublayer(textLayer)
        transientBgLayer = bgLayer
        transientTextLayer = textLayer

        // Fade in
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        bgLayer.opacity = 1
        textLayer.opacity = 1
        CATransaction.commit()

        // Schedule auto-fade with generation guard
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [weak self] in
            guard let self, self.transientGeneration == gen else { return }
            self.fadeOutTransientHelp()
        }
    }

    /// Fade out and remove transient help layers.
    private func fadeOutTransientHelp() {
        transientGeneration += 1
        guard transientBgLayer != nil || transientTextLayer != nil else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in
            self?.transientBgLayer?.removeFromSuperlayer()
            self?.transientTextLayer?.removeFromSuperlayer()
            self?.transientBgLayer = nil
            self?.transientTextLayer = nil
        }
        transientBgLayer?.opacity = 0
        transientTextLayer?.opacity = 0
        CATransaction.commit()
    }

    /// Re-enable the hint bar (triggered by "?" key).
    private func showHintBar() {
        guard hintBarView.superview == nil else { return }
        guard !hideHintBarPref else { return }
        guard let container = contentView else { return }

        // Clear stale pressed key states
        for key in HintBarView.KeyID.allCases {
            hintBarView.releaseKey(key)
        }

        hintBarView.alphaValue = 0
        hintBarView.configure(screenWidth: screenBounds.width, screenHeight: screenBounds.height)
        container.addSubview(hintBarView)

        // Update position for current cursor location
        let mouse = NSEvent.mouseLocation
        let wp = NSPoint(x: mouse.x - screenBounds.origin.x, y: mouse.y - screenBounds.origin.y)
        hintBarView.updatePosition(cursorY: wp.y, screenHeight: screenBounds.height)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            hintBarView.animator().alphaValue = 1
        })

        UserDefaults.standard.removeObject(forKey: kHintBarDismissedKey)

        // Remove transient help if visible
        fadeOutTransientHelp()
    }
}
