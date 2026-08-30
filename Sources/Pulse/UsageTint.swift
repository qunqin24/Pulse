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
