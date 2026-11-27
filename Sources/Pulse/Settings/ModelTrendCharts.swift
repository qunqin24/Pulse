// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// One model's trends over the span the pane shows: output speed, the wait
/// for the first token, cache hit rate and tokens — a line each, by day, or
/// by hour over a day or two (`ModelSpendSummary.trend`).
///
/// **This Mac's records, not the provider's.** Speeds are timed from the
/// request to the end of its reply as the CLIs logged them; the first token is
/// Codex's own measure, and no other agent's log carries one. A point with too
/// little behind it is a gap in the line, never a zero.
struct ModelTrendCharts: View {
    let model: ModelSpendSummary

    var body: some View {
        SettingsGroup(String.localized("Trends")) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    card(String.localized("Tokens/s"),
                         figure: model.averageSpeed.map { String.localized("Average \(Self.speed($0))") },
                         values: model.trend.map(\.tokensPerSecond), tint: .orange)
                    Divider()
                    card(String.localized("First token"),
                         figure: model.averageFirstToken.map { String.localized("Average \(Self.seconds($0))") },
                         values: model.trend.map(\.firstToken), tint: .purple)
                }
                Divider()
                GridRow {
                    card(String.localized("Cache hit rate"),
                         figure: model.cacheHitRate.map { String.localized("Average \(Self.percent($0))") },
                         values: model.trend.map(\.cacheHitRate), tint: .teal, ceiling: 1)
                    Divider()
                    card(String.localized("Usage"),
                         figure: String.localized("\(TokenCount.short(model.tokens)) tokens"),
                         values: model.trend.map { $0.tokens.map(Double.init) }, tint: .blue)
                }
            }
        }
    }

    private func card(_ title: String, figure: String?, values: [Double?], tint: Color, ceiling: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: figure ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if values.contains(where: { $0 != nil }) {
                TrendLine(values: values, tint: tint, ceiling: ceiling)
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

/// A line over evenly spaced points, broken where a point is nil; a point
/// with no neighbour is a dot. Scaled from zero to the largest value (or to
/// `ceiling`, for a rate), so two lines' heights compare.
private struct TrendLine: View {
    let values: [Double?]
    let tint: Color
    var ceiling: Double?

    var body: some View {
        GeometryReader { proxy in
            let top = max(ceiling ?? (values.compactMap { $0 }.max() ?? 0) * 1.1, .leastNonzeroMagnitude)
            let step = values.count > 1 ? proxy.size.width / CGFloat(values.count - 1) : 0
            let point = { (index: Int, value: Double) in
                CGPoint(x: values.count > 1 ? CGFloat(index) * step : proxy.size.width / 2,
                        y: proxy.size.height * (1 - CGFloat(min(value / top, 1))))
            }

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                }
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)

                Path { path in
                    var drawing = false
                    for (index, value) in values.enumerated() {
                        guard let value else { drawing = false; continue }
                        if drawing { path.addLine(to: point(index, value)) } else { path.move(to: point(index, value)) }
                        drawing = true
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if let value, Self.isolated(index, in: values) {
                        Circle().fill(tint).frame(width: 4, height: 4).position(point(index, value))
                    }
                }
            }
        }
    }

    static func isolated(_ index: Int, in values: [Double?]) -> Bool {
        let before = index > 0 ? values[index - 1] : nil
        let after = index + 1 < values.count ? values[index + 1] : nil
        return before == nil && after == nil
    }
}
