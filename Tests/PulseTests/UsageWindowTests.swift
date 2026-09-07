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
