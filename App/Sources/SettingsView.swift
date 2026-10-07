import KeyboardShortcuts
import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    static let width: CGFloat = 520

    let updater: SPUUpdater

    @State private var launchAtLogin: Bool
    @State private var hideHintBar: Bool
    @State private var corrections: String
    @State private var automaticallyChecksForUpdates: Bool
    @State private var measureConflict: String?
    @State private var guidesConflict: String?

    init(updater: SPUUpdater) {
        self.updater = updater
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _hideHintBar = State(initialValue: AppPreferences.shared.hideHintBar)
        _corrections = State(initialValue: AppPreferences.shared.corrections)
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    /// Footer under General in builds that can't update themselves, with a link to GitHub Releases.
    private static let betaUpdatesNote: AttributedString = {
        let markdown = "This beta can't update itself yet. Download new versions from "
            + "[GitHub Releases](\(AppBuild.releasesURL.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }()

    private var correctionsDescription: String {
        switch corrections {
        case "include": return "Always counts 1px borders as part of the measured element."
        case "none": return "Reports edges exactly as detected, with no adjustments."
        default: return "Counts a 1px border only when that lands the size on the 4px grid."
        }
    }

    var body: some View {
        Form {
            // --- Header ---
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Design Ruler")
                                .font(.title2.weight(.semibold))
                            if AppBuild.isBeta {
                                BetaBadge()
                            }
                        }
                        Text("Version \(AppBuild.version)")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Check for Updates\u{2026}") {
                        updater.checkForUpdates()
                    }
                    .disabled(!AppBuild.canAutoUpdate)
                }
                .padding(.vertical, 4)
            }

            // --- General ---
            Section {
                Toggle(isOn: $launchAtLogin) {
                    SettingLabel("Launch at Login", symbol: "power", color: .green,
                                 detail: "Keeps Design Ruler in the menu bar after you restart.")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

                Toggle(isOn: $hideHintBar) {
                    SettingLabel("Hide Hint Bar", symbol: "keyboard", color: .gray,
                                 detail: "Hides the keyboard shortcut bar at the bottom of the overlay.")
                }
                .onChange(of: hideHintBar) { _, newValue in
                    AppPreferences.shared.hideHintBar = newValue
                }

                Toggle(isOn: AppBuild.canAutoUpdate ? $automaticallyChecksForUpdates : .constant(false)) {
                    SettingLabel("Check for Updates Automatically", symbol: "arrow.triangle.2.circlepath", color: .blue,
                                 detail: "Looks for new versions in the background once a day.")
                }
                .disabled(!AppBuild.canAutoUpdate)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            } header: {
                Text("General")
            } footer: {
                if !AppBuild.canAutoUpdate {
                    Text(Self.betaUpdatesNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // --- Measure ---
            Section("Measure") {
                Picker(selection: $corrections) {
                    Text("Smart").tag("smart")
                    Text("Include Borders").tag("include")
                    Text("None").tag("none")
                } label: {
                    SettingLabel("Border Corrections", symbol: "square.dashed", color: .orange,
                                 detail: correctionsDescription)
                }
                .pickerStyle(.menu)
                .onChange(of: corrections) { _, newValue in
                    AppPreferences.shared.corrections = newValue
                }
            }

            // --- Keyboard Shortcuts ---
            Section {
                shortcutRow("Measure", symbol: "ruler", color: .purple,
                            name: .measure, other: .alignmentGuides, otherTitle: "Alignment Guides",
                            conflict: $measureConflict)
                shortcutRow("Alignment Guides", symbol: "rectangle.split.3x1", color: .pink,
                            name: .alignmentGuides, other: .measure, otherTitle: "Measure",
                            conflict: $guidesConflict)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Shortcuts work from any app. Press the same shortcut again to close the overlay, or the other one to switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // --- Footer ---
            Section {
                HStack {
                    Text("\u{00A9} 2026 Haythem Gataa")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link(destination: URL(string: "https://github.com/haythemgataa/design-ruler")!) {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                    }
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsView {
    /// Shortcut recorder row. Rejects a shortcut already used by the other command and shows
    /// the conflict in place of the row's explanation.
    private func shortcutRow(_ title: String, symbol: String, color: Color,
                             name: KeyboardShortcuts.Name, other: KeyboardShortcuts.Name, otherTitle: String,
                             conflict: Binding<String?>) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name) { newShortcut in
                if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: other) {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    conflict.wrappedValue = "Already assigned to \(otherTitle)"
                } else if newShortcut != nil {  // setShortcut(nil) re-fires onChange with nil; keep the warning
                    conflict.wrappedValue = nil
                }
            }
        } label: {
            SettingLabel(title, symbol: symbol, color: color, warning: conflict.wrappedValue)
        }
    }
}

/// Small orange capsule next to the app name while the version is 0.x.
private struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}

/// Settings row label in the System Settings style: a colored icon tile, a title, and an
/// optional one-line explanation or orange warning underneath.
private struct SettingLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var detail: String?
    var warning: String?

    init(_ title: String, symbol: String, color: Color, detail: String? = nil, warning: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.detail = detail
        self.warning = warning
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

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
}
