import Foundation

/// How long to wait before asking again, when the interval is left on
/// automatic.
///
/// A fixed cadence is wrong in both directions at once: a minute is too slow
/// to watch a limit you are actively burning through, and far too fast for
/// figures that haven't moved since last night. So the wait is decided from
/// what is actually going on, and the strongest signal is the one Pulse has
/// and a menu-bar app doesn't — the agents write their transcripts to this
/// Mac, so it can see whether either of them is running *right now* without
/// asking anyone's server.
///
/// Everything here is a reason to wait *longer*; the floor is what you get
/// when something is happening. Deciding it this way round means a new signal
/// can only ever save requests, never spend more of them.
enum AdaptiveRefresh {
    /// Fast enough that a limit moving under you is visible, slow enough that
    /// it is nobody's idea of hammering.
    static let floor: TimeInterval = 120
    static let ceiling: TimeInterval = 1800

    struct Signals: Sendable, Equatable {
        /// When either agent last wrote to its transcripts.
        var lastAgentActivity: Date?
        /// When the reported figures last actually moved.
        var lastChange: Date?
        /// When the user last hovered the rail to read a card.
        var lastLooked: Date?
        var isPanelVisible: Bool = true
        /// Low power mode, a hot machine, or the display asleep — all of them
        /// reasons to stop waking the radio every couple of minutes.
        var isConstrained: Bool = false
    }

    static func interval(for signals: Signals, now: Date = Date()) -> TimeInterval {
        if signals.isConstrained { return ceiling }

        // Nothing on screen is showing these numbers, so there is nothing to
        // keep current. The panel coming back triggers a refresh of its own.
        if !signals.isPanelVisible { return ceiling }

        // The most recent sign that anyone — user or agent — cares.
        let ages = [signals.lastAgentActivity, signals.lastChange, signals.lastLooked]
            .compactMap { $0.map { now.timeIntervalSince($0) } }
            .filter { $0 >= 0 }

        guard let quiet = ages.min() else { return ceiling }

        switch quiet {
        case ..<(5 * 60): return floor
        case ..<(60 * 60): return 300
        case ..<(4 * 60 * 60): return 900
        default: return ceiling
        }
    }
}
