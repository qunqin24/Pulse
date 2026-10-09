// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What the recap cards read off a `Recap` beyond its own fields: weekday and
/// week totals, the shape of a streak, the day split into quarters, money per
/// million tokens, and the strips that show which agent worked on which day.
///
/// Facts only, like `Recap`, and apart from drawing so they can be tested: no
/// copy, no layout. **A figure that cannot be stood behind is nil**, and the
/// card that would draw it leaves it out — a weekday the period never had is
/// not a zero, a series with one unpriced working day is not a series.
struct RecapInsights: Sendable {
    let recap: Recap

    init(_ recap: Recap) { self.recap = recap }

    private var calendar: Calendar { recap.calendar }

    /// Monday = 0 … Sunday = 6, in the calendar the recap was built with.
    func weekdayIndex(of date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }

    /// Saturday and Sunday.
    static func isWeekend(weekdayIndex: Int) -> Bool { weekdayIndex >= 5 }

    // MARK: - Weekdays and weekends

    /// Tokens by day of the week, Monday first. Nil for a weekday the period
    /// has not had a single day of (the first days of a running month), which
    /// is unknown rather than quiet.
    var weekdayTokens: [Int?] {
        var tokens = [Int](repeating: 0, count: 7)
        var seen = [Bool](repeating: false, count: 7)
        for day in recap.days {
            let index = weekdayIndex(of: day.date)
            tokens[index] += day.tokens
            seen[index] = true
        }
        return (0..<7).map { seen[$0] ? tokens[$0] : nil }
    }

    /// The heaviest day of the week (Monday = 0), the earliest of a tie; nil
    /// when none had work.
    var busiestWeekday: Int? {
        let tokens = weekdayTokens
        var best: Int?
        for index in 0..<7 where (tokens[index] ?? 0) > (best.flatMap { tokens[$0] } ?? 0) { best = index }
        return best
    }

    /// The days of the week against the weekend: tokens, the days the period
    /// has had of each, and how many of them had work.
    struct WorkSplit: Equatable, Sendable {
        let weekdayTokens: Int
        let weekendTokens: Int
        let weekdayDays: Int
        let weekendDays: Int
        let weekdayActive: Int
        let weekendActive: Int

        var tokens: Int { weekdayTokens + weekendTokens }
        /// Of all the tokens, 0...1.
        var weekdayShare: Double { tokens > 0 ? Double(weekdayTokens) / Double(tokens) : 0 }
        var weekendShare: Double { tokens > 0 ? Double(weekendTokens) / Double(tokens) : 0 }
    }

    /// Nil where there is nothing to split: no days, or no tokens in them.
    var workSplit: WorkSplit? {
        guard recap.days.contains(where: { $0.tokens > 0 }) else { return nil }
        var weekday = (tokens: 0, days: 0, active: 0)
        var weekend = (tokens: 0, days: 0, active: 0)
        // Days before the first record were not seen, so they are not days
        // the period "had" of either kind.
        for day in recap.days where !recap.isBeforeRecords(day.date) {
            let isWeekend = Self.isWeekend(weekdayIndex: weekdayIndex(of: day.date))
            if isWeekend {
                weekend = (weekend.tokens + day.tokens, weekend.days + 1, weekend.active + (day.tokens > 0 ? 1 : 0))
            } else {
                weekday = (weekday.tokens + day.tokens, weekday.days + 1, weekday.active + (day.tokens > 0 ? 1 : 0))
            }
        }
        return WorkSplit(
            weekdayTokens: weekday.tokens, weekendTokens: weekend.tokens,
            weekdayDays: weekday.days, weekendDays: weekend.days,
            weekdayActive: weekday.active, weekendActive: weekend.active
        )
    }

    /// Tokens on an average day with work, nil with none.
    var tokensPerActiveDay: Int? {
        recap.activeDays > 0 ? recap.tokens / recap.activeDays : nil
    }

    // MARK: - Weeks

    /// A week of the period, Monday to Sunday, **clipped to the period**: the
    /// first and last may be short.
    struct Week: Equatable, Sendable {
        let first: Date
        let last: Date
        let tokens: Int
    }

    /// The period's weeks, oldest first, from the days it has had.
    var weeks: [Week] {
        var result: [Week] = []
        var currentKey: Date?
        for day in recap.days {
            let key = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start ?? day.date
            if key == currentKey, let last = result.popLast() {
                result.append(Week(first: last.first, last: day.date, tokens: last.tokens + day.tokens))
            } else {
                result.append(Week(first: day.date, last: day.date, tokens: day.tokens))
                currentKey = key
            }
        }
        return result
    }

    /// The index of the heaviest week, the earliest of a tie; nil when none had work.
    var busiestWeek: Int? {
        var best: Int?
        for (index, week) in weeks.enumerated() where week.tokens > (best.map { weeks[$0].tokens } ?? 0) { best = index }
        return best
    }

    // MARK: - Streak

    /// A run of days with work.
    struct Run: Equatable, Sendable {
        let first: Date
        let last: Date
        let length: Int
    }

    /// The longest run of days with work inside the period, the earliest of a
    /// tie. Nil when no day had work.
    var longestRun: Run? {
        var best: Run?
        var start: Int?
        for (index, day) in recap.days.enumerated() {
            if day.tokens > 0 {
                let from = start ?? index
                start = from
                let length = index - from + 1
                if length > (best?.length ?? 0) {
                    best = Run(first: recap.days[from].date, last: day.date, length: length)
                }
            } else {
                start = nil
            }
        }
        return best
    }

    /// The streak drawn as a chain of days: a window of at most nine around
    /// the run, kept inside the period, with the run's own days marked.
    struct Chain: Equatable, Sendable {
        /// The days drawn, oldest first.
        let days: [Date]
        /// Which of them belong to the run.
        let run: Range<Int>
        /// The dates a label under the chain names: the window's two ends, or
        /// the run's own where the run is longer than the window (the chain
        /// then shows its first nine days, and the label says where it ends).
        let first: Date
        let last: Date

        static let width = 9
    }

    var streakChain: Chain? {
        guard let run = longestRun,
              let from = recap.days.firstIndex(where: { $0.date == run.first }) else { return nil }
        let width = Chain.width
        let count = recap.days.count
        if run.length >= width {
            let days = recap.days[from..<(from + width)].map(\.date)
            return Chain(days: days, run: 0..<width, first: run.first, last: run.last)
        }
        let window = min(width, count)
        // The run in the middle where it can be, else against the edge.
        let before = (window - run.length) / 2
        let start = max(0, min(from - before, count - window))
        let days = recap.days[start..<(start + window)].map(\.date)
        let lower = from - start
        return Chain(days: days, run: lower..<(lower + run.length), first: days[0], last: days[days.count - 1])
    }

    // MARK: - Time of day

    /// The earliest hour from 05:00 on with any work: when the day usually
    /// starts, leaving the after-midnight tail to the night before. Nil where
    /// there is no hour shape or nothing from 05:00 on.
    var firstHour: Int? {
        guard let hours = recap.hours, hours.count == 24 else { return nil }
        return (Recap.nightEndsAtHour..<24).first { hours[$0] > 0 }
    }

    /// A quarter of the day and its share of the tokens in the hour shape.
    struct Quarter: Equatable, Sendable {
        /// 0..<6, 6..<12, 12..<18 or 18..<24.
        let hours: Range<Int>
        let tokens: Int
        let share: Double
    }

    /// The four quarters of the day, midnight first. Nil with no hour shape
    /// or no tokens in it.
    var quarters: [Quarter]? {
        guard let hours = recap.hours, hours.count == 24 else { return nil }
        let total = hours.reduce(0, +)
        guard total > 0 else { return nil }
        return stride(from: 0, to: 24, by: 6).map { start in
            let tokens = hours[start..<(start + 6)].reduce(0, +)
            return Quarter(hours: start..<(start + 6), tokens: tokens, share: Double(tokens) / Double(total))
        }
    }

    /// The heaviest quarter's index, the earliest of a tie.
    var leadingQuarter: Int? {
        guard let quarters else { return nil }
        var best = 0
        for index in 1..<quarters.count where quarters[index].tokens > quarters[best].tokens { best = index }
        return best
    }

    // MARK: - Money

    /// Dollars per million tokens, over the tokens that had a price: with some
    /// unpriced the cost is a floor, and dividing it by every token would
    /// understate the rate. Nil with no cost or no priced tokens.
    var costPerMillion: Double? {
        guard let cost = recap.cost else { return nil }
        let priced = recap.tokens - recap.unpricedTokens
        return priced > 0 ? cost / Double(priced) * 1_000_000 : nil
    }

    /// Money on an average day with work.
    var costPerActiveDay: Double? {
        guard let cost = recap.cost, recap.activeDays > 0 else { return nil }
        return cost / Double(recap.activeDays)
    }

    /// The day that cost most among the days with a price, the earliest of a
    /// tie; nil when no day had one. A day with work and no price at all is
    /// left out of the running rather than taking the tile away — it once did,
    /// and one Kimi-only day (0.05% of July) removed it. The card already says
    /// the money is a floor where any work went unpriced.
    var costliestDay: Recap.Day? {
        var best: Recap.Day?
        for day in recap.days where (day.cost ?? 0) > (best?.cost ?? 0) { best = day }
        return best
    }

    /// Money by day (a month) or by month (a year), one entry per day or
    /// month: a quiet one a real zero, and **nil for one with no figure** — a
    /// month still to come or before the first record, or work with no price
    /// at all, which is not a zero. Nil altogether when nothing had a price.
    var costBars: [Double?]? {
        let bars: [Double?]
        switch recap.period {
        case .month:
            bars = recap.days.map { $0.tokens > 0 ? $0.cost : 0 }
        case .year:
            guard recap.months.count == 12 else { return nil }
            bars = recap.months.enumerated().map { index, month in
                if isMonthUnrecorded(index) { return nil }
                return month.tokens > 0 ? month.cost : 0
            }
        }
        return bars.contains { ($0 ?? 0) > 0 } ? bars : nil
    }

    /// Whether month `index` (0 for January) of a running year has not begun:
    /// a month to come, which is not a quiet month and is not drawn as one.
    func isMonthToCome(_ index: Int) -> Bool {
        guard recap.isInProgress, case .year = recap.period, let last = recap.days.last?.date else { return false }
        let starts = recap.monthStarts
        return index < starts.count && starts[index] > last
    }

    /// Whether month `index` of a year ended before this Mac's first record:
    /// nothing was seen in it, so it is not a quiet month either.
    func isMonthBeforeRecords(_ index: Int) -> Bool {
        guard case .year = recap.period, let begin = recap.recordsBegin else { return false }
        let starts = recap.monthStarts
        guard index < starts.count,
              let next = recap.calendar.date(byAdding: .month, value: 1, to: starts[index]) else { return false }
        return next <= begin
    }

    /// A month with nothing to show: still to come, or before the records.
    func isMonthUnrecorded(_ index: Int) -> Bool {
        isMonthToCome(index) || isMonthBeforeRecords(index)
    }

    // MARK: - Who worked when

    /// What one agent's strip shows for a day (or, in a year, a month).
    enum Mark: Equatable, Sendable {
        /// This agent worked.
        case used
        /// Another agent did, this one did not.
        case other
        /// Nobody did, and it was a weekend.
        case quietWeekend
        /// Nobody did, on a weekday (or in a month).
        case quiet
        /// A month of a running year that has not begun.
        case toCome
    }

    /// One mark per day of the period for an agent.
    func dayMarks(of agent: Recap.AgentShare) -> [Mark] {
        recap.days.map { day in
            if agent.activeDates.contains(day.date) { return .used }
            if day.tokens > 0 { return .other }
            return Self.isWeekend(weekdayIndex: weekdayIndex(of: day.date)) ? .quietWeekend : .quiet
        }
    }

    /// One mark per month of a year for an agent: used when it had work in the
    /// month at all. Empty for a month recap.
    func monthMarks(of agent: Recap.AgentShare) -> [Mark] {
        let used = Set(agent.activeDates.map { calendar.component(.month, from: $0) })
        return recap.months.enumerated().map { index, month in
            if isMonthUnrecorded(index) { return .toCome }
            if used.contains(month.month) { return .used }
            return month.tokens > 0 ? .other : .quiet
        }
    }

    /// The marks the opener draws: days for a month, months for a year.
    func marks(of agent: Recap.AgentShare) -> [Mark] {
        switch recap.period {
        case .month: dayMarks(of: agent)
        case .year: monthMarks(of: agent)
        }
    }
}
