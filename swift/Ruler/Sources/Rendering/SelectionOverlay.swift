import AppKit
import CoreText
import QuartzCore

/// A single selection overlay: rectangle outline + dimension pill.
/// Composed of CALayers (not an NSView) for lightweight stacking.
final class SelectionOverlay {
    enum State { case normal, hovered }

    private(set) var rect: CGRect  // AppKit window-local coords
    private(set) var state: State = .normal
    private var dimensionW: Int = 0
    private var dimensionH: Int = 0

    // Layers
    let rectLayer = CAShapeLayer()
    let fillLayer = CAShapeLayer()
    let pillBgLayer = CAShapeLayer()
    let pillTextLayer = CATextLayer()

    // Colors
    private let normalStroke = CGColor(gray: 1.0, alpha: 1.0)
    private let hoveredStroke = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
    private let normalFill = CGColor(gray: 1.0, alpha: 0.04)
    private let hoveredFill = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.06)
    private let normalPillBg = CGColor(gray: 0, alpha: 0.8)
    private let hoveredPillBg = CGColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 0.85)

    // Pill layout
    private let pillHeight: CGFloat = 24
    private let pillPadH: CGFloat = 8
    private let pillRadius: CGFloat = 8
    private let pillGap: CGFloat = 6
    private let slideDistance: CGFloat = 4  // intro animation slide

    // Squircle kappa (same as CrosshairView)
    private let k: CGFloat = 0.72

    // Font — SF Pro 11px Semibold with same OpenType features as inspector pill
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let tags = ["ss01", "ss02", "cv01", "cv02", "cv08", "cv12", "lnum", "tnum"]
        let features: [[String: Any]] = tags.map { tag in
            [kCTFontOpenTypeFeatureTag as String: tag, kCTFontOpenTypeFeatureValue as String: 1]
        }
        let desc = CTFontDescriptorCreateWithAttributes(
            [kCTFontFeatureSettingsAttribute: features] as CFDictionary
        )
        let ctFont = CTFontCreateCopyWithAttributes(base as CTFont, 11, nil, desc)
        return ctFont as NSFont
    }()

    init(rect: CGRect, parentLayer: CALayer, scale: CGFloat) {
        self.rect = rect
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
        rectLayer.compositingFilter = "differenceBlendMode"
        parentLayer.addSublayer(rectLayer)

        // Pill background
        pillBgLayer.fillColor = normalPillBg
        pillBgLayer.strokeColor = nil
        pillBgLayer.shadowColor = CGColor(gray: 0, alpha: 0.3)
        pillBgLayer.shadowOffset = CGSize(width: 0, height: -1)
        pillBgLayer.shadowRadius = 3
        pillBgLayer.shadowOpacity = 1.0
        parentLayer.addSublayer(pillBgLayer)

        // Pill text
        pillTextLayer.font = Self.font
        pillTextLayer.fontSize = 12
        pillTextLayer.foregroundColor = CGColor(gray: 1.0, alpha: 1.0)
        pillTextLayer.alignmentMode = .center
        pillTextLayer.truncationMode = .none
        pillTextLayer.contentsScale = scale
        parentLayer.addSublayer(pillTextLayer)

        // Start hidden (shown after snap)
        pillBgLayer.opacity = 0
        pillTextLayer.opacity = 0
    }

    /// Update the selection rectangle (during drag or snap).
    func updateRect(_ newRect: CGRect, animated: Bool) {
        rect = newRect

        if animated {
            // Don't disable actions — let CA animate
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }

        // Stroke sits outside: outset by half line width
        let strokeInset = -rectLayer.lineWidth / 2
        rectLayer.path = CGPath(rect: rect.insetBy(dx: strokeInset, dy: strokeInset), transform: nil)
        fillLayer.path = CGPath(rect: rect, transform: nil)

        if !animated {
            CATransaction.commit()
        }
    }

    /// Animate snap to detected edges, then show dimensions pill with slide-down + fade.
    func animateSnap(to newRect: CGRect, w: Int, h: Int) {
        dimensionW = w
        dimensionH = h

        // Remove dash pattern for finalized selection
        rectLayer.lineDashPattern = nil

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        rect = newRect
        let strokeInset = -rectLayer.lineWidth / 2
        rectLayer.path = CGPath(rect: newRect.insetBy(dx: strokeInset, dy: strokeInset), transform: nil)
        fillLayer.path = CGPath(rect: newRect, transform: nil)

        CATransaction.commit()

        // Place pill at final position, invisible (no implicit animations)
        setDimensionsText(w: w, h: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutPill()
        pillBgLayer.opacity = 1
        pillTextLayer.opacity = 1
        CATransaction.commit()

        // Explicit slide-down + fade-in from offset position
        let duration: CFTimeInterval = 0.2
        let timing = CAMediaTimingFunction(name: .easeOut)

        for layer in [pillBgLayer, pillTextLayer] as [CALayer] {
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

    func setHovered(_ hovered: Bool) {
        let newState: State = hovered ? .hovered : .normal
        guard newState != state else { return }
        state = newState

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        rectLayer.strokeColor = hovered ? hoveredStroke : normalStroke
        rectLayer.compositingFilter = hovered ? nil : "differenceBlendMode"
        fillLayer.fillColor = hovered ? hoveredFill : normalFill
        pillBgLayer.fillColor = hovered ? hoveredPillBg : normalPillBg

        if hovered {
            setClearText()
        } else {
            setDimensionsText(w: dimensionW, h: dimensionH)
            layoutPill()
        }

        CATransaction.commit()
    }

    /// Shake horizontally (macOS login rejection idiom) then fade out and remove.
    func shakeAndRemove() {
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [0, -10, 10, -6, 6, -2, 2, 0]
        shake.keyTimes = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0] as [NSNumber]
        shake.duration = 0.4
        shake.isAdditive = true

        let layers: [CALayer] = [rectLayer, fillLayer, pillBgLayer, pillTextLayer]

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.remove(animated: true)
        }
        for layer in layers {
            layer.add(shake, forKey: "shake")
        }
        CATransaction.commit()
    }

    func remove(animated: Bool) {
        let layers: [CALayer] = [rectLayer, fillLayer, pillBgLayer, pillTextLayer]
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
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
    func contains(_ point: CGPoint) -> Bool {
        let padding: CGFloat = 4
        return rect.insetBy(dx: -padding, dy: -padding).contains(point)
    }

    // MARK: - Text helpers

    private func setDimensionsText(w: Int, h: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
            .kern: -0.36 as CGFloat,
        ]
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor(white: 1, alpha: 0.5),
            .kern: -0.36 as CGFloat,
            .baselineOffset: 1.0 as CGFloat,
        ]

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: "\(w)", attributes: attrs))
        str.append(NSAttributedString(string: " \u{00D7} ", attributes: dimAttrs))
        str.append(NSAttributedString(string: "\(h)", attributes: attrs))
        pillTextLayer.string = str
    }

    private func setClearText() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
            .kern: -0.36 as CGFloat,
        ]
        pillTextLayer.string = NSAttributedString(string: "Clear", attributes: attrs)
        layoutPill()
    }

    // MARK: - Pill layout

    private func layoutPill() {
        guard let str = pillTextLayer.string as? NSAttributedString else { return }
        let textSize = str.size()
        let pillW = ceil(textSize.width) + pillPadH * 2
        let textH = ceil(textSize.height)

        // Position pill below the selection rect (or above if near bottom)
        let pillX = round(rect.midX - pillW / 2)
        var pillY = round(rect.minY - pillGap - pillHeight)
        if pillY < 8 {
            pillY = round(rect.maxY + pillGap)
        }

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillHeight)
        pillBgLayer.frame = pillRect
        pillBgLayer.path = squirclePath(rect: CGRect(origin: .zero, size: pillRect.size),
                                         radius: pillRadius)

        let textY = round(pillY + (pillHeight - textH) / 2)
        pillTextLayer.frame = CGRect(x: pillX, y: textY, width: pillW, height: textH)
    }

    // MARK: - Squircle path

    /// Rounded rect with continuous (squircle) corners.
    private func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let path = CGMutablePath()

        // Top edge
        path.move(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))

        // Top-right
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                      control1: CGPoint(x: rect.maxX - r * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - r * (1 - k)))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))

        // Bottom-right
        path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + r * (1 - k)),
                      control2: CGPoint(x: rect.maxX - r * (1 - k), y: rect.minY))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))

        // Bottom-left
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                      control1: CGPoint(x: rect.minX + r * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + r * (1 - k)))

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))

        // Top-left
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - r * (1 - k)),
                      control2: CGPoint(x: rect.minX + r * (1 - k), y: rect.maxY))

        path.closeSubpath()
        return path
    }
}
