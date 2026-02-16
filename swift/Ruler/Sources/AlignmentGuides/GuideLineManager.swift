import AppKit
import QuartzCore

/// Manages the preview line and collection of placed guide lines.
final class GuideLineManager {
    private let previewLine: GuideLine
    private var placedLines: [GuideLine] = []

    private var currentDirection: Direction = .vertical
    private var currentStyle: GuideLineStyle = .dynamic

    private let parentLayer: CALayer
    private let scale: CGFloat
    private let screenSize: CGSize

    // Current preview state (for placing)
    private var currentPosition: CGFloat = 0
    private var currentCursorAlongAxis: CGFloat = 0

    init(parentLayer: CALayer, scale: CGFloat, screenSize: CGSize) {
        self.parentLayer = parentLayer
        self.scale = scale
        self.screenSize = screenSize

        // Create preview line
        self.previewLine = GuideLine(
            direction: .vertical,
            position: 0,
            style: .dynamic,
            isPreview: true,
            parentLayer: parentLayer,
            scale: scale
        )
    }

    /// Update preview line position to follow cursor.
    func updatePreview(at point: NSPoint) {
        let position: CGFloat
        let cursorAlongAxis: CGFloat

        if currentDirection == .vertical {
            position = point.x
            cursorAlongAxis = point.y
        } else {
            position = point.y
            cursorAlongAxis = point.x
        }

        currentPosition = position
        currentCursorAlongAxis = cursorAlongAxis

        previewLine.update(
            position: position,
            cursorAlongAxis: cursorAlongAxis,
            screenSize: screenSize,
            direction: currentDirection,
            style: currentStyle
        )
    }

    /// Place a guide line at the current preview position.
    func placeGuide() {
        let newLine = GuideLine(
            direction: currentDirection,
            position: currentPosition,
            style: currentStyle,
            isPreview: false,
            parentLayer: parentLayer,
            scale: scale
        )

        // Update position immediately
        newLine.update(
            position: currentPosition,
            cursorAlongAxis: currentCursorAlongAxis,
            screenSize: screenSize,
            direction: currentDirection,
            style: currentStyle
        )

        // Fade in
        newLine.setOpacity(0, animated: false)
        newLine.setOpacity(1, animated: true)

        placedLines.append(newLine)
    }

    /// Toggle preview direction between vertical and horizontal.
    func toggleDirection() {
        currentDirection = currentDirection.toggled()

        // Update preview line to new direction at same cursor position
        previewLine.update(
            position: currentPosition,
            cursorAlongAxis: currentCursorAlongAxis,
            screenSize: screenSize,
            direction: currentDirection,
            style: currentStyle
        )
    }

    /// Cycle to next style (stub for phase 10).
    func cycleStyle() {
        // Phase 10: implement style cycling
        // currentStyle = currentStyle.next()
        // Update preview + all placed lines to new style
    }

    /// Get current direction for cursor management.
    var direction: Direction {
        currentDirection
    }
}
