import AppKit

enum CoordinateConverter {
    /// Convert from AppKit coordinates (bottom-left origin) to AX/CG coordinates (top-left origin)
    static func appKitToAX(_ point: NSPoint) -> CGPoint {
        guard let screenHeight = NSScreen.main?.frame.height else {
            return CGPoint(x: point.x, y: point.y)
        }
        return CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// Convert from AX/CG coordinates (top-left origin) to AppKit coordinates (bottom-left origin)
    static func axToAppKit(_ point: CGPoint) -> NSPoint {
        guard let screenHeight = NSScreen.main?.frame.height else {
            return NSPoint(x: point.x, y: point.y)
        }
        return NSPoint(x: point.x, y: screenHeight - point.y)
    }
}
