import KeyboardShortcuts
import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
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
        _hideHintBar = State(initialValue: UserDefaults.standard.bool(forKey: "hideHintBar"))
        _corrections = State(initialValue: UserDefaults.standard.string(forKey: "corrections") ?? "smart")
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            // --- General ---
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }

                Toggle("Hide Hint Bar", isOn: $hideHintBar)
                    .onChange(of: hideHintBar) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "hideHintBar")
                    }

                Toggle("Automatically Check for Updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.automaticallyChecksForUpdates = newValue
                    }
            }

            // --- Measure ---
            Section("Measure") {
                Picker("Border Corrections", selection: $corrections) {
                    Text("Smart").tag("smart")
                    Text("Include").tag("include")
                    Text("None").tag("none")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: corrections) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "corrections")
                }

                KeyboardShortcuts.Recorder("Shortcut:", name: .measure) { newShortcut in
                    if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: .alignmentGuides) {
                        KeyboardShortcuts.setShortcut(nil, for: .measure)
                        measureConflict = "Already assigned to Alignment Guides"
                    } else {
                        measureConflict = nil
                    }
                }

                if let measureConflict {
                    Text(measureConflict)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // --- Alignment Guides ---
            Section("Alignment Guides") {
                KeyboardShortcuts.Recorder("Shortcut:", name: .alignmentGuides) { newShortcut in
                    if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: .measure) {
                        KeyboardShortcuts.setShortcut(nil, for: .alignmentGuides)
                        guidesConflict = "Already assigned to Measure"
                    } else {
                        guidesConflict = nil
                    }
                }

                if let guidesConflict {
                    Text(guidesConflict)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            // --- About ---
            Section("About") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Design Ruler")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")")
                            .foregroundStyle(.secondary)

                        Text("\u{00A9} 2025 Haythem Elachi. All rights reserved.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Link("GitHub", destination: URL(string: "https://github.com/haythem/design-ruler")!)

                Button("Check for Updates\u{2026}") {
                    updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
