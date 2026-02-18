import AppKit

/// Shared screen capture utility returning CGImage.
/// Used by both EdgeDetector (which wraps into ColorMap) and AlignmentGuides (background only).
package enum ScreenCapture {
    /// Capture the full contents of a screen, returning the CGImage.
    /// Converts the screen's AppKit frame to CG coordinates for the capture rect.
    package static func captureScreen(_ screen: NSScreen) -> CGImage? {
        let cgRect = CoordinateConverter.appKitRectToCG(screen.frame)
        return CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }
}
