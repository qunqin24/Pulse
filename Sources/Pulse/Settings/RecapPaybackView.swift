// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What the period cost at API prices against what the reader pays: the cost
/// and the multiple, a ruler of paid against used with the used bar cut by
/// model, three tiles, the cache's saving, the models, and the days.
struct RecapPaybackView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }
    private var insights: RecapInsights { RecapInsights(recap) }

    /// Bars for a ranked list, the same colours on the ruler and in the rows.
    private static let fills: [Color] = [
        RecapColor.ink, Color(recap: 0x4A4A4F), RecapColor.lime, Color(recap: 0x9A9A93), Color(recap: 0xC9C9C2),
    ]
    /// The slice of the ruler for what the five named models leave over.
    private static let remainder = Color(recap: 0xE2E2DB)

    private func money(_ amount: Double) -> String {
        RecapFormat.money(amount, currency: recap.currency)
    }

    var body: some View {
        if let payback = deck.payback {
            RecapStoryPage(page: deck.page(of: .payback)) {
                hero(payback).padding(.top, 44)
                Spacer(minLength: 20)
                ruler(payback)
                Spacer(minLength: 20)
                tiles
                Spacer(minLength: 20)
                cache
                Spacer(minLength: 20)
                models
                Spacer(minLength: 20)
                daily
                footnotes
            }
        }
    }

    // MARK: The figure

    /// The size that keeps a figure of `text` inside `available`, from digits
    /// that are about 0.56 em wide (tracking included) and signs about half that.
    private func fitted(_ text: String, base: CGFloat, available: CGFloat) -> CGFloat {
        let em = text.reduce(CGFloat(0)) { $0 + ($1.isNumber || $1 == "$" ? 0.56 : 0.3) }
        return min(base, available / max(em, 1))
    }

    private func hero(_ payback: RecapPayback) -> some View {
        let cost = money(payback.used)
        let size = fitted(cost, base: 250, available: 656)
        return VStack(alignment: .leading, spacing: 0) {
            Text(String.localized("On a plan of \(money(payback.monthlyPrice)) a month, you used"))
                .font(.recap(32))
                .foregroundStyle(Color(recap: 0x55554F))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 24) {
                Text(tight: cost, tracking: -size * 0.06)
                    .font(.recap(size, .bold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.top, 22 - size * RecapFigureText.ascenderRoom)
                    .padding(.bottom, -size * RecapFigureText.descenderRoom)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text(localized: "Payback")
                        .font(.recap(20, .bold))
                        .foregroundStyle(RecapColor.limeInk)
                    Text(tight: RecapFormat.multiple(payback.multiple) + "×", tracking: -84 * 0.04)
                        .font(.recap(84, .heavy))
                        .lineLimit(1)
                }
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 18, trailing: 24))
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RecapColor.lime))
                .fixedSize()
                .padding(.bottom, 6)
            }
            Text(String.localized("For every \(RecapFormat.axisMoney(1, step: 1, currency: recap.currency)) of subscription, you used \(money(payback.multiple)) of API value"))
                .font(.recap(20))
                .foregroundStyle(RecapColor.tertiary)
                .recapFit(0.6)
                .padding(.top, 34)
        }
    }

    // MARK: The ruler

    /// The models that have money, dearest first.
    private var pricedModels: [Recap.ModelShare] {
        recap.models.filter { ($0.cost ?? 0) > 0 }.sorted { ($0.cost ?? 0) > ($1.cost ?? 0) }
    }

    private func ruler(_ payback: RecapPayback) -> some View {
        let scale = RecapRulerScale(for: max(payback.used, payback.paid))
        let barArea: CGFloat = 690
        let named = Array(pricedModels.prefix(5))
        let shown = named.reduce(0.0) { $0 + ($1.cost ?? 0) }
        let rest = max(payback.used - shown, 0)
        let whole = max(shown + rest, 0.0001)
        let usedWidth = max(8, barArea * payback.used / scale.maximum)
        let gaps = CGFloat(named.count + (rest > 0.005 * payback.used ? 1 : 0) - 1) * 2
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                rulerLabel(.localized("You paid"))
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(RecapColor.ink, lineWidth: 2)
                        .frame(width: max(8, barArea * payback.paid / scale.maximum), height: 56)
                    Text(verbatim: money(payback.paid)).font(.recap(24, .semibold)).lineLimit(1)
                }
            }
            HStack(spacing: 18) {
                rulerLabel(.localized("You used"))
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        ForEach(named.indices, id: \.self) { index in
                            Rectangle()
                                .fill(Self.fills[index])
                                .frame(width: max(2, (usedWidth - max(gaps, 0)) * (named[index].cost ?? 0) / whole))
                        }
                        if rest > 0.005 * payback.used {
                            Rectangle().fill(Self.remainder)
                                .frame(width: max(2, (usedWidth - max(gaps, 0)) * rest / whole))
                        }
                    }
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(verbatim: money(payback.used)).font(.recap(24, .semibold)).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                Color.clear.frame(width: 110, height: 1)
                axis(scale: scale, width: barArea)
            }
        }
    }

    private func rulerLabel(_ title: String) -> some View {
        Text(title)
            .font(.recap(20))
            .foregroundStyle(RecapColor.secondary)
            .recapFit(0.6)
            .frame(width: 110, alignment: .leading)
    }

    private func axis(scale: RecapRulerScale, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(RecapColor.ink).frame(width: width, height: 1.5)
            ForEach(0...scale.ticks, id: \.self) { index in
                let value = Double(index) * scale.step / Double(scale.subdivisions)
                let labelled = index % scale.subdivisions == 0
                let x = width * value / scale.maximum
                VStack(spacing: 6) {
                    Rectangle().fill(RecapColor.ink).frame(width: 1.5, height: labelled ? 14 : 7)
                    if labelled {
                        Text(verbatim: RecapFormat.axisMoney(value, step: scale.step, currency: recap.currency))
                            .font(.recap(14, .regular, mono: true))
                            .foregroundStyle(RecapColor.tertiary)
                            .fixedSize()
                    }
                }
                .position(x: x, y: labelled ? 30 : 4)
            }
        }
        .frame(width: width, height: 44, alignment: .topLeading)
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        let saved = deck.cacheSavings
        let day = insights.costliestDay
        let perMillion = insights.costPerMillion
        if saved != nil || day != nil || perMillion != nil {
            HStack(spacing: 14) {
                if let saved, let cost = recap.cost, cost > 0 {
                    // "0.3× what you spent" says little; the line is for a saving
                    // that is more than the spend.
                    tile(
                        tone: .ink, label: .localized("The cache took off the API price"), value: money(saved),
                        note: saved >= cost ? String.localized("\(RecapFormat.multiple(saved / cost))× the estimate") : nil
                    )
                }
                if let day, let cost = day.cost {
                    tile(
                        tone: .white, label: .localized("Most expensive day"), value: money(cost),
                        note: RecapFormat.dayAndWeekday(day.date)
                    )
                }
                if let perMillion {
                    tile(
                        tone: .white, label: .localized("Per million tokens"), value: money(perMillion),
                        note: insights.costPerActiveDay.map { String.localized("Average per active day: \(money($0))") }
                    )
                }
            }
            .frame(height: 160)
        }
    }

    private func tile(tone: RecapTileTone, label: String, value: String, note: String?) -> some View {
        RecapTile(tone: tone) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: label)
                    .font(.recap(17))
                    .foregroundStyle(tone.caption)
                    .recapFit(0.6)
                Text(tight: value, tracking: -52 * 0.03)
                    .font(.recap(52, .bold))
                    .foregroundStyle(tone == .ink ? RecapColor.lime : RecapColor.ink)
                    .recapFit(0.5)
                Spacer(minLength: 0)
                if let note {
                    Text(verbatim: note)
                        .font(.recap(16))
                        .foregroundStyle(tone.detail)
                        .recapFit(0.6)
                }
            }
        }
    }

    // MARK: The cache

    @ViewBuilder
    private var cache: some View {
        if let saved = deck.cacheSavings, let cost = recap.cost, cost > 0 {
            let without = cost + saved
            let title: String = recap.cacheHitRate.map { .localized("Cache hit \(RecapFormat.percent($0))") }
                ?? .localized("The cache")
            VStack(spacing: 12) {
                RecapSectionHead(title: title, note: .localized("Repeated context is read straight from the cache"))
                    .padding(.bottom, 2)
                compareRow(label: .localized("Without the cache"), value: money(without), fraction: 1,
                           track: Color(recap: 0xE2E2DB), fill: Color(recap: 0xE2E2DB), bold: false)
                compareRow(label: .localized("With the cache"), value: money(cost), fraction: cost / without,
                           track: RecapColor.heatZero, fill: RecapColor.ink, bold: true)
            }
        }
    }

    private func compareRow(label: String, value: String, fraction: Double, track: Color, fill: Color, bold: Bool) -> some View {
        HStack(spacing: 16) {
            Text(verbatim: label)
                .font(.recap(19, bold ? .bold : .regular))
                .foregroundStyle(bold ? RecapColor.ink : RecapColor.secondary)
                .recapFit(0.6)
                .frame(width: 170, alignment: .leading)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(track)
                .frame(height: 26)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(fill)
                            .frame(width: max(8, proxy.size.width * fraction))
                    }
                }
            Text(verbatim: value)
                .font(.recap(19, bold ? .bold : .regular, mono: true))
                .recapFit(0.6)
                .frame(width: 120, alignment: .trailing)
        }
    }

    // MARK: Models

    @ViewBuilder
    private var models: some View {
        let rows = Array(pricedModels.prefix(5))
        let top = max(rows.first?.cost ?? 1, 0.0001)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                RecapSectionHead(title: .localized("Where the money went"), note: .localized("By model"))
                    .padding(.bottom, 10)
                ForEach(rows.indices, id: \.self) { index in
                    let first = index == 0
                    let model = rows[index]
                    RecapHairline()
                    HStack(spacing: 16) {
                        RecapMarkTile(resource: RecapVendorMark.resource(forModel: model.name), name: model.name, side: 44)
                        Text(verbatim: model.name)
                            .font(.recap(24, first ? .semibold : .regular))
                            .recapFit(0.6)
                            .frame(width: 250, alignment: .leading)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(RecapColor.heatZero)
                            .frame(height: 12)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Self.fills[index])
                                        .frame(width: max(6, proxy.size.width * (model.cost ?? 0) / top))
                                }
                            }
                        Text(verbatim: money(model.cost ?? 0))
                            .font(.recap(24, first ? .semibold : .regular))
                            .recapFit(0.6)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 13)
                }
            }
        }
    }

    // MARK: Days or months

    @ViewBuilder
    private var daily: some View {
        if let bars = insights.costBars, let top = bars.compactMap({ $0 }).max(), top > 0 {
            let best = bars.firstIndex(of: top)
            VStack(spacing: 10) {
                RecapHairline(strong: true).padding(.bottom, 8)
                RecapSectionHead(
                    title: deck.isYear ? .localized("Spent by month") : .localized("Spent by day"),
                    note: RecapWords.activeDays(recap.activeDays)
                )
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(bars.indices, id: \.self) { index in
                        if let bar = bars[index] {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(index == best ? RecapColor.ink : (bar > 0 ? RecapColor.lime : RecapColor.restBar))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(4, CGFloat(bar / top) * 90))
                        } else {
                            // No figure — a month to come or before the first
                            // record, or work with no price: an outline, not a zero.
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(RecapColor.rule, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(maxWidth: .infinity)
                                .frame(height: 12)
                        }
                    }
                }
                .frame(height: 92, alignment: .bottom)
                axisLabels(count: bars.count)
            }
        }
    }

    /// Day numbers (1, 10, 20 and the last) or the quarter's first months,
    /// under the bar they belong to.
    private func axisLabels(count: Int) -> some View {
        let labels: [(index: Int, text: String)] = deck.isYear
            ? [0, 3, 6, 9].map { ($0, RecapFormat.shortMonthName($0 + 1)) }
            : ([0, 9, 19, count - 1].filter { $0 < count }.reduce(into: [Int]()) { list, index in
                if !list.contains(index), list.last.map({ index - $0 >= 5 }) ?? true { list.append(index) }
            }).map { ($0, "\($0 + 1)") }
        return GeometryReader { proxy in
            let cell = proxy.size.width / CGFloat(max(count, 1))
            ForEach(labels, id: \.index) { label in
                Text(verbatim: label.text)
                    .font(.recap(14, .regular, mono: true))
                    .foregroundStyle(RecapColor.tertiary)
                    .lineLimit(1)
                    .frame(width: 60)
                    .position(x: (CGFloat(label.index) + 0.5) * cell, y: 9)
            }
        }
        .frame(height: 18)
    }

    // MARK: Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized: "Estimated at each model's published API price. The plan price is the one you typed in Pulse.")
            // A period still running: both figures stop today.
            if deck.payback?.isToDate == true {
                Text(localized: "Figures are to date, and the plan price is prorated by the days so far.")
            }
            if let begin = deck.recap.recordsBegin {
                Text(String.localized("The plan price is counted from \(RecapFormat.day(begin)), when records on this Mac begin."))
            }
            if deck.costIsFloor {
                Text(localized: "Some work had no published price, so the money is a floor.")
            }
        }
        .font(.recap(15))
        .foregroundStyle(RecapColor.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }
}
