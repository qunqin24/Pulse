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

    /// The list is short on purpose: it is the providers whose money moves
    /// where this Mac cannot see it.
    @Test("Only the balance providers are unwatched")
    func onlyBalanceProvidersAreUnwatched() {
        for provider in Provider.allCases {
            #expect(provider.spendingIsWatchedLocally == !provider.reportsSpendableBalance,
                    "\(provider.rawValue)")
        }
        #expect(Provider.deepSeek.spendingIsWatchedLocally == false)
        #expect(Provider.claudeCode.spendingIsWatchedLocally)
    }
}
