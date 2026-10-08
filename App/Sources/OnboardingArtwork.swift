import KeyboardShortcuts
import SwiftUI

// Artwork for the onboarding pages, in the installer's style (scripts/assets/dmg-background.png):
// a dotted canvas, light wireframe UI, guide lines and measurement pills. Each piece is laid out
// in the 480×264 artwork area, on the 12pt dot grid.

/// A ripple across the dot grid, from `origin` (in the artwork's coordinates).
struct Ripple: Equatable {
    var origin: CGPoint
    var tint: Color
    var start = Date()
}

/// Dots on a 12pt grid, drawn once. A ripple tints and grows the dots as its front passes, like the
/// overlay's launch wave: only the lit dots redraw, and only while it runs.
struct DotGrid: View {
    var ripple: Ripple?

    @State private var isRippling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spacing: CGFloat = 12
    private static let duration: TimeInterval = 1.4
    private static let band: CGFloat = 54
    /// Lit dots are grouped into this many strengths, so a frame is a handful of fills.
    private static let levels = 8

    var body: some View {
        ZStack {
            Canvas { context, size in
                var dots = Path()
                Self.forEachDot(in: size) { dots.addEllipse(in: CGRect(x: $0.x - 0.75, y: $0.y - 0.75, width: 1.5, height: 1.5)) }
                context.fill(dots, with: .color(.primary.opacity(0.16)))
            }
            if isRippling, let ripple {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        Self.drawRipple(ripple, in: context, size: size, at: timeline.date)
                    }
                }
            }
        }
        .task(id: ripple?.start) {
            guard ripple != nil, !reduceMotion else { return }
            isRippling = true
            try? await Task.sleep(for: .seconds(Self.duration))
            isRippling = false
        }
    }

    private static func forEachDot(in size: CGSize, _ body: (CGPoint) -> Void) {
        for row in 0...Int(size.height / spacing) {
            for column in 0...Int(size.width / spacing) {
                body(CGPoint(x: CGFloat(column) * spacing, y: CGFloat(row) * spacing))
            }
        }
    }

    /// The front eases out from the origin to the farthest corner, fading as it goes.
    private static func drawRipple(_ ripple: Ripple, in context: GraphicsContext, size: CGSize, at date: Date) {
        let t = min(max(date.timeIntervalSince(ripple.start) / duration, 0), 1)
        let reach = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
                     CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - ripple.origin.x, $0.y - ripple.origin.y) }.max() ?? 0
        let front = (1 - pow(1 - t, 3)) * reach
        let fade = 1 - t

        var paths = Array(repeating: Path(), count: levels)
        forEachDot(in: size) { point in
            let behind = (front - hypot(point.x - ripple.origin.x, point.y - ripple.origin.y)) / band
            guard behind > 0, behind < 1 else { return }
            let level = min(Int((1 - behind) * (1 - behind) * fade * Double(levels)), levels - 1)
            let radius = 0.75 + 1.25 * strength(level)
            paths[level].addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        for (level, path) in paths.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(ripple.tint.opacity(0.9 * strength(level))))
        }
    }

    private static func strength(_ level: Int) -> Double { (Double(level) + 0.5) / Double(levels) }
}

// MARK: - Welcome

/// The app icon, measured and lined up the way the overlay does it: a selection is dragged out
/// around it and snaps to its edges with its size, then a vertical guide slides in from the left and
/// a horizontal one drops in from the top, each with its position pill until it's placed.
struct WelcomeArtwork: View {
    /// On the dot grid: a 96pt icon centered in the artwork has its edges on grid lines.
    static let iconCenter = CGPoint(x: 240, y: 132)
    private static let icon = CGRect(x: 192, y: 84, width: 96, height: 96)
    /// The drag starts above-left of the icon and overshoots it, as a hand would, before snapping.
    private static let dragRect = CGRect(x: icon.minX - 14, y: icon.minY - 12, width: icon.width + 26, height: icon.height + 22)

    @State private var showsIcon = false
    @State private var selection = CGRect(origin: dragRect.origin, size: .zero)
    @State private var showsSelection = false
    @State private var isSnapped = false
    @State private var verticalX: CGFloat = 0
    @State private var verticalState = GuideState.hidden
    @State private var horizontalY: CGFloat = 0
    @State private var horizontalState = GuideState.hidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            AssetIcon("DesignRulerIcon", size: Self.icon.width)
                .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
                .scaleEffect(showsIcon ? 1 : 0.85)
                .opacity(showsIcon ? 1 : 0)
                .position(Self.iconCenter)

            // Selection: dashed while dragging, solid once it snaps (SelectionOverlay)
            SelectionShape(rect: selection)
                .fill(Color.primary.opacity(0.04))
                .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: isSnapped ? [] : [4, 3]))
                .opacity(showsSelection ? 1 : 0)
            MeasurePill(Text("\(Int(Self.icon.width)) \(Text("\u{00D7}").foregroundStyle(.tertiary)) \(Int(Self.icon.height))"))
                .fixedSize()
                .frame(width: Self.icon.width)
                .offset(x: Self.icon.minX, y: Self.icon.maxY + 6 + (isSnapped ? 0 : -4))
                .opacity(isSnapped ? 1 : 0)

            MovingGuide(axis: .vertical, position: verticalX, color: GuideColor.blue, state: verticalState)
            MovingGuide(axis: .horizontal, position: horizontalY, color: GuideColor.orange, state: horizontalState)
        }
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.artworkHeight, alignment: .topLeading)
        .task { try? await play() }  // stops when the page goes, at the next pause
    }

    private func play() async throws {
        guard !reduceMotion else {
            showsIcon = true
            selection = Self.icon
            showsSelection = true
            isSnapped = true
            verticalX = Self.icon.minX
            verticalState = .placed
            horizontalY = Self.icon.maxY
            horizontalState = .placed
            return
        }

        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { showsIcon = true }
        try await Task.sleep(for: .milliseconds(450))

        // Drag out the selection, then let go: it snaps to the icon (solid) and its size slides in
        showsSelection = true
        withAnimation(.easeInOut(duration: 0.8)) { selection = Self.dragRect }
        try await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeOut(duration: 0.25)) {
            selection = Self.icon
            isSnapped = true
        }
        try await Task.sleep(for: .milliseconds(600))

        try await place($verticalX, $verticalState, at: Self.icon.minX)
        try await Task.sleep(for: .milliseconds(150))
        try await place($horizontalY, $horizontalState, at: Self.icon.maxY)
    }

    /// A guide follows the pointer in, showing where it is, then gets placed.
    private func place(_ position: Binding<CGFloat>, _ state: Binding<GuideState>, at target: CGFloat) async throws {
        state.wrappedValue = .moving
        withAnimation(.easeInOut(duration: 0.9)) { position.wrappedValue = target }
        try await Task.sleep(for: .milliseconds(1050))
        withAnimation(.easeOut(duration: 0.25)) { state.wrappedValue = .placed }
    }
}

private enum GuideState { case hidden, moving, placed }

/// A rectangle at an absolute position in the artwork, its edges on the pixel grid, animatable.
private struct SelectionShape: Shape {
    var rect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(rect.minX, rect.minY), AnimatablePair(rect.width, rect.height)) }
        set { rect = CGRect(x: newValue.first.first, y: newValue.first.second,
                            width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in _: CGRect) -> Path {
        Path(rect.insetBy(dx: -0.5, dy: -0.5))  // the stroke runs just outside the icon, like the overlay's
    }
}

/// A guide line across the artwork at `position`, with the overlay's position pill beside it while
/// it moves (placed lines don't show one). Animatable, so the pill counts as the line travels.
private struct MovingGuide: View, Animatable {
    let axis: Axis
    var position: CGFloat
    let color: Color
    let state: GuideState

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        let label = axis == .vertical ? "X" : "Y"
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(0.75))
                .frame(width: axis == .vertical ? 1 : OnboardingLayout.width,
                       height: axis == .vertical ? OnboardingLayout.artworkHeight : 1)
                // On whole points, just outside the icon over the selection's stroke: left of a
                // vertical line's position, below a horizontal one's
                .offset(x: axis == .vertical ? position - 1 : 0, y: axis == .vertical ? 0 : position)
            // Beside the line as in GuideLine: right of a vertical one, above a horizontal one
            MeasurePill(Text("\(Text(label).foregroundStyle(.secondary)) \(MeasurePill.padded(Int(position.rounded())))"))
                .fixedSize()
                .offset(x: axis == .vertical ? position + 8 : 24, y: axis == .vertical ? 40 : position - 8 - 24)
                .opacity(state == .moving ? 1 : 0)
        }
        .opacity(state == .hidden ? 0 : 1)
    }
}

// MARK: - Screen Recording

/// The System Settings list the user is about to visit: Design Ruler between two wireframe rows,
/// with its switch following the real permission and a pointer nudging toward it until then.
struct PermissionArtwork: View {
    let isOn: Bool

    private static let card = CGRect(x: 96, y: 84, width: 288, height: 132)
    private static let rowHeight: CGFloat = 44
    static let toggleCenter = CGPoint(x: card.maxX - 14 - 17, y: card.minY + rowHeight * 1.5)

    @State private var nudge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The list's name in System Settings
    private static let listTitle = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
    ) ? "Screen & System Audio Recording" : "Screen Recording"

    var body: some View {
        ZStack {
            Text(Self.listTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.card.width - 8, alignment: .leading)
                .position(x: Self.card.midX, y: Self.card.minY - 14)

            VStack(spacing: 0) {
                placeholderRow(barWidth: 76)
                Divider().padding(.leading, 46)
                HStack(spacing: 10) {
                    AssetIcon("DesignRulerIcon", size: 24)
                    Text("Design Ruler")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Switch(isOn: isOn)
                }
                .padding(.horizontal, 14)
                .frame(height: Self.rowHeight)
                Divider().padding(.leading, 46)
                placeholderRow(barWidth: 58)
            }
            .frame(width: Self.card.width, height: Self.card.height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.07), radius: 16, y: 6)
            .position(x: Self.card.midX, y: Self.card.midY)

            // Gone once it's on, which also ends its endless nudge
            if !isOn {
                Pointer()
                    .offset(x: nudge ? 3 : 10, y: nudge ? 4 : 12)
                    .position(Self.toggleCenter)
                    .transition(.opacity)
            }
        }
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.artworkHeight)
        .animation(.easeOut(duration: 0.25), value: isOn)
        .onAppear {
            guard !reduceMotion, !isOn else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { nudge = true }
        }
    }

    private func placeholderRow(barWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 24, height: 24)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: barWidth, height: 7)
            Spacer()
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 34, height: 20)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
    }
}

/// A System Settings switch, drawn so it can't be clicked: only System Settings can turn it on.
private struct Switch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.12))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.spring(duration: 0.35, bounce: 0.3), value: isOn)
    }
}

/// The system arrow pointer, positioned by its tip (the cursor's hot spot).
private struct Pointer: View {
    var body: some View {
        let cursor = NSCursor.arrow
        Image(nsImage: cursor.image)
            .offset(x: cursor.image.size.width / 2 - cursor.hotSpot.x, y: cursor.image.size.height / 2 - cursor.hotSpot.y)
    }
}

// MARK: - Shortcuts

/// The top of a screen: the menu bar with Design Ruler's menu open, showing the shortcuts as the
/// user records them. The command whose shortcut just changed lights up.
struct MenuBarArtwork: View {
    let lastChange: (name: KeyboardShortcuts.Name, date: Date)?

    private static let screen = CGRect(x: 60, y: 60, width: 360, height: 204)
    private static let menuBarHeight: CGFloat = 24
    /// The status item's left edge, which the menu lines up with.
    private static let itemX: CGFloat = 176

    @State private var highlighted: KeyboardShortcuts.Name?

    var body: some View {
        ZStack(alignment: .topLeading) {
            menuBar
            menu
                .offset(x: Self.itemX - 5, y: Self.menuBarHeight + 3)
        }
        .frame(width: Self.screen.width, height: Self.screen.height, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
            .strokeBorder(Color.primary.opacity(0.1)))
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .position(x: Self.screen.midX, y: Self.screen.midY)
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.artworkHeight)
        .task(id: lastChange?.date) {
            guard let lastChange else { return }
            withAnimation(.easeOut(duration: 0.15)) { highlighted = lastChange.name }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.4)) { highlighted = nil }
        }
    }

    private var menuBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "apple.logo")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.55))
                .padding(.trailing, 14)
            HStack(spacing: 12) {
                ForEach([30, 22, 22, 26], id: \.self) { width in
                    Capsule().fill(Color.primary.opacity(0.1)).frame(width: CGFloat(width), height: 6)
                }
            }
            Spacer()
        }
        .padding(.leading, 14)
        .frame(width: Self.screen.width, height: Self.menuBarHeight)
        .overlay(alignment: .topLeading) {
            // Design Ruler's status item, open, then the system's own items
            HStack(spacing: 12) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .frame(width: 30, height: 20)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                ForEach([16, 16, 14], id: \.self) { width in
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.1)).frame(width: CGFloat(width), height: 10)
                }
                Text("9:41")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .frame(height: Self.menuBarHeight)
            .offset(x: Self.itemX)
        }
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            item("Measure", shortcut: .measure)
            item("Alignment Guides", shortcut: .alignmentGuides)
            Divider().padding(.horizontal, 10).padding(.vertical, 4)
            item("Settings\u{2026}", keys: "\u{2318},")
        }
        .padding(5)
        .frame(width: 172)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    private func item(_ title: String, shortcut name: KeyboardShortcuts.Name) -> some View {
        item(title, keys: KeyboardShortcuts.getShortcut(for: name)?.description ?? "", isHighlighted: highlighted == name)
    }

    private func item(_ title: String, keys: String, isHighlighted: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
        }
        .font(.system(size: 12))
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(isHighlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Shared

/// The overlay's guide colors (GuideLineStyle in DesignRulerCore).
private enum GuideColor {
    static let blue = Color(.sRGB, red: 0.3, green: 0.5, blue: 1.0)
    static let orange = Color(.sRGB, red: 1.0, green: 0.6, blue: 0.2)
}

/// A light measurement pill, as on the installer background: tabular digits, leading zeros dimmed.
private struct MeasurePill: View {
    let content: Text

    init(_ content: Text) { self.content = content }

    /// The overlay pills' font: SF Pro Semibold with tabular digits and stylistic alternates
    /// (PillRenderer.makeDesignFont in DesignRulerCore, which the app can't reach).
    private static let font: Font = {
        let tags = ["ss01", "ss02", "cv01", "cv02", "cv08", "cv12", "lnum", "tnum"]
        let features = tags.map { [kCTFontOpenTypeFeatureTag as String: $0, kCTFontOpenTypeFeatureValue as String: 1] }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: features] as CFDictionary)
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return Font(CTFontCreateCopyWithAttributes(base as CTFont, 12, nil, descriptor))
    }()

    /// `value` padded to four digits, the padding dimmed: 0192.
    static func padded(_ value: Int) -> Text {
        let digits = String(value)
        let zeros = String(repeating: "0", count: max(0, 4 - digits.count))
        return Text("\(Text(zeros).foregroundStyle(.tertiary))\(digits)")
    }

    var body: some View {
        content
            .font(Self.font)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}
