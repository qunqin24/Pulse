// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The hour you work hardest, a 24-hour dial, when the day starts and ends,
/// the day in four parts, every hour as a bar, and the days of the week.
struct RecapTimetableView: View {
    let deck: RecapDeck

    private var recap: Recap { deck.recap }

    var body: some View {
        let hours = recap.hours ?? []
        let peak = recap.peakHour ?? 0
        let insights = RecapInsights(recap)
        RecapStoryPage(page: deck.page(of: .timetable), footnotes: deck.notes) {
            HStack(alignment: .bottom) {
                RecapFigureText(figure: RecapFormat.hour(peak), numberSize: 230, unitSize: 100, unitGap: 10, trimmed: true)
                Spacer(minLength: 12)
                if let persona = recap.persona {
                    RecapPill(fill: RecapColor.ink, horizontal: 16, vertical: 8) {
                        Text(persona.title)
                            .font(.recap(20))
                            .foregroundStyle(RecapColor.lime)
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 44)
            Text(localized: "is your busiest hour of the day.")
                .font(.recap(42, .heavy))
                .lineSpacing(6)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 26)
            Spacer(minLength: 20)
            HStack(spacing: 34) {
                RecapDial(hours: hours, peak: peak, size: 460)
                stats(insights)
            }
            Spacer(minLength: 20)
            quarters(insights)
            Spacer(minLength: 20)
            hourBars(hours, peak: peak)
            Spacer(minLength: 20)
            weekdays(insights)
        }
    }

    // MARK: Start, end and the late hours

    private func stats(_ insights: RecapInsights) -> some View {
        VStack(spacing: 0) {
            if let first = insights.firstHour {
                stat(
                    label: .localized("Earliest start"),
                    value: RecapFormat.hourLabel(first),
                    note: .localized("The earliest hour after 5 AM with any work")
                )
            }
            if let latest = recap.latestMinute {
                stat(
                    label: .localized("Finishes latest"),
                    value: RecapFormat.clockTime(minutes: latest),
                    note: recap.lateNights > 0 ? RecapWords.nightsPastMidnight(recap.lateNights) : nil
                )
            }
            if let window = recap.busiestHours {
                stat(
                    label: .localized("\(RecapFormat.hourLabel(window.start)) to \(RecapFormat.hourLabel(window.end))"),
                    value: RecapFormat.percent(window.share),
                    note: .localized("of your usage fell in these hours")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(label: String, value: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(.recap(18))
                .foregroundStyle(RecapColor.secondary)
                .recapFit(0.6)
            Text(tight: value, tracking: -52 * 0.03)
                .font(.recap(52, .bold))
                .recapFit(0.5)
            if let note {
                Text(verbatim: note)
                    .font(.recap(16))
                    .foregroundStyle(RecapColor.tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { RecapHairline() }
    }

    // MARK: The day in four parts

    @ViewBuilder
    private func quarters(_ insights: RecapInsights) -> some View {
        if let quarters = insights.quarters, let lead = insights.leadingQuarter {
            let names: [String] = [
                .localized("Small hours"), .localized("Morning"), .localized("Afternoon"), .localized("Evening"),
            ]
            let kinds: [RecapDayGlyph.Kind] = [.night, .sunrise, .day, .sunset]
            VStack(spacing: 14) {
                RecapSectionHead(title: .localized("Four parts of the day"), note: .localized("Busiest: \(names[lead])"))
                HStack(spacing: 14) {
                    ForEach(quarters.indices, id: \.self) { index in
                        quarterTile(quarters[index], name: names[index], kind: kinds[index], lead: index == lead)
                    }
                }
                .frame(height: 194)
            }
        }
    }

    private func quarterTile(_ quarter: RecapInsights.Quarter, name: String, kind: RecapDayGlyph.Kind, lead: Bool) -> some View {
        let tone: RecapTileTone = lead ? .ink : .white
        let span = String(format: "%02d–%02d", quarter.hours.lowerBound, quarter.hours.upperBound)
        return RecapTile(tone: tone, padding: EdgeInsets(top: 20, leading: 20, bottom: 18, trailing: 20)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RecapDayGlyph(kind: kind, side: 30, color: lead ? RecapColor.lime : RecapColor.ink)
                    Spacer(minLength: 0)
                    Text(verbatim: span)
                        .font(.recap(15, .regular, mono: true))
                        .foregroundStyle(lead ? RecapColor.paper.opacity(0.55) : RecapColor.tertiary)
                }
                Spacer(minLength: 0)
                Text(verbatim: name)
                    .font(.recap(20))
                    .foregroundStyle(lead ? RecapColor.paper.opacity(0.75) : RecapColor.ink)
                    .recapFit(0.6)
                    .padding(.bottom, 8)
                RecapFigureText(
                    figure: RecapFormat.percentFigure(quarter.share), numberSize: 54, unitSize: 26,
                    numberWeight: .bold, unitWeight: .bold, color: lead ? RecapColor.lime : RecapColor.ink,
                    tracking: -0.03, unitGap: 2
                )
                .padding(.bottom, 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(lead ? Color(recap: 0x34343A) : RecapColor.heatZero)
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(lead ? RecapColor.lime : RecapColor.ink)
                                .frame(width: max(proxy.size.width * quarter.share, 4))
                        }
                    }
            }
        }
    }

    // MARK: Every hour

    private func hourBars(_ hours: [Int], peak: Int) -> some View {
        let top = max(hours.max() ?? 1, 1)
        let figure = RecapFormat.tokens(hours.indices.contains(peak) ? hours[peak] : 0)
        return VStack(spacing: 10) {
            RecapSectionHead(
                title: .localized("24 hours"),
                note: String.localized("Peak \(RecapFormat.hourLabel(peak))") + " · " + figure.text
            )
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<min(24, hours.count), id: \.self) { hour in
                    let value = hours[hour]
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hour == peak ? RecapColor.ink : (value > 0 ? RecapColor.lime : RecapColor.restBar))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, CGFloat(value) / CGFloat(top) * 120))
                }
            }
            .frame(height: 124, alignment: .bottom)
            HStack(spacing: 5) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(verbatim: hour % 3 == 0 || hour == peak ? String(format: "%02d", hour) : "")
                        .font(.recap(14, hour == peak ? .semibold : .regular, mono: true))
                        .foregroundStyle(hour == peak ? RecapColor.ink : RecapColor.faint)
                        .recapFit(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: The week

    @ViewBuilder
    private func weekdays(_ insights: RecapInsights) -> some View {
        let tokens = insights.weekdayAverages
        let top = tokens.compactMap { $0 }.max() ?? 0
        if top > 0, let best = insights.busiestWeekday {
            let names = RecapFormat.weekdayNames()
            VStack(spacing: 14) {
                RecapHairline(strong: true).padding(.bottom, 8)
                RecapSectionHead(title: .localized("Seven days of the week"), note: .localized("Busiest on average: \(names[best])"))
                HStack(spacing: 14) {
                    ForEach(0..<7, id: \.self) { index in
                        weekdayColumn(name: names[index], tokens: tokens[index], top: top, isBest: index == best)
                    }
                }
            }
        }
    }

    private func weekdayColumn(name: String, tokens: Int?, top: Int, isBest: Bool) -> some View {
        let used = (tokens ?? 0) > 0
        return VStack(spacing: 10) {
            Text(verbatim: used ? RecapFormat.tokens(tokens ?? 0).text : "—")
                .font(.recap(15, .regular, mono: true))
                .foregroundStyle(isBest ? RecapColor.ink : RecapColor.tertiary)
                .recapFit(0.6)
            ZStack(alignment: .bottom) {
                if used {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isBest ? RecapColor.ink : RecapColor.lime)
                        .frame(height: max(6, CGFloat(tokens ?? 0) / CGFloat(top) * 120))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(recap: 0xCFCFC8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(height: 24)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120, alignment: .bottom)
            Text(verbatim: name)
                .font(.recap(20, isBest ? .bold : .regular))
                .foregroundStyle(isBest ? RecapColor.ink : RecapColor.secondary)
                .recapFit(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The dial

/// The 24 hours as a clock face: one wedge per hour, as long as the hour's
/// work, midnight at the top. The peak is ink, an hour with work lime, an hour
/// with none grey; a hand points to the peak.
struct RecapDial: View {
    let hours: [Int]
    let peak: Int
    var size: CGFloat = 460

    var body: some View {
        let k = size / 460
        let inner = 118 * k
        ZStack {
            Canvas { context, canvasSize in
                guard hours.count == 24, let top = hours.max(), top > 0 else { return }
                var layer = context
                layer.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)

                let face = Path(ellipseIn: CGRect(x: -204 * k, y: -204 * k, width: 408 * k, height: 408 * k))
                layer.fill(face, with: .color(RecapColor.white))
                layer.stroke(face, with: .color(RecapColor.hairline), lineWidth: 1.5)

                // Ninety-six ticks, a longer one at every hour.
                for index in 0..<96 {
                    let long = index % 4 == 0
                    let angle = Double(index) * 3.75 - 90
                    var tick = Path()
                    tick.move(to: Self.point(angle, 196 * k))
                    tick.addLine(to: Self.point(angle, (long ? 203 : 199) * k))
                    layer.stroke(tick, with: .color(long ? RecapColor.ink : Color(recap: 0xC9C9C2)), lineWidth: long ? 2 : 1)
                }

                // One wedge per hour, a hair narrower than its 15 degrees.
                for hour in 0..<24 {
                    let value = hours[hour]
                    let start = Angle.degrees(Double(hour) * 15 - 90 + 1.2)
                    let end = Angle.degrees(Double(hour + 1) * 15 - 90 - 1.2)
                    let reach = value > 0 ? max(inner + 4 * k, inner + (182 * k - inner) * CGFloat(value) / CGFloat(top)) : inner + 4 * k
                    var wedge = Path()
                    wedge.addArc(center: .zero, radius: reach, startAngle: start, endAngle: end, clockwise: false)
                    wedge.addArc(center: .zero, radius: inner, startAngle: end, endAngle: start, clockwise: true)
                    wedge.closeSubpath()
                    layer.fill(wedge, with: .color(hour == peak ? RecapColor.ink : (value > 0 ? RecapColor.lime : RecapColor.restBar)))
                }

                // The hand, to the middle of the peak hour.
                let angle = (Double(peak) + 0.5) * 15 - 90
                var hand = Path()
                hand.move(to: .zero)
                hand.addLine(to: Self.point(angle, inner - 40 * k))
                layer.stroke(hand, with: .color(RecapColor.ink), style: StrokeStyle(lineWidth: 7 * k, lineCap: .round))
                layer.fill(Path(ellipseIn: CGRect(x: -16 * k, y: -16 * k, width: 32 * k, height: 32 * k)), with: .color(RecapColor.ink))
                layer.fill(Path(ellipseIn: CGRect(x: -6 * k, y: -6 * k, width: 12 * k, height: 12 * k)), with: .color(RecapColor.lime))
            }
            // 00, 06, 12, 18 inside the wedges, on the angles of the hours.
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                let angle = Double(hour) * 15 - 90
                let radius = inner - 24 * k
                Text(verbatim: String(format: "%02d", hour))
                    .font(.recap(20 * k, .regular, mono: true))
                    .foregroundStyle(RecapColor.tertiary)
                    .offset(x: radius * cos(angle * .pi / 180), y: radius * sin(angle * .pi / 180))
            }
        }
        .frame(width: size, height: size)
    }

    private static func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: radius * cos(degrees * .pi / 180), y: radius * sin(degrees * .pi / 180))
    }
}

// MARK: - Day glyphs

/// A moon, a sunrise, a sun and a sunset as line drawings on a 24-point grid,
/// for the four parts of the day.
struct RecapDayGlyph: View {
    enum Kind { case night, sunrise, day, sunset }

    let kind: Kind
    let side: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let k = min(size.width, size.height) / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            func line(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) -> Path {
                var path = Path()
                path.move(to: point(ax, ay))
                path.addLine(to: point(bx, by))
                return path
            }
            let style = StrokeStyle(lineWidth: 2 * k, lineCap: .round, lineJoin: .round)
            var path = Path()
            switch kind {
            case .night:
                // A crescent: a small arc about one centre, a large one about the other.
                let c1 = point(17.676, 6.324), c2 = point(11.824, 12.176)
                path.addArc(center: c1, radius: 8.5 * k, startAngle: .degrees(74.2), endAngle: .degrees(195.8), clockwise: false)
                path.addArc(center: c2, radius: 8.5 * k, startAngle: .degrees(254.2), endAngle: .degrees(15.8), clockwise: true)
                path.closeSubpath()
            case .sunrise, .sunset:
                path.addPath(line(4, 18, 20, 18))
                path.move(to: point(7, 18))
                path.addArc(center: point(12, 18), radius: 5 * k, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                if kind == .sunrise {
                    path.addPath(line(12, 5, 12, 8))
                    path.addPath(line(5.6, 9.6, 7.4, 11.4))
                    path.addPath(line(18.4, 9.6, 16.6, 11.4))
                } else {
                    path.addPath(line(12, 12, 12, 9))
                    path.move(to: point(9.5, 10.5))
                    path.addLine(to: point(12, 13))
                    path.addLine(to: point(14.5, 10.5))
                }
            case .day:
                path.addEllipse(in: CGRect(x: 8 * k, y: 8 * k, width: 8 * k, height: 8 * k))
                for ray in [(12.0, 2.0, 12.0, 4.5), (12, 19.5, 12, 22), (2, 12, 4.5, 12), (19.5, 12, 22, 12),
                            (4.9, 4.9, 6.7, 6.7), (17.3, 17.3, 19.1, 19.1), (4.9, 19.1, 6.7, 17.3), (17.3, 6.7, 19.1, 4.9)] {
                    path.addPath(line(ray.0, ray.1, ray.2, ray.3))
                }
            }
            context.stroke(path, with: .color(color), style: style)
        }
        .frame(width: side, height: side)
    }
}
