import AppKit
import SwiftUI
import QuartzCore

/// Thin NSView wrapper that hosts SwiftUI hint bar content.
/// Handles frame positioning and slide animation; all rendering is in HintBarContent.
final class HintBarView: NSView {
    // MARK: - Public key identifiers

    enum KeyID: Hashable, CaseIterable {
        case up, down, left, right, shift, esc
    }

    enum BarState {
        case expanded   // full text + keycaps (default, shown on launch)
        case collapsed  // keycaps only, two separate bars
    }

    // MARK: - State & hosting

    private let state = HintBarState()
    private var glassPanel: NSView?
    private var hostingView: NSHostingView<HintBarContent>?

    // Collapsed panels
    private var leftCollapsedPanel: NSView?
    private var leftHostingView: NSHostingView<CollapsedLeftContent>?
    private var rightCollapsedPanel: NSView?
    private var rightHostingView: NSHostingView<CollapsedRightContent>?
    private var escTintLayer = CALayer()
    private(set) var currentBarState: BarState = .expanded

    // MARK: - Animation

    private let barMargin: CGFloat = 24
    private let topMargin: CGFloat = 56
    private var isAtBottom = true
    private var isAnimating = false
    private var isAnimatingCollapse = false

    // MARK: - Adaptive appearance

    private var bottomIsLight = false
    private var topIsLight = false

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupHostingView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupHostingView()
    }

    private func setupHostingView() {
        // Expanded panel (default visible)
        let glass = makeGlassPanel()
        self.glassPanel = glass
        addSubview(glass)

        let content = HintBarContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        self.hostingView = hosting

        // Left collapsed panel (arrows + shift)
        let leftGlass = makeGlassPanel(cornerRadius: 14)
        self.leftCollapsedPanel = leftGlass
        addSubview(leftGlass)

        let leftContent = NSHostingView(rootView: CollapsedLeftContent(state: state))
        leftContent.autoresizingMask = [.width, .height]
        leftGlass.addSubview(leftContent)
        self.leftHostingView = leftContent

        // Right collapsed panel (ESC)
        let rightGlass = makeGlassPanel(cornerRadius: 14)
        self.rightCollapsedPanel = rightGlass
        addSubview(rightGlass)

        let rightContent = NSHostingView(rootView: CollapsedRightContent(state: state))
        rightContent.autoresizingMask = [.width, .height]
        rightGlass.addSubview(rightContent)
        self.rightHostingView = rightContent

        // ESC tint overlay on right panel
        setupEscTint()

        // Start with collapsed panels hidden (expanded is default)
        leftGlass.isHidden = true
        rightGlass.isHidden = true
    }

    private func makeGlassPanel(cornerRadius: CGFloat = 14) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        } else {
            let vev = NSVisualEffectView()
            vev.blendingMode = .withinWindow
            vev.material = .hudWindow
            vev.state = .active
            vev.wantsLayer = true
            vev.layer?.cornerRadius = cornerRadius
            vev.layer?.cornerCurve = .continuous
            vev.layer?.masksToBounds = true
            return vev
        }
    }

    // MARK: - Hit testing (pass all events through to the window)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            applyAppearance(isLight: isAtBottom ? bottomIsLight : topIsLight)
        }
    }

    // MARK: - Public API: key press/release

    func pressKey(_ key: KeyID) { state.pressedKeys.insert(key) }
    func releaseKey(_ key: KeyID) { state.pressedKeys.remove(key) }

    // MARK: - Public API: bar state

    func setBarState(_ newState: BarState) {
        guard newState != currentBarState else { return }
        currentBarState = newState
        switch newState {
        case .expanded:
            glassPanel?.isHidden = false
            leftCollapsedPanel?.isHidden = true
            rightCollapsedPanel?.isHidden = true
        case .collapsed:
            glassPanel?.isHidden = true
            leftCollapsedPanel?.isHidden = false
            rightCollapsedPanel?.isHidden = false
        }
    }

    // MARK: - Public API: collapse animation

    /// Animate from expanded to collapsed state with a crossfade.
    /// Expanded panel fades out while collapsed panels fade in (0.35s easeOut).
    /// Call once on first mouse move; once collapsed, stays collapsed for the session.
    func animateToCollapsed(duration: TimeInterval = 0.35) {
        guard currentBarState == .expanded else { return }
        guard !isAnimatingCollapse else { return }
        isAnimatingCollapse = true

        // Accessibility: instant toggle if reduce motion is enabled
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            setBarState(.collapsed)
            isAnimatingCollapse = false
            return
        }

        // Set collapsed panels visible but fully transparent BEFORE unhiding
        // (prevents single-frame flash at final position -- Pitfall 3 from research)
        leftCollapsedPanel?.alphaValue = 0
        rightCollapsedPanel?.alphaValue = 0
        leftCollapsedPanel?.isHidden = false
        rightCollapsedPanel?.isHidden = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            // Fade out expanded bar
            self.glassPanel?.animator().alphaValue = 0

            // Fade in collapsed bars
            self.leftCollapsedPanel?.animator().alphaValue = 1
            self.rightCollapsedPanel?.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.glassPanel?.isHidden = true
            self.glassPanel?.alphaValue = 1  // reset for potential reuse
            self.currentBarState = .collapsed
            self.isAnimatingCollapse = false
        })
    }

    // MARK: - Position & animation

    /// Compute layout and set initial frame at bottom center.
    func configure(screenWidth: CGFloat, screenHeight: CGFloat, screenshot: CGImage? = nil) {
        guard let hosting = hostingView, let glass = glassPanel else { return }
        let expandedSize = hosting.fittingSize

        // Container spans full screen width; height is tallest panel
        var maxHeight = expandedSize.height

        // Compute collapsed layout
        if let leftHosting = leftHostingView, let rightHosting = rightHostingView {
            let leftSize = leftHosting.fittingSize
            let rightSize = rightHosting.fittingSize
            maxHeight = max(maxHeight, max(leftSize.height, rightSize.height))
        }

        frame = NSRect(x: 0, y: barMargin, width: screenWidth, height: maxHeight)

        // Center expanded panel within container
        let expandedX = floor((screenWidth - expandedSize.width) / 2)
        glass.frame = NSRect(x: expandedX, y: 0, width: expandedSize.width, height: expandedSize.height)
        hosting.frame = glass.bounds

        // Center collapsed panels within container
        let gap: CGFloat = 4
        if let leftHosting = leftHostingView, let leftGlass = leftCollapsedPanel,
           let rightHosting = rightHostingView, let rightGlass = rightCollapsedPanel {
            let leftSize = leftHosting.fittingSize
            let rightSize = rightHosting.fittingSize
            let totalWidth = leftSize.width + gap + rightSize.width
            let startX = floor((screenWidth - totalWidth) / 2)

            leftGlass.frame = NSRect(x: startX, y: 0, width: leftSize.width, height: leftSize.height)
            leftHosting.frame = leftGlass.bounds

            rightGlass.frame = NSRect(x: startX + leftSize.width + gap, y: 0, width: rightSize.width, height: rightSize.height)
            rightHosting.frame = rightGlass.bounds
            escTintLayer.frame = rightGlass.bounds
        }

        isAtBottom = true

        // Sample brightness at both bar positions
        if let image = screenshot {
            let scale = CGFloat(image.width) / screenWidth
            let sampleW = expandedSize.width * scale
            let sampleH = expandedSize.height * scale
            let sampleX = floor(CGFloat(image.width - Int(sampleW)) / 2)

            // Bottom position (CG coords: y increases downward, bottom of screen = large y)
            let bottomY = CGFloat(image.height) - (barMargin + expandedSize.height) * scale
            bottomIsLight = regionIsLight(image, x: sampleX, y: bottomY, w: sampleW, h: sampleH)

            // Top position (CG coords: top of screen = small y)
            let topY = topMargin * scale
            topIsLight = regionIsLight(image, x: sampleX, y: topY, w: sampleW, h: sampleH)
        }

        applyAppearance(isLight: bottomIsLight)
    }

    func updatePosition(cursorY: CGFloat, screenHeight: CGFloat) {
        // Block position updates during collapse animation to prevent overlap
        guard !isAnimatingCollapse else { return }

        let viewH = bounds.height
        let nearBottom = cursorY < viewH + barMargin * 3
        let shouldBeAtTop = nearBottom

        if shouldBeAtTop && !isAtBottom { return }
        if !shouldBeAtTop && isAtBottom { return }
        guard !isAnimating else { return }

        let finalY: CGFloat
        if shouldBeAtTop {
            finalY = screenHeight - viewH - topMargin
            isAtBottom = false
            applyAppearance(isLight: topIsLight)
        } else {
            finalY = barMargin
            isAtBottom = true
            applyAppearance(isLight: bottomIsLight)
        }
        animateSlide(to: finalY, screenHeight: screenHeight, exitDown: shouldBeAtTop)
    }

    // MARK: - Adaptive appearance

    private func applyAppearance(isLight: Bool) {
        state.isOnLightBackground = isLight
        // Force the appearance so the glass material matches the background,
        // not the system theme. Without this, NSGlassEffectView auto-adapts
        // to the system dark/light mode and ignores our tint on launch.
        let appearanceName: NSAppearance.Name = isLight ? .aqua : .darkAqua
        let appearance = NSAppearance(named: appearanceName)
        let tintColor: NSColor = isLight
            ? NSColor(white: 1, alpha: 0.4)
            : NSColor(white: 0, alpha: 0.4)

        // Apply to all glass panels
        for panel in [glassPanel, leftCollapsedPanel, rightCollapsedPanel] {
            panel?.appearance = appearance
            if #available(macOS 26.0, *), let glass = panel as? NSGlassEffectView {
                glass.tintColor = tintColor
            }
        }
        updateEscTint()
    }

    // MARK: - ESC tint

    private func setupEscTint() {
        escTintLayer.cornerRadius = 14
        escTintLayer.cornerCurve = .continuous
        rightCollapsedPanel?.layer?.addSublayer(escTintLayer)
        updateEscTint()
    }

    private func updateEscTint() {
        let isDark = !state.isOnLightBackground
        escTintLayer.backgroundColor = isDark
            ? CGColor(srgbRed: 1.0, green: 0.3, blue: 0.3, alpha: 0.08)
            : CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 0.06)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEscTint()
    }

    private func regionIsLight(_ image: CGImage, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> Bool {
        let rect = CGRect(
            x: max(0, x), y: max(0, y),
            width: min(w, CGFloat(image.width) - max(0, x)),
            height: min(h, CGFloat(image.height) - max(0, y))
        )
        guard rect.width > 0, rect.height > 0,
              let cropped = image.cropping(to: rect) else { return false }

        // Downsample to small size for fast averaging
        let sw = min(cropped.width, 64)
        let sh = min(cropped.height, 16)
        guard let ctx = CGContext(
            data: nil, width: sw, height: sh,
            bitsPerComponent: 8, bytesPerRow: sw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let data = ctx.data else { return false }

        let ptr = data.bindMemory(to: UInt8.self, capacity: sw * sh * 4)
        var total: Double = 0
        let count = sw * sh
        for i in 0..<count {
            let r = Double(ptr[i * 4]) / 255.0
            let g = Double(ptr[i * 4 + 1]) / 255.0
            let b = Double(ptr[i * 4 + 2]) / 255.0
            total += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return (total / Double(count)) > 0.5
    }

    // MARK: - Slide animation

    private func animateSlide(to finalY: CGFloat, screenHeight: CGFloat, exitDown: Bool) {
        guard let layer = self.layer else {
            frame.origin.y = finalY
            return
        }

        let viewH = bounds.height
        isAnimating = true
        let currentPos = layer.position.y
        let offscreenExit = exitDown ? -viewH : screenHeight + viewH
        let offscreenEntry = exitDown ? screenHeight + viewH : -viewH

        let anim = CAKeyframeAnimation(keyPath: "position.y")
        anim.values = [currentPos, offscreenExit, offscreenEntry, finalY]
        anim.keyTimes = [0, 0.3, 0.3001, 1]
        anim.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        ]
        anim.duration = 0.3
        anim.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isAnimating = false
        }
        frame.origin.y = finalY
        layer.add(anim, forKey: "hintBarSlide")
        CATransaction.commit()
    }
}
