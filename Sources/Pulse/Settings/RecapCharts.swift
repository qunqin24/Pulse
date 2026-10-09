// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Drawing the recap cards share, kept apart from the cards that place it.
/// Flat fills and strokes only.

// MARK: - Heat

enum RecapHeat {
    /// The calendar colour for a day: the heaviest day is ink, the rest step
    /// through four lights relative to it, and a quiet day is the empty tone.
    static func color(tokens: Int, maximum: Int) -> Color {
        guard tokens > 0, maximum > 0 else { return RecapColor.heatZero }
        return RecapColor.heat[step(tokens: tokens, maximum: maximum)]
    }

    /// 0...4, the last for the busiest day only.
    static func step(tokens: Int, maximum: Int) -> Int {
        guard maximum > 0 else { return 0 }
        if tokens >= maximum { return 4 }
        return min(Int(Double(tokens) / Double(maximum) * 4), 3)
    }
}

// MARK: - Month grid

/// The days of one month laid out Monday first: where the 1st falls, how many
/// weeks it takes, and which cell holds which day.
struct RecapMonthGrid {
    /// One entry per cell, row by row: nil for a blank before the 1st or after
    /// the last day, else the day.
    let cells: [Recap.Day?]
    let rows: Int

    /// - Parameters:
    ///   - monthStart: any instant in the month.
    ///   - days: the recap's days; those outside the month are ignored. A day
    ///     the recap does not carry (the future of a month still running)
    ///     leaves a blank.
    init(monthStart: Date, days: [Recap.Day], calendar: Calendar) {
        let first = calendar.dateInterval(of: .month, for: monthStart)?.start ?? monthStart
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        // Monday = 0.
        let lead = (calendar.component(.weekday, from: first) + 5) % 7
        let byDay = Dictionary(
            days.compactMap { day -> (Int, Recap.Day)? in
                guard calendar.isDate(day.date, equalTo: first, toGranularity: .month) else { return nil }
                return (calendar.component(.day, from: day.date), day)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var cells: [Recap.Day?] = Array(repeating: nil, count: lead)
        for number in 1...count { cells.append(byDay[number]) }
        while cells.count % 7 != 0 { cells.append(nil) }
        self.cells = cells
        self.rows = cells.count / 7
    }
}

// MARK: - Sparkline

/// A line over a filled area, the area in lime and the line in ink.
struct RecapSparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let maximum = values.max(), maximum > 0 else { return }
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * size.width,
                        y: size.height - 6 - CGFloat(value / maximum) * (size.height - 12))
            }
            var line = Path()
            line.move(to: points[0])
            points.dropFirst().forEach { line.addLine(to: $0) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(RecapColor.lime))
            context.stroke(line, with: .color(RecapColor.ink),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Donut

struct RecapDonut: View {
    struct Part {
        let share: Double
        let color: Color
    }

    let parts: [Part]
    let thickness: CGFloat

    var body: some View {
        Canvas { context, size in
            let radius = (min(size.width, size.height) - thickness) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let total = parts.reduce(0) { $0 + $1.share }
            guard total > 0 else { return }
            // A gap between parts, as the mockup has, drawn as a round cap's
            // worth of shortening.
            let gap = Double(thickness) / Double(radius) * 0.5
            var start = -Double.pi / 2
            for part in parts {
                let sweep = part.share / total * 2 * .pi
                let length = max(sweep - gap, 0.02)
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .radians(start + gap / 2), endAngle: .radians(start + gap / 2 + length),
                           clockwise: false)
                context.stroke(arc, with: .color(part.color),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                start += sweep
            }
        }
    }
}

// MARK: - Clock

/// 24 bars around a ring, one per hour, midnight at the top. The busiest
/// four hours (`Recap.busiestHours`) are lime; the rest are a muted grey that
/// gets lighter with less work.
struct RecapClock: View {
    let hours: [Int]
    let highlight: Recap.HourWindow?
    let inner: CGFloat
    let longest: CGFloat
    let barWidth: CGFloat
    let labelSize: CGFloat

    var body: some View {
        Canvas { context, size in
            guard hours.count == 24, let maximum = hours.max(), maximum > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - (inner - 26), y: center.y - (inner - 26),
                                       width: (inner - 26) * 2, height: (inner - 26) * 2))
            context.stroke(ring, with: .color(RecapColor.paper.opacity(0.12)), lineWidth: 1)

            for (hour, tokens) in hours.enumerated() {
                let fraction = Double(tokens) / Double(maximum)
                let length = longest * (0.12 + 0.88 * fraction)
                var layer = context
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .degrees(Double(hour) * 15))
                let bar = Path(roundedRect: CGRect(x: -barWidth / 2, y: -(inner + length), width: barWidth, height: length),
                               cornerRadius: barWidth / 2)
                if highlight?.contains(hour) == true {
                    layer.fill(bar, with: .color(RecapColor.lime))
                } else {
                    layer.fill(bar, with: .color(RecapColor.darkRest.opacity(0.38 + 0.62 * fraction)))
                }
            }
        }
        .overlay {
            // 0, 6, 12, 18 inside the ring, on the same angles as the bars.
            ZStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    let angle = Double(hour) * 15 - 90
                    let radius = inner - 12 - labelSize * 0.2
                    Text(verbatim: "\(hour)")
                        .font(.recap(labelSize, .regular, mono: true))
                        .foregroundStyle(RecapColor.paper.opacity(0.45))
                        .offset(x: radius * cos(angle * .pi / 180), y: radius * sin(angle * .pi / 180))
                }
            }
        }
    }
}
