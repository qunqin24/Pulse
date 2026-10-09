import Foundation
import Testing
@testable import Pulse

/// What the opener, calendar, timetable and payback cards read off a recap:
/// weekday and week totals, the streak chain, the quarters of the day, money
/// per million tokens, and the per-agent strips. All worked out apart from any
/// drawing, so a card can be left to draw what it is given.
@Suite("Recap insights")
struct RecapInsightsTests {
    private static var calendar: Calendar { Recap.calendar }

    private static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// September 2026 from day 1 (a Tuesday) for as many days as `tokens` has.
    private static func september(_ tokens: [Int], cost: ((Int) -> Double?)? = nil) -> [Recap.Day] {
        tokens.enumerated().map { index, count in
            Recap.Day(date: date(9, index + 1), tokens: count, cost: count > 0 ? cost?(count) : nil)
        }
    }

    private static func recap(
        days: [Recap.Day],
        period: Recap.Period = .month(year: 2026, month: 9),
        months: [Recap.Month] = [],
        agents: [Recap.AgentShare] = [],
        hours: [Int]? = nil,
        cost: Double? = nil,
        unpricedTokens: Int = 0
    ) -> Recap {
        let tokens = days.reduce(0) { $0 + $1.tokens }
        return Recap(
            period: period, start: days.first?.date ?? date(9, 1), end: date(10, 1), isInProgress: false,
            tokens: tokens, cost: cost, unpricedTokens: unpricedTokens, previousTokens: nil,
            activeDays: days.filter { $0.tokens > 0 }.count, elapsedDays: days.count, sessions: 1,
            days: days, months: months, hours: hours, peakHour: nil, lateShare: nil, latestMinute: nil, lateNights: 0,
            persona: nil, models: [], agents: agents, projects: [], cacheHitRate: nil, cacheSavings: nil,
            currentStreak: 0, longestStreak: 0, busiestDay: nil, currency: "USD", isPartial: false
        )
    }

    // MARK: - Weekdays and weekends

    @Test("Tokens by weekday, Monday first, and a weekday the period never had is nil, not zero")
    func weekdays() {
        // Tue 1, Wed 2, Thu 3: no Monday, Friday, Saturday or Sunday yet.
        let few = RecapInsights(Self.recap(days: Self.september([100, 40, 0])))
        #expect(few.weekdayTokens == [nil, 100, 40, 0, nil, nil, nil])
        #expect(few.busiestWeekday == 1)

        // Ten days: Tue Sep 1 through Thu Sep 10, two Tuesdays.
        let ten = RecapInsights(Self.recap(days: Self.september([100, 0, 0, 0, 5, 7, 1, 50, 0, 3])))
        #expect(ten.weekdayTokens == [1, 150, 0, 3, 0, 5, 7])
        #expect(ten.busiestWeekday == 1)
    }

    @Test("The busiest weekday is the earliest of a tie, and none when nothing was used")
    func busiestWeekdayTies() {
        let tie = RecapInsights(Self.recap(days: Self.september([10, 10, 0, 0, 0, 0, 0])))
        #expect(tie.busiestWeekday == 1)
        let none = RecapInsights(Self.recap(days: Self.september([0, 0, 0])))
        #expect(none.busiestWeekday == nil)
    }

    @Test("Weekdays against the weekend: tokens, days the period had, and days used")
    func workSplit() throws {
        // Sep 1–10: weekend days are 5 and 6.
        let split = try #require(RecapInsights(Self.recap(days: Self.september([100, 0, 0, 0, 30, 0, 50, 20, 0, 0]))).workSplit)
        #expect(split.weekdayTokens == 170)
        #expect(split.weekendTokens == 30)
        #expect(split.weekdayDays == 8)
        #expect(split.weekendDays == 2)
        #expect(split.weekdayActive == 3)
        #expect(split.weekendActive == 1)
        #expect(abs(split.weekdayShare - 0.85) < 1e-9)
        #expect(abs(split.weekendShare - 0.15) < 1e-9)
    }

    @Test("Nothing to split with no work")
    func workSplitNeedsWork() {
        #expect(RecapInsights(Self.recap(days: Self.september([0, 0, 0]))).workSplit == nil)
        #expect(RecapInsights(Self.recap(days: [])).workSplit == nil)
    }

    @Test("Tokens on an average day with work")
    func perActiveDay() {
        #expect(RecapInsights(Self.recap(days: Self.september([100, 0, 50]))).tokensPerActiveDay == 75)
        #expect(RecapInsights(Self.recap(days: Self.september([0, 0]))).tokensPerActiveDay == nil)
    }

    // MARK: - Weeks

    @Test("Weeks run Monday to Sunday and are clipped to the month")
    func weeks() {
        let days = (1...30).map { Recap.Day(date: Self.date(9, $0), tokens: $0, cost: nil) }
        let weeks = RecapInsights(Self.recap(days: days)).weeks
        #expect(weeks.count == 5)
        #expect(weeks.map(\.first) == [1, 7, 14, 21, 28].map { Self.date(9, $0) })
        #expect(weeks.map(\.last) == [6, 13, 20, 27, 30].map { Self.date(9, $0) })
        #expect(weeks.map(\.tokens) == [21, 70, 119, 168, 87])
        #expect(RecapInsights(Self.recap(days: days)).busiestWeek == 3)
    }

    @Test("A quiet week is there, with nothing in it, and the busiest is the earliest of a tie")
    func quietAndTiedWeeks() {
        var days = (1...14).map { Recap.Day(date: Self.date(9, $0), tokens: 0, cost: nil) }
        days[0] = Recap.Day(date: Self.date(9, 1), tokens: 10, cost: nil)
        days[7] = Recap.Day(date: Self.date(9, 8), tokens: 10, cost: nil)
        let insights = RecapInsights(Self.recap(days: days))
        #expect(insights.weeks.map(\.tokens) == [10, 10, 0])
        #expect(insights.busiestWeek == 0)
    }

    @Test("A month running only a few days has a short week and nothing past today")
    func runningMonthWeeks() {
        let days = Self.september([5, 5, 5, 5, 5, 5, 5, 5])
        let weeks = RecapInsights(Self.recap(days: days)).weeks
        #expect(weeks.map(\.first) == [Self.date(9, 1), Self.date(9, 7)])
        #expect(weeks.map(\.last) == [Self.date(9, 6), Self.date(9, 8)])
    }

    // MARK: - The streak

    @Test("The longest run is the earliest of a tie, and nil with no work")
    func longestRun() throws {
        let days = Self.september([1, 0, 1, 1, 0, 1, 1, 0, 1])
        let run = try #require(RecapInsights(Self.recap(days: days)).longestRun)
        #expect(run.first == Self.date(9, 3))
        #expect(run.last == Self.date(9, 4))
        #expect(run.length == 2)
        #expect(RecapInsights(Self.recap(days: Self.september([0, 0]))).longestRun == nil)
        #expect(RecapInsights(Self.recap(days: Self.september([0, 0]))).streakChain == nil)
    }

    @Test("The chain is a window of nine around the run, kept inside the month")
    func chainWindow() throws {
        // A three-day run in the middle: three days either side.
        var tokens = [Int](repeating: 0, count: 30)
        for day in [25, 26, 27] { tokens[day - 1] = 1 }
        let middle = try #require(RecapInsights(Self.recap(days: Self.september(tokens))).streakChain)
        #expect(middle.days.count == 9)
        #expect(middle.days.first == Self.date(9, 22))
        #expect(middle.days.last == Self.date(9, 30))
        #expect(middle.run == 3..<6)
        #expect(middle.first == Self.date(9, 22) && middle.last == Self.date(9, 30))

        // A run at the very start cannot be centred: the window stays inside.
        var early = [Int](repeating: 0, count: 30)
        early[0] = 1
        early[1] = 1
        let start = try #require(RecapInsights(Self.recap(days: Self.september(early))).streakChain)
        #expect(start.days.first == Self.date(9, 1))
        #expect(start.days.last == Self.date(9, 9))
        #expect(start.run == 0..<2)
    }

    @Test("A month shorter than the window is all of it, and a long run shows its first nine days")
    func chainEdges() throws {
        let short = try #require(RecapInsights(Self.recap(days: Self.september([0, 1, 1, 0]))).streakChain)
        #expect(short.days.count == 4)
        #expect(short.run == 1..<3)

        let long = try #require(RecapInsights(Self.recap(days: Self.september([Int](repeating: 1, count: 20) + [0, 0]))).streakChain)
        #expect(long.days.count == 9)
        #expect(long.run == 0..<9)
        // The label names where the run really ends.
        #expect(long.first == Self.date(9, 1))
        #expect(long.last == Self.date(9, 20))
    }

    // MARK: - Time of day

    private static func hours(_ shape: [Int: Int]) -> [Int] { (0..<24).map { shape[$0] ?? 0 } }

    @Test("The day starts at the first hour from 05:00 with any work, and not at the after-midnight tail")
    func firstHour() {
        let days = Self.september([1])
        #expect(RecapInsights(Self.recap(days: days, hours: Self.hours([0: 5, 10: 3, 12: 9]))).firstHour == 10)
        #expect(RecapInsights(Self.recap(days: days, hours: Self.hours([5: 1, 10: 3]))).firstHour == 5)
        #expect(RecapInsights(Self.recap(days: days, hours: Self.hours([0: 5, 3: 2]))).firstHour == nil)
        #expect(RecapInsights(Self.recap(days: days, hours: nil)).firstHour == nil)
    }

    @Test("Four quarters of the day, each a share of the hour shape")
    func quarters() throws {
        let insights = RecapInsights(Self.recap(days: Self.september([1]), hours: Self.hours([1: 10, 7: 30, 13: 20, 20: 40])))
        let quarters = try #require(insights.quarters)
        #expect(quarters.map(\.hours) == [0..<6, 6..<12, 12..<18, 18..<24])
        #expect(quarters.map(\.tokens) == [10, 30, 20, 40])
        #expect(abs(quarters[3].share - 0.4) < 1e-9)
        #expect(insights.leadingQuarter == 3)
        #expect(RecapInsights(Self.recap(days: Self.september([1]), hours: nil)).quarters == nil)
        #expect(RecapInsights(Self.recap(days: Self.september([1]), hours: Self.hours([:]))).quarters == nil)
    }

    @Test("A tie between quarters goes to the earlier one")
    func quarterTie() {
        let insights = RecapInsights(Self.recap(days: Self.september([1]), hours: Self.hours([2: 10, 20: 10])))
        #expect(insights.leadingQuarter == 0)
    }

    // MARK: - Money

    @Test("Dollars per million tokens count the priced tokens only")
    func costPerMillion() {
        let days = Self.september([1_000_000, 1_000_000])
        #expect(RecapInsights(Self.recap(days: days, cost: 10)).costPerMillion == 5)
        // A quarter unpriced: the cost is for the other three.
        #expect(RecapInsights(Self.recap(days: days, cost: 6, unpricedTokens: 500_000)).costPerMillion == 4)
        #expect(RecapInsights(Self.recap(days: days, cost: nil)).costPerMillion == nil)
        #expect(RecapInsights(Self.recap(days: days, cost: 6, unpricedTokens: 2_000_000)).costPerMillion == nil)
        #expect(RecapInsights(Self.recap(days: days, cost: 10)).costPerActiveDay == 5)
    }

    @Test("The dearest day is the dearest priced day; a day with no price does not take the tile away")
    func costliestDay() throws {
        let priced = Self.september([10, 0, 30, 20], cost: { Double($0) })
        let insights = RecapInsights(Self.recap(days: priced, cost: 60))
        #expect(try #require(insights.costliestDay).date == Self.date(9, 3))

        var unpriced = priced
        unpriced[1] = Recap.Day(date: Self.date(9, 2), tokens: 99, cost: nil)
        #expect(try #require(RecapInsights(Self.recap(days: unpriced, cost: 60)).costliestDay).date == Self.date(9, 3))
        #expect(RecapInsights(Self.recap(days: Self.september([10, 20]), cost: nil)).costliestDay == nil)
    }

    @Test("The earliest of equal days is the dearest")
    func costliestTie() throws {
        let days = Self.september([10, 10], cost: { Double($0) })
        #expect(try #require(RecapInsights(Self.recap(days: days, cost: 20)).costliestDay).date == Self.date(9, 1))
    }

    @Test("Daily money: a quiet day is a real zero, a day with no price is a gap")
    func dailyBars() {
        let priced = Self.september([10, 0, 30], cost: { Double($0) })
        #expect(RecapInsights(Self.recap(days: priced, cost: 40)).costBars == [10, 0, 30])

        var partial = priced
        partial[2] = Recap.Day(date: Self.date(9, 3), tokens: 30, cost: nil)
        #expect(RecapInsights(Self.recap(days: partial, cost: 10)).costBars == [10, 0, nil])
        #expect(RecapInsights(Self.recap(days: Self.september([10, 20]), cost: nil)).costBars == nil)
    }

    @Test("A year's money is by month, and an unpriced month is a gap")
    func monthlyBars() {
        let months = (1...12).map { Recap.Month(month: $0, tokens: $0 == 4 ? 0 : 100, cost: $0 == 4 ? nil : Double($0), activeDays: 1) }
        let year = Self.recap(days: Self.september([1]), period: .year(2026), months: months, cost: 70)
        #expect(RecapInsights(year).costBars == [1, 2, 3, 0, 5, 6, 7, 8, 9, 10, 11, 12])

        // A free model's day is priced at zero, and is still a price.
        let free = Self.september([10, 20], cost: { $0 == 10 ? 0 : 5 })
        #expect(RecapInsights(Self.recap(days: free, cost: 5)).costBars == [0, 5])

        var broken = months
        broken[8] = Recap.Month(month: 9, tokens: 100, cost: nil, activeDays: 1)
        #expect(RecapInsights(Self.recap(days: Self.september([1]), period: .year(2026), months: broken, cost: 70)).costBars
                == [1, 2, 3, 0, 5, 6, 7, 8, nil, 10, 11, 12])
    }

    // MARK: - Who worked when

    private static func agent(_ agent: SpendAgent, on dates: [Date]) -> Recap.AgentShare {
        Recap.AgentShare(agent: agent, tokens: 1, share: 0.5, activeDays: dates.count, cost: nil, activeDates: Set(dates))
    }

    @Test("A strip says used, another agent's day, a quiet weekend or a quiet weekday")
    func dayMarks() {
        // Sep 1 Tue … Sep 8 Tue. Work: Tue 1 (this agent), Wed 2 (another), Sat 5 (another); quiet: the rest.
        let days = Self.september([5, 5, 0, 0, 5, 0, 0, 0])
        let claude = Self.agent(.claudeCode, on: [Self.date(9, 1)])
        let insights = RecapInsights(Self.recap(days: days, agents: [claude]))
        #expect(insights.dayMarks(of: claude) == [.used, .other, .quiet, .quiet, .other, .quietWeekend, .quiet, .quiet])
        #expect(insights.marks(of: claude) == insights.dayMarks(of: claude))
    }

    @Test("In a year the strip has a cell per month: used, other, or quiet")
    func monthMarks() {
        let months = (1...12).map { Recap.Month(month: $0, tokens: $0 == 3 ? 0 : 10, cost: nil, activeDays: 1) }
        let codex = Self.agent(.codex, on: [Self.date(1, 12, year: 2025), Self.date(6, 3, year: 2025)])
        let year = Self.recap(days: Self.september([1]), period: .year(2025), months: months, agents: [codex])
        let marks = RecapInsights(year).marks(of: codex)
        #expect(marks.count == 12)
        #expect(marks[0] == .used)
        #expect(marks[2] == .quiet)
        #expect(marks[1] == .other)
        #expect(marks[5] == .used)
    }

    @Test("In a running year the months to come are neither quiet nor zero")
    func monthsToCome() {
        // 2026 read on 10 March: April to December have not begun.
        let months = (1...12).map { Recap.Month(month: $0, tokens: $0 <= 3 ? 10 : 0, cost: $0 <= 3 ? 1 : nil, activeDays: $0 <= 3 ? 1 : 0) }
        let codex = Self.agent(.codex, on: [Self.date(2, 3)])
        let base = Self.recap(days: [Recap.Day(date: Self.date(3, 10), tokens: 5, cost: 1)], period: .year(2026), months: months,
                              agents: [codex], cost: 3)
        let running = Recap(
            period: base.period, start: Self.date(1, 1), end: Self.date(3, 11), isInProgress: true,
            tokens: base.tokens, cost: base.cost, unpricedTokens: 0, previousTokens: nil,
            activeDays: base.activeDays, elapsedDays: base.elapsedDays, sessions: 1,
            days: base.days, months: months, hours: nil, peakHour: nil, lateShare: nil, latestMinute: nil, lateNights: 0,
            persona: nil, models: [], agents: [codex], projects: [], cacheHitRate: nil, cacheSavings: nil,
            currentStreak: 0, longestStreak: 0, busiestDay: nil, currency: "USD", isPartial: false
        )
        let insights = RecapInsights(running)
        #expect(insights.isMonthToCome(2) == false)
        #expect(insights.isMonthToCome(3))
        let marks = insights.marks(of: codex)
        #expect(marks[1] == .used)
        #expect(marks[3...].allSatisfy { $0 == .toCome })
        let bars = insights.costBars
        #expect(bars?[0...2].allSatisfy { $0 == 1 } == true)
        #expect(bars?[3...].allSatisfy { $0 == nil } == true)
    }
}
