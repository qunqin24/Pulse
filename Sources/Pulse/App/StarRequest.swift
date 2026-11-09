// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The one request for a GitHub star: a banner at the top of the settings
/// window, once, after Pulse has been in use for a while.
///
/// **In use means days Pulse ran, not days since it was installed.** It is
/// due when the first day it was counted is at least `minimumAge` behind and
/// Pulse has run on at least `minimumDays` separate days since. A copy that
/// was installed and forgotten is never asked.
///
/// **Counted from the first launch of a version that counts**, for everyone:
/// an existing user is not asked on the day they update to it.
///
/// **Once, whatever happens to it.** It is spent when the banner is shown,
/// not when it is answered: Pulse cannot tell whether the star was given and
/// does not try to. The About pane keeps a permanent link. Never a window,
/// never a notification. See `Docs/ui/settings.md`.
enum StarRequest {
    enum Key {
        static let since = "settings.starRequestSince"
        static let days = "settings.starRequestDays"
        static let lastDay = "settings.starRequestLastDay"
        static let shown = "settings.starRequestShown"
    }

    static let minimumAge: TimeInterval = 14 * 24 * 60 * 60
    static let minimumDays = 7

    static let repository = URL(string: "https://github.com/qunqin24/Pulse")!

    /// What is stored, kept apart from `UserDefaults` so it can be tested.
    struct Record: Equatable {
        var since: Date?
        var days = 0
        var lastDay: String?
        var shown = false
    }

    /// The record after Pulse is seen running at `now`: the first sighting
    /// starts the count, and each new calendar day adds one.
    static func noting(_ record: Record, now: Date, calendar: Calendar = .current) -> Record {
        var record = record
        if record.since == nil { record.since = now }
        let day = dayKey(now, calendar: calendar)
        if record.lastDay != day {
            record.lastDay = day
            record.days += 1
        }
        return record
    }

    static func isDue(_ record: Record, now: Date) -> Bool {
        guard !record.shown, let since = record.since else { return false }
        return now.timeIntervalSince(since) >= minimumAge && record.days >= minimumDays
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: Stored

    static func record(in defaults: UserDefaults) -> Record {
        Record(
            since: defaults.object(forKey: Key.since) as? Date,
            days: defaults.integer(forKey: Key.days),
            lastDay: defaults.string(forKey: Key.lastDay),
            shown: defaults.bool(forKey: Key.shown)
        )
    }

    /// Called at launch, at midnight and on waking, so a Mac left running
    /// for days counts each of them.
    static func noteActive(now: Date = Date(), defaults: UserDefaults = .standard) {
        let record = noting(record(in: defaults), now: now)
        defaults.set(record.since, forKey: Key.since)
        defaults.set(record.days, forKey: Key.days)
        defaults.set(record.lastDay, forKey: Key.lastDay)
    }

    /// Whether to show the banner as the settings window opens, spending the
    /// request if so.
    static func claimIfDue(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard isDue(record(in: defaults), now: now) else { return false }
        defaults.set(true, forKey: Key.shown)
        return true
    }
}
