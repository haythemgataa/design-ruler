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

    // MARK: - State & hosting

    private let state = HintBarState()
    private var glassPanel: NSView?
    private var hostingView: NSHostingView<HintBarContent>?

    // MARK: - Animation

    private let barMargin: CGFloat = 16
    private let topMargin: CGFloat = 48
    private var isAtBottom = true
    private var isAnimating = false

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
        let glass = makeGlassPanel()
        self.glassPanel = glass
        addSubview(glass)

        let content = HintBarContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        self.hostingView = hosting
    }

    private func makeGlassPanel() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 18
            return glass
        } else {
            let vev = NSVisualEffectView()
            vev.blendingMode = .withinWindow
            vev.material = .hudWindow
            vev.state = .active
            vev.wantsLayer = true
            vev.layer?.cornerRadius = 18
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

    // MARK: - Position & animation

    /// Compute layout and set initial frame at bottom center.
    func configure(screenWidth: CGFloat, screenHeight: CGFloat, screenshot: CGImage? = nil) {
        guard let hosting = hostingView, let glass = glassPanel else { return }
        let size = hosting.fittingSize
        let viewX = floor((screenWidth - size.width) / 2)
        frame = NSRect(x: viewX, y: barMargin, width: size.width, height: size.height)
        glass.frame = bounds
        hosting.frame = glass.bounds
        isAtBottom = true

        // Sample brightness at both bar positions
        if let image = screenshot {
            let scale = CGFloat(image.width) / screenWidth
            let sampleW = size.width * scale
            let sampleH = size.height * scale
            let sampleX = floor(CGFloat(image.width - Int(sampleW)) / 2)

            // Bottom position (CG coords: y increases downward, bottom of screen = large y)
            let bottomY = CGFloat(image.height) - (barMargin + size.height) * scale
            bottomIsLight = regionIsLight(image, x: sampleX, y: bottomY, w: sampleW, h: sampleH)

            // Top position (CG coords: top of screen = small y)
            let topY = topMargin * scale
            topIsLight = regionIsLight(image, x: sampleX, y: topY, w: sampleW, h: sampleH)
        }

        applyAppearance(isLight: bottomIsLight)
    }

    func updatePosition(cursorY: CGFloat, screenHeight: CGFloat) {
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
        glassPanel?.appearance = NSAppearance(named: appearanceName)
        if #available(macOS 26.0, *), let glass = glassPanel as? NSGlassEffectView {
            glass.tintColor = isLight
                ? NSColor(white: 1, alpha: 0.4)
                : NSColor(white: 0, alpha: 0.4)
        }
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
