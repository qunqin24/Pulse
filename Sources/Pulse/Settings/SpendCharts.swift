// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// One agent's or one model's share of the whole, as a bar.
///
/// A bar rather than a percentage because the list is read by comparing rows,
/// and a column of percentages has to be compared digit by digit.
struct ShareBar: View {
    let share: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    // A share too small to see is still a share: anything at
                    // all keeps a visible stub, the same rule the ring follows.
                    .frame(width: max(proxy.size.width * min(max(share, 0), 1), share > 0 ? 3 : 0))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((share * 100).rounded()))%")
    }
}

/// Tokens per day, across every agent or one model.
///
/// Its own view rather than the card's `DailyTokensChart`: that one takes
/// `LedgerDay`, which belongs to one provider, and this bar is several agents'
/// work on one day. **It is a calendar, not a money chart** — only the day and
/// its token count are read, so a model can draw it without inventing a cost.
struct SpendBarChart: View {
    /// One day's bar. The model's own `Day` carries a `date` and `tokens` too,
    /// and both are projected into this so the same chart serves either.
    struct Bar: Identifiable, Equatable {
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    let bars: [Bar]

    /// **A bar is never wider than this.** Dividing the pane by the number of
    /// days and using the result is right at ninety bars and absurd at seven:
    /// a week filled the width with columns 160pt across and 64pt tall, which
    /// reads as a row of blocks rather than as a chart. Each day still gets an
    /// equal slot — that is what keeps the spacing even and the dates
    /// honest — and the bar sits in the middle of its own.
    private static let maxBarWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let peak = max(bars.map(\.tokens).max() ?? 1, 1)
                let slot = proxy.size.width / CGFloat(max(bars.count, 1))
                let width = max(min(slot * 0.72, Self.maxBarWidth), 1)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars) { bar in
                        RoundedRectangle(cornerRadius: min(width, 5) / 2, style: .continuous)
                            .fill(bar.tokens > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            // A day with any work at all keeps a visible stub,
                            // so a quiet day reads as quiet rather than as
                            // missing.
                            .frame(
                                width: width,
                                height: bar.tokens > 0
                                    ? max((proxy.size.height - 1) * CGFloat(bar.tokens) / CGFloat(peak), 3)
                                    : 2
                            )
                            .frame(width: slot, alignment: .center)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SpendFormat.chartDate(bar.date))
                            .accessibilityValue(SpendFormat.tokens(bar.tokens))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // The line the bars stand on. Without it the short days float
                // and the whole thing reads as blocks rather than a chart.
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
                .overlay {
                    ChartHoverOverlay(samples: bars.enumerated().map { index, bar in
                        .init(
                            x: slot * (CGFloat(index) + 0.5),
                            title: SpendFormat.chartDate(bar.date),
                            tokens: bar.tokens
                        )
                    })
                }
            }

            // Only the ends. A label under every bar is unreadable at ninety
            // of them and unnecessary at seven — the tooltip has the rest.
            if let first = bars.first, let last = bars.last, bars.count > 1 {
                HStack {
                    Text(Self.shortDate(first.date))
                    Spacer(minLength: 0)
                    Text(Self.shortDate(last.date))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Tokens per day"))
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }
}

/// Tokens by hour of the local day.
///
/// Its own view because it is drawn in more than one place for more than one
/// reason: as the whole shape of today, where a single daily bar says nothing;
/// as the profile of a longer span, where it answers "when do I work"; and as
/// one model's hours rather than every agent's.
struct HourProfile: View {
    let hours: [Int: Int]

    var body: some View {
        let peak = max(hours.values.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let width = max((proxy.size.width - spacing * 23) / 24, 0)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<24, id: \.self) { hour in
                        let tokens = hours[hour] ?? 0
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tokens > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            // An hour with any work at all keeps a visible
                            // stub, so a quiet hour reads as quiet rather than
                            // as missing.
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: tokens > 0
                                    ? max((proxy.size.height - 1) * CGFloat(tokens) / CGFloat(peak), 3)
                                    : 2
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SpendFormat.hour(hour))
                            .accessibilityValue(SpendFormat.tokens(tokens))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
                .overlay {
                    ChartHoverOverlay(samples: (0..<24).map { hour in
                        .init(
                            x: width / 2 + CGFloat(hour) * (width + spacing),
                            title: SpendFormat.hour(hour),
                            tokens: hours[hour] ?? 0
                        )
                    })
                }
            }

            HStack {
                Text(SpendFormat.hour(0))
                Spacer(minLength: 0)
                Text(SpendFormat.hour(12))
                Spacer(minLength: 0)
                Text(SpendFormat.hour(23))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Tokens per hour"))
    }
}

/// Fresh input, cache written, cache read, output — the four kinds of token,
/// with each one's share of the whole.
///
/// **The split is the point, not the total.** These four are priced an order of
/// magnitude apart — a cache read costs a tenth of fresh input on most price
/// lists — so a bill that looks surprising next to a token count is usually
/// explained here and nowhere else.
///
/// The agent and combined panes have no per-model money and pass no `cost`, so
/// they draw tokens alone; a model's drill-down passes its own `costBreakdown`
/// and gets the amount beside each kind. That is the model's money only — never
/// a day's or an agent's blended rate spread across it.
struct TokenKindBreakdown: View {
    let tally: TokenTally
    /// The priced subset of these kinds, where there is one. Nil leaves the
    /// rows as tokens, which is what the agent and combined panes show.
    var cost: TokenCost? = nil
    /// Tokens behind these amounts that had no price. A positive count puts a
    /// `*` on each kind's amount, tying it to the note under the rows.
    var unpriced: Int = 0

    var body: some View {
        let total = max(tally.total, 1)

        return VStack(spacing: 0) {
            ForEach(Array(Self.rows(tally, cost: cost).enumerated()), id: \.offset) { index, row in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(row.label, subtitle: row.note) {
                    HStack(spacing: 10) {
                        ShareBar(share: Double(row.tokens) / Double(total))
                            .frame(width: 64, height: 6)

                        Text(String.localized("\(TokenCount.short(row.tokens)) tokens"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            // One line, always. Grouped by ten thousands
                            // these read "1246万 tokens", which is wider
                            // than the English it was measured against and
                            // was wrapping under its own bar.
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .help(SpendFormat.tokens(row.tokens))

                        if row.cost != nil {
                            CostText(cost: row.cost, unpriced: unpriced)
                                .font(.system(size: 12))
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private struct Row {
        let label: String
        let note: String
        let tokens: Int
        let cost: Double?
    }

    private static func rows(_ tally: TokenTally, cost: TokenCost?) -> [Row] {
        [
            Row(label: .localized("Input"), note: .localized("Sent fresh, not served from the cache."), tokens: tally.input, cost: cost?.input),
            Row(label: .localized("Cache write"), note: .localized("Put into the prompt cache to be re-used."), tokens: tally.cacheWrite, cost: cost?.cacheWrite),
            Row(label: .localized("Cache read"), note: .localized("Served from the cache, and priced far lower."), tokens: tally.cacheRead, cost: cost?.cacheRead),
            Row(label: .localized("Output"), note: .localized("Written back by the model."), tokens: tally.output, cost: cost?.output),
        ]
    }
}

/// The one short line that explains a `*` beside a partial amount. The count
/// itself lives in the help tag rather than in the sentence.
struct SpendPartialNote: View {
    let tokens: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "*")
            Text(localized: "Excludes unpriced tokens.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .help(SpendFormat.unpriced(tokens))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// An estimated amount, or the mark that says there isn't one.
///
/// Shared by a model's agent rows and its day table so nil, a real zero and a
/// partial estimate are drawn the same way in both. A positive `unpriced`
/// count appends `*` and puts the exact amount and the excluded tokens in the
/// help tag and the accessibility label — VoiceOver cannot read the `*`.
struct CostText: View {
    let cost: Double?
    var unpriced: Int = 0

    var body: some View {
        Group {
            if let cost {
                Text(verbatim: unpriced > 0 ? "\(SpendFormat.money(cost))*" : SpendFormat.money(cost))
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(helpText(cost))
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    /// The exact amount, and where the row is partial, the tokens it leaves out.
    private func helpText(_ cost: Double) -> String {
        guard unpriced > 0 else { return SpendFormat.moneyExact(cost) }
        return "\(SpendFormat.moneyExact(cost)) · \(SpendFormat.unpriced(unpriced))"
    }

    private var accessibilityText: String {
        guard let cost else { return String.localized("Estimate unavailable") }
        guard unpriced > 0 else { return SpendFormat.money(cost) }
        return "\(SpendFormat.money(cost)), \(SpendFormat.unpriced(unpriced))"
    }
}

/// A small label above its figure. Used for the captions under a total.
struct SpendCaption: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
        }
    }
}

/// The hours, in the words each language actually uses for one.
///
/// **Not `.dateTime.hour()`.** It is locale-aware and still wrong here: for
/// Chinese it produces the written "10时" where an hour spoken aloud is
/// "10 点". A key per language says it the way that language says it, and the
/// number is interpolated as a string so the entry stays `%@`.
enum SpendFormat {
    /// A hover can be read without the surrounding span picker, including
    /// across New Year, so unlike the axis it includes the year.
    static func chartDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(LocalizationSource.locale))
    }

    static func hour(_ hour: Int) -> String {
        .localized("\("\(hour)") o'clock")
    }

    /// The exact count, grouped the reader's way and in the app's language.
    ///
    /// For a help tag: `TokenCount.short` rounds by ten thousands, and a reader
    /// checking one figure wants every digit rather than a short form that
    /// hides the difference between two nearby numbers.
    static func tokens(_ count: Int) -> String {
        let number = count.formatted(.number.locale(LocalizationSource.locale))
        return String.localized("\(number) tokens")
    }

    /// How many of a model's tokens had no price behind the estimate. The same
    /// phrasing as the line under the total, for a row's help tag.
    static func unpriced(_ count: Int) -> String {
        let number = count.formatted(.number.locale(LocalizationSource.locale))
        return String.localized("\(number) tokens unpriced")
    }

    /// A dollar figure, in dollars whatever the reader's currency is, at two
    /// places — or none once it is over a thousand.
    ///
    /// **A positive amount too small to show is still not free.** Rounded to
    /// cents it would print `$0.00`, which reads as nothing spent; it says
    /// "less than a cent" instead. A real zero still prints `$0.00`, because
    /// that one is a measurement.
    static func money(_ amount: Double, locale: Locale = LocalizationSource.locale) -> String {
        if amount > 0, amount < 0.01 {
            let cent = 0.01.formatted(
                .currency(code: "USD")
                    .precision(.fractionLength(2))
                    .locale(locale)
            )
            return String.localized("< \(cent)")
        }

        return amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(amount >= 1000 ? 0 : 2))
                .locale(locale)
        )
    }

    /// The same figure as a help tag, where the visible rounding hides the
    /// digits being checked.
    ///
    /// **Significant digits, not a fixed count.** A fixed six places turns
    /// anything below a millionth into `$0.000000`, contradicting the visible
    /// "less than a cent"; and a fixed count also drops a large amount's real
    /// fraction. Significant digits keep a tiny positive amount visible and a
    /// large one exact.
    static func moneyExact(_ amount: Double, locale: Locale = LocalizationSource.locale) -> String {
        // A real zero keeps the same two places the page shows it with.
        guard amount != 0 else { return money(amount, locale: locale) }

        return amount.formatted(
            .currency(code: "USD")
                .precision(.significantDigits(1...15))
                .locale(locale)
        )
    }
}

/// The row counts a long table may be cut into. Ten by default: a table long
/// enough to scroll past is a table nobody reads to the end of.
enum SpendPaging {
    static let sizes = [10, 20, 30, 50]
}

/// The foot of a paged table: the page size, where in the list the reader is,
/// and the two arrows.
///
/// Shared by the day table, the session list and one model's daily detail — the
/// three are the same control, and a second copy is a second place for the
/// range arithmetic to disagree.
struct SpendPageFooter: View {
    let rows: Int
    @Binding var pageSize: Int
    @Binding var page: Int

    var body: some View {
        let pages = max((rows + pageSize - 1) / pageSize, 1)
        // Clamped rather than trusted: the span and the sort can both shorten
        // the table under a page that is already on screen.
        let current = min(max(page, 0), pages - 1)

        HStack(spacing: 10) {
            Picker("", selection: $pageSize) {
                ForEach(SpendPaging.sizes, id: \.self) { size in
                    // Interpolated as a string: an `Int` in a key produces
                    // `%lld`, which will not match a `%@` entry.
                    Text(String.localized("\("\(size)") per page")).tag(size)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(String.localized("Rows per page"))
            // A shorter page does not mean the same rows: going back to the
            // first one is the only answer that is the same every time.
            .onChange(of: pageSize) { _, _ in page = 0 }

            Spacer(minLength: 8)

            Text(String.localized("\("\(current * pageSize + 1)")–\("\(min((current + 1) * pageSize, rows))") of \("\(rows)")"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // An icon-only control still needs a name for VoiceOver and for
            // keyboard access, so the arrow carries a `Label` whose text is
            // only hidden, not dropped.
            Button {
                page = max(current - 1, 0)
            } label: {
                Label(String.localized("Previous page"), systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(current == 0)

            Button {
                page = min(current + 1, pages - 1)
            } label: {
                Label(String.localized("Next page"), systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(current >= pages - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
