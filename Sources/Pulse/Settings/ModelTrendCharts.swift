// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// One model's trends over the span the pane shows: output speed, the wait
/// for the first token, cache hit rate and tokens — a line each, by day, or
/// by hour over a day or two (`ModelSpendSummary.trend`).
///
/// **This Mac's records, not the provider's.** Speeds are timed from the
/// request to the end of its reply as the CLIs logged them; the first token is
/// Codex's own measure, and no other agent's log carries one. A point with too
/// little behind it is skipped, never drawn as a zero: the line joins its
/// neighbours, and only measured points carry a dot.
struct ModelTrendCharts: View {
    let model: ModelSpendSummary

    var body: some View {
        SettingsGroup(String.localized("Trends")) {
            // Stacks, not a `Grid`: a `Divider` in a grid row is drawn across
            // its cell, a horizontal rule where the column break should be.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    card(String.localized("Tokens/s"),
                         figure: model.averageSpeed.map { String.localized("Average \(Self.speed($0))") },
                         values: model.trend.map(\.tokensPerSecond), tint: .orange)
                    Divider()
                    card(String.localized("First token"),
                         figure: model.averageFirstToken.map { String.localized("Average \(Self.seconds($0))") },
                         values: model.trend.map(\.firstToken), tint: .purple)
                }
                Divider()
                HStack(spacing: 0) {
                    card(String.localized("Cache hit rate"),
                         figure: model.cacheHitRate.map { String.localized("Average \(Self.percent($0))") },
                         values: model.trend.map(\.cacheHitRate), tint: .teal)
                    Divider()
                    card(String.localized("Usage"),
                         figure: String.localized("\(TokenCount.short(model.tokens)) tokens"),
                         values: model.trend.map { $0.tokens.map(Double.init) }, tint: .blue, fromZero: true)
                }
            }
        }
    }

    private func card(_ title: String, figure: String?, values: [Double?], tint: Color, fromZero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: figure ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if values.contains(where: { $0 != nil }) {
                TrendLine(values: values, tint: tint, fromZero: fromZero)
                    .frame(height: 90)
            } else {
                Text(localized: "Not enough data in this span.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }

            HStack {
                Text(verbatim: model.trend.first.map { label($0.start) } ?? "")
                Spacer(minLength: 0)
                Text(verbatim: model.trend.last.map { label($0.start) } ?? "")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func label(_ date: Date) -> String {
        model.trendIsHourly
            ? date.formatted(.dateTime.hour().minute().locale(LocalizationSource.locale))
            : date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }

    static func speed(_ value: Double) -> String { "\(Int(value.rounded())) tok/s" }
    static func seconds(_ value: TimeInterval) -> String {
        String.localized("\(value.formatted(.number.precision(.fractionLength(1)).locale(LocalizationSource.locale))) s")
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(LocalizationSource.locale))
    }
}

/// A smooth line through the points that have a value, at their place along
/// the span. A point with none is skipped and the line joins its neighbours,
/// with a dot at every measured point so a joined stretch is not taken for
/// measured; a lone point is a dot alone.
///
/// **Scaled to the figures' own range**, padded a little, so a speed that
/// moves between 80 and 110 tok/s reads as moving — from zero it was a flat
/// line pressed against the top. `fromZero` keeps zero at the bottom, for the
/// tokens, where a quiet day is a real zero.
private struct TrendLine: View {
    let values: [Double?]
    let tint: Color
    var fromZero = false

    var body: some View {
        GeometryReader { proxy in
            let measured = values.enumerated().compactMap { index, value in value.map { (index, $0) } }
            let range = Self.range(measured.map(\.1), fromZero: fromZero)
            let points = measured.map { index, value in
                CGPoint(
                    x: values.count > 1 ? proxy.size.width * CGFloat(index) / CGFloat(values.count - 1) : proxy.size.width / 2,
                    y: proxy.size.height * (1 - CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                )
            }

            ZStack {
                Self.smooth(points)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if points.count < 40 {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle().fill(tint).frame(width: 4, height: 4).position(point)
                    }
                }
            }
        }
    }

    /// The figures' span with a tenth of it either side, or a band around a
    /// single value; zero at the bottom when asked.
    static func range(_ values: [Double], fromZero: Bool) -> ClosedRange<Double> {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        if fromZero { return 0...max(high * 1.1, .leastNonzeroMagnitude) }
        let pad = high > low ? (high - low) * 0.1 : max(abs(high) * 0.1, 0.01)
        return (low - pad)...(high + pad)
    }

    /// Quadratic curves through the midpoints, with each point as the control:
    /// smooth, and never beyond the points themselves, as a spline can be.
    static func smooth(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            guard points.count > 2 else {
                points.dropFirst().forEach { path.addLine(to: $0) }
                return
            }
            for index in 1..<(points.count - 1) {
                let middle = CGPoint(x: (points[index].x + points[index + 1].x) / 2,
                                     y: (points[index].y + points[index + 1].y) / 2)
                path.addQuadCurve(to: middle, control: points[index])
            }
            path.addLine(to: points[points.count - 1])
        }
    }
}
