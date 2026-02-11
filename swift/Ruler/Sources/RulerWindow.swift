import AppKit
import QuartzCore

/// Fullscreen borderless window that captures mouse and keyboard events.
final class RulerWindow: NSWindow {
    private var edgeDetector: EdgeDetector!
    private var crosshairView: CrosshairView!
    private var hintBarView: HintBarView!
    private var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0
    private var hasReceivedFirstMove = false

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

        window.setupViews(screenFrame: screen.frame, hideHintBar: hideHintBar)
        return window
    }

    private func setupViews(screenFrame: CGRect, hideHintBar: Bool) {
        let size = screenFrame.size
        let containerView = NSView(frame: NSRect(origin: .zero, size: size))

        let cv = CrosshairView(frame: NSRect(origin: .zero, size: size))
        cv.screenFrame = screenFrame
        self.crosshairView = cv
        containerView.addSubview(cv)

        let hv = HintBarView(frame: .zero)
        self.hintBarView = hv
        let dismissed = UserDefaults.standard.bool(forKey: "com.raycast.design-ruler.hintBarDismissed")
        if !hideHintBar && !dismissed {
            hv.configure(screenWidth: size.width, screenHeight: size.height)
            containerView.addSubview(hv)
        }

        contentView = containerView
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

    // MARK: - Event Handling

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        // Throttle to ~60fps
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= 0.014 else { return }
        lastMoveTime = now

        if !hasReceivedFirstMove {
            hasReceivedFirstMove = true
            crosshairView.hideSystemCrosshair()
        }

        let windowPoint = event.locationInWindow
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )

        guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }
        crosshairView.update(cursor: windowPoint, edges: edges)
        if hintBarView.superview != nil {
            hintBarView.updatePosition(cursorY: windowPoint.y, screenHeight: screenBounds.height)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )
        let axPoint = CoordinateConverter.appKitToAX(appKitScreenPoint)

        // Re-scan edges at click position (don't reset skips)
        guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }

        let leftX = edges.left.map { windowPoint.x - $0.distance } ?? 0
        let rightX = edges.right.map { windowPoint.x + $0.distance } ?? screenBounds.width
        let topY = edges.top.map { windowPoint.y + $0.distance } ?? screenBounds.height
        let bottomY = edges.bottom.map { windowPoint.y - $0.distance } ?? 0
        let w = rightX - leftX
        let h = topY - bottomY

        let ld = edges.left.map { String(format: "%.1f", $0.distance) } ?? "nil"
        let rd = edges.right.map { String(format: "%.1f", $0.distance) } ?? "nil"
        let td = edges.top.map { String(format: "%.1f", $0.distance) } ?? "nil"
        let bd = edges.bottom.map { String(format: "%.1f", $0.distance) } ?? "nil"

        let line = "[TEST] pos=(\(Int(axPoint.x)),\(Int(axPoint.y))) W×H=\(Int(w))×\(Int(h)) edges: L=\(ld) R=\(rd) T=\(td) B=\(bd)\n"
        fputs(line, stderr)
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let hintVisible = hintBarView.superview != nil

        switch Int(event.keyCode) {
        case 123: // Left arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.left) }
            let edges = shift ? edgeDetector.decrementSkip(.left) : edgeDetector.incrementSkip(.left)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 124: // Right arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.right) }
            let edges = shift ? edgeDetector.decrementSkip(.right) : edgeDetector.incrementSkip(.right)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 125: // Down arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.down) }
            let edges = shift ? edgeDetector.decrementSkip(.bottom) : edgeDetector.incrementSkip(.bottom)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 126: // Up arrow
            if !event.isARepeat && hintVisible { hintBarView.pressKey(.up) }
            let edges = shift ? edgeDetector.decrementSkip(.top) : edgeDetector.incrementSkip(.top)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 51: // Backspace — dismiss hint bar permanently
            if hintVisible {
                hintBarView.pressKey(.backspace)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, self.hintBarView.superview != nil else { return }
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.2
                        self.hintBarView.animator().alphaValue = 0
                    }, completionHandler: {
                        self.hintBarView.removeFromSuperview()
                    })
                }
                UserDefaults.standard.set(true, forKey: "com.raycast.design-ruler.hintBarDismissed")
            }
        case 53: // ESC
            if hintVisible { hintBarView.pressKey(.esc) }
            if hasReceivedFirstMove {
                NSCursor.unhide()
            }
            close()
            NSApp.terminate(nil)
        default:
            break
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
}
