import Foundation

struct EdgeHit {
    let distance: CGFloat        // points from cursor to edge
    let screenPosition: CGFloat  // absolute screen coord (AX coords)
    let borderAbsorbed: Bool     // true if a 1px border was absorbed into this measurement

    init(distance: CGFloat, screenPosition: CGFloat, borderAbsorbed: Bool = false) {
        self.distance = distance
        self.screenPosition = screenPosition
        self.borderAbsorbed = borderAbsorbed
    }
}

struct DirectionalEdges {
    let cursorPosition: CGPoint  // AX coords
    let left: EdgeHit?
    let right: EdgeHit?
    let top: EdgeHit?
    let bottom: EdgeHit?
}
