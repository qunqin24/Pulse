import Foundation
import Testing
@testable import Pulse

/// The notification rules, which are the reason `AlertMemory.alerts` was
/// written as a pure function in the first place: it reads no clock, no disk
/// and no notification centre, so every rule below is decidable from its
/// arguments. See [Docs/notifications.md](../../Docs/notifications.md) for why
/// each rule is the way it is — these prove that it is.
@Suite("Alert rules")
struct AlertMemoryTests {
    // MARK: - Building readings

    private static let account = AccountKey(.claudeCode)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        _ id: String = "weekly",
        used: Double,
        resetsAt: Date? = nil,
        exhausted: Bool = false
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: .weekly,
            scope: nil,
            usedFraction: used,
            windowSeconds: 7 * 86_400,
            resetsAt: resetsAt,
            isExhausted: exhausted
        )
    }

    private static func live(_ windows: UsageWindow..., at observedAt: Date = now) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: windows,
            observedAt: observedAt,
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    private static func unavailable(_ reason: ProviderUsage.Unavailability) -> ProviderUsage {
        .unavailable(account, reason: reason)
    }

    private static func stale(observedAt: Date) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [window(used: 0.5)],
            observedAt: observedAt,
            state: .stale,
            plan: nil,
            creditBalance: nil
        )
    }

    /// Everything on, threshold at 90, unless a test says otherwise.
    private func run(
        _ memory: inout AlertMemory,
        _ reading: ProviderUsage,
        threshold: AlertThreshold = .ninety,
        announcesReset: Bool = true,
        announcesFailure: Bool = true,
        staleMeansFailure: Bool = true,
        now: Date = AlertMemoryTests.now
    ) -> [UsageAlert] {
        memory.alerts(
            for: reading,
            as: Self.account,
            threshold: threshold,
            announcesReset: announcesReset,
            announcesFailure: announcesFailure,
            staleMeansFailure: staleMeansFailure,
            now: now
        )
    }

    // MARK: - Thresholds

    @Test("A limit already past the line is announced once, immediately")
    func firstSightingOverTheLine() {
        var memory = AlertMemory()

        let first = run(&memory, Self.live(Self.window(used: 0.93)))
        #expect(first.count == 1)
        #expect(first.first?.kind == .approaching(percent: 90))

        // Still over it on the next pass, and nothing more to say.
        #expect(run(&memory, Self.live(Self.window(used: 0.94))).isEmpty)
    }

    @Test("A limit under the line says nothing")
    func firstSightingUnderTheLine() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.42))).isEmpty)
    }

    @Test("Crossing the line while Pulse is watching announces")
    func crossingTheLine() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.80))).isEmpty)

        let crossed = run(&memory, Self.live(Self.window(used: 0.91)))
        #expect(crossed.map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("Off means silent, however full the limit is")
    func thresholdOff() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 1.0, exhausted: true)), threshold: .off).isEmpty)
    }

    @Test("Lowering the threshold announces the step that is now crossed")
    func loweringTheThreshold() {
        var memory = AlertMemory()
        // 80% with the line at 90 records nothing announced.
        #expect(run(&memory, Self.live(Self.window(used: 0.80)), threshold: .ninety).isEmpty)

        let lowered = run(&memory, Self.live(Self.window(used: 0.80)), threshold: .seventyFive)
        #expect(lowered.map(\.kind) == [.approaching(percent: 75)])
    }

    // MARK: - Spent is the provider's word

    @Test("`isExhausted` is spent, whatever the fraction says")
    func exhaustedFlagWins() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(Self.window(used: 0.5, exhausted: true)))
        #expect(alerts.map(\.kind) == [.spent])
    }

    @Test("99.6% is not spent — the fraction only reaches 100 rounding down")
    func almostSpentIsNotSpent() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(Self.window(used: 0.996)))
        #expect(alerts.map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("Spent follows the warning rather than replacing it")
    func warningThenSpent() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.live(Self.window(used: 0.91))).map(\.kind) == [.approaching(percent: 90)])
        #expect(run(&memory, Self.live(Self.window(used: 1.0))).map(\.kind) == [.spent])
        // And not a third time.
        #expect(run(&memory, Self.live(Self.window(used: 1.0))).isEmpty)
    }

    // MARK: - Resets

    @Test("A reset time that moved forward is a new window")
    func resetTimeMovedForward() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(&memory, Self.live(Self.window(used: 0.95, resetsAt: first)))

        let alerts = run(&memory, Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(7 * 86_400))))
        #expect(alerts.map(\.kind) == [.reset])
    }

    @Test("A rolling window sliding down a few points is not a reset")
    func rollingWindowIsNotAReset() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        // Kimi's week can reset anywhere inside it, so the figure drifts down
        // without anything having turned over. Six points is drift.
        #expect(run(&memory, Self.live(Self.window(used: 0.89))).isEmpty)
    }

    @Test("A window oscillating across the line is announced once, not once per wobble")
    func oscillationDoesNotReAnnounce() {
        var memory = AlertMemory()
        // Clearing the announced step on any drop — rather than on the same
        // evidence that would announce a reset — re-armed a window that had
        // not reset. A rolling allowance crossing back and forth then said
        // "93% used" again, and again, for as long as it wobbled.
        #expect(run(&memory, Self.live(Self.window(used: 0.95))).count == 1)
        #expect(run(&memory, Self.live(Self.window(used: 0.89))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.93))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.88))).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.97))).isEmpty)
    }

    @Test("A real turnover still re-arms the step after an oscillation")
    func turnoverStillRearms() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))
        _ = run(&memory, Self.live(Self.window(used: 0.89)))

        // Unambiguous this time: a forty-point drop.
        #expect(run(&memory, Self.live(Self.window(used: 0.05))).map(\.kind) == [.reset])
        #expect(run(&memory, Self.live(Self.window(used: 0.94))).map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("A drop of forty points with no reset time is a reset")
    func bigDropIsAReset() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        #expect(run(&memory, Self.live(Self.window(used: 0.10))).map(\.kind) == [.reset])
    }

    @Test("A window that was never warned about resets quietly")
    func unannouncedWindowResetsQuietly() {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_800_003_600)
        _ = run(&memory, Self.live(Self.window(used: 0.12, resetsAt: first)))

        let alerts = run(&memory, Self.live(Self.window(used: 0.0, resetsAt: first.addingTimeInterval(7 * 86_400))))
        #expect(alerts.isEmpty)
    }

    @Test("A reset clears the step, so the next crossing is announced again")
    func resetRearmsTheThreshold() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))
        _ = run(&memory, Self.live(Self.window(used: 0.10)))

        #expect(run(&memory, Self.live(Self.window(used: 0.92))).map(\.kind) == [.approaching(percent: 90)])
    }

    @Test("The reset switch off means no reset alert, but the step still clears")
    func resetSwitchOff() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)), announcesReset: false)
        #expect(run(&memory, Self.live(Self.window(used: 0.10)), announcesReset: false).isEmpty)
        #expect(run(&memory, Self.live(Self.window(used: 0.92)), announcesReset: false)
            .map(\.kind) == [.approaching(percent: 90)])
    }

    // MARK: - Failures

    @Test("Three failed passes in a row, then one alert and silence")
    func failureStreak() {
        var memory = AlertMemory()
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)

        let third = run(&memory, Self.unavailable(.unreachable))
        #expect(third.map(\.kind) == [.unreadable(.unreachable)])

        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
    }

    @Test("A reading that works clears the streak")
    func successClearsTheStreak() {
        var memory = AlertMemory()
        for _ in 1...3 { _ = run(&memory, Self.unavailable(.unreachable)) }

        _ = run(&memory, Self.live(Self.window(used: 0.1)))

        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).isEmpty)
        #expect(run(&memory, Self.unavailable(.unreachable)).count == 1)
    }

    @Test("A setup step nobody has taken is not a failure, however often it is seen")
    func steadyStatesAreNotFailures() {
        for reason: ProviderUsage.Unavailability in [
            .apiKeyMissing, .notSignedIn, .antigravityNotRunning, .grokBotNotIncluded,
            .noLimitsReported, .loading, .codexNotInstalled
        ] {
            var memory = AlertMemory()
            for _ in 1...5 {
                #expect(run(&memory, Self.unavailable(reason)).isEmpty, "\(reason) should never alert")
            }
        }
    }

    @Test("A credential that went bad is a failure")
    func badCredentialsAreFailures() {
        for reason: ProviderUsage.Unavailability in [
            .claudeLoginExpired, .cursorLoginExpired, .grokLoginExpired,
            .signedOut, .apiKeyRefused, .serverError
        ] {
            var memory = AlertMemory()
            _ = run(&memory, Self.unavailable(reason))
            _ = run(&memory, Self.unavailable(reason))
            #expect(run(&memory, Self.unavailable(reason)).count == 1, "\(reason) should alert")
        }
    }

    @Test("Failures are still counted while the limit threshold is off")
    func failuresAreIndependentOfTheThreshold() {
        var memory = AlertMemory()
        for _ in 1...2 { _ = run(&memory, Self.unavailable(.unreachable), threshold: .off) }
        #expect(run(&memory, Self.unavailable(.unreachable), threshold: .off).count == 1)
    }

    @Test("The failure switch off means silence, however long the outage")
    func failureSwitchOff() {
        var memory = AlertMemory()
        for _ in 1...5 {
            #expect(run(&memory, Self.unavailable(.unreachable), announcesFailure: false).isEmpty)
        }
    }

    // MARK: - Stale is judged on age

    @Test("Fresh figures from the cache are not a failure")
    func freshStaleIsNotAFailure() {
        var memory = AlertMemory()
        // The trap: `reconciled` returns a stale reading for a *successful*
        // fetch too, when what was banked is newer than what came back.
        let recent = Self.now.addingTimeInterval(-120)
        for _ in 1...5 {
            #expect(run(&memory, Self.stale(observedAt: recent)).isEmpty)
        }
    }

    @Test("A push route going quiet is never a failure, however old the figures")
    func pushRouteStalenessIsNotAFailure() {
        var memory = AlertMemory()
        // Claude Code's status line only writes while a session runs. Hours
        // old means nobody has used it, not that a check failed — and the
        // copy would have said "the last few checks didn't get through" about
        // checks that all got through.
        let ancient = Self.now.addingTimeInterval(-6 * 3_600)
        for _ in 1...6 {
            #expect(run(&memory, Self.stale(observedAt: ancient), staleMeansFailure: false).isEmpty)
        }
    }

    @Test("Only Claude Code's push routes are spared, and only for the primary account")
    func pushRouteIsPerRouteNotPerProvider() {
        let claude = AccountKey(.claudeCode)
        // The status line, and the automatic route that can fall back to it.
        #expect(UsageSource.tooling.reportsOnlyWhenUsed(for: claude))
        #expect(UsageSource.automatic.reportsOnlyWhenUsed(for: claude))
        // These ask a server on every pass, so silence would hide a real
        // outage — which is what asking the *provider* instead of the route
        // did, for the provider Pulse is most about.
        #expect(!UsageSource.endpoint.reportsOnlyWhenUsed(for: claude))
        #expect(!UsageSource.desktopApp.reportsOnlyWhenUsed(for: claude))
        // An added account has no status line at all: it is reached over HTTP
        // and nothing else.
        #expect(!UsageSource.automatic.reportsOnlyWhenUsed(for: AccountKey(.claudeCode, slot: "work")))
        // And no other provider has a push route.
        for provider in Provider.allCases where provider != .claudeCode {
            #expect(!UsageSource.automatic.reportsOnlyWhenUsed(for: AccountKey(provider)),
                    "\(provider) should not be spared")
        }
    }

    @Test("Antigravity open but refusing is not a failure; nothing running is not either")
    func antigravityReasonsAreSpared() {
        var memory = AlertMemory()
        for reason: ProviderUsage.Unavailability in [.antigravityNotAnswering, .antigravityNotRunning] {
            memory = AlertMemory()
            for _ in 1...5 {
                #expect(run(&memory, Self.unavailable(reason)).isEmpty, "\(reason) alerted")
            }
        }
    }

    @Test("Figures older than half an hour are a failure")
    func agedStaleIsAFailure() {
        var memory = AlertMemory()
        let old = Self.now.addingTimeInterval(-3_600)
        _ = run(&memory, Self.stale(observedAt: old))
        _ = run(&memory, Self.stale(observedAt: old))
        #expect(run(&memory, Self.stale(observedAt: old)).map(\.kind) == [.unreadable(nil)])
    }

    @Test("A stale reading never drives the limit rules")
    func staleDoesNotDriveWindows() {
        var memory = AlertMemory()
        _ = run(&memory, Self.live(Self.window(used: 0.95)))

        // Cached windows can be lower than what was already recorded. Run
        // through the reset rules they would announce a turnover that never
        // happened.
        let cached = ProviderUsage(
            account: Self.account,
            windows: [Self.window(used: 0.10)],
            observedAt: Self.now.addingTimeInterval(-60),
            state: .stale,
            plan: nil,
            creditBalance: nil
        )
        #expect(run(&memory, cached).isEmpty)
    }

    // MARK: - Several limits at once

    @Test("Each limit is judged on its own")
    func windowsAreIndependent() {
        var memory = AlertMemory()
        let alerts = run(&memory, Self.live(
            Self.window("weekly", used: 0.95),
            Self.window("5h", used: 0.20)
        ))
        #expect(alerts.count == 1)
        #expect(alerts.first?.window?.id == "weekly")
    }
}
