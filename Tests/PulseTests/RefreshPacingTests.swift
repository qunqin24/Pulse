import Foundation
import Testing
@testable import Pulse

/// How long `.automatic` waits, and the one asymmetry in it.
///
/// Every signal `AdaptiveRefresh` reads is local — an agent writing
/// transcripts here, a figure that moved, the panel being looked at. That is
/// deliberate and it is the module's whole advantage, but it means a provider
/// billed entirely on its own servers is invisible to all three and lands on
/// the ceiling every time. Circular, too: it waits half an hour because
/// nothing changed, and nothing appears to have changed because it waited.
@Suite("Refresh pacing")
struct RefreshPacingTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func quiet(for seconds: TimeInterval) -> AdaptiveRefresh.Signals {
        AdaptiveRefresh.Signals(lastChange: now.addingTimeInterval(-seconds))
    }

    private static func interval(
        _ signals: AdaptiveRefresh.Signals,
        isWatched: Bool = true
    ) -> TimeInterval {
        AdaptiveRefresh.interval(for: signals, isWatched: isWatched, now: now)
    }

    @Test("A quiet provider this Mac can watch is left for the full ceiling")
    func watchedProvidersReachTheCeiling() {
        #expect(Self.interval(Self.quiet(for: 6 * 3_600)) == AdaptiveRefresh.ceiling)
    }

    @Test("A quiet provider it cannot watch is capped well short of it")
    func unwatchedProvidersAreCapped() {
        let wait = Self.interval(Self.quiet(for: 6 * 3_600), isWatched: false)
        #expect(wait == AdaptiveRefresh.unwatchedCeiling)
        #expect(wait < AdaptiveRefresh.ceiling)
    }

    /// Nothing recorded at all is the state a fresh launch is in, and it used
    /// to mean the ceiling outright.
    @Test("No signals at all is capped too")
    func silenceIsCapped() {
        #expect(Self.interval(.init(), isWatched: false) == AdaptiveRefresh.unwatchedCeiling)
        #expect(Self.interval(.init()) == AdaptiveRefresh.ceiling)
    }

    /// The cap may only ever *lower* a wait. Where something is happening, the
    /// ladder already asks sooner than the cap and the cap does nothing.
    @Test("The cap never makes anything wait longer than it would have")
    func theCapOnlyLowers() {
        for age: TimeInterval in [60, 300, 1_800, 4 * 3_600, 24 * 3_600] {
            let watched = Self.interval(Self.quiet(for: age))
            let unwatched = Self.interval(Self.quiet(for: age), isWatched: false)
            #expect(unwatched <= watched, "quiet for \(age)s")
        }
    }

    /// A constrained Mac and a hidden panel are statements about **this
    /// machine**, not about the provider, so they still win.
    @Test("A hidden panel and a constrained Mac still get the full ceiling")
    func machineStateOutranksTheCap() {
        var hidden = Self.quiet(for: 60)
        hidden.isPanelVisible = false
        #expect(Self.interval(hidden, isWatched: false) == AdaptiveRefresh.ceiling)

        var constrained = Self.quiet(for: 60)
        constrained.isConstrained = true
        #expect(Self.interval(constrained, isWatched: false) == AdaptiveRefresh.ceiling)
    }

    // MARK: - Which accounts a pass asks

    private static let deepSeek = AccountKey(.deepSeek)
    private static let claude = AccountKey(.claudeCode)

    private static func asked(_ seconds: TimeInterval) -> [AccountKey: Date] {
        [deepSeek: now.addingTimeInterval(-seconds), claude: now.addingTimeInterval(-seconds)]
    }

    private static func toAsk(dueOnly: Bool, askedAt: [AccountKey: Date]) -> Set<AccountKey> {
        UsageStore.accountsToAsk(
            from: [deepSeek, claude],
            dueOnly: dueOnly,
            askedAt: askedAt,
            interval: { $0 == .deepSeek ? AdaptiveRefresh.unwatchedCeiling : AdaptiveRefresh.ceiling },
            now: now
        )
    }

    /// **The bug this exists to prevent is not a slow refresh, it is a control
    /// that does nothing.** Switching DeepSeek between "since top-up" and
    /// "balance only" changes what the reading means, and a pass that skipped
    /// the provider because it had been asked a minute ago left the old ring
    /// on screen for up to five minutes.
    @Test("Anything but the timer asks everything, however recently it was asked")
    func onlyTheTimerHonoursTheCadence() {
        #expect(Self.toAsk(dueOnly: false, askedAt: Self.asked(1)) == [Self.deepSeek, Self.claude])
    }

    @Test("The timer asks only what its own cadence says is due")
    func theTimerAsksWhatIsDue() {
        // Six minutes: past DeepSeek's five-minute cap, nowhere near the
        // half-hour ceiling the other one is on.
        #expect(Self.toAsk(dueOnly: true, askedAt: Self.asked(6 * 60)) == [Self.deepSeek])
        // Neither, a minute in.
        #expect(Self.toAsk(dueOnly: true, askedAt: Self.asked(60)).isEmpty)
        // Both, once the slower one comes round.
        #expect(Self.toAsk(dueOnly: true, askedAt: Self.asked(31 * 60)) == [Self.deepSeek, Self.claude])
    }

    @Test("An account never asked is due")
    func neverAskedIsDue() {
        #expect(Self.toAsk(dueOnly: true, askedAt: [:]) == [Self.deepSeek, Self.claude])
    }

    /// A timer that fires a hair early must not skip the very provider it woke
    /// up for and then sleep another full interval.
    @Test("A tick landing just short of the interval still counts as due")
    func theSlackCoversAnEarlyTick() {
        let justShort = AdaptiveRefresh.unwatchedCeiling - UsageStore.dueSlack / 2
        #expect(Self.toAsk(dueOnly: true, askedAt: Self.asked(justShort)).contains(Self.deepSeek))
    }

    @Test("A faster provider does not pull an added account onto its cadence")
    func addedAccountKeepsItsCadence() {
        let extra = AccountKey(.codex, slot: "extra")
        let accounts = [Self.deepSeek, extra]
        let askedAt = Dictionary(uniqueKeysWithValues: accounts.map { ($0, Self.now) })
        let interval: (Provider) -> TimeInterval = {
            $0 == .deepSeek ? AdaptiveRefresh.unwatchedCeiling : AdaptiveRefresh.ceiling
        }
        let fiveMinutesLater = Self.now.addingTimeInterval(5 * 60)
        #expect(UsageStore.accountsToAsk(
            from: accounts, dueOnly: true, askedAt: askedAt, interval: interval, now: fiveMinutesLater
        ) == [Self.deepSeek])
        #expect(UsageStore.accountsToAsk(
            from: accounts, dueOnly: false, askedAt: askedAt, interval: interval, now: fiveMinutesLater
        ) == Set(accounts))
        #expect(UsageStore.accountsToAsk(
            from: accounts, dueOnly: true, askedAt: askedAt, interval: interval,
            now: Self.now.addingTimeInterval(30 * 60)
        ) == Set(accounts))
    }

    @Test("Accounts of one provider have separate deadlines")
    func eachAccountHasItsOwnDeadline() {
        let primary = AccountKey(.codex)
        let extra = AccountKey(.codex, slot: "extra")
        let askedAt = [primary: Self.now, extra: Self.now.addingTimeInterval(-300)]
        #expect(UsageStore.accountsToAsk(
            from: [primary, extra], dueOnly: true, askedAt: askedAt, interval: { _ in 300 }, now: Self.now
        ) == [extra])
    }

    @Test("Only added accounts still schedule the chosen fixed interval")
    func addedAccountsSetTheTimer() {
        let first = AccountKey(.codex, slot: "first")
        let second = AccountKey(.codex, slot: "second")
        let askedAt = [first: Self.now, second: Self.now.addingTimeInterval(-60)]
        #expect(UsageStore.nextRefreshDelay(
            from: [first, second], askedAt: askedAt, interval: { _ in 300 }, now: Self.now
        ) == 240)
        #expect(UsageStore.nextRefreshDelay(
            from: [first, second], askedAt: [first: Self.now], interval: { _ in 300 }, now: Self.now
        ) == 0)
    }

    @Test("Off-rail accounts neither get asked nor set the timer")
    func onlyShownAccountsCount() {
        let enabled = AccountKey(.codex, slot: "enabled")
        let disabled = AccountKey(.codex, slot: "disabled")
        let askedAt = [enabled: Self.now, disabled: Self.now.addingTimeInterval(-3_600)]
        #expect(UsageStore.accountsToAsk(
            from: [enabled], dueOnly: true, askedAt: askedAt, interval: { _ in 300 }, now: Self.now
        ).isEmpty)
        #expect(UsageStore.nextRefreshDelay(
            from: [enabled], askedAt: askedAt, interval: { _ in 300 }, now: Self.now
        ) == 300)
        #expect(UsageStore.nextRefreshDelay(
            from: [], askedAt: askedAt, interval: { _ in 300 }, now: Self.now
        ) == nil)
    }

    /// The list is short on purpose: it is the providers whose spending moves
    /// where this Mac cannot see it.
    ///
    /// **Named rather than derived**, because the derivation is a test about
    /// *money* and the question is about visibility. V2EX is the case that
    /// pulled them apart: its allowance is counted in tokens, so
    /// `reportsSpendableBalance` says nothing about it, while it is spent in a
    /// browser on somebody else's site and its window does not even start on a
    /// clock. Checking the two properties against each other would have let it
    /// inherit `true` in silence.
    @Test("Only the providers this Mac cannot watch are unwatched")
    func onlyUnwatchableProvidersAreUnwatched() {
        let unwatched: Set<Provider> = [.deepSeek, .commandCode, .sub2api, .newAPI, .v2ex]
        for provider in Provider.allCases {
            #expect(provider.spendingIsWatchedLocally == !unwatched.contains(provider),
                    "\(provider.rawValue)")
        }
        #expect(Provider.claudeCode.spendingIsWatchedLocally)
    }

    // MARK: - Which providers' moves shorten the interval

    private static func reading(_ provider: Provider, used: Double, at observedAt: Date = now) -> ProviderUsage {
        ProviderUsage(
            account: AccountKey(provider),
            windows: [UsageWindow(
                id: "devin-daily", kind: .daily, scope: nil,
                usedFraction: used, windowSeconds: 86_400, resetsAt: nil
            )],
            observedAt: observedAt,
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    private static func result(
        _ provider: Provider,
        used: Double,
        at observedAt: Date = now
    ) -> UsageStore.BatchResult {
        let after = Self.reading(provider, used: used, at: observedAt)
        return UsageStore.BatchResult(provider: provider, raw: after, fetched: after)
    }

    /// **The bug was an omission, not a slow refresh.** Devin is fetched by
    /// the pass and written to the table, but its row was left out of the
    /// hand-written list the "did anything move" test walked — so its figures
    /// could move forever without ever shortening the interval. The comparison
    /// now runs over the same collection the commit loop uses, and this pins
    /// that any provider in that collection counts.
    @Test("A provider's figures moving counts, Devin included")
    func aMoveCounts() {
        let before = Self.reading(.devin, used: 0.1)
        let results = [Self.result(.devin, used: 0.4)]

        #expect(UsageStore.didAnythingMove(results, previous: [before.account.id: before]))
    }

    @Test("A re-fetch that only advances the clock is not a move")
    func observedAtDoesNotCountAsAMove() {
        let before = Self.reading(.devin, used: 0.4, at: Self.now)
        // A minute later, same windows.
        let results = [Self.result(.devin, used: 0.4, at: Self.now.addingTimeInterval(60))]

        // `didAnythingMove` compares windows only, so a fresh stamp over the
        // same figures does not keep the loop at its floor.
        #expect(!UsageStore.didAnythingMove(results, previous: [before.account.id: before]))
    }

    @Test("A pass that fetched nothing cannot report a move")
    func noResultsNoMove() {
        // Not asked is not moved: an off-rail provider still holding a reading
        // must not pin the interval at its floor on every pass.
        let before = Self.reading(.devin, used: 0.4)
        #expect(!UsageStore.didAnythingMove([], previous: [before.account.id: before]))
    }

    /// The regression test the omission calls for: the comparison is asked of
    /// **every** provider, not a hand-picked subset, so a provider added to
    /// the pass cannot be committed and silently left out of the change test.
    @Test("Every provider a pass reports can shorten the interval")
    func everyProviderCanMove() {
        for provider in Provider.allCases {
            let before = Self.reading(provider, used: 0.1)
            let results = [Self.result(provider, used: 0.4)]

            #expect(
                UsageStore.didAnythingMove(results, previous: [before.account.id: before]),
                "\(provider.rawValue) moves were not counted"
            )
        }
    }

    @Test("An account with no previous reading counts as moved")
    func aFirstReadingCounts() {
        // Nothing was on screen, so the figures are new to the rail.
        #expect(UsageStore.didAnythingMove([Self.result(.devin, used: 0.4)], previous: [:]))
    }
}
