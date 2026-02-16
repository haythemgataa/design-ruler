import QuartzCore

/// Centralized design constants shared across all overlay views.
/// Caseless enum prevents instantiation — access values as `DesignTokens.Pill.height`.
enum DesignTokens {

    // MARK: - Pill layout

    enum Pill {
        static let height: CGFloat = 24
        static let cornerRadius: CGFloat = 8
        static let innerCornerRadius: CGFloat = 4
        static let sectionGap: CGFloat = 2
        static let backgroundColor: CGColor = CGColor(gray: 0, alpha: 0.8)
        static let kerning: CGFloat = -0.36
    }

    // MARK: - Shadow

    enum Shadow {
        static let color: CGColor = CGColor(gray: 0, alpha: 0.3)
        static let offset: CGSize = CGSize(width: 0, height: -1)
        static let radius: CGFloat = 3
        static let opacity: Float = 1.0
    }

    // MARK: - Colors

    enum Color {
        static let hoverRed: CGColor = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        static let hoverRedFill: CGColor = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.06)
        static let hoverRedPillBg: CGColor = CGColor(srgbRed: 0.85, green: 0.2, blue: 0.2, alpha: 0.85)
        static let removePillBg: CGColor = CGColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 0.9)
    }

    // MARK: - Animation durations (named speed tiers)

    enum Animation {
        static let fast: CFTimeInterval = 0.15
        static let standard: CFTimeInterval = 0.2
        static let slow: CFTimeInterval = 0.3
        static let collapse: CFTimeInterval = 0.35
    }
}

/// Single source of truth for Core Animation compositing filter strings.
/// Caseless enum prevents instantiation — use `BlendMode.difference`.
enum BlendMode {
    static let difference: String = "differenceBlendMode"
}
