// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Numbers, money, hours and dates as the recap cards print them.
///
/// Every function takes the locale as a parameter that defaults to the app's
/// language (`LocalizationSource.locale`), so the cards follow the language the
/// reader picked and the tests can ask about one the app is not set to.
///
/// The hero figures are drawn as a large number and a small unit, which is why
/// most of these return a `Figure` rather than a string.
enum RecapFormat {
    /// A number and the unit that follows it, kept apart so the card can set
    /// them in two sizes: ("8.4", "亿"), ("840", "M"), ("23:00", ""), ("11", "PM").
    struct Figure: Equatable, Sendable {
        let number: String
        let unit: String

        /// The two joined, for running text.
        var text: String { number + unit }
    }

    // MARK: - Tokens

    /// A token count split at its unit. 万/亿 in Chinese and Japanese, 만/억 in
    /// Korean, K/M/B elsewhere — one rule with `TokenCount.short`, so the
    /// recap and the panel never disagree about where 亿 begins. Where the
    /// number has four digits before the unit (6,240万) it carries a separator,
    /// which `TokenCount.short` leaves out because it is read in a narrow row.
    static func tokens(_ count: Int, locale: Locale = LocalizationSource.locale) -> Figure {
        let parts = TokenCount.parts(count, units: LocalizationSource.myriadUnits(for: locale))
        return Figure(number: separated(parts.number), unit: parts.unit)
    }

    /// "4764" → "4,764", "8.4" → "8.4".
    private static func separated(_ number: String) -> String {
        let whole = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = whole.first, head.count > 3 else { return number }
        var grouped = ""
        for (index, character) in head.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let integer = String(grouped.reversed())
        return whole.count > 1 ? integer + "." + whole[1] : integer
    }

    // MARK: - Money

    /// Whole units from ten up ("$1,342", "$47"), cents below it ("$3.40"), and
    /// "< $0.01" for a positive amount under a cent — the same line
    /// `AccountUsageCard.money` draws, so a sliver of spend is never "$0".
    static func money(_ amount: Double, currency: String, locale: Locale = LocalizationSource.locale) -> String {
        let style = Self.currencyStyle(currency, locale: locale)
        if amount > 0, amount < 0.01 {
            return String.localized("< \(0.01.formatted(style.precision(.fractionLength(2))))")
        }
        return amount.formatted(style.precision(.fractionLength(amount >= 10 ? 0 : 2)))
    }

    /// Dollars are written "$" in every language of the app: a Chinese locale
    /// would print "US$1,342", which on a card that is shared reads as a
    /// different currency from the one beside it. Any other currency is drawn
    /// the way the locale draws it.
    private static func currencyStyle(_ currency: String, locale: Locale) -> FloatingPointFormatStyle<Double>.Currency {
        FloatingPointFormatStyle<Double>.Currency(code: currency)
            .locale(currency == "USD" ? Locale(identifier: "en_US") : locale)
    }

    /// A ruler label: whole units unless the step between labels is under one.
    static func axisMoney(_ amount: Double, step: Double, currency: String, locale: Locale = LocalizationSource.locale) -> String {
        let style = Self.currencyStyle(currency, locale: locale)
        return amount.formatted(style.precision(.fractionLength(step < 1 ? 2 : 0)))
    }

    // MARK: - Ratios

    /// "41%", and "<1%" for a share that is there but would round to nothing.
    static func percent(_ share: Double) -> String {
        let rounded = Int((share * 100).rounded())
        if rounded == 0, share > 0 { return "<1%" }
        return "\(rounded)%"
    }

    /// The same share split for a figure with its sign set small: ("41", "%"),
    /// ("<1", "%").
    static func percentFigure(_ share: Double) -> Figure {
        Figure(number: String(percent(share).dropLast()), unit: "%")
    }

    /// "6.7" under ten, "42" from ten up, "<0.1" for a positive multiple that
    /// would round to "0.0" — a zero is not what was used.
    static func multiple(_ value: Double) -> String {
        if value > 0, value < 0.05 { return "<0.1" }
        return String(format: value < 10 ? "%.1f" : "%.0f", value)
    }

    // MARK: - Hours and clock times

    /// Whether the card counts the day in twelves ("11 PM"). Only English does,
    /// and only where its locale does: Chinese, Japanese and Korean put the
    /// half-day before the hour ("午後11時", "오후 11시"), which a number with a
    /// unit after it cannot say, so a rhythm chart there reads in 24 hours.
    static func usesTwelveHourClock(_ locale: Locale) -> Bool {
        guard locale.language.languageCode?.identifier == "en" else { return false }
        return (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
    }

    /// One hour of the day: ("23:00", "") or ("11", "PM").
    static func hour(_ hour: Int, locale: Locale = LocalizationSource.locale) -> Figure {
        guard usesTwelveHourClock(locale) else {
            return Figure(number: String(format: "%02d:00", hour), unit: "")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return Figure(number: "\(twelve)", unit: hour < 12 ? formatter.amSymbol : formatter.pmSymbol)
    }

    /// The same hour on one line, for the timetable's rows: "23:00", "11 PM".
    static func hourLabel(_ hour: Int, locale: Locale = LocalizationSource.locale) -> String {
        let figure = Self.hour(hour, locale: locale)
        return figure.unit.isEmpty ? figure.number : figure.number + " " + figure.unit
    }

    /// Minutes after midnight as a time of day, on the same clock as `hour`:
    /// "02:14" beside "05:00" in a 24-hour language, the locale's own "2:14 AM"
    /// in English.
    static func clockTime(minutes: Int, locale: Locale = LocalizationSource.locale) -> String {
        guard usesTwelveHourClock(locale) else {
            let wrapped = ((minutes % 1440) + 1440) % 1440
            return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .gmt
        let midnight = Date(timeIntervalSince1970: 0)
        let date = midnight.addingTimeInterval(Double(minutes) * 60)
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(style)
    }

    // MARK: - Dates

    // MARK: - Calendar

    /// The recap's calendar (`Recap.calendar`: Gregorian, weeks from Monday)
    /// speaking the locale. Periods are built, offered and named in this one
    /// calendar, so what a card prints and what it counted never differ.
    static func calendar(locale: Locale = LocalizationSource.locale) -> Calendar {
        var calendar = Recap.calendar
        calendar.locale = locale
        return calendar
    }

    private static func formatted(_ date: Date, template: String, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// "September", "九月", "9月", "9월".
    static func monthName(_ month: Int, locale: Locale = LocalizationSource.locale) -> String {
        let calendar = calendar(locale: locale)
        let symbols = calendar.standaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
    }

    /// "Sep", "9月", "9월" — the short month for the twelve-bar chart.
    static func shortMonthName(_ month: Int, locale: Locale = LocalizationSource.locale) -> String {
        let symbols = calendar(locale: locale).shortStandaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
    }

    /// Weekday headings, Monday first. One character where the language has
    /// one ("一", "月", "월"); the short name elsewhere, because "T" and "T"
    /// are Tuesday and Thursday.
    static func weekdayHeadings(locale: Locale = LocalizationSource.locale) -> [String] {
        let calendar = calendar(locale: locale)
        let compact = ["zh", "ja", "ko"].contains(locale.language.languageCode?.identifier ?? "")
        let symbols = compact ? calendar.veryShortStandaloneWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { symbols[$0] }
    }

    /// The weekdays' short names, Monday first: "Mon", "周一", "月", "월".
    static func weekdayNames(locale: Locale = LocalizationSource.locale) -> [String] {
        let symbols = calendar(locale: locale).shortStandaloneWeekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { symbols[$0] }
    }

    /// The short name of the weekday a date falls on.
    static func weekdayName(of date: Date, locale: Locale = LocalizationSource.locale) -> String {
        let calendar = calendar(locale: locale)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return symbols[calendar.component(.weekday, from: date) - 1]
    }

    /// "2026", "2026年", "2026년": how the language says which year.
    static func yearName(_ year: Int, locale: Locale = LocalizationSource.locale) -> String {
        var components = DateComponents()
        components.year = year
        components.month = 6
        components.day = 15
        let date = calendar(locale: locale).date(from: components) ?? Date()
        return formatted(date, template: "y", locale: locale)
    }

    /// "September 2026", "2026年9月".
    static func monthYear(_ date: Date, locale: Locale = LocalizationSource.locale) -> String {
        formatted(date, template: "yMMMM", locale: locale)
    }

    /// "Sep 17, Thu", "9月17日周四".
    static func dayWithWeekday(_ date: Date, locale: Locale = LocalizationSource.locale) -> String {
        formatted(date, template: "MMMdEEE", locale: locale)
    }

    /// "Sep 17 · Thu", "9月17日 · 周四".
    static func dayAndWeekday(_ date: Date, locale: Locale = LocalizationSource.locale) -> String {
        day(date, locale: locale) + " · " + weekdayName(of: date, locale: locale)
    }

    /// "9/21": month and day with no name, for a range or a chain.
    static func shortDay(_ date: Date, locale: Locale = LocalizationSource.locale) -> String {
        formatted(date, template: "Md", locale: locale)
    }

    /// "9/21–9/27", and a single day alone.
    static func dayRange(_ first: Date, _ last: Date, locale: Locale = LocalizationSource.locale) -> String {
        let start = shortDay(first, locale: locale)
        return calendar(locale: locale).isDate(first, inSameDayAs: last) ? start : start + "–" + shortDay(last, locale: locale)
    }

    /// "Sep 17", "9月17日".
    static func day(_ date: Date, locale: Locale = LocalizationSource.locale) -> String {
        formatted(date, template: "MMMd", locale: locale)
    }
}
