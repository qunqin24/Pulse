import AppKit
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

/// A colour someone has chosen for one account's ring, stored as hex.
///
/// **The default is no colour at all**, and should stay that way. Colour on
/// these rings means how much of a limit is gone; giving a ring a fixed hue
/// takes that reading away, which is what the app is for. It was how the rings
/// worked once — each provider in its own brand colour — and it read as a
/// status it never was: Claude Code's orange-red looked like a warning at 3%
/// used. So this is an option, off unless asked for.
///
/// A spent limit still shows the spent colour whatever is chosen. Being
/// blocked is not a matter of taste.
///
/// Free rather than a fixed palette, because eight swatches is not a choice —
/// and the eight had to be legible on both the panel's black and on Liquid
/// Glass, which is a constraint on *us*, not on the person picking. Anything
/// can be chosen; `RingTint.suggestions` is only a starting point.
enum RingTint {
    /// A few that read at ring size on both surfaces, offered as a start.
    /// Not a limit — the colour well takes anything.
    static let suggestions: [Color] = [
        Color(red: 0.25, green: 0.60, blue: 1.00),
        Color(red: 0.70, green: 0.50, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.72),
        Color(red: 1.00, green: 0.56, blue: 0.20),
        Color(red: 0.20, green: 0.82, blue: 0.82),
    ]

    /// The colour a stored value means, or nil for "colour it by usage".
    ///
    /// Accepts the eight names the first version of this stored, so a choice
    /// made before it became a colour well is not silently dropped.
    static func color(from stored: String?) -> Color? {
        guard let stored, !stored.isEmpty else { return nil }
        if let named = legacy[stored] { return named }
        return Color(hex: stored)
    }

    private static let legacy: [String: Color] = [
        "blue": Color(red: 0.25, green: 0.60, blue: 1.00),
        "purple": Color(red: 0.70, green: 0.50, blue: 1.00),
        "pink": Color(red: 1.00, green: 0.44, blue: 0.72),
        "red": .pulseWarning,
        "orange": Color(red: 1.00, green: 0.56, blue: 0.20),
        "yellow": .pulseCaution,
        "green": .pulseGood,
        "teal": Color(red: 0.20, green: 0.82, blue: 0.82),
    ]
}

extension Color {
    /// "#RRGGBB", which is what a chosen colour is stored as.
    ///
    /// Converted through sRGB explicitly: a colour picked in another space
    /// answers its components in that space, and the numbers would not survive
    /// a round trip.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
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
