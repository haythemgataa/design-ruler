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

    /// Set on the first launch, which also turns on Launch at Login.
    var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunchedBefore") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunchedBefore") }
    }

    /// The onboarding window was finished, or closed once Screen Recording was on. Nil until the
    /// first launch of a version with onboarding decides whether it's needed.
    var hasCompletedOnboarding: Bool? {
        get { UserDefaults.standard.object(forKey: "hasCompletedOnboarding") as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Onboarding asked for Screen Recording: after a relaunch it picks up on that page.
    var hasRequestedScreenRecording: Bool {
        get { UserDefaults.standard.bool(forKey: "hasRequestedScreenRecording") }
        set { UserDefaults.standard.set(newValue, forKey: "hasRequestedScreenRecording") }
    }
}
