// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One card of a recap. Each is 1080 × 1920, drawn by `RecapCardView`.
enum RecapCard: String, Hashable, CaseIterable, Sendable {
    /// The dense one-page summary. Stands alone, so it is not numbered.
    case poster
    /// The month number or the year, and the agents that did the work.
    case opener
    /// A month: every day of it, one cell each.
    case calendar
    /// A year: every month of it as a small calendar.
    case yearCalendar
    /// A year: one bar per month.
    case months
    /// Peak hour, on a dial and as 24 bars.
    case timetable
    /// What the period cost at API prices against the subscription price.
    case payback
    /// The closing scorecard.
    case scorecard
}

/// Cost against what the reader pays: the figure on the payback card, the
/// poster's lime tile and the scorecard.
struct RecapPayback: Equatable, Sendable {
    /// What the period's work would have cost at API prices.
    let used: Double
    /// The monthly price the reader typed.
    let monthlyPrice: Double
    /// Months of subscription the period covers: 1 for a month recap, 12 for a
    /// year, and for a period still running that share of them the days so far
    /// make (`RecapDeck.paidMonths`) — so 5 days into a 31-day month is 5/31.
    let months: Double
    /// Whether the period is still running: both figures are to date.
    let isToDate: Bool

    /// What the subscription cost over the span: the price times `months`.
    var paid: Double { monthlyPrice * months }

    /// `used / paid`, under 1 when the subscription cost more than the work did.
    var multiple: Double { used / paid }
}

/// The cards a `Recap` gets, in order, and the facts they share.
///
/// **A card whose data is missing is left out, never drawn empty or with a
/// zero.** No agents, no opener; no hour shape (`Recap.hours` is nil where a
/// store only has session-level timing), no timetable; no cost or no price, no
/// payback. An empty recap gets no deck at all. The page counter ("01 / 05")
/// counts the numbered cards the deck really has.
struct RecapDeck: Sendable {
    let recap: Recap
    /// What the reader pays a month, in `recap.currency`. Nil when they have
    /// not typed one.
    let monthlyPrice: Double?
    /// Replaces project names with "Project 1", "Project 2"… for a card that
    /// is about to be shared.
    let hidesProjects: Bool
    let payback: RecapPayback?
    let cards: [RecapCard]

    init(recap: Recap, monthlyPrice: Double?, hidesProjects: Bool) {
        self.recap = recap
        self.monthlyPrice = monthlyPrice
        self.hidesProjects = hidesProjects
        let payback = Self.payback(recap: recap, monthlyPrice: monthlyPrice)
        self.payback = payback
        self.cards = Self.cards(recap: recap, hasPayback: payback != nil)
    }

    /// Whether the recap is a year's.
    var isYear: Bool {
        if case .year = recap.period { return true }
        return false
    }

    /// The numbered cards: everything but the poster.
    var stories: [RecapCard] { cards.filter { $0 != .poster } }

    /// "01 / 05" for a numbered card; nil for the poster and for a card the
    /// deck does not hold.
    func page(of card: RecapCard) -> (number: Int, count: Int)? {
        guard let index = stories.firstIndex(of: card) else { return nil }
        return (index + 1, stories.count)
    }

    /// The label for one project, which is "Project 2" when names are hidden.
    func projectName(_ index: Int, _ project: Recap.ProjectShare) -> String {
        hidesProjects ? String.localized("Project \("\(index + 1)")") : project.name
    }

    // MARK: - Rules

    private static func cards(recap: Recap, hasPayback: Bool) -> [RecapCard] {
        guard !recap.isEmpty else { return [] }
        var cards: [RecapCard] = [.poster]
        if !recap.agents.isEmpty { cards.append(.opener) }

        switch recap.period {
        case .month:
            if recap.days.contains(where: { $0.tokens > 0 }) { cards.append(.calendar) }
        case .year:
            if recap.days.contains(where: { $0.tokens > 0 }) { cards.append(.yearCalendar) }
            if recap.months.count == 12, recap.months.contains(where: { $0.tokens > 0 }) { cards.append(.months) }
        }

        if let hours = recap.hours, hours.count == 24, recap.peakHour != nil, hours.contains(where: { $0 > 0 }) {
            cards.append(.timetable)
        }
        if hasPayback { cards.append(.payback) }
        cards.append(.scorecard)
        return cards
    }

    /// A payback card needs a priced period and a price. A price of nothing is
    /// not a subscription, and a period priced at nothing has no payback to
    /// state.
    ///
    /// **Unpriced work does not take the card away.** It once did, from 1% of
    /// the tokens — and a heavy month with a model nobody publishes a price
    /// for (swe-2-high was 1.2% of five billion tokens) lost the card every
    /// month, with nothing on screen saying why. The money is then a floor, so
    /// the multiple is too: the card carries the floor note (`costIsFloor`),
    /// and a floor never overstates what the plan returned.
    static func payback(recap: Recap, monthlyPrice: Double?) -> RecapPayback? {
        guard let cost = recap.cost, cost > 0, let price = monthlyPrice, price > 0,
              recap.tokens > 0 else { return nil }
        let months = paidMonths(recap)
        guard months > 0 else { return nil }
        return RecapPayback(used: cost, monthlyPrice: price, months: months, isToDate: recap.isInProgress)
    }

    /// Months of subscription the period spans: one for a month, twelve for a
    /// year. **A period still running is prorated by days** — the days so far
    /// over the days in the month (or the year) — not by whole months started,
    /// which would charge a year in March for three full months, or a month's
    /// fifth day for all of it.
    ///
    /// **Nor from before the first record.** The price is counted from
    /// `Recap.recordsBegin` when the records start inside the period, and the
    /// card says so: Pulse cannot know the plan was paid for months it saw no
    /// work in, and charging January for a year whose records begin in May
    /// shrank the multiple by a third.
    static func paidMonths(_ recap: Recap) -> Double {
        let whole: Double = recap.period.isYear ? 12 : 1
        guard recap.isInProgress || recap.recordsBegin != nil,
              let full = recap.period.bounds(calendar: recap.calendar),
              let total = recap.calendar.dateComponents([.day], from: full.start, to: full.end).day,
              total > 0 else { return whole }
        return whole * Double(min(recap.observedDays, total)) / Double(total)
    }

    /// Whether some of the money is a floor because part of the work had no
    /// published price, where there is money to say it about.
    var costIsFloor: Bool { recap.cost != nil && recap.unpricedTokens > 0 }

    /// The cache's saving worth saying: nil below fifty cents, where "about
    /// $0.00" would be the sentence.
    var cacheSavings: Double? {
        recap.cacheSavings.flatMap { $0 >= Self.minimumSavings ? $0 : nil }
    }

    static let minimumSavings = 0.5
}
