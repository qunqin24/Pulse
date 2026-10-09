// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The month's calendar card, and the pieces the year's calendar and months
// cards share with it: the hero total, the three tiles, and the split between
// weekdays and the weekend.

// MARK: - Hero

/// The period's total, huge, on a lime bar, with how it compares to the period
/// before and what it cost beside it.
struct RecapCalendarHero: View {
    let deck: RecapDeck
    var numberSize: CGFloat = 240
    var unitSize: CGFloat = 116

    private var recap: Recap { deck.recap }

    var body: some View {
        let figure = RecapFormat.tokens(recap.tokens)
        VStack(alignment: .leading, spacing: 34) {
            Text(deck.workedThroughLine)
                .font(.recap(32))
                .foregroundStyle(Color(recap: 0x55554F))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 24) {
                RecapFigureText(figure: figure, numberSize: numberSize, unitSize: unitSize, unitGap: 14, trimmed: true)
                    .background(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(RecapColor.lime)
                            .frame(height: numberSize * 0.38)
                            .padding(.bottom, numberSize * 0.0175)
                            .padding(.leading, -8)
                            .padding(.trailing, -14)
                    }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    if let change = deck.sameSpanChange {
                        RecapPill(fill: RecapColor.ink, horizontal: 12, vertical: 6) {
                            Text(verbatim: "\(change.arrow) \(change.percent) \(change.versus)")
                                .font(.recap(18))
                                .foregroundStyle(RecapColor.lime)
                                .lineLimit(1)
                        }
                    }
                    Text(verbatim: tokensLine)
                        .font(.recap(20, .regular, mono: true))
                        .tracking(0.8)
                        .foregroundStyle(Color(recap: 0x55554F))
                        .recapFit(0.6)
                }
                .padding(.bottom, 14)
            }
        }
    }

    /// "TOKENS · ≈ $622"; without a cost, "TOKENS".
    private var tokensLine: String {
        guard let cost = recap.cost else { return "TOKENS" }
        return "TOKENS · ≈ " + RecapFormat.money(cost, currency: recap.currency)
    }
}

// MARK: - Month calendar

/// The month, every day a cell, with the total above it and what the month
/// held below: active days, the longest streak, the busiest day, the weeks,
/// and the weekdays against the weekend.
struct RecapCalendarView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let calendar = RecapFormat.calendar()
        let grid = RecapMonthGrid(monthStart: recap.start, days: recap.days, calendar: calendar)
        let maximum = recap.days.map(\.tokens).max() ?? 0
        let busiest = recap.busiestDay?.date
        let cellHeight: CGFloat = grid.rows > 5 ? 74 : 86
        RecapStoryPage(page: deck.page(of: .calendar)) {
            RecapCalendarHero(deck: deck).padding(.top, 44)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                RecapSectionHead(title: RecapFormat.monthYear(recap.start), note: .localized("Darker days used more · dashed days had none"))
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(RecapFormat.weekdayHeadings().enumerated()), id: \.offset) { _, heading in
                            Text(heading)
                                .font(.recap(16))
                                .foregroundStyle(RecapColor.tertiary)
                                .recapFit(0.6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<grid.rows, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { column in
                                cell(grid.cells[row * 7 + column], column: column, maximum: maximum, busiest: busiest, height: cellHeight)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 24)
            RecapCalendarTiles(deck: deck)
            Spacer(minLength: 24)
            weeks
            Spacer(minLength: 24)
            RecapWorkSplitView(deck: deck)
        }
    }

    @ViewBuilder
    private func cell(_ day: Recap.Day?, column: Int, maximum: Int, busiest busiestDate: Date?, height: CGFloat) -> some View {
        if let day {
            let number = recap.calendar.component(.day, from: day.date)
            let quiet = day.tokens == 0
            // Only the one day `Recap.busiestDay` names, not every tie.
            let busiest = !quiet && day.date == busiestDate
            let foreground = busiest ? RecapColor.lime : (quiet ? RecapColor.faint : RecapColor.ink)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(busiest ? RecapColor.ink : (quiet ? Color.clear : RecapHeat.color(tokens: day.tokens, maximum: maximum)))
                // Every day without work alike, weekend or not: a grey weekend
                // beside a dashed weekday read as two different things, and
                // the legend could name only one of them. The column headings
                // already say which days are the weekend.
                if quiet {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(recap: 0xD6D6CF), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(number)")
                        .font(.recap(20, .semibold))
                        .foregroundStyle(foreground)
                    Spacer(minLength: 0)
                    if !quiet {
                        Text(verbatim: RecapFormat.tokens(day.tokens).text)
                            .font(.recap(13, .regular, mono: true))
                            .foregroundStyle(foreground.opacity(busiest ? 1 : 0.75))
                            .recapFit(0.6)
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: height)
        }
    }

    // MARK: Weeks

    @ViewBuilder
    private var weeks: some View {
        let insights = RecapInsights(recap)
        let weeks = insights.weeks
        let busiest = insights.busiestWeek
        let top = max(weeks.map(\.tokens).max() ?? 0, 1)
        if weeks.count > 1 {
            VStack(spacing: 12) {
                RecapSectionHead(
                    title: .localized("By week"),
                    note: busiest.map { .localized("Busiest week: \(RecapFormat.dayRange(weeks[$0].first, weeks[$0].last))") }
                )
                ForEach(weeks.indices, id: \.self) { index in
                    let week = weeks[index]
                    let best = index == busiest
                    HStack(spacing: 16) {
                        Text(verbatim: RecapFormat.dayRange(week.first, week.last))
                            .font(.recap(17, best ? .bold : .regular, mono: true))
                            .foregroundStyle(best ? RecapColor.ink : RecapColor.secondary)
                            .recapFit(0.6)
                            .frame(width: 170, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(RecapColor.heatZero)
                                if week.tokens > 0 {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(best ? RecapColor.ink : RecapColor.lime)
                                        .frame(width: max(8, proxy.size.width * CGFloat(week.tokens) / CGFloat(top)))
                                }
                            }
                        }
                        .frame(height: 22)
                        Text(verbatim: week.tokens > 0 ? RecapFormat.tokens(week.tokens).text : "—")
                            .font(.recap(17, best ? .bold : .regular, mono: true))
                            .foregroundStyle(best ? RecapColor.ink : RecapColor.secondary)
                            .recapFit(0.6)
                            .frame(width: 110, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Tiles

/// Three tiles: the days with work against the days the period had (a ring), the
/// longest streak (a chain of days), and the busiest day (on ink).
struct RecapCalendarTiles: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        HStack(spacing: 14) {
            activeTile
            if let chain = RecapInsights(recap).streakChain { streakTile(chain) }
            if let day = recap.busiestDay, day.tokens > 0 { busiestTile(day) }
        }
        .frame(height: 190)
    }

    private var activeTile: some View {
        // A month's own days are the ring's segments; a year's are too many to
        // draw, so its ring is a fixed 36 in proportion.
        let isYear = deck.isYear
        let segments = isYear ? 36 : max(recap.observedDays, 1)
        let share = Double(recap.activeDays) / Double(max(recap.observedDays, 1))
        let filled = isYear ? (recap.activeDays > 0 ? max(Int((share * 36).rounded()), 1) : 0) : recap.activeDays
        return RecapTile {
            HStack(spacing: 14) {
                RecapSegmentRing(filled: filled, segments: segments)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized: "Active days")
                        .font(.recap(17))
                        .foregroundStyle(RecapTileTone.white.caption)
                        .recapFit(0.6)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(tight: "\(recap.activeDays)", tracking: -48 * 0.03)
                            .font(.recap(48, .bold))
                        Text(verbatim: "/ \(recap.observedDays)")
                            .font(.recap(22))
                            .foregroundStyle(RecapColor.tertiary)
                    }
                    .recapFit(0.6)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func streakTile(_ chain: RecapInsights.Chain) -> some View {
        RecapTile {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized: "Longest streak")
                    .font(.recap(17))
                    .foregroundStyle(RecapTileTone.white.caption)
                    .recapFit(0.6)
                RecapFigureText(
                    figure: .init(number: "\(recap.longestStreak)", unit: RecapWords.daysUnit(recap.longestStreak)),
                    numberSize: 48, unitSize: 24, unitWeight: .bold, tracking: -0.03, unitGap: 6
                )
                Spacer(minLength: 0)
                RecapStreakChain(chain: chain)
            }
        }
    }

    private func busiestTile(_ day: Recap.Day) -> some View {
        let tone = RecapTileTone.ink
        var detail = RecapFormat.dayAndWeekday(day.date)
        if let cost = day.cost { detail += " · ≈ " + RecapFormat.money(cost, currency: recap.currency) }
        return RecapTile(tone: tone) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized: "Busiest day")
                    .font(.recap(17))
                    .foregroundStyle(tone.caption)
                    .recapFit(0.6)
                RecapFigureText(figure: RecapFormat.tokens(day.tokens), numberSize: 48, unitSize: 24,
                                unitWeight: .bold, color: RecapColor.lime, tracking: -0.03, unitGap: 6)
                Spacer(minLength: 0)
                Text(verbatim: detail)
                    .font(.recap(16))
                    .foregroundStyle(tone.detail)
                    .recapFit(0.6)
            }
        }
    }
}

// MARK: - Weekdays and the weekend

/// How the work divided between Monday to Friday and the weekend: one bar,
/// and a line each for the days there were and the days used.
struct RecapWorkSplitView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let insights = RecapInsights(recap)
        if let split = insights.workSplit {
            VStack(spacing: 12) {
                RecapHairline(strong: true).padding(.bottom, 10)
                RecapSectionHead(
                    title: .localized("Weekdays and weekends"),
                    note: insights.tokensPerActiveDay.map { .localized("Average per active day: \(RecapFormat.tokens($0).text)") }
                )
                bar(split)
                HStack(alignment: .firstTextBaseline) {
                    if split.weekdayDays > 0 {
                        Text(String.localized("\("\(split.weekdayDays)") weekdays, used on \("\(split.weekdayActive)") of them"))
                    }
                    Spacer(minLength: 12)
                    if split.weekendDays > 0 {
                        Text(String.localized("\("\(split.weekendDays)") weekend days, used on \("\(split.weekendActive)") of them"))
                    }
                }
                .font(.recap(16))
                .foregroundStyle(RecapColor.tertiary)
                .recapFit(0.6)
            }
        }
    }

    private func bar(_ split: RecapInsights.WorkSplit) -> some View {
        GeometryReader { proxy in
            let gap: CGFloat = 4
            let both = split.weekdayTokens > 0 && split.weekendTokens > 0
            let room = proxy.size.width - (both ? gap : 0)
            HStack(spacing: gap) {
                if split.weekdayTokens > 0 {
                    segment(
                        word: String.localized("Weekdays \(RecapFormat.percent(split.weekdayShare))"),
                        percent: RecapFormat.percent(split.weekdayShare),
                        width: room * split.weekdayShare, fill: RecapColor.ink, text: RecapColor.paper, trailing: false
                    )
                }
                if split.weekendTokens > 0 {
                    segment(
                        word: String.localized("Weekends \(RecapFormat.percent(split.weekendShare))"),
                        percent: RecapFormat.percent(split.weekendShare),
                        width: room * split.weekendShare, fill: RecapColor.lime, text: RecapColor.ink, trailing: true
                    )
                }
            }
        }
        .frame(height: 44)
    }

    /// A slice of the bar: the whole label where it fits, the percent alone
    /// where it does not, and nothing where even that would not.
    private func segment(word: String, percent: String, width: CGFloat, fill: Color, text: Color, trailing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fill)
            .frame(width: max(width, 6))
            .overlay(alignment: trailing ? .trailing : .leading) {
                if width >= 180 {
                    Text(verbatim: word).font(.recap(19)).foregroundStyle(text).lineLimit(1).padding(.horizontal, 16)
                } else if width >= 64 {
                    Text(verbatim: percent).font(.recap(19)).foregroundStyle(text).lineLimit(1).padding(.horizontal, 14)
                }
            }
    }
}
