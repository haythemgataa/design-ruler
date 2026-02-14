import SwiftUI

// MARK: - Observable State

final class HintBarState: ObservableObject {
    @Published var pressedKeys: Set<HintBarView.KeyID> = []
    @Published var isOnLightBackground: Bool = false
}

// MARK: - Root Content

struct HintBarContent: View {
    @ObservedObject var state: HintBarState

    private var isDark: Bool { !state.isOnLightBackground }

    var body: some View {
        HStack(spacing: 6) {
            text("Use")
            ArrowCluster(state: state)
            text("to skip edges, plus")
            KeyCap(.shift, symbol: "\u{21E7}", width: 40, height: 25,
                   symbolFont: .system(size: 16, weight: .bold, design: .rounded),
                   symbolTracking: -0.2, align: .bottomLeading, state: state)
            text("to reverse.")
            KeyCap(.esc, symbol: "esc", width: 32, height: 25,
                   symbolFont: .system(size: 13, weight: .bold, design: .rounded),
                   symbolTracking: -0.2, align: .center, state: state,
                   tint: escTint, tintFill: Color(nsColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.1)))
            exitText("to exit.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var escTint: Color {
        isDark
            ? Color(nsColor: NSColor(srgbRed: 0xFF / 255.0, green: 0xB2 / 255.0, blue: 0xB2 / 255.0, alpha: 1))
            : Color(nsColor: NSColor(srgbRed: 0x80 / 255.0, green: 0, blue: 0, alpha: 1))
    }

    private func text(_ string: String) -> Text {
        Text(string)
            .font(.system(size: 16, weight: .semibold))
            .tracking(-0.48)
            .foregroundColor(isDark ? .white : .black)
    }

    private func exitText(_ string: String) -> Text {
        Text(string)
            .font(.system(size: 16, weight: .semibold))
            .tracking(-0.48)
            .foregroundColor(escTint)
    }
}

// MARK: - Arrow Cluster

private struct ArrowCluster: View {
    @ObservedObject var state: HintBarState

    private let capW: CGFloat = 26
    private let capH: CGFloat = 11
    private let hGap: CGFloat = 1
    private let vGap: CGFloat = 2

    var body: some View {
        let font = Font.system(size: 7, weight: .bold, design: .rounded)
        VStack(spacing: vGap) {
            KeyCap(.up, symbol: "\u{25B2}", width: capW, height: capH,
                   symbolFont: font, symbolTracking: 0, align: .center, state: state)
                .offset(y: 1)
            HStack(spacing: hGap) {
                KeyCap(.left, symbol: "\u{25C0}\u{FE0E}", width: capW, height: capH,
                       symbolFont: font, symbolTracking: 0, align: .center, state: state)
                KeyCap(.down, symbol: "\u{25BC}", width: capW, height: capH,
                       symbolFont: font, symbolTracking: 0, align: .center, state: state)
                KeyCap(.right, symbol: "\u{25B6}\u{FE0E}", width: capW, height: capH,
                       symbolFont: font, symbolTracking: 0, align: .center, state: state)
            }
        }
    }
}

// MARK: - Key Cap

private struct KeyCap: View {
    enum Align { case center, bottomLeading, bottomTrailing }

    let id: HintBarView.KeyID
    let symbol: String
    let width: CGFloat
    let height: CGFloat
    let symbolFont: Font
    let symbolTracking: CGFloat
    let align: Align
    let tint: Color?
    let tintFill: Color?
    @ObservedObject var state: HintBarState

    private let cornerRadius: CGFloat = 5
    private let borderWidth: CGFloat = 1.5
    private let shadowOffset: CGFloat = 2

    private var isDark: Bool { !state.isOnLightBackground }

    private var normalColor: Color {
        isDark
            ? Color(nsColor: NSColor(srgbRed: 0x44 / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1))
            : Color(nsColor: NSColor(srgbRed: 0xDD / 255.0, green: 0xDD / 255.0, blue: 0xDD / 255.0, alpha: 1))
    }
    private var pressedColor: Color {
        isDark
            ? Color(nsColor: NSColor(srgbRed: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2C / 255.0, alpha: 1))
            : Color(nsColor: NSColor(srgbRed: 0xAA / 255.0, green: 0xAA / 255.0, blue: 0xAA / 255.0, alpha: 1))
    }

    private var accentColor: Color { tint ?? (isDark ? .white : .black) }

    init(_ id: HintBarView.KeyID, symbol: String, width: CGFloat, height: CGFloat,
         symbolFont: Font, symbolTracking: CGFloat, align: Align, state: HintBarState,
         tint: Color? = nil, tintFill: Color? = nil) {
        self.id = id
        self.symbol = symbol
        self.width = width
        self.height = height
        self.symbolFont = symbolFont
        self.symbolTracking = symbolTracking
        self.align = align
        self.tint = tint
        self.tintFill = tintFill
        self._state = ObservedObject(wrappedValue: state)
    }

    private var isPressed: Bool { state.pressedKeys.contains(id) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Shadow rect (sits at the bottom for 3D depth)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accentColor)
                .frame(width: width, height: height)
                .opacity(isPressed ? 0 : 1)

            // Cap (elevated when not pressed, drops down when pressed)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPressed ? pressedColor : normalColor)
                if let tintFill {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tintFill)
                }
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(accentColor, lineWidth: borderWidth)
                capLabel
            }
            .frame(width: width, height: height)
            .offset(y: isPressed ? 0 : -shadowOffset)
        }
        .frame(width: width, height: height + shadowOffset)
        .animation(.easeOut(duration: 0.06), value: isPressed)
    }

    @ViewBuilder
    private var capLabel: some View {
        let label = Text(symbol)
            .font(symbolFont)
            .tracking(symbolTracking)
            .foregroundColor(accentColor)

        switch align {
        case .center:
            label
        case .bottomLeading:
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 3)
                .padding(.bottom, 1)
        case .bottomTrailing:
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 3)
                .padding(.bottom, 1)
        }
    }
}
