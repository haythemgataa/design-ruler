import CoreGraphics

enum PermissionChecker {
    /// Returns true if screen recording permission is granted
    static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests screen recording permission. Returns true if already granted.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        return false
    }
}
