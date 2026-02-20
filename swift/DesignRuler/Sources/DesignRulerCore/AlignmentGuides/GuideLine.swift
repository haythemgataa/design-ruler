import AppKit
import QuartzCore

/// Direction for guide lines
package enum Direction {
    case vertical, horizontal

    package func toggled() -> Direction {
        self == .vertical ? .horizontal : .vertical
    }
}

/// A single guide line rendered as CALayers (line + position pill).
/// Used for both preview line and placed lines.
package final class GuideLine {
    package let direction: Direction
    package var position: CGFloat
    package let style: GuideLineStyle
    package let isPreview: Bool

    // Layers
    private let lineLayer = CAShapeLayer()
    private var pill: PillRenderer.PositionPill!

    private weak var parentLayer: CALayer?
    private let scale: CGFloat

    // Hover state
    package private(set) var isHovered = false
    package var isInRemoveMode = false

    // Pill position state (for swap animation)
    private var pillOnFarSide = false
    private var pillBelowOrAfter = false

    // Pill layout constants (matching CrosshairView)
    private let pillHeight = DesignTokens.Pill.height
    private let outerRadius = DesignTokens.Pill.cornerRadius
    private let labelValueGap: CGFloat = 4
    private let padLeft: CGFloat = 8
    private let padRight: CGFloat = 8

    // Font (SF Pro 12px Semibold with OpenType features)
    private static let font = PillRenderer.makeDesignFont(size: 12)

    package init(direction: Direction, position: CGFloat, style: GuideLineStyle, isPreview: Bool, parentLayer: CALayer, scale: CGFloat) {
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
            lineLayer.compositingFilter = BlendMode.difference
        }
        lineLayer.contentsScale = scale
        parent.addSublayer(lineLayer)

        // Pill (background + text layers created by factory)
        pill = PillRenderer.makePositionPill(parentLayer: parent, scale: scale)

        // Set initial opacity for preview vs placed
        if isPreview {
            let opacity: Float = 1.0
            pill.bgLayer.opacity = opacity
            pill.labelLayer.opacity = opacity
            pill.valueLayer.opacity = opacity
        } else {
            // Placed lines don't show coordinate pills
            pill.bgLayer.opacity = 0
            pill.labelLayer.opacity = 0
            pill.valueLayer.opacity = 0
        }
    }

    /// Update line path, pill position/text based on current position + cursor location.
    package func update(position: CGFloat, cursorAlongAxis: CGFloat, screenSize: CGSize, direction: Direction, style: GuideLineStyle) {
        self.position = position

        // Line update — always instant
        CATransaction.instant {
            let linePath = CGMutablePath()
            if direction == .vertical {
                linePath.move(to: CGPoint(x: position, y: 0))
                linePath.addLine(to: CGPoint(x: position, y: screenSize.height))
            } else {
                linePath.move(to: CGPoint(x: 0, y: position))
                linePath.addLine(to: CGPoint(x: screenSize.width, y: position))
            }
            lineLayer.path = linePath

            lineLayer.strokeColor = style.color
            if style.useDifferenceBlend {
                lineLayer.compositingFilter = BlendMode.difference
            } else {
                lineLayer.compositingFilter = nil
            }
        }

        // Pill update — animated on flip, instant otherwise
        layoutPill(position: position, cursorAlongAxis: cursorAlongAxis, screenSize: screenSize, direction: direction)
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
                .kern: DesignTokens.Pill.kerning,
            ])
            bgColor = DesignTokens.Color.removePillBg
            pillOpacity = 1.0
        } else {
            let label = direction == .vertical ? "X" : "Y"
            let value = Int(round(position))
            labelAttr = PillRenderer.labelText(label)
            valueAttr = PillRenderer.valueText(value)
            bgColor = DesignTokens.Pill.backgroundColor
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
        var nowFarSide = false
        var nowBelowOrAfter = false

        if direction == .vertical {
            // Vertical line: pill to the right (or left if near right edge)
            let onRight = position + 8 + pillW < screenSize.width - 12
            nowFarSide = !onRight
            pillX = onRight ? position + 8 : position - 8 - pillW

            // Position along axis relative to cursor (12px offset)
            pillY = cursorAlongAxis - 12 - pillHeight
            nowBelowOrAfter = pillY < 12
            if nowBelowOrAfter { pillY = cursorAlongAxis + 12 }
        } else {
            // Horizontal line: pill above (or below if near top)
            let above = position - 8 - pillHeight > 12
            nowFarSide = !above
            pillY = above ? position - 8 - pillHeight : position + 8

            // Position along axis relative to cursor (12px offset)
            pillX = cursorAlongAxis + 12
            nowBelowOrAfter = pillX + pillW > screenSize.width - 12
            if nowBelowOrAfter {
                pillX = cursorAlongAxis - 12 - pillW
            }
        }

        // Detect flip
        let flipped = (nowFarSide != pillOnFarSide) || (nowBelowOrAfter != pillBelowOrAfter)
        pillOnFarSide = nowFarSide
        pillBelowOrAfter = nowBelowOrAfter

        let pillBody = {
            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: self.pillHeight)
            let textY = round(pillY + (self.pillHeight - textH) / 2)

            // Pill background — frame for position, path at local origin
            self.pill.bgLayer.frame = pillRect
            self.pill.bgLayer.path = PillRenderer.squirclePath(rect: CGRect(origin: .zero, size: pillRect.size), radius: self.outerRadius)
            self.pill.bgLayer.fillColor = bgColor
            self.pill.bgLayer.opacity = pillOpacity

            // Label layer
            let labelX = round(pillX + self.padLeft)
            self.pill.labelLayer.string = labelAttr
            self.pill.labelLayer.frame = CGRect(x: labelX, y: textY, width: labelW, height: textH)
            self.pill.labelLayer.opacity = pillOpacity

            // Value layer
            let valueX = round(labelX + labelW + gap)
            self.pill.valueLayer.string = valueAttr
            self.pill.valueLayer.frame = CGRect(x: valueX, y: textY, width: valueW, height: textH)
            self.pill.valueLayer.opacity = pillOpacity
        }

        if flipped {
            CATransaction.animated(duration: DesignTokens.Animation.fast, pillBody)
        } else {
            CATransaction.instant(pillBody)
        }
    }

    /// Set opacity on all layers (for fade in/out).
    package func setOpacity(_ opacity: Float, animated: Bool) {
        let body = {
            self.lineLayer.opacity = opacity
            // Only touch pill layers for preview lines; placed lines keep pills hidden
            if self.isPreview {
                self.pill.bgLayer.opacity = opacity
                self.pill.labelLayer.opacity = opacity
                self.pill.valueLayer.opacity = opacity
            }
        }
        if animated {
            CATransaction.animated(duration: DesignTokens.Animation.fast, body)
        } else {
            CATransaction.instant(body)
        }
    }

    /// Set hover state: red + dashed line visual on placed lines.
    package func setHovered(_ isHovered: Bool, cursorPosition: CGPoint) {
        CATransaction.instant {
            if isHovered {
                self.isHovered = true
                lineLayer.strokeColor = DesignTokens.Color.hoverRed
                lineLayer.lineDashPattern = [4, 3]
                lineLayer.compositingFilter = nil
            } else {
                self.isHovered = false
                lineLayer.strokeColor = style.color
                lineLayer.lineDashPattern = nil
                if style.useDifferenceBlend {
                    lineLayer.compositingFilter = BlendMode.difference
                }
            }
        }
    }

    /// Hide pill layers instantly (used when color indicator is visible).
    package func hidePill() {
        CATransaction.instant {
            pill.bgLayer.opacity = 0
            pill.labelLayer.opacity = 0
            pill.valueLayer.opacity = 0
        }
    }

    /// Show or hide the line layer (used to hide preview line during hover-to-remove).
    package func setLineVisible(_ visible: Bool) {
        CATransaction.instant {
            lineLayer.opacity = visible ? 1.0 : 0
        }
    }

    /// Shrink line toward click point with path animation, then call completion.
    package func shrinkToPoint(_ clickPoint: CGPoint, screenSize: CGSize, completion: @escaping () -> Void) {
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
        pathAnim.duration = DesignTokens.Animation.standard
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        pathAnim.fillMode = .forwards
        pathAnim.isRemovedOnCompletion = false
        lineLayer.add(pathAnim, forKey: "shrink")

        CATransaction.commit()
    }

    /// Remove all sublayers from parent.
    package func remove(animated: Bool) {
        if animated {
            setOpacity(0, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + DesignTokens.Animation.fast) { [weak self] in
                self?.removeLayers()
            }
        } else {
            removeLayers()
        }
    }

    private func removeLayers() {
        lineLayer.removeFromSuperlayer()
        pill.bgLayer.removeFromSuperlayer()
        pill.labelLayer.removeFromSuperlayer()
        pill.valueLayer.removeFromSuperlayer()
    }
}
