import Foundation
import Testing
@testable import Pulse

/// The recap's numbers, from synthetic ledgers priced through the production
/// chain (`UsageLedgerReader.price`, the path every reader prices with), on a
/// fixed clock and a UTC calendar.
@Suite("Recap")
struct RecapTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Rates in dollars per million tokens, chosen so each kind is visible.
    private static let prices: [String: ModelPrice] = [
        "claude": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, name: "Claude"),
        "gpt": ModelPrice(input: 2, output: 8, cacheRead: 0.5, cacheWrite: nil, name: "GPT"),
        // States no cache rate: reads are billed as input, which saves nothing.
        "flat": ModelPrice(input: 1, output: 2, cacheRead: nil, cacheWrite: nil, name: "Flat"),
        "tiered": ModelPrice(
            input: 3, output: 15, cacheRead: 0.3, cacheWrite: nil, name: "Tiered",
            tiers: [.init(threshold: 200_000, input: 6, output: 22.5, cacheRead: 0.6, cacheWrite: nil)]
        ),
    ]

    private struct Event {
        let at: Date
        let model: String
        let tally: TokenTally
    }

    private static func event(_ at: Date, _ tokens: Int, model: String = "claude") -> Event {
        Event(at: at, model: model, tally: TokenTally(input: tokens))
    }

    /// The production chain: quarter-hour buckets → priced ledger.
    private static func ledger(_ events: [Event], prices: [String: ModelPrice]? = nil) -> UsageLedger {
        var buckets: [String: [String: TokenTally]] = [:]
        for event in events {
            let key = UsageLedgerReader.slotKey(for: event.at, calendar: calendar)
            buckets[key, default: [:]][event.model] = (buckets[key]?[event.model] ?? TokenTally()) + event.tally
        }
        return UsageLedgerReader.price(buckets, with: prices ?? Self.prices, calendar: calendar)
    }

    private static func build(
        _ period: Recap.Period,
        _ ledgers: [SpendAgent: UsageLedger],
        now: Date = at(2026, 10, 5),
        prices: [String: ModelPrice]? = nil
    ) -> Recap {
        Recap.build(period, from: ledgers, prices: prices ?? Self.prices, now: now, calendar: calendar)!
    }

    private static func october(_ events: [Event], now: Date = at(2026, 10, 5)) -> Recap {
        build(.month(year: 2026, month: 10), [.claudeCode: ledger(events)], now: now)
    }

    private static func slot(_ at: Date, _ tokens: Int) -> UsageLedger.Slot {
        UsageLedger.Slot(start: at, tokens: tokens, cost: 0)
    }

    private static func session(
        _ id: String, project: String?, from start: Date, to end: Date, slots: [UsageLedger.Slot]
    ) -> UsageLedger.Session {
        UsageLedger.Session(
            id: id, name: id, title: nil, project: UsageProject(project), start: start, end: end,
            tokens: slots.reduce(0) { $0 + $1.tokens }, cost: 0, slots: slots
        )
    }

    // MARK: - Bounds

    @Test("A month holds its first and last day and nothing from either neighbour")
    func monthBounds() throws {
        let recap = Self.october([
            Self.event(Self.at(2026, 9, 30, 23, 45), 1_000),
            Self.event(Self.at(2026, 10, 1, 0, 0), 100),
            Self.event(Self.at(2026, 10, 31, 23, 45), 100),
            Self.event(Self.at(2026, 11, 1, 0, 0), 1_000),
        ], now: Self.at(2026, 12, 1))

        #expect(recap.tokens == 200)
        #expect(recap.days.count == 31)
        #expect(recap.start == Self.at(2026, 10, 1, 0))
        #expect(recap.end == Self.at(2026, 11, 1, 0))
        #expect(!recap.isInProgress)
        #expect(recap.days.first?.tokens == 100)
        #expect(recap.days.last?.tokens == 100)
        // The quarter-hours at either edge are not in the hours, nor in the
        // nights: the neighbours' midnights are not this month's.
        #expect(recap.hours?.reduce(0, +) == 200)
        #expect(recap.hours?[0] == 100)
        #expect(recap.hours?[23] == 100)
        #expect(recap.lateNights == 1)
    }

    @Test("A period running ends at the end of today, and its months are not yet drawn")
    func inProgress() {
        let recap = Self.october([Self.event(Self.at(2026, 10, 2), 100), Self.event(Self.at(2026, 10, 5, 9), 50)])
        #expect(recap.isInProgress)
        #expect(recap.end == Self.at(2026, 10, 6, 0))
        #expect(recap.elapsedDays == 5)
        #expect(recap.days.count == 5)
        #expect(recap.activeDays == 2)
        #expect(recap.months.isEmpty)
    }

    @Test("A period that has not started is empty, and a month outside 1...12 is no period")
    func futureAndInvalid() {
        let future = Self.build(.month(year: 2026, month: 12), [.claudeCode: Self.ledger([Self.event(Self.at(2026, 10, 2), 100)])])
        #expect(future.isEmpty)
        #expect(future.days.isEmpty)
        #expect(!future.isInProgress)
        #expect(future.previousTokens == nil)
        #expect(Recap.build(.month(year: 2026, month: 13), from: [:], prices: [:], now: Self.at(2026, 10, 5), calendar: Self.calendar) == nil)
        #expect(Recap.build(.month(year: 2026, month: 0), from: [:], prices: [:], now: Self.at(2026, 10, 5), calendar: Self.calendar) == nil)
    }

    @Test("The span form of SpendSummary cuts a session at both edges")
    func boundedSummaryCutsSessions() {
        var ledger = Self.ledger([
            Self.event(Self.at(2026, 10, 31, 23, 45), 100),
            Self.event(Self.at(2026, 11, 1, 0, 15), 300),
        ])
        ledger.sessions = [Self.session(
            "s", project: "/w/pulse", from: Self.at(2026, 10, 31, 23, 40), to: Self.at(2026, 11, 1, 0, 20),
            slots: [Self.slot(Self.at(2026, 10, 31, 23, 45), 100), Self.slot(Self.at(2026, 11, 1, 0, 15), 300)]
        )]
        let summary = SpendSummary.of(
            [.claudeCode: ledger], from: Self.at(2026, 10, 1, 0), until: Self.at(2026, 11, 1, 0),
            now: Self.at(2026, 12, 1), calendar: Self.calendar
        )
        #expect(summary.tokens == 100)
        #expect(summary.sessions.map(\.session.tokens) == [100])
        #expect(summary.projects.map(\.tokens) == [100])
        #expect(summary.days.count == 31)
        #expect(summary.hours.values.reduce(0, +) == 100)
        // An end not after the start is no days at all.
        let none = SpendSummary.of(
            [.claudeCode: ledger], from: Self.at(2026, 11, 1, 0), until: Self.at(2026, 11, 1, 0),
            now: Self.at(2026, 12, 1), calendar: Self.calendar
        )
        #expect(none.days.isEmpty)
        #expect(none.tokens == 0)
    }

    // MARK: - The previous period

    @Test("A month in progress is set against the same days of the month before")
    func previousIsAlignedToDate() {
        let recap = Self.october([
            Self.event(Self.at(2026, 10, 1), 100),
            Self.event(Self.at(2026, 9, 1), 40),
            Self.event(Self.at(2026, 9, 5, 23, 45), 10),
            // Sept 6 is not in "October 1–5 against September 1–5".
            Self.event(Self.at(2026, 9, 6), 5_000),
        ])
        #expect(recap.previousTokens == 50)
    }

    @Test("A finished month is set against the whole month before, clamped to its length")
    func previousIsClampedToItsLength() {
        // March has 31 days and February 28: 31 days after Feb 1 is March 4,
        // which is not February's.
        let events = [
            Self.event(Self.at(2026, 3, 31), 100),
            Self.event(Self.at(2026, 2, 28), 20),
            Self.event(Self.at(2026, 3, 1), 7_000),
        ]
        let recap = Self.build(.month(year: 2026, month: 3), [.claudeCode: Self.ledger(events)], now: Self.at(2026, 4, 10))
        #expect(recap.previousTokens == 20)
    }

    @Test("January's previous month is last December, to the same date")
    func previousWrapsTheYear() {
        let recap = Self.build(
            .month(year: 2026, month: 1),
            [.claudeCode: Self.ledger([
                Self.event(Self.at(2025, 12, 15), 30), Self.event(Self.at(2025, 12, 31), 900), Self.event(Self.at(2026, 1, 3), 10),
            ])],
            now: Self.at(2026, 1, 20)
        )
        #expect(recap.previousTokens == 30)
    }

    @Test("A previous period with nothing recorded is nil, not zero")
    func noPrevious() {
        let recap = Self.october([Self.event(Self.at(2026, 10, 2), 100), Self.event(Self.at(2026, 8, 2), 100)])
        #expect(recap.previousTokens == nil)
    }

    // MARK: - A year

    @Test("A year has twelve months, the days it has had, and last year's same days")
    func year() {
        let ledger = Self.ledger([
            Self.event(Self.at(2026, 1, 15), 100),
            Self.event(Self.at(2026, 3, 1), 200),
            Self.event(Self.at(2026, 3, 2), 300),
            Self.event(Self.at(2026, 10, 3), 400),
            Self.event(Self.at(2025, 1, 1), 50),
            Self.event(Self.at(2025, 10, 5), 100),
            // The day after the same 278 days.
            Self.event(Self.at(2025, 10, 6), 9_000),
        ])
        let recap = Self.build(.year(2026), [.claudeCode: ledger])
        #expect(recap.months.map(\.month) == Array(1...12))
        #expect(recap.months.map(\.tokens) == [100, 0, 500, 0, 0, 0, 0, 0, 0, 400, 0, 0])
        #expect(recap.months[2].activeDays == 2)
        // Quiet months have no money, not $0.
        #expect(recap.months[1].cost == nil)
        #expect(recap.months[2].cost != nil)
        #expect(recap.days.count == 278)
        #expect(recap.elapsedDays == 278)
        #expect(recap.isInProgress)
        #expect(recap.previousTokens == 150)
        #expect(recap.tokens == 1_000)
    }

    @Test("A finished year runs to its last day")
    func finishedYear() {
        let recap = Self.build(.year(2025), [.claudeCode: Self.ledger([Self.event(Self.at(2025, 12, 31), 10)])], now: Self.at(2026, 10, 5))
        #expect(recap.days.count == 365)
        #expect(!recap.isInProgress)
        #expect(recap.end == Self.at(2026, 1, 1, 0))
        #expect(recap.months[11].tokens == 10)
    }

    // MARK: - What is missing is nil

    @Test("Nothing priced means no money, and no cache saving")
    func unpriced() {
        let ledger = Self.ledger(
            [Event(at: Self.at(2026, 10, 2), model: "mystery", tally: TokenTally(input: 100, cacheRead: 900))]
        )
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        #expect(recap.tokens == 1_000)
        #expect(recap.cost == nil)
        #expect(recap.cacheSavings == nil)
        #expect(recap.days.first { $0.tokens > 0 }?.cost == nil)
        #expect(recap.models.map(\.cost) == [nil])
        // The cache hit rate does not need a price.
        #expect(recap.cacheHitRate == 0.9)
    }

    @Test("A part-priced total is its priced subtotal")
    func partPriced() {
        let ledger = Self.ledger([
            Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 1_000_000)),
            Event(at: Self.at(2026, 10, 2), model: "mystery", tally: TokenTally(input: 500)),
        ])
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        #expect(recap.cost == 3)
        #expect(Dictionary(uniqueKeysWithValues: recap.models.map { ($0.name, $0.cost) })["Claude"] == 3)
        #expect(Dictionary(uniqueKeysWithValues: recap.models.map { ($0.name, $0.cost) })["mystery"] == .some(nil))
    }

    @Test("Aggregate timing withholds every hour figure")
    func aggregateTiming() {
        var ledger = Self.ledger([Self.event(Self.at(2026, 10, 2, 23), 100)])
        ledger.hasAggregateTiming = true
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        #expect(recap.tokens == 100)
        #expect(recap.hours == nil)
        #expect(recap.peakHour == nil)
        #expect(recap.lateShare == nil)
        #expect(recap.persona == nil)
    }

    @Test("A tool without a time of day is left out of the hours alone, and counted")
    func aggregateTimingBesideTimedWork() throws {
        var untimed = Self.ledger([Self.event(Self.at(2026, 10, 2, 23), 10)])
        untimed.hasAggregateTiming = true
        let timed = Self.ledger([Self.event(Self.at(2026, 10, 2, 14), 990)])
        let recap = Self.build(.month(year: 2026, month: 10), [.zed: untimed, .claudeCode: timed])
        let hours = try #require(recap.hours)
        #expect(hours[14] == 990)
        #expect(hours[23] == 0, "the untimed tool's invented hour is not drawn")
        #expect(recap.untimedTokens == 10)
        #expect(recap.peakHour == 14)
        #expect(recap.persona == .dayShift)
        #expect(RecapDeck(recap: recap, monthlyPrice: nil, hidesProjects: false).hoursNote != nil)
    }

    @Test("A ledger with no quarter-hours has no hour shape to invent")
    func noSlots() {
        let day = LedgerDay(date: Self.at(2026, 10, 2, 0), tokens: 100, cost: 1, unpricedTokens: 0, models: ["claude": 100])
        let ledger = UsageLedger(days: [day], earliest: day.date, unpricedModels: [], modelNames: [:], slots: [])
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        #expect(recap.tokens == 100)
        #expect(recap.hours == nil)
        #expect(recap.persona == nil)
    }

    @Test("An empty month is empty, with nothing to rank and nothing invented")
    func empty() {
        let recap = Self.october([])
        #expect(recap.isEmpty)
        #expect(recap.cost == nil)
        #expect(recap.hours == nil)
        #expect(recap.persona == nil)
        #expect(recap.busiestDay == nil)
        #expect(recap.cacheHitRate == nil)
        #expect(recap.cacheSavings == nil)
        #expect(recap.models.isEmpty && recap.agents.isEmpty && recap.projects.isEmpty)
        #expect(recap.days.count == 5)
        #expect(recap.latestMinute == nil)
        #expect(recap.lateNights == 0)
    }

    @Test("A provider's own statistics are not part of a recap")
    func providerStatisticsAreLeftOut() {
        var statistics = Self.ledger([Self.event(Self.at(2026, 10, 2), 9_000)])
        statistics.origin = .providerStatistics
        let recap = Self.build(
            .month(year: 2026, month: 10),
            [.claudeCode: Self.ledger([Self.event(Self.at(2026, 10, 2), 100)]), .openCode: statistics]
        )
        #expect(recap.tokens == 100)
        #expect(recap.agents.map(\.agent) == [.claudeCode])
    }

    // MARK: - Time of day

    @Test("Hours, the peak and the late share come from the quarter-hours")
    func hours() throws {
        let recap = Self.october([
            Self.event(Self.at(2026, 10, 2, 22, 30), 300),
            Self.event(Self.at(2026, 10, 2, 22, 45), 100),
            Self.event(Self.at(2026, 10, 3, 3), 100),
            Self.event(Self.at(2026, 10, 3, 14), 500),
        ])
        let hours = try #require(recap.hours)
        #expect(hours.count == 24)
        #expect(hours[22] == 400)
        #expect(hours[3] == 100)
        #expect(hours[14] == 500)
        #expect(recap.peakHour == 14)
        #expect(try abs(#require(recap.lateShare) - 0.5) < 0.0001)
    }

    @Test("The busiest four hours are read off the work, not a fixed band")
    func busiestHoursFollowTheWork() throws {
        // The same 22:00 / 03:00 / 14:00 day as above. Any four hours that
        // take in 14:00 hold 500 of 1,000, more than the 400 around 22:00;
        // the earliest of those starts is 11:00.
        let recap = Self.october([
            Self.event(Self.at(2026, 10, 2, 22, 30), 300),
            Self.event(Self.at(2026, 10, 2, 22, 45), 100),
            Self.event(Self.at(2026, 10, 3, 3), 100),
            Self.event(Self.at(2026, 10, 3, 14), 500),
        ])
        let window = try #require(recap.busiestHours)
        #expect(window.start == 11)
        #expect(window.end == 15)
        #expect(abs(window.share - 0.5) < 0.0001)

        var daytime = Array(repeating: 0, count: 24)
        daytime[10] = 30; daytime[11] = 40; daytime[12] = 20; daytime[13] = 10; daytime[23] = 25
        let day = try #require(Recap.busiestHours(in: daytime))
        #expect(day.start == 10 && day.end == 14)
        #expect(abs(day.share - 100.0 / 125.0) < 0.0001)
        #expect(day.contains(10) && day.contains(13) && !day.contains(14) && !day.contains(9))
    }

    @Test("A window across midnight wraps, and a tie is the earliest start")
    func busiestHoursWrapAndTie() throws {
        var night = Array(repeating: 0, count: 24)
        night[22] = 10; night[23] = 10; night[0] = 10; night[1] = 10; night[12] = 5
        let window = try #require(Recap.busiestHours(in: night))
        #expect(window.start == 22 && window.end == 2)
        #expect(window.contains(23) && window.contains(1) && !window.contains(2) && !window.contains(21))

        var even = Array(repeating: 0, count: 24)
        even[3] = 1; even[15] = 1
        #expect(Recap.busiestHours(in: even)?.start == 0)

        #expect(Recap.busiestHours(in: Array(repeating: 0, count: 24)) == nil)
        #expect(Recap.busiestHours(in: [1, 2, 3]) == nil)
    }

    @Test("A year whose records begin in May counts from May, not January")
    func recordsBeginInsideTheYear() throws {
        let recap = Self.build(
            .year(2026),
            [.claudeCode: Self.ledger([
                Self.event(Self.at(2026, 5, 14), 100),
                Self.event(Self.at(2026, 9, 2), 300),
            ])],
            now: Self.at(2026, 10, 9)
        )
        let begin = try #require(recap.recordsBegin)
        #expect(begin == Self.calendar.startOfDay(for: Self.at(2026, 5, 14)))
        // January 1 to October 9 has been 282 days; May 14 to October 9, 149.
        #expect(recap.elapsedDays == 282)
        #expect(recap.observedDays == 149)
        #expect(recap.isBeforeRecords(Self.at(2026, 5, 13)))
        #expect(!recap.isBeforeRecords(Self.at(2026, 5, 14, 0)))

        let insights = RecapInsights(recap)
        #expect((0..<4).allSatisfy(insights.isMonthBeforeRecords))
        #expect(!insights.isMonthBeforeRecords(4), "May holds the first record")
        #expect(insights.isMonthUnrecorded(11), "December is still to come")
        let split = try #require(insights.workSplit)
        #expect(split.weekdayDays + split.weekendDays == 149)

        // The plan price runs from the first record too.
        #expect(abs(RecapDeck.paidMonths(recap) - 12.0 * 149.0 / 365.0) < 1e-9)
    }

    @Test("Records reaching back before the period leave it whole")
    func recordsBeforeThePeriod() {
        let recap = Self.october([
            Self.event(Self.at(2026, 9, 20), 100),
            Self.event(Self.at(2026, 10, 2), 100),
        ])
        #expect(recap.recordsBegin == nil)
        #expect(recap.observedDays == recap.elapsedDays)
    }

    @Test("A tie for the peak is the earlier hour, every time")
    func peakTie() {
        let recap = Self.october([Self.event(Self.at(2026, 10, 2, 16), 100), Self.event(Self.at(2026, 10, 2, 9), 100)])
        #expect(recap.peakHour == 9)
    }

    @Test("Work running past midnight, or begun before 05:00, is a late night, once")
    func lateNights() {
        var ledger = Self.ledger([
            // A night spent across midnight: the session started the evening before.
            Self.event(Self.at(2026, 10, 2, 23, 30), 100),
            Self.event(Self.at(2026, 10, 3, 1, 0), 100),
            Self.event(Self.at(2026, 10, 3, 1, 15), 100),
            // A second night, as late as 04:58.
            Self.event(Self.at(2026, 10, 4, 4, 45), 100),
            // 05:00 is the morning.
            Self.event(Self.at(2026, 10, 5, 5, 0), 100),
        ])
        ledger.sessions = [
            Self.session(
                "a", project: nil, from: Self.at(2026, 10, 2, 23, 20), to: Self.at(2026, 10, 3, 1, 22),
                slots: [Self.slot(Self.at(2026, 10, 2, 23, 30), 100), Self.slot(Self.at(2026, 10, 3, 1, 0), 100), Self.slot(Self.at(2026, 10, 3, 1, 15), 100)]
            ),
            Self.session(
                "b", project: nil, from: Self.at(2026, 10, 4, 4, 40), to: Self.at(2026, 10, 4, 4, 58),
                slots: [Self.slot(Self.at(2026, 10, 4, 4, 45), 100)]
            ),
        ]
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        // Both nights: 04:40–04:58 began before 05:00, so it is the night of
        // October 3. 05:00 on the 5th is that morning's.
        #expect(recap.lateNights == 2)
        // 04:58, from the session's own last record rather than its quarter-hour.
        #expect(recap.latestMinute == 24 * 60 + 4 * 60 + 58)

        // Without the session's end it is the quarter-hour's start.
        var bare = ledger
        bare.sessions = []
        #expect(Self.build(.month(year: 2026, month: 10), [.claudeCode: bare]).latestMinute == 24 * 60 + 4 * 60 + 45)
    }

    @Test("An all-nighter finishes when it stopped, and an evening that ends before midnight still has a finish")
    func latestFinishIsNotCapped() {
        let allNight = Self.october([
            Self.event(Self.at(2026, 10, 2, 22), 100),
            Self.event(Self.at(2026, 10, 3, 1), 100),
            Self.event(Self.at(2026, 10, 3, 4), 100),
            Self.event(Self.at(2026, 10, 3, 6, 45), 100),
        ])
        #expect(allNight.latestMinute == 24 * 60 + 6 * 60 + 45)
        #expect(allNight.lateNights == 1)

        let early = Self.october([Self.event(Self.at(2026, 10, 2, 9), 100), Self.event(Self.at(2026, 10, 2, 23, 30), 100)])
        // Two stretches (a gap over three hours); the later ends at 23:30.
        #expect(early.latestMinute == 23 * 60 + 30)
        #expect(early.lateNights == 0)
    }

    @Test("No work over midnight is no late night, and the evening still has its finish")
    func noLateNight() {
        let recap = Self.october([Self.event(Self.at(2026, 10, 2, 22), 100), Self.event(Self.at(2026, 10, 3, 5, 0), 100)])
        // Seven quiet hours between them: two stretches, neither over midnight.
        #expect(recap.lateNights == 0)
        #expect(recap.latestMinute == 22 * 60)
    }

    // MARK: - Persona

    @Test("A persona is a plain majority of the tokens in a band, and not half of them")
    func personaThresholds() {
        func shape(_ fill: [(Int, Int)]) -> [Int] {
            var hours = Array(repeating: 0, count: 24)
            for (hour, tokens) in fill { hours[hour] += tokens }
            return hours
        }
        // 21:00-04:59.
        #expect(Recap.Persona.of(hours: shape([(23, 51), (14, 49)])) == .nightOwl)
        #expect(Recap.Persona.of(hours: shape([(2, 51), (14, 49)])) == .nightOwl)
        // Exactly half is not a majority.
        #expect(Recap.Persona.of(hours: shape([(23, 50), (14, 50)])) == .allDay)
        // The band ends are 21:00 in, 20:59 out; 04:59 in, 05:00 out.
        #expect(Recap.Persona.of(hours: shape([(21, 60), (12, 40)])) == .nightOwl)
        #expect(Recap.Persona.of(hours: shape([(20, 60), (12, 40)])) == .allDay)
        #expect(Recap.Persona.of(hours: shape([(4, 60), (12, 40)])) == .nightOwl)
        #expect(Recap.Persona.of(hours: shape([(5, 60), (12, 40)])) == .earlyBird)
        // 05:00-09:59.
        #expect(Recap.Persona.of(hours: shape([(9, 51), (14, 49)])) == .earlyBird)
        #expect(Recap.Persona.of(hours: shape([(10, 60), (20, 40)])) == .dayShift)
        // 10:00-17:59.
        #expect(Recap.Persona.of(hours: shape([(17, 51), (20, 49)])) == .dayShift)
        #expect(Recap.Persona.of(hours: shape([(18, 60), (12, 40)])) == .allDay)
        // Spread out.
        #expect(Recap.Persona.of(hours: shape([(7, 30), (13, 30), (19, 20), (23, 20)])) == .allDay)
        // Nothing to read.
        #expect(Recap.Persona.of(hours: Array(repeating: 0, count: 24)) == nil)
        #expect(Recap.Persona.of(hours: [1, 2, 3]) == nil)
    }

    @Test("The persona comes through the build")
    func personaFromLedgers() {
        let owl = Self.october([Self.event(Self.at(2026, 10, 2, 23), 100), Self.event(Self.at(2026, 10, 3, 1), 100), Self.event(Self.at(2026, 10, 3, 11), 100)])
        #expect(owl.persona == .nightOwl)
        let day = Self.october([Self.event(Self.at(2026, 10, 2, 11), 100)])
        #expect(day.persona == .dayShift)
    }

    // MARK: - Cache

    @Test("Cache savings are cache reads at the input rate, less what they cost")
    func cacheSavings() throws {
        let claude = Self.ledger([
            // 2M reads at $3 - $0.30 per million = $5.40.
            Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 1_000, cacheRead: 2_000_000)),
            // No cache rate stated: billed as input, nothing saved.
            Event(at: Self.at(2026, 10, 2), model: "flat", tally: TokenTally(cacheRead: 1_000_000)),
            // No price at all: not guessed.
            Event(at: Self.at(2026, 10, 2), model: "mystery", tally: TokenTally(cacheRead: 5_000_000)),
        ])
        let codex = Self.ledger([
            // 1M reads at $2 - $0.50 = $1.50.
            Event(at: Self.at(2026, 10, 3), model: "gpt", tally: TokenTally(input: 10, cacheRead: 1_000_000)),
        ])
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: claude, .codex: codex])
        #expect(try abs(#require(recap.cacheSavings) - 6.9) < 0.000001)
    }

    @Test("A long-context request's reads are saved at its tier's rates")
    func cacheSavingsAtATier() throws {
        // One request over 272K, one under: the first is billed at the tier
        // ($6 input, $0.60 cache read), the second at the base rates.
        let big = TokenTally(cacheRead: 1_000_000).request(context: 1_000_000)
        let small = TokenTally(cacheRead: 1_000_000)
        let ledger = Self.ledger([Event(at: Self.at(2026, 10, 2), model: "tiered", tally: big + small)])
        let recap = Self.build(.month(year: 2026, month: 10), [.codex: ledger])
        // 1M x (6 - 0.6) + 1M x (3 - 0.3) per million.
        #expect(try abs(#require(recap.cacheSavings) - 8.1) < 0.000001)
        // And it is exactly what the ledger charged for those reads.
        let charged = try #require(ledger.days.first { $0.tokens > 0 }?.modelCosts["tiered"]).cacheRead
        #expect(abs(charged - (0.6 + 0.3)) < 0.000001)
    }

    @Test("No cache reads, no savings figure")
    func noCacheReads() {
        let recap = Self.october([Self.event(Self.at(2026, 10, 2), 1_000)])
        #expect(recap.cacheSavings == nil)
        #expect(recap.cacheHitRate == 0)
    }

    @Test("The hit rate is the Token spend rule: reads over all input, output left out")
    func cacheHitRate() throws {
        let events = [
            Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 100, cacheWrite: 100, cacheRead: 600, output: 5_000)),
            Event(at: Self.at(2026, 10, 3), model: "claude", tally: TokenTally(input: 50, cacheWrite: 50, cacheRead: 100)),
        ]
        let ledger = Self.ledger(events)
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: ledger])
        let rate = try #require(recap.cacheHitRate)
        #expect(abs(rate - 0.7) < 0.0001)
        let own = try #require(ledger.cacheHitRate(overLast: 400))
        #expect(abs(rate - own) < 0.0001)
    }

    @Test("A hit rate over several agents adds the measured tallies, and leaves out an agent that records no cache")
    func cacheHitRateAcrossAgents() throws {
        let claude = Self.ledger([Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 100, cacheRead: 100))])
        let codex = Self.ledger([Event(at: Self.at(2026, 10, 2), model: "gpt", tally: TokenTally(input: 100, cacheRead: 700))])
        // Goose keeps no cache column: its 1,000 of input is not 1,000 misses.
        let goose = Self.ledger([Event(at: Self.at(2026, 10, 2), model: "gpt", tally: TokenTally(input: 1_000))])
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: claude, .codex: codex, .goose: goose])
        #expect(try abs(#require(recap.cacheHitRate) - 0.8) < 0.0001)
        #expect(recap.tokens == 200 + 800 + 1_000)

        let alone = Self.build(.month(year: 2026, month: 10), [.goose: goose])
        #expect(alone.cacheHitRate == nil)
        #expect(alone.cacheSavings == nil)
    }

    @Test("An agent whose counts may be missing is left out of the hit rate and counted, not allowed to take it away")
    func cacheHitRateWithheld() throws {
        let events = [Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 100, cacheRead: 100))]
        var partial = Self.ledger(events)
        partial.hasPartialCounts = true
        let healthy = Self.ledger([Event(at: Self.at(2026, 10, 2), model: "gpt", tally: TokenTally(input: 100, cacheRead: 300))])
        let both = Self.build(.month(year: 2026, month: 10), [.claudeCode: partial, .codex: healthy])
        // The rate is the healthy agent's alone, and the rest is said.
        #expect(try abs(#require(both.cacheHitRate) - 0.75) < 0.0001)
        #expect(both.cacheUnmeasuredTokens == 200)
        #expect(both.isPartial)

        // Alone, a partial agent leaves no rate at all, and nothing to state.
        let only = Self.build(.month(year: 2026, month: 10), [.claudeCode: partial])
        #expect(only.cacheHitRate == nil)
        #expect(only.cacheUnmeasuredTokens == 0)

        let day = LedgerDay(
            date: Self.at(2026, 10, 2, 0), tokens: 700, cost: 0, unpricedTokens: 0, models: ["m": 700],
            tally: TokenTally(input: 100, cacheRead: 100)
        )
        let unclassified = UsageLedger(days: [day], earliest: day.date, unpricedModels: [], modelNames: [:], slots: [])
        #expect(Self.build(.month(year: 2026, month: 10), [.claudeCode: unclassified]).cacheHitRate == nil)
    }

    // MARK: - Who, what, where

    @Test("Agents, models and projects rank heaviest first with shares of the whole")
    func shares() throws {
        var claude = Self.ledger([
            Self.event(Self.at(2026, 10, 1), 100),
            Self.event(Self.at(2026, 10, 2), 100),
            Self.event(Self.at(2026, 10, 3), 100),
        ])
        claude.sessions = [Self.session(
            "c", project: "/w/pulse", from: Self.at(2026, 10, 1), to: Self.at(2026, 10, 3),
            slots: [Self.slot(Self.at(2026, 10, 1), 100), Self.slot(Self.at(2026, 10, 2), 100), Self.slot(Self.at(2026, 10, 3), 100)]
        )]
        var codex = Self.ledger([
            Event(at: Self.at(2026, 10, 3), model: "gpt", tally: TokenTally(input: 300)),
            Event(at: Self.at(2026, 10, 4), model: "gpt", tally: TokenTally(input: 300)),
        ])
        codex.sessions = [
            Self.session("x", project: "/w/pulse", from: Self.at(2026, 10, 3), to: Self.at(2026, 10, 3), slots: [Self.slot(Self.at(2026, 10, 3), 300)]),
            Self.session("y", project: "/w/other", from: Self.at(2026, 10, 4), to: Self.at(2026, 10, 4), slots: [Self.slot(Self.at(2026, 10, 4), 300)]),
        ]
        let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: claude, .codex: codex])

        #expect(recap.tokens == 900)
        #expect(recap.sessions == 3)

        #expect(recap.agents.map(\.agent) == [.codex, .claudeCode])
        #expect(recap.agents.map(\.tokens) == [600, 300])
        // Active days are the agent's own, not the span's: Codex on two days
        // (one shared with Claude Code), Claude Code on three.
        #expect(recap.agents.map(\.activeDays) == [2, 3])
        // And which days: local midnights, one set per agent, each of the size
        // its count says, the shared day in both.
        #expect(recap.agents.map(\.activeDates) == [
            [Self.at(2026, 10, 3, 0), Self.at(2026, 10, 4, 0)],
            [Self.at(2026, 10, 1, 0), Self.at(2026, 10, 2, 0), Self.at(2026, 10, 3, 0)],
        ])
        #expect(recap.agents.allSatisfy { $0.activeDates.count == $0.activeDays })
        #expect(recap.activeDays == 4)
        #expect(try abs(#require(recap.agents.first).share - 2.0 / 3.0) < 0.0001)

        #expect(recap.models.map(\.name) == ["GPT", "Claude"])
        #expect(try abs(#require(recap.models.first).share - 2.0 / 3.0) < 0.0001)
        // 600 tokens at $2 and 300 at $3 per million.
        let gptCost = try #require(recap.models.first?.cost)
        let claudeCost = try #require(recap.models.last?.cost)
        #expect(abs(gptCost - 0.0012) < 1e-9)
        #expect(abs(claudeCost - 0.0009) < 1e-9)

        // One directory used by two agents is one project.
        #expect(recap.projects.map(\.name) == ["pulse", "other"])
        #expect(recap.projects.map(\.tokens) == [600, 300])
        #expect(recap.projects.map(\.sessions) == [2, 1])
        #expect(try abs(#require(recap.projects.last).share - 1.0 / 3.0) < 0.0001)
    }

    @Test("The busiest day is the earliest of the heaviest; streaks are the period's own")
    func busiestAndStreaks() {
        let recap = Self.october([
            Self.event(Self.at(2026, 9, 29), 10),
            Self.event(Self.at(2026, 9, 30), 10),
            Self.event(Self.at(2026, 10, 1), 10),
            Self.event(Self.at(2026, 10, 2), 400),
            Self.event(Self.at(2026, 10, 3), 400),
            Self.event(Self.at(2026, 10, 5), 10),
        ])
        #expect(recap.busiestDay?.date == Self.at(2026, 10, 2, 0))
        #expect(recap.busiestDay?.tokens == 400)
        // 29 Sep is September's: the run inside October is the 1st to the 3rd.
        // The 5th is a new run that is still going (today), one day.
        #expect(recap.longestStreak == 3)
        #expect(recap.currentStreak == 1)
        #expect(recap.currency == "USD")
        #expect(!recap.isPartial)
    }

    @Test("A past month's streaks stop at the month's edges, and its current one is how it ended")
    func pastMonthStreaks() {
        let days = [1, 2, 3, 10, 11, 12, 13, 14, 28, 29, 30]
        let recap = Self.build(
            .month(year: 2026, month: 9),
            [.claudeCode: Self.ledger(
                days.map { Self.event(Self.at(2026, 9, $0), 10) }
                    // October's own run must not reach back, nor add to September.
                    + (1...4).map { Self.event(Self.at(2026, 10, $0), 10) }
                    + [Self.event(Self.at(2026, 8, 30), 10), Self.event(Self.at(2026, 8, 31), 10)]
            )]
        )
        #expect(!recap.isInProgress)
        #expect(recap.longestStreak == 5)
        // The run that ends on 30 September (28, 29, 30), not October's.
        #expect(recap.currentStreak == 3)
        #expect(recap.longestStreak <= recap.elapsedDays)
    }

    @Test("A past month that ended on a quiet day has no current run; a running month's grace is today only")
    func streakEdges() {
        let quietEnd = Self.build(
            .month(year: 2026, month: 9),
            [.claudeCode: Self.ledger([Self.event(Self.at(2026, 9, 20), 10), Self.event(Self.at(2026, 9, 21), 10)])]
        )
        #expect(quietEnd.longestStreak == 2)
        #expect(quietEnd.currentStreak == 0)

        // Today (5 Oct) has had nothing yet: yesterday's run is still current.
        let before = Self.october((2...4).map { Self.event(Self.at(2026, 10, $0), 10) })
        #expect(before.currentStreak == 3)
        // Two quiet days end it.
        let lapsed = Self.october((1...3).map { Self.event(Self.at(2026, 10, $0), 10) })
        #expect(lapsed.currentStreak == 0)
        #expect(lapsed.longestStreak == 3)
        // The first of the month with nothing yet: yesterday is not in the period.
        let first = Self.build(
            .month(year: 2026, month: 10),
            [.claudeCode: Self.ledger([Self.event(Self.at(2026, 9, 30), 10)])],
            now: Self.at(2026, 10, 1)
        )
        #expect(first.tokens == 0)
        #expect(first.currentStreak == 0)
    }

    @Test("The streak helper counts runs of days with tokens, with today's grace only while running")
    func streakHelper() {
        func days(_ tokens: [Int]) -> [Recap.Day] {
            tokens.enumerated().map { Recap.Day(date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), tokens: $0.element, cost: nil) }
        }
        #expect(Recap.streaks(of: [], isInProgress: true) == (0, 0))
        let shape = days([1, 1, 0, 1, 1, 1, 0])
        #expect(Recap.streaks(of: shape, isInProgress: false) == (0, 3))
        #expect(Recap.streaks(of: shape, isInProgress: true) == (3, 3))
        #expect(Recap.streaks(of: days([0, 0, 5, 5]), isInProgress: true) == (2, 2))
    }

    @Test("Tokens with no published price are carried, so the money can be called a floor")
    func unpricedTokensAreCarried() {
        let mixed = Self.build(.month(year: 2026, month: 10), [.claudeCode: Self.ledger([
            Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 1_000_000)),
            Event(at: Self.at(2026, 10, 2), model: "mystery", tally: TokenTally(input: 500)),
        ])])
        #expect(mixed.unpricedTokens == 500)
        #expect(mixed.cost == 3)

        let none = Self.build(.month(year: 2026, month: 10), [.claudeCode: Self.ledger([
            Event(at: Self.at(2026, 10, 2), model: "claude", tally: TokenTally(input: 1_000)),
        ])])
        #expect(none.unpricedTokens == 0)

        let allUnpriced = Self.build(.month(year: 2026, month: 10), [.claudeCode: Self.ledger([
            Event(at: Self.at(2026, 10, 2), model: "mystery", tally: TokenTally(input: 1_000)),
        ])])
        #expect(allUnpriced.unpricedTokens == 1_000)
        #expect(allUnpriced.cost == nil)
    }

    @Test("An unpriced day breaks the cost line rather than drawing a zero, and takes nothing else away")
    func unpricedDayBreaksTheCostLine() {
        func series(_ mysteryDay: Int?) -> [Double?] {
            var events = [Self.event(Self.at(2026, 10, 1), 1_000_000), Self.event(Self.at(2026, 10, 3), 1_000_000)]
            if let mysteryDay {
                events.append(Event(at: Self.at(2026, 10, mysteryDay), model: "mystery", tally: TokenTally(input: 500)))
            }
            let recap = Self.build(.month(year: 2026, month: 10), [.claudeCode: Self.ledger(events)])
            return RecapDeck(recap: recap, monthlyPrice: nil, hidesProjects: false).costSeries
        }
        // October 2nd is quiet: a real zero between priced days.
        #expect(series(nil) == [3, 0, 3, 0, 0])
        // On the 4th there was work with no price: a gap, not a zero, and the
        // rest of the line stays.
        #expect(series(4) == [3, 0, 3, nil, 0])
    }

    @Test("A system calendar of another era builds the span the period names, and the year's months follow it")
    func buddhistCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        let ledger = Self.ledger([Self.event(Self.at(2026, 3, 15), 100), Self.event(Self.at(2026, 10, 3), 200)])
        // 2569 is 2026 in the Buddhist era.
        let recap = try #require(Recap.build(
            .year(2569), from: [.claudeCode: ledger], prices: Self.prices, now: Self.at(2026, 10, 5), calendar: buddhist
        ))
        #expect(recap.start == Self.at(2026, 1, 1, 0))
        #expect(recap.tokens == 300)
        #expect(recap.calendar.identifier == .buddhist)
        let starts = recap.monthStarts
        #expect(starts.count == 12)
        #expect(starts == (1...12).map { Self.at(2026, $0, 1, 0) })
        #expect(recap.months.map(\.tokens) == [0, 0, 100, 0, 0, 0, 0, 0, 0, 200, 0, 0])

        let month = try #require(Recap.build(
            .month(year: 2569, month: 10), from: [.claudeCode: ledger], prices: Self.prices, now: Self.at(2026, 10, 5), calendar: buddhist
        ))
        #expect(month.monthStarts == [Self.at(2026, 10, 1, 0)])
        #expect(month.tokens == 200)
    }

    @Test("A recap is built, offered and named in one calendar: Gregorian, weeks from Monday")
    func oneCalendar() {
        #expect(Recap.calendar.identifier == .gregorian)
        #expect(Recap.calendar.firstWeekday == 2)
        #expect(RecapFormat.calendar().identifier == .gregorian)
        #expect(RecapPeriods.earliest(in: [:]) == nil)
    }

    // MARK: - The command

    @Test("--recap reads a month, a year, or nothing for this month")
    func probeArguments() {
        let now = Self.at(2026, 10, 5)
        #expect(RecapReport.period(from: "2026-09", now: now, calendar: Self.calendar) == .month(year: 2026, month: 9))
        #expect(RecapReport.period(from: "2026", now: now, calendar: Self.calendar) == .year(2026))
        #expect(RecapReport.period(from: nil, now: now, calendar: Self.calendar) == .month(year: 2026, month: 10))
        #expect(RecapReport.period(from: "2026-13", now: now, calendar: Self.calendar) == nil)
        #expect(RecapReport.period(from: "2026-9", now: now, calendar: Self.calendar) == nil)
        #expect(RecapReport.period(from: "26", now: now, calendar: Self.calendar) == nil)
        #expect(RecapReport.period(from: "2026-09-01", now: now, calendar: Self.calendar) == nil)
        #expect(RecapReport.period(from: "september", now: now, calendar: Self.calendar) == nil)
    }

    @Test("The printed recap leaves a missing figure out rather than printing a zero")
    func probeOutput() throws {
        let recap = Self.build(.month(year: 2026, month: 10), [:])
        let data = try #require(RecapReport.encode(recap, calendar: Self.calendar))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["period"] as? String == "2026-10")
        #expect(json["start"] as? String == "2026-10-01")
        #expect(json["end"] as? String == "2026-10-06")
        #expect(json["tokens"] as? Int == 0)
        #expect(json["cost"] == nil)
        #expect(json["hours"] == nil)
        #expect(json["persona"] == nil)
        #expect(json["cacheHitRate"] == nil)
        #expect(json["previousTokens"] == nil)

        let full = Self.october([Self.event(Self.at(2026, 10, 2, 23), 1_000_000)])
        let printed = try #require(RecapReport.encode(full, calendar: Self.calendar))
        let object = try #require(JSONSerialization.jsonObject(with: printed) as? [String: Any])
        #expect(object["persona"] as? String == "nightOwl")
        #expect(object["cost"] as? Double == 3)
        #expect((object["hours"] as? [Int])?.count == 24)
        // Each agent carries the days it worked, as dates.
        let agents = try #require(object["agents"] as? [[String: Any]])
        #expect(agents.first?["days"] as? [String] == ["2026-10-02"])
        #expect(agents.first?["activeDays"] as? Int == 1)
    }
}
