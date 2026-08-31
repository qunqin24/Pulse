import SwiftUI

extension UsageWindow {
    /// Colour for how much of a limit is gone.
    ///
    /// Rings and bars used to be drawn in each provider's brand colour, which
    /// read as a status even though it never was one: Claude Code's orange-red
    /// looked like a warning at 3% used. Colour here means one thing only —
    /// how close this limit is to running out.
    var tint: Color { UsageTint.color(for: usedFraction, isExhausted: isExhausted) }
}

enum UsageTint {
    /// Comfortable below this.
    static let cautionThreshold = 0.5
    /// Getting tight above this.
    static let warningThreshold = 0.75

    /// Spent is its own state, not just "more red". Being blocked and being
    /// nearly out call for different reactions, and at ring size a fourth hue
    /// would just read as the third — so this one is darker *and* the figure
    /// beside the ring changes colour too.
    static func color(for usedFraction: Double, isExhausted: Bool = false) -> Color {
        if isExhausted || usedFraction >= 1 { return .pulseExhausted }

        switch usedFraction {
        case ..<cautionThreshold: return .pulseGood
        case ..<warningThreshold: return .pulseCaution
        default: return .pulseWarning
        }
    }

    static func isSpent(_ window: UsageWindow?) -> Bool {
        guard let window else { return false }
        return window.isExhausted || window.usedFraction >= 1
    }
}

/// A colour someone has chosen for one account's ring.
///
/// **The default is not one of these**, and should stay that way. Colour on
/// these rings means how much of a limit is gone; giving a ring a fixed hue
/// takes that reading away, which is what the app is for. It was how the rings
/// worked once — each provider in its own brand colour — and it read as a
/// status it never was: Claude Code's orange-red looked like a warning at 3%
/// used. So this is an option, off unless asked for.
///
/// A spent limit still shows the spent colour whatever is chosen. Being
/// blocked is not a matter of taste.
///
/// A fixed set rather than a free colour well: these have to stay legible at
/// ring size on the panel's black *and* on Liquid Glass, which takes whatever
/// is behind it — a dark navy someone picked against a bright backdrop would
/// disappear against a dark one.
enum RingTint: String, CaseIterable, Identifiable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.25, green: 0.60, blue: 1.00)
        case .purple: Color(red: 0.70, green: 0.50, blue: 1.00)
        case .pink: Color(red: 1.00, green: 0.44, blue: 0.72)
        case .red: .pulseWarning
        case .orange: Color(red: 1.00, green: 0.56, blue: 0.20)
        case .yellow: .pulseCaution
        case .green: .pulseGood
        case .teal: Color(red: 0.20, green: 0.82, blue: 0.82)
        }
    }

    var title: String {
        switch self {
        case .blue: .localized("Blue")
        case .purple: .localized("Purple")
        case .pink: .localized("Pink")
        case .red: .localized("Red")
        case .orange: .localized("Orange")
        case .yellow: .localized("Yellow")
        case .green: .localized("Green")
        case .teal: .localized("Teal")
        }
    }
}

extension Color {
    /// Picked to sit on the panel's black: bright enough to read at ring size,
    /// without the neon cast that fully saturated values take on there.
    static let pulseGood = Color(red: 0.00, green: 0.90, blue: 0.55)
    static let pulseCaution = Color(red: 1.00, green: 0.76, blue: 0.15)
    static let pulseWarning = Color(red: 1.00, green: 0.31, blue: 0.26)
    /// Deeper and flatter than the warning red, so a spent limit doesn't just
    /// look like a slightly redder nearly-spent one.
    static let pulseExhausted = Color(red: 0.85, green: 0.09, blue: 0.13)
}
