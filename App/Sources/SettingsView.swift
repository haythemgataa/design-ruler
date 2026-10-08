import ServiceManagement
import Sparkle
import SwiftUI

// The Settings window's tabs. SettingsWindowController puts each one in a toolbar tab.

struct GeneralSettingsView: View {
    let updater: SPUUpdater

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showHintBar = AppPreferences.shared.showHintBar
    @State private var automaticallyChecksForUpdates: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    /// Footer in builds that can't update themselves, with a link to GitHub Releases.
    private static let betaUpdatesNote: AttributedString = {
        let markdown = "This beta can't update itself yet. Download new versions from "
            + "[GitHub Releases](\(AppBuild.releasesURL.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }()

    var body: some View {
        SettingsPane {
            // --- App ---
            Section {
                PaneHeader(icon: "DesignRulerIcon", description: "Version \(AppBuild.version) (\(AppBuild.build))") {
                    HStack(spacing: 8) {
                        Text("Design Ruler")
                        if AppBuild.isBeta {
                            BetaBadge()
                        }
                    }
                } accessory: {
                    Button("Check for Updates\u{2026}") {
                        updater.checkForUpdates()
                    }
                    .disabled(!AppBuild.canAutoUpdate)
                }
            }

            Section {
                Toggle(isOn: $launchAtLogin) {
                    SettingLabel("Launch at Login", detail: "Keeps Design Ruler in the menu bar after you restart.")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

                Toggle(isOn: $showHintBar) {
                    SettingLabel("Show Hint Bar", detail: "Shows the keyboard shortcuts at the bottom of the overlay.")
                }
                .onChange(of: showHintBar) { _, newValue in
                    AppPreferences.shared.showHintBar = newValue
                }

                Toggle(isOn: AppBuild.canAutoUpdate ? $automaticallyChecksForUpdates : .constant(false)) {
                    SettingLabel("Check for Updates Automatically",
                                 detail: "Looks for new versions in the background once a day.")
                }
                .disabled(!AppBuild.canAutoUpdate)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            } footer: {
                VStack(spacing: 28) {
                    if !AppBuild.canAutoUpdate {
                        SectionFooter(Self.betaUpdatesNote)
                    }

                    // --- Footer ---
                    HStack {
                        Text("\u{00A9} 2026 Haythem Gataa")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(destination: URL(string: "https://github.com/haythemgataa/design-ruler")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .font(.callout)
                    .padding(.top, AppBuild.canAutoUpdate ? 12 : 0)
                }
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        // Reopening Settings reuses the window, so onAppear doesn't fire again: re-read the
        // status (it may have changed in System Settings) whenever the window becomes key
        .onChange(of: controlActiveState) { _, state in
            if state == .key { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }
}

struct MeasureSettingsView: View {
    @State private var corrections = AppPreferences.shared.corrections

    private var correctionsDescription: String {
        switch corrections {
        case "include": return "Counts them in every measurement."
        case "none": return "Leaves them out of every measurement."
        default: return "Counts them or not, whichever fits the 4px grid."
        }
    }

    /// The green matches the crosshair's tick for an edge whose border was counted (CrosshairView).
    private static let bordersNote: AttributedString = {
        var note = AttributedString("A ")
        var green = AttributedString("green")
        green.foregroundColor = Color(.sRGB, red: 0.29, green: 0.87, blue: 0.50)
        green.inlinePresentationIntent = .stronglyEmphasized  // bolder, so the light green reads on light backgrounds
        note.append(green)
        note.append(AttributedString(" tick marks an edge where a border was counted."))
        return note
    }()

    var body: some View {
        SettingsPane {
            Section {
                PaneHeader(icon: Command.measure.icon,
                           description: "Point at anything on screen to see its width and height. Edges are "
                               + "detected from the pixels around the cursor.") {
                    Text(Command.measure.title)
                }
            }

            Section {
                ShortcutRow(command: .measure)
            } footer: {
                SectionFooter("Press it again to close the overlay, or the \(Command.measure.other.title) shortcut to switch.")
            }

            Section {
                Picker(selection: $corrections) {
                    Text("Smart").tag("smart")
                    Text("Always").tag("include")
                    Text("Never").tag("none")
                } label: {
                    SettingLabel("Count 1px Borders", detail: correctionsDescription)
                }
                .pickerStyle(.menu)
                .onChange(of: corrections) { _, newValue in
                    AppPreferences.shared.corrections = newValue
                }
            } header: {
                Text("Measurements")
            } footer: {
                SectionFooter(Self.bordersNote)
            }
        }
    }
}

struct AlignmentSettingsView: View {
    @State private var remembersGuideStyle = AppPreferences.shared.remembersGuideStyle

    var body: some View {
        SettingsPane {
            Section {
                PaneHeader(icon: Command.alignmentGuides.icon,
                           description: "Place vertical and horizontal lines across the screen to check "
                               + "that elements line up.") {
                    Text(Command.alignmentGuides.title)
                }
            }

            Section {
                ShortcutRow(command: .alignmentGuides)
            } footer: {
                SectionFooter("Press it again to close the overlay, or the \(Command.alignmentGuides.other.title) shortcut to switch.")
            }

            Section("Guides") {
                Toggle(isOn: $remembersGuideStyle) {
                    SettingLabel("Remember Color and Direction",
                                 detail: "Starts where you left off, instead of Dynamic and vertical.")
                }
                .onChange(of: remembersGuideStyle) { _, newValue in
                    AppPreferences.shared.remembersGuideStyle = newValue
                }
            }
        }
    }
}
