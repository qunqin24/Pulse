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

    /// Roughly a month, which is the span most of the figures cover.
    private static let span = 31

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized: "Usage history")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                if let credits, credits.availableResetCredits > 0 || credits.nextExpiringCredit != nil {
                    resetCredits(credits)
                    Divider()
                }

                figures

                if ledger.days.count > 1 {
                    DailyTokensChart(days: ledger.recent(Self.span))
                        .frame(height: 58)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                Divider()

                summary
            }
            .background(.background)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            }

            footnote
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
                       cost: ledger.today?.cost ?? 0, tokens: ledger.today?.tokens ?? 0)
                figure(String.localized("Last 31 days"), cost: recent.cost, tokens: recent.tokens)
            }
            GridRow {
                figure(String.localized("Busiest day"),
                       cost: busiest?.cost ?? 0, tokens: busiest?.tokens ?? 0)
                figure(String.localized("All time"), cost: all.cost, tokens: all.tokens)
            }
        }
        .padding(16)
    }

    private func figure(_ label: String, cost: Double, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(Self.money(cost))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()

            Text(String.localized("\(TokenCount.short(tokens)) tokens"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary

    /// The two things that don't fit the grid: which model did the work, and —
    /// for Codex, which knows — what the account has done across every
    /// machine, not just this one.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let top = ledger.topModel(overLast: Self.span) {
                // The percent sign is baked into the value rather than left in
                // the key: a bare `%` next to a placeholder is a malformed
                // printf conversion, and Foundation formats these values.
                line(
                    String.localized("Top model"),
                    String.localized("\(top.name) · \("\(Int((top.share * 100).rounded()))%") of tokens")
                )
            }

            if let credits, credits.lifetimeTokens > ledger.allTime.tokens {
                line(
                    String.localized("Account total"),
                    String.localized("\(TokenCount.short(credits.lifetimeTokens)) tokens")
                )
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            Text(localized: "Counted from this Mac's \(provider.displayName) logs and priced at the published API rates from models.dev. Your plan is a subscription, so this is what the same work would cost through the API — not what you were charged.")

            if !ledger.unpricedModels.isEmpty {
                Text(String.localized("No published price for \(ledger.unpricedModels.joined(separator: ", ")), so those tokens are counted but not costed."))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    // MARK: - Formatting

    private static func money(_ amount: Double) -> String {
        // Both providers publish their rates in dollars, so the figure is in
        // dollars whatever the reader's own currency is — hence a fixed code
        // rather than the locale's.
        amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(amount >= 1000 ? 0 : 2))
                .locale(LocalizationSource.locale)
        )
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

/// Daily totals as bars, oldest on the left.
private struct DailyTokensChart: View {
    let days: [LedgerDay]

    var body: some View {
        GeometryReader { proxy in
            let peak = max(days.map(\.tokens).max() ?? 1, 1)
            let spacing = max(proxy.size.width / CGFloat(max(days.count, 1)) * 0.22, 2)
            let width = max(
                (proxy.size.width - spacing * CGFloat(max(days.count - 1, 0))) / CGFloat(max(days.count, 1)),
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
                        .help(Self.tooltip(day))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("Tokens per day"))
    }

    private static func tooltip(_ day: LedgerDay) -> String {
        let date = day.date.formatted(
            .dateTime.month(.abbreviated).day().locale(LocalizationSource.locale)
        )
        return "\(date) · \(TokenCount.short(day.tokens))"
    }
}

enum TokenCount {
    /// "5.9B", "119M" — or "4.19亿", "4764万" where numbers are grouped by ten
    /// thousands. The scale is the point, not the digits.
    static func short(_ tokens: Int) -> String {
        guard !LocalizationSource.groupsByTenThousands else { return grouped(tokens) }

        let value = Double(tokens)
        switch value {
        case 1_000_000_000...: return format(value / 1_000_000_000, decimals: value < 1e10 ? 1 : 0) + "B"
        case 1_000_000...: return format(value / 1_000_000, decimals: value < 1e7 ? 1 : 0) + "M"
        case 1_000...: return format(value / 1_000, decimals: value < 1e4 ? 1 : 0) + "K"
        default: return "\(tokens)"
        }
    }

    /// 万 is 10⁴ and 亿 is 10⁸, so the breaks fall in different places than
    /// thousands do — 419,000,000 is 4.19亿, not "419 million".
    private static func grouped(_ tokens: Int) -> String {
        let value = Double(tokens)
        switch value {
        case 100_000_000...:
            let scaled = value / 100_000_000
            // Three significant figures, which is what "419M" carried.
            return format(scaled, decimals: scaled < 10 ? 2 : (scaled < 100 ? 1 : 0)) + "亿"
        case 10_000...:
            let scaled = value / 10_000
            return format(scaled, decimals: scaled < 10 ? 1 : 0) + "万"
        default:
            return "\(tokens)"
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
