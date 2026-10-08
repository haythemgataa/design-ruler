import Foundation
import Security

/// Facts about this build that decide how the app talks about updates.
enum AppBuild {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    /// Build number: CI stamps it with the commit count.
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

    /// 0.x versions are the beta.
    static let isBeta = version.hasPrefix("0.")

    /// Only a release signed with a Developer ID (it has a Team ID) can update itself: Sparkle
    /// checks the update's signature against the running app, and only signed releases get an
    /// appcast. The unsigned beta builds are ad-hoc signed, so they point to GitHub Releases instead.
    static let canAutoUpdate: Bool = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return false }
        return info[kSecCodeInfoTeamIdentifier as String] != nil
    }()

    static let releasesURL = URL(string: "https://github.com/haythemgataa/design-ruler/releases")!
}
