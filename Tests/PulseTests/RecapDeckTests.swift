import Foundation
import Testing
@testable import Pulse

/// Which cards a recap gets: a card whose data is missing is left out.
@Suite("Recap deck")
struct RecapDeckTests {
    private static func deck(_ recap: Recap, price: Double? = 200, hidesProjects: Bool = false) -> RecapDeck {
        RecapDeck(recap: recap, monthlyPrice: price, hidesProjects: hidesProjects)
    }

    @Test("A full month has all six cards, in order")
    func fullMonth() {
        #expect(Self.deck(RecapSamples.month()).cards == [.poster, .opener, .calendar, .timetable, .payback, .scorecard])
    }

    @Test("A full year has the year's own cards")
    func fullYear() {
        #expect(Self.deck(RecapSamples.year()).cards
            == [.poster, .opener, .yearCalendar, .months, .timetable, .payback, .scorecard])
    }

    @Test("No price, no payback")
    func noPrice() {
        #expect(!Self.deck(RecapSamples.month(), price: nil).cards.contains(.payback))
        #expect(!Self.deck(RecapSamples.month(), price: 0).cards.contains(.payback))
        #expect(Self.deck(RecapSamples.month(), price: nil).payback == nil)
    }

    @Test("No cost, no payback, whatever the price")
    func noCost() {
        let deck = Self.deck(RecapSamples.month(priced: false))
        #expect(!deck.cards.contains(.payback))
        #expect(deck.payback == nil)
    }

    @Test("No hour shape, no timetable")
    func noHours() {
        #expect(!Self.deck(RecapSamples.month(hasHours: false)).cards.contains(.timetable))
    }

    @Test("No agents, no opener")
    func noAgents() {
        #expect(!Self.deck(RecapSamples.month(hasAgents: false)).cards.contains(.opener))
    }

    @Test("A recap with nothing in it has no deck")
    func empty() {
        #expect(Self.deck(RecapSamples.empty).cards.isEmpty)
    }

    @Test("The page counter counts the numbered cards the deck really has")
    func pageCounter() throws {
        let full = Self.deck(RecapSamples.month())
        #expect(full.stories.count == 5)
        #expect(full.page(of: .poster) == nil)
        #expect(try #require(full.page(of: .opener)) == (1, 5))
        #expect(try #require(full.page(of: .scorecard)) == (5, 5))

        let bare = Self.deck(RecapSamples.month(priced: false, hasHours: false, hasAgents: false), price: nil)
        #expect(bare.cards == [.poster, .calendar, .scorecard])
        #expect(try #require(bare.page(of: .calendar)) == (1, 2))
        #expect(try #require(bare.page(of: .scorecard)) == (2, 2))
        #expect(bare.page(of: .payback) == nil)
    }

    @Test("Payback divides the estimate by the price")
    func paybackMultiple() throws {
        let payback = try #require(Self.deck(RecapSamples.month()).payback)
        #expect(payback.months == 1)
        #expect(payback.monthlyPrice == 200)
        #expect(payback.paid == 200)
        #expect(!payback.isToDate)
        #expect(abs(payback.multiple - 6.71) < 0.001)
    }

    @Test("Unpriced work keeps the payback card, with the floor noted")
    func unpricedPayback() throws {
        let tenth = Self.deck(RecapSamples.month(unpricedShare: 0.1))
        #expect(tenth.payback != nil)
        #expect(tenth.cards.contains(.payback))
        #expect(tenth.costIsFloor)
        #expect(tenth.provenance.contains(String.localized("Some work had no published price, so the money is a floor.")))

        let sliver = Self.deck(RecapSamples.month(unpricedShare: 0.004))
        #expect(sliver.payback != nil)
        #expect(sliver.costIsFloor)
        #expect(sliver.provenance.contains(String.localized("Some work had no published price, so the money is a floor.")))

        let whole = Self.deck(RecapSamples.month())
        #expect(!whole.costIsFloor)
        #expect(!whole.provenance.contains(String.localized("Some work had no published price, so the money is a floor.")))
        // Nothing priced is no money at all, so there is no floor to speak of.
        #expect(!Self.deck(RecapSamples.month(priced: false, unpricedShare: 1)).costIsFloor)
    }

    private static func running(_ period: Recap.Period, now: Date, tokens: Int = 1_000) -> Recap {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // A record a year back as well, so the records reach before the period
        // and these test the proration by days gone, not `recordsBegin`.
        let yearBack = calendar.date(byAdding: .year, value: -1, to: now)!
        let ledger = UsageLedgerReader.price(
            [UsageLedgerReader.slotKey(for: now, calendar: calendar): ["claude": TokenTally(input: tokens)],
             UsageLedgerReader.slotKey(for: yearBack, calendar: calendar): ["claude": TokenTally(input: 1)]],
            with: ["claude": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, name: "Claude")],
            calendar: calendar
        )
        return Recap.build(
            period, from: [.claudeCode: ledger],
            prices: ["claude": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75, name: "Claude")],
            now: now, calendar: calendar
        )!
    }

    private static func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("A month still running is charged by the days gone, not for the whole month")
    func monthInProgressIsProrated() throws {
        // 10 days of 31.
        let recap = Self.running(.month(year: 2026, month: 10), now: Self.utc(2026, 10, 10))
        #expect(recap.isInProgress)
        let payback = try #require(Self.deck(recap, price: 31).payback)
        #expect(payback.isToDate)
        #expect(abs(payback.months - 10.0 / 31.0) < 1e-9)
        #expect(abs(payback.paid - 10) < 1e-9)
        #expect(payback.monthlyPrice == 31)
    }

    @Test("A year still running is charged twelve months by the days gone over the days in the year")
    func yearInProgressIsProrated() throws {
        // 1 March 2026: 31 + 28 + 1 = 60 days of 365.
        let recap = Self.running(.year(2026), now: Self.utc(2026, 3, 1))
        #expect(recap.elapsedDays == 60)
        let payback = try #require(Self.deck(recap, price: 365).payback)
        #expect(abs(payback.months - 12.0 * 60.0 / 365.0) < 1e-9)
        #expect(abs(payback.paid - 12.0 * 60.0) < 1e-9)
        // A leap year has 366.
        let leap = Self.running(.year(2028), now: Self.utc(2028, 1, 31))
        #expect(abs(RecapDeck.paidMonths(leap) - 12.0 * 31.0 / 366.0) < 1e-9)
    }

    @Test("A finished period is charged whole, as before")
    func finishedIsWhole() {
        #expect(RecapDeck.paidMonths(RecapSamples.month()) == 1)
        #expect(RecapDeck.paidMonths(RecapSamples.year()) == 12)
    }

    @Test("A cache saving under fifty cents is not worth a sentence")
    func smallSavingsAreLeftOut() {
        #expect(Self.deck(RecapSamples.month()).cacheSavings == 410)
        #expect(Self.deck(RecapSamples.month(cacheSavings: 0.5)).cacheSavings == 0.5)
        #expect(Self.deck(RecapSamples.month(cacheSavings: 0.49)).cacheSavings == nil)
        #expect(Self.deck(RecapSamples.month(cacheSavings: 0)).cacheSavings == nil)
        #expect(Self.deck(RecapSamples.month(hasCache: false)).cacheSavings == nil)
    }

    @Test("The poster's cost line is drawn only when every day with work has a price")
    func costSeries() {
        let full = Self.deck(RecapSamples.month())
        #expect(full.costSeries.count == full.recap.days.count)
        // Quiet days are zero, not missing.
        let quiet = zip(full.recap.days, full.costSeries).filter { $0.0.tokens == 0 }
        #expect(!quiet.isEmpty && quiet.allSatisfy { $0.1 == 0 })
        #expect(Self.deck(RecapSamples.month(priced: false)).costSeries.isEmpty)
        #expect(Self.deck(RecapSamples.year()).costSeries.count == 12)
    }

    @Test("A past period never says its streak is still going; a running one does")
    func streakWording() throws {
        let past = Self.deck(RecapSamples.month())
        let streak = try #require(past.streak)
        #expect(!streak.isCurrent)
        #expect(streak.days == past.recap.longestStreak)
        #expect(streak.days <= past.recap.elapsedDays)

        let running = Self.deck(RecapSamples.month(isInProgress: true))
        let current = try #require(running.streak)
        #expect(current.isCurrent == (running.recap.currentStreak > 0))
    }

    @Test("A year's payback is against twelve months of the price")
    func yearPayback() throws {
        let payback = try #require(Self.deck(RecapSamples.year()).payback)
        #expect(payback.months == 12)
        #expect(payback.paid == 2400)
    }

    @Test("Hidden projects are numbered; shown ones keep their name")
    func projects() {
        let recap = RecapSamples.month()
        let shown = Self.deck(recap)
        let hidden = Self.deck(recap, hidesProjects: true)
        #expect(shown.projectName(0, recap.projects[0]) == "pulse")
        #expect(hidden.projectName(0, recap.projects[0]) == String.localized("Project \("1")"))
        #expect(hidden.projectName(2, recap.projects[2]) == String.localized("Project \("3")"))
        #expect(hidden.projectName(0, recap.projects[0]) != "pulse")
    }

    @Test("Money is left out of the cards when nothing was priced")
    func unpricedHidesMoney() {
        let deck = Self.deck(RecapSamples.month(priced: false))
        #expect(deck.recap.cost == nil)
        #expect(deck.provenance.first == String.localized("Counted from this Mac's local records"))
    }
}
