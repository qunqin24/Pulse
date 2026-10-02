// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Remembers when an account's limit last turned over.
///
/// The rail's animated mark celebrates a reset, and a celebration has to be
/// about something that happened: this watches live readings go past and
/// records the moment one of an account's windows turned over, by the same
/// test the reset notification uses — `UsageWindow.hasTurnedOver(since:)`.
///
/// **Separate from `UsageAlerts`' own memory on purpose.** The alert rules
/// keep a richer record, but the whole of that loop sits behind "notifications
/// are switched on", and the mark is not a notification: it has to work for
/// somebody who has every alert off. Sharing the *rule* and not the bookkeeping
/// is what keeps the two from drifting while leaving the announcement path
/// untouched.
@MainActor
final class ResetWatch {
    /// What a window looked like when it was last seen live.
    private struct Seen {
        var fraction: Double
        var resetsAt: Date?
    }

    private var windows: [String: [String: Seen]] = [:]
    private var resets: [String: Date] = [:]

    /// Takes a reading in. Only live ones: a cached reading carries whatever
    /// was banked, which can be *lower* than what is recorded here — and a
    /// figure that falls is exactly how a reset is recognised, so running the
    /// cache through this would celebrate every network hiccup.
    func observe(_ reading: ProviderUsage, as account: AccountKey, now: Date = Date()) {
        // The same gate the alert rules put in front of this test, and for
        // the reasons written there: a live reading, one that is actually
        // recent, and windows that have not already outlived themselves
        // between two polls. Sharing the rule and not the gate is how the two
        // would drift apart.
        guard case .live = reading.state,
              let observedAt = reading.observedAt,
              now.timeIntervalSince(observedAt) <= UsageCache.maximumAge else { return }
        var seen = windows[account.id] ?? [:]
        for window in reading.windows where window.resetsAt.map({ $0 > now }) ?? true {
            if let previous = seen[window.id],
               window.hasTurnedOver(since: previous.fraction, resetsAt: previous.resetsAt) {
                resets[account.id] = now
            }
            seen[window.id] = Seen(fraction: window.usedFraction, resetsAt: window.resetsAt)
        }
        windows[account.id] = seen
    }

    /// Whether this account's limit turned over within the last `window`.
    ///
    /// A span rather than a flag, because the rail asks this on every frame
    /// and the answer has to stay true long enough for the celebration to be
    /// worth starting — and then stop being true by itself, with nothing to
    /// clear.
    func justReset(_ account: AccountKey, within window: TimeInterval = 20,
                   now: Date = Date()) -> Bool {
        guard let at = resets[account.id] else { return false }
        return now.timeIntervalSince(at) >= 0 && now.timeIntervalSince(at) <= window
    }
}
