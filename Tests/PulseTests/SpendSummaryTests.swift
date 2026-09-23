import Foundation
import Testing
@testable import Pulse

/// Adding two agents' ledgers together, which is arithmetic until the calendar
/// gets involved.
@Suite("Spend summary")
struct SpendSummaryTests {
    private static let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_372_800))

    private static func day(_ daysAgo: Int, tokens: Int, cost: Double, models: [String: Int] = [:]) -> LedgerDay {
        LedgerDay(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: today)!,
            tokens: tokens,
            cost: cost,
            unpricedTokens: 0,
            models: models.isEmpty ? ["m": tokens] : models
        )
    }

    private static func ledger(
        _ days: [LedgerDay],
        origin: UsageLedger.Origin = .localTranscripts,
        names: [String: String] = [:]
    ) -> UsageLedger {
        UsageLedger(
            origin: origin,
            days: days,
            earliest: days.first?.date,
            unpricedModels: [],
            modelNames: names,
            slots: []
        )
    }

    private static func summary(
        _ ledgers: [SpendAgent: UsageLedger],
        overLast span: Int?
    ) -> SpendSummary {
        SpendSummary.of(ledgers, overLast: span, now: today, calendar: calendar)
    }

    // MARK: - The span

    @Test("A span is a window on the calendar, not each ledger's last few rows")
    func spanIsADateWindow() {
        // Codex was used today; Claude Code was last used a fortnight ago.
        // Taking seven rows from each would reach back fourteen days for one
        // of them and draw nine bars for a seven-day span — which it did.
        let summary = Self.summary([
            .codex: Self.ledger((0..<7).map { Self.day($0, tokens: 100, cost: 1) }),
            .claudeCode: Self.ledger((10..<17).map { Self.day($0, tokens: 100, cost: 1) }),
        ], overLast: 7)

        #expect(summary.days.count == 7)
        // Only Codex's week is inside the window; Claude Code's work is older
        // than the cutoff and is not in the total.
        #expect(summary.tokens == 700)
        #expect(summary.agents.map(\.agent) == [.codex])
    }

    @Test("Quiet days are in the series, so the chart stays a calendar")
    func emptyDaysArePadded() {
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(0, tokens: 100, cost: 1), Self.day(6, tokens: 50, cost: 0.5)]),
        ], overLast: 7)

        #expect(summary.days.count == 7)
        // Five of the seven had nothing on them — and a chart drawn from only
        // the days with work would compress a quiet week into a busy one.
        #expect(summary.activeDays == 2)
        #expect(summary.days.filter { $0.tokens == 0 }.count == 5)
    }

    @Test("Today is the day in progress, not the last twenty-four hours")
    func todayIsOneCalendarDay() {
        let summary = Self.summary([
            .codex: Self.ledger([
                Self.day(0, tokens: 100, cost: 1),
                // Yesterday evening is not part of today, however recent it is.
                Self.day(1, tokens: 900, cost: 9),
            ]),
        ], overLast: 1)

        #expect(summary.days.count == 1)
        #expect(summary.tokens == 100)
        #expect(summary.cost == 1)
    }

    @Test("All time runs from the earliest day to today")
    func allTimeCoversEverything() {
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(9, tokens: 10, cost: 1)]),
        ], overLast: nil)

        #expect(summary.days.count == 10)
        #expect(summary.tokens == 10)
    }

    // MARK: - What may be added up

    @Test("A ledger that cannot be priced is left out of a priced total")
    func providerStatisticsAreExcluded() {
        // Z.ai reports one token total per model and no money. Folding it in
        // would put a figure on the total that half of it cannot carry.
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(0, tokens: 100, cost: 2)]),
            .openCode: Self.ledger([Self.day(0, tokens: 900, cost: 0)], origin: .providerStatistics),
        ], overLast: 7)

        #expect(summary.tokens == 100)
        #expect(summary.cost == 2)
        #expect(summary.agents.map(\.agent) == [.codex])
    }

    @Test("An agent with nothing in the span is not a row")
    func silentAgentsAreOmitted() {
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(0, tokens: 100, cost: 1)]),
            .claudeCode: Self.ledger([Self.day(0, tokens: 0, cost: 0)]),
        ], overLast: 7)

        // A row reading zero is a row that has to be explained.
        #expect(summary.agents.map(\.agent) == [.codex])
    }

    // MARK: - The splits

    @Test("Agents rank by tokens, heaviest first")
    func agentsAreRanked() {
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(0, tokens: 100, cost: 1)]),
            .claudeCode: Self.ledger([Self.day(0, tokens: 400, cost: 9)]),
        ], overLast: 7)

        #expect(summary.agents.map(\.agent) == [.claudeCode, .codex])
        #expect(summary.tokens == 500)
        #expect(summary.cost == 10)
    }

    @Test("A model used by two agents is one row naming both")
    func modelsAreCombinedAcrossAgents() {
        let summary = Self.summary([
            .codex: Self.ledger(
                [Self.day(0, tokens: 300, cost: 1, models: ["shared": 200, "gpt": 100])],
                names: ["shared": "Shared Model", "gpt": "GPT"]
            ),
            .claudeCode: Self.ledger(
                [Self.day(0, tokens: 100, cost: 1, models: ["shared": 100])],
                names: ["shared": "Shared Model"]
            ),
        ], overLast: 7)

        let shared = summary.models.first
        #expect(shared?.name == "Shared Model")
        #expect(shared?.tokens == 300)
        // Both, and in a stable order — a row whose agents shuffle between
        // reads looks like the data moved.
        #expect(shared?.agents == [.claudeCode, .codex])
        #expect(abs((shared?.share ?? 0) - 0.75) < 0.0001)
    }

    @Test("One raw id, priced in one source and unknown-only in another, is one model row")
    func unknownOnlyKeepsTheSameNameAcrossSources() {
        // The same model id reaches Pulse two ways: one source classified its
        // work, another reported only a bare total. Without the name lookup the
        // unknown-only copy would group under its raw id and the model would
        // split into two rows — one named, one not.
        let prices: [String: ModelPrice] = [
            "gpt-5": ModelPrice(
                input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "GPT-5"
            )
        ]
        let at = Self.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Self.today)!

        let known = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: at, model: "gpt-5", tally: TokenTally(input: 1_000))],
            prices: prices, namespace: "a", calendar: Self.calendar
        )
        let unknown = AgentUsageLedger.build(
            [AgentUsageRecord(timestamp: at, model: "gpt-5", tally: TokenTally(), unclassifiedTokens: 500)],
            prices: prices, namespace: "b", calendar: Self.calendar
        )

        let summary = Self.summary([.codex: known, .claudeCode: unknown], overLast: 7)
        #expect(summary.models.map(\.name) == ["GPT-5"])
        #expect(summary.models.first?.tokens == 1_500)
        #expect(summary.models.first?.agents == [.claudeCode, .codex])
        // The day carries the unknown-price tokens beside the priced ones.
        #expect(summary.days.last?.unpricedTokens == 500)

        let model = ModelSpendSummary.of(
            [.codex: known, .claudeCode: unknown], named: "GPT-5",
            overLast: 7, now: Self.today, calendar: Self.calendar
        )
        #expect(model.tokens == 1_500)
        // 1,000 input at $1,000/M for the classified copy.
        #expect(model.cost == 1)
        #expect(model.unpricedTokens == 500)
        #expect(model.agents.count == 2)
    }

    @Test("The busiest day is the busiest across agents, not any one of them")
    func busiestDayIsCombined() {
        // Neither agent's own heaviest day is the pair's heaviest.
        let summary = Self.summary([
            .codex: Self.ledger([Self.day(0, tokens: 60, cost: 1), Self.day(1, tokens: 50, cost: 1)]),
            .claudeCode: Self.ledger([Self.day(1, tokens: 50, cost: 1)]),
        ], overLast: 7)

        #expect(summary.busiestDay?.tokens == 100)
        #expect(summary.busiestDay?.date == Self.calendar.date(byAdding: .day, value: -1, to: Self.today))
    }

    // MARK: - Day by day

    @Test("Each day carries its own split, summed across agents")
    func daysCarryTheirTally() {
        var codex = Self.day(0, tokens: 300, cost: 1)
        codex = LedgerDay(
            date: codex.date, tokens: 300, cost: 1, unpricedTokens: 0, models: ["m": 300],
            tally: TokenTally(input: 100, cacheWrite: 50, cacheRead: 120, output: 30)
        )
        var claude = Self.day(0, tokens: 100, cost: 2)
        claude = LedgerDay(
            date: claude.date, tokens: 100, cost: 2, unpricedTokens: 0, models: ["m": 100],
            tally: TokenTally(input: 10, cacheWrite: 5, cacheRead: 80, output: 5)
        )

        let summary = Self.summary([
            .codex: Self.ledger([codex]),
            .claudeCode: Self.ledger([claude]),
        ], overLast: 7)

        let today = summary.days.last
        // Both agents' work on one day is one row, split and all.
        #expect(today?.tally.input == 110)
        #expect(today?.tally.cacheRead == 200)
        #expect(today?.tally.total == 400)
    }

    @Test("A day's unknown-price tokens roll up into its day and month rows")
    func unpricedTokensReachDaysAndMonths() {
        let priced = LedgerDay(
            date: Self.today, tokens: 100, cost: 1, unpricedTokens: 0, models: ["m": 100]
        )
        let unpriced = LedgerDay(
            date: Self.today, tokens: 300, cost: 0, unpricedTokens: 300, models: ["mystery": 300]
        )

        let summary = Self.summary([
            .codex: Self.ledger([priced]),
            .claudeCode: Self.ledger([unpriced]),
        ], overLast: 7)

        #expect(summary.days.last?.tokens == 400)
        #expect(summary.days.last?.unpricedTokens == 300)
        #expect(summary.months.last?.unpricedTokens == 300)
        // A quiet day carries a real zero rather than a missing figure.
        #expect(summary.days.first?.unpricedTokens == 0)
    }

    @Test("The table sorts by any column, both ways")
    func theTableSorts() {
        let days = [
            SpendSummary.Day(date: Self.today, tokens: 10, cost: 9,
                             tally: TokenTally(input: 1, cacheWrite: 0, cacheRead: 9, output: 0)),
            SpendSummary.Day(date: Self.calendar.date(byAdding: .day, value: -1, to: Self.today)!,
                             tokens: 900, cost: 1,
                             tally: TokenTally(input: 800, cacheWrite: 0, cacheRead: 100, output: 0)),
        ]

        // Descending is the default, because the first thing anybody looks for
        // in a table like this is the biggest row.
        #expect(SpendSummary.sorted(days, by: .cost, ascending: false).first?.cost == 9)
        #expect(SpendSummary.sorted(days, by: .total, ascending: false).first?.tokens == 900)
        #expect(SpendSummary.sorted(days, by: .input, ascending: true).first?.tally.input == 1)
        #expect(SpendSummary.sorted(days, by: .date, ascending: false).first?.date == Self.today)
    }

    // MARK: - Sessions and projects

    private static func session(
        _ name: String,
        project: String?,
        endedDaysAgo: Int,
        tokens: Int,
        cost: Double
    ) -> UsageLedger.Session {
        let end = calendar.date(byAdding: .day, value: -endedDaysAgo, to: today)!
        return UsageLedger.Session(
            id: "/tmp/\(name).jsonl", name: name, title: nil, project: UsageProject(project),
            start: end, end: end, tokens: tokens, cost: cost
        )
    }

    @Test("A session is in the span by when it ended")
    func sessionsAreFilteredByTheirEnd() {
        var ledger = Self.ledger([Self.day(0, tokens: 10, cost: 1)])
        ledger.sessions = [
            Self.session("recent", project: "Pulse", endedDaysAgo: 1, tokens: 100, cost: 1),
            // A conversation that finished a fortnight ago is not in a week.
            Self.session("old", project: "Pulse", endedDaysAgo: 14, tokens: 900, cost: 9),
        ]

        let summary = Self.summary([.codex: ledger], overLast: 7)
        #expect(summary.sessions.map(\.session.name) == ["recent"])
    }

    @Test("Projects roll up their sessions; sessions without one are not a bucket")
    func projectsAreRolledUp() {
        var ledger = Self.ledger([Self.day(0, tokens: 10, cost: 1)])
        ledger.sessions = [
            Self.session("a", project: "Pulse", endedDaysAgo: 0, tokens: 100, cost: 1),
            Self.session("b", project: "Pulse", endedDaysAgo: 2, tokens: 300, cost: 3),
            // Codex keeps no directory. Putting these in an "other" row would
            // make the largest project on the list a name for "unknown".
            Self.session("c", project: nil, endedDaysAgo: 0, tokens: 900, cost: 9),
        ]

        let summary = Self.summary([.codex: ledger], overLast: 7)
        #expect(summary.projects.count == 1)

        let project = summary.projects.first
        #expect(project?.tokens == 400)
        #expect(project?.sessions == 2)
        // The most recent of its sessions, not the first one seen.
        #expect(project?.lastUsed == Self.today)
        // Every session is still a row, project or no project.
        #expect(summary.sessions.count == 3)
    }

    // MARK: - The pattern

    @Test("A streak is the run ending at the most recent day")
    func streaksAreCountedFromTheEnd() {
        // Worked today and the two days before; a gap; then four days.
        let worked = [0, 1, 2, 4, 5, 6, 7]
        let summary = Self.summary([
            .codex: Self.ledger(worked.map { Self.day($0, tokens: 10, cost: 1) }),
        ], overLast: 10)

        #expect(summary.currentStreak == 3)
        #expect(summary.longestStreak == 4)
        #expect(summary.activeDays == 7)
    }

    @Test("A streak that ended yesterday is not current")
    func aBrokenStreakIsZero() {
        let summary = Self.summary([
            .codex: Self.ledger((1..<5).map { Self.day($0, tokens: 10, cost: 1) }),
        ], overLast: 10)

        // The series runs to today, and nothing was done today.
        #expect(summary.currentStreak == 0)
        #expect(summary.longestStreak == 4)
    }

    @Test("The peak hour comes from the quarter-hour buckets, not the days")
    func peakHourIsReadFromSlots() {
        let afternoon = Self.calendar.date(bySettingHour: 16, minute: 30, second: 0, of: Self.today)!
        let morning = Self.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Self.today)!

        var ledger = Self.ledger([Self.day(0, tokens: 400, cost: 1)])
        ledger = UsageLedger(
            origin: .localTranscripts,
            days: ledger.days,
            earliest: ledger.earliest,
            unpricedModels: [],
            modelNames: [:],
            slots: [
                .init(start: morning, tokens: 100, cost: 0.25),
                .init(start: afternoon, tokens: 300, cost: 0.75),
            ]
        )

        let summary = Self.summary([.codex: ledger], overLast: 7)
        // A `LedgerDay` has already thrown the time of day away, so this can
        // only come from the buckets.
        #expect(summary.peakHour == 16)
        #expect(summary.hours[9] == 100)
    }

    @Test("Nothing to add up is empty, not zero-shaped")
    func nothingIsEmpty() {
        #expect(Self.summary([:], overLast: 7).isEmpty)
        #expect(Self.summary([.codex: .empty], overLast: 7).isEmpty)
    }

    // MARK: - Sessions that straddle the span

    @Test("A session resumed past midnight is counted by the day, not by when it ended")
    func aSessionAcrossMidnightFollowsTheSpan() {
        // The bug: one session with 900 tokens / $9 yesterday and 100 / $1
        // today put the whole 1000 / $10 on the project while the Today total
        // read 100 / $1.
        let lateYesterday = Self.calendar.date(
            bySettingHour: 23, minute: 30, second: 0,
            of: Self.calendar.date(byAdding: .day, value: -1, to: Self.today)!
        )!
        let noonToday = Self.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Self.today)!

        var ledger = Self.ledger([Self.day(1, tokens: 900, cost: 9), Self.day(0, tokens: 100, cost: 1)])
        ledger.sessions = [
            UsageLedger.Session(
                id: "/tmp/long.jsonl", name: "long", title: "Long", project: UsageProject("Pulse"),
                start: lateYesterday, end: noonToday, tokens: 1000, cost: 10,
                slots: [
                    .init(start: lateYesterday, tokens: 900, cost: 9),
                    .init(start: noonToday, tokens: 100, cost: 1),
                ]
            ),
        ]

        let today = Self.summary([.codex: ledger], overLast: 1)
        #expect(today.tokens == 100)
        #expect(today.cost == 1)
        #expect(today.projects.first?.tokens == 100)
        #expect(abs((today.projects.first?.cost ?? 0) - 1) < 1e-9)
        // The row carries the span's portion, so the list and the totals above
        // it are the same arithmetic.
        #expect(today.sessions.first?.session.tokens == 100)

        // The whole session is back once the span reaches before it.
        let week = Self.summary([.codex: ledger], overLast: 7)
        #expect(week.projects.first?.tokens == 1000)
        #expect(abs((week.projects.first?.cost ?? 0) - 10) < 1e-9)
    }

    @Test("A session resumed over days contributes only the days in the window")
    func aResumedSessionFollowsTheWindow() {
        let slots = (0..<3).map { offset -> UsageLedger.Slot in
            let day = Self.calendar.date(byAdding: .day, value: -offset, to: Self.today)!
            let at = Self.calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
            return .init(start: at, tokens: 100, cost: 1)
        }
        var ledger = Self.ledger((0..<3).map { Self.day($0, tokens: 100, cost: 1) })
        ledger.sessions = [
            UsageLedger.Session(
                id: "/tmp/resumed.jsonl", name: "resumed", title: nil, project: UsageProject("Pulse"),
                start: slots[2].start, end: slots[0].start, tokens: 300, cost: 3, slots: slots
            ),
        ]

        let week = Self.summary([.codex: ledger], overLast: 7)
        #expect(week.projects.first?.tokens == 300)
        #expect(week.sessions.count == 1)

        let todayOnly = Self.summary([.codex: ledger], overLast: 1)
        #expect(todayOnly.tokens == 100)
        #expect(todayOnly.projects.first?.tokens == 100)
        #expect(todayOnly.projects.first?.sessions == 1)
        #expect(todayOnly.sessions.count == 1)
    }

    @Test("The project total is the sum of the in-span session buckets")
    func projectTotalReconcilesWithTheSpan() {
        // Two sessions in one project, one straddling the cutoff. Nothing is
        // prorated: the project's money is the sum of the buckets, the same
        // number the day rows add up to.
        let yesterdayLate = Self.calendar.date(
            bySettingHour: 23, minute: 0, second: 0,
            of: Self.calendar.date(byAdding: .day, value: -1, to: Self.today)!
        )!
        let morning = Self.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Self.today)!
        let afternoon = Self.calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Self.today)!

        var ledger = Self.ledger([Self.day(1, tokens: 500, cost: 5), Self.day(0, tokens: 300, cost: 3)])
        ledger.sessions = [
            UsageLedger.Session(
                id: "a", name: "a", title: nil, project: UsageProject("Pulse"),
                start: yesterdayLate, end: afternoon, tokens: 600, cost: 6,
                slots: [
                    .init(start: yesterdayLate, tokens: 500, cost: 5),
                    .init(start: afternoon, tokens: 100, cost: 1),
                ]
            ),
            UsageLedger.Session(
                id: "b", name: "b", title: nil, project: UsageProject("Pulse"),
                start: morning, end: morning, tokens: 200, cost: 2,
                slots: [.init(start: morning, tokens: 200, cost: 2)]
            ),
        ]

        let summary = Self.summary([.codex: ledger], overLast: 1)
        #expect(summary.projects.reduce(0) { $0 + $1.tokens } == summary.tokens)
        #expect(summary.projects.first?.cost == summary.cost)
        #expect(summary.projects.first?.tokens == 300)
    }
}
