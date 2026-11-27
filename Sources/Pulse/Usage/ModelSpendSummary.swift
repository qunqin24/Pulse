// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One model's usage, answered from the same ledgers the combined page adds up.
///
/// The combined page ranks models by tokens; this is the drill-down behind one
/// of those rows — and behind one agent's copy of it, since the caller passes a
/// dictionary filtered to that agent.
///
/// **Money is an API-rate estimate for this model, never a share of a day.**
/// Each raw id is priced at its own published rates and the model's figure is
/// the sum of those, so a day's combined cost is never prorated across the
/// models in it. Only the **priced subset** of tokens is added up: a model whose
/// raw id has no price contributes `unpricedTokens` and no money, so a subtotal
/// is never mistaken for the whole. A total of exactly zero from a real zero
/// rate is a reading; no price at all is nil.
///
/// Categories and hours are shown only where the ledger's per-model detail
/// reconciles; otherwise they are nil.
///
/// **A name is a grouping, not a new spelling.** The key is exactly the one the
/// combined list uses, `ledger.modelNames[rawID] ?? rawID`, so a raw id that
/// resolves to a display name and the display name itself are one row — and
/// several raw ids, across several agents, are added rather than aliased into
/// each other. Only `localTranscripts` ledgers count.
struct ModelSpendSummary: Equatable, Sendable {
    /// One calendar day of this model's work.
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int
        /// Classified tokens where the recorded kinds plus the explicit
        /// unclassified remainder reconcile. Nil for missing or broken detail.
        let tally: TokenTally?
        /// The day's money for the **priced subset** of its tokens. Nil where
        /// nothing that day could be priced; a real zero from a zero rate is a
        /// value, not a nil.
        var costBreakdown: TokenCost? = nil

        var cost: Double? { costBreakdown?.total }

        /// Tokens that day with no price behind them, counted here and never
        /// added to `costBreakdown`.
        var unpricedTokens: Int = 0

        /// The source's explicit count without usable category detail.
        var unclassifiedTokens: Int = 0

        var classifiedTally: TokenTally? {
            tokens > 0 && unclassifiedTokens == tokens ? nil : tally
        }

        var id: Date { date }
    }

    /// One agent's share of this model, over the chosen span.
    struct Agent: Identifiable, Equatable, Sendable {
        let agent: SpendAgent
        let tokens: Int
        /// The agent's money for the priced subset of its tokens, nil where it
        /// priced nothing in this model.
        var cost: Double? = nil
        var unpricedTokens: Int = 0

        var id: SpendAgent { agent }
    }

    var name: String = ""
    var tokens: Int = 0
    /// The classified subset. Together with `unclassifiedTokens` it accounts
    /// for the span; nil where contributing detail was missing or broken.
    var tally: TokenTally? = nil
    /// Explicitly unclassified tokens, shown beside a reconciled tally.
    var unclassifiedTokens = 0
    /// Every day in the span, quiet ones included, so the drill-down is the
    /// same calendar shape as the row it came from.
    var days: [Day] = []
    /// Heaviest first, name breaking a tie.
    var agents: [Agent] = []
    /// Tokens by hour of the local day, 0–23. Nil where the quarter-hour
    /// buckets could not be reconciled with the daily totals, so a model does
    /// not inherit another model's — or its agent's whole — time of day.
    var hours: [Int: Int]? = nil
    /// The model's money by kind, summed over the priced subset of every agent
    /// and day in the span. Nil where no contributing raw id had a price, so
    /// an unpriced model is not shown as free.
    var costBreakdown: TokenCost? = nil

    var cost: Double? { costBreakdown?.total }

    /// Tokens in the span with no price behind them. When `cost` is non-nil and
    /// this is more than zero, the figure is a partial estimate.
    var unpricedTokens: Int = 0

    /// Whether a contributing ledger had only session- or report-level timing
    /// for some of its work. The hours may not be drawn when it did.
    var hasAggregateTiming = false

    /// Whether a contributing ledger's counts may be missing. When set, this
    /// model's total in the span is a floor rather than a whole, so the UI says
    /// "partial" rather than under-reporting silently. No tokens are added and
    /// no price changes.
    var hasPartialCounts = false

    /// The model's trend charts: one point a day, or an hour where the span
    /// is one or two days. See `TrendPoint`.
    var trend: [TrendPoint] = []
    var trendIsHourly = false
    /// Over the whole span, as the charts' headings state them. Nil when too
    /// few replies were timed, or a day's cache split cannot be vouched for.
    var averageSpeed: Double? = nil
    var averageFirstToken: TimeInterval? = nil
    var cacheHitRate: Double? = nil

    /// One point of the trend charts. Every figure is nil where nothing may be
    /// said — too few timed replies, a cache split that does not add up, an
    /// hour whose tokens do not reconcile — and the chart leaves a gap there
    /// rather than drawing a zero nobody measured.
    struct TrendPoint: Identifiable, Equatable, Sendable {
        let start: Date
        let tokens: Int?
        let cacheHitRate: Double?
        let tokensPerSecond: Double?
        let firstToken: TimeInterval?
        var id: Date { start }
    }

    /// Fewer timed replies than this in one point and it is left blank: one
    /// or two requests are luck, not a speed. Lower than the 24-hour figure's
    /// `UsageLedger.fewestTimedReplies` because a point is an hour or a day.
    static let fewestTimedPerPoint = 3

    var isEmpty: Bool { tokens == 0 }

    var activeDays: Int { days.count { $0.tokens > 0 } }

    var busiestDay: Day? { days.max { $0.tokens < $1.tokens } }

    /// Adds one model's work up across every agent, over `span` days or all of
    /// it when `span` is nil.
    ///
    /// The cutoff is the calendar's own midnight, the same window
    /// `SpendSummary.of` uses, so a model's "last 7 days" and the page's are
    /// the same seven. All-time starts at this model's first day of actual
    /// use, not at the earliest day any agent's ledger happens to hold.
    ///
    /// **Money is priced per raw id, per day.** The rates are the only source,
    /// the arithmetic is `TokenTally.costBreakdown`, and a contribution counts
    /// only when its own id was priced *and* its category detail adds up to the
    /// tokens counted — otherwise it is a token, not a zero. The check is
    /// **checked**: a negative kind or remainder, or a sum that would overflow,
    /// is broken metadata and is neither priced nor crashed on. Different ids
    /// behind one display name are priced separately before being added.
    ///
    /// **Categories and hours are offered only when they can be reconciled.**
    /// A ledger read before the per-model detail was kept still carries each
    /// day's model totals and so still answers the token question; its
    /// categories and hours come back nil, because reading a model's whole
    /// total as one kind, or as the agent's own time of day, is a number
    /// nobody measured.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        named name: String,
        overLast span: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ModelSpendSummary {
        let today = calendar.startOfDay(for: now)
        let cutoff = span.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }
        return of(ledgers, named: name, from: cutoff, until: nil, now: now, calendar: calendar)
    }

    /// The same, over the calendar days from `cutoff` up to, **not
    /// including**, `upper` — local midnights, either open — as
    /// `SpendSummary.of(_:from:until:)` counts them, so a model opened from a
    /// row of "last month" is the same month.
    static func of(
        _ ledgers: [SpendAgent: UsageLedger],
        named name: String,
        from cutoff: Date?,
        until upper: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ModelSpendSummary {
        let today = calendar.startOfDay(for: now)
        func inside(_ date: Date) -> Bool {
            (cutoff.map { date >= $0 } ?? true) && (upper.map { date < $0 } ?? true)
        }

        var dayTokens: [Date: Int] = [:]
        var dayTally: [Date: TokenTally] = [:]
        var dayTallyComplete: [Date: Bool] = [:]
        var dayCost: [Date: TokenCost] = [:]
        var dayUnpriced: [Date: Int] = [:]
        var dayUnclassified: [Date: Int] = [:]
        var agentTokens: [SpendAgent: Int] = [:]
        var agentCost: [SpendAgent: TokenCost] = [:]
        var agentUnpriced: [SpendAgent: Int] = [:]
        var hourTokens: [Int: Int] = [:]
        // The trend charts' inputs: replies timed per day and per hour, the
        // model's tallies per hour, and the days whose cache split cannot be
        // vouched for (a source with no cache column, partial counts, or
        // tokens no kind claims).
        var dayTiming: [Date: ReplyTiming] = [:]
        var hourTiming: [Date: ReplyTiming] = [:]
        var hourTally: [Date: TokenTally] = [:]
        var cacheUnvouched: Set<Date> = []
        var totalTally = TokenTally()
        var totalCost = TokenCost()
        var totalUnpriced = 0
        var totalUnclassified = 0
        var tallyComplete = true
        var hoursComplete = true
        var pricedAny = false
        var found = false
        var aggregate = false
        var partial = false

        for (agent, ledger) in ledgers {
            guard !Task.isCancelled else { return ModelSpendSummary(name: name) }
            // A ledger that cannot be priced has no place here: a provider's
            // own statistics report one total per model and no categories.
            guard ledger.origin.supportsTokenSpend else { continue }

            // **Reconciled inside one ledger, one day and one raw id at a
            // time.** A global day-total-versus-slot-total check cancels
            // real faults against each other: one agent's overcount covers
            // another agent's missing detail, and two days that swap tokens
            // add to the right sum. Either would draw an hourly profile
            // nobody measured.
            var ledgerDayTokens: [Date: [String: Int]] = [:]
            var ledgerSlotTokens: [Date: [String: Int]] = [:]

            for day in ledger.days {
                guard !Task.isCancelled else { return ModelSpendSummary(name: name) }
                if !inside(day.date) { continue }
                for (rawID, tokens) in day.models
                where tokens > 0 && (ledger.modelNames[rawID] ?? rawID) == name {
                    found = true
                    if ledger.hasAggregateTiming { aggregate = true }
                    if ledger.hasPartialCounts { partial = true }
                    dayTokens[day.date, default: 0] += tokens
                    agentTokens[agent, default: 0] += tokens
                    ledgerDayTokens[day.date, default: [:]][rawID, default: 0] += tokens

                    // **The split must account for every token.** Classified
                    // kinds plus the explicitly unclassified remainder has to
                    // equal the model's total, and every count has to be a
                    // real, non-negative one whose sum fits an `Int`. A
                    // negative count or an overflowing total is broken
                    // metadata, not a legitimate partial: it is neither
                    // categorized nor priced, and it never traps.
                    let modelTally = day.modelTallies[rawID]
                    let rawUnclassified = day.modelUnclassifiedTokens[rawID]
                    let accountsForAll = Self.accountsForAll(
                        tally: modelTally, unclassified: rawUnclassified, tokens: tokens
                    )
                    let unclassified = rawUnclassified ?? 0
                    if !ledger.reportsCacheReads || ledger.hasPartialCounts || modelTally == nil || unclassified != 0 {
                        cacheUnvouched.insert(day.date)
                    }

                    if accountsForAll,
                       let daySum = Self.adding(dayTally[day.date] ?? TokenTally(), modelTally ?? TokenTally()),
                       let totalSum = Self.adding(totalTally, modelTally ?? TokenTally()),
                       Self.checkedTotal(daySum) != nil,
                       Self.checkedTotal(totalSum) != nil {
                        dayTally[day.date] = daySum
                        totalTally = totalSum
                        dayUnclassified[day.date, default: 0] += unclassified
                        totalUnclassified += unclassified
                    } else {
                        tallyComplete = false
                        dayTallyComplete[day.date] = false
                    }

                    // The money is the classified, priced part only; the
                    // unclassified tokens are counted in `unpricedTokens` and
                    // never costed. A real zero rate is still a priced part.
                    if accountsForAll, let modelCost = day.modelCosts[rawID] {
                        pricedAny = true
                        dayCost[day.date] = (dayCost[day.date] ?? TokenCost()) + modelCost
                        totalCost = totalCost + modelCost
                        agentCost[agent, default: TokenCost()] =
                            (agentCost[agent] ?? TokenCost()) + modelCost
                        dayUnpriced[day.date, default: 0] += unclassified
                        totalUnpriced += unclassified
                        agentUnpriced[agent, default: 0] += unclassified
                    } else {
                        // Counted, never costed, and never patched to a zero.
                        dayUnpriced[day.date, default: 0] += tokens
                        totalUnpriced += tokens
                        agentUnpriced[agent, default: 0] += tokens
                    }
                }
            }

            // The time of day survives only in the quarter-hour buckets, and
            // only per model where the reader kept it. A slot with no model
            // detail contributes nothing here — and then the reconciliation
            // below fails, which is the point.
            for slot in ledger.slots {
                guard !Task.isCancelled else { return ModelSpendSummary(name: name) }
                if !inside(slot.start) { continue }
                for (rawID, modelTally) in slot.models
                where (ledger.modelNames[rawID] ?? rawID) == name {
                    // A slot whose model tally is broken contributes no hours:
                    // reading its total would trap, and a negative or
                    // overflowing count is not a time of day.
                    guard let slotTokens = Self.checkedTotal(modelTally), slotTokens > 0 else {
                        continue
                    }
                    let date = calendar.startOfDay(for: slot.start)
                    ledgerSlotTokens[date, default: [:]][rawID, default: 0] += slotTokens
                    hourTokens[calendar.component(.hour, from: slot.start), default: 0] += slotTokens
                    if let hour = calendar.dateInterval(of: .hour, for: slot.start)?.start,
                       let sum = Self.adding(hourTally[hour] ?? TokenTally(), modelTally) {
                        hourTally[hour] = sum
                    }
                }
                for (rawID, timing) in slot.timings where (ledger.modelNames[rawID] ?? rawID) == name {
                    let date = calendar.startOfDay(for: slot.start)
                    dayTiming[date] = (dayTiming[date] ?? ReplyTiming()) + timing
                    if let hour = calendar.dateInterval(of: .hour, for: slot.start)?.start {
                        hourTiming[hour] = (hourTiming[hour] ?? ReplyTiming()) + timing
                    }
                }
            }

            // Every day of this ledger that carried the model must have slot
            // buckets adding to the same per-raw-id figure. Empty ledgers
            // compare equal and change nothing.
            if ledgerDayTokens != ledgerSlotTokens { hoursComplete = false }
        }

        guard found else { return ModelSpendSummary(name: name) }

        var summary = ModelSpendSummary()
        summary.name = name
        summary.tokens = dayTokens.values.reduce(0, +)

        // Every contributing model's split is present and matches its own
        // daily total, and the pieces add up to the total on screen. The sum
        // is checked so an aggregate whose kinds no longer fit an `Int` is
        // withheld rather than crashed on.
        if tallyComplete, totalTally.accountsFor(tokens: summary.tokens, unclassified: totalUnclassified) {
            summary.tally = totalTally
            summary.unclassifiedTokens = totalUnclassified
        }

        // The hour series is the model's own only where every ledger's buckets
        // reconcile with its days.
        if hoursComplete {
            summary.hours = hourTokens
        }

        // Money is the priced subset; nil when nothing in scope had a price.
        if pricedAny {
            summary.costBreakdown = totalCost
        }
        summary.unpricedTokens = totalUnpriced
        summary.hasAggregateTiming = aggregate
        summary.hasPartialCounts = partial

        summary.agents = agentTokens
            .map { agent, tokens in
                Agent(
                    agent: agent,
                    tokens: tokens,
                    cost: agentCost[agent]?.total,
                    unpricedTokens: agentUnpriced[agent] ?? 0
                )
            }
            .sorted {
                $0.tokens == $1.tokens
                    ? $0.agent.displayName < $1.agent.displayName
                    : $0.tokens > $1.tokens
            }

        // Every day in the window, quiet ones included: a drill-down should be
        // the same calendar as the row it was opened from.
        let first = cutoff ?? dayTokens.keys.min() ?? today
        let last = upper.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
            ?? max(today, dayTokens.keys.max() ?? today)
        // As `SpendSummary`'s: a bounded span starts where it was asked to.
        var cursor = upper == nil ? min(first, last) : first
        while cursor <= last {
            guard !Task.isCancelled else { return ModelSpendSummary(name: name) }
            let tokens = dayTokens[cursor] ?? 0
            let tally: TokenTally?
            if tokens == 0 {
                // A quiet day has nothing missing: its split is an empty one.
                tally = TokenTally()
            } else if dayTallyComplete[cursor] ?? true {
                tally = dayTally[cursor] ?? TokenTally()
            } else {
                tally = nil
            }
            summary.days.append(Day(
                date: cursor,
                tokens: tokens,
                tally: tally,
                costBreakdown: dayCost[cursor],
                unpricedTokens: dayUnpriced[cursor] ?? 0,
                unclassifiedTokens: tally == nil ? 0 : dayUnclassified[cursor] ?? 0
            ))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        summary.addTrend(
            dayTiming: dayTiming, hourTiming: hourTiming, hourTally: hourTally,
            cacheUnvouched: cacheUnvouched, hoursReconcile: hoursComplete, now: now, calendar: calendar
        )
        return summary
    }

    // MARK: - Trend

    /// Output speed: all output over all timed seconds, so a long reply
    /// weighs what it wrote. First token: the mean over turns.
    static func speed(_ timing: ReplyTiming?, fewest: Int) -> Double? {
        guard let timing, timing.replies >= fewest, timing.seconds > 0 else { return nil }
        return Double(timing.outputTokens) / timing.seconds
    }

    static func firstToken(_ timing: ReplyTiming?, fewest: Int) -> TimeInterval? {
        guard let timing, timing.firstTokenTurns >= fewest else { return nil }
        return timing.firstTokenSeconds / Double(timing.firstTokenTurns)
    }

    /// Cache reads over everything read in, as `UsageLedger.cacheHitRate`.
    static func cacheHitRate(_ tally: TokenTally?) -> Double? {
        guard let tally, !tally.reportsNoCache else { return nil }
        let input = tally.input + tally.cacheWrite + tally.cacheRead
        return input > 0 ? Double(tally.cacheRead) / Double(input) : nil
    }

    private mutating func addTrend(
        dayTiming: [Date: ReplyTiming], hourTiming: [Date: ReplyTiming], hourTally: [Date: TokenTally],
        cacheUnvouched: Set<Date>, hoursReconcile: Bool, now: Date, calendar: Calendar
    ) {
        let fewest = Self.fewestTimedPerPoint
        let inSpan = Set(days.map(\.date))
        let timed = dayTiming.filter { inSpan.contains($0.key) }.values.reduce(ReplyTiming(), +)
        averageSpeed = Self.speed(timed, fewest: UsageLedger.fewestTimedReplies)
        averageFirstToken = Self.firstToken(timed, fewest: UsageLedger.fewestTimedReplies)
        let active = days.filter { $0.tokens > 0 }.map(\.date)
        if active.allSatisfy({ !cacheUnvouched.contains($0) }) { cacheHitRate = Self.cacheHitRate(tally) }

        // A day or two is one line of hours; anything longer, one of days.
        trendIsHourly = days.count <= 2
        guard trendIsHourly else {
            trend = days.map { day in
                TrendPoint(
                    start: day.date,
                    tokens: day.tokens,
                    cacheHitRate: day.tokens > 0 && !cacheUnvouched.contains(day.date) ? Self.cacheHitRate(day.tally) : nil,
                    tokensPerSecond: Self.speed(dayTiming[day.date], fewest: fewest),
                    firstToken: Self.firstToken(dayTiming[day.date], fewest: fewest)
                )
            }
            return
        }
        let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        trend = days.flatMap { day -> [TrendPoint] in
            // The day's own hours: 23 when the clocks go forward, 25 when they
            // go back. A fixed 24 dropped the repeated hour's tokens from the
            // chart while the day's total kept them (review, New York).
            let end = calendar.dateInterval(of: .day, for: day.date)?.end
                ?? day.date.addingTimeInterval(24 * 3600)
            return (0..<25).compactMap { offset in
                guard let hour = calendar.date(byAdding: .hour, value: offset, to: day.date),
                      hour < end, hour <= thisHour
                else { return nil }
                let tally = hourTally[hour]
                let tokens = tally.flatMap(Self.checkedTotal) ?? 0
                return TrendPoint(
                    start: hour,
                    // An hour whose quarter-hours do not add up to the day is
                    // not drawn: nobody measured it.
                    tokens: hoursReconcile ? tokens : nil,
                    cacheHitRate: tokens > 0 && !cacheUnvouched.contains(day.date) ? Self.cacheHitRate(tally) : nil,
                    tokensPerSecond: Self.speed(hourTiming[hour], fewest: fewest),
                    firstToken: Self.firstToken(hourTiming[hour], fewest: fewest)
                )
            }
        }
    }

    // MARK: - Checked metadata

    /// Whether a raw id's classified kinds and its explicitly unclassified
    /// remainder account for exactly `tokens`.
    ///
    /// **Checked, not assumed.** A negative kind, a negative remainder or a
    /// sum that would overflow is broken metadata: it must not be repaired to
    /// zero and it must not trap, so it accounts for nothing and the tokens
    /// fall through to `unpricedTokens`. Only a genuine split — every piece
    /// non-negative and the whole fitting an `Int` — is priced.
    private static func accountsForAll(
        tally: TokenTally?,
        unclassified: Int?,
        tokens: Int
    ) -> Bool {
        (tally ?? TokenTally()).accountsFor(tokens: tokens, unclassified: unclassified ?? 0)
    }

    /// A tally's own total, or nil when any kind is negative or the sum does
    /// not fit an `Int`. Never traps on hostile metadata.
    private static func checkedTotal(_ tally: TokenTally) -> Int? {
        var total = 0
        for value in [tally.input, tally.cacheWrite, tally.cacheRead, tally.output] {
            guard value >= 0 else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }

    /// Adds two tallies without trapping, or nil when any kind overflows.
    private static func adding(_ lhs: TokenTally, _ rhs: TokenTally) -> TokenTally? {
        guard
            let input = Self.adding(lhs.input, rhs.input),
            let cacheWrite = Self.adding(lhs.cacheWrite, rhs.cacheWrite),
            let cacheRead = Self.adding(lhs.cacheRead, rhs.cacheRead),
            let output = Self.adding(lhs.output, rhs.output),
            let hourWrites = Self.adding(lhs.cacheWrite1h, rhs.cacheWrite1h),
            let silent = Self.adding(lhs.repliesWithoutCacheFields, rhs.repliesWithoutCacheFields)
        else { return nil }
        return TokenTally(
            input: input, cacheWrite: cacheWrite, cacheRead: cacheRead, output: output,
            cacheWrite1h: hourWrites, repliesWithoutCacheFields: silent
        )
    }

    private static func adding(_ lhs: Int, _ rhs: Int) -> Int? {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : sum
    }

    // MARK: - Sorting

    /// The day table's columns, and what it can be sorted by. Lives with the
    /// summary rather than the view: ordering is data, and the same question is
    /// asked of the same rows whoever asks it.
    enum DayColumn: String, CaseIterable, Identifiable, Sendable {
        case date
        /// New input, cache writes included (`TokenTally.fresh`).
        case fresh
        case cacheRead
        case output
        case unclassified
        case total
        case cost

        var id: String { rawValue }
    }

    /// The day rows in the order a column asks for.
    ///
    /// **A missing category or price is not a zero.** A day whose split was
    /// never recorded has nil category columns; a day that priced nothing has a
    /// nil cost. Sorting those nils among the zeroes would file "not recorded"
    /// under "none" and hide the difference. So a nil cell sorts **last
    /// whichever way the column is turned**, a known zero sorts where zero
    /// belongs, and equal values keep a deterministic order broken by date.
    ///
    /// **Each column keeps its own type.** Token counts are compared as `Int`
    /// and money as `Double`; widening a token count to `Double` would make two
    /// adjacent values above 2^53 compare equal and fall back to the date,
    /// which is a wrong order rather than a rounding. The generic ranker below
    /// is shared only for the nil-last and tie rules.
    static func sorted(_ days: [Day], by column: DayColumn, ascending: Bool, cacheUnreported: Bool = false) -> [Day] {
        /// Equal values keep their place by date, so two runs over one table
        /// agree rather than shuffling.
        func byDate(_ lhs: Day, _ rhs: Day) -> Bool {
            ascending ? lhs.date < rhs.date : lhs.date > rhs.date
        }

        /// One nil-last comparison over any comparable value, so a token
        /// column never has to be widened to reuse the money column's rules.
        func rank<T: Comparable>(_ left: T?, _ right: T?, _ lhs: Day, _ rhs: Day) -> Bool {
            switch (left, right) {
            case (nil, nil):
                return byDate(lhs, rhs)
            // nils last, in both directions.
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (left?, right?):
                guard left == right else { return ascending ? left < right : left > right }
                return byDate(lhs, rhs)
            }
        }

        switch column {
        // Every day is equally "no value", so only the date tie-break orders
        // this column.
        case .date:
            return days.sorted(by: byDate)
        case .fresh:
            return days.sorted { rank($0.classifiedTally?.fresh, $1.classifiedTally?.fresh, $0, $1) }
        case .cacheRead:
            // A store with no cache column has hits that were never recorded.
            func hits(_ day: Day) -> Int? { cacheUnreported && day.classifiedTally?.cacheRead == 0 ? nil : day.classifiedTally?.cacheRead }
            return days.sorted { rank(hits($0), hits($1), $0, $1) }
        case .output:
            return days.sorted { rank($0.classifiedTally?.output, $1.classifiedTally?.output, $0, $1) }
        case .unclassified:
            return days.sorted {
                rank($0.tally == nil ? nil : $0.unclassifiedTokens, $1.tally == nil ? nil : $1.unclassifiedTokens, $0, $1)
            }
        case .total:
            return days.sorted { rank($0.tokens, $1.tokens, $0, $1) }
        case .cost:
            return days.sorted { rank($0.cost, $1.cost, $0, $1) }
        }
    }
}
