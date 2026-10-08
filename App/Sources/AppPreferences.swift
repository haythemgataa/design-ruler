import Foundation

@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    /// Stored inverted under the original "hideHintBar" key, so a missing key means shown and
    /// settings saved before the switch was renamed carry over.
    var showHintBar: Bool {
        get { !UserDefaults.standard.bool(forKey: "hideHintBar") }
        set { UserDefaults.standard.set(!newValue, forKey: "hideHintBar") }
    }

    var corrections: String {
        get { UserDefaults.standard.string(forKey: "corrections") ?? "smart" }
        set { UserDefaults.standard.set(newValue, forKey: "corrections") }
    }

    /// Start Alignment Guides with `guideStyle` / `guideDirection` instead of dynamic and vertical.
    var remembersGuideStyle: Bool {
        get { UserDefaults.standard.bool(forKey: "remembersGuideStyle") }
        set { UserDefaults.standard.set(newValue, forKey: "remembersGuideStyle") }
    }

    /// Color the last Alignment Guides session ended with. Saved even while `remembersGuideStyle`
    /// is off, so turning it on resumes the last-used color
    var guideStyle: String {
        get { UserDefaults.standard.string(forKey: "guideStyle") ?? "dynamic" }
        set { UserDefaults.standard.set(newValue, forKey: "guideStyle") }
    }

    /// Direction the last Alignment Guides session ended with (see `guideStyle`).
    var guideDirection: String {
        get { UserDefaults.standard.string(forKey: "guideDirection") ?? "vertical" }
        set { UserDefaults.standard.set(newValue, forKey: "guideDirection") }
    }
}
