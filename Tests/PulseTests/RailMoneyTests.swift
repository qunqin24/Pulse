import AppKit
import Foundation
import Testing
@testable import Pulse

/// The figure a ring shows when a provider reports money instead of a
/// percentage.
///
/// The rail's label is budgeted for "100%". Money is bounded by nothing, and
/// the first version simply handed the formatted balance over: ¥5,000.00 needs
/// 64pt against a 38pt budget, and `minimumScaleFactor` gives up at 0.6, so it
/// was truncated on screen.
@Suite("Money on the rail")
struct RailMoneyTests {
    private static let english = Locale(identifier: "en_US")

    private static func text(_ amount: Double, _ currency: String = "CNY") -> String {
        ProviderUsage.CreditAmount(amount: amount, currency: currency).railText(locale: english)
    }

    @Test("Thousands and millions are abbreviated")
    func largeAmountsAreAbbreviated() {
        #expect(Self.text(9.4) == "¥9.4")
        #expect(Self.text(999) == "¥999")
        #expect(Self.text(5_000) == "¥5k")
        #expect(Self.text(12_345) == "¥12.3k")
        #expect(Self.text(123_456) == "¥123k")
        #expect(Self.text(1_234_567, "USD") == "$1.2M")
    }

    /// A balance shown as **more** than it is is the wrong way to be wrong.
    @Test("The figure is truncated, never rounded up")
    func nothingIsEverRoundedUp() {
        #expect(Self.text(9.49) == "¥9.49")
        #expect(Self.text(123.99) == "¥123")
        #expect(Self.text(12_399) == "¥12.3k")
        #expect(Self.text(1_299_999, "USD") == "$1.2M")
    }

    /// Rounding to one place turned 999,999 into "¥1,000k". Truncating settles
    /// the rollover without a special case.
    @Test("A figure just short of the next unit does not roll over")
    func theUnitDoesNotRollOverEarly() {
        #expect(Self.text(999_999) == "¥999k")
        #expect(Self.text(999.99) == "¥999")
    }

    /// The wide form disambiguates currencies that share a symbol, which is
    /// worth 45pt somewhere the currency is not already fixed by the account.
    @Test("A reader outside China sees ¥, not CN¥")
    func theSymbolIsTheNarrowOne() {
        #expect(Self.text(5_000).hasPrefix("¥"))
        #expect(!Self.text(5_000).contains("CN"))
    }

    @Test("Nothing left is nothing, not a rounding of it")
    func zeroIsZero() {
        #expect(Self.text(0) == "¥0")
    }

    /// The point of all of the above. `minimumScaleFactor` is 0.6, so anything
    /// past 63pt is cut rather than shrunk; the bound here is the rail's own
    /// thickness, which is the room a label down a side actually has.
    @MainActor
    @Test("Every figure fits the label the rail budgets for it")
    func everyFigureFits() {
        let font = NSFont.systemFont(ofSize: DockLayout.percentFontSize, weight: .medium)
        let room = DockLayout.thickness(on: .vertical)

        for amount in [0, 9.4, 99.99, 123.45, 999, 5_000, 12_345, 123_456,
                       999_999, 1_234_567, 99_999_999] as [Double] {
            for currency in ["CNY", "USD"] {
                let figure = ProviderUsage.CreditAmount(amount: amount, currency: currency)
                    .railText(locale: Self.english)
                let width = (figure as NSString).size(withAttributes: [.font: font]).width
                #expect(width <= room, "\(figure) is \(width)pt against \(room)pt")
            }
        }
    }
}
