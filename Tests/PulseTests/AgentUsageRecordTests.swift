import Foundation
import Testing
@testable import Pulse

/// The shared builder the native readers feed: decoded **incremental** records
/// in, one `UsageLedger` out, through the same pricing path every transcript
/// reader uses.
///
/// Every date is fixed and computed on a UTC calendar, so the day keys cannot
/// depend on the machine's timezone, and nothing here touches a user store.
@Suite("Agent usage records")
struct AgentUsageRecordTests {
    private static let prices: [String: ModelPrice] = [
        "priced": ModelPrice(input: 1_000, output: 10_000, cacheRead: 100, cacheWrite: 1_000, name: "Priced")
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_789_372_800)

    private static func at(daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func record(
        _ model: String,
        _ tally: TokenTally,
        at date: Date,
        unclassified: Int = 0,
        aggregate: Bool = false,
        partial: Bool = false,
        session: String? = nil,
        name: String? = nil,
        title: String? = nil,
        project: String? = nil,
        dedup: String? = nil
    ) -> AgentUsageRecord {
        AgentUsageRecord(
            timestamp: date, model: model, tally: tally,
            sessionID: session, sessionName: name, title: title,
            project: project, deduplicationID: dedup,
            unclassifiedTokens: unclassified, isAggregate: aggregate,
            isPartial: partial
        )
    }

    private static func slotSums(_ session: UsageLedger.Session) -> (tokens: Int, cost: Double) {
        session.slots.reduce(into: (tokens: 0, cost: 0.0)) { running, slot in
            running.tokens += slot.tokens
            running.cost += slot.cost
        }
    }

    // MARK: - Bucketing

    @Test("Incremental records roll into the day keys and each session's own buckets")
    func recordsBecomeDaysAndSessions() throws {
        let records = [
            Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9),
                        session: "s1", name: "one"),
            Self.record("priced", TokenTally(input: 50), at: Self.at(daysAgo: 0, hour: 10),
                        session: "s2", name: "two"),
            Self.record("priced", TokenTally(input: 900), at: Self.at(daysAgo: 1, hour: 11),
                        session: "s1", name: "one"),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "opencode", calendar: Self.calendar
        )

        #expect(ledger.days.count == 2)
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 1050)
        #expect(abs(ledger.days.reduce(0.0) { $0 + $1.cost } - 1.05) < 1e-9)

        let first = try #require(ledger.sessions.first { $0.id == "opencode#s1" })
        #expect(first.tokens == 1000)
        #expect(abs(first.cost - 1.0) < 1e-9)
        #expect(first.slots.count == 2)
        // The session's buckets must add up to its own totals, or a span would
        // be windowing a different number than the row shows.
        let sums = Self.slotSums(first)
        #expect(sums.tokens == first.tokens)
        #expect(abs(sums.cost - first.cost) < 1e-9)

        // Two session ids are two sessions, not one.
        #expect(ledger.sessions.count == 2)
        #expect(ledger.sessions.contains { $0.id == "opencode#s2" })
    }

    // MARK: - Deduplication

    @Test("Only an explicit id folds a message; identical work still counts")
    func explicitDeduplicationOnly() {
        let at = Self.at(daysAgo: 0, hour: 9)
        let records = [
            // The same message present in two roots.
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "m1"),
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "m1"),
            // A different message that happens to carry the same counts.
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "m2"),
            // No id: every occurrence is its own request, however alike.
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1"),
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1"),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        // m1 once, m2 once, the two unidentified twice.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 400)
        #expect(ledger.sessions.first?.tokens == 400)
    }

    // MARK: - What is skipped, and what is counted without money

    @Test("Empty models and empty tallies are skipped; an unpriced model is counted, not costed")
    func filteringAndUnpriced() {
        let at = Self.at(daysAgo: 0, hour: 9)
        let records = [
            Self.record("", TokenTally(input: 100), at: at),
            Self.record("priced", TokenTally(), at: at),
            Self.record("mystery", TokenTally(input: 10), at: at),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 10)
        #expect(ledger.days.reduce(0.0) { $0 + $1.cost } == 0)
        #expect(ledger.days.first?.unpricedTokens == 10)
        #expect(ledger.unpricedModels == ["mystery"])
        // No session was named, so none is invented.
        #expect(ledger.sessions.isEmpty)
    }

    @Test("No usable records is an empty ledger, not a zero")
    func noUsableRecordsIsEmpty() {
        let none = AgentUsageLedger.build(
            [], prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(none.days.isEmpty)
        #expect(none.sessions.isEmpty)

        let onlyInvalid = AgentUsageLedger.build(
            [Self.record("", TokenTally(input: 5), at: Date())],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(onlyInvalid.days.isEmpty)
    }

    // MARK: - Session metadata

    @Test("A session keeps only the name, title and project it was given")
    func sessionMetadataIsExplicit() throws {
        let records = [
            Self.record("priced", TokenTally(input: 10), at: Self.at(daysAgo: 0, hour: 9),
                        session: "id-1", name: "slug", title: "Fix the ring", project: "Pulse")
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "opencode", calendar: Self.calendar
        )

        let session = try #require(ledger.sessions.first)
        #expect(session.id == "opencode#id-1")
        #expect(session.name == "slug")
        #expect(session.title == "Fix the ring")
        #expect(session.project?.name == "Pulse")
    }

    @Test("A record with no session id counts toward totals and creates no session row")
    func sessionlessRecordsDoNotFabricateASession() {
        let ledger = AgentUsageLedger.build(
            [
                Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9)),
                Self.record("priced", TokenTally(input: 900), at: Self.at(daysAgo: 1, hour: 10)),
            ],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 1000)
        #expect(ledger.sessions.isEmpty)
    }

    // MARK: - Through the production chain

    @Test("Built records reconcile through SpendSummary and ModelSpendSummary")
    func productionChainReconciles() throws {
        let records = [
            Self.record(
                "priced",
                TokenTally(input: 100, cacheWrite: 20, cacheRead: 30, output: 40),
                at: Self.at(daysAgo: 0, hour: 9), session: "s1", name: "one"
            ),
            Self.record(
                "priced", TokenTally(input: 900),
                at: Self.at(daysAgo: 1, hour: 10), session: "s1", name: "one"
            ),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices,
            namespace: SpendAgent.openCode.rawValue, calendar: Self.calendar
        )

        let summary = SpendSummary.of(
            [.openCode: ledger], overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(summary.tokens == 1090)
        // 100*.001 + 20*.001 + 30*.0001 + 40*.01 + 900*.001 = 1.423
        #expect(abs(summary.cost - 1.423) < 1e-9)
        #expect(summary.tally == TokenTally(input: 1000, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(summary.sessions.count == 1)
        #expect(summary.sessions.first?.session.tokens == 1090)
        #expect(abs((summary.sessions.first?.session.cost ?? -1) - 1.423) < 1e-9)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: nil, now: Self.now, calendar: Self.calendar
        )
        #expect(model.tokens == 1090)
        #expect(model.tally == TokenTally(input: 1000, cacheWrite: 20, cacheRead: 30, output: 40))
        #expect(abs((model.cost ?? -1) - 1.423) < 1e-9)
        #expect(model.days.count == 2)
        let hours = try #require(model.hours)
        #expect(hours == [9: 190, 10: 900])

        // A one-day window keeps only today's record and the session's own
        // in-window half — the totals above and the row agree.
        let today = SpendSummary.of(
            [.openCode: ledger], overLast: 1, now: Self.now, calendar: Self.calendar
        )
        #expect(today.tokens == 190)
        #expect(today.sessions.first?.session.tokens == 190)
    }

    // MARK: - Blank identities

    @Test("Blank values are absent, not shared keys")
    func blankValuesAreAbsent() {
        let at = Self.at(daysAgo: 0, hour: 9)
        let records = [
            // A blank model names nothing and is skipped.
            Self.record("", TokenTally(input: 100), at: at),
            Self.record("   ", TokenTally(input: 100), at: at),
            // Blank dedup ids are no ids: the two are not folded together.
            Self.record("priced", TokenTally(input: 100), at: at, dedup: ""),
            Self.record("priced", TokenTally(input: 100), at: at, dedup: "   "),
            // A blank session id counts but makes no session.
            Self.record("priced", TokenTally(input: 100), at: at, session: ""),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        // Three priced records survive: the two blank-id ones and the
        // blank-session one. Neither blank model counts.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 300)
        #expect(ledger.sessions.isEmpty)
    }

    @Test("An explicit deduplication id still folds; a blank one is each its own record")
    func explicitIdStillFoldsPastBlanks() {
        let at = Self.at(daysAgo: 0, hour: 9)
        let records = [
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "m1"),
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "m1"),
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "  "),
            Self.record("priced", TokenTally(input: 100), at: at, session: "s1", dedup: "  "),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        // m1 once, then the two whitespace ids counted separately.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 300)
    }

    @Test("Blank session metadata is nil, and the id is the name's fallback")
    func blankSessionMetadataIsNil() throws {
        let records = [
            Self.record("priced", TokenTally(input: 10), at: Self.at(daysAgo: 0, hour: 9),
                        session: "id-1", name: "  ", title: "\n", project: " ")
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        let session = try #require(ledger.sessions.first)
        #expect(session.name == "id-1")
        #expect(session.title == nil)
        #expect(session.project == nil)
    }

    // MARK: - Unclassified tokens

    @Test("A bare total is counted, never invented into a kind, and never priced")
    func bareTotalIsNotInvented() throws {
        let ledger = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(), at: Self.at(daysAgo: 0, hour: 9),
                         unclassified: 500, session: "s1")],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        let day = try #require(ledger.days.first { $0.tokens > 0 })
        #expect(day.tokens == 500)
        #expect(day.unpricedTokens == 500)
        #expect(day.models["priced"] == 500)
        #expect(day.modelUnclassifiedTokens["priced"] == 500)
        // Never placed into a kind, and never costed even though the model has
        // a published price.
        #expect(day.modelTallies["priced"] == nil)
        #expect(day.tally.total == 0)
        #expect(day.cost == 0)
        #expect(day.modelCosts["priced"] == nil)

        let session = try #require(ledger.sessions.first)
        #expect(session.tokens == 500)
        #expect(session.cost == 0)
        // An event record's unknown tokens still reach their hour bucket...
        #expect(ledger.slots.first?.tokens == 500)

        // ...but the model's categories cannot, so the drill-down withholds
        // the split and the money while keeping the count. The drill-down is
        // reached by the published name, which the unknown-only id now takes
        // even though its tokens were never priced.
        #expect(ledger.modelNames["priced"] == "Priced")
        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: 7,
            now: Self.now, calendar: Self.calendar
        )
        #expect(model.tokens == 500)
        #expect(model.tally == nil)
        #expect(model.cost == nil)
        #expect(model.unpricedTokens == 500)
    }

    @Test("A mixed model keeps its classified cost and counts the remainder unpriced")
    func mixedKnownAndUnknownKeepCost() throws {
        let ledger = AgentUsageLedger.build(
            [
                Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9),
                            session: "s1"),
                Self.record("priced", TokenTally(), at: Self.at(daysAgo: 0, hour: 9),
                            unclassified: 50, session: "s1"),
            ],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        let day = try #require(ledger.days.first { $0.tokens > 0 })
        #expect(day.tokens == 150)
        #expect(day.models["priced"] == 150)
        #expect(day.modelTallies["priced"] == TokenTally(input: 100))
        #expect(day.modelUnclassifiedTokens["priced"] == 50)
        // 100 input at $1000/M.
        #expect(abs((day.modelCosts["priced"]?.total ?? -1) - 0.1) < 1e-12)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: 7,
            now: Self.now, calendar: Self.calendar
        )
        #expect(model.tokens == 150)
        #expect(abs((model.cost ?? -1) - 0.1) < 1e-12)
        #expect(model.unpricedTokens == 50)
        // The split cannot stand for the whole, so it is withheld.
        #expect(model.tally == nil)
    }

    @Test("A negative or overflowing record is skipped whole; the rest of the run is kept")
    func hostileRecordsAreRejectedWithoutFabrication() {
        let at = Self.at(daysAgo: 0, hour: 9)
        let records = [
            // A legitimate record that must survive.
            Self.record("priced", TokenTally(input: 10), at: at),
            // A record whose four kinds do not fit an Int: it used to saturate
            // the whole ledger to Int.max.
            Self.record("priced", TokenTally(input: Int.max, output: 1), at: at),
            // A negative unclassified remainder: it used to be clamped to zero
            // and counted anyway.
            Self.record("priced", TokenTally(input: 5), at: at, unclassified: -3),
        ]

        let ledger = AgentUsageLedger.build(
            records, prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        // The two hostile records are gone, and the valid ten is exactly what
        // is left — not a saturated Int.max and not a seven-token clamp.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 10)
        #expect(abs(ledger.days.reduce(0.0) { $0 + $1.cost } - 0.01) < 1e-12)
        #expect(ledger.days.allSatisfy { $0.tokens != Int.max })
    }

    @Test("An unknown-only raw id takes its published name but never its price")
    func unknownOnlyModelKeepsItsName() throws {
        let ledger = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(), at: Self.at(daysAgo: 0, hour: 9), unclassified: 500)],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        // The name is a grouping, not a price: the model is still unknown-only
        // for money, and it is not called "no published price" either.
        #expect(ledger.modelNames["priced"] == "Priced")
        #expect(ledger.unpricedModels.isEmpty)
        let day = try #require(ledger.days.first { $0.tokens > 0 })
        #expect(day.cost == 0)
        #expect(day.modelCosts["priced"] == nil)
    }

    @Test("An unknown-only raw id with no rate at all is named as unpriced")
    func unknownOnlyWithoutRateIsUnpriced() {
        let ledger = AgentUsageLedger.build(
            [Self.record("mystery", TokenTally(), at: Self.at(daysAgo: 0, hour: 9), unclassified: 500)],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        #expect(ledger.modelNames["mystery"] == nil)
        #expect(ledger.unpricedModels == ["mystery"])
    }

    @Test("Broken data without unclassified metadata is not mistaken for a legitimate partial")
    func brokenSplitStaysBroken() throws {
        // The day accounts 500 but only 100 is classified and nothing says the
        // rest is unclassified, so the split is broken and nothing is priced.
        let broken = UsageLedger(
            days: [
                LedgerDay(
                    date: Self.calendar.startOfDay(for: Self.at(daysAgo: 0, hour: 9)),
                    tokens: 500, cost: 0, unpricedTokens: 0,
                    models: ["alpha": 500], tally: TokenTally(input: 100),
                    modelTallies: ["alpha": TokenTally(input: 100)]
                )
            ],
            earliest: nil, unpricedModels: [], modelNames: ["alpha": "Alpha"], slots: []
        )
        let summary = ModelSpendSummary.of(
            [.openCode: broken], named: "Alpha", overLast: 7,
            now: Self.now, calendar: Self.calendar
        )
        #expect(summary.tokens == 500)
        #expect(summary.tally == nil)
        #expect(summary.cost == nil)
        #expect(summary.unpricedTokens == 500)
    }

    // MARK: - Origin

    @Test("Imported records enter the spend summaries; provider statistics do not")
    func importedOriginEntersSummaries() {
        let imported = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9))],
            prices: Self.prices, namespace: "a", calendar: Self.calendar,
            origin: .importedRecords
        )
        #expect(imported.origin == .importedRecords)
        #expect(imported.origin.supportsTokenSpend)

        let combined = SpendSummary.of(
            [.openCode: imported], overLast: 7, now: Self.now, calendar: Self.calendar
        )
        #expect(combined.tokens == 100)
        #expect(abs(combined.cost - 0.1) < 1e-12)
        #expect(
            !ModelSpendSummary.of(
                [.openCode: imported], named: "Priced", overLast: 7,
                now: Self.now, calendar: Self.calendar
            ).isEmpty
        )

        var statistics = imported
        statistics.origin = .providerStatistics
        #expect(!statistics.origin.supportsTokenSpend)
        #expect(
            SpendSummary.of([.openCode: statistics], overLast: 7, now: Self.now, calendar: Self.calendar).isEmpty
        )
        #expect(
            ModelSpendSummary.of(
                [.openCode: statistics], named: "Priced", overLast: 7,
                now: Self.now, calendar: Self.calendar
            ).isEmpty
        )
    }

    @Test("Origin is a Codable string")
    func originIsCodable() throws {
        let encoded = try JSONEncoder().encode(UsageLedger.Origin.importedRecords)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"importedRecords\"")
        #expect(try JSONDecoder().decode(UsageLedger.Origin.self, from: encoded) == .importedRecords)
    }

    // MARK: - Aggregate timing

    @Test("An aggregate record keeps its day, including in its session, but no hour bucket")
    func aggregateTimingHasNoHours() throws {
        let ledger = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9),
                         unclassified: 400, aggregate: true, session: "s1")],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        #expect(ledger.hasAggregateTiming)
        let day = try #require(ledger.days.first { $0.tokens > 0 })
        #expect(day.tokens == 500)
        #expect(day.models["priced"] == 500)
        #expect(day.modelTallies["priced"] == TokenTally(input: 100))
        #expect(day.modelUnclassifiedTokens["priced"] == 400)
        // No quarter-hour bucket was fabricated for the aggregate work.
        #expect(ledger.slots.isEmpty)

        let session = try #require(ledger.sessions.first)
        #expect(session.tokens == 500)
        // Known calendar dates survive without inventing an hour series.
        #expect(session.slots.isEmpty)
        #expect(session.days == [.init(date: day.date, tokens: 500, cost: session.cost)])
        #expect(abs(session.cost - 0.1) < 1e-12)

        let combined = SpendSummary.of(
            [.openCode: ledger], overLast: 7, now: Self.now, calendar: Self.calendar
        )
        #expect(combined.tokens == 500)
        #expect(combined.hasAggregateTiming)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: 7,
            now: Self.now, calendar: Self.calendar
        )
        #expect(model.tokens == 500)
        #expect(model.hasAggregateTiming)
        #expect(model.hours == nil)
        #expect(abs((model.cost ?? -1) - 0.1) < 1e-12)
        #expect(model.unpricedTokens == 400)
        #expect(model.tally == nil)
    }

    @Test("Aggregate and mixed-timing sessions window by their known days", arguments: [true, false])
    func aggregateSessionWindows(onlyAggregate: Bool) throws {
        let ledger = AgentUsageLedger.build(
            [
                Self.record("priced", TokenTally(input: 900), at: Self.at(daysAgo: 1, hour: 9),
                            aggregate: true, session: "s", project: "Pulse"),
                Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9),
                            unclassified: 50, aggregate: onlyAggregate, session: "s", project: "Pulse"),
            ],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(ledger.sessions.first?.slots.isEmpty == true)
        #expect(ledger.sessions.first?.days.count == 2)
        let today = SpendSummary.of([.cursor: ledger], overLast: 1, now: Self.now, calendar: Self.calendar)
        #expect(today.tokens == 150)
        #expect(today.sessions.first?.session.tokens == today.tokens)
        #expect(today.projects.first?.tokens == today.tokens)
        #expect(today.sessions.first?.session.cost == today.cost)
        #expect(today.projects.first?.cost == today.cost)
        #expect(today.hasAggregateTiming)
        let all = SpendSummary.of([.cursor: ledger], overLast: nil, now: Self.now, calendar: Self.calendar)
        #expect(all.sessions.first?.session.tokens == 1050)
    }

    // MARK: - Partial counts

    @Test("A partial record marks the ledger and both summaries, without changing a number")
    func partialFlagPropagates() throws {
        let ledger = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9),
                         partial: true, session: "s1")],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )

        #expect(ledger.hasPartialCounts)
        // The reported count is kept exactly; the flag invents no remainder.
        #expect(ledger.days.reduce(0) { $0 + $1.tokens } == 100)
        #expect(abs(ledger.days.reduce(0.0) { $0 + $1.cost } - 0.1) < 1e-12)

        let combined = SpendSummary.of(
            [.openCode: ledger], overLast: 7, now: Self.now, calendar: Self.calendar
        )
        #expect(combined.hasPartialCounts)
        #expect(combined.tokens == 100)

        let model = ModelSpendSummary.of(
            [.openCode: ledger], named: "Priced", overLast: 7,
            now: Self.now, calendar: Self.calendar
        )
        #expect(model.hasPartialCounts)
        #expect(model.tokens == 100)
        #expect(abs((model.cost ?? -1) - 0.1) < 1e-12)
    }

    @Test("A skipped partial record makes nothing partial and produces no usage")
    func partialOnSkippedRecordIsInert() {
        // An empty model and a zero-total record are skipped whole, so a flag
        // on them must not manufacture a partial ledger or any usage.
        let none = AgentUsageLedger.build(
            [Self.record("", TokenTally(input: 100), at: Self.at(daysAgo: 0, hour: 9), partial: true)],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(!none.hasPartialCounts)
        #expect(none.days.isEmpty)

        let zero = AgentUsageLedger.build(
            [Self.record("priced", TokenTally(), at: Self.at(daysAgo: 0, hour: 9), partial: true)],
            prices: Self.prices, namespace: "a", calendar: Self.calendar
        )
        #expect(!zero.hasPartialCounts)
        #expect(
            !SpendSummary.of(
                [.openCode: zero], overLast: 7, now: Self.now, calendar: Self.calendar
            ).hasPartialCounts
        )
        #expect(
            !ModelSpendSummary.of(
                [.openCode: zero], named: "Priced", overLast: 7,
                now: Self.now, calendar: Self.calendar
            ).hasPartialCounts
        )
    }
}
