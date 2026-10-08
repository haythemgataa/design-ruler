import Foundation
import RaycastSwiftMacros
import DesignRulerCore

/// The color and direction the last session ended with are saved in the extension's support
/// directory, even while Remember is off, so turning it on resumes them. Swift saves them itself:
/// Raycast mode ends the process on exit, so nothing comes back to TypeScript.
@raycast func alignmentGuides(showHintBar: Bool, remembersGuideStyle: Bool, supportPath: String) {
    let coordinator = AlignmentGuidesCoordinator.shared
    let file = URL(fileURLWithPath: supportPath).appendingPathComponent("last-guide-style.plist")
    let last = remembersGuideStyle ? NSDictionary(contentsOf: file) as? [String: String] ?? [:] : [:]

    coordinator.onSessionEnd = {
        let ended = ["style": coordinator.styleName, "direction": coordinator.directionName]
        try? FileManager.default.createDirectory(atPath: supportPath, withIntermediateDirectories: true)
        try? (ended as NSDictionary).write(to: file)
    }
    coordinator.run(
        hideHintBar: !showHintBar,
        style: last["style"] ?? "dynamic",
        direction: last["direction"] ?? "vertical"
    )
}
