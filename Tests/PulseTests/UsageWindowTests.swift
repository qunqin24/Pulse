import Foundation
import Testing
@testable import Pulse

/// The figure on the ring. Two rules that are easy to "simplify" back into
/// bugs: anything used never reads 0%, and the same rule applies at both ends
/// when the figure is counting down.
@Suite("Reported figures")
struct UsageWindowTests {
    private func window(used: Double, seconds: Int = 5 * 3_600, resetsAt: Date? = nil, reportsLength: Bool = true) -> UsageWindow {
        UsageWindow(
            id: "w",
            kind: .fiveHour,
            scope: nil,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength
        )
    }

    @Test("Nothing used reads 0%; anything used reads at least 1%")
    func smallestNonZeroReadingShows() {
        #expect(window(used: 0).percentText == "0%")
        // Cursor reports 0.03% and its own page says 1%.
        #expect(window(used: 0.0003).percentText == "1%")
        #expect(window(used: 0.004).percentText == "1%")
    }

    @Test("Not quite full never reads 100%")
    func almostFullIsNotFull() {
        #expect(window(used: 0.996).percentText == "99%")
        #expect(window(used: 1).percentText == "100%")
        // A spend limit can sail past its own ceiling.
        #expect(window(used: 1.4).percentText == "100%")
    }

    @Test("Counting down gets the same rule at both ends, not 100 minus the other")
    func remainingIsHeldOffBothEnds() {
        // 99.6% spent still has something left, so it must not read 0% left.
        #expect(window(used: 0.996).percentText(remaining: true) == "1%")
        // 0.4% spent is not everything left either.
        #expect(window(used: 0.004).percentText(remaining: true) == "99%")
        #expect(window(used: 0).percentText(remaining: true) == "100%")
        #expect(window(used: 1).percentText(remaining: true) == "0%")
    }

    @Test("The window clock needs a length the provider actually stated")
    func elapsedNeedsAStatedLength() {
        let now = Date()
        let halfway = window(used: 0.5, resetsAt: now.addingTimeInterval(2.5 * 3_600))
        #expect(halfway.elapsedFraction(at: now).map { abs($0 - 0.5) < 0.01 } == true)

        // A sort key is also a positive number. Dividing by one draws an arc
        // nobody reported.
        let sortKeyOnly = window(used: 0.5, resetsAt: now.addingTimeInterval(3_600), reportsLength: false)
        #expect(sortKeyOnly.elapsedFraction(at: now) == nil)

        // No reset time, nothing to measure against.
        #expect(window(used: 0.5).elapsedFraction(at: now) == nil)
    }
}

/// Which limit the second ring shows. Off by default, so most people never see
/// this — but when it is on it must never pick the one already on the ring,
/// and must draw nothing at all where there is only one limit.
@Suite("The second ring's limit")
struct SecondWindowTests {
    private static func window(_ id: String, used: Double) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: .weekly,
            scope: nil,
            usedFraction: used,
            windowSeconds: 7 * 86_400,
            resetsAt: nil
        )
    }

    private static func usage(_ windows: [UsageWindow]) -> ProviderUsage {
        ProviderUsage(
            account: AccountKey(.claudeCode),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    @Test("One limit draws no second ring")
    func singleWindow() {
        #expect(Self.usage([Self.window("only", used: 0.4)]).secondWindow() == nil)
        // An empty second ring would read as a limit at zero, or as a fault.
        #expect(Self.usage([]).secondWindow() == nil)
    }

    @Test("It is the fullest of the rest, never the one already on the ring")
    func nextFullest() {
        let usage = Self.usage([
            Self.window("5h", used: 0.82),
            Self.window("weekly", used: 0.34),
            Self.window("monthly", used: 0.61)
        ])
        #expect(usage.headlineWindow()?.id == "5h")
        #expect(usage.secondWindow()?.id == "monthly")
    }

    @Test("A pinned ring moves the second one out of its way")
    func followsThePin() {
        let usage = Self.usage([
            Self.window("5h", used: 0.82),
            Self.window("weekly", used: 0.34)
        ])
        // Pinning the *emptier* limit to the ring leaves the fuller one for
        // the inner ring — stated as "the fullest of the rest" so it needs no
        // table of which window each provider calls its long one.
        #expect(usage.headlineWindow(preferring: "weekly")?.id == "weekly")
        #expect(usage.secondWindow(preferring: "weekly")?.id == "5h")
    }

    @Test("Two limits at the same figure still resolve to two different rings")
    func ties() throws {
        let usage = Self.usage([Self.window("a", used: 0.5), Self.window("b", used: 0.5)])
        let headline = try #require(usage.headlineWindow())
        let second = try #require(usage.secondWindow())
        #expect(headline.id != second.id)
    }
}
