import SwiftUI
import Testing
@testable import Pulse

/// Where the three usage colours change over.
///
/// The warning step is a setting now, so the thing worth pinning is that
/// moving it moves *only* that step: green and spent do not follow it around,
/// and every offered figure stays above the caution step it bounds.
@Suite("Usage tint")
// On the main actor: resolving a colour backed by an `NSColor` provider makes
// SwiftUI sync onto the main thread, and two tests doing that at once from the
// cooperative pool deadlocked the whole run (sampled on 2026-10-09: both
// threads in `Update.syncMain`, the main thread idle in its run loop).
@MainActor
struct UsageTintTests {
    private static func colour(_ used: Double, warningAt: WarningThreshold, spent: Bool = false) -> Color {
        UsageTint.color(for: used, isExhausted: spent, warningAt: warningAt.fraction)
    }

    @Test("the warning step is where the setting puts it")
    func warningFollowsTheSetting() {
        #expect(Self.colour(0.76, warningAt: .seventyFive) == .pulseWarning)
        #expect(Self.colour(0.76, warningAt: .eighty) == .pulseCaution)
        #expect(Self.colour(0.86, warningAt: .eightyFive) == .pulseWarning)
        #expect(Self.colour(0.61, warningAt: .sixty) == .pulseWarning)
    }

    @Test("red starts at the selected threshold, not one step after it")
    func warningBoundary() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(threshold.fraction.nextDown, warningAt: threshold) == .pulseCaution)
            #expect(Self.colour(threshold.fraction, warningAt: threshold) == .pulseWarning)
        }
    }

    @Test("the caution step does not move with it")
    func cautionStaysPut() {
        for threshold in WarningThreshold.allCases {
            #expect(Self.colour(0.49, warningAt: threshold) == .pulseGood)
            #expect(Self.colour(0.5, warningAt: threshold) == .pulseCaution)
        }
    }

    @Test("every offered figure sits above the caution step")
    func optionsClearCaution() {
        for threshold in WarningThreshold.allCases {
            #expect(threshold.fraction > UsageTint.cautionThreshold)
        }
    }

    @Test("spent is not a matter of where red begins")
    func spentIgnoresTheSetting() {
        #expect(Self.colour(0.1, warningAt: .ninety, spent: true) == .pulseExhausted)
        #expect(Self.colour(1, warningAt: .ninety) == .pulseExhausted)
    }

    @Test("the shipped default is the figure it always was")
    func defaultIsUnchanged() {
        #expect(UsageTint.warningThreshold == 0.75)
        #expect(WarningThreshold.default == .seventyFive)
    }

    // MARK: Light panel (#74)

    private static func resolved(_ colour: Color, _ scheme: ColorScheme) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return colour.resolve(in: environment)
    }

    private static func luminance(_ colour: Color.Resolved) -> Double {
        func linear(_ value: Float) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }

    @Test("the panel's own scheme picks the twin, not the system's")
    func usageColoursFollowTheScheme() {
        for colour in [Color.pulseGood, .pulseCaution, .pulseWarning, .pulseExhausted] {
            #expect(Self.resolved(colour, .light) != Self.resolved(colour, .dark))
        }
        let good = Self.resolved(.pulseGood, .dark)
        #expect(abs(good.red - 0) < 0.01 && abs(good.green - 0.90) < 0.01 && abs(good.blue - 0.55) < 0.01)
    }

    @Test("every usage colour reads on the light surface")
    func lightTwinsHaveContrast() {
        let surface = Self.luminance(Self.resolved(PanelLight.fill, .light))
        for colour in [Color.pulseGood, .pulseCaution, .pulseWarning, .pulseExhausted] {
            let ratio = (surface + 0.05) / (Self.luminance(Self.resolved(colour, .light)) + 0.05)
            #expect(ratio >= 3, "\(colour) is \(ratio):1 on the light panel")
        }
    }
}
