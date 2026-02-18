import AppKit
import QuartzCore

/// A single selection overlay: rectangle outline + dimension pill.
/// Composed of CALayers (not an NSView) for lightweight stacking.
package final class SelectionOverlay {
    package enum State { case normal, hovered }

    package private(set) var rect: CGRect  // AppKit window-local coords
    package private(set) var state: State = .normal
    private var dimensionW: Int = 0
    private var dimensionH: Int = 0
    private let screenSize: CGSize

    // Layers
    package let rectLayer = CAShapeLayer()
    package let fillLayer = CAShapeLayer()
    private var pill: PillRenderer.SelectionPill!

    // Colors
    private let normalStroke = CGColor(gray: 1.0, alpha: 1.0)
    private let hoveredStroke = DesignTokens.Color.hoverRed
    private let normalFill = CGColor(gray: 1.0, alpha: 0.04)
    private let hoveredFill = DesignTokens.Color.hoverRedFill
    private let normalPillBg = DesignTokens.Pill.backgroundColor
    private let hoveredPillBg = DesignTokens.Color.hoverRedPillBg

    // Pill layout
    private let pillHeight = DesignTokens.Pill.height
    private let pillPadH: CGFloat = 8
    private let pillRadius = DesignTokens.Pill.cornerRadius
    private let pillGap: CGFloat = 6
    private let slideDistance: CGFloat = 4  // intro animation slide
    private let clampMargin: CGFloat = 4   // shadow: radius=3 + offset.y=1

    // Font — SF Pro 11px Semibold with same OpenType features as inspector pill
    private static let font = PillRenderer.makeDesignFont(size: 11)

    package init(rect: CGRect, parentLayer: CALayer, scale: CGFloat) {
        self.rect = rect
        self.screenSize = parentLayer.bounds.size
        setupLayers(parentLayer: parentLayer, scale: scale)
        updateRect(rect, animated: false)
    }

    private func setupLayers(parentLayer: CALayer, scale: CGFloat) {
        // Fill layer — very subtle
        fillLayer.fillColor = normalFill
        fillLayer.strokeColor = nil
        parentLayer.addSublayer(fillLayer)

        // Rect outline — difference blend
        rectLayer.fillColor = nil
        rectLayer.strokeColor = normalStroke
        rectLayer.lineWidth = 1.0
        rectLayer.lineDashPattern = [4, 3]
        rectLayer.compositingFilter = BlendMode.difference
        parentLayer.addSublayer(rectLayer)

        // Pill (background + text layer created by factory, starts hidden)
        pill = PillRenderer.makeSelectionPill(parentLayer: parentLayer, scale: scale)
    }

    /// Update the selection rectangle (during drag or snap).
    package func updateRect(_ newRect: CGRect, animated: Bool) {
        rect = newRect

        // Stroke sits outside: outset by half line width
        let strokeInset = -rectLayer.lineWidth / 2

        if animated {
            // Don't disable actions — let CA animate
            rectLayer.path = CGPath(rect: rect.insetBy(dx: strokeInset, dy: strokeInset), transform: nil)
            fillLayer.path = CGPath(rect: rect, transform: nil)
        } else {
            CATransaction.instant {
                rectLayer.path = CGPath(rect: rect.insetBy(dx: strokeInset, dy: strokeInset), transform: nil)
                fillLayer.path = CGPath(rect: rect, transform: nil)
            }
        }
    }

    /// Animate snap to detected edges, then show dimensions pill with slide-down + fade.
    package func animateSnap(to newRect: CGRect, w: Int, h: Int) {
        dimensionW = w
        dimensionH = h

        // Remove dash pattern for finalized selection
        rectLayer.lineDashPattern = nil

        CATransaction.animated(duration: DesignTokens.Animation.standard) {
            rect = newRect
            let strokeInset = -rectLayer.lineWidth / 2
            rectLayer.path = CGPath(rect: newRect.insetBy(dx: strokeInset, dy: strokeInset), transform: nil)
            fillLayer.path = CGPath(rect: newRect, transform: nil)
        }

        // Place pill at final position, invisible (no implicit animations)
        setDimensionsText(w: w, h: h)
        CATransaction.instant {
            layoutPill()
            pill.bgLayer.opacity = 1
            pill.textLayer.opacity = 1
        }

        // Explicit slide-down + fade-in from offset position
        let duration: CFTimeInterval = 0.2
        let timing = CAMediaTimingFunction(name: .easeOut)

        for layer in [pill.bgLayer, pill.textLayer] as [CALayer] {
            let slide = CABasicAnimation(keyPath: "position.y")
            slide.fromValue = layer.position.y + slideDistance
            slide.toValue = layer.position.y
            slide.duration = duration
            slide.timingFunction = timing
            layer.add(slide, forKey: "slideIn")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            fade.duration = duration
            fade.timingFunction = timing
            layer.add(fade, forKey: "fadeIn")
        }
    }

    package func setHovered(_ hovered: Bool) {
        let newState: State = hovered ? .hovered : .normal
        guard newState != state else { return }
        state = newState

        CATransaction.animated(duration: DesignTokens.Animation.fast) {
            rectLayer.strokeColor = hovered ? hoveredStroke : normalStroke
            rectLayer.compositingFilter = hovered ? nil : BlendMode.difference
            fillLayer.fillColor = hovered ? hoveredFill : normalFill
            pill.bgLayer.fillColor = hovered ? hoveredPillBg : normalPillBg

            if hovered {
                setClearText()
            } else {
                setDimensionsText(w: dimensionW, h: dimensionH)
                layoutPill()
            }
        }
    }

    /// Shake horizontally (macOS login rejection idiom) with overlapping fade out.
    package func shakeAndRemove() {
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [0, -10, 10, -6, 6, -2, 2, 0]
        shake.keyTimes = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0] as [NSNumber]
        shake.duration = 0.4
        shake.isAdditive = true

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.beginTime = 0.1
        fade.duration = 0.3
        fade.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [shake, fade]
        group.duration = 0.4
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        let layers: [CALayer] = [rectLayer, fillLayer, pill.bgLayer, pill.textLayer]

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layers.forEach { $0.removeFromSuperlayer() }
        }
        for layer in layers {
            layer.opacity = 0  // model value matches final state
            layer.add(group, forKey: "shakeAndFade")
        }
        CATransaction.commit()
    }

    package func remove(animated: Bool) {
        let layers: [CALayer] = [rectLayer, fillLayer, pill.bgLayer, pill.textLayer]
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(DesignTokens.Animation.fast)
            CATransaction.setCompletionBlock {
                layers.forEach { $0.removeFromSuperlayer() }
            }
            layers.forEach { $0.opacity = 0 }
            CATransaction.commit()
        } else {
            layers.forEach { $0.removeFromSuperlayer() }
        }
    }

    /// Hit-test with slight padding for easier clicking.
    package func contains(_ point: CGPoint) -> Bool {
        let padding: CGFloat = 4
        return rect.insetBy(dx: -padding, dy: -padding).contains(point)
    }

    // MARK: - Text helpers

    private func setDimensionsText(w: Int, h: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
            .kern: DesignTokens.Pill.kerning,
        ]
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor(white: 1, alpha: 0.5),
            .kern: DesignTokens.Pill.kerning,
            .baselineOffset: 1.0 as CGFloat,
        ]

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: "\(w)", attributes: attrs))
        str.append(NSAttributedString(string: " \u{00D7} ", attributes: dimAttrs))
        str.append(NSAttributedString(string: "\(h)", attributes: attrs))
        pill.textLayer.string = str
    }

    private func setClearText() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
            .kern: DesignTokens.Pill.kerning,
        ]
        pill.textLayer.string = NSAttributedString(string: "Clear", attributes: attrs)
        layoutPill()
    }

    // MARK: - Pill layout

    private func layoutPill() {
        guard let str = pill.textLayer.string as? NSAttributedString else { return }
        let textSize = str.size()
        let pillW = ceil(textSize.width) + pillPadH * 2
        let textH = ceil(textSize.height)

        // Position pill below the selection rect (or above if near bottom)
        var pillX = round(rect.midX - pillW / 2)
        var pillY = round(rect.minY - pillGap - pillHeight)
        if pillY < clampMargin {
            pillY = round(rect.maxY + pillGap)
        }

        // Clamp to screen bounds (accounting for shadow)
        let maxX = screenSize.width - pillW - clampMargin
        pillX = min(max(pillX, clampMargin), max(clampMargin, maxX))

        let maxY = screenSize.height - pillHeight - clampMargin
        pillY = min(max(pillY, clampMargin), max(clampMargin, maxY))

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillHeight)
        pill.bgLayer.frame = pillRect
        pill.bgLayer.path = PillRenderer.squirclePath(rect: CGRect(origin: .zero, size: pillRect.size),
                                                       radius: pillRadius)

        let textY = round(pillY + (pillHeight - textH) / 2)
        pill.textLayer.frame = CGRect(x: pillX, y: textY, width: pillW, height: textH)
    }
}
