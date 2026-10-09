// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension Recap.Period {
    /// The calendar days the period covers: its first local midnight and the
    /// midnight that ends it (exclusive). Nil for a month outside 1...12, which
    /// names no span.
    func bounds(calendar: Calendar) -> (start: Date, end: Date)? {
        switch self {
        case .month(let year, let month):
            guard (1...12).contains(month),
                  let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return (start, end)
        case .year(let year):
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
            return (start, end)
        }
    }

    /// The period before this one: the month before (December of the year
    /// before, from January), or the year before.
    var previous: Recap.Period {
        switch self {
        case .month(let year, let month):
            month > 1 ? .month(year: year, month: month - 1) : .month(year: year - 1, month: 12)
        case .year(let year):
            .year(year - 1)
        }
    }
}

extension Recap.Persona {
    /// The band of the day most of the work fell in, from tokens by local hour
    /// (24 entries, 0 = midnight). **Each case is a plain majority** — more than
    /// half of the tokens — so at most one can hold, checked in this order:
    ///
    /// - `nightOwl`: 21:00 through 04:59
    /// - `earlyBird`: 05:00 through 09:59
    /// - `dayShift`: 10:00 through 17:59
    /// - `allDay`: none of those holds (18:00–20:59 is a band of its own that
    ///   cannot win alone, on purpose: an evening person is an owl or all-day)
    ///
    /// Nil where there is no shape to read: not 24 hours, or no tokens in them.
    static func of(hours: [Int]) -> Recap.Persona? {
        guard hours.count == 24 else { return nil }
        let total = hours.reduce(0, +)
        guard total > 0 else { return nil }
        func share(_ range: Range<Int>) -> Double {
            Double(range.reduce(0) { $0 + hours[$1] }) / Double(total)
        }
        let night = share(21..<24) + share(0..<5)
        if night > 0.5 { return .nightOwl }
        if share(5..<10) > 0.5 { return .earlyBird }
        if share(10..<18) > 0.5 { return .dayShift }
        return .allDay
    }
}

extension Recap {
    /// The tokens-by-hour band that counts as late: 21:00 through 04:59.
    static let lateHours = Set([21, 22, 23, 0, 1, 2, 3, 4])
    /// Work before this local hour, after midnight, belongs to the night before.
    static let nightEndsAtHour = 5

    /// A calendar month's or year's recap from the Token spend ledgers — the
    /// same input `SpendSummary.of` takes.
    ///
    /// **Everything is added up by `SpendSummary`** over `[start, end)`
    /// (`SpendSummary.of(_:from:until:)`) — totals, models, agents, projects,
    /// sessions, hours — so a recap and the Token spend pane cannot count one
    /// span two ways. What is worked out here is what the summary does not
    /// carry: the previous period, per-agent active days and the dates of them, per-model money, the
    /// late-night figures, the cache savings and the persona.
    ///
    /// **Calendar-bounded, to today.** A period still running ends at the end of
    /// today (`isInProgress`, `end`), and its previous period is cut to the same
    /// number of days (October 1–5 against September 1–5). A period that has
    /// not started is an empty recap, not an error. Nil only for a month outside
    /// 1...12.
    ///
    /// **Missing is nil.** See the field comments; the rules this adds:
    ///
    /// - `hours`: nil when any contributing store has only session- or
    ///   report-level timing, and when no quarter-hour work was recorded. The
    ///   shares behind `lateShare` and `persona` are of the quarter-hour tokens.
    /// - Late nights (`lateNights`, `latestMinute`): any work with a recorded
    ///   quarter-hour from 00:00 to 04:59 local counts toward the night it
    ///   belongs to (the evening before), so a session running past midnight
    ///   does, and so does one that began at 01:00. The minute is the quarter
    ///   hour's start, or a session's own last record where that is later and
    ///   in the same window. Work with only day-level timing has no minute and
    ///   cannot be counted: where `hours` is nil, `lateNights` is a floor.
    /// - `cacheHitRate`: the rule of `UsageLedger.cacheHitRate`, over every
    ///   contributing agent — nil when any of them has counts that may be
    ///   missing or tokens no kind can claim; agents whose store records no
    ///   cache (`SpendAgent.reportsCacheReads`) are left out of it.
    /// - `cacheSavings`: per model, cache-read tokens billed at the input rate
    ///   less what they were billed at (`TokenTally.costBreakdown`, long-context
    ///   tiers included), at the price `prices` holds for that raw model id and
    ///   the agent's plan vendor — the lookup the ledgers were priced with.
    ///   **From each day's own per-model tallies** (`LedgerDay.modelTallies`),
    ///   nothing prorated. A model with no price, or a day with no per-model
    ///   detail, adds nothing: the figure is a floor, and nil where no priced
    ///   cache read exists at all. A model that states no cache rate is billed
    ///   at its input rate, which saves nothing — a real zero for it.
    /// - Streaks are of the period's own days (`Recap.streaks`), not the whole
    ///   history `SpendSummary` counts.
    /// - `unpricedTokens` is the summary's: above zero, money is a floor.
    /// - Money is nil where nothing behind it was priced (`UsageLedger.shownCost`)
    ///   and for a day or month with no work; a part-priced total is its priced
    ///   subtotal, as the pane shows it.
    static func build(
        _ period: Period,
        from ledgers: [SpendAgent: UsageLedger],
        prices: [String: ModelPrice],
        now: Date = Date(),
        calendar: Calendar = Recap.calendar
    ) -> Recap? {
        guard let bounds = period.bounds(calendar: calendar) else { return nil }
        let start = bounds.start
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let isInProgress = today >= start && today < bounds.end
        // Ends at the end of today while running; an unstarted period is empty.
        let end = min(bounds.end, max(start, tomorrow))

        let summary = SpendSummary.of(ledgers, from: start, until: end, now: now, calendar: calendar)
        let elapsedDays = summary.days.count
        // Only a first record inside the span moves anything: one before the
        // start leaves the whole period observed.
        let recordsBegin = RecapPeriods.earliest(in: ledgers, calendar: calendar)
            .map { calendar.startOfDay(for: $0) }
            .flatMap { $0 > start && $0 < end ? $0 : nil }
        let inSpan: (Date) -> Bool = { $0 >= start && $0 < end }

        // MARK: The previous period, as long as this one has run.

        var previousTokens: Int?
        if elapsedDays > 0, let previous = period.previous.bounds(calendar: calendar) {
            let same = calendar.date(byAdding: .day, value: elapsedDays, to: previous.start) ?? previous.end
            let before = SpendSummary.of(
                ledgers, from: previous.start, until: min(previous.end, same), now: now, calendar: calendar
            )
            previousTokens = before.tokens > 0 ? before.tokens : nil
        }

        // MARK: Days and months

        let days = summary.days.map { day in
            Day(date: day.date, tokens: day.tokens, cost: Self.cost(day.cost, tokens: day.tokens, unpriced: day.unpricedTokens))
        }

        var months: [Month] = []
        if case .year = period {
            for month in 1...12 {
                let inMonth = summary.days.filter { calendar.component(.month, from: $0.date) == month }
                let tokens = inMonth.reduce(0) { $0 + $1.tokens }
                months.append(Month(
                    month: month,
                    tokens: tokens,
                    cost: Self.cost(
                        inMonth.reduce(0) { $0 + $1.cost }, tokens: tokens,
                        unpriced: inMonth.reduce(0) { $0 + $1.unpricedTokens }
                    ),
                    activeDays: inMonth.count { $0.tokens > 0 }
                ))
            }
        }

        // The earliest of the heaviest days: a tie is not a later day's.
        var busiest: Day?
        for day in days where day.tokens > (busiest?.tokens ?? 0) { busiest = day }

        // MARK: Time of day

        var hours: [Int]?
        if !summary.hasAggregateTiming, summary.hours.values.reduce(0, +) > 0 {
            hours = (0..<24).map { summary.hours[$0] ?? 0 }
        }
        let hourTotal = hours?.reduce(0, +) ?? 0
        var peakHour: Int?
        var lateShare: Double?
        if let hours, hourTotal > 0 {
            // The earliest hour among equals, so a tie reads the same twice.
            var best = 0
            for hour in 1..<24 where hours[hour] > hours[best] { best = hour }
            peakHour = best
            lateShare = Double(Self.lateHours.reduce(0) { $0 + hours[$1] }) / Double(hourTotal)
        }

        // MARK: Per ledger: late nights, cache, per-model money

        let contributing = summary.agents.map(\.agent)
        var lookup = ModelPriceLookup(prices)
        var nights: Set<Date> = []
        var latestMinute: Int?
        var cacheTally = TokenTally()
        var cacheUnvouched = false
        var savings = 0.0
        var pricedCacheReads = 0
        var modelMoney: [String: Double] = [:]

        for agent in contributing {
            guard let ledger = ledgers[agent] else { continue }

            // A quarter-hour's start, and where a session's own last record
            // falls later in that window, are the instants of work after midnight.
            var instants = ledger.slots.filter { $0.tokens > 0 && inSpan($0.start) }.map(\.start)
            for session in ledger.sessions where !session.slots.isEmpty && inSpan(session.end) {
                instants.append(session.end)
            }
            for instant in instants {
                let parts = calendar.dateComponents([.hour, .minute], from: instant)
                guard let hour = parts.hour, let minute = parts.minute, hour < Self.nightEndsAtHour else { continue }
                nights.insert(calendar.startOfDay(for: instant))
                latestMinute = max(latestMinute ?? 0, hour * 60 + minute)
            }

            let span = ledger.days.filter { inSpan($0.date) }

            if agent.reportsCacheReads {
                switch ledger.cacheReading(in: span) {
                case .measured(let tally): cacheTally = cacheTally + tally
                case .unrecorded: break
                case .unvouched: cacheUnvouched = true
                }
            }

            for day in span {
                for (raw, costs) in day.modelCosts {
                    modelMoney[ledger.modelNames[raw] ?? raw, default: 0] += costs.total
                }
                guard agent.reportsCacheReads else { continue }
                for (raw, tally) in day.modelTallies where tally.cacheRead > 0 {
                    guard let price = lookup.price(for: raw, vendor: agent.priceVendor) else { continue }
                    savings += tally.cacheReadAsInput.cost(at: price) - tally.cost(at: price)
                    pricedCacheReads += tally.cacheRead
                }
            }
        }

        let cacheInput = cacheTally.input + cacheTally.cacheWrite + cacheTally.cacheRead
        let cacheHitRate = cacheUnvouched || cacheInput == 0 ? nil : Double(cacheTally.cacheRead) / Double(cacheInput)

        // MARK: Shares

        let tokens = summary.tokens
        func share(_ part: Int) -> Double { tokens > 0 ? min(Double(part) / Double(tokens), 1) : 0 }

        let agents = summary.agents.map { row -> AgentShare in
            let only = ledgers.filter { $0.key == row.agent }
            let own = SpendSummary.of(only, from: start, until: end, now: now, calendar: calendar)
            return AgentShare(
                agent: row.agent, tokens: row.tokens, share: share(row.tokens), activeDays: own.activeDays,
                cost: Self.cost(row.cost, tokens: row.tokens, unpriced: row.unpricedTokens),
                activeDates: Set(own.days.filter { $0.tokens > 0 }.map(\.date))
            )
        }

        let streaks = Self.streaks(of: days, isInProgress: isInProgress)

        return Recap(
            period: period,
            start: start,
            end: end,
            isInProgress: isInProgress,
            tokens: tokens,
            cost: Self.cost(summary.cost, tokens: tokens, unpriced: summary.unpricedTokens),
            unpricedTokens: summary.unpricedTokens,
            previousTokens: previousTokens,
            activeDays: summary.activeDays,
            elapsedDays: elapsedDays,
            sessions: summary.sessions.count,
            days: days,
            months: months,
            hours: hours,
            peakHour: peakHour,
            lateShare: lateShare,
            latestMinute: latestMinute,
            lateNights: nights.count,
            persona: hours.flatMap(Persona.of(hours:)),
            models: summary.models.map { model in
                ModelShare(name: model.name, tokens: model.tokens, share: share(model.tokens), cost: modelMoney[model.name])
            },
            agents: agents,
            projects: summary.projects.filter { $0.tokens > 0 }.map { project in
                ProjectShare(name: project.name, tokens: project.tokens, share: share(project.tokens), sessions: project.sessions)
            },
            cacheHitRate: cacheHitRate,
            cacheSavings: pricedCacheReads > 0 ? savings : nil,
            currentStreak: streaks.current,
            longestStreak: streaks.longest,
            busiestDay: busiest,
            currency: "USD",
            isPartial: summary.hasPartialCounts,
            recordsBegin: recordsBegin,
            calendar: calendar
        )
    }

    /// Money for some work, nil where there was no work or none of it had a
    /// price (`UsageLedger.shownCost`).
    private static func cost(_ cost: Double, tokens: Int, unpriced: Int) -> Double? {
        tokens > 0 ? UsageLedger.shownCost(cost, tokens: tokens, unpriced: unpriced) : nil
    }
}

private extension TokenTally {
    /// The same work with every cache read billed as fresh input, long-context
    /// bands included — what it would have cost with no cache to read from.
    var cacheReadAsInput: TokenTally {
        var copy = self
        copy.input += cacheRead
        copy.cacheRead = 0
        copy.contextBands = contextBands.mapValues(\.cacheReadAsInput)
        return copy
    }
}
