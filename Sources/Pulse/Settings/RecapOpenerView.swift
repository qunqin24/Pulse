// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The month number or the year, a line, a lineup of the agents that did the
/// work as tiles, and a roster with each agent's days drawn as a strip.
struct RecapOpenerView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }
    private var isYear: Bool { deck.isYear }

    var body: some View {
        RecapStoryPage(page: deck.page(of: .opener), footnotes: deck.notes) {
            big.padding(.top, 36)
            headline.padding(.top, 34)
            Spacer(minLength: 24)
            lineup
            Spacer(minLength: 24)
            roster
            Spacer(minLength: 24)
            footer
        }
    }

    // MARK: The number and the line

    @ViewBuilder
    private var big: some View {
        switch recap.period {
        case .month(let year, let month):
            HStack(alignment: .bottom, spacing: 24) {
                Text(tight: String(format: "%02d", month), tracking: -340 * 0.07)
                    .font(.recap(340, .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, -340 * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -340 * RecapFigureText.descenderRoom)
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(RecapColor.lime)
                        .frame(width: 60, height: 60)
                    Text(verbatim: "\(year)")
                        .font(.recap(20, .regular, mono: true))
                        .foregroundStyle(Color(recap: 0x55554F))
                }
                .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
        case .year(let year):
            HStack(alignment: .bottom, spacing: 24) {
                Text(tight: "\(year)", tracking: -300 * 0.07)
                    .font(.recap(300, .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, -300 * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -300 * RecapFigureText.descenderRoom)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(RecapColor.lime)
                    .frame(width: 60, height: 60)
                    .padding(.bottom, 4)
                Spacer(minLength: 0)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String.localized("In \(deck.periodName),"))
            // The count is the lineup below it, so the line says how many
            // rather than a negative ("didn't code alone") that read oddly in
            // Chinese. One tool gets its own sentence: no plural to agree.
            if recap.agents.count == 1 {
                Text(localized: "One AI tool coded with you.")
            } else {
                Text(String.localized("\("\(recap.agents.count)") AI tools coded with you."))
            }
        }
        .font(.recap(66, .black))
        .tracking(-0.66)
        .lineSpacing(6)
        .lineLimit(3)
        .minimumScaleFactor(0.5)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: The lineup

    private enum Cell: Identifiable {
        case agent(rank: Int, Recap.AgentShare)
        case summary

        var id: Int {
            switch self {
            case .agent(let rank, _): rank
            case .summary: 0
            }
        }
    }

    private var lineup: some View {
        let agents = Array(recap.agents.prefix(4))
        var cells: [Cell] = agents.enumerated().dropFirst().map { .agent(rank: $0.offset + 1, $0.element) }
        cells.append(.summary)
        // Up to two cells each take a row; three or four sit in pairs, and an
        // odd one out spans the row.
        let rows: [[Cell]] = cells.count <= 2 ? cells.map { [$0] } : stride(from: 0, to: cells.count, by: 2).map {
            Array(cells[$0..<min($0 + 2, cells.count)])
        }
        return HStack(spacing: 14) {
            if let lead = agents.first { leadTile(lead).frame(width: 430, height: 430) }
            VStack(spacing: 14) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 14) {
                        ForEach(rows[row]) { cell in tile(cell) }
                    }
                }
            }
            .frame(height: 430)
        }
    }

    private func leadTile(_ agent: Recap.AgentShare) -> some View {
        RecapTile(tone: .ink, radius: 44, padding: EdgeInsets(top: 36, leading: 36, bottom: 36, trailing: 36)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    RecapGlyph(resource: agent.agent.iconResource, name: agent.agent.displayName, side: 120, color: RecapColor.lime)
                    Spacer(minLength: 0)
                    Text(verbatim: "01")
                        .font(.recap(18, .regular, mono: true))
                        .foregroundStyle(RecapColor.paper.opacity(0.55))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: agent.agent.displayName)
                        .font(.recap(26))
                        .foregroundStyle(RecapColor.paper.opacity(0.7))
                        .recapFit(0.6)
                    RecapFigureText(figure: RecapFormat.percentFigure(agent.share), numberSize: 110, unitSize: 50,
                                    color: RecapColor.lime, unitGap: 4)
                    Text(String.localized("Used \(RecapWords.days(agent.activeDays)) · top tool"))
                        .font(.recap(20))
                        .foregroundStyle(RecapColor.paper.opacity(0.6))
                        .recapFit(0.6)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ cell: Cell) -> some View {
        switch cell {
        case .agent(let rank, let agent):
            RecapTile(radius: 28, padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        RecapGlyph(resource: agent.agent.iconResource, name: agent.agent.displayName, side: 56, color: RecapColor.ink)
                        Spacer(minLength: 0)
                        Text(verbatim: String(format: "%02d", rank))
                            .font(.recap(15, .regular, mono: true))
                            .foregroundStyle(RecapColor.faint)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: agent.agent.displayName)
                        .font(.recap(19))
                        .foregroundStyle(RecapColor.secondary)
                        .recapFit(0.6)
                    Text(tight: RecapFormat.percent(agent.share), tracking: -44 * 0.03)
                        .font(.recap(44, .bold))
                        .lineLimit(1)
                }
            }
        case .summary:
            RecapTile(tone: .lime, radius: 28, padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized: "In all")
                        .font(.recap(19))
                        .foregroundStyle(RecapTileTone.lime.caption)
                    Spacer(minLength: 0)
                    RecapFigureText(
                        figure: .init(number: "\(recap.agents.count)", unit: RecapWords.toolsUnit(recap.agents.count)),
                        numberSize: 58, unitSize: 24, numberWeight: .heavy, unitWeight: .bold, unitGap: 6
                    )
                    .lineLimit(1)
                    Text(verbatim: RecapWords.activeDays(recap.activeDays))
                        .font(.recap(18))
                        .foregroundStyle(RecapTileTone.lime.caption)
                        .recapFit(0.6)
                }
            }
        }
    }

    // MARK: The roster

    private var roster: some View {
        let insights = RecapInsights(recap)
        let agents = Array(recap.agents.prefix(5))
        let note: String = isYear
            ? .localized("Which months · days used · token share")
            : .localized("Which days · days used · token share")
        return VStack(spacing: 0) {
            RecapSectionHead(title: .localized("Worked beside you"), note: note)
                .padding(.bottom, 12)
            ForEach(agents.indices, id: \.self) { index in
                let agent = agents[index]
                let first = index == 0
                RecapHairline()
                HStack(spacing: 20) {
                    RecapMarkTile(resource: agent.agent.iconResource, name: agent.agent.displayName, side: 64, lead: first)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tight: agent.agent.displayName, tracking: -0.6)
                            .font(.recap(first ? 34 : 30, first ? .bold : .medium))
                            .recapFit(0.5)
                        // A strip needs the dates; an agent without them has
                        // none to draw, and is left without one.
                        if !agent.activeDates.isEmpty {
                            RecapAgentStrip(marks: insights.marks(of: agent))
                        }
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: RecapWords.days(agent.activeDays))
                        .font(.recap(20))
                        .foregroundStyle(Color(recap: 0x55554F))
                        .recapFit(0.7)
                        .frame(width: 110, alignment: .trailing)
                    Text(verbatim: RecapFormat.percent(agent.share))
                        .font(.recap(20, .regular, mono: true))
                        .foregroundStyle(first ? RecapColor.ink : RecapColor.tertiary)
                        .padding(.horizontal, first ? 8 : 0)
                        .padding(.vertical, first ? 2 : 0)
                        .frame(width: 110, alignment: .trailing)
                        .background(first ? RecapColor.lime : .clear)
                }
                .padding(.vertical, 20)
            }
            // The headline counts every tool; the rows stop at five, so the
            // rest are named here rather than dropped without a word.
            let rest = Array(recap.agents.dropFirst(5))
            if !rest.isEmpty {
                RecapHairline()
                HStack(spacing: 20) {
                    Text(String.localized(
                        "\("\(rest.count)") more: \(rest.map(\.agent.displayName).formatted(.list(type: .and).locale(LocalizationSource.locale)))"
                    ))
                        .font(.recap(20))
                        .foregroundStyle(Color(recap: 0x55554F))
                        .lineLimit(2)
                        .recapFit(0.7)
                    Spacer(minLength: 0)
                    Text(verbatim: RecapFormat.percent(rest.reduce(0) { $0 + $1.share }))
                        .font(.recap(20, .regular, mono: true))
                        .foregroundStyle(RecapColor.tertiary)
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.vertical, 16)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            RecapHairline(strong: true)
            HStack {
                Text(localized: "Turn the page to see what you made together")
                    .font(.recap(22))
                    .foregroundStyle(Color(recap: 0x55554F))
                    .lineLimit(2)
                Spacer(minLength: 16)
                Image(systemName: "arrow.right")
                    .font(.system(size: 32, weight: .regular))
            }
            .padding(.top, 22)
        }
    }
}

/// The days (or months) of the period as a strip of cells: ink where the agent
/// worked, grey where another did, a pale fill for a quiet weekend and an
/// outline for a quiet weekday. A fixed width, so a 28-day month and a
/// 31-day one line up.
struct RecapAgentStrip: View {
    let marks: [RecapInsights.Mark]
    var width: CGFloat = 390
    var height: CGFloat = 22

    var body: some View {
        let count = max(marks.count, 1)
        let gap: CGFloat = count > 12 ? 3 : 4
        let cell = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        let radius: CGFloat = count > 12 ? 3 : 5
        HStack(spacing: gap) {
            ForEach(marks.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill(marks[index]))
                    .overlay {
                        if marks[index] == .quiet {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color(recap: 0xDCDCD5), lineWidth: 1)
                        } else if marks[index] == .toCome {
                            // Still to come: dashed, as the scorecard draws it.
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    .frame(width: cell, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private func fill(_ mark: RecapInsights.Mark) -> Color {
        switch mark {
        case .used: RecapColor.ink
        case .other: Color(recap: 0xE2E2DB)
        case .quietWeekend: Color(recap: 0xEDEDE7)
        case .quiet, .toCome: .clear
        }
    }
}
