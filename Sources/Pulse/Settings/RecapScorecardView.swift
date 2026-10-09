// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The closing card: this was your month (or year).
///
/// Rows of one fact each, every one with a small picture of its own — the
/// total on a lime bar with the change on the period before, the money with
/// its daily line, a 2 × 2 of days / sessions / peak hour / cache, the strip of
/// every day, the tools as one segmented bar, the top model and the persona.
/// **A fact Pulse does not have is a row (or a cell, or a chart) left out**,
/// never a zero: the rows that remain share the height.
struct RecapScorecardView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    private enum Widget {
        case pips([RecapSlot])
        case note(String)
        case hours([Int], peak: Int)
        case meter(Double)
    }

    private struct Cell: Identifiable {
        let id: Int
        let figure: RecapFormat.Figure
        let label: String
        var wordUnit = false
        var widget: Widget?
    }

    var body: some View {
        RecapStoryPage(page: deck.page(of: .scorecard), stamp: deck.scoreStamp) {
            headline.padding(.top, 52)
            let sections = self.sections
            ForEach(sections.indices, id: \.self) { index in
                Spacer(minLength: 0)
                sections[index]
            }
            Spacer(minLength: 16)
            notes
            RecapRule(strong: true).padding(.top, 14)
            footer.padding(.top, 26)
        }
    }

    private var sections: [AnyView] {
        var sections: [AnyView] = [AnyView(hero)]
        if let cost = recap.cost { sections.append(AnyView(moneyRow(cost))) }
        sections.append(AnyView(grid))
        if !deck.scoreBars.isEmpty { sections.append(AnyView(strip)) }
        if !deck.scoreAgents.isEmpty { sections.append(AnyView(tools)) }
        if recap.models.first != nil || recap.persona != nil { sections.append(AnyView(bottom)) }
        return sections
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            // While the period runs it is not over yet: "That was your
            // October" on October 9 says a month that has hardly begun is done.
            Text(recap.isInProgress ? String.localized("So far, this is") : String.localized("That was"))
            RecapRichText(
                text: .localized("your \(RecapEmphasis.mark(deck.periodName))."),
                size: 84, weight: .black, emphasisWeight: .black
            )
        }
        .font(.recap(84, .black))
        .tracking(-0.84)
        .lineSpacing(0)
        .lineLimit(2)
        .minimumScaleFactor(0.5)
    }

    // MARK: - Rows

    /// A row: the hairline above it and the room around what it holds.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RecapRule()
            content().padding(.vertical, 22)
        }
    }

    // The total, huge on a lime bar, with the change on the period before.

    private var hero: some View {
        row {
            ViewThatFits(in: .horizontal) {
                heroRow(size: 210)
                heroRow(size: 180)
                heroRow(size: 150)
                heroRow(size: 120)
            }
        }
    }

    private func heroRow(size: CGFloat) -> some View {
        let label: String = {
            guard recap.isInProgress, let day = deck.lastDay else { return .localized("Tokens") }
            return .localized("Tokens · to \(RecapFormat.day(day))")
        }()
        return HStack(alignment: .bottom, spacing: 16) {
            RecapFigureText(figure: RecapFormat.tokens(recap.tokens), numberSize: size, unitSize: size * 0.45,
                            unitGap: 8, trimmed: true)
                .padding(.vertical, size * 0.09)
                .padding(.horizontal, 14)
                .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(RecapColor.lime) }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 14) {
                if let change = deck.sameSpanChange {
                    RecapPill(fill: RecapColor.ink, horizontal: 14, vertical: 7) {
                        Text(verbatim: "\(change.arrow) \(change.percent) \(change.versus)")
                            .font(.recap(18, .medium))
                            .foregroundStyle(RecapColor.lime)
                            .lineLimit(1)
                    }
                }
                Text(verbatim: label)
                    .font(.recap(20))
                    .foregroundStyle(RecapColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.bottom, size * 0.09)
        }
    }

    // The money, with its line.

    private func moneyRow(_ cost: Double) -> some View {
        row {
            ViewThatFits(in: .horizontal) {
                moneyContent(cost, size: 150)
                moneyContent(cost, size: 120)
                moneyContent(cost, size: 96)
            }
        }
    }

    private func moneyContent(_ cost: Double, size: CGFloat) -> some View {
        let series = deck.costSeries
        let label: String = {
            if series.isEmpty { return .localized("Estimated at API prices") }
            return deck.isYear ? .localized("Estimated at API prices · monthly") : .localized("Estimated at API prices · daily")
        }()
        return HStack(alignment: .bottom, spacing: 16) {
            RecapFigureText(figure: .init(number: RecapFormat.money(cost, currency: recap.currency), unit: ""),
                            numberSize: size, unitSize: 0, trimmed: true)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 12) {
                if !series.isEmpty {
                    RecapMiniLine(values: series).frame(width: 200, height: 54)
                }
                Text(verbatim: label)
                    .font(.recap(20))
                    .foregroundStyle(RecapColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: - The 2 × 2

    private var cells: [Cell] {
        var cells: [Cell] = []
        func add(_ figure: RecapFormat.Figure, _ label: String, word: Bool = false, widget: Widget? = nil) {
            cells.append(Cell(id: cells.count, figure: figure, label: label, wordUnit: word, widget: widget))
        }
        let slots = deck.scoreBars.map(\.slot)
        add(.init(number: "\(recap.activeDays)", unit: RecapWords.daysUnit(recap.activeDays)), .localized("Active days"), word: true,
            widget: slots.isEmpty ? nil : .pips(slots))
        var note: Widget?
        if let perDay = deck.sessionsPerActiveDay {
            note = .note(.localized("\("\(perDay)") per active day"))
        }
        add(.init(number: recap.sessions.formatted(.number.locale(LocalizationSource.locale)), unit: ""), .localized("Sessions"), widget: note)
        if let peak = recap.peakHour, let hours = recap.hours, hours.count == 24 {
            add(RecapFormat.hour(peak), .localized("Busiest hour"), widget: .hours(hours, peak: peak))
        }
        if let rate = recap.cacheHitRate {
            // "41%" or "<1%", as the poster prints it: split at the sign.
            let percent = RecapFormat.percent(rate)
            add(.init(number: String(percent.dropLast()), unit: "%"), .localized("Cache hit"), widget: .meter(rate))
        }
        return cells
    }

    private var grid: some View {
        let cells = self.cells
        let rows = (cells.count + 1) / 2
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 40) {
                    cellView(cells[row * 2])
                    // An odd one out takes the whole row, not a hole beside it.
                    if row * 2 + 1 < cells.count { cellView(cells[row * 2 + 1]) }
                }
            }
        }
    }

    private func cellView(_ cell: Cell) -> some View {
        ViewThatFits(in: .horizontal) {
            // The picture shrinks before the figure does, so the four figures
            // stay one size wherever they can.
            cellContent(cell, size: 110, scale: 1)
            cellContent(cell, size: 110, scale: 0.8)
            cellContent(cell, size: 110, scale: 0.62)
            cellContent(cell, size: 92, scale: 0.62)
            cellContent(cell, size: 76, scale: 0.62)
            cellContent(cell, size: 76, scale: 0, withWidget: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cellContent(_ cell: Cell, size: CGFloat, scale: CGFloat, withWidget: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 12) {
                RecapFigureText(figure: cell.figure, numberSize: size, unitSize: size * 0.45,
                                unitWeight: cell.wordUnit ? .bold : .black, unitGap: 6, trimmed: true)
                Spacer(minLength: 12)
                if withWidget, let widget = cell.widget { widgetView(widget, scale: scale) }
            }
            Text(verbatim: cell.label)
                .font(.recap(20))
                .foregroundStyle(RecapColor.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { RecapRule() }
    }

    @ViewBuilder
    private func widgetView(_ widget: Widget, scale: CGFloat) -> some View {
        switch widget {
        case .pips(let slots): RecapPips(slots: slots, scale: scale)
        case .note(let text):
            Text(verbatim: text)
                .font(.recap(18))
                .foregroundStyle(RecapColor.tertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 190 * scale + 20, alignment: .trailing)
                .padding(.bottom, 4)
        case .hours(let hours, let peak): RecapMiniHours(hours: hours, peak: peak, scale: scale)
        case .meter(let rate): RecapMeter(fraction: rate).frame(width: 200 * scale, height: 12).padding(.bottom, 4)
        }
    }

    // MARK: - Every day

    private var strip: some View {
        let bars = deck.scoreBars
        let isYear = deck.isYear
        let title: String = isYear ? .localized("Month by month") : .localized("Every day of \(deck.periodName)")
        return VStack(alignment: .leading, spacing: 14) {
            RecapRule()
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(.recap(22, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 12)
                if let note = deck.scoreBusiestNote {
                    Text(verbatim: note)
                        .font(.recap(18))
                        .foregroundStyle(RecapColor.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.top, 8)
            RecapBarStrip(bars: bars, axis: deck.scoreAxis, gap: isYear ? 12 : 5, height: 116, centeredEnds: isYear)
        }
        .padding(.bottom, 22)
    }

    // MARK: - Tools

    private var tools: some View {
        let agents = deck.scoreAgents
        return VStack(alignment: .leading, spacing: 14) {
            RecapRule()
            HStack(alignment: .firstTextBaseline) {
                Text(localized: "Tools")
                    .font(.recap(22, .bold))
                Spacer(minLength: 12)
                Text(localized: "By token share")
                    .font(.recap(18))
                    .foregroundStyle(RecapColor.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 8)
            RecapShareBar(agents: agents.map { ($0.share, Self.color($0.tone)) })
                .frame(height: 16)
            HStack(spacing: 24) {
                ForEach(agents.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.color(agents[index].tone))
                            .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(RecapColor.ink.opacity(0.2), lineWidth: 1) }
                            .frame(width: 12, height: 12)
                        Text(verbatim: agents[index].name)
                            .font(.recap(18))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(verbatim: RecapFormat.percent(agents[index].share))
                            .font(.recap(18, .regular, mono: true))
                            .foregroundStyle(RecapColor.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 22)
    }

    private static func color(_ tone: RecapScoreAgent.Tone) -> Color {
        switch tone {
        case .lime: RecapColor.lime
        case .ink: RecapColor.ink
        case .grey: RecapColor.restLabel
        }
    }

    // MARK: - Model and persona

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecapRule()
            HStack(alignment: .center, spacing: 20) {
                if let model = recap.models.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized: "Most used")
                            .font(.recap(20))
                            .foregroundStyle(RecapColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(tight: model.name, tracking: -0.8)
                                .font(.recap(40, .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .layoutPriority(1)
                            Text(verbatim: RecapFormat.percent(model.share))
                                .font(.recap(22, .medium))
                                .foregroundStyle(RecapColor.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
                Spacer(minLength: 12)
                if let persona = recap.persona {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(localized: "Your type")
                            .font(.recap(20))
                            .foregroundStyle(RecapColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        RecapPill(fill: RecapColor.ink, horizontal: 18, vertical: 8) {
                            Text(verbatim: persona.title)
                                .font(.recap(22, .medium))
                                .foregroundStyle(RecapColor.lime)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.top, 22)
        }
    }

    // MARK: - Notes and footer

    @ViewBuilder
    private var notes: some View {
        if deck.costIsFloor || recap.isPartial {
            VStack(alignment: .leading, spacing: 4) {
                if deck.costIsFloor {
                    Text(localized: "Some work had no published price, so the money is a floor.")
                }
                if recap.isPartial {
                    Text(localized: "Some tools' counts may be missing, so the total is a floor.")
                }
            }
            .font(.recap(15))
            .foregroundStyle(RecapColor.tertiary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            RecapMark(side: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Pulse").font(.recap(32, .semibold))
                Text(verbatim: "github.com/qunqin24/Pulse")
                    .font(.recap(17, .regular, mono: true))
                    .foregroundStyle(Color(recap: 0x55554F))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 16)
            Text(recap.isInProgress
                 ? String.localized("Check back when \(deck.periodName) is over")
                 : String.localized("See you in \(deck.nextName)"))
                .font(.recap(20))
                .foregroundStyle(RecapColor.tertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .trailing)
        }
    }
}

// MARK: - Small charts

/// One dot per day (or month): ink for work, grey for a quiet one that is
/// over, hollow for one still to come.
private struct RecapPips: View {
    let slots: [RecapSlot]
    let scale: CGFloat

    var body: some View {
        // A month is 11 across (31 days in three rows); a year's twelve are two
        // rows of six, bigger so they read.
        let isYear = slots.count == 12
        let columns = isYear ? 6 : 11
        let pip = (isYear ? 14.0 : 9.0) * scale
        let gap = 6.0 * scale
        let rows = stride(from: 0, to: slots.count, by: columns).map { Array(slots[$0..<min($0 + columns, slots.count)]) }
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        switch rows[row][column] {
                        case .active: Circle().fill(RecapColor.ink).frame(width: pip, height: pip)
                        case .quiet: Circle().fill(Color(recap: 0xE2E2DB)).frame(width: pip, height: pip)
                        case .future:
                            Circle().strokeBorder(Color(recap: 0xCFCFC8), lineWidth: 1.5).frame(width: pip, height: pip)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}

/// The 24 hours as small bars: the peak in ink, hours with work lime, empty
/// ones a stub of grey.
private struct RecapMiniHours: View {
    let hours: [Int]
    let peak: Int
    let scale: CGFloat

    var body: some View {
        let maximum = max(hours.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 2 * scale) {
            ForEach(hours.indices, id: \.self) { hour in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hour == peak ? RecapColor.ink : (hours[hour] > 0 ? RecapColor.lime : Color(recap: 0xE2E2DB)))
                    .frame(width: 5 * scale, height: max(3, CGFloat(hours[hour]) / CGFloat(maximum) * 54))
            }
        }
        .frame(height: 54, alignment: .bottom)
    }
}

/// A thin meter: a rate as lime on a grey track, ended by an ink tick.
private struct RecapMeter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(recap: 0xE2E2DB))
                Capsule().fill(RecapColor.lime).frame(width: max(width, 4))
                Rectangle().fill(RecapColor.ink).frame(width: 2).offset(x: max(width, 4) - 2)
            }
            .clipShape(Capsule())
        }
    }
}

/// The cost line: a stroke through one point per day (or month), a ring on each
/// when there are few of them, and the last point filled.
private struct RecapMiniLine: View {
    /// Nil breaks the line: work with no price, which is not a zero.
    let values: [Double?]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.compactMap({ $0 }).max(), maximum > 0 else { return }
            let inset: CGFloat = 5
            let points: [CGPoint?] = values.enumerated().map { index, value in
                value.map {
                    CGPoint(x: inset + CGFloat(index) / CGFloat(values.count - 1) * (size.width - inset * 2),
                            y: size.height - 4 - CGFloat($0 / maximum) * (size.height - 10))
                }
            }
            for run in RecapLineRuns.of(values) where run.count > 1 {
                var line = Path()
                line.move(to: points[run[0]]!)
                run.dropFirst().forEach { line.addLine(to: points[$0]!) }
                context.stroke(line, with: .color(RecapColor.ink),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            // A ring on every point while they are few enough to count, and
            // always on the last one that has a figure.
            let drawn = points.indices.filter { points[$0] != nil }
            let rings = values.count <= 12 ? drawn : Array(drawn.suffix(1))
            for index in rings {
                guard let center = points[index] else { continue }
                let dot = Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
                let isLast = index == drawn.last
                context.fill(dot, with: .color(isLast ? RecapColor.ink : RecapColor.paper))
                context.stroke(dot, with: .color(RecapColor.ink), lineWidth: 2)
            }
        }
    }
}

/// One bar per day (or month): the busiest ink, the others lime, a quiet one
/// only its grey slot, one still to come a dashed outline.
private struct RecapBarStrip: View {
    let bars: [RecapScoreBar]
    let axis: [(index: Int, label: String)]
    let gap: CGFloat
    let height: CGFloat
    /// Whether the first and last labels centre on their bars (twelve months)
    /// rather than sit flush with the strip's edges (days).
    let centeredEnds: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(bars.indices, id: \.self) { index in
                    bar(bars[index])
                }
            }
            .frame(height: height)
            GeometryReader { proxy in
                let slot = (proxy.size.width - gap * CGFloat(bars.count - 1)) / CGFloat(max(bars.count, 1))
                ForEach(axis.indices, id: \.self) { item in
                    let entry = axis[item]
                    let center = (slot + gap) * CGFloat(entry.index) + slot / 2
                    let width: CGFloat = centeredEnds ? slot + gap : 60
                    let isFirst = !centeredEnds && item == 0
                    let isLast = !centeredEnds && item == axis.count - 1
                    Text(verbatim: entry.label)
                        .font(.recap(16, .regular, mono: true))
                        .foregroundStyle(RecapColor.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(width: width, alignment: isFirst ? .leading : (isLast ? .trailing : .center))
                        .position(x: isFirst ? width / 2 : (isLast ? proxy.size.width - width / 2 : center), y: 11)
                }
            }
            .frame(height: 22)
        }
    }

    @ViewBuilder
    private func bar(_ bar: RecapScoreBar) -> some View {
        let radius: CGFloat = gap > 8 ? 8 : 5
        switch bar.slot {
        case .future:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(maxWidth: .infinity)
                .frame(height: height)
        case .quiet, .active:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(recap: 0xE6E6DF))
                if bar.slot == .active {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(bar.isBusiest ? RecapColor.ink : RecapColor.lime)
                        .frame(height: max(radius * 2, height * CGFloat(bar.fraction)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
    }
}

/// The share bar: each tool a segment, the width its share, with a sliver of a
/// minimum so a 1% tool is still there to see.
private struct RecapShareBar: View {
    let agents: [(share: Double, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let weights = agents.map { max($0.share, 0.012) }
            let total = weights.reduce(0, +)
            let free = proxy.size.width - gap * CGFloat(max(agents.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(agents.indices, id: \.self) { index in
                    Rectangle().fill(agents[index].color).frame(width: free * weights[index] / max(total, 0.0001))
                }
            }
            .clipShape(Capsule())
        }
    }
}
