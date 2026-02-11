import AppKit
import QuartzCore

/// Static hint bar showing keyboard shortcut hints.
/// Renders once into layer.contents for zero per-frame cost.
final class HintBarView: NSView {
    private let barHeight: CGFloat = 36
    private let barMargin: CGFloat = 20
    private let topMargin: CGFloat = 48
    private let cornerRadius: CGFloat = 8
    private var isAtBottom = true
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = self.layer, layer.contents == nil else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.screens.first?.backingScaleFactor ?? 2.0
        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)

        guard pixelWidth > 0, pixelHeight > 0 else { return }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        rep.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx

        drawContent()

        NSGraphicsContext.restoreGraphicsState()

        layer.contents = rep.cgImage
        layer.contentsScale = scale
    }

    private func drawContent() {
        let totalWidth = bounds.width
        let text = "Use ↑ ↓ ← → to skip an edge.  Add ⇧ to invert."

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let pillWidth = textSize.width + 24
        let pillHeight = barHeight
        let pillX = (totalWidth - pillWidth) / 2
        let pillY: CGFloat = 0

        let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        let bg = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0, alpha: 0.7).setFill()
        bg.fill()

        let textX = pillX + 12
        let textY = pillY + (pillHeight - textSize.height) / 2
        let textRect = NSRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    /// Update position based on cursor proximity. Call from mouseMoved.
    func updatePosition(cursorY: CGFloat, screenHeight: CGFloat) {
        let nearBottom = cursorY < barHeight + barMargin * 3
        let shouldBeAtTop = nearBottom

        // No change needed if already in the right position
        if shouldBeAtTop && !isAtBottom { return }
        if !shouldBeAtTop && isAtBottom { return }
        guard !isAnimating else { return }

        let finalY: CGFloat
        if shouldBeAtTop {
            finalY = screenHeight - barHeight - topMargin
            isAtBottom = false
        } else {
            finalY = barMargin
            isAtBottom = true
        }

        animateSlide(to: finalY, screenHeight: screenHeight, exitDown: shouldBeAtTop)
    }

    private func animateSlide(to finalY: CGFloat, screenHeight: CGFloat, exitDown: Bool) {
        guard let layer = self.layer else {
            frame.origin.y = finalY
            return
        }

        isAnimating = true
        let currentCenter = layer.position.y
        let offscreenExit = exitDown ? -barHeight : screenHeight + barHeight
        let offscreenEntry = exitDown ? screenHeight + barHeight : -barHeight
        let finalCenter = finalY + barHeight / 2

        // Slide out
        let slideOut = CABasicAnimation(keyPath: "position.y")
        slideOut.fromValue = currentCenter
        slideOut.toValue = offscreenExit
        slideOut.duration = 0.1
        slideOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
        slideOut.beginTime = 0

        // Slide in
        let slideIn = CABasicAnimation(keyPath: "position.y")
        slideIn.fromValue = offscreenEntry
        slideIn.toValue = finalCenter
        slideIn.duration = 0.15
        slideIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        slideIn.beginTime = 0.1

        let group = CAAnimationGroup()
        group.animations = [slideOut, slideIn]
        group.duration = 0.25
        group.isRemovedOnCompletion = true

        // Set model value immediately
        frame.origin.y = finalY

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isAnimating = false
        }
        layer.add(group, forKey: "hintBarSlide")
        CATransaction.commit()
    }

    /// Set up initial frame positioned at bottom center
    func configure(screenWidth: CGFloat, screenHeight: CGFloat) {
        let barWidth = screenWidth
        frame = NSRect(x: 0, y: barMargin, width: barWidth, height: barHeight)
        isAtBottom = true
    }
}
