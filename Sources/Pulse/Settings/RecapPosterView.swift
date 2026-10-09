// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The one-page summary: the whole period on a single card.
///
/// A row is drawn only when its facts exist, and the rows that remain share
/// the height between them — so a recap with no price, no cost or no hour
/// shape is a shorter poster, not one with holes in it.
struct RecapPosterView: View {
    let deck: RecapDeck
    private var recap: Recap { deck.recap }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hero.padding(.top, 34)
            let rows = self.rows
            ForEach(rows.indices, id: \.self) { index in
                Spacer(minLength: 20)
                rows[index]
            }
            Spacer(minLength: 20)
            footer
        }
        .foregroundStyle(RecapColor.ink)
        .padding(EdgeInsets(top: 64, leading: 64, bottom: 56, trailing: 64))
        .frame(width: RecapRenderer.cardSize.width, height: RecapRenderer.cardSize.height, alignment: .topLeading)
        .background(RecapColor.paper)
    }

    // MARK: - Header and hero

    private var header: some View {
        HStack(spacing: 0) {
            RecapMark(side: 46)
            Text(verbatim: "Pulse")
                .font(.recap(26, .semibold))
                .padding(.leading, 14)
            Text(verbatim: deck.periodLabel)
                .font(.recap(16, .regular, mono: true))
                .tracking(1.3)
                .foregroundStyle(RecapColor.secondary)
                .padding(.leading, 20)
            Spacer(minLength: 12)
            if let persona = recap.persona {
                RecapPill(fill: RecapColor.ink, horizontal: 18, vertical: 10) {
                    HStack(spacing: 8) {
                        RecapPersonaGlyph(persona: persona, side: 16)
                        Text(persona.title)
                            .font(.recap(17, .medium))
                            .foregroundStyle(RecapColor.paper)
                    }
                }
            }
        }
    }

    private var hero: some View {
        let kicker = deck.workedThroughLine
        let figure = RecapFormat.tokens(recap.tokens)
        return VStack(alignment: .leading, spacing: 30) {
            Text(kicker)
                .font(.recap(22))
                .foregroundStyle(RecapColor.secondary)
                .lineLimit(2)
            HStack(alignment: .bottom, spacing: 30) {
                RecapFigureText(figure: figure, numberSize: 230, unitSize: 110, unitGap: 14, trimmed: true)
                    .background(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(RecapColor.lime)
                            .frame(height: 86)
                            .padding(.bottom, 4)
                            .padding(.leading, -8)
                            .padding(.trailing, -14)
                    }
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "TOKENS")
                        .font(.recap(18, .regular, mono: true))
                        .tracking(1.4)
                        .foregroundStyle(RecapColor.secondary)
                    if let change = deck.sameSpanChange {
                        RecapPill(fill: RecapColor.ink, horizontal: 12, vertical: 6) {
                            Text(verbatim: "\(change.arrow) \(change.percent)")
                                .font(.recap(17, .semibold))
                                .foregroundStyle(RecapColor.lime)
                            + Text(verbatim: " ")
                            + Text(change.versus)
                                .font(.recap(17, .regular))
                                .foregroundStyle(RecapColor.paper)
                        }
                    }
                }
                .padding(.bottom, 14)
                Spacer(minLength: 0)
            }
            summaryLine
                .padding(.top, 30)
        }
    }

    private var summaryLine: some View {
        var parts = [RecapEmphasis.plain(deck.activeDaysLine), deck.sessionsText(recap.sessions)]
        if let perDay = deck.tokensPerDay, perDay > 0 {
            parts.append(String.localized("\(RecapFormat.tokens(perDay).text) a day on average"))
        }
        return Text(parts.joined(separator: "  ·  "))
            .font(.recap(20))
            .foregroundStyle(RecapColor.bodyInk)
            .lineLimit(2)
    }

    // MARK: - Rows

    private var rows: [AnyView] {
        var rows: [AnyView] = []
        if recap.cost != nil { rows.append(AnyView(moneyRow)) }
        rows.append(AnyView(shapeRow))
        if !recap.models.isEmpty { rows.append(AnyView(modelsCard.fixedSize(horizontal: false, vertical: true))) }
        let tiles = tileCards
        if !tiles.isEmpty { rows.append(AnyView(HStack(spacing: 20) { ForEach(tiles.indices, id: \.self) { tiles[$0] } }.frame(height: 236))) }
        let low = lowCards
        if !low.isEmpty { rows.append(AnyView(HStack(spacing: 20) { ForEach(low.indices, id: \.self) { low[$0] } }.frame(height: 206))) }
        return rows
    }

    // Money and payback.

    private var moneyRow: some View {
        // 1.25 : 1 between the two, as drawn.
        let free = RecapRenderer.cardSize.width - 128 - 20
        return HStack(spacing: 20) {
            if let payback = deck.payback {
                moneyCard.frame(width: free * 1.25 / 2.25)
                paybackCard(payback).frame(width: free / 2.25)
            } else {
                moneyCard
            }
        }
        .frame(height: 200)
    }

    private var moneyCard: some View {
        RecapBox(padding: EdgeInsets(top: 26, leading: 28, bottom: 26, trailing: 28)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(localized: "Estimated at API prices")
                    .font(.recap(17))
                    .foregroundStyle(RecapColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(tight: RecapFormat.money(recap.cost ?? 0, currency: recap.currency), tracking: -72 * 0.03)
                    .font(.recap(72, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                RecapSparkline(values: deck.costSeries)
                    .frame(height: 46)
                    .padding(.horizontal, -4)
                    .padding(.bottom, -6)
            }
        }
    }

    private func paybackCard(_ payback: RecapPayback) -> some View {
        RecapBox(fill: RecapColor.lime, padding: EdgeInsets(top: 26, leading: 28, bottom: 26, trailing: 28)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(localized: "Subscription payback")
                    .font(.recap(17))
                    .foregroundStyle(RecapColor.limeInk)
                Spacer(minLength: 0)
                RecapFigureText(figure: .init(number: RecapFormat.multiple(payback.multiple), unit: "×"),
                                numberSize: 84, unitSize: 44, unitWeight: .semibold, tracking: -0.04, unitGap: 6, trimmed: true)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4).fill(RecapColor.ink).frame(height: 8)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(RecapColor.ink.opacity(0.28))
                            .frame(width: proxy.size.width * min(1, payback.paid / payback.used))
                    }
                    .frame(height: 8)
                    Text(String.localized("Paid \(RecapFormat.money(payback.paid, currency: recap.currency)) · used \(RecapFormat.money(payback.used, currency: recap.currency))"))
                        .font(.recap(14))
                        .foregroundStyle(RecapColor.limeInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // Calendar (or months) and rhythm.

    private var shapeRow: some View {
        let hasHours = recap.hours != nil && recap.peakHour != nil
        // Alone in the row, the calendar takes the width and grows to fill it.
        let wide = !deck.isYear && !hasHours
        return HStack(spacing: 20) {
            if deck.isYear {
                monthsCard.frame(maxWidth: .infinity)
            } else {
                calendarCard(wide: wide).frame(maxWidth: .infinity)
            }
            if hasHours { rhythmCard.frame(maxWidth: .infinity) }
        }
        .frame(height: wide ? 520 : 330)
    }

    private func calendarCard(wide: Bool) -> some View {
        let calendar = RecapFormat.calendar()
        let grid = RecapMonthGrid(monthStart: recap.start, days: recap.days, calendar: calendar)
        let maximum = recap.days.map(\.tokens).max() ?? 0
        let busiest = recap.busiestDay?.date
        let cell: CGFloat = wide ? 54 : (grid.rows > 5 ? 32 : 36)
        let gap: CGFloat = wide ? 12 : (grid.rows > 5 ? 7 : 8)
        return RecapBox(padding: EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle(.localized("Every day"), note: .localized("Darker days used more"))
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        ForEach(Array(RecapFormat.weekdayHeadings().enumerated()), id: \.offset) { _, heading in
                            Text(heading)
                                .font(.recap(13))
                                .foregroundStyle(RecapColor.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: cell)
                        }
                    }
                    ForEach(0..<grid.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { column in
                                dayCell(grid.cells[row * 7 + column], maximum: maximum, busiest: busiest, side: cell)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Recap.Day?, maximum: Int, busiest: Date?, side: CGFloat) -> some View {
        if let day {
            // Only the one day `Recap.busiestDay` names, not every tie.
            let isBusiest = day.tokens > 0 && day.date == busiest
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(RecapHeat.color(tokens: day.tokens, maximum: maximum))
                .frame(width: side, height: side)
                .overlay {
                    if isBusiest {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(RecapColor.ink, lineWidth: 2)
                            .padding(-4)
                    }
                }
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }

    private var monthsCard: some View {
        RecapBox(padding: EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(.localized("Month by month"), note: nil)
                RecapMonthBars(months: recap.months, labelSize: 14, labelHeight: 22)
            }
        }
    }

    private var rhythmCard: some View {
        RecapBox(dark: true, padding: EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localized: "Rhythm of the day")
                        .font(.recap(20, .semibold))
                        .foregroundStyle(RecapColor.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if let peak = recap.peakHour {
                        Text(String.localized("Peak \(RecapFormat.hourLabel(peak))"))
                            .font(.recap(14))
                            .foregroundStyle(RecapColor.paper.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                ZStack {
                    RecapClock(hours: recap.hours ?? [], highlight: recap.busiestHours, inner: 54, longest: 62, barWidth: 7, labelSize: 11)
                        .frame(width: 236, height: 236)
                    if let persona = recap.persona {
                        RecapPersonaGlyph(persona: persona, side: 30)
                    }
                }
                .frame(maxHeight: .infinity)
                if let window = recap.busiestHours {
                    Text(String.localized(
                        "\(RecapFormat.percent(window.share)) of it came between \(RecapFormat.hourLabel(window.start)) and \(RecapFormat.hourLabel(window.end))."
                    ))
                        .font(.recap(16))
                        .foregroundStyle(RecapColor.paper.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    // Models.

    private var modelsCard: some View {
        let models = Array(recap.models.prefix(5))
        let top = max(models.first?.share ?? 0, 0.0001)
        return RecapBox(padding: EdgeInsets(top: 26, leading: 28, bottom: 26, trailing: 28)) {
            VStack(alignment: .leading, spacing: 16) {
                cardTitle(.localized("Model ranking"), note: .localized("By token share"))
                ForEach(models.indices, id: \.self) { index in
                    HStack(spacing: 14) {
                        Text(verbatim: "0\(index + 1)")
                            .font(.recap(15, .regular, mono: true))
                            .foregroundStyle(RecapColor.faint)
                            .frame(width: 28, alignment: .leading)
                        Text(verbatim: models[index].name)
                            .font(.recap(19, .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(width: 210, alignment: .leading)
                        RecapRankBar(fraction: models[index].share / top, color: RecapColor.ranks[min(index, 4)], height: 14)
                        Text(verbatim: RecapFormat.percent(models[index].share))
                            .font(.recap(16, .regular, mono: true))
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    // Tiles: agents, cache, streak.

    private var tileCards: [AnyView] {
        var tiles: [AnyView] = []
        if !recap.agents.isEmpty { tiles.append(AnyView(agentsTile)) }
        if let rate = recap.cacheHitRate { tiles.append(AnyView(cacheTile(rate))) }
        if deck.streak != nil { tiles.append(AnyView(streakTile)) }
        return tiles
    }

    private var agentsTile: some View {
        let agents = recap.agents
        let top = Array(agents.prefix(agents.count > 3 ? 2 : agents.count))
        var parts = top.enumerated().map { index, agent in
            RecapDonut.Part(share: agent.share, color: [RecapColor.lime, RecapColor.ink, Color(recap: 0xB9B9B2)][index])
        }
        var legend: [(String, Double, Color)] = top.enumerated().map { index, agent in
            (agent.agent.displayName, agent.share, parts[index].color)
        }
        if agents.count > 3 {
            let other = agents.dropFirst(2).reduce(0) { $0 + $1.share }
            parts.append(.init(share: other, color: Color(recap: 0xB9B9B2)))
            legend.append((String.localized("Other"), other, Color(recap: 0xB9B9B2)))
        }
        return RecapBox(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized: "By agent")
                    .font(.recap(18, .semibold))
                    .lineLimit(1)
                ZStack {
                    RecapDonut(parts: parts, thickness: 13).frame(width: 96, height: 96)
                    Text(RecapWords.agents(agents.count))
                        .font(.recap(13, .regular, mono: true))
                        .foregroundStyle(RecapColor.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 60)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 5) {
                    ForEach(legend.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Circle().fill(legend[index].2).frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(RecapColor.ink.opacity(0.15), lineWidth: 1))
                            Text(verbatim: legend[index].0)
                                .font(.recap(14))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            Text(verbatim: RecapFormat.percent(legend[index].1))
                                .font(.recap(14, .regular, mono: true))
                                .foregroundStyle(RecapColor.secondary)
                        }
                    }
                }
            }
        }
    }

    private func cacheTile(_ rate: Double) -> some View {
        RecapBox(dark: true, padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(localized: "Cache hit")
                    .font(.recap(18, .semibold))
                    .foregroundStyle(RecapColor.paper)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(tight: RecapFormat.percent(rate), tracking: -76 * 0.04)
                    .font(.recap(76, .semibold))
                    .foregroundStyle(RecapColor.lime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if let saved = deck.cacheSavings {
                    RecapRichText(
                        text: .localized("Repeated context is read from the cache, saving about \(RecapEmphasis.mark(RecapFormat.money(saved, currency: recap.currency)))"),
                        size: 15, color: RecapColor.paper.opacity(0.72), emphasisWeight: .bold, highlights: false
                    )
                    .environment(\.colorScheme, .dark)
                }
            }
        }
    }

    private var streakTile: some View {
        let streak = deck.streak ?? (days: 0, isCurrent: false)
        let title: String = streak.isCurrent ? .localized("Current streak") : .localized("Longest streak")
        return RecapBox(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.recap(18, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(tight: "\(streak.days)", tracking: -76 * 0.04)
                        .font(.recap(76, .semibold))
                        .lineLimit(1)
                    Text(RecapWords.daysUnit(streak.days))
                        .font(.recap(28))
                        .lineLimit(1)
                    RecapFlame()
                        .fill(RecapColor.ink)
                        .frame(width: 30, height: 36)
                        .padding(.leading, 8)
                }
                .fixedSize()
                Spacer(minLength: 0)
                // Only a running period has a streak that is still going.
                if streak.isCurrent {
                    Text(String.localized("Still going · longest \(String.localized("\("\(recap.longestStreak)") days"))"))
                        .font(.recap(15))
                        .foregroundStyle(RecapColor.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // Busiest day and projects.

    private var lowCards: [AnyView] {
        var cards: [AnyView] = []
        if let day = recap.busiestDay { cards.append(AnyView(busiestCard(day))) }
        if !recap.projects.isEmpty { cards.append(AnyView(projectsCard)) }
        return cards
    }

    private func busiestCard(_ day: Recap.Day) -> some View {
        let figure = RecapFormat.tokens(day.tokens)
        let neighbours = busiestWindow(around: day)
        let maximum = neighbours.map(\.tokens).max() ?? 1
        return RecapBox(padding: EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localized: "Busiest day")
                        .font(.recap(18, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(verbatim: RecapFormat.dayWithWeekday(day.date))
                        .font(.recap(14))
                        .foregroundStyle(RecapColor.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    RecapFigureText(figure: figure, numberSize: 46, unitSize: 24, numberWeight: .semibold,
                                    unitWeight: .regular, tracking: -0.03, unitGap: 3)
                    if let cost = day.cost {
                        Text(verbatim: "≈ " + RecapFormat.money(cost, currency: recap.currency))
                            .font(.recap(20))
                            .foregroundStyle(RecapColor.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(neighbours.indices, id: \.self) { index in
                        let item = neighbours[index]
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.date == day.date ? RecapColor.lime : Color(recap: 0xE9E9E3))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, CGFloat(item.tokens) / CGFloat(max(maximum, 1)) * 72))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// Seven days with the busiest one among them, for the little bars: the
    /// week it falls in, trimmed to the days the recap has.
    private func busiestWindow(around day: Recap.Day) -> [Recap.Day] {
        let days = recap.days
        guard let index = days.firstIndex(where: { $0.date == day.date }) else { return [day] }
        let start = max(0, min(index - 5, days.count - 7))
        return Array(days[start..<min(days.count, start + 7)])
    }

    private var projectsCard: some View {
        let projects = Array(recap.projects.prefix(3))
        return RecapBox(padding: EdgeInsets(top: 24, leading: 26, bottom: 24, trailing: 26)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized: "Top projects")
                    .font(.recap(18, .semibold))
                    .lineLimit(1)
                ForEach(projects.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: "\(index + 1)")
                            .font(.recap(14, .regular, mono: true))
                            .foregroundStyle(RecapColor.faint)
                        Text(verbatim: deck.projectName(index, projects[index]))
                            .font(.recap(18, .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Text(deck.sessionsText(projects[index].sessions))
                            .font(.recap(15))
                            .foregroundStyle(RecapColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: RecapFormat.percent(projects[index].share))
                            .font(.recap(15, .regular, mono: true))
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(deck.provenance, id: \.self) { line in
                    Text(line)
                        .font(.recap(14))
                        .foregroundStyle(RecapColor.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 20)
            Text(verbatim: "PULSE · RECAP")
                .font(.recap(14, .regular, mono: true))
                .tracking(1.2)
                .foregroundStyle(RecapColor.tertiary)
        }
    }

    // MARK: - Pieces

    private func cardTitle(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.recap(20, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(.recap(14))
                    .foregroundStyle(RecapColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// A bar in a ranked list: a pale track with the fill over it.
struct RecapRankBar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(RecapColor.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(color)
                        .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
    }
}
