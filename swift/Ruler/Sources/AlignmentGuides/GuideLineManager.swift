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

    // Hover state
    private(set) var hoveredLine: GuideLine? = nil

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

    /// Check for hover over placed lines.
    var hasHoveredLine: Bool {
        hoveredLine != nil
    }

    /// Update hover state based on cursor position.
    func updateHover(at point: NSPoint) {
        let newHovered = findNearestLine(to: point, within: 5.0)

        if newHovered !== hoveredLine {
            // Unhover old line
            hoveredLine?.setHovered(false, cursorPosition: point)

            // Hover new line
            newHovered?.setHovered(true, cursorPosition: point)

            hoveredLine = newHovered
        }
    }

    /// Find nearest placed line to point within threshold.
    private func findNearestLine(to point: NSPoint, within threshold: CGFloat) -> GuideLine? {
        var nearest: GuideLine? = nil
        var minDistance = threshold

        for line in placedLines {
            let distance: CGFloat
            if line.direction == .vertical {
                distance = abs(point.x - line.position)
            } else {
                distance = abs(point.y - line.position)
            }

            if distance < minDistance {
                minDistance = distance
                nearest = line
            }
        }

        return nearest
    }

    /// Remove a placed line with shrink animation.
    func removeLine(_ line: GuideLine, clickPoint: NSPoint) {
        line.shrinkToPoint(clickPoint, screenSize: screenSize) { [weak self] in
            line.remove(animated: false)
            self?.placedLines.removeAll { $0 === line }
        }
        hoveredLine = nil
    }
}
