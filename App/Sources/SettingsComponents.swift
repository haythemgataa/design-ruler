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
                AssetIcon(icon, size: 32)

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

/// Secondary explanation under a section. The Form already lines footers up with the section
/// header and the rows' titles (macOS 26+ SDK), so no padding of its own.
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

/// A command's shortcut recorder row, showing a conflict (see ShortcutRecorder) in place of its
/// explanation.
struct ShortcutRow: View {
    let command: Command

    @State private var conflict: String?

    var body: some View {
        LabeledContent {
            ShortcutRecorder(command: command, conflict: $conflict)
        } label: {
            SettingLabel("Keyboard Shortcut", detail: "Opens \(command.title) from any app.", warning: conflict)
        }
    }
}

/// Shortcut recorder that rejects a shortcut already used by the other command. It reads the other
/// one from KeyboardShortcuts, so this works with the recorders in different tabs and windows.
struct ShortcutRecorder: View {
    let command: Command
    @Binding var conflict: String?
    var onChange: () -> Void = {}

    var body: some View {
        KeyboardShortcuts.Recorder(for: command.shortcutName) { newShortcut in
            if let newShortcut, newShortcut == KeyboardShortcuts.getShortcut(for: command.other.shortcutName) {
                KeyboardShortcuts.setShortcut(nil, for: command.shortcutName)
                conflict = "Already assigned to \(command.other.title)"
            } else if newShortcut != nil {  // setShortcut(nil) re-fires onChange with nil; keep the warning
                conflict = nil
            }
            onChange()
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

/// An asset catalog icon drawn once at its exact pixel size, with high-quality downsampling. Shrunk
/// by the GPU instead, the 256px icons' fine background grid breaks up into dots at 24-40pt.
/// Follows the display's scale and the light/dark variant.
struct AssetIcon: View {
    let name: String
    let size: CGFloat

    @Environment(\.displayScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let image = Self.render(name, pixels: Int((size * scale).rounded()), dark: colorScheme == .dark) {
            Image(decorative: image, scale: scale)
                .frame(width: size, height: size)
        }
    }

    private static var cache: [String: CGImage] = [:]

    private static func render(_ name: String, pixels: Int, dark: Bool) -> CGImage? {
        let key = "\(name)-\(pixels)-\(dark)"
        if let cached = cache[key] { return cached }
        guard let image = NSImage(named: name), pixels > 0,
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        graphics.imageInterpolation = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        // The asset's appearance variant is picked when it's drawn
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        NSGraphicsContext.restoreGraphicsState()

        let result = context.makeImage()
        cache[key] = result
        return result
    }
}
