import Foundation
import Testing
@testable import Pulse

/// A model's trend charts (`ModelSpendSummary.trend`), through the same chain
/// production uses: a reader's quarter-hour buckets and timed replies, priced
/// by `UsageLedgerReader.price`, then `ModelSpendSummary.of`.
@Suite("Model trends")
struct ModelTrendTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = Date(timeIntervalSince1970: 1_789_372_800 + 20 * 3600)
    private static let today = calendar.startOfDay(for: now)

    private static func at(daysAgo: Int, hour: Int) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)!
    }

    private static let prices: [String: ModelPrice] = [
        "alpha": ModelPrice(input: 1, output: 10, cacheRead: 0.1, cacheWrite: 1, name: "Alpha"),
    ]

    private static func ledger(
        _ entries: [(Date, TokenTally, ReplyTiming?)]
    ) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        var timings: [String: [String: ReplyTiming]] = [:]
        for (date, tally, timing) in entries {
            let key = UsageLedgerReader.slotKey(for: date, calendar: calendar)
            buckets[key, default: [:]]["alpha"] = (buckets[key]?["alpha"] ?? TokenTally()) + tally
            if let timing { timings[key, default: [:]]["alpha"] = (timings[key]?["alpha"] ?? ReplyTiming()) + timing }
        }
        return UsageLedgerReader.price(buckets, with: prices, calendar: calendar, timings: timings)
    }

    private static func summary(_ ledger: UsageLedger, overLast span: Int) -> ModelSpendSummary {
        ModelSpendSummary.of([.claudeCode: ledger], named: "Alpha", overLast: span, now: now, calendar: calendar)
    }

    /// `replies` replies of 500 tokens, 10 s each: 50 tok/s.
    private static func timed(_ replies: Int, firstToken: Double? = nil) -> ReplyTiming {
        ReplyTiming(outputTokens: 500 * replies, seconds: 10 * Double(replies), replies: replies,
                    firstTokenSeconds: (firstToken ?? 0) * Double(replies), firstTokenTurns: firstToken == nil ? 0 : replies)
    }

    @Test("A week is drawn by day: speed, first token, cache hit rate and tokens")
    func daily() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 2, hour: 9), TokenTally(input: 100, cacheRead: 300, output: 600), Self.timed(4, firstToken: 1.5)),
            (Self.at(daysAgo: 0, hour: 10), TokenTally(input: 200, cacheRead: 200, output: 100), Self.timed(1)),
        ])
        let model = Self.summary(ledger, overLast: 7)
        #expect(!model.trendIsHourly)
        #expect(model.trend.count == 7)
        let twoDaysAgo = model.trend[4]
        #expect(twoDaysAgo.tokens == 1_000)
        #expect(twoDaysAgo.cacheHitRate == 0.75)
        #expect(twoDaysAgo.tokensPerSecond == 50)
        #expect(twoDaysAgo.firstToken == 1.5)
        // One timed reply is luck, not a speed: a gap, not a zero.
        #expect(model.trend[6].tokensPerSecond == nil)
        #expect(model.trend[6].cacheHitRate == 0.5)
        // A quiet day has tokens 0 and nothing else to say.
        #expect(model.trend[5].tokens == 0)
        #expect(model.trend[5].cacheHitRate == nil)
        #expect(model.trend[5].tokensPerSecond == nil)
        // The headings: five replies over the week, and the week's cache.
        #expect(model.averageSpeed == 50)
        #expect(model.averageFirstToken == nil, "four turns are too few for the span's figure")
        #expect(model.cacheHitRate == 500.0 / 800.0)
    }

    @Test("A day is drawn by hour, up to the hour in progress")
    func hourly() {
        let ledger = Self.ledger([
            (Self.at(daysAgo: 0, hour: 3), TokenTally(input: 10, cacheRead: 30, output: 60), Self.timed(3)),
            (Self.at(daysAgo: 0, hour: 3).addingTimeInterval(15 * 60), TokenTally(input: 10, output: 10), nil),
        ])
        let model = Self.summary(ledger, overLast: 1)
        #expect(model.trendIsHourly)
        #expect(model.trend.count == Self.calendar.component(.hour, from: Self.now) + 1,
                "midnight to the hour in progress, that hour included")
        #expect(model.trend[3].tokens == 120)
        #expect(model.trend[3].cacheHitRate == 30.0 / 50.0)
        #expect(model.trend[3].tokensPerSecond == 50)
        #expect(model.trend[4].tokens == 0)
    }

    @Test("The day the clocks go back has 25 hours, and the repeated one is drawn")
    func fallBack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-11-01: clocks go back at 02:00.
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let late = calendar.date(byAdding: .hour, value: 24, to: day)!   // 23:00 local
        var buckets: [String: [String: TokenTally]] = [:]
        buckets[UsageLedgerReader.slotKey(for: late, calendar: calendar), default: [:]]["alpha"] = TokenTally(input: 7)
        let ledger = UsageLedgerReader.price(buckets, with: Self.prices, calendar: calendar)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30))!
        let model = ModelSpendSummary.of([.claudeCode: ledger], named: "Alpha",
                                         from: day, until: calendar.date(byAdding: .day, value: 1, to: day), now: now, calendar: calendar)
        #expect(model.trendIsHourly)
        #expect(model.trend.count == 25)
        #expect(model.trend.compactMap(\.tokens).reduce(0, +) == 7)
        #expect(model.trend.last?.tokens == 7)
    }
}
