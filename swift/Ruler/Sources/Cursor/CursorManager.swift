import AppKit

/// Centralized cursor state machine with explicit state tracking and balanced hide/push counters.
/// All NSCursor push/pop/hide/unhide calls go through this class (except `addCursorRect` in `resetCursorRects`).
final class CursorManager {
    static let shared = CursorManager()

    enum State: String {
        case systemCrosshair   // Launch: cursor rects manage crosshair, cursor visible
        case hidden            // After first mouse move: cursor hidden, CAShapeLayer renders
        case pointingHand      // Hovering a selection: pointing hand pushed, cursor visible
        case crosshairDrag     // During drag: system crosshair pushed, cursor visible
    }

    private(set) var state: State = .systemCrosshair
    private var hideCount: Int = 0
    private var pushCount: Int = 0

    private init() {}

    // MARK: - Transitions

    /// First mouse move: transition from system crosshair to hidden custom crosshair.
    /// CrosshairView handles invalidateCursorRects separately.
    func transitionToHidden() {
        guard state == .systemCrosshair else { return }
        NSCursor.hide()
        hideCount += 1
        state = .hidden
    }

    /// Hover selection: show pointing hand cursor.
    func transitionToPointingHand() {
        guard state == .hidden else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount = max(hideCount - 1, 0)
        state = .pointingHand
    }

    /// Start drag from hidden state: show system crosshair cursor.
    func transitionToCrosshairDrag() {
        guard state == .hidden else { return }
        NSCursor.crosshair.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount = max(hideCount - 1, 0)
        state = .crosshairDrag
    }

    /// Return to hidden state from any visible-cursor state.
    func transitionBackToHidden() {
        switch state {
        case .pointingHand, .crosshairDrag:
            NSCursor.pop()
            pushCount = max(pushCount - 1, 0)
            NSCursor.hide()
            hideCount += 1
            state = .hidden
        default:
            break
        }
    }

    /// Transition to pointing hand from system crosshair (for alignment guides hover).
    func transitionToPointingHandFromSystem() {
        guard state == .systemCrosshair else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        state = .pointingHand
    }

    /// Transition back to system crosshair from pointing hand (for alignment guides unhover).
    func transitionBackToSystem() {
        guard state == .pointingHand else { return }
        NSCursor.pop()
        pushCount = max(pushCount - 1, 0)
        state = .systemCrosshair
    }

    /// Unconditional cleanup for all exit paths.
    /// Pops all pushed cursors and unhides all hidden levels.
    func restore() {
        for _ in 0..<pushCount {
            NSCursor.pop()
        }
        pushCount = 0
        for _ in 0..<hideCount {
            NSCursor.unhide()
        }
        hideCount = 0
        state = .systemCrosshair
    }

    /// Reset to initial state. Used for multi-monitor window re-setup.
    func reset() {
        restore()
    }
}
