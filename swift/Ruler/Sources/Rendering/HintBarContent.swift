import SwiftUI

// MARK: - Observable State

final class HintBarState: ObservableObject {
    @Published var pressedKeys: Set<HintBarView.KeyID> = []
}

// MARK: - Root Content

struct HintBarContent: View {
    @ObservedObject var state: HintBarState

    var body: some View {
        VStack(spacing: -2) {
            MainHintCard(state: state)
                .zIndex(1)
            ExtraHintCard(state: state)
                .zIndex(0)
        }
        .padding(30)
    }
}

// MARK: - Main Hint Card

private struct MainHintCard: View {
    @ObservedObject var state: HintBarState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            mainText("Use")
            ArrowCluster(state: state)
            mainText("to skip an edge.")
            mainText("Plus")
            KeyCap(.shift, symbol: "\u{21E7}", width: 32, height: 20,
                   symbolFont: .system(size: 14, weight: .bold, design: .rounded),
                   symbolTracking: -0.2, align: .bottomLeading, state: state)
            mainText("to invert direction.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(nsColor: NSColor(srgbRed: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2C / 255.0, alpha: 1)) : .white)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder((colorScheme == .dark ? Color.white : Color.black).opacity(0.10), lineWidth: 1)
        )
    }

    private func mainText(_ string: String) -> Text {
        Text(string)
            .font(.system(size: 20, weight: .semibold))
            .tracking(-0.6)
            .foregroundColor(colorScheme == .dark ? .white : .black)
    }
}

// MARK: - Extra Hint Card

private struct ExtraHintCard: View {
    @ObservedObject var state: HintBarState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(.esc, symbol: "esc", width: 32, height: 20,
                   symbolFont: .system(size: 12, weight: .bold, design: .rounded),
                   symbolTracking: -0.2, align: .center, state: state)
            extraText("to exit.")
                .padding(.trailing, 4)
            KeyCap(.backspace, symbol: "\u{232B}", width: 32, height: 20,
                   symbolFont: .system(size: 14, weight: .bold, design: .rounded),
                   symbolTracking: -0.2, align: .bottomTrailing, state: state)
            extraText("to not show this hint again.")
        }
        .padding(8)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 12,
                bottomTrailingRadius: 12, topTrailingRadius: 0,
                style: .continuous
            )
            .fill(colorScheme == .dark ? Color(nsColor: NSColor(srgbRed: 0x1E / 255.0, green: 0x1E / 255.0, blue: 0x1E / 255.0, alpha: 1)) : .white)
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 12,
                bottomTrailingRadius: 12, topTrailingRadius: 0,
                style: .continuous
            )
            .strokeBorder((colorScheme == .dark ? Color.white : Color.black).opacity(0.10), lineWidth: 1)
        )
    }

    private func extraText(_ string: String) -> Text {
        Text(string)
            .font(.system(size: 14, weight: .semibold))
            .tracking(-0.42)
            .foregroundColor(colorScheme == .dark ? .white : .black)
    }
}

// MARK: - Arrow Cluster

private struct ArrowCluster: View {
    @ObservedObject var state: HintBarState

    private let capW: CGFloat = 20
    private let capH: CGFloat = 16
    private let hGap: CGFloat = 1
    private let vGap: CGFloat = 3

    var body: some View {
        let font = Font.system(size: 9, weight: .bold, design: .rounded)
        VStack(spacing: vGap) {
            KeyCap(.up, symbol: "\u{25B2}", width: capW, height: capH,
                   symbolFont: font, symbolTracking: 0, align: .center, state: state)
                .offset(y: 2)
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
    @ObservedObject var state: HintBarState
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 5
    private let borderWidth: CGFloat = 1.5
    private let shadowOffset: CGFloat = 2

    private var normalColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(srgbRed: 0x44 / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1))
            : Color(nsColor: NSColor(srgbRed: 0xDD / 255.0, green: 0xDD / 255.0, blue: 0xDD / 255.0, alpha: 1))
    }
    private var pressedColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(srgbRed: 0x2C / 255.0, green: 0x2C / 255.0, blue: 0x2C / 255.0, alpha: 1))
            : Color(nsColor: NSColor(srgbRed: 0xAA / 255.0, green: 0xAA / 255.0, blue: 0xAA / 255.0, alpha: 1))
    }

    init(_ id: HintBarView.KeyID, symbol: String, width: CGFloat, height: CGFloat,
         symbolFont: Font, symbolTracking: CGFloat, align: Align, state: HintBarState) {
        self.id = id
        self.symbol = symbol
        self.width = width
        self.height = height
        self.symbolFont = symbolFont
        self.symbolTracking = symbolTracking
        self.align = align
        self._state = ObservedObject(wrappedValue: state)
    }

    private var isPressed: Bool { state.pressedKeys.contains(id) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Shadow rect (sits at the bottom for 3D depth)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .dark ? .white : .black)
                .frame(width: width, height: height)
                .opacity(isPressed ? 0 : 1)

            // Cap (elevated when not pressed, drops down when pressed)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPressed ? pressedColor : normalColor)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? .white : .black, lineWidth: borderWidth)
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
        switch align {
        case .center:
            Text(symbol)
                .font(symbolFont)
                .tracking(symbolTracking)
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .bottomLeading:
            Text(symbol)
                .font(symbolFont)
                .tracking(symbolTracking)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 3)
                .padding(.bottom, 1)
        case .bottomTrailing:
            Text(symbol)
                .font(symbolFont)
                .tracking(symbolTracking)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 3)
                .padding(.bottom, 1)
        }
    }
}
