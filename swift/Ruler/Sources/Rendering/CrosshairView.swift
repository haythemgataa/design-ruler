import AppKit
import CoreText
import QuartzCore

/// GPU-composited crosshair using CAShapeLayer.
/// No draw() override — only layer property updates on mouse move.
final class CrosshairView: NSView {
    var cursorPosition: NSPoint = .zero
    var screenFrame: CGRect = .zero

    // Crosshair layers
    private let linesLayer = CAShapeLayer()
    private let leftFoot = CAShapeLayer()
    private let rightFoot = CAShapeLayer()
    private let topFoot = CAShapeLayer()
    private let bottomFoot = CAShapeLayer()

    // Pill section backgrounds
    private let wBgLayer = CAShapeLayer()
    private let hBgLayer = CAShapeLayer()

    // Label layers (W / H)
    private let wLabelLayer = CATextLayer()
    private let hLabelLayer = CATextLayer()

    // Value text layers
    private let wValueLayer = CATextLayer()
    private let hValueLayer = CATextLayer()

    // Crosshair constants
    private let crossFootHalf: CGFloat = 4.0

    // Pill layout constants
    private let pillHeight: CGFloat = 24
    private let sectionGap: CGFloat = 2
    private let outerRadius: CGFloat = 8
    private let innerRadius: CGFloat = 4
    private let labelValueGap: CGFloat = 4
    private let wPadLeft: CGFloat = 8
    private let wPadRight: CGFloat = 6
    private let hPadLeft: CGFloat = 6
    private let hPadRight: CGFloat = 8

    // Pill position state (for swap animation)
    private var pillIsOnLeft = false
    private var pillIsBelow = false

    // System crosshair cursor (before first mouse move)
    private var showSystemCrosshair = true

    // Cross-foot colors (difference blend)
    private let lineColor = CGColor(gray: 1.0, alpha: 1.0)
    private let absorbedFootColor = CGColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1.0)

    // Font (SF Pro 12px Semibold with OpenType features for values)
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    override func resetCursorRects() {
        if showSystemCrosshair {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    /// Hide all crosshair elements (lines, feet, pill) during drag.
    func hideForDrag() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        linesLayer.opacity = 0
        leftFoot.opacity = 0
        rightFoot.opacity = 0
        topFoot.opacity = 0
        bottomFoot.opacity = 0
        for pl in pillLayers { pl.opacity = 0 }
        CATransaction.commit()
    }

    /// Show all crosshair elements after drag ends.
    func showAfterDrag() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        linesLayer.opacity = 1
        leftFoot.opacity = 1
        rightFoot.opacity = 1
        topFoot.opacity = 1
        bottomFoot.opacity = 1
        for pl in pillLayers { pl.opacity = 1 }
        CATransaction.commit()
    }

    /// Switch from system crosshair to hidden cursor (custom CAShapeLayer takes over).
    func hideSystemCrosshair() {
        showSystemCrosshair = false
        window?.invalidateCursorRects(for: self)
        NSCursor.hide()
    }

    /// Skip the system crosshair phase without calling NSCursor.hide().
    /// Used when transitioning to a screen where the mouse has already moved
    /// (avoids incrementing the hide counter or flashing the system crosshair).
    func skipSystemCrosshairPhase() {
        showSystemCrosshair = false
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let scale = window?.backingScaleFactor else { return }
        // Set contentsScale on ALL layers — shape layers need it for crisp
        // rendering on non-Retina / mixed-DPI displays
        for sl in [linesLayer, leftFoot, rightFoot, topFoot, bottomFoot, wBgLayer, hBgLayer] {
            sl.contentsScale = scale
        }
        for tl in [wLabelLayer, hLabelLayer, wValueLayer, hValueLayer] {
            tl.contentsScale = scale
        }
    }

    private func setupLayers() {
        guard let root = layer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Crosshair lines — white + difference blend → black on light, white on dark
        linesLayer.strokeColor = lineColor
        linesLayer.lineWidth = 1.0
        linesLayer.fillColor = nil
        linesLayer.compositingFilter = "differenceBlendMode"
        linesLayer.frame = bounds
        root.addSublayer(linesLayer)

        // Cross-foot ticks — one layer per direction for independent color control
        for foot in [leftFoot, rightFoot, topFoot, bottomFoot] {
            foot.strokeColor = lineColor
            foot.lineWidth = 1.0
            foot.fillColor = nil
            foot.compositingFilter = "differenceBlendMode"
            foot.frame = bounds
            root.addSublayer(foot)
        }

        // Pill section backgrounds
        let bgColor = CGColor(gray: 0, alpha: 0.8)
        for bg in [wBgLayer, hBgLayer] {
            bg.fillColor = bgColor
            bg.strokeColor = nil
            bg.shadowColor = CGColor(gray: 0, alpha: 0.3)
            bg.shadowOffset = CGSize(width: 0, height: -1)
            bg.shadowRadius = 3
            bg.shadowOpacity = 1.0
            root.addSublayer(bg)
        }

        // Text layers
        for tl in [wLabelLayer, hLabelLayer, wValueLayer, hValueLayer] {
            tl.contentsScale = scale
            tl.truncationMode = .none
            tl.isWrapped = false
            tl.alignmentMode = .left
            tl.allowsFontSubpixelQuantization = true
            root.addSublayer(tl)
        }
    }

    /// Batch-update cursor + edges. Only updates layer properties (GPU-composited).
    func update(cursor: NSPoint, edges: DirectionalEdges) {
        cursorPosition = cursor

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let cx = cursor.x
        let cy = cursor.y
        let vw = bounds.width
        let vh = bounds.height

        let leftX = edges.left.map { cx - $0.distance } ?? 0
        let rightX = edges.right.map { cx + $0.distance } ?? vw
        let topY = edges.top.map { cy + $0.distance } ?? vh
        let bottomY = edges.bottom.map { cy - $0.distance } ?? 0

        // --- Lines path ---
        let path = CGMutablePath()
        path.move(to: CGPoint(x: leftX, y: cy))
        path.addLine(to: CGPoint(x: cx - 1, y: cy))
        path.move(to: CGPoint(x: cx + 1, y: cy))
        path.addLine(to: CGPoint(x: rightX, y: cy))
        path.move(to: CGPoint(x: cx, y: bottomY))
        path.addLine(to: CGPoint(x: cx, y: cy - 1))
        path.move(to: CGPoint(x: cx, y: cy + 1))
        path.addLine(to: CGPoint(x: cx, y: topY))
        linesLayer.path = path

        // --- Cross-feet (absorbed: green, thicker, longer) ---
        let hf = crossFootHalf
        let ahf = crossFootHalf * 1.5  // absorbed feet are 50% longer

        let la = edges.left?.borderAbsorbed ?? false
        let ra = edges.right?.borderAbsorbed ?? false
        let ta = edges.top?.borderAbsorbed ?? false
        let ba = edges.bottom?.borderAbsorbed ?? false

        updateFoot(leftFoot, edge: edges.left, absorbed: la,
                   p1: CGPoint(x: leftX, y: cy - (la ? ahf : hf)),
                   p2: CGPoint(x: leftX, y: cy + (la ? ahf : hf)))
        updateFoot(rightFoot, edge: edges.right, absorbed: ra,
                   p1: CGPoint(x: rightX, y: cy - (ra ? ahf : hf)),
                   p2: CGPoint(x: rightX, y: cy + (ra ? ahf : hf)))
        updateFoot(topFoot, edge: edges.top, absorbed: ta,
                   p1: CGPoint(x: cx - (ta ? ahf : hf), y: topY),
                   p2: CGPoint(x: cx + (ta ? ahf : hf), y: topY))
        updateFoot(bottomFoot, edge: edges.bottom, absorbed: ba,
                   p1: CGPoint(x: cx - (ba ? ahf : hf), y: bottomY),
                   p2: CGPoint(x: cx + (ba ? ahf : hf), y: bottomY))

        CATransaction.commit()

        // --- Dimension pill (separate transaction for swap animation) ---
        let w = Int(rightX - leftX)
        let h = Int(topY - bottomY)

        layoutPill(cx: cx, cy: cy, vw: vw, w: w, h: h)
    }

    // MARK: - Initial pill

    /// Show the pill at cursor position with zero values, fading in.
    func showInitialPill(at point: NSPoint) {
        cursorPosition = point
        let cx = point.x
        let cy = point.y
        let vw = bounds.width

        // Position and layout with zeros (no actions — set opacity to 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pillLayer in pillLayers { pillLayer.opacity = 0 }
        CATransaction.commit()

        layoutPill(cx: cx, cy: cy, vw: vw, w: 0, h: 0)

        // Fade in
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for pillLayer in pillLayers { pillLayer.opacity = 1 }
        CATransaction.commit()
    }

    private var pillLayers: [CALayer] {
        [wBgLayer, hBgLayer, wLabelLayer, hLabelLayer, wValueLayer, hValueLayer]
    }

    // MARK: - Pill layout

    private func layoutPill(cx: CGFloat, cy: CGFloat, vw: CGFloat, w: Int, h: Int) {
        let wLabAttr = labelText("W")
        let hLabAttr = labelText("H")
        let wValAttr = valueText(w)
        let hValAttr = valueText(h)
        let wLabW = ceil(wLabAttr.size().width)
        let hLabW = ceil(hLabAttr.size().width)
        let wValW = ceil(wValAttr.size().width)
        let hValW = ceil(hValAttr.size().width)
        let textH = ceil(wValAttr.size().height)

        let wSectionW = wPadLeft + wLabW + labelValueGap + wValW + wPadRight
        let hSectionW = hPadLeft + hLabW + labelValueGap + hValW + hPadRight
        let totalPillW = wSectionW + sectionGap + hSectionW

        // Position pill near cursor
        var px = round(cx + 12)
        var py = round(cy - 12 - pillHeight)
        let nowOnLeft = px + totalPillW > vw - 12
        if nowOnLeft { px = round(cx - 12 - totalPillW) }
        let nowBelow = py < 12
        if nowBelow { py = round(cy + 12) }

        // Detect flip
        let flipped = (nowOnLeft != pillIsOnLeft) || (nowBelow != pillIsBelow)
        pillIsOnLeft = nowOnLeft
        pillIsBelow = nowBelow

        CATransaction.begin()
        if flipped {
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        let textY = round(py + (pillHeight - textH) / 2)

        // W section — set frame for position animation, path at local origin
        let wRect = CGRect(x: px, y: py, width: wSectionW, height: pillHeight)
        wBgLayer.frame = wRect
        wBgLayer.path = sectionPath(rect: CGRect(origin: .zero, size: wRect.size),
                                     leftRadius: outerRadius, rightRadius: innerRadius)

        let wLabX = round(wRect.minX + wPadLeft)
        wLabelLayer.string = wLabAttr
        wLabelLayer.frame = CGRect(x: wLabX, y: textY, width: wLabW, height: textH)

        let wValX = round(wLabX + wLabW + labelValueGap)
        wValueLayer.string = wValAttr
        wValueLayer.frame = CGRect(x: wValX, y: textY, width: wValW, height: textH)

        // H section — set frame for position animation, path at local origin
        let hRect = CGRect(x: px + wSectionW + sectionGap, y: py, width: hSectionW, height: pillHeight)
        hBgLayer.frame = hRect
        hBgLayer.path = sectionPath(rect: CGRect(origin: .zero, size: hRect.size),
                                     leftRadius: innerRadius, rightRadius: outerRadius)

        let hLabX = round(hRect.minX + hPadLeft)
        hLabelLayer.string = hLabAttr
        hLabelLayer.frame = CGRect(x: hLabX, y: textY, width: hLabW, height: textH)

        let hValX = round(hLabX + hLabW + labelValueGap)
        hValueLayer.string = hValAttr
        hValueLayer.frame = CGRect(x: hValX, y: textY, width: hValW, height: textH)

        CATransaction.commit()
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

    // MARK: - Foot helper

    private func updateFoot(_ foot: CAShapeLayer, edge: EdgeHit?, absorbed: Bool, p1: CGPoint, p2: CGPoint) {
        guard edge != nil else {
            foot.path = nil
            return
        }
        let path = CGMutablePath()
        path.move(to: p1)
        path.addLine(to: p2)
        foot.path = path
        foot.strokeColor = absorbed ? absorbedFootColor : lineColor
        foot.lineWidth = absorbed ? 2.0 : 1.0
        foot.compositingFilter = absorbed ? nil : "differenceBlendMode"
    }

    // MARK: - Section path

    /// Rounded rect path with different left/right corner radii and continuous (squircle) corners.
    private func sectionPath(rect: CGRect, leftRadius: CGFloat, rightRadius: CGFloat) -> CGPath {
        let lr = min(leftRadius, rect.height / 2)
        let rr = min(rightRadius, rect.height / 2)
        let path = CGMutablePath()

        // Continuous corner kappa — higher than circle's 0.5523 to create squircle shape
        let k: CGFloat = 0.72

        // Top edge
        path.move(to: CGPoint(x: rect.minX + lr, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rr, y: rect.maxY))

        // Top-right corner
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - rr),
                      control1: CGPoint(x: rect.maxX - rr * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - rr * (1 - k)))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rr))

        // Bottom-right corner
        path.addCurve(to: CGPoint(x: rect.maxX - rr, y: rect.minY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + rr * (1 - k)),
                      control2: CGPoint(x: rect.maxX - rr * (1 - k), y: rect.minY))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + lr, y: rect.minY))

        // Bottom-left corner
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + lr),
                      control1: CGPoint(x: rect.minX + lr * (1 - k), y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + lr * (1 - k)))

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lr))

        // Top-left corner
        path.addCurve(to: CGPoint(x: rect.minX + lr, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - lr * (1 - k)),
                      control2: CGPoint(x: rect.minX + lr * (1 - k), y: rect.maxY))

        path.closeSubpath()
        return path
    }
}
