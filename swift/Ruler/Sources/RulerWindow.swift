import AppKit
import QuartzCore

/// Fullscreen borderless window that captures mouse and keyboard events.
final class RulerWindow: NSWindow {
    private var edgeDetector: EdgeDetector!
    private var crosshairView: CrosshairView!
    private var hintBarView: HintBarView!
    private var screenBounds: CGRect = .zero
    private var lastMoveTime: Double = 0

    /// Create a fullscreen ruler window for the given screen
    static func create(for screen: NSScreen, edgeDetector: EdgeDetector, hideHintBar: Bool) -> RulerWindow {
        let window = RulerWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
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
        NSCursor.hide()
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
        if !hideHintBar {
            hv.configure(screenWidth: size.width, screenHeight: size.height)
            containerView.addSubview(hv)
        }

        contentView = containerView
    }

    /// Set frozen screenshot as background
    func setBackground(_ image: NSImage) {
        guard let container = contentView else { return }

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: screenBounds.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently

        container.addSubview(imageView, positioned: .below, relativeTo: crosshairView)
    }

    // MARK: - Event Handling

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        // Throttle to ~60fps
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= 0.014 else { return }
        lastMoveTime = now

        let windowPoint = event.locationInWindow
        let appKitScreenPoint = NSPoint(
            x: screenBounds.origin.x + windowPoint.x,
            y: screenBounds.origin.y + windowPoint.y
        )

        guard let edges = edgeDetector.onMouseMoved(at: appKitScreenPoint) else { return }
        crosshairView.update(cursor: windowPoint, edges: edges)
        hintBarView.updatePosition(cursorY: windowPoint.y, screenHeight: screenBounds.height)
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

        switch Int(event.keyCode) {
        case 123: // Left arrow
            let edges = shift ? edgeDetector.decrementSkip(.left) : edgeDetector.incrementSkip(.left)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 124: // Right arrow
            let edges = shift ? edgeDetector.decrementSkip(.right) : edgeDetector.incrementSkip(.right)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 125: // Down arrow
            let edges = shift ? edgeDetector.decrementSkip(.bottom) : edgeDetector.incrementSkip(.bottom)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 126: // Up arrow
            let edges = shift ? edgeDetector.decrementSkip(.top) : edgeDetector.incrementSkip(.top)
            if let edges { crosshairView.update(cursor: crosshairView.cursorPosition, edges: edges) }
        case 53: // ESC
            NSCursor.unhide()
            close()
            NSApp.terminate(nil)
        default:
            break
        }
    }
}
