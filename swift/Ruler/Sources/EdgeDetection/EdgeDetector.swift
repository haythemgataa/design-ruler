import AppKit

enum CorrectionMode: String {
    case smart = "smart"
    case include = "include"
    case none = "none"
}

final class EdgeDetector {
    private var colorMap: ColorMap?
    private(set) var skipCounts = (left: 0, right: 0, top: 0, bottom: 0)
    private var lastCursorPosition: CGPoint?
    var correctionMode: CorrectionMode = .smart

    /// Capture full screen before window exists. Returns NSImage for window background.
    func capture(screen: NSScreen) -> NSImage? {
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let frame = screen.frame
        let mainHeight = mainScreen.frame.height

        // CG rect for capture (top-left origin)
        let cgRect = CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }

        // screenFrame in AX/CG coords for ColorMap
        let screenFrame = CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
        applyCapture(cgImage: cgImage, screenFrame: screenFrame)

        return NSImage(cgImage: cgImage, size: frame.size)
    }

    /// Apply captured image — sets colorMap. Call from main thread.
    func applyCapture(cgImage: CGImage, screenFrame: CGRect) {
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        guard let context = CGContext(
            data: &pixels,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        colorMap = ColorMap(width: pixelWidth, height: pixelHeight,
                            pixels: pixels, screenFrame: screenFrame)
    }

    /// Called on every mouse move. Resets skip counts, returns edges.
    /// Point is in AppKit screen coords (bottom-left origin).
    func onMouseMoved(at appKitPoint: NSPoint) -> DirectionalEdges? {
        skipCounts = (0, 0, 0, 0)
        let axPoint = CoordinateConverter.appKitToAX(appKitPoint)
        lastCursorPosition = axPoint
        return currentEdges(at: axPoint)
    }

    /// Scan cached ColorMap at point (AX coords) with current skip counts.
    private func currentEdges(at point: CGPoint) -> DirectionalEdges? {
        guard let map = colorMap else { return nil }
        switch correctionMode {
        case .include:
            return map.scan(from: point, tolerance: 1,
                            skipLeft: skipCounts.left, skipRight: skipCounts.right,
                            skipTop: skipCounts.top, skipBottom: skipCounts.bottom,
                            includeBorders: true)
        case .none:
            return map.scan(from: point, tolerance: 1,
                            skipLeft: skipCounts.left, skipRight: skipCounts.right,
                            skipTop: skipCounts.top, skipBottom: skipCounts.bottom,
                            includeBorders: false)
        case .smart:
            return smartEdges(from: map, at: point)
        }
    }

    /// Smart mode: scan twice, try all 4 per-edge combinations per axis,
    /// pick the combo whose displayed dimension lands on the 4px grid.
    private func smartEdges(from map: ColorMap, at point: CGPoint) -> DirectionalEdges {
        let absorbed = map.scan(from: point, tolerance: 1,
                                skipLeft: skipCounts.left, skipRight: skipCounts.right,
                                skipTop: skipCounts.top, skipBottom: skipCounts.bottom,
                                includeBorders: true)
        let normal = map.scan(from: point, tolerance: 1,
                              skipLeft: skipCounts.left, skipRight: skipCounts.right,
                              skipTop: skipCounts.top, skipBottom: skipCounts.bottom,
                              includeBorders: false)

        // Cursor-to-screen-boundary distances (used when an edge is nil)
        let sf = map.screenFrame
        let fbLeft = point.x - sf.origin.x
        let fbRight = sf.origin.x + sf.width - point.x
        let fbTop = point.y - sf.origin.y
        let fbBottom = sf.origin.y + sf.height - point.y

        let (finalLeft, finalRight) = bestCombo(
            absA: absorbed.left, absB: absorbed.right,
            normA: normal.left, normB: normal.right,
            fallbackA: fbLeft, fallbackB: fbRight
        )
        let (finalTop, finalBottom) = bestCombo(
            absA: absorbed.top, absB: absorbed.bottom,
            normA: normal.top, normB: normal.bottom,
            fallbackA: fbTop, fallbackB: fbBottom
        )

        return DirectionalEdges(cursorPosition: absorbed.cursorPosition,
                                left: finalLeft, right: finalRight,
                                top: finalTop, bottom: finalBottom)
    }

    /// Try all 4 combinations of absorbed/normal for an opposing edge pair.
    /// Computes the full displayed dimension (using fallback for nil edges)
    /// and picks the first combo that lands on the 4px grid.
    /// Prefers more absorption when multiple combos fit.
    private func bestCombo(
        absA: EdgeHit?, absB: EdgeHit?,
        normA: EdgeHit?, normB: EdgeHit?,
        fallbackA: CGFloat, fallbackB: CGFloat
    ) -> (EdgeHit?, EdgeHit?) {
        // 4 combinations ordered by absorption preference (most → least)
        let options: [(EdgeHit?, EdgeHit?)] = [
            (absA, absB),   // both absorbed
            (absA, normB),  // A absorbed, B normal
            (normA, absB),  // A normal, B absorbed
            (normA, normB), // both normal
        ]

        let dims = options.map { pair -> Int in
            let dA = pair.0?.distance ?? fallbackA
            let dB = pair.1?.distance ?? fallbackB
            return Int(dA + dB)
        }

        // If all same, no border was absorbed — use absorbed (default)
        if dims[0] == dims[3] { return (absA, absB) }

        // Pick first combo (most absorption) whose dimension lands on 4px grid
        for i in 0..<4 {
            if dims[i] % 4 == 0 { return options[i] }
        }

        // No combo fits grid — default to absorbed
        return (absA, absB)
    }

    enum Direction { case left, right, top, bottom }

    /// Arrow key: push edge further away. Returns updated edges.
    func incrementSkip(_ direction: Direction) -> DirectionalEdges? {
        switch direction {
        case .left:   skipCounts.left += 1
        case .right:  skipCounts.right += 1
        case .top:    skipCounts.top += 1
        case .bottom: skipCounts.bottom += 1
        }
        guard let p = lastCursorPosition else { return nil }
        return currentEdges(at: p)
    }

    /// Shift+Arrow: bring edge back closer. Returns updated edges.
    func decrementSkip(_ direction: Direction) -> DirectionalEdges? {
        switch direction {
        case .left:   skipCounts.left = max(0, skipCounts.left - 1)
        case .right:  skipCounts.right = max(0, skipCounts.right - 1)
        case .top:    skipCounts.top = max(0, skipCounts.top - 1)
        case .bottom: skipCounts.bottom = max(0, skipCounts.bottom - 1)
        }
        guard let p = lastCursorPosition else { return nil }
        return currentEdges(at: p)
    }
}
