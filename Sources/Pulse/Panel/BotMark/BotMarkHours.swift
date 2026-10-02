// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Whether a turn is happening outside working hours.
///
/// A working mark takes `angry` into its playlist outside these hours. Rest
/// uses a separate night window: a Saturday afternoon is not bedtime.
///
/// **The hours are a guess and are meant to be edited.** Nobody's calendar is
/// in this app, so there is nothing to read: 09:00–21:00 Monday to Friday is a
/// default, not a fact about the person using it. Kept in one place, and out
/// of the mood table, so changing it is one line and so it cannot creep into
/// anything that claims to be a reading.
enum BotMarkHours {
    static let start = 9
    static let end = 21

    /// Decorative night-time rest, independent of weekday/weekend work hours.
    static func isNight(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let hour = calendar.dateComponents([.hour], from: date).hour else { return false }
        return hour >= 23 || hour < 8
    }

    static func isOvertime(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let hour = calendar.dateComponents([.hour], from: date).hour else { return false }
        // `isDateInWeekend` rather than a weekday number: which days are the
        // weekend is a property of the calendar, not a pair of constants.
        return calendar.isDateInWeekend(date) || hour < start || hour >= end
    }
}
