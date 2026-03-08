import AppKit
import ScreenCaptureKit

/// Shared screen capture utility returning CGImage.
/// Used by both EdgeDetector (which wraps into ColorMap) and AlignmentGuides (background only).
package enum ScreenCapture {
    /// Capture the full contents of a screen, returning the CGImage.
    /// Uses ScreenCaptureKit (SCScreenshotManager) on macOS 14+.
    package static func captureScreen(_ screen: NSScreen) -> CGImage? {
        guard let displayIDNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = displayIDNumber.uint32Value as CGDirectDisplayID

        // Fetch shareable content synchronously via semaphore
        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                    semaphore.signal()
                    return
                }
                let filter = SCContentFilter(display: scDisplay, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = scDisplay.width * Int(screen.backingScaleFactor)
                config.height = scDisplay.height * Int(screen.backingScaleFactor)
                config.showsCursor = false
                result = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                // Fall through: result stays nil
            }
            semaphore.signal()
        }

        // 5-second timeout prevents a permanent hang if SCScreenshotManager
        // stalls (e.g., system under load or permission dialog on first launch).
        // A timeout returns nil (result stays nil), which callers handle gracefully.
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }
}
