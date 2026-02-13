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
    private var hostingView: NSHostingView<HintBarContent>?

    // MARK: - Animation

    private let barMargin: CGFloat = 16
    private let topMargin: CGFloat = 48
    private var isAtBottom = true
    private var isAnimating = false

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
        let content = HintBarContent(state: state)
        let hosting = NSHostingView(rootView: content)
        addSubview(hosting)
        self.hostingView = hosting
    }

    // MARK: - Hit testing (pass all events through to the window)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Public API: key press/release

    func pressKey(_ key: KeyID) { state.pressedKeys.insert(key) }
    func releaseKey(_ key: KeyID) { state.pressedKeys.remove(key) }

    // MARK: - Position & animation

    /// Compute layout and set initial frame at bottom center.
    func configure(screenWidth: CGFloat, screenHeight: CGFloat) {
        guard let hosting = hostingView else { return }
        let size = hosting.fittingSize
        let viewX = floor((screenWidth - size.width) / 2)
        frame = NSRect(x: viewX, y: barMargin, width: size.width, height: size.height)
        hosting.frame = bounds
        isAtBottom = true
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
        } else {
            finalY = barMargin
            isAtBottom = true
        }
        animateSlide(to: finalY, screenHeight: screenHeight, exitDown: shouldBeAtTop)
    }

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
