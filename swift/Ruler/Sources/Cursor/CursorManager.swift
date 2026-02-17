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
        case resizeUpDown      // Alignment guides: horizontal preview line, resize cursor visible
        case resizeLeftRight   // Alignment guides: vertical preview line, resize cursor visible
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

    /// Hover selection: show pointing hand cursor (from hidden state).
    func transitionToPointingHand() {
        guard state == .hidden else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        NSCursor.unhide()
        hideCount = max(hideCount - 1, 0)
        state = .pointingHand
    }

    /// Hover selection: show pointing hand cursor (from system crosshair state).
    /// Used by alignment guides where cursor rects manage resize cursors.
    func transitionToPointingHandFromSystem() {
        guard state == .systemCrosshair else { return }
        NSCursor.pointingHand.push()
        pushCount += 1
        state = .pointingHand
    }

    /// Return to system cursor state from pointing hand or resize states.
    /// Used by alignment guides to restore cursor-rect-managed resize cursors.
    func transitionBackToSystem() {
        switch state {
        case .pointingHand, .resizeUpDown, .resizeLeftRight:
            NSCursor.pop()
            pushCount = max(pushCount - 1, 0)
            state = .systemCrosshair
        default:
            break
        }
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
        case .pointingHand, .crosshairDrag, .resizeUpDown, .resizeLeftRight:
            NSCursor.pop()
            pushCount = max(pushCount - 1, 0)
            NSCursor.hide()
            hideCount += 1
            state = .hidden
        default:
            break
        }
    }

    // MARK: - Resize Cursor Transitions (Alignment Guides)

    /// First mouse move in alignment guides with horizontal direction.
    func transitionToResizeUpDown() {
        guard state == .systemCrosshair else { return }
        NSCursor.resizeUpDown.push()
        pushCount += 1
        state = .resizeUpDown
    }

    /// First mouse move in alignment guides with vertical direction.
    func transitionToResizeLeftRight() {
        guard state == .systemCrosshair else { return }
        NSCursor.resizeLeftRight.push()
        pushCount += 1
        state = .resizeLeftRight
    }

    /// Hover a placed line while in resize state: show pointing hand cursor.
    func transitionToPointingHandFromResize() {
        guard state == .resizeUpDown || state == .resizeLeftRight else { return }
        NSCursor.pop()
        pushCount = max(pushCount - 1, 0)
        NSCursor.pointingHand.push()
        pushCount += 1
        state = .pointingHand
    }

    /// Return to resize cursor from pointing hand (unhover a placed line).
    func transitionToResize(_ direction: Direction) {
        guard state == .pointingHand else { return }
        NSCursor.pop()
        pushCount = max(pushCount - 1, 0)
        let cursor: NSCursor = direction == .vertical ? .resizeLeftRight : .resizeUpDown
        cursor.push()
        pushCount += 1
        state = direction == .vertical ? .resizeLeftRight : .resizeUpDown
    }

    /// Switch between resize directions (tab toggle in alignment guides).
    func switchResize(to direction: Direction) {
        guard state == .resizeUpDown || state == .resizeLeftRight else { return }
        let newState: State = direction == .vertical ? .resizeLeftRight : .resizeUpDown
        guard state != newState else { return }
        NSCursor.pop()
        pushCount = max(pushCount - 1, 0)
        let cursor: NSCursor = direction == .vertical ? .resizeLeftRight : .resizeUpDown
        cursor.push()
        pushCount += 1
        state = newState
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
