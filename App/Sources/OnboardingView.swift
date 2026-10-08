import KeyboardShortcuts
import SwiftUI

/// The onboarding window's content: artwork on a dotted canvas up top (OnboardingArtwork), a title
/// and a line or two, the page's controls, and a footer with the page dots and the next step.
struct OnboardingView: View {
    let model: OnboardingModel

    @State private var ripple: Ripple?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DotGrid(ripple: ripple)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                artwork
                    .id(model.page)
                    .transition(pageTransition)
            }
            .frame(width: OnboardingLayout.width, height: OnboardingLayout.artworkHeight)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title.weight(.semibold))
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 48)

                controls
                    .padding(.horizontal, 40)
            }
            .padding(.top, 12)
            .id(model.page)
            .transition(pageTransition)

            Spacer(minLength: 0)
            footer
        }
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.height)
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea()  // the artwork runs under the transparent title bar
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.12), value: model.page)
        .onAppear {
            switch model.page {
            case .welcome: ripple = Ripple(origin: WelcomeArtwork.iconCenter, tint: .accentColor)
            case .permission where model.hasPermission: celebratePermission()
            default: break
            }
        }
        .onChange(of: model.hasPermission) { _, granted in
            if granted { celebratePermission() }
        }
    }

    private func celebratePermission() {
        ripple = Ripple(origin: PermissionArtwork.toggleCenter, tint: .green)
    }

    /// The old page clears out quickly before the new one settles in, so the two never read on top
    /// of each other.
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24))
                .animation(.spring(duration: 0.5, bounce: 0.12).delay(0.1)),
            removal: .opacity.combined(with: .offset(x: -12))
                .animation(.easeIn(duration: 0.12))
        )
    }

    // MARK: - Pages

    @ViewBuilder private var artwork: some View {
        switch model.page {
        case .welcome: WelcomeArtwork()
        case .permission: PermissionArtwork(isOn: model.hasPermission)
        case .shortcuts: MenuBarArtwork(lastChange: model.lastShortcutChange)
        }
    }

    private var title: String {
        switch model.page {
        case .welcome: "Welcome to Design Ruler"
        case .permission: "Allow Screen Recording"
        case .shortcuts: "Open It from Anywhere"
        }
    }

    private var message: String {
        switch model.page {
        case .welcome:
            "Measure anything on your screen and check that it lines up, right from the menu bar."
        case .permission:
            "Design Ruler measures a still screenshot of your screen. It never leaves your Mac and is never saved."
        case .shortcuts:
            "Design Ruler lives in your menu bar. Give each tool a shortcut to open it from any app, now or later in Settings."
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.page {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Feature(icon: "MeasureIcon", title: "Measure", detail: "See the size of anything.")
                Feature(icon: "AlignmentGuidesIcon", title: "Alignment Guides", detail: "Check that things line up.")
            }
        case .permission:
            PermissionStatus(model: model)
        case .shortcuts:
            VStack(spacing: 0) {
                OnboardingShortcutRow(icon: "MeasureIcon", title: "Measure", name: .measure,
                                      other: .alignmentGuides, otherTitle: "Alignment Guides",
                                      onChange: model.shortcutChanged)
                Divider().padding(.leading, 54)
                OnboardingShortcutRow(icon: "AlignmentGuidesIcon", title: "Alignment Guides", name: .alignmentGuides,
                                      other: .measure, otherTitle: "Measure", onChange: model.shortcutChanged)
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if model.pages.count > 1, let index = model.pages.firstIndex(of: model.page) {
                PageDots(count: model.pages.count, index: index)
            }
            Spacer()
            Button {
                primaryAction()
            } label: {
                Text(primaryTitle)
                    .frame(minWidth: 96)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var primaryTitle: String {
        switch model.page {
        case .welcome: "Get Started"
        case .permission where !model.hasPermission: "Open System Settings"
        default: model.isLastPage ? "Done" : "Continue"
        }
    }

    private func primaryAction() {
        if model.page == .permission && !model.hasPermission {
            model.requestPermission()
        } else {
            model.advance()
        }
    }
}

enum OnboardingLayout {
    static let width: CGFloat = 480
    static let height: CGFloat = 548
    /// 22 rows of the 12pt dot grid, so artwork centered in it sits on the grid.
    static let artworkHeight: CGFloat = 264
}

// MARK: - Pieces

/// A command on the welcome page: its icon, name and what it's for.
private struct Feature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            AssetIcon(icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Under the Screen Recording message: nothing before the first request, then how to apply a
/// permission switched on in System Settings (macOS applies it when the app reopens), then a tick.
private struct PermissionStatus: View {
    let model: OnboardingModel

    var body: some View {
        Group {
            if model.hasPermission {
                Label("Screen Recording is on", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if model.hasRequestedPermission {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Switched it on?")
                            .foregroundStyle(.secondary)
                        Button("Quit & Reopen") { model.relaunch() }
                            .buttonStyle(.link)
                    }
                    if !AppBuild.canAutoUpdate {
                        // Ad-hoc signed builds don't match the entry an earlier build left behind
                        Text("Already on from an earlier beta? Remove it with \u{2212}, then click Open System Settings again.")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .multilineTextAlignment(.center)
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: model.hasPermission)
        .animation(.easeOut(duration: 0.25), value: model.hasRequestedPermission)
    }
}

/// A command's shortcut recorder on the shortcuts page, with a conflict warning under its name.
private struct OnboardingShortcutRow: View {
    let icon: String
    let title: String
    let name: KeyboardShortcuts.Name
    let other: KeyboardShortcuts.Name
    let otherTitle: String
    let onChange: (KeyboardShortcuts.Name) -> Void

    @State private var conflict: String?

    var body: some View {
        HStack(spacing: 12) {
            AssetIcon(icon, size: 28)
            SettingLabel(title, warning: conflict)
            Spacer(minLength: 12)
            ShortcutRecorder(name: name, other: other, otherTitle: otherTitle, conflict: $conflict) { onChange(name) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Where the user is in the flow: a dot per page, the current one stretched into a capsule.
private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
