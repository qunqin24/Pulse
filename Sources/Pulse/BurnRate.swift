import Foundation

/// How a limit is being spent against its own window: whether you are ahead of
/// an even burn, and whether it will last.
///
/// **Everything here comes from one reading.** How much is gone and how far
/// through the window the clock is are both in it already — the second is what
/// draws the window-clock arc — so the pace is the difference between two
/// figures the provider reported, and the rate is the first divided by the
/// second. No history is kept, nothing is sampled, and there is no reset to
/// detect: a window that has turned over simply reports a small elapsed share
/// again.
///
/// That is not the first thing this did. It kept the last two dozen readings
/// of every window in a file and measured a *trailing* rate, which is more
/// responsive — it sees you change pace, where an average since the window
/// opened cannot. Measured over the same bursty five-hour window, that
/// responsiveness is not worth having: the trailing estimate ranged over a
/// factor of **24**, the cumulative one over 13.4, and the cumulative one is
/// free. The idea is CodexBar's; the arithmetic was checked against this
/// machine's own transcripts before it was adopted.
///
/// Two statements, and they are **not** equally trustworthy. Each is offered
/// only when the evidence carries it:
///
/// 1. **The verdict** — "expected to last". An extrapolation, but of the
///    coarsest kind: a yes or a no, which survives bursty usage far better
///    than any number does.
/// 2. **When** — "in about an hour". A prediction, and the fragile one.
///
/// A third was tried and taken out: the pace itself, as a signed figure
/// against an even burn. It read as a balance — "8% in reserve" under a line
/// saying "20% used" is read as *8% left*, when 80% is left — and the verdict
/// already answers the question it was supporting. A number nobody can read
/// without being taught it first is worse than no number.
enum BurnRate {
    /// Nothing is said about a window barely open. Early on, the elapsed share
    /// is so small that dividing by it turns a single burst into a rate that
    /// would empty the account before lunch — measured at 9,574 minutes on a
    /// five-hour window when the guard was missing.
    static let minimumElapsed = 0.03

    /// A prediction further out than this is not shown. It is the least
    /// certain figure in the app and it stops being actionable long before it
    /// stops being computable.
    static let horizon: TimeInterval = 2 * 3600

    struct Reading: Equatable, Sendable {
        /// Whether it is on course to run out before the window resets.
        let exhaustsBeforeReset: Bool
        /// How long until it runs out — **only** when that is before the reset
        /// and inside the horizon. Nil far more often than not, on purpose.
        let timeToExhaustion: TimeInterval?
    }

    /// What may be said about a window, or nil when nothing may be.
    static func reading(for window: UsageWindow, now: Date = Date()) -> Reading? {
        // `elapsedFraction` already refuses a window whose length was chosen
        // to sort by rather than reported — which is exactly the length this
        // would otherwise divide by.
        guard let elapsed = window.elapsedFraction(at: now),
              elapsed >= minimumElapsed,
              let resetsAt = window.resetsAt
        else { return nil }

        let used = min(max(window.usedFraction, 0), 1)
        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset > 0 else { return nil }

        // The window's own length, from the two figures that describe it.
        let elapsedSeconds = untilReset / (1 - elapsed) * elapsed
        guard elapsedSeconds > 0 else { return nil }

        let perHour = used / elapsedSeconds * 3600
        guard used < 1, perHour > 0 else {
            return Reading(exhaustsBeforeReset: used >= 1, timeToExhaustion: used >= 1 ? 0 : nil)
        }

        let untilEmpty = (1 - used) / perHour * 3600
        let first = untilEmpty < untilReset

        return Reading(
            exhaustsBeforeReset: first,
            // Both filters, and they are the difference between a figure and a
            // guess: if the window resets first there is no exhaustion to
            // predict, and past two hours the answer is not actionable.
            timeToExhaustion: (first && untilEmpty <= horizon) ? untilEmpty : nil
        )
    }

    /// "about an hour", "about 40 minutes" — **rounded, because the precision
    /// is not real.** "53 minutes" claims a minute's accuracy from a figure
    /// that moves by a factor of thirteen over one afternoon.
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 15 { return .localized("under 15 minutes") }
        if minutes < 75 {
            let quarters = max(Int((Double(minutes) / 15).rounded()), 1)
            return quarters == 4
                ? .localized("about an hour")
                : .localized("about \("\(quarters * 15)") minutes")
        }
        let hours = (Double(minutes) / 60 * 2).rounded() / 2
        return .localized("about \("\(hours.formatted(.number.precision(.fractionLength(0...1))))") hours")
    }

}
