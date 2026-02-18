import AppKit
import QuartzCore

/// GPU-composited crosshair using CAShapeLayer.
/// No draw() override — only layer property updates on mouse move.
package final class CrosshairView: NSView {
    package var cursorPosition: NSPoint = .zero
    package var screenFrame: CGRect = .zero

    // Crosshair layers
    private let linesLayer = CAShapeLayer()
    private let leftFoot = CAShapeLayer()
    private let rightFoot = CAShapeLayer()
    private let topFoot = CAShapeLayer()
    private let bottomFoot = CAShapeLayer()

    // Pill (created by PillRenderer factory in setupLayers)
    private var pill: PillRenderer.DimensionPill!

    // Crosshair constants
    private let crossFootHalf: CGFloat = 4.0

    // Pill layout constants
    private let pillHeight = DesignTokens.Pill.height
    private let sectionGap = DesignTokens.Pill.sectionGap
    private let outerRadius = DesignTokens.Pill.cornerRadius
    private let innerRadius = DesignTokens.Pill.innerCornerRadius
    private let labelValueGap: CGFloat = 4
    private let wPadLeft: CGFloat = 8
    private let wPadRight: CGFloat = 6
    private let hPadLeft: CGFloat = 6
    private let hPadRight: CGFloat = 8

    // Pill position state (for swap animation)
    private var pillIsOnLeft = false
    private var pillIsBelow = false

    // Cross-foot colors (difference blend)
    private let lineColor = CGColor(gray: 1.0, alpha: 1.0)
    private let absorbedFootColor = CGColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1.0)

    // Font (SF Pro 12px Semibold with OpenType features for values)
    private static let font = PillRenderer.makeDesignFont(size: 12)

    override package init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    package required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    /// Hide all crosshair elements (lines, feet, pill) during drag.
    package func hideForDrag() {
        CATransaction.instant {
            linesLayer.opacity = 0
            leftFoot.opacity = 0
            rightFoot.opacity = 0
            topFoot.opacity = 0
            bottomFoot.opacity = 0
            for pl in pillLayers { pl.opacity = 0 }
        }
    }

    /// Show all crosshair elements after drag ends.
    package func showAfterDrag() {
        CATransaction.instant {
            linesLayer.opacity = 1
            leftFoot.opacity = 1
            rightFoot.opacity = 1
            topFoot.opacity = 1
            bottomFoot.opacity = 1
            for pl in pillLayers { pl.opacity = 1 }
        }
    }

    override package func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let scale = window?.backingScaleFactor else { return }
        // Set contentsScale on ALL layers — shape layers need it for crisp
        // rendering on non-Retina / mixed-DPI displays
        for sl in [linesLayer, leftFoot, rightFoot, topFoot, bottomFoot] {
            sl.contentsScale = scale
        }
        for pl in pill.allLayers {
            pl.contentsScale = scale
        }
    }

    private func setupLayers() {
        guard let root = layer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Crosshair lines — white + difference blend → black on light, white on dark
        linesLayer.strokeColor = lineColor
        linesLayer.lineWidth = 1.0
        linesLayer.fillColor = nil
        linesLayer.compositingFilter = BlendMode.difference
        linesLayer.frame = bounds
        root.addSublayer(linesLayer)

        // Cross-foot ticks — one layer per direction for independent color control
        for foot in [leftFoot, rightFoot, topFoot, bottomFoot] {
            foot.strokeColor = lineColor
            foot.lineWidth = 1.0
            foot.fillColor = nil
            foot.compositingFilter = BlendMode.difference
            foot.frame = bounds
            root.addSublayer(foot)
        }

        // Pill (backgrounds + text layers created by factory)
        pill = PillRenderer.makeDimensionPill(parentLayer: root, scale: scale)
    }

    /// Batch-update cursor + edges. Only updates layer properties (GPU-composited).
    package func update(cursor: NSPoint, edges: DirectionalEdges) {
        cursorPosition = cursor

        let cx = cursor.x
        let cy = cursor.y
        let vw = bounds.width
        let vh = bounds.height

        let leftX = edges.left.map { cx - $0.distance } ?? 0
        let rightX = edges.right.map { cx + $0.distance } ?? vw
        let topY = edges.top.map { cy + $0.distance } ?? vh
        let bottomY = edges.bottom.map { cy - $0.distance } ?? 0

        CATransaction.instant {
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
        }

        // --- Dimension pill (separate transaction for swap animation) ---
        let w = Int(rightX - leftX)
        let h = Int(topY - bottomY)

        layoutPill(cx: cx, cy: cy, vw: vw, w: w, h: h)
    }

    // MARK: - Initial pill

    /// Show the pill at cursor position with zero values, fading in.
    package func showInitialPill(at point: NSPoint) {
        cursorPosition = point
        let cx = point.x
        let cy = point.y
        let vw = bounds.width

        // Position and layout with zeros (no actions — set opacity to 0)
        CATransaction.instant {
            for pillLayer in pillLayers { pillLayer.opacity = 0 }
        }

        layoutPill(cx: cx, cy: cy, vw: vw, w: 0, h: 0)

        // Fade in
        CATransaction.animated(duration: DesignTokens.Animation.slow) {
            for pillLayer in pillLayers { pillLayer.opacity = 1 }
        }
    }

    private var pillLayers: [CALayer] {
        pill.allLayers
    }

    // MARK: - Pill layout

    private func layoutPill(cx: CGFloat, cy: CGFloat, vw: CGFloat, w: Int, h: Int) {
        let wLabAttr = PillRenderer.labelText("W")
        let hLabAttr = PillRenderer.labelText("H")
        let wValAttr = PillRenderer.valueText(w)
        let hValAttr = PillRenderer.valueText(h)
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

        let pillBody = {
            let textY = round(py + (self.pillHeight - textH) / 2)

            // W section — set frame for position animation, path at local origin
            let wRect = CGRect(x: px, y: py, width: wSectionW, height: self.pillHeight)
            self.pill.wBgLayer.frame = wRect
            self.pill.wBgLayer.path = PillRenderer.sectionPath(rect: CGRect(origin: .zero, size: wRect.size),
                                         leftRadius: self.outerRadius, rightRadius: self.innerRadius)

            let wLabX = round(wRect.minX + self.wPadLeft)
            self.pill.wLabelLayer.string = wLabAttr
            self.pill.wLabelLayer.frame = CGRect(x: wLabX, y: textY, width: wLabW, height: textH)

            let wValX = round(wLabX + wLabW + self.labelValueGap)
            self.pill.wValueLayer.string = wValAttr
            self.pill.wValueLayer.frame = CGRect(x: wValX, y: textY, width: wValW, height: textH)

            // H section — set frame for position animation, path at local origin
            let hRect = CGRect(x: px + wSectionW + self.sectionGap, y: py, width: hSectionW, height: self.pillHeight)
            self.pill.hBgLayer.frame = hRect
            self.pill.hBgLayer.path = PillRenderer.sectionPath(rect: CGRect(origin: .zero, size: hRect.size),
                                         leftRadius: self.innerRadius, rightRadius: self.outerRadius)

            let hLabX = round(hRect.minX + self.hPadLeft)
            self.pill.hLabelLayer.string = hLabAttr
            self.pill.hLabelLayer.frame = CGRect(x: hLabX, y: textY, width: hLabW, height: textH)

            let hValX = round(hLabX + hLabW + self.labelValueGap)
            self.pill.hValueLayer.string = hValAttr
            self.pill.hValueLayer.frame = CGRect(x: hValX, y: textY, width: hValW, height: textH)
        }

        if flipped {
            CATransaction.animated(duration: DesignTokens.Animation.fast, pillBody)
        } else {
            CATransaction.instant(pillBody)
        }
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
        foot.compositingFilter = absorbed ? nil : BlendMode.difference
    }
}
