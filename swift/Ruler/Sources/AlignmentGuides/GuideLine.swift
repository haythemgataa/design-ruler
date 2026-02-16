import AppKit
import CoreText
import QuartzCore

/// Direction for guide lines
enum Direction {
    case vertical, horizontal

    func toggled() -> Direction {
        self == .vertical ? .horizontal : .vertical
    }
}

/// A single guide line rendered as CALayers (line + position pill).
/// Used for both preview line and placed lines.
final class GuideLine {
    let direction: Direction
    var position: CGFloat
    let style: GuideLineStyle
    let isPreview: Bool

    // Layers
    private let lineLayer = CAShapeLayer()
    private let pillBgLayer = CAShapeLayer()
    private let pillLabelLayer = CATextLayer()
    private let pillValueLayer = CATextLayer()

    private weak var parentLayer: CALayer?
    private let scale: CGFloat

    // Hover state
    private(set) var isHovered = false
    var isInRemoveMode = false

    // Pill layout constants (matching CrosshairView)
    private let pillHeight: CGFloat = 24
    private let outerRadius: CGFloat = 8
    private let labelValueGap: CGFloat = 4
    private let padLeft: CGFloat = 8
    private let padRight: CGFloat = 8

    // Font (SF Pro 12px Semibold with OpenType features)
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let tags = ["ss01", "ss02", "cv01", "cv02", "cv08", "cv12", "lnum", "tnum"]
        let features: [[String: Any]] = tags.map { tag in
            [kCTFontOpenTypeFeatureTag as String: tag, kCTFontOpenTypeFeatureValue as String: 1]
        }
        let desc = CTFontDescriptorCreateWithAttributes(
            [kCTFontFeatureSettingsAttribute: features] as CFDictionary
        )
        let ctFont = CTFontCreateCopyWithAttributes(base as CTFont, 12, nil, desc)
        return ctFont as NSFont
    }()

    init(direction: Direction, position: CGFloat, style: GuideLineStyle, isPreview: Bool, parentLayer: CALayer, scale: CGFloat) {
        self.direction = direction
        self.position = position
        self.style = style
        self.isPreview = isPreview
        self.parentLayer = parentLayer
        self.scale = scale

        setupLayers()
    }

    private func setupLayers() {
        guard let parent = parentLayer else { return }

        // Line layer
        lineLayer.strokeColor = style.color
        lineLayer.lineWidth = 1.0
        lineLayer.fillColor = nil
        if style.useDifferenceBlend {
            lineLayer.compositingFilter = "differenceBlendMode"
        }
        lineLayer.contentsScale = scale
        parent.addSublayer(lineLayer)

        // Pill background
        let bgColor = CGColor(gray: 0, alpha: 0.8)
        pillBgLayer.fillColor = bgColor
        pillBgLayer.strokeColor = nil
        pillBgLayer.shadowColor = CGColor(gray: 0, alpha: 0.3)
        pillBgLayer.shadowOffset = CGSize(width: 0, height: -1)
        pillBgLayer.shadowRadius = 3
        pillBgLayer.shadowOpacity = 1.0
        pillBgLayer.contentsScale = scale
        parent.addSublayer(pillBgLayer)

        // Text layers
        for tl in [pillLabelLayer, pillValueLayer] {
            tl.contentsScale = scale
            tl.truncationMode = .none
            tl.isWrapped = false
            tl.alignmentMode = .left
            tl.allowsFontSubpixelQuantization = true
            parent.addSublayer(tl)
        }

        // Set initial opacity for preview vs placed
        if isPreview {
            let opacity: Float = 1.0
            pillBgLayer.opacity = opacity
            pillLabelLayer.opacity = opacity
            pillValueLayer.opacity = opacity
        } else {
            // Placed lines don't show coordinate pills
            pillBgLayer.opacity = 0
            pillLabelLayer.opacity = 0
            pillValueLayer.opacity = 0
        }
    }

    /// Update line path, pill position/text based on current position + cursor location.
    func update(position: CGFloat, cursorAlongAxis: CGFloat, screenSize: CGSize, direction: Direction, style: GuideLineStyle) {
        self.position = position

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update line path
        let linePath = CGMutablePath()
        if direction == .vertical {
            // Full-height vertical line
            linePath.move(to: CGPoint(x: position, y: 0))
            linePath.addLine(to: CGPoint(x: position, y: screenSize.height))
        } else {
            // Full-width horizontal line
            linePath.move(to: CGPoint(x: 0, y: position))
            linePath.addLine(to: CGPoint(x: screenSize.width, y: position))
        }
        lineLayer.path = linePath

        // Update style
        lineLayer.strokeColor = style.color
        if style.useDifferenceBlend {
            lineLayer.compositingFilter = "differenceBlendMode"
        } else {
            lineLayer.compositingFilter = nil
        }

        // Update pill
        layoutPill(position: position, cursorAlongAxis: cursorAlongAxis, screenSize: screenSize, direction: direction)

        CATransaction.commit()
    }

    private func layoutPill(position: CGFloat, cursorAlongAxis: CGFloat, screenSize: CGSize, direction: Direction) {
        // Placed lines don't show pills
        if !isPreview { return }

        let labelAttr: NSAttributedString
        let valueAttr: NSAttributedString
        let bgColor: CGColor
        let pillOpacity: Float

        if isInRemoveMode {
            labelAttr = NSAttributedString(string: "", attributes: [:])
            valueAttr = NSAttributedString(string: "Remove", attributes: [
                .font: Self.font,
                .foregroundColor: NSColor.white,
                .kern: -0.36 as CGFloat,
            ])
            bgColor = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.9)
            pillOpacity = 1.0
        } else {
            let label = direction == .vertical ? "X" : "Y"
            let value = Int(round(position))
            labelAttr = labelText(label)
            valueAttr = valueText(value)
            bgColor = CGColor(gray: 0, alpha: 0.8)
            pillOpacity = 1.0
        }

        let labelW = ceil(labelAttr.size().width)
        let valueW = ceil(valueAttr.size().width)
        let textH = ceil(valueAttr.size().height)
        let gap = labelW > 0 ? labelValueGap : CGFloat(0)

        let pillW = padLeft + labelW + gap + valueW + padRight

        // Position pill offset from line
        var pillX: CGFloat
        var pillY: CGFloat

        if direction == .vertical {
            // Vertical line: pill to the right (or left if near right edge)
            let onRight = position + 8 + pillW < screenSize.width - 12
            pillX = onRight ? position + 8 : position - 8 - pillW

            // Position along axis relative to cursor (12px offset)
            pillY = cursorAlongAxis - 12 - pillHeight
            if pillY < 12 { pillY = cursorAlongAxis + 12 }
        } else {
            // Horizontal line: pill above (or below if near top)
            let above = position - 8 - pillHeight > 12
            pillY = above ? position - 8 - pillHeight : position + 8

            // Position along axis relative to cursor (12px offset)
            pillX = cursorAlongAxis + 12
            if pillX + pillW > screenSize.width - 12 {
                pillX = cursorAlongAxis - 12 - pillW
            }
        }

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillHeight)
        let textY = round(pillY + (pillHeight - textH) / 2)

        // Pill background — frame for position, path at local origin
        pillBgLayer.frame = pillRect
        pillBgLayer.path = squirclePath(rect: CGRect(origin: .zero, size: pillRect.size), radius: outerRadius)
        pillBgLayer.fillColor = bgColor
        pillBgLayer.opacity = pillOpacity

        // Label layer
        let labelX = round(pillX + padLeft)
        pillLabelLayer.string = labelAttr
        pillLabelLayer.frame = CGRect(x: labelX, y: textY, width: labelW, height: textH)
        pillLabelLayer.opacity = pillOpacity

        // Value layer
        let valueX = round(labelX + labelW + gap)
        pillValueLayer.string = valueAttr
        pillValueLayer.frame = CGRect(x: valueX, y: textY, width: valueW, height: textH)
        pillValueLayer.opacity = pillOpacity
    }

    /// Set opacity on all layers (for fade in/out).
    func setOpacity(_ opacity: Float, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        lineLayer.opacity = opacity
        // Only touch pill layers for preview lines; placed lines keep pills hidden
        if isPreview {
            pillBgLayer.opacity = opacity
            pillLabelLayer.opacity = opacity
            pillValueLayer.opacity = opacity
        }
        CATransaction.commit()
    }

    /// Set hover state: red + dashed line visual on placed lines.
    func setHovered(_ isHovered: Bool, cursorPosition: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if isHovered {
            self.isHovered = true
            lineLayer.strokeColor = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
            lineLayer.lineDashPattern = [4, 3]
            lineLayer.compositingFilter = nil
        } else {
            self.isHovered = false
            lineLayer.strokeColor = style.color
            lineLayer.lineDashPattern = nil
            if style.useDifferenceBlend {
                lineLayer.compositingFilter = "differenceBlendMode"
            }
        }

        CATransaction.commit()
    }

    /// Hide pill layers instantly (used when color indicator is visible).
    func hidePill() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillBgLayer.opacity = 0
        pillLabelLayer.opacity = 0
        pillValueLayer.opacity = 0
        CATransaction.commit()
    }

    /// Show or hide the line layer (used to hide preview line during hover-to-remove).
    func setLineVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineLayer.opacity = visible ? 1.0 : 0
        CATransaction.commit()
    }

    /// Shrink line toward click point with path animation, then call completion.
    func shrinkToPoint(_ clickPoint: CGPoint, screenSize: CGSize, completion: @escaping () -> Void) {
        // Create end path: both endpoints converge to click point along the line
        let endPath = CGMutablePath()
        if direction == .vertical {
            endPath.move(to: CGPoint(x: position, y: clickPoint.y))
            endPath.addLine(to: CGPoint(x: position, y: clickPoint.y))
        } else {
            endPath.move(to: CGPoint(x: clickPoint.x, y: position))
            endPath.addLine(to: CGPoint(x: clickPoint.x, y: position))
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = lineLayer.path
        pathAnim.toValue = endPath
        pathAnim.duration = 0.2
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        pathAnim.fillMode = .forwards
        pathAnim.isRemovedOnCompletion = false
        lineLayer.add(pathAnim, forKey: "shrink")

        CATransaction.commit()
    }

    /// Remove all sublayers from parent.
    func remove(animated: Bool) {
        if animated {
            setOpacity(0, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.removeLayers()
            }
        } else {
            removeLayers()
        }
    }

    private func removeLayers() {
        lineLayer.removeFromSuperlayer()
        pillBgLayer.removeFromSuperlayer()
        pillLabelLayer.removeFromSuperlayer()
        pillValueLayer.removeFromSuperlayer()
    }

    // MARK: - Text helpers

    private func labelText(_ label: String) -> NSAttributedString {
        NSAttributedString(string: label, attributes: [
            .font: Self.font,
            .foregroundColor: NSColor(white: 1, alpha: 0.5),
            .kern: -0.36 as CGFloat,
        ])
    }

    private func valueText(_ value: Int) -> NSAttributedString {
        let padded = String(format: "%04d", min(value, 9999))
        let digitCount = String(value).count
        let zeroCount = max(0, 4 - digitCount)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .kern: -0.36 as CGFloat,
        ]
        let attr = NSMutableAttributedString()
        if zeroCount > 0 {
            var dimAttrs = attrs
            dimAttrs[.foregroundColor] = NSColor(white: 1, alpha: 0.2)
            attr.append(NSAttributedString(string: String(padded.prefix(zeroCount)), attributes: dimAttrs))
        }
        var brightAttrs = attrs
        brightAttrs[.foregroundColor] = NSColor.white
        attr.append(NSAttributedString(string: String(padded.suffix(digitCount)), attributes: brightAttrs))
        return attr
    }

    // MARK: - Squircle path

    private func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, rect.height / 2)
        let path = CGMutablePath()
        let k: CGFloat = 0.72  // continuous corner kappa

        // Top edge
        path.move(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))

        // Top-right corner
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                      control1: CGPoint(x: rect.maxX - r * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - r * (1 - k)))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))

        // Bottom-right corner
        path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + r * (1 - k)),
                      control2: CGPoint(x: rect.maxX - r * (1 - k), y: rect.minY))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))

        // Bottom-left corner
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + r),
                      control1: CGPoint(x: rect.minX + r * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + r * (1 - k)))

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))

        // Top-left corner
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - r * (1 - k)),
                      control2: CGPoint(x: rect.minX + r * (1 - k), y: rect.maxY))

        path.closeSubpath()
        return path
    }
}
