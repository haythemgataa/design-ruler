import AppKit
import QuartzCore

/// Visual indicator showing 5 color presets in an arc above the cursor.
/// Appears on spacebar press, follows cursor, auto-hides after 1s.
final class ColorCircleIndicator {
    private let containerLayer = CALayer()
    private var circleLayers: [CALayer] = []
    private let dotLayer = CALayer()
    private var hideWorkItem: DispatchWorkItem?
    private let scale: CGFloat
    private var showGeneration = 0

    private(set) var isVisible = false
    private var isFadingOut = false
    private var activeIndex: Int = 0
    private var lastCursorPosition: CGPoint = .zero

    // Layout constants
    private let circleRadius: CGFloat = 7       // 14px diameter
    private let activeRadius: CGFloat = 8       // 16px diameter for active
    private let arcRadius: CGFloat = 36         // Distance from cursor to circle centers
    private let arcSpan: CGFloat = .pi * 0.6    // 108 degrees
    private let dotDiameter: CGFloat = 4        // 4px white center dot
    private let stagger: CFTimeInterval = 0.03  // 30ms between each circle

    init(parentLayer: CALayer, scale: CGFloat, screenSize: CGSize) {
        self.scale = scale
        containerLayer.frame = CGRect(origin: .zero, size: screenSize)
        containerLayer.opacity = 0
        parentLayer.addSublayer(containerLayer)
        createCircleLayers()
        setupDotLayer()
    }

    // MARK: - Public

    func show(at cursorPosition: NSPoint, activeIndex: Int, screenSize: CGSize) {
        hideWorkItem?.cancel()
        showGeneration += 1
        let gen = showGeneration

        // Cancel any in-flight animations
        for layer in circleLayers { layer.removeAllAnimations() }
        dotLayer.removeAllAnimations()
        isFadingOut = false

        let oldActiveIndex = self.activeIndex
        self.activeIndex = activeIndex
        self.lastCursorPosition = cursorPosition

        let wasHidden = !isVisible
        isVisible = true
        let positions = computePositions(at: cursorPosition, screenSize: screenSize)

        if wasHidden {
            // Set model values to final state immediately
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.opacity = 1
            updateCircleSizes(activeIndex: activeIndex)
            for (i, layer) in circleLayers.enumerated() {
                layer.position = positions[i]
                layer.transform = CATransform3DIdentity
            }
            dotLayer.position = positions[activeIndex]
            dotLayer.transform = CATransform3DIdentity
            dotLayer.opacity = 1
            CATransaction.commit()

            // Add staggered appear animations (from cursor + scale 0 → final position + scale 1)
            let now = CACurrentMediaTime()
            let timing = CAMediaTimingFunction(name: .easeOut)

            for (i, layer) in circleLayers.enumerated() {
                let delay = now + CFTimeInterval(i) * stagger

                let posAnim = CABasicAnimation(keyPath: "position")
                posAnim.fromValue = NSValue(point: cursorPosition)
                posAnim.duration = 0.2
                posAnim.beginTime = delay
                posAnim.timingFunction = timing
                posAnim.fillMode = .backwards
                layer.add(posAnim, forKey: "appear-pos")

                let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
                scaleAnim.fromValue = 0.01
                scaleAnim.duration = 0.2
                scaleAnim.beginTime = delay
                scaleAnim.timingFunction = timing
                scaleAnim.fillMode = .backwards
                layer.add(scaleAnim, forKey: "appear-scale")
            }

            // Dot appears with active circle's timing
            let dotDelay = now + CFTimeInterval(activeIndex) * stagger
            let dotPos = CABasicAnimation(keyPath: "position")
            dotPos.fromValue = NSValue(point: cursorPosition)
            dotPos.duration = 0.2
            dotPos.beginTime = dotDelay
            dotPos.timingFunction = timing
            dotPos.fillMode = .backwards
            dotLayer.add(dotPos, forKey: "appear-pos")

            let dotScale = CABasicAnimation(keyPath: "transform.scale")
            dotScale.fromValue = 0.01
            dotScale.duration = 0.2
            dotScale.beginTime = dotDelay
            dotScale.timingFunction = timing
            dotScale.fillMode = .backwards
            dotLayer.add(dotScale, forKey: "appear-scale")
        } else {
            // Already visible — animate active circle transition
            let timing = CAMediaTimingFunction(name: .easeOut)

            // Positions update instantly
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, layer) in circleLayers.enumerated() {
                layer.position = positions[i]
                layer.transform = CATransform3DIdentity
            }
            CATransaction.commit()

            // Animate size change + dot
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(timing)

            // Shrink old active circle
            if oldActiveIndex != activeIndex {
                let oldLayer = circleLayers[oldActiveIndex]
                let smallD = circleRadius * 2
                oldLayer.bounds = CGRect(x: 0, y: 0, width: smallD, height: smallD)
                oldLayer.cornerRadius = circleRadius
                oldLayer.borderWidth = 1
                oldLayer.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: smallD, height: smallD), transform: nil)
                if oldActiveIndex == 0 {
                    updateDynamicPresetSize(oldLayer, radius: circleRadius)
                }
            }

            // Grow new active circle
            let newLayer = circleLayers[activeIndex]
            let bigD = activeRadius * 2
            newLayer.bounds = CGRect(x: 0, y: 0, width: bigD, height: bigD)
            newLayer.cornerRadius = activeRadius
            newLayer.borderWidth = 2
            newLayer.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: bigD, height: bigD), transform: nil)
            if activeIndex == 0 {
                updateDynamicPresetSize(newLayer, radius: activeRadius)
            }

            // Move dot to new active + scale pulse
            dotLayer.position = positions[activeIndex]
            CATransaction.commit()

            // Dot scale pulse
            let dotPulse = CABasicAnimation(keyPath: "transform.scale")
            dotPulse.fromValue = 0.3
            dotPulse.toValue = 1.0
            dotPulse.duration = 0.15
            dotPulse.timingFunction = timing
            dotLayer.add(dotPulse, forKey: "dot-pulse")
        }

        // Schedule auto-hide
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.showGeneration == gen else { return }
            self.fadeOut()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// Reposition circles to follow cursor (called on every mouseMoved).
    func updatePosition(at cursorPosition: NSPoint, screenSize: CGSize) {
        guard isVisible, !isFadingOut else { return }
        lastCursorPosition = cursorPosition
        let positions = computePositions(at: cursorPosition, screenSize: screenSize)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, layer) in circleLayers.enumerated() {
            layer.position = positions[i]
        }
        dotLayer.position = positions[activeIndex]
        CATransaction.commit()
    }

    // MARK: - Setup

    private func createCircleLayers() {
        for style in GuideLineStyle.allCases {
            let layer: CALayer
            if style == .dynamic {
                layer = createDynamicPresetLayer(radius: circleRadius)
            } else {
                layer = createSolidColorLayer(color: style.color, radius: circleRadius)
            }
            layer.contentsScale = scale

            // Shadow
            let d = circleRadius * 2
            layer.shadowColor = CGColor(gray: 0, alpha: 1.0)
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.shadowRadius = 3
            layer.shadowOpacity = 0.25
            layer.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)

            // Border (1px white, all circles)
            layer.borderColor = CGColor(gray: 1.0, alpha: 1.0)
            layer.borderWidth = 1
            layer.cornerRadius = circleRadius

            containerLayer.addSublayer(layer)
            circleLayers.append(layer)
        }
    }

    private func setupDotLayer() {
        dotLayer.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
        dotLayer.cornerRadius = dotDiameter / 2
        dotLayer.backgroundColor = CGColor(gray: 1.0, alpha: 1.0)
        dotLayer.contentsScale = scale
        dotLayer.opacity = 0
        containerLayer.addSublayer(dotLayer)
    }

    private func createDynamicPresetLayer(radius: CGFloat) -> CALayer {
        let d = radius * 2
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: d, height: d)

        let center = CGPoint(x: radius, y: radius)

        // Left half (black) — semicircle arc path
        let leftHalf = CAShapeLayer()
        leftHalf.frame = CGRect(x: 0, y: 0, width: d, height: d)
        let leftPath = CGMutablePath()
        leftPath.move(to: center)
        leftPath.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        leftPath.closeSubpath()
        leftHalf.path = leftPath
        leftHalf.fillColor = CGColor(gray: 0, alpha: 1.0)

        // Right half (white) — semicircle arc path
        let rightHalf = CAShapeLayer()
        rightHalf.frame = CGRect(x: 0, y: 0, width: d, height: d)
        let rightPath = CGMutablePath()
        rightPath.move(to: center)
        rightPath.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        rightPath.closeSubpath()
        rightHalf.path = rightPath
        rightHalf.fillColor = CGColor(gray: 1.0, alpha: 1.0)

        container.addSublayer(leftHalf)
        container.addSublayer(rightHalf)

        return container
    }

    private func createSolidColorLayer(color: CGColor, radius: CGFloat) -> CALayer {
        let d = radius * 2
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        layer.cornerRadius = radius
        layer.backgroundColor = color
        return layer
    }

    // MARK: - Layout

    /// Compute arc positions with dynamic on the left, blue on the right (clockwise order).
    private func computePositions(at cursorPosition: CGPoint, screenSize: CGSize) -> [CGPoint] {
        let centerAngle: CGFloat
        if cursorPosition.y + arcRadius + activeRadius > screenSize.height {
            centerAngle = -.pi / 2  // Flip below cursor near top
        } else {
            centerAngle = .pi / 2   // Above cursor (default)
        }

        let startAngle = centerAngle - arcSpan / 2
        let count = circleLayers.count
        var positions: [CGPoint] = []

        for i in 0..<count {
            // Reverse index: i=0 (dynamic) gets leftmost position (largest angle)
            let angle = startAngle + arcSpan * CGFloat(count - 1 - i) / CGFloat(count - 1)
            let x = cursorPosition.x + arcRadius * cos(angle)
            let y = cursorPosition.y + arcRadius * sin(angle)
            positions.append(CGPoint(x: x, y: y))
        }
        return positions
    }

    private func updateCircleSizes(activeIndex: Int) {
        for (i, layer) in circleLayers.enumerated() {
            let isActive = (i == activeIndex)
            let radius = isActive ? activeRadius : circleRadius
            let d = radius * 2

            layer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            layer.cornerRadius = radius
            layer.borderWidth = isActive ? 2 : 1
            layer.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: d, height: d), transform: nil)

            if i == 0 {
                updateDynamicPresetSize(layer, radius: radius)
            }
        }
    }

    private func updateDynamicPresetSize(_ container: CALayer, radius: CGFloat) {
        let d = radius * 2
        let center = CGPoint(x: radius, y: radius)

        guard let sublayers = container.sublayers, sublayers.count >= 2,
              let leftHalf = sublayers[0] as? CAShapeLayer,
              let rightHalf = sublayers[1] as? CAShapeLayer else { return }

        leftHalf.frame = CGRect(x: 0, y: 0, width: d, height: d)
        let leftPath = CGMutablePath()
        leftPath.move(to: center)
        leftPath.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        leftPath.closeSubpath()
        leftHalf.path = leftPath

        rightHalf.frame = CGRect(x: 0, y: 0, width: d, height: d)
        let rightPath = CGMutablePath()
        rightPath.move(to: center)
        rightPath.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        rightPath.closeSubpath()
        rightHalf.path = rightPath
    }

    // MARK: - Animation

    private func fadeOut() {
        let gen = showGeneration
        isFadingOut = true

        // Capture current positions before setting model values
        let currentPositions = circleLayers.map { $0.position }
        let dotPosition = dotLayer.position
        let totalDuration = 0.2 + CFTimeInterval(circleLayers.count - 1) * stagger

        // Set model values to final state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in circleLayers {
            layer.position = lastCursorPosition
            layer.transform = CATransform3DMakeScale(0.01, 0.01, 1.0)
        }
        dotLayer.position = lastCursorPosition
        dotLayer.transform = CATransform3DMakeScale(0.01, 0.01, 1.0)
        dotLayer.opacity = 0
        CATransaction.commit()

        // Add staggered exit animations (current position → cursor + scale 0)
        let now = CACurrentMediaTime()
        let timing = CAMediaTimingFunction(name: .easeIn)

        for (i, layer) in circleLayers.enumerated() {
            let delay = now + CFTimeInterval(i) * stagger

            let posAnim = CABasicAnimation(keyPath: "position")
            posAnim.fromValue = NSValue(point: currentPositions[i])
            posAnim.duration = 0.2
            posAnim.beginTime = delay
            posAnim.timingFunction = timing
            posAnim.fillMode = .backwards
            layer.add(posAnim, forKey: "exit-pos")

            let scaleAnim = CABasicAnimation(keyPath: "transform")
            scaleAnim.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            scaleAnim.duration = 0.2
            scaleAnim.beginTime = delay
            scaleAnim.timingFunction = timing
            scaleAnim.fillMode = .backwards
            layer.add(scaleAnim, forKey: "exit-scale")
        }

        // Dot exits with active circle's timing
        let dotDelay = now + CFTimeInterval(activeIndex) * stagger
        let dotPos = CABasicAnimation(keyPath: "position")
        dotPos.fromValue = NSValue(point: dotPosition)
        dotPos.duration = 0.2
        dotPos.beginTime = dotDelay
        dotPos.timingFunction = timing
        dotPos.fillMode = .backwards
        dotLayer.add(dotPos, forKey: "exit-pos")

        let dotScale = CABasicAnimation(keyPath: "transform")
        dotScale.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        dotScale.duration = 0.2
        dotScale.beginTime = dotDelay
        dotScale.timingFunction = timing
        dotScale.fillMode = .backwards
        dotLayer.add(dotScale, forKey: "exit-scale")

        // Cleanup after all animations complete
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.05) { [weak self] in
            guard let self = self, self.showGeneration == gen else { return }
            self.isVisible = false
            self.isFadingOut = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.containerLayer.opacity = 0
            for layer in self.circleLayers {
                layer.transform = CATransform3DIdentity
                layer.removeAllAnimations()
            }
            self.dotLayer.transform = CATransform3DIdentity
            self.dotLayer.removeAllAnimations()
            CATransaction.commit()
        }
    }
}
