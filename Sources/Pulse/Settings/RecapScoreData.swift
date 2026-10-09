// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

// What the scorecard's small charts draw, worked out from the recap. Kept apart
// from the view so the rules (what is future, what is quiet, which bar is the
// busiest, when a figure is left out) can be tested without drawing anything.

/// What one day (or, in a year, one month) was: worked, quiet, or not yet.
enum RecapSlot: Equatable, Sendable {
    /// Some work.
    case active
    /// Over, and nothing recorded.
    case quiet
    /// Still to come in a period that is running. Never drawn as a zero.
    case future
}

/// One bar of the day (or month) strip.
struct RecapScoreBar: Equatable, Sendable {
    let slot: RecapSlot
    /// The slot's tokens over the period's largest, 0...1. Zero unless active.
    let fraction: Double
    let isBusiest: Bool
}

/// One tool in the segmented share bar and its legend.
struct RecapScoreAgent: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case lime, ink, grey }
    let name: String
    let share: Double
    let tone: Tone
}

extension RecapDeck {
    /// "NO. 2026·10" for a month, "NO. 2026" for a year: the period as an id,
    /// not a translation.
    var scoreStamp: String {
        switch recap.period {
        case .month(let year, let month): String(format: "NO. %d·%02d", year, month)
        case .year(let year): "NO. \(year)"
        }
    }

    /// The last day the recap has: today while the period runs.
    var lastDay: Date? { recap.days.last?.date }

    /// The change chip every card draws (`change`), by the name the
    /// scorecard was written against.
    var sameSpanChange: (arrow: String, percent: String, versus: String)? { change }

    /// Sessions over days with work, rounded. Nil when either is none or the
    /// average rounds to nothing, so the card says nothing rather than "0".
    var sessionsPerActiveDay: Int? {
        guard recap.activeDays > 0, recap.sessions > 0 else { return nil }
        let average = Int((Double(recap.sessions) / Double(recap.activeDays)).rounded())
        return average > 0 ? average : nil
    }

    /// One bar per day of the month (up to the month's last day, the days
    /// after today as `.future`), or one per month of the year. Empty where the
    /// recap carries no such series or no slot had work.
    var scoreBars: [RecapScoreBar] {
        let bars: [RecapScoreBar]
        switch recap.period {
        case .month:
            let calendar = recap.calendar
            let count = calendar.range(of: .day, in: .month, for: recap.start)?.count ?? recap.days.count
            let byDay = Dictionary(
                recap.days.map { (calendar.component(.day, from: $0.date), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let maximum = recap.days.map(\.tokens).max() ?? 0
            let busiest = recap.busiestDay?.date
            bars = (1...max(count, 1)).map { number in
                guard let day = byDay[number] else { return RecapScoreBar(slot: .future, fraction: 0, isBusiest: false) }
                guard day.tokens > 0, maximum > 0 else { return RecapScoreBar(slot: .quiet, fraction: 0, isBusiest: false) }
                return RecapScoreBar(slot: .active, fraction: Double(day.tokens) / Double(maximum), isBusiest: day.date == busiest)
            }
        case .year:
            let months = recap.months
            let maximum = months.map(\.tokens).max() ?? 0
            let busiest = maximum > 0 ? months.firstIndex { $0.tokens == maximum } : nil
            let starts = recap.monthStarts
            bars = months.enumerated().map { index, month in
                // A month that begins after today has not happened, and one
                // that ended before the first record was not seen: neither is
                // quiet. A past month with nothing is.
                if recap.isInProgress, let last = lastDay, index < starts.count, starts[index] > last {
                    return RecapScoreBar(slot: .future, fraction: 0, isBusiest: false)
                }
                if RecapInsights(recap).isMonthBeforeRecords(index) {
                    return RecapScoreBar(slot: .future, fraction: 0, isBusiest: false)
                }
                guard month.tokens > 0, maximum > 0 else { return RecapScoreBar(slot: .quiet, fraction: 0, isBusiest: false) }
                return RecapScoreBar(slot: .active, fraction: Double(month.tokens) / Double(maximum), isBusiest: index == busiest)
            }
        }
        return bars.contains { $0.slot == .active } ? bars : []
    }

    /// The labels under the strip, by bar index: 1, 10, 20 and the last day for
    /// a month; every month's short name for a year.
    var scoreAxis: [(index: Int, label: String)] {
        let bars = scoreBars
        guard !bars.isEmpty else { return [] }
        switch recap.period {
        case .month:
            let indices = Array(Set([0, 9, 19, bars.count - 1]).filter { $0 < bars.count }).sorted()
            return indices.map { ($0, "\($0 + 1)") }
        case .year:
            return recap.months.indices.map { ($0, RecapFormat.shortMonthName(recap.months[$0].month)) }
        }
    }

    /// "Busiest Oct 5 · 340M": the strip's right-hand note. Nil without a
    /// busiest slot.
    var scoreBusiestNote: String? {
        switch recap.period {
        case .month:
            guard let day = recap.busiestDay, day.tokens > 0 else { return nil }
            return .localized("Busiest \(RecapFormat.day(day.date)) · \(RecapFormat.tokens(day.tokens).text)")
        case .year:
            let maximum = recap.months.map(\.tokens).max() ?? 0
            guard maximum > 0, let busiest = recap.months.first(where: { $0.tokens == maximum }) else { return nil }
            return .localized("Busiest \(RecapFormat.monthName(busiest.month)) · \(RecapFormat.tokens(busiest.tokens).text)")
        }
    }

    /// The tools as the share bar draws them: the top one lime, the second ink,
    /// the third grey — and past three, the second's runners-up grouped as
    /// "Other". Empty without agents.
    var scoreAgents: [RecapScoreAgent] {
        let agents = recap.agents
        let tones: [RecapScoreAgent.Tone] = [.lime, .ink, .grey]
        guard !agents.isEmpty else { return [] }
        if agents.count <= 3 {
            return agents.enumerated().map { RecapScoreAgent(name: $1.agent.displayName, share: $1.share, tone: tones[$0]) }
        }
        let top = agents.prefix(2).enumerated().map {
            RecapScoreAgent(name: $1.agent.displayName, share: $1.share, tone: tones[$0])
        }
        let rest = agents.dropFirst(2).reduce(0) { $0 + $1.share }
        return top + [RecapScoreAgent(name: .localized("Other"), share: rest, tone: .grey)]
    }
}
