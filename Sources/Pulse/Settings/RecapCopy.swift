// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Wording the cards share. Every sentence is a key in the strings files, in
/// all five languages; none is assembled from English fragments.
///
/// Where a figure sits inside a sentence it is handed in marked
/// (`RecapEmphasis.mark`), so each translation puts it where its language
/// wants it and the card still finds it to set it in bold.
extension Recap.Persona {
    var title: String {
        switch self {
        case .nightOwl: .localized("Night owl")
        case .earlyBird: .localized("Early bird")
        case .dayShift: .localized("Day shift")
        // Not "all day": it is only that no band holds most of the work, and
        // August 2026 — nothing at all from 07:00 to 12:59 — was called it.
        case .allDay: .localized("No set hours")
        }
    }
}

extension RecapDeck {
    /// "September" for a month recap, "2026年" for a year's — the language's
    /// own way of saying which year, so one sentence serves both.
    var periodName: String {
        switch recap.period {
        case .month(_, let month): RecapFormat.monthName(month)
        case .year(let year): RecapFormat.yearName(year)
        }
    }

    /// The label in the running head: "SEPTEMBER 2026", "2026".
    var periodLabel: String {
        switch recap.period {
        case .month: RecapFormat.monthYear(recap.start).uppercased()
        case .year(let year): "\(year)"
        }
    }

    /// The month or year before this one, as the delta's "vs" names it.
    var previousName: String {
        switch recap.period {
        case .month(_, let month): RecapFormat.monthName(month == 1 ? 12 : month - 1)
        case .year(let year): RecapFormat.yearName(year - 1)
        }
    }

    /// The month or year after, for the closing line.
    var nextName: String {
        switch recap.period {
        case .month(_, let month): RecapFormat.monthName(month == 12 ? 1 : month + 1)
        case .year(let year): RecapFormat.yearName(year + 1)
        }
    }

    /// "In September, you and AI worked through" — the line above the total.
    var workedThroughLine: String {
        .localized("In \(periodName), you and AI worked through")
    }

    /// "Active 27 of 30 days", with the days in bold.
    var activeDaysLine: String {
        let active = RecapEmphasis.mark("\(recap.activeDays)")
        // "of 1 days" on a running month's first day: the singular is its own key.
        return recap.observedDays == 1
            ? .localized("Active \(active) of 1 day")
            : .localized("Active \(active) of \("\(recap.observedDays)") days")
    }

    /// "412 sessions".
    func sessionsText(_ count: Int) -> String { RecapWords.sessions(count) }

    /// "↑ 38%" and "vs same period in August", for a period with something
    /// before it to compare to. **Per day**: `Recap.previousTokens` covers
    /// `previousDays`, which need not be as many as this period's — a month
    /// after February, September against all of August — so the totals are
    /// compared as daily averages. A running period is set against the same
    /// stretch of the one before ("same period"); a finished one against the
    /// whole of it, and says it is per day. Nil without a previous figure.
    var change: (arrow: String, percent: String, versus: String)? {
        guard let previous = recap.previousTokens, previous > 0, recap.elapsedDays > 0 else { return nil }
        let days = Double(max(recap.previousDays ?? recap.elapsedDays, 1))
        let ratio = (Double(recap.tokens) / Double(recap.elapsedDays)) / (Double(previous) / days)
        let delta = Int(((ratio - 1) * 100).rounded())
        let arrow = delta > 0 ? "↑" : (delta < 0 ? "↓" : "→")
        let versus: String = recap.isInProgress
            ? .localized("vs same period in \(previousName)")
            : .localized("per day vs \(previousName)")
        return (arrow, "\(abs(delta))%", versus)
    }

    /// The tokens a day, over the days of the period Pulse could see.
    var tokensPerDay: Int? {
        recap.observedDays > 0 ? recap.tokens / recap.observedDays : nil
    }

    /// Cost per day, or per month for a year, to draw under the poster's total
    /// and on the scorecard. A day (or month) with work and **no price at all
    /// is nil**, drawn as a break in the line rather than a zero; a quiet one
    /// is a real zero. Months still to come or before the first record are not
    /// points at all. Empty with fewer than two priced points.
    ///
    /// It used to be empty whenever any worked day had no price, and one
    /// Kimi-only day — 0.05% of July — took the line off every card.
    var costSeries: [Double?] {
        let series: [(tokens: Int, cost: Double?)]
        if isYear {
            let insights = RecapInsights(recap)
            series = recap.months.enumerated().compactMap { index, month in
                insights.isMonthUnrecorded(index) ? nil : (month.tokens, month.cost)
            }
        } else {
            series = recap.days.map { ($0.tokens, $0.cost) }
        }
        let points: [Double?] = series.map { $0.tokens > 0 ? $0.cost : 0 }
        return points.compactMap { $0 }.count > 1 && points.contains(where: { ($0 ?? 0) > 0 }) ? points : []
    }

    /// The streak a card shows, of the period's own days: the one still going
    /// while the period is running and today or yesterday ended a run, else the
    /// longest the period had. A past period is never "still going". Nil when
    /// no day had work.
    var streak: (days: Int, isCurrent: Bool)? {
        guard recap.longestStreak > 0 else { return nil }
        if recap.isInProgress, recap.currentStreak > 0 { return (recap.currentStreak, true) }
        return (recap.longestStreak, false)
    }

    /// The lines at the foot of a card that shows money: where the numbers come
    /// from, that the money is an estimate, and — only when it is so — that the
    /// period is not over, that some work had no price (money is a floor), or that
    /// a store may be missing counts.
    /// The notes a card that shows no money needs: that the period is not
    /// over, where the records begin, and that a store may be missing counts.
    /// Empty when none applies.
    var notes: [String] {
        var lines: [String] = []
        if recap.isInProgress { lines.append(.localized("Figures are to date.")) }
        if let begin = recap.recordsBegin {
            lines.append(.localized("Records on this Mac begin on \(RecapFormat.day(begin)); days before it are not counted."))
        }
        if recap.isPartial { lines.append(.localized("Some tools' counts may be missing, so the total is a floor.")) }
        return lines
    }

    /// Said wherever the hour shape is drawn, when some tools' work could not
    /// be placed in it.
    var hoursNote: String? {
        guard recap.untimedTokens > 0, recap.hours != nil, recap.tokens > 0 else { return nil }
        let share = RecapFormat.percent(Double(recap.untimedTokens) / Double(recap.tokens))
        return .localized("\(share) of the tokens came from tools that record no time of day and are not in the hours.")
    }

    var provenance: [String] {
        let source: String = recap.cost != nil
            ? .localized("Counted from this Mac's local records · money estimated at API prices")
            : .localized("Counted from this Mac's local records")
        var lines = [source]
        if recap.isInProgress { lines.append(.localized("Figures are to date.")) }
        if let begin = recap.recordsBegin {
            lines.append(.localized("Records on this Mac begin on \(RecapFormat.day(begin)); days before it are not counted."))
        }
        if costIsFloor { lines.append(.localized("Some work had no published price, so the money is a floor.")) }
        if recap.isPartial { lines.append(.localized("Some tools' counts may be missing, so the total is a floor.")) }
        if recap.cacheUnmeasuredTokens > 0, recap.tokens > 0 {
            let share = RecapFormat.percent(Double(recap.cacheUnmeasuredTokens) / Double(recap.tokens))
            lines.append(.localized("The cache hit rate leaves out \(share) of the tokens, whose counts are incomplete."))
        }
        return lines
    }
}
