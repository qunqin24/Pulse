// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

// The cards only a year recap has: every month as a small calendar, and the
// twelve months side by side.

/// Twelve vertical bars, January to December, the busiest in lime. For the
/// year poster, where it stands in for the month calendar. A month with
/// nothing to show — still to come, or before the first record — is a dashed
/// outline, as on the months card and the scorecard, not a quiet month's sliver.
struct RecapMonthBars: View {
    let months: [Recap.Month]
    /// Month indices (0 for January) that are unrecorded.
    var unrecorded: Set<Int> = []
    let labelSize: CGFloat
    let labelHeight: CGFloat

    var body: some View {
        let maximum = max(months.map(\.tokens).max() ?? 1, 1)
        let busiest = months.max { $0.tokens < $1.tokens }?.month
        GeometryReader { proxy in
            let barArea = max(proxy.size.height - labelHeight - 8, 10)
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(months) { month in
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if unrecorded.contains(month.month - 1) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(height: 6)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(month.month == busiest ? RecapColor.lime : Color(recap: 0xE0E0DA))
                                .overlay {
                                    if month.month == busiest {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(RecapColor.ink, lineWidth: 2)
                                    }
                                }
                                .frame(height: max(6, barArea * CGFloat(month.tokens) / CGFloat(maximum)))
                        }
                        Text(verbatim: RecapFormat.shortMonthName(month.month))
                            .font(.recap(labelSize, month.month == busiest ? .semibold : .regular))
                            .foregroundStyle(month.month == busiest ? RecapColor.ink : RecapColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(height: labelHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Year calendar

/// The year, one small calendar per month.
struct RecapYearCalendarView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        RecapStoryPage(page: deck.page(of: .yearCalendar), footnotes: deck.provenance) {
            RecapCalendarHero(deck: deck, numberSize: 190, unitSize: 92).padding(.top, 40)
            Spacer(minLength: 20)
            RecapSectionHead(
                title: RecapFormat.yearName(recap.period.year),
                note: recap.recordsBegin == nil
                    ? .localized("Darker days used more")
                    : .localized("Darker days used more · dashed days had none")
            )
            months.padding(.top, 20)
            Spacer(minLength: 20)
            RecapCalendarTiles(deck: deck)
        }
    }

    private var maximum: Int { recap.days.map(\.tokens).max() ?? 0 }

    private var months: some View {
        let calendar = recap.calendar
        let starts = recap.monthStarts
        let columns = Array(repeating: GridItem(.flexible(), spacing: 30, alignment: .top), count: 3)
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(starts.indices, id: \.self) { index in
                monthBlock(starts[index], calendar: calendar)
            }
        }
    }

    private func monthBlock(_ first: Date, calendar: Calendar) -> some View {
        let month = calendar.component(.month, from: first)
        let grid = RecapMonthGrid(monthStart: first, days: recap.days, calendar: calendar)
        let cell: CGFloat = 33, gap: CGFloat = 5
        return VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: RecapFormat.monthName(month))
                .font(.recap(22, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(spacing: gap) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = row * 7 + column
                            if index < grid.cells.count, let day = grid.cells[index] {
                                if recap.isBeforeRecords(day.date) {
                                    // Not seen, so not a quiet grey day: the
                                    // dashed outline the month calendar uses.
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                        .frame(width: cell, height: cell)
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(RecapHeat.color(tokens: day.tokens, maximum: maximum))
                                        .frame(width: cell, height: cell)
                                }
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Months

/// A year, month by month: the busiest named large, and the twelve as rows.
struct RecapMonthsView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let months = recap.months
        let maximum = max(months.map(\.tokens).max() ?? 1, 1)
        let busiest = months.max { $0.tokens < $1.tokens }
        RecapStoryPage(page: deck.page(of: .months), footnotes: deck.notes) {
            Text(localized: "Your busiest month")
                .font(.recap(34))
                .foregroundStyle(Color(recap: 0x55554F))
                .padding(.top, 52)
            if let busiest {
                Text(tight: RecapFormat.monthName(busiest.month), tracking: -230 * 0.05)
                    .font(.recap(230, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 30 - 230 * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -230 * RecapFigureText.descenderRoom)
            }
            Rectangle().fill(RecapColor.ink).frame(height: 2).padding(.top, 34)
            VStack(spacing: 0) {
                let insights = RecapInsights(recap)
                ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                    row(month, maximum: maximum, isBusiest: month.month == busiest?.month,
                        toCome: insights.isMonthUnrecorded(index))
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 16)
            RecapWorkSplitView(deck: deck)
        }
    }

    /// One month as a row; a month still to come in a running year is a
    /// dashed outline with no figure, not a quiet month's sliver of a bar.
    private func row(_ month: Recap.Month, maximum: Int, isBusiest: Bool, toCome: Bool) -> some View {
        let fraction = max(CGFloat(month.tokens) / CGFloat(maximum), 0.02)
        return HStack(spacing: 0) {
            Text(verbatim: RecapFormat.shortMonthName(month.month))
                .font(.recap(22, isBusiest ? .semibold : .regular))
                .foregroundStyle(isBusiest ? RecapColor.ink : RecapColor.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 104, alignment: .leading)
            GeometryReader { proxy in
                HStack(spacing: 14) {
                    if toCome {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 30, height: 30)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isBusiest ? RecapColor.ink : RecapColor.restBar)
                            .frame(width: max(6, (proxy.size.width - 150) * fraction), height: isBusiest ? 42 : 30)
                        Text(verbatim: RecapFormat.tokens(month.tokens).text)
                            .font(.recap(18, isBusiest ? .semibold : .regular, mono: true))
                            .foregroundStyle(isBusiest ? RecapColor.ink : RecapColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 96)
    }
}
