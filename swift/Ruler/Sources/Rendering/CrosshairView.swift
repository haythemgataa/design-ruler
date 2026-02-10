import AppKit
import QuartzCore

/// GPU-composited crosshair using CAShapeLayer.
/// No draw() override — only layer property updates on mouse move.
final class CrosshairView: NSView {
    var cursorPosition: NSPoint = .zero
    var screenFrame: CGRect = .zero

    // Crosshair layers
    private let linesLayer = CAShapeLayer()
    private let feetLayer = CAShapeLayer()

    // Two-section pill layers
    private let wBgLayer = CAShapeLayer()
    private let hBgLayer = CAShapeLayer()
    private let wTextLayer = CATextLayer()
    private let hTextLayer = CATextLayer()

    // Border absorption indicators
    private let wLeftInd = CALayer()
    private let wRightInd = CALayer()
    private let hTopInd = CALayer()
    private let hBottomInd = CALayer()

    private let crossFootHalf: CGFloat = 4.0
    private let pillGap: CGFloat = 2.0
    private let pillPadH: CGFloat = 6.0
    private let pillPadV: CGFloat = 4.0
    private let indThickness: CGFloat = 2.0
    private let fontSize: CGFloat = 10.0

    private let inactiveIndColor = CGColor(gray: 1.0, alpha: 0.2)
    private let activeIndColor = CGColor(srgbRed: 0.29, green: 0.87, blue: 0.50, alpha: 1.0)

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

    private func setupLayers() {
        guard let root = layer else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Crosshair lines — difference blend via compositing filter
        linesLayer.strokeColor = NSColor.orange.cgColor
        linesLayer.lineWidth = 1.0
        linesLayer.fillColor = nil
        linesLayer.compositingFilter = CIFilter(name: "CIDifferenceBlendMode")
        linesLayer.frame = bounds
        root.addSublayer(linesLayer)

        // Cross-foot ticks — same blend
        feetLayer.strokeColor = NSColor.orange.cgColor
        feetLayer.lineWidth = 1.0
        feetLayer.fillColor = nil
        feetLayer.compositingFilter = CIFilter(name: "CIDifferenceBlendMode")
        feetLayer.frame = bounds
        root.addSublayer(feetLayer)

        // Pill section backgrounds
        let bgColor = CGColor(gray: 0, alpha: 0.8)
        wBgLayer.fillColor = bgColor
        wBgLayer.strokeColor = nil
        wBgLayer.frame = bounds
        root.addSublayer(wBgLayer)

        hBgLayer.fillColor = bgColor
        hBgLayer.strokeColor = nil
        hBgLayer.frame = bounds
        root.addSublayer(hBgLayer)

        // Text layers
        for textLayer in [wTextLayer, hTextLayer] {
            textLayer.contentsScale = scale
            textLayer.truncationMode = .none
            textLayer.isWrapped = false
            textLayer.allowsFontSubpixelQuantization = true
            root.addSublayer(textLayer)
        }

        // Border absorption indicators
        for ind in [wLeftInd, wRightInd, hTopInd, hBottomInd] {
            ind.backgroundColor = inactiveIndColor
            ind.cornerRadius = indThickness / 2
            root.addSublayer(ind)
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
        // Horizontal
        path.move(to: CGPoint(x: leftX, y: cy))
        path.addLine(to: CGPoint(x: cx - 1, y: cy))
        path.move(to: CGPoint(x: cx + 1, y: cy))
        path.addLine(to: CGPoint(x: rightX, y: cy))
        // Vertical
        path.move(to: CGPoint(x: cx, y: bottomY))
        path.addLine(to: CGPoint(x: cx, y: cy - 1))
        path.move(to: CGPoint(x: cx, y: cy + 1))
        path.addLine(to: CGPoint(x: cx, y: topY))
        linesLayer.path = path

        // --- Feet path (only at detected edges) ---
        let fp = CGMutablePath()
        let hf = crossFootHalf
        if edges.left != nil {
            fp.move(to: CGPoint(x: leftX, y: cy - hf))
            fp.addLine(to: CGPoint(x: leftX, y: cy + hf))
        }
        if edges.right != nil {
            fp.move(to: CGPoint(x: rightX, y: cy - hf))
            fp.addLine(to: CGPoint(x: rightX, y: cy + hf))
        }
        if edges.top != nil {
            fp.move(to: CGPoint(x: cx - hf, y: topY))
            fp.addLine(to: CGPoint(x: cx + hf, y: topY))
        }
        if edges.bottom != nil {
            fp.move(to: CGPoint(x: cx - hf, y: bottomY))
            fp.addLine(to: CGPoint(x: cx + hf, y: bottomY))
        }
        feetLayer.path = fp

        // --- Dimension pill (two sections: W + H) ---
        let w = Int(rightX - leftX)
        let h = Int(topY - bottomY)

        let wAttr = pillText(label: "W", value: w)
        let hAttr = pillText(label: "H", value: h)
        wTextLayer.string = wAttr
        hTextLayer.string = hAttr

        let wTextSize = wAttr.size()
        let hTextSize = hAttr.size()

        let sectionH = ceil(max(wTextSize.height, hTextSize.height) + pillPadV * 2)
        let wSectionW = ceil(wTextSize.width + pillPadH * 2)
        let hSectionW = ceil(hTextSize.width + pillPadH * 2)
        let totalW = wSectionW + pillGap + hSectionW

        let outerR = sectionH / 2   // semicircle on outer ends
        let innerR: CGFloat = 4.0   // small radius on inner ends

        // Position pill near cursor
        var px = cx + 12
        var py = cy - 12 - sectionH
        if px + totalW > vw - 12 { px = cx - 12 - totalW }
        if py < 12 { py = cy + 12 }

        // W section (left half: pill-rounded left, squared right)
        let wRect = CGRect(x: px, y: py, width: wSectionW, height: sectionH)
        wBgLayer.path = sectionPath(rect: wRect, leftRadius: outerR, rightRadius: innerR)
        wTextLayer.frame = CGRect(
            x: wRect.minX + pillPadH,
            y: wRect.minY + (sectionH - wTextSize.height) / 2,
            width: ceil(wTextSize.width),
            height: ceil(wTextSize.height)
        )

        // H section (right half: squared left, pill-rounded right)
        let hRect = CGRect(x: px + wSectionW + pillGap, y: py, width: hSectionW, height: sectionH)
        hBgLayer.path = sectionPath(rect: hRect, leftRadius: innerR, rightRadius: outerR)
        hTextLayer.frame = CGRect(
            x: hRect.minX + pillPadH,
            y: hRect.minY + (sectionH - hTextSize.height) / 2,
            width: ceil(hTextSize.width),
            height: ceil(hTextSize.height)
        )

        // --- Border absorption indicators ---
        let indInsetV: CGFloat = 3.0   // inset from top/bottom for vertical indicators
        let indInsetH: CGFloat = 4.0   // inset from left/right for horizontal indicators
        let vIndH = sectionH - indInsetV * 2
        let hIndW = hSectionW - indInsetH * 2

        // W: left indicator (vertical line at left edge)
        wLeftInd.frame = CGRect(
            x: wRect.minX + 3, y: wRect.minY + indInsetV,
            width: indThickness, height: vIndH
        )
        wLeftInd.backgroundColor = (edges.left?.borderAbsorbed ?? false) ? activeIndColor : inactiveIndColor

        // W: right indicator (vertical line at right edge)
        wRightInd.frame = CGRect(
            x: wRect.maxX - 3 - indThickness, y: wRect.minY + indInsetV,
            width: indThickness, height: vIndH
        )
        wRightInd.backgroundColor = (edges.right?.borderAbsorbed ?? false) ? activeIndColor : inactiveIndColor

        // H: top indicator (horizontal line at top edge)
        hTopInd.frame = CGRect(
            x: hRect.minX + indInsetH, y: hRect.maxY - 3 - indThickness,
            width: hIndW, height: indThickness
        )
        hTopInd.backgroundColor = (edges.top?.borderAbsorbed ?? false) ? activeIndColor : inactiveIndColor

        // H: bottom indicator (horizontal line at bottom edge)
        hBottomInd.frame = CGRect(
            x: hRect.minX + indInsetH, y: hRect.minY + 3,
            width: hIndW, height: indThickness
        )
        hBottomInd.backgroundColor = (edges.bottom?.borderAbsorbed ?? false) ? activeIndColor : inactiveIndColor

        CATransaction.commit()
    }

    // MARK: - Helpers

    private func pillText(label: String, value: Int) -> NSAttributedString {
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: "\(label)  ", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.5)
        ]))
        attr.append(NSAttributedString(string: "\(value)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]))
        return attr
    }

    /// Rounded rect path with different left/right corner radii.
    private func sectionPath(rect: CGRect, leftRadius: CGFloat, rightRadius: CGFloat) -> CGPath {
        let lr = min(leftRadius, rect.height / 2)
        let rr = min(rightRadius, rect.height / 2)
        let path = CGMutablePath()

        // Top-left → top-right (AppKit: top = maxY)
        path.move(to: CGPoint(x: rect.minX + lr, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rr, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - rr), radius: rr)

        // Right edge → bottom-right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rr))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - rr, y: rect.minY), radius: rr)

        // Bottom edge → bottom-left
        path.addLine(to: CGPoint(x: rect.minX + lr, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.minY + lr), radius: lr)

        // Left edge → top-left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lr))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX + lr, y: rect.maxY), radius: lr)

        path.closeSubpath()
        return path
    }
}
