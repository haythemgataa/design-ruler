import AppKit
import ScreenCaptureKit

/// Shared screen capture utility returning CGImages.
/// Used by both Measure (images wrapped into ColorMap) and AlignmentGuides (background only).
package enum ScreenCapture {
    /// Capture every screen in `screens`, returning one image per screen in the same order
    /// (nil where that screen could not be captured).
    ///
    /// Uses ScreenCaptureKit with a single shareable-content query and concurrent per-display
    /// screenshots. Blocks the calling thread until done, capped at 5 seconds for the whole batch
    /// so a stalled ScreenCaptureKit (e.g. system under load) can't freeze launch; screens not
    /// captured by then come back nil.
    package static func captureScreens(_ screens: [NSScreen]) -> [CGImage?] {
        // Read AppKit state here on the calling (main) thread; the capture task runs off-main.
        let targets: [(displayID: CGDirectDisplayID, scale: Int)?] = screens.map { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (displayID: number.uint32Value, scale: Int(screen.backingScaleFactor))
        }
        let results = CaptureResults(count: screens.count)
        let semaphore = DispatchSemaphore(value: 0)

        // Detached: the calling thread is blocked on the semaphore, so the task must never
        // need the main actor. userInitiated: the (user-interactive) main thread is waiting on it.
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
            await withTaskGroup(of: (Int, CGImage?).self) { group in
                for (index, target) in targets.enumerated() {
                    guard let target, let display = content.displays.first(where: { $0.displayID == target.displayID }) else { continue }
                    group.addTask {
                        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = display.width * target.scale
                        config.height = display.height * target.scale
                        config.showsCursor = false
                        let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        return (index, image)
                    }
                }
                for await result in group {
                    results.set(result.0, result.1)
                }
            }
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return results.snapshot()
    }
}

/// Lock-protected result slots. After a timeout the capture task may still finish and write
/// here; nobody reads it any more, but the lock keeps that late write race-free.
private final class CaptureResults: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [CGImage?]

    init(count: Int) {
        images = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ image: CGImage?) {
        lock.lock()
        images[index] = image
        lock.unlock()
    }

    func snapshot() -> [CGImage?] {
        lock.lock()
        defer { lock.unlock() }
        return images
    }
}
