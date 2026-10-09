// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One month's or one year's recap: what the Token spend readers saw on this
/// Mac over a calendar period, gathered for the shareable recap cards.
///
/// **Facts only, no copy.** Every field is a number, a date, a name the tools
/// themselves use (a model id's display name, an agent, a project directory)
/// or an enum. Wording, number units (万/亿 against K/M/B) and date formats
/// belong to the cards, per language — nothing here is localized.
///
/// **Missing is nil, never zero.** A figure Pulse cannot stand behind — money
/// where nothing was priced, a cache rate where no store records the cache, a
/// previous period with no records — is nil, and the card that needs it is
/// left out rather than drawn with a zero.
///
/// The payback figure is not here: it divides `cost` by a price the reader
/// types into the recap (`AppSettings`), and is worked out where both are.
struct Recap: Sendable, Equatable {
    enum Period: Hashable, Sendable {
        case month(year: Int, month: Int)
        case year(Int)
    }

    /// A rule-based label from where in the day the work fell. Each case is a
    /// stated threshold over `hours` (see `Recap.build`), not a judgement.
    enum Persona: String, Sendable, Equatable, CaseIterable {
        /// Most work after 21:00 or before 05:00.
        case nightOwl
        /// Most work between 05:00 and 10:00.
        case earlyBird
        /// Most work between 10:00 and 18:00.
        case dayShift
        /// No band holds most of it.
        case allDay
    }

    struct Day: Sendable, Equatable, Identifiable {
        /// Local midnight.
        let date: Date
        let tokens: Int
        /// Estimated at API prices; nil when none of the day's work had a price.
        let cost: Double?
        var id: Date { date }
    }

    /// Year recaps only: one entry per calendar month, January first.
    struct Month: Sendable, Equatable, Identifiable {
        /// 1...12.
        let month: Int
        let tokens: Int
        let cost: Double?
        let activeDays: Int
        var id: Int { month }
    }

    struct ModelShare: Sendable, Equatable, Identifiable {
        /// The provider's own display name ("Claude Opus 4.6"), else the raw id.
        let name: String
        let tokens: Int
        /// Of `Recap.tokens`, 0...1.
        let share: Double
        let cost: Double?
        var id: String { name }
    }

    struct AgentShare: Sendable, Equatable, Identifiable {
        let agent: SpendAgent
        let tokens: Int
        let share: Double
        /// Calendar days in the period with any of this agent's work.
        let activeDays: Int
        let cost: Double?
        /// Which days those were: local midnights, `activeDays` of them, all
        /// inside the period. The opener's per-agent strip is drawn from them.
        var activeDates: Set<Date> = []
        var id: SpendAgent { agent }
    }

    struct ProjectShare: Sendable, Equatable, Identifiable {
        /// The directory's short name, as the Token spend pane shows it.
        let name: String
        let tokens: Int
        let share: Double
        let sessions: Int
        var id: String { name }
    }

    let period: Period
    /// The first local midnight of the period, and the instant it ends
    /// (exclusive). A period still running ends at the end of today.
    let start: Date
    let end: Date
    /// Whether the period is still running: figures are to date.
    let isInProgress: Bool

    let tokens: Int
    /// Estimated at published API prices (`ModelPrices`); nil when nothing
    /// was priced. Always labelled as an estimate on the cards.
    let cost: Double?
    /// Tokens of the period with no published price behind them
    /// (`SpendSummary.unpricedTokens`). Above zero, `cost` is the priced part
    /// only — a floor — and the cards say so, the payback card included
    /// (`RecapDeck.payback`).
    let unpricedTokens: Int
    /// The same span of the previous period, for "up 38% on August". Nil when
    /// nothing was recorded then.
    let previousTokens: Int?

    /// Calendar days with any work, and the days the period has had so far.
    let activeDays: Int
    let elapsedDays: Int
    let sessions: Int

    /// Every calendar day of the period up to today, quiet ones included.
    let days: [Day]
    /// Year recaps: twelve entries. Month recaps: empty.
    let months: [Month]

    /// Tokens by local hour, 24 entries, 0 = midnight. Nil when any store
    /// behind the period has only session- or report-level timing, so an
    /// hour shape would be invented (`SpendSummary.hasAggregateTiming`).
    let hours: [Int]?
    let peakHour: Int?
    /// Share of the period's tokens in 21:00–04:59.
    let lateShare: Double?
    /// The latest any stretch of work ended, as minutes after the midnight of
    /// the day it began — past 1440 when it ran into the next morning
    /// (`Recap.workdays`). Nil with no timed work.
    let latestMinute: Int?
    /// Stretches of work that ran over a midnight.
    let lateNights: Int
    let persona: Persona?

    /// Heaviest first.
    let models: [ModelShare]
    let agents: [AgentShare]
    let projects: [ProjectShare]

    /// Cache reads over all input, as the Token spend pane works it out; nil
    /// where no store records the cache.
    let cacheHitRate: Double?
    /// What the cache reads would have cost at each model's input rate, less
    /// what they did cost at its cache-read rate. Nil when unpriced.
    let cacheSavings: Double?

    /// **Streaks belong to the period**, counted over `days` and nothing outside
    /// it (not `SpendSummary`'s whole-history ones): a past month's card must
    /// not carry October's streak, nor an all-time record longer than the month.
    ///
    /// `longestStreak` is the longest run of days with work inside the period.
    /// `currentStreak` is the run that ends on the period's last day — for a
    /// past period, its final day; for a running one, today, or yesterday while
    /// today has had no work yet ("today is not over") — counted inside the
    /// period only. Only a running period's is "still going"
    /// (`isInProgress`); a past period's says how it ended.
    let currentStreak: Int
    let longestStreak: Int
    let busiestDay: Day?

    /// ISO currency of `cost`; the readers price in US dollars.
    let currency: String
    /// Whether some store behind it may be missing counts: the total is a floor.
    let isPartial: Bool

    /// The first day this Mac has any record for, when that falls inside the
    /// period after its first day; nil when the records reach back to the
    /// start or before it.
    ///
    /// **Before it Pulse saw nothing, which is not a quiet day.** A year whose
    /// records began in May drew January to April as zeros and counted them in
    /// every denominator — "active 88 of 282 days", the workday split, the
    /// plan price prorated from January 1. `observedDays` is the count those
    /// use, and a month entirely before it is drawn as unrecorded.
    var recordsBegin: Date? = nil

    /// The days `previousTokens` was counted over: as many as this period has
    /// had while it runs (fewer where the period before is shorter), all of
    /// the period before once this one is over, and none from before the
    /// first record. Nil where `previousTokens` is.
    var previousDays: Int? = nil

    /// The calendar the recap was built with, so the cards that lay out its
    /// days (the year's twelve months) count them the way it did.
    var calendar: Calendar = Recap.calendar

    var isEmpty: Bool { tokens == 0 }

    /// The period's days Pulse could have seen work on: from `recordsBegin`
    /// (or the start) up to today or the end. `elapsedDays` without a later
    /// first record; the "same period" comparison keeps `elapsedDays`.
    var observedDays: Int {
        guard let recordsBegin else { return elapsedDays }
        return days.count { $0.date >= recordsBegin }
    }

    /// Whether a day falls before the first record this Mac holds.
    func isBeforeRecords(_ date: Date) -> Bool {
        recordsBegin.map { date < $0 } ?? false
    }

    /// The calendar every recap is built, offered and drawn in: Gregorian,
    /// weeks from Monday, the system's time zone. **Not `Calendar.current`** —
    /// a Buddhist or Japanese system calendar would number the year 2569 or
    /// Reiwa 8 while the cards print the Gregorian year, and a recap asked for
    /// as "2026" would be built over another span than the one it names.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// The first day of each month the period covers — twelve for a year, one
    /// for a month — found from `start` by whole-month offsets in the calendar
    /// the recap was built with, never rebuilt from the year's number (which a
    /// calendar of another era would read as a different year).
    var monthStarts: [Date] {
        let count: Int
        switch period {
        case .year: count = 12
        case .month: count = 1
        }
        return (0..<count).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    /// The streaks of `days` (oldest first, one entry per calendar day, quiet
    /// ones included): see `currentStreak` and `longestStreak`. A running
    /// period's last day is today, and a quiet today does not break the run
    /// until it has passed.
    static func streaks(of days: [Day], isInProgress: Bool) -> (current: Int, longest: Int) {
        var longest = 0
        var run = 0
        for day in days {
            run = day.tokens > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        var current = 0
        var index = days.count - 1
        if isInProgress, index >= 0, days[index].tokens == 0 { index -= 1 }
        while index >= 0, days[index].tokens > 0 {
            current += 1
            index -= 1
        }
        return (current, longest)
    }
}

extension Recap {
    /// The four hours in a row, wrapping past midnight, that held the most of
    /// the period's tokens — where this person's day actually bunched.
    ///
    /// It replaced a fixed 21:00–04:59 band on the rhythm card, which read as
    /// a claim about when *you* worked ("8% … between 9 PM and 5 AM") while
    /// saying the same hours for everyone. `lateShare` still measures that
    /// band for `--recap`.
    struct HourWindow: Equatable, Sendable {
        static let length = 4

        /// The first hour, 0..<24.
        let start: Int
        /// Of the period's hour tokens, 0...1.
        let share: Double

        /// The hour the window stops at, exclusive: 10 for one starting at 6.
        var end: Int { (start + Self.length) % 24 }

        func contains(_ hour: Int) -> Bool {
            ((hour - start) % 24 + 24) % 24 < Self.length
        }
    }

    var busiestHours: HourWindow? { hours.flatMap(Self.busiestHours(in:)) }

    /// The earliest start among equals, so a tie reads the same twice — the
    /// rule `peakHour` follows. Nil without 24 hours or without any work.
    static func busiestHours(in hours: [Int]) -> HourWindow? {
        guard hours.count == 24 else { return nil }
        let total = hours.reduce(0, +)
        guard total > 0 else { return nil }
        var best = 0
        var bestTokens = -1
        for start in 0..<24 {
            let tokens = (0..<HourWindow.length).reduce(0) { $0 + hours[(start + $1) % 24] }
            if tokens > bestTokens {
                best = start
                bestTokens = tokens
            }
        }
        return HourWindow(start: best, share: Double(bestTokens) / Double(total))
    }
}
