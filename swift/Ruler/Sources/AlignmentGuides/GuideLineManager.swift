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

    // Color indicator
    private var colorIndicator: ColorCircleIndicator?

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

        // Follow cursor with color indicator
        colorIndicator?.updatePosition(at: point, screenSize: screenSize)

        // Hide pill when color indicator is showing
        if colorIndicator?.isVisible == true && !previewLine.isInRemoveMode {
            previewLine.hidePill()
        }
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

    /// Cycle to next style preset with color indicator.
    func cycleStyle(cursorPosition: NSPoint) {
        currentStyle = currentStyle.next()
        let styleIndex = GuideLineStyle.allCases.firstIndex(of: currentStyle)!

        // Update preview line to new color
        previewLine.update(
            position: currentPosition,
            cursorAlongAxis: currentCursorAlongAxis,
            screenSize: screenSize,
            direction: currentDirection,
            style: currentStyle
        )

        // Show/update color indicator
        if colorIndicator == nil {
            colorIndicator = ColorCircleIndicator(parentLayer: parentLayer, scale: scale, screenSize: screenSize)
        }
        colorIndicator!.show(at: cursorPosition, activeIndex: styleIndex, screenSize: screenSize)
        previewLine.hidePill()
    }

    /// Get current direction for cursor management.
    var direction: Direction {
        currentDirection
    }

    /// Get current style index for color indicator.
    private var currentStyleIndex: Int {
        GuideLineStyle.allCases.firstIndex(of: currentStyle)!
    }

    /// Set preview line style (for global color sync across multi-monitor).
    func setPreviewStyle(_ style: GuideLineStyle) {
        currentStyle = style
    }

    /// Get current style value (for propagating to coordinator).
    var currentStyleValue: GuideLineStyle {
        currentStyle
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

            // Toggle preview line mode: hide line + show "Remove" pill when hovering
            previewLine.isInRemoveMode = (newHovered != nil)
            previewLine.setLineVisible(newHovered == nil)
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

    /// Reset preview line state after a removal.
    func resetRemoveMode() {
        previewLine.isInRemoveMode = false
        previewLine.setLineVisible(true)
    }

    /// Hide preview line and pill (for multi-monitor deactivation).
    func hidePreview() {
        previewLine.setLineVisible(false)
        previewLine.hidePill()
    }

    /// Show preview line (for multi-monitor activation).
    func showPreview() {
        previewLine.setLineVisible(true)
    }
}
