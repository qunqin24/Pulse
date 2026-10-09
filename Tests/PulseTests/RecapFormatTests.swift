import Foundation
import Testing
@testable import Pulse

/// How the recap cards print numbers, hours and dates in each language.
@Suite("Recap format")
struct RecapFormatTests {
    private static func tokens(_ count: Int, _ identifier: String) -> RecapFormat.Figure {
        RecapFormat.tokens(count, locale: Locale(identifier: identifier))
    }

    @Test("A hero number is split from its unit in the language's own units")
    func tokenUnits() {
        #expect(Self.tokens(840_019_200, "zh_Hans") == .init(number: "8.4", unit: "亿"))
        #expect(Self.tokens(840_019_200, "zh_Hant") == .init(number: "8.4", unit: "億"))
        #expect(Self.tokens(840_019_200, "ja_JP") == .init(number: "8.4", unit: "億"))
        #expect(Self.tokens(840_019_200, "ko_KR") == .init(number: "8.4", unit: "억"))
        #expect(Self.tokens(840_019_200, "en_US") == .init(number: "840", unit: "M"))
    }

    @Test("Below the big unit, ten-thousands carry a separator and thousands do not need one")
    func smallerScales() {
        #expect(Self.tokens(62_400_000, "zh_Hans") == .init(number: "6,240", unit: "万"))
        #expect(Self.tokens(62_400_000, "ko_KR") == .init(number: "6,240", unit: "만"))
        #expect(Self.tokens(62_400_000, "en_US") == .init(number: "62", unit: "M"))
        #expect(Self.tokens(41_000, "en_US") == .init(number: "41", unit: "K"))
        #expect(Self.tokens(31_000_000, "zh_Hant") == .init(number: "3,100", unit: "萬"))
        #expect(Self.tokens(5_900_000_000, "en_US") == .init(number: "5.9", unit: "B"))
        #expect(Self.tokens(412, "en_US") == .init(number: "412", unit: ""))
        #expect(Self.tokens(412, "zh_Hans") == .init(number: "412", unit: ""))
    }

    @Test("The split agrees with TokenCount.short, which the panel uses")
    func agreesWithPanel() {
        for count in [412, 9_999, 10_000, 4_764_000, 62_400_000, 419_000_000, 840_019_200, 5_900_000_000] {
            for identifier in ["en_US", "zh_Hans", "zh_Hant", "ja_JP", "ko_KR"] {
                let locale = Locale(identifier: identifier)
                let figure = RecapFormat.tokens(count, locale: locale)
                let short = TokenCount.short(count, units: LocalizationSource.myriadUnits(for: locale))
                #expect(figure.text.replacingOccurrences(of: ",", with: "") == short, "\(count) in \(identifier)")
            }
        }
    }

    @Test("Dollars are written with a bare dollar sign whatever the language")
    func dollars() {
        for identifier in ["en_US", "zh_Hans", "ja_JP", "ko_KR"] {
            let locale = Locale(identifier: identifier)
            #expect(RecapFormat.money(1342, currency: "USD", locale: locale) == "$1,342")
            #expect(RecapFormat.money(47.4, currency: "USD", locale: locale) == "$47")
            #expect(RecapFormat.money(3.4, currency: "USD", locale: locale) == "$3.40")
        }
    }

    @Test("A ruler label has cents only when the step is under a dollar")
    func axis() {
        let locale = Locale(identifier: "en_US")
        #expect(RecapFormat.axisMoney(500, step: 500, currency: "USD", locale: locale) == "$500")
        #expect(RecapFormat.axisMoney(0.4, step: 0.2, currency: "USD", locale: locale) == "$0.40")
    }

    @Test("Percentages and multiples")
    func ratios() {
        #expect(RecapFormat.percent(0.41) == "41%")
        #expect(RecapFormat.percent(0.004) == "<1%")
        #expect(RecapFormat.percent(0) == "0%")
        #expect(RecapFormat.multiple(6.7123) == "6.7")
        #expect(RecapFormat.multiple(12.4) == "12")
        #expect(RecapFormat.multiple(0.031) == "<0.1")
        #expect(RecapFormat.multiple(0) == "0.0")
    }

    @Test("English reads the day in twelves; the other languages in 24 hours")
    func hours() {
        #expect(RecapFormat.hour(23, locale: Locale(identifier: "en_US")) == .init(number: "11", unit: "PM"))
        #expect(RecapFormat.hour(0, locale: Locale(identifier: "en_US")) == .init(number: "12", unit: "AM"))
        #expect(RecapFormat.hourLabel(9, locale: Locale(identifier: "en_US")) == "9 AM")
        for identifier in ["zh_Hans", "zh_Hant", "ja_JP", "ko_KR"] {
            #expect(RecapFormat.hour(23, locale: Locale(identifier: identifier)) == .init(number: "23:00", unit: ""))
            #expect(RecapFormat.hourLabel(5, locale: Locale(identifier: identifier)) == "05:00")
            // The latest finish sits under "05:00" on the same card: padded too.
            #expect(RecapFormat.clockTime(minutes: 134, locale: Locale(identifier: identifier)) == "02:14")
        }
        #expect(RecapFormat.clockTime(minutes: 134, locale: Locale(identifier: "en_US")).hasPrefix("2:14"))
    }

    @Test("Weekday headings start on Monday and come from the locale")
    func weekdays() {
        #expect(RecapFormat.weekdayHeadings(locale: Locale(identifier: "zh_Hans")) == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(RecapFormat.weekdayHeadings(locale: Locale(identifier: "ja_JP")) == ["月", "火", "水", "木", "金", "土", "日"])
        #expect(RecapFormat.weekdayHeadings(locale: Locale(identifier: "ko_KR")) == ["월", "화", "수", "목", "금", "토", "일"])
        #expect(RecapFormat.weekdayHeadings(locale: Locale(identifier: "en_US")).first == "Mon")
        #expect(RecapFormat.weekdayHeadings(locale: Locale(identifier: "en_US")).last == "Sun")
    }

    @Test("Month and year names are the language's own")
    func names() {
        #expect(RecapFormat.monthName(9, locale: Locale(identifier: "en_US")) == "September")
        #expect(RecapFormat.monthName(9, locale: Locale(identifier: "zh_Hans")) == "九月")
        #expect(RecapFormat.monthName(9, locale: Locale(identifier: "ja_JP")) == "9月")
        #expect(RecapFormat.monthName(9, locale: Locale(identifier: "ko_KR")) == "9월")
        #expect(RecapFormat.yearName(2026, locale: Locale(identifier: "en_US")) == "2026")
        #expect(RecapFormat.yearName(2026, locale: Locale(identifier: "zh_Hans")) == "2026年")
        #expect(RecapFormat.yearName(2026, locale: Locale(identifier: "ko_KR")) == "2026년")
    }

    @Test("A month grid starts the 1st under its weekday, Monday first")
    func monthGrid() throws {
        let calendar = RecapFormat.calendar(locale: Locale(identifier: "en_US"))
        let september = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let grid = RecapMonthGrid(monthStart: september, days: [], calendar: calendar)
        // 1 September 2026 is a Tuesday: one blank before it, five rows.
        #expect(grid.rows == 5)
        #expect(grid.cells.count == 35)
        #expect(grid.cells.allSatisfy { $0 == nil })
    }

    @Test("Emphasis markers survive being placed anywhere in a sentence")
    func emphasis() {
        let text = "A \(RecapEmphasis.mark("one")) b \(RecapEmphasis.mark("two"))"
        let segments = RecapEmphasis.segments(text)
        #expect(segments.map(\.text) == ["A ", "one", " b ", "two"])
        #expect(segments.map(\.emphasised) == [false, true, false, true])
        #expect(RecapEmphasis.plain(text) == "A one b two")
    }

    @Test("Payback ruler steps are round and end past the figure")
    func rulerScale() {
        let scale = RecapRulerScale(for: 1342)
        #expect(scale.step == 500)
        #expect(scale.maximum >= 1342)
        #expect(RecapRulerScale(for: 9820).step == 2500)
        #expect(RecapRulerScale(for: 3.4).maximum >= 3.4)
    }

    private static func september(_ day: Int) -> Date {
        Recap.calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    @Test("Weekday names start on Monday and come from the locale, not from this code")
    func weekdayNames() {
        #expect(RecapFormat.weekdayNames(locale: Locale(identifier: "en_US")) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(RecapFormat.weekdayNames(locale: Locale(identifier: "zh_Hans")) == ["周一", "周二", "周三", "周四", "周五", "周六", "周日"])
        #expect(RecapFormat.weekdayNames(locale: Locale(identifier: "ja_JP")).first == "月")
        #expect(RecapFormat.weekdayNames(locale: Locale(identifier: "ko_KR")).last == "일")
    }

    @Test("The weekday of a date, in the locale")
    func weekdayOfDate() {
        // September 25, 2026 is a Friday.
        #expect(RecapFormat.weekdayName(of: Self.september(25), locale: Locale(identifier: "en_US")) == "Fri")
        #expect(RecapFormat.weekdayName(of: Self.september(25), locale: Locale(identifier: "zh_Hans")) == "周五")
        #expect(RecapFormat.dayAndWeekday(Self.september(25), locale: Locale(identifier: "en_US")) == "Sep 25 · Fri")
    }

    @Test("A range is two short dates, and a single day stands alone")
    func dayRange() {
        let en = Locale(identifier: "en_US")
        #expect(RecapFormat.dayRange(Self.september(21), Self.september(27), locale: en) == "9/21–9/27")
        #expect(RecapFormat.dayRange(Self.september(30), Self.september(30), locale: en) == "9/30")
        #expect(RecapFormat.shortDay(Self.september(5), locale: Locale(identifier: "zh_Hans")) == "9/5")
    }

    @Test("A share split for a figure keeps the sign apart, and a sliver reads under one")
    func percentFigure() {
        #expect(RecapFormat.percentFigure(0.41) == .init(number: "41", unit: "%"))
        #expect(RecapFormat.percentFigure(0.002) == .init(number: "<1", unit: "%"))
        #expect(RecapFormat.percentFigure(0) == .init(number: "0", unit: "%"))
    }
}
