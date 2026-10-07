import KeyboardShortcuts
import SwiftUI

/// One Settings tab: a grouped Form at the window's fixed width and its full (ideal) height, which
/// the window follows (see SettingsTabViewController). The outer frame takes whatever height the
/// window has while it animates between tabs, keeping the Form pinned to the top instead of
/// re-centering in the changing space.
struct SettingsPane<Content: View>: View {
    private static var width: CGFloat { 480 }

    @ViewBuilder let content: Content
    @Environment(\.settingsPaneDidResize) private var didResize

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in didResize() }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsPaneDidResizeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Called when a Settings tab's content changes height, e.g. a description wrapping to a
    /// second line, so the window can follow.
    var settingsPaneDidResize: () -> Void {
        get { self[SettingsPaneDidResizeKey.self] }
        set { self[SettingsPaneDidResizeKey.self] = newValue }
    }
}

/// Top of a tab: its icon (light and dark variants in the asset catalog), title and a line or two
/// about it, with an optional control on the trailing side.
struct PaneHeader<Title: View, Accessory: View>: View {
    let icon: String
    let description: String
    @ViewBuilder let title: Title
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(icon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.title3.weight(.semibold))
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            accessory
        }
        .padding(.vertical, 4)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(icon: String, description: String, @ViewBuilder title: () -> Title) {
        self.init(icon: icon, description: description, title: title, accessory: { EmptyView() })
    }
}

/// Secondary explanation under a section. Footers already end where the rows' controls do; the
/// leading inset lines them up with the section header and the rows' titles.
struct SectionFooter: View {
    let text: Text

    init(_ text: String) { self.text = Text(text) }
    init(_ text: AttributedString) { self.text = Text(text) }

    var body: some View {
        text
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
    }
}

/// Settings row label: a title and an optional one-line explanation or orange warning underneath.
struct SettingLabel: View {
    let title: String
    var detail: String?
    var warning: String?

    init(_ title: String, detail: String? = nil, warning: String? = nil) {
        self.title = title
        self.detail = detail
        self.warning = warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let warning {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shortcut recorder row. Rejects a shortcut already used by the other command (it reads the
/// other one from KeyboardShortcuts, so this works with the recorders in different tabs) and shows
/// the conflict in place of the row's explanation.
struct ShortcutRow: View {
    let detail: String
    let name: KeyboardShortcuts.Name
    let other: KeyboardShortcuts.Name
    let otherTitle: String

    @State private var conflict: String?

    var body: some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name) { newShortcut in
                if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: other) {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    conflict = "Already assigned to \(otherTitle)"
                } else if newShortcut != nil {  // setShortcut(nil) re-fires onChange with nil; keep the warning
                    conflict = nil
                }
            }
        } label: {
            SettingLabel("Keyboard Shortcut", detail: detail, warning: conflict)
        }
    }
}

/// Small orange capsule next to the app name while the version is 0.x.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}
