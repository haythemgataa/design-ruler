import AppKit
import QuartzCore

/// Manages the collection of active selection overlays and the drag lifecycle.
final class SelectionManager {
    private(set) var selections: [SelectionOverlay] = []
    private let parentLayer: CALayer
    private let edgeDetector: EdgeDetector
    private let scale: CGFloat

    // Drag state
    private var dragOrigin: CGPoint?
    private var liveSelection: SelectionOverlay?

    init(parentLayer: CALayer, edgeDetector: EdgeDetector, scale: CGFloat) {
        self.parentLayer = parentLayer
        self.edgeDetector = edgeDetector
        self.scale = scale
    }

    // MARK: - Drag lifecycle

    func startDrag(at point: CGPoint) {
        dragOrigin = point
        let rect = CGRect(origin: point, size: .zero)
        let sel = SelectionOverlay(rect: rect, parentLayer: parentLayer, scale: scale)
        liveSelection = sel
    }

    func updateDrag(to point: CGPoint) {
        guard let origin = dragOrigin, let sel = liveSelection else { return }
        let rect = rectFromPoints(origin, point)
        sel.updateRect(rect, animated: false)
    }

    /// End drag and attempt to snap. Returns true if snap succeeded.
    func endDrag(at point: CGPoint, screenBounds: CGRect) -> Bool {
        guard let origin = dragOrigin, let sel = liveSelection else { return false }
        let dragRect = rectFromPoints(origin, point)
        dragOrigin = nil
        liveSelection = nil

        // Minimum drag distance check
        guard dragRect.width >= 4, dragRect.height >= 4 else {
            sel.remove(animated: false)
            return false
        }

        // Attempt snap via edge detection
        if let snapped = edgeDetector.snapSelection(windowRect: dragRect, screenBounds: screenBounds) {
            let w = Int(round(snapped.width))
            let h = Int(round(snapped.height))
            sel.animateSnap(to: snapped, w: w, h: h)
            selections.append(sel)
            return true
        } else {
            sel.shakeAndRemove()
            return false
        }
    }

    /// Cancel an in-progress drag without snapping.
    func cancelDrag() {
        dragOrigin = nil
        if let sel = liveSelection {
            sel.remove(animated: false)
            liveSelection = nil
        }
    }

    // MARK: - Hit testing & hover

    func hitTest(_ point: CGPoint) -> SelectionOverlay? {
        selections.reversed().first { $0.contains(point) }
    }

    func updateHover(at point: CGPoint) {
        let hovered = hitTest(point)
        for sel in selections {
            sel.setHovered(sel === hovered)
        }
    }

    // MARK: - Removal

    func removeSelection(_ selection: SelectionOverlay) {
        selection.remove(animated: true)
        selections.removeAll { $0 === selection }
    }

    func clearAll() {
        for sel in selections {
            sel.remove(animated: true)
        }
        selections.removeAll()
    }

    var hasSelections: Bool { !selections.isEmpty }
    var isDragging: Bool { dragOrigin != nil }

    // MARK: - Helpers

    private func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
