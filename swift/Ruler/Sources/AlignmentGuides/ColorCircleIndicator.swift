import AppKit
import QuartzCore

/// Visual indicator showing 5 color presets in an arc above the cursor.
/// Appears on spacebar press, auto-hides after 1s of inactivity.
final class ColorCircleIndicator {
    private let containerLayer = CALayer()
    private var circleLayers: [CALayer] = []
    private var hideWorkItem: DispatchWorkItem?
    private let scale: CGFloat

    // Layout constants
    private let circleRadius: CGFloat = 6      // ~12px diameter
    private let activeRadius: CGFloat = 8      // ~16px diameter for active
    private let arcRadius: CGFloat = 40        // Distance from cursor to circle centers
    private let arcSpan: CGFloat = .pi * 0.6   // 108 degrees

    init(parentLayer: CALayer, scale: CGFloat) {
        self.scale = scale
        containerLayer.opacity = 0  // Hidden initially
        parentLayer.addSublayer(containerLayer)
        createCircleLayers()
    }

    /// Show or update the indicator at cursor position with active color highlighted.
    func show(at cursorPosition: NSPoint, activeIndex: Int, screenSize: CGSize) {
        // Cancel any pending hide
        hideWorkItem?.cancel()

        // Layout circles
        layoutCircles(at: cursorPosition, activeIndex: activeIndex, screenSize: screenSize)

        if containerLayer.opacity == 0 {
            // First show — animate appearance
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in circleLayers {
                layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0)
            }
            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            containerLayer.opacity = 1
            for layer in circleLayers {
                layer.transform = CATransform3DIdentity
            }
            CATransaction.commit()
        }

        // Schedule auto-hide
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func createCircleLayers() {
        for style in GuideLineStyle.allCases {
            let layer: CALayer
            if style == .dynamic {
                layer = createDynamicPresetLayer(radius: circleRadius)
            } else {
                layer = createSolidColorLayer(color: style.color, radius: circleRadius)
            }
            layer.contentsScale = scale
            containerLayer.addSublayer(layer)
            circleLayers.append(layer)
        }
    }

    private func createDynamicPresetLayer(radius: CGFloat) -> CALayer {
        let diameter = radius * 2
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        container.cornerRadius = radius
        container.masksToBounds = true

        // Left half: black semicircle
        let leftHalf = CAShapeLayer()
        leftHalf.frame = CGRect(x: 0, y: 0, width: radius, height: diameter)
        let leftPath = CGMutablePath()
        leftPath.addRect(CGRect(x: 0, y: 0, width: radius, height: diameter))
        leftHalf.path = leftPath
        leftHalf.fillColor = CGColor(gray: 0, alpha: 1.0)

        // Right half: white semicircle
        let rightHalf = CAShapeLayer()
        rightHalf.frame = CGRect(x: radius, y: 0, width: radius, height: diameter)
        let rightPath = CGMutablePath()
        rightPath.addRect(CGRect(x: 0, y: 0, width: radius, height: diameter))
        rightHalf.path = rightPath
        rightHalf.fillColor = CGColor(gray: 1.0, alpha: 1.0)

        container.addSublayer(leftHalf)
        container.addSublayer(rightHalf)

        return container
    }

    private func createSolidColorLayer(color: CGColor, radius: CGFloat) -> CALayer {
        let diameter = radius * 2
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = radius
        layer.backgroundColor = color
        return layer
    }

    private func layoutCircles(at cursorPosition: CGPoint, activeIndex: Int, screenSize: CGSize) {
        // Determine if arc should flip below cursor (when near top of screen)
        let centerAngle: CGFloat
        if cursorPosition.y + arcRadius + activeRadius > screenSize.height {
            centerAngle = -.pi / 2  // Point downward
        } else {
            centerAngle = .pi / 2   // Point upward (default)
        }

        let startAngle = centerAngle - arcSpan / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (i, layer) in circleLayers.enumerated() {
            let angle = startAngle + arcSpan * CGFloat(i) / CGFloat(circleLayers.count - 1)
            let x = cursorPosition.x + arcRadius * cos(angle)
            let y = cursorPosition.y + arcRadius * sin(angle)

            // Set radius based on active state
            let isActive = (i == activeIndex)
            let radius = isActive ? activeRadius : circleRadius
            let diameter = radius * 2

            // Update bounds and position
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.position = CGPoint(x: x, y: y)

            // Set border for active circle
            if isActive {
                layer.borderWidth = 2
                layer.borderColor = CGColor(gray: 1.0, alpha: 1.0)
                layer.cornerRadius = radius
            } else {
                layer.borderWidth = 0
                layer.borderColor = nil
                layer.cornerRadius = radius
            }

            // For dynamic preset layer, need to update sublayers if size changed
            if i == 0 { // dynamic preset
                updateDynamicPresetLayerSize(layer, radius: radius)
            }
        }

        CATransaction.commit()
    }

    private func updateDynamicPresetLayerSize(_ container: CALayer, radius: CGFloat) {
        let diameter = radius * 2
        container.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        container.cornerRadius = radius

        guard container.sublayers?.count == 2 else { return }

        // Update sublayer frames
        let leftHalf = container.sublayers![0] as! CAShapeLayer
        leftHalf.frame = CGRect(x: 0, y: 0, width: radius, height: diameter)
        let leftPath = CGMutablePath()
        leftPath.addRect(CGRect(x: 0, y: 0, width: radius, height: diameter))
        leftHalf.path = leftPath

        let rightHalf = container.sublayers![1] as! CAShapeLayer
        rightHalf.frame = CGRect(x: radius, y: 0, width: radius, height: diameter)
        let rightPath = CGMutablePath()
        rightPath.addRect(CGRect(x: 0, y: 0, width: radius, height: diameter))
        rightHalf.path = rightPath
    }

    private func fadeOut() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else { return }
            // Reset transforms for next show
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in self.circleLayers {
                layer.transform = CATransform3DIdentity
            }
            CATransaction.commit()
        }

        containerLayer.opacity = 0
        for layer in circleLayers {
            layer.transform = CATransform3DMakeScale(0.8, 0.8, 1.0)
        }

        CATransaction.commit()
    }
}
