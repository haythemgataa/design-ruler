import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let measure = Self("measure")
    static let alignmentGuides = Self("alignmentGuides")
}

/// The app's two commands, and how the menu bar, hotkeys, Settings and onboarding name them.
enum Command: CaseIterable {
    case measure
    case alignmentGuides

    var title: String {
        switch self {
        case .measure: "Measure"
        case .alignmentGuides: "Alignment Guides"
        }
    }

    /// Image set in Assets.xcassets, with a dark variant
    var icon: String {
        switch self {
        case .measure: "MeasureIcon"
        case .alignmentGuides: "AlignmentGuidesIcon"
        }
    }

    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .measure: .measure
        case .alignmentGuides: .alignmentGuides
        }
    }

    /// The two can't share a shortcut, and pressing the other one's switches to it.
    var other: Command { self == .measure ? .alignmentGuides : .measure }
}
