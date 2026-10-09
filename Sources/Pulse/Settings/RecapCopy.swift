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
        case .allDay: .localized("All day")
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
    /// before it to compare to. `Recap.previousTokens` is counted over the same
    /// number of days of the period before, so every card says "same period".
    /// Nil without it: a percentage of nothing is not a number.
    var change: (arrow: String, percent: String, versus: String)? {
        guard let previous = recap.previousTokens, previous > 0 else { return nil }
        let delta = Int(((Double(recap.tokens) / Double(previous) - 1) * 100).rounded())
        let arrow = delta > 0 ? "↑" : (delta < 0 ? "↓" : "→")
        return (arrow, "\(abs(delta))%", .localized("vs same period in \(previousName)"))
    }

    /// The tokens a day, over the days of the period Pulse could see.
    var tokensPerDay: Int? {
        recap.observedDays > 0 ? recap.tokens / recap.observedDays : nil
    }

    /// Cost per day, or per month for a year, to draw under the poster's total.
    /// Empty where fewer than two points carry a price, and **where any point
    /// with work has none**: a line through a zero for a day that was merely
    /// unpriced would be a figure Pulse made up. A quiet point (no tokens) is a
    /// real zero, and a month (or day) still to come is not drawn at all.
    var costSeries: [Double] {
        let series: [(tokens: Int, cost: Double?)]
        if isYear {
            // A year still running has no months to come: those are not zeros.
            let starts = recap.monthStarts
            let last = recap.days.last?.date
            series = recap.months.enumerated().compactMap { index, month in
                if recap.isInProgress, let last, index < starts.count, starts[index] > last { return nil }
                return (month.tokens, month.cost)
            }
        } else {
            series = recap.days.map { ($0.tokens, $0.cost) }
        }
        guard !series.contains(where: { $0.tokens > 0 && $0.cost == nil }) else { return [] }
        return series.filter { $0.cost != nil }.count > 1 ? series.map { $0.cost ?? 0 } : []
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
        return lines
    }
}
