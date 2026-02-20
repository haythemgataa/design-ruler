import Foundation

@Observable
final class AppPreferences {
    static let shared = AppPreferences()

    var hideHintBar: Bool {
        get { UserDefaults.standard.bool(forKey: "hideHintBar") }
        set { UserDefaults.standard.set(newValue, forKey: "hideHintBar") }
    }

    var corrections: String {
        get { UserDefaults.standard.string(forKey: "corrections") ?? "smart" }
        set { UserDefaults.standard.set(newValue, forKey: "corrections") }
    }
}
