import Foundation
import Testing
@testable import Pulse

/// DeepSeek is the first provider Pulse carries that reports **no percentage at
/// all** — a prepaid balance and nothing else. Every ring it draws therefore
/// rests on a denominator that did not come from DeepSeek, and these tests are
/// mostly about where each one did come from and what happens when there is
/// none.
@Suite("DeepSeek parsing")
struct DeepSeekParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func reply(_ name: String) throws -> DeepSeekUsageService.Reply {
        try JSONDecoder().decode(DeepSeekUsageService.Reply.self, from: try fixture(name))
    }

    private static func purse(_ name: String = "deepseek-balance", currency: String? = nil) throws
        -> DeepSeekUsageService.Purse
    {
        try #require(DeepSeekUsageService.purse(from: try reply(name), preferring: currency))
    }

    private static func windows(
        _ purse: DeepSeekUsageService.Purse,
        basis: DeepSeekBasis,
        budget: Double? = nil,
        peak: Double = 0,
        isAvailable: Bool? = true
    ) -> [UsageWindow] {
        DeepSeekUsageService.windows(
            purse: purse, basis: basis, budget: budget, peak: peak,
            since: Date(timeIntervalSince1970: 0), isAvailable: isAvailable
        )
    }

    // MARK: - The reply

    @Test("Money arrives as a string and is read as a number")
    func moneyIsParsedFromStrings() throws {
        let purse = try Self.purse()

        #expect(purse.currency == "CNY")
        #expect(purse.total == 42.30)
        #expect(purse.granted == 10)
        #expect(purse.toppedUp == 32.30)
    }

    /// The same rule the rest of this directory learned the hard way: a field
    /// that is absent has said nothing, and a balance read as zero is a full
    /// red ring and a notification announcing an account as spent.
    @Test("A money field that is absent or unreadable is absent, not zero")
    func absentMoneyIsNotZero() {
        #expect(DeepSeekUsageService.money(nil) == nil)
        #expect(DeepSeekUsageService.money("") == nil)
        #expect(DeepSeekUsageService.money("  ") == nil)
        #expect(DeepSeekUsageService.money("not a number") == nil)
        #expect(DeepSeekUsageService.money("0.00") == 0)
    }

    @Test("An entry with no total is dropped rather than counted as empty")
    func anEntryWithoutATotalIsDropped() throws {
        let reply = try JSONDecoder().decode(
            DeepSeekUsageService.Reply.self,
            from: Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY"}]}"#.utf8)
        )
        #expect(DeepSeekUsageService.purse(from: reply, preferring: nil) == nil)
    }

    // MARK: - Which currency

    /// `balance_infos` is an array and an account can hold both. ¥100 against
    /// $10 is not a comparison, so nothing here picks a "main" one by size.
    @Test("The ring follows the currency with money in it, then the user's choice")
    func currencySelection() throws {
        let held = try Self.purse("deepseek-two-currencies")
        let chosen = try Self.purse("deepseek-two-currencies", currency: "USD")
        // A choice for a currency this account does not hold is not honoured
        // over one it does.
        let absent = try Self.purse("deepseek-two-currencies", currency: "EUR")

        #expect(held.currency == "CNY")
        #expect(chosen.currency == "USD")
        #expect(absent.currency == "CNY")
    }

    // MARK: - Where the denominator comes from

    @Test("Balance only draws no ring, because nothing reported a denominator")
    func balanceOnlyDrawsNoWindow() throws {
        let purse = try Self.purse()
        #expect(Self.windows(purse, basis: .balanceOnly).isEmpty)
    }

    @Test("Since top-up measures against the highest balance Pulse has seen")
    func sinceTopUpMeasuresAgainstTheObservedPeak() throws {
        let window = try #require(
            Self.windows(try Self.purse(), basis: .sinceTopUp, peak: 100).first
        )

        #expect(abs(window.usedFraction - (100 - 42.30) / 100) < 0.000_001)
        #expect(window.percentText(remaining: false) == "58%")
        #expect(window.isEstimated)
        #expect(window.scope == "since top-up")
        // Prepaid credit does not turn over, so there is no length to divide by.
        #expect(window.reportsLength == false)
        #expect(window.resetsAt == nil)
        #expect(window.elapsedFraction(at: Date()) == nil)
    }

    /// A first run has watched nothing, so the peak is whatever is there now.
    /// 0% is then a true statement — Pulse has seen nothing spent — where a
    /// guess at what the account started with would not be.
    @Test("A peak of zero is an account with nothing to measure, and draws nothing")
    func noPeakMeansNoWindow() throws {
        let purse = try Self.purse()
        #expect(Self.windows(purse, basis: .sinceTopUp, peak: 0).isEmpty)
    }

    @Test("A budget of nothing, zero or less draws no ring rather than a full one")
    func aBudgetMustBeAFigure() throws {
        let purse = try Self.purse()
        for budget in [nil, 0, -5] as [Double?] {
            #expect(Self.windows(purse, basis: .budget, budget: budget).isEmpty,
                    "budget \(String(describing: budget))")
        }
    }

    @Test("A budget measures against the figure the reader set")
    func budgetMeasuresAgainstTheReadersFigure() throws {
        let window = try #require(
            Self.windows(try Self.purse(), basis: .budget, budget: 50).first
        )

        #expect(abs(window.usedFraction - (50 - 42.30) / 50) < 0.000_001)
        #expect(window.scope == "of your budget")
        #expect(window.isEstimated)
    }

    /// Both denominators are somebody's rather than DeepSeek's, so both rows
    /// have to say so — the same promise `--json` makes with `estimated`.
    @Test("Every ring DeepSeek draws is flagged as inferred")
    func everyWindowIsFlaggedEstimated() throws {
        let purse = try Self.purse()
        let measured = Self.windows(purse, basis: .sinceTopUp, peak: 100)
        let budgeted = Self.windows(purse, basis: .budget, budget: 50)

        #expect((measured + budgeted).count == 2)
        #expect((measured + budgeted).allSatisfy { $0.isEstimated })
    }

    // MARK: - Spent

    /// `is_available` is DeepSeek's own word for "this balance can no longer
    /// pay for a call", which is the only thing here that may set `isExhausted`.
    @Test("Spent is DeepSeek's own flag, not the arithmetic")
    func spentComesFromTheProvider() throws {
        let spent = try Self.purse("deepseek-spent")
        let window = try #require(
            Self.windows(spent, basis: .sinceTopUp, peak: 100, isAvailable: false).first
        )
        #expect(window.usedFraction == 1)
        #expect(window.isExhausted)

        // A generous budget puts the ring near the top while DeepSeek says the
        // account is perfectly able to pay. That is the reader's own line, and
        // reaching it is not the provider saying anything at all.
        let purse = try Self.purse()
        let ambitious = try #require(
            Self.windows(purse, basis: .budget, budget: 1_000, isAvailable: true).first
        )
        #expect(ambitious.usedFraction > 0.95)
        #expect(ambitious.isExhausted == false)

        // And the other way: more money than the reader calls a full tank is
        // none of it spent, not a negative fraction.
        let overfull = try #require(
            Self.windows(purse, basis: .budget, budget: 20, isAvailable: true).first
        )
        #expect(overfull.usedFraction == 0)
    }

    // MARK: - The mark

    /// The whole honesty of the default mode: the denominator is *watched*.
    @Test("A balance that rises is a top-up and resets the mark")
    func theMarkFollowsTopUps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        let first = DeepSeekBaseline.advanced(nil, seeing: 100, at: start)
        #expect(first.peak == 100)
        #expect(first.setAt == start)

        // Spending leaves the mark exactly where it was, including its date —
        // which is what the card means by "since".
        let spending = DeepSeekBaseline.advanced(first, seeing: 42.30, at: later)
        #expect(spending == first)

        // Only a rise can be a top-up, and it starts the measurement again.
        let toppedUp = DeepSeekBaseline.advanced(spending, seeing: 150, at: later)
        #expect(toppedUp.peak == 150)
        #expect(toppedUp.setAt == later)
    }

    @Test("A negative balance is not a negative denominator")
    func theMarkNeverGoesBelowZero() {
        let mark = DeepSeekBaseline.advanced(nil, seeing: -5, at: Date())
        #expect(mark.peak == 0)
        #expect(DeepSeekBaseline.usedFraction(balance: -5, peak: 0) == nil)
    }
}
