import Foundation

/// How fast a limit is going, and whether it will outlast its own window.
///
/// Three statements, and they are **not** equally trustworthy — which is the
/// whole design of this file. Each is offered only when the evidence carries
/// it, and each is withheld separately rather than the three standing or
/// falling together:
///
/// 1. **The rate** — "12% an hour". A description of what already happened,
///    from two figures the provider itself reported. This is measurement.
/// 2. **The verdict** — "this will run out before it resets". An
///    extrapolation, but of the coarsest possible kind: a yes or a no, which
///    survives usage being bursty far better than any number does.
/// 3. **When** — "in about an hour". A prediction, and the fragile one.
///
/// Measured against three days of this machine's real transcripts, the reason
/// for that ordering is stark. Over one continuous 3.2-hour working session,
/// re-asked every five minutes: the verdict changed 4 times out of 35, and all
/// four around the point where the answer was genuinely borderline. The
/// "when", over the same stretch, ranged from **89 minutes to 9,574** — six
/// days, for a five-hour window.
///
/// So (3) is shown only when it lands **before the reset**. That is not a
/// tuning knob; if the window resets first there is no exhaustion to predict,
/// and the honest sentence is the verdict alone. The same filter took the
/// range from 89–9,574 to 89–204, and a second — only when it is within two
/// hours — to 89–109.
///
/// Usage is *extremely* bursty: over three days, 3% of five-minute slots had
/// any activity at all, and the busiest was six times the median. Anything
/// here that reads as precise is wrong.
enum BurnRate {
    /// How much has to be seen before any of this is said.
    ///
    /// Two samples make a rate; they make a very bad one. Four spanning a
    /// quarter of an hour is the least that can distinguish a burst from a
    /// pace, and the refresh loop reaches it in minutes while a window is
    /// actually moving.
    static let minimumSamples = 4
    static let minimumSpan: TimeInterval = 15 * 60

    /// Below this the rate is indistinguishable from nothing happening, and
    /// dividing by it produces the six-day answers. A window moving slower
    /// than a percent an hour will not run out inside any window Pulse sees.
    static let minimumRate = 0.01

    /// A prediction further out than this is not shown. It is the least
    /// certain figure in the app and it stops being actionable long before it
    /// stops being computable.
    static let horizon: TimeInterval = 2 * 3600

    struct Reading: Equatable, Sendable {
        /// Fraction of the limit per hour, as measured.
        let perHour: Double
        /// Whether the limit is on course to run out before the window resets.
        /// Nil when the window never says when it resets.
        let exhaustsBeforeReset: Bool?
        /// How long until it runs out — **only** when that is before the reset
        /// and inside the horizon. Nil far more often than not, on purpose.
        let timeToExhaustion: TimeInterval?
    }

    /// Works out what may be said about a window, or nil when nothing may be.
    ///
    /// `samples` must already be on one side of a reset — `UsageTrail.samples`
    /// does that — because differencing across one gives a negative rate.
    static func reading(
        for window: UsageWindow,
        from samples: [UsageTrail.Sample],
        now: Date = Date()
    ) -> Reading? {
        guard samples.count >= minimumSamples,
              let first = samples.first, let last = samples.last
        else { return nil }

        let span = last.at.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return nil }

        let climbed = last.usedFraction - first.usedFraction
        let perHour = climbed / span * 3600
        guard perHour >= minimumRate else { return nil }

        // Measured from the newest reading rather than from whatever is on
        // screen: the card may be showing a cached figure minutes old, and the
        // arithmetic should not mix the two.
        let remaining = max(1 - last.usedFraction, 0)
        let untilEmpty = remaining / perHour * 3600

        guard let resetsAt = window.resetsAt else {
            return Reading(perHour: perHour, exhaustsBeforeReset: nil, timeToExhaustion: nil)
        }

        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset > 0 else {
            return Reading(perHour: perHour, exhaustsBeforeReset: nil, timeToExhaustion: nil)
        }

        let first_ = untilEmpty < untilReset
        return Reading(
            perHour: perHour,
            exhaustsBeforeReset: first_,
            // Both filters, and they are the difference between a figure and a
            // guess. See the note above the type.
            timeToExhaustion: (first_ && untilEmpty <= horizon) ? untilEmpty : nil
        )
    }

    /// "about an hour", "about 40 minutes" — **rounded, because the precision
    /// is not real.** "53 minutes" claims a minute's accuracy from a figure
    /// that moved by a factor of thirty-six over one afternoon.
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 15 { return .localized("under 15 minutes") }
        if minutes < 75 {
            // To the nearest quarter hour, which is as fine as this deserves.
            let quarters = max(Int((Double(minutes) / 15).rounded()), 1)
            return quarters == 4
                ? .localized("about an hour")
                : .localized("about \("\(quarters * 15)") minutes")
        }
        let hours = (Double(minutes) / 60 * 2).rounded() / 2
        return .localized("about \("\(hours.formatted(.number.precision(.fractionLength(0...1))))") hours")
    }

    /// "12% an hour".
    static func rateText(_ perHour: Double) -> String {
        let percent = perHour * 100
        let shown = percent >= 10
            ? "\(Int(percent.rounded()))"
            : percent.formatted(.number.precision(.fractionLength(0...1)))
        // The sign goes **into** the value, never beside the placeholder:
        // "%@% an hour" is a malformed printf conversion, the lookup misses,
        // and the line silently reverts to English. Documented in CLAUDE.md,
        // and walked into anyway.
        return .localized("\("\(shown)%") an hour")
    }
}
