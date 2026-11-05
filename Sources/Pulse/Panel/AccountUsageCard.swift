// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// A provider's history: what has been spent, and what it would have cost.
///
/// Settings-only on purpose. The rail answers "how much of my limit is left",
/// which is a glance; this answers "how heavily am I using this", which is a
/// sit-down — and it is read off a few hundred megabytes of transcripts rather
/// than a live endpoint.
///
/// Laid out as a grid of figures rather than a list of rows. Six numbers in a
/// settings list is six lines to read in order; the same six in a grid can be
/// taken in at once, which is what this pane is actually for.
struct AccountUsageCard: View {
    let provider: Provider
    let ledger: UsageLedger
    /// Codex only, and only when its app server answered.
    var credits: CodexAccountUsage?
    var isReading = false

    /// Roughly a month, which is the span most of the figures cover.
    private static let span = 31

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localized: "Usage history")
                        .font(.system(size: 13, weight: .semibold))
                    if isReading {
                        ProgressView().controlSize(.small)
                        Text(localized: "Reading…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 0) {
                    if let credits, credits.availableResetCredits > 0 || credits.nextExpiringCredit != nil {
                        resetCredits(credits)
                        Divider()
                    }

                    figures

                    // From the first day, as the panel's detailed card draws
                    // it: one bar at the end of the month still says when
                    // the use was, which the figures above do not.
                    DailyTokensChart(days: ledger.recent(Self.span), slots: Self.span)
                        .frame(height: 58)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    if let credits, credits.lifetimeTokens > ledger.allTime.tokens {
                        Divider()
                        line(
                            String.localized("Account total"),
                            String.localized("\(TokenCount.short(credits.lifetimeTokens)) tokens")
                        )
                        .font(.system(size: 11))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .usageCard()

                if ledger.hasPartialCounts {
                    Text(localized: "Counts may be incomplete.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                footnote
            }

            // **A card of its own.** The table is about models, not days, and
            // under the chart it read as more of the same history.
            if !modelRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized: "Models")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.leading, 4)

                    modelTable
                        .usageCard()

                    if let tableNote {
                        Text(tableNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: - Header

    /// The one-off credits that clear a rate limit early — the reason to open
    /// this pane before a long session rather than after one, so it leads.
    private func resetCredits(_ credits: CodexAccountUsage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized: "Limit reset credits")
                    .font(.system(size: 13, weight: .semibold))

                if let expiry = expiry(credits) {
                    Text(expiry)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text(
                credits.availableResetCredits == 1
                    ? String.localized("1 available")
                    : String.localized("\("\(credits.availableResetCredits)") available")
            )
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(credits.availableResetCredits > 0 ? .primary : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func expiry(_ credits: CodexAccountUsage) -> String? {
        guard
            let expires = credits.nextExpiringCredit?.expiresAt,
            expires > Date(),
            let remaining = Self.remainingFormatter.string(from: Date(), to: expires)
        else { return nil }

        return String.localized("Next expires in \(remaining)")
    }

    // MARK: - Figures

    /// Four spans, each answering both halves of the same question at once.
    ///
    /// The money and the tokens for one span used to sit in separate cells,
    /// which made them look like separate facts and left the reader pairing
    /// them up by eye. They are one fact: what went through, and what it was
    /// worth.
    private var figures: some View {
        let recent = ledger.total(overLast: Self.span)
        let busiest = ledger.busiestDay(overLast: Self.span)
        let all = ledger.allTime

        return Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 16) {
            GridRow {
                figure(String.localized("Today"),
                       cost: ledger.today.map { UsageLedger.shownCost($0.cost, tokens: $0.tokens, unpriced: $0.unpricedTokens) } ?? 0,
                       tokens: ledger.today?.tokens ?? 0)
                figure(String.localized("Last 31 days"),
                       cost: UsageLedger.shownCost(recent.cost, tokens: recent.tokens, unpriced: recent.unpriced),
                       tokens: recent.tokens)
            }
            GridRow {
                figure(String.localized("Busiest day"),
                       cost: busiest.map { UsageLedger.shownCost($0.cost, tokens: $0.tokens, unpriced: $0.unpricedTokens) } ?? 0,
                       tokens: busiest?.tokens ?? 0)
                // **"All time" is only true of a ledger that goes back.** A
                // provider's statistics are asked for a fixed window, so all
                // time and the last month are the same sum — one figure
                // printed twice, under a label claiming a lifetime Pulse does
                // not have. A shorter span is something the window can answer.
                if ledger.origin == .localTranscripts {
                    figure(String.localized("All time"),
                           cost: UsageLedger.shownCost(all.cost, tokens: all.tokens, unpriced: all.unpriced),
                           tokens: all.tokens)
                } else {
                    let week = ledger.total(overLast: 7)
                    figure(String.localized("Last 7 days"),
                           cost: UsageLedger.shownCost(week.cost, tokens: week.tokens, unpriced: week.unpriced),
                           tokens: week.tokens)
                }
            }
        }
        .padding(16)
    }

    /// The money is the big figure where there is money, and the tokens are
    /// where there isn't.
    ///
    /// **Not a zero.** A provider's own statistics give one token total per
    /// model, which no price list can turn into a cost — and `Self.money(0)`
    /// renders a confident "$0.00" for work that certainly cost something.
    /// The figure that is actually known takes the top line instead.
    private func figure(_ label: String, cost: Double?, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Money where there is money: this Mac's logs priced at API rates,
            // or a provider's own log of what it charged.
            if ledger.origin == .localTranscripts || ledger.origin == .providerLogs {
                // None of it priced: a dash, as the Token spend pane draws it.
                Text(verbatim: cost.map { Self.money($0, currency: ledger.currency, isCharged: ledger.origin == .providerLogs) } ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()

                Text(String.localized("\(TokenCount.short(tokens)) tokens"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(String.localized("\(TokenCount.short(tokens)) tokens"))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Models

    /// One model's line in the table: its share of the month's tokens, its
    /// cache hit rate over the same month, and its speed and first-token wait
    /// over the last day. A figure the records cannot give is nil.
    private struct ModelRow: Identifiable {
        let name: String
        let share: Double?
        let cacheRate: Double?
        let speed: Double?
        let firstToken: TimeInterval?
        var id: String { name }
    }

    private var speeds: [UsageLedger.ModelSpeed] {
        ledger.outputSpeedsByModel(since: Date().addingTimeInterval(-UsageLedger.speedSpan))
    }

    /// Every model with tokens this month, most first, and any timed in the
    /// last day that somehow has none.
    private var modelRows: [ModelRow] {
        let rates = Dictionary(ledger.cacheHitRatesByModel(overLast: Self.span).map { ($0.name, $0.rate) }) { first, _ in first }
        let timed = Dictionary(speeds.map { ($0.name, $0) }) { first, _ in first }
        let shares = ledger.modelShares(overLast: Self.span)
        var rows = shares.map {
            ModelRow(name: $0.name, share: $0.share, cacheRate: rates[$0.name],
                     speed: timed[$0.name]?.tokensPerSecond, firstToken: timed[$0.name]?.firstToken)
        }
        let listed = Set(shares.map(\.name))
        rows += speeds.filter { !listed.contains($0.name) }.map {
            ModelRow(name: $0.name, share: nil, cacheRate: rates[$0.name], speed: $0.tokensPerSecond, firstToken: $0.firstToken)
        }
        return rows
    }

    /// The readers that time replies (`ReplyTiming`).
    private static func timesReplies(_ provider: Provider) -> Bool {
        provider == .claudeCode || provider == .codex
    }

    /// **One table, not a section per measure.** Share, cache hit rate and
    /// speed are all facts about a model; stacked as three lists they named
    /// every model three times, each list under its own paragraph. A column
    /// with nothing in it for any model is left out rather than filled with
    /// dashes, and the explanations sit under the card with the others.
    private var modelTable: some View {
        let rows = modelRows
        let showsCache = rows.contains { $0.cacheRate != nil }
        let showsSpeed = rows.contains { $0.speed != nil }
        let showsWait = rows.contains { $0.firstToken != nil }
        let columns = 2 + (showsCache ? 1 : 0) + (showsSpeed ? 1 : 0) + (showsWait ? 1 : 0)

        return Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 7) {
            GridRow {
                // The card is titled for it; the names need no heading.
                Text(verbatim: "")
                    .gridColumnAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(localized: "Share")
                if showsCache { Text(localized: "Cache hit") }
                if showsSpeed { Text(localized: "Tokens/s") }
                if showsWait { Text(localized: "First token") }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Divider().gridCellColumns(columns)

            ForEach(rows) { row in
                GridRow {
                    Text(verbatim: row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    cell(row.share.map(Self.percent))
                    if showsCache { cell(row.cacheRate.map(Self.percent)) }
                    if showsSpeed { cell(row.speed.map(Self.speed)) }
                    if showsWait { cell(row.firstToken.map(Self.seconds)) }
                }
                .font(.system(size: 12))
            }

            // The account's own rate, which is not the average of the lines
            // above: each model weighs what it read.
            if showsCache, rows.count > 1, let overall = ledger.cacheHitRate(overLast: Self.span) {
                Divider().gridCellColumns(columns)
                GridRow {
                    Text(localized: "All models")
                    Text(verbatim: "")
                    cell(Self.percent(overall))
                    if showsSpeed { Text(verbatim: "") }
                    if showsWait { Text(verbatim: "") }
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A figure, or a faint dash where this model has none.
    private func cell(_ text: String?) -> some View {
        Text(verbatim: text ?? "–")
            .monospacedDigit()
            .foregroundStyle(text == nil ? .tertiary : .primary)
    }

    private static func speed(_ tokensPerSecond: Double) -> String {
        tokensPerSecond.formatted(.number.precision(.fractionLength(0)))
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String.localized("\(value.formatted(.number.precision(.fractionLength(1)))) s")
    }

    /// What the table's columns measure and over what span — said once, under
    /// the card, in place of a paragraph under each list.
    private var tableNote: String? {
        guard !modelRows.isEmpty else { return nil }
        guard Self.timesReplies(provider) else {
            return String.localized("Share and cache hit cover the last 31 days.")
        }
        var sentences = [String.localized("Share and cache hit cover the last 31 days; tokens per second only the last 24 hours, from sending a request to the end of its reply.")]
        if speeds.isEmpty {
            sentences.append(String.localized("Too few replies in the last 24 hours to time."))
        } else if provider == .codex {
            sentences.append(String.localized("First token is Codex's own measure of how long a turn waited for it."))
        } else {
            sentences.append(String.localized("Claude Code doesn't record when the first token arrived, so its wait isn't shown."))
        }
        // Chinese and Japanese run sentences together; the rest put a space.
        let language = LocalizationSource.locale.language.languageCode?.identifier
        let note = sentences.joined(separator: language == "zh" || language == "ja" ? "" : " ")
        return note
    }

    private static func percent(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    /// Where the money comes from, said plainly. It would be easy to read
    /// these as a bill; they are not one, and the card shouldn't let anyone
    /// believe otherwise.
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            if ledger.origin == .providerStatistics {
                // A different provenance needs different words: this one is
                // the account's, not this Mac's, and it carries no money.
                Text(localized: "Reported by \(provider.displayName) for the whole account, so it covers every machine you use it on. It counts tokens only — the figures behind it cannot be turned into a cost.")
            } else if ledger.origin == .providerLogs, provider == .deepSeek {
                // Day by day, not request by request, and Pulse asks for the
                // console's own "last 30 days".
                Text(localized: "From \(provider.displayName)'s console for the whole account — every key and every machine — with what was charged, day by day. Pulse reads the last 30 days.")
            } else if ledger.origin == .providerLogs {
                // The account's own log, and the money is what was charged —
                // the one history here that is a bill rather than an estimate.
                Text(localized: "From \(provider.displayName)'s request log for the whole account — every machine and every app that uses it — with what each request was charged. The log keeps 30 days.")
            } else {
                Text(localized: "Counted from this Mac's \(provider.displayName) logs and priced at the published API rates from models.dev. Your plan is a subscription, so this is what the same work would cost through the API — not what you were charged.")
            }

            if !ledger.unpricedModels.isEmpty, ledger.origin == .localTranscripts {
                Text(String.localized("No published price for \(ledger.unpricedModels.joined(separator: ", ")), so those tokens are counted but not costed."))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    // MARK: - Formatting

    /// A day's or a period's money. **An estimate is converted** — no
    /// `currency`, or dollars from the price lists — into the currency chosen
    /// in Settings (`Money.estimate`). **What a console charged is not**: a
    /// ledger whose origin is the provider's own logs passes `isCharged`, and
    /// its figure is drawn in the currency the console gave (DeepSeek's yuan).
    static func money(_ amount: Double, currency: String? = nil, isCharged: Bool = false) -> String {
        guard isCharged || (currency != nil && currency != "USD") else { return Money.estimate(amount) }
        return Money.format(amount, code: currency ?? "USD")
    }

    /// Built per call rather than kept around: it has to follow the language
    /// the user picked in settings, which can change while the window is open.
    private static var remainingFormatter: DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.calendar = {
            var calendar = Calendar.current
            calendar.locale = LocalizationSource.locale
            return calendar
        }()
        return formatter
    }
}

private extension View {
    /// The settings cards' own surface: the window's background, rounded,
    /// with a hairline.
    func usageCard() -> some View {
        background(.background)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Daily totals as bars, oldest on the left.
///
/// **Sized for the whole span, not for the days on record** — the same rule
/// as the panel card's chart. A history two days old, divided across the
/// width, drew two blocks each half the card wide; it now draws two bars at
/// the left that the following days join.
struct DailyTokensChart: View {
    let days: [LedgerDay]
    let slots: Int

    var body: some View {
        GeometryReader { proxy in
            let peak = max(days.map(\.tokens).max() ?? 1, 1)
            let count = max(days.count, slots, 1)
            let spacing = max(proxy.size.width / CGFloat(count) * 0.22, 2)
            let width = max(
                (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count),
                1
            )

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: min(width, 4) / 2, style: .continuous)
                        .fill(day.tokens > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        // A day with any work at all keeps a visible stub, so a
                        // quiet day reads as quiet rather than as missing.
                        .frame(
                            width: width,
                            height: day.tokens > 0
                                ? max(proxy.size.height * CGFloat(day.tokens) / CGFloat(peak), 4)
                                : 2
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SpendFormat.chartDate(day.date))
                        .accessibilityValue(SpendFormat.tokens(day.tokens))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .overlay {
                ChartHoverOverlay(samples: days.enumerated().map { index, day in
                    .init(
                        x: width / 2 + CGFloat(index) * (width + spacing),
                        title: SpendFormat.chartDate(day.date),
                        tokens: day.tokens
                    )
                })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Tokens per day"))
    }
}

enum TokenCount {
    /// "5.9B", "119M" — or "4.19亿", "4764万" where numbers are grouped by ten
    /// thousands. The scale is the point, not the digits.
    static func short(_ tokens: Int) -> String {
        short(tokens, units: LocalizationSource.myriadUnits)
    }

    /// The same formatting with the units supplied. Not `private` so
    /// `MyriadUnitsTests` can drive it without setting the app's language; do
    /// not tidy it back.
    static func short(_ tokens: Int, units: (tenThousand: String, hundredMillion: String)?) -> String {
        let (number, unit) = parts(tokens, units: units)
        return number + unit
    }

    /// The same figure as `short`, split at the unit: ("4.19", "亿"), ("5.9", "B"),
    /// ("812", ""). The recap cards draw the number large and the unit small,
    /// so they need the two apart — and take them from here so there is one
    /// rule for where 万 and 亿 begin, not two.
    static func parts(
        _ tokens: Int,
        units: (tenThousand: String, hundredMillion: String)?
    ) -> (number: String, unit: String) {
        if let units { return grouped(tokens, units) }

        let value = Double(tokens)
        switch value {
        case 1_000_000_000...: return (format(value / 1_000_000_000, decimals: value < 1e10 ? 1 : 0), "B")
        case 1_000_000...: return (format(value / 1_000_000, decimals: value < 1e7 ? 1 : 0), "M")
        case 1_000...: return (format(value / 1_000, decimals: value < 1e4 ? 1 : 0), "K")
        default: return ("\(tokens)", "")
        }
    }

    /// 万 is 10⁴ and 亿 is 10⁸, so the breaks fall in different places than
    /// thousands do — 419,000,000 is 4.19亿, not "419 million".
    ///
    /// The two characters are handed in rather than written here: the same
    /// arithmetic serves Japanese and Korean, which break at the same powers
    /// and spell them differently. See `LocalizationSource.myriadUnits`.
    private static func grouped(
        _ tokens: Int,
        _ units: (tenThousand: String, hundredMillion: String)
    ) -> (number: String, unit: String) {
        let value = Double(tokens)
        switch value {
        case 100_000_000...:
            let scaled = value / 100_000_000
            // Three significant figures, which is what "419M" carried.
            return (format(scaled, decimals: scaled < 10 ? 2 : (scaled < 100 ? 1 : 0)), units.hundredMillion)
        case 10_000...:
            let scaled = value / 10_000
            return (format(scaled, decimals: scaled < 10 ? 1 : 0), units.tenThousand)
        default:
            return ("\(tokens)", "")
        }
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", value)
        guard text.contains(".") else { return text }
        // "4.10亿" and "4.00亿" both read as a mistake; trim what adds nothing.
        return text
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
