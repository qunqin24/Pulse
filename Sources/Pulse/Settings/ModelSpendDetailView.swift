// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// One model's usage, opened from the model list.
///
/// **In place, not a new window.** It is drawn inside the same settings pane as
/// the agent view, so the span picker above it keeps working and the reader
/// never leaves the page to find out where one model's tokens went.
///
/// **The money is an API estimate, and only where a price exists.** It is
/// priced from this model's own raw ids at models.dev rates — never a day's or
/// an agent's blended rate spread across it. Where none of the tokens could be
/// priced the figure is absent rather than `$0.00`; where only some could, the
/// total is marked partial and says how many tokens were left out. A category
/// the summary could not fill in says so rather than showing a zero.
///
/// The empty case belongs to `TokenSpendView`: it draws the model's name and
/// "nothing in this span" and only then builds this, so there is no second
/// empty state here.
struct ModelSpendDetailView: View {
    let model: ModelSpendSummary

    /// Which column the day table is sorted by. Its own state, like the agent
    /// view's, because it is a way of reading the table in front of you rather
    /// than a preference about the app.
    @State private var sort = ModelSpendSummary.DayColumn.date
    @State private var ascending = false
    @State private var pageSize = 10
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            total
            kinds
            hours
            if !model.agents.isEmpty { agents }
            daily
            footnote
        }
    }

    // MARK: - The figure

    private var total: some View {
        SettingsGroup(String.localized("Total")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let cost = model.cost {
                        Text(SpendFormat.money(cost))
                            .font(.system(size: 28, weight: .semibold))
                            .monospacedDigit()
                            .help(SpendFormat.moneyExact(cost))

                        Text(estimateLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        // Nothing could be priced: no rate for any raw id, or
                        // the split the rates need was incomplete. A zero here
                        // would read as a measurement, and there was none.
                        Text(localized: "Estimate unavailable")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String.localized("\(TokenCount.short(model.tokens)) tokens"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help(SpendFormat.tokens(model.tokens))

                    // The estimate covers only the priced part; the reader is
                    // told how much was left out rather than left to hover.
                    if model.cost != nil, model.unpricedTokens > 0 {
                        Text(String.localized("\(TokenCount.short(model.unpricedTokens)) tokens unpriced"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .help(SpendFormat.tokens(model.unpricedTokens))
                    }
                }

                // A single day has no trend to draw; the hourly profile below
                // is the shape worth seeing there.
                if model.days.count > 1 {
                    SpendBarChart(bars: model.days.map { .init(date: $0.date, tokens: $0.tokens) })
                        .frame(height: 78)
                }

                HStack(spacing: 16) {
                    SpendCaption(
                        String.localized("Active days"),
                        String.localized("\("\(model.activeDays)") of \("\(max(model.days.count, 1))")")
                    )

                    if let busiest = model.busiestDay, busiest.tokens > 0 {
                        SpendCaption(
                            String.localized("Busiest"),
                            "\(Self.shortDate(busiest.date)) · \(TokenCount.short(busiest.tokens))"
                        )
                        .help(SpendFormat.tokens(busiest.tokens))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// Whether the figure is the model's whole cost or only its priced part.
    private var estimateLabel: String {
        // A partial estimate either because some tokens had no price, or
        // because the source could only attest to part of its own counts.
        model.unpricedTokens > 0 || model.hasPartialCounts
            ? String.localized("Partial estimate")
            : String.localized("API estimate")
    }

    // MARK: - What kind of token

    /// **Not the agent's overall split.** This is the model's own tally, so a
    /// slice of one model is never dressed up as the whole agent's work. The
    /// amounts beside the kinds are the model's own priced subset, and a short
    /// line says when some of it could not be priced.
    private var kinds: some View {
        SettingsGroup(String.localized("By kind")) {
            VStack(spacing: 0) {
                if let tally = model.tally {
                    TokenKindBreakdown(
                        tally: tally,
                        cost: model.costBreakdown,
                        unpriced: model.unpricedTokens
                    )
                } else {
                    SettingsRow(String.localized("Token breakdown unavailable.")) {
                        EmptyView()
                    }
                }

                // The `*` marks in the agent and day rows are explained here,
                // where the amounts they belong to sit.
                if model.cost != nil, model.unpricedTokens > 0 {
                    SettingsRowDivider()
                    SpendPartialNote(tokens: model.unpricedTokens)
                }
            }
        }
    }

    // MARK: - When

    private var hours: some View {
        SettingsGroup(String.localized("By hour")) {
            // `hours` is already nil unless the buckets reconciled, and an
            // aggregate-timed ledger keeps no buckets at all — both mean the
            // profile would be a partial day, so the unavailable line stands.
            if !model.hasAggregateTiming,
               let value = model.hours, value.values.contains(where: { $0 > 0 }) {
                HourProfile(hours: value)
                    .frame(height: 66)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                SettingsRow(String.localized("Hourly detail unavailable.")) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Where it went

    private var agents: some View {
        SettingsGroup(String.localized("By agent")) {
            ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, row in
                if index > 0 { SettingsRowDivider() }

                SettingsRow(
                    row.agent.displayName,
                    subtitle: String.localized("\(TokenCount.short(row.tokens)) tokens"),
                    icon: row.agent.iconResource
                ) {
                    HStack(spacing: 10) {
                        ShareBar(share: model.tokens > 0
                            ? Double(row.tokens) / Double(model.tokens)
                            : 0)
                            .frame(width: 64, height: 6)

                        CostText(cost: row.cost, unpriced: row.unpricedTokens)
                            .font(.system(size: 12))
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                // The row's own exact token count. The amount's help tag is a
                // descendant, so hovering the amount still shows its own.
                .help(SpendFormat.tokens(row.tokens))
            }
        }
    }

    // MARK: - Day by day

    /// Every day with work on it, with the split, the total and the estimate
    /// beside it. The quiet days the chart keeps are rows nobody reads past, so
    /// they are left out here. Ordering is `ModelSpendSummary`'s, where a nil
    /// cell sorts last and a real zero sorts as a zero.
    private var daily: some View {
        let rows = ModelSpendSummary.sorted(
            model.days.filter { $0.tokens > 0 }, by: sort, ascending: ascending
        )
        let pages = max((rows.count + pageSize - 1) / pageSize, 1)
        let current = min(max(page, 0), pages - 1)
        let shown = Array(rows.dropFirst(current * pageSize).prefix(pageSize))

        return SettingsGroup(String.localized("Day by day")) {
            VStack(spacing: 0) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                    GridRow {
                        ForEach(ModelSpendSummary.DayColumn.allCases) { column in
                            header(column)
                        }
                    }
                    .padding(.vertical, 8)

                    ForEach(shown) { day in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            ForEach(ModelSpendSummary.DayColumn.allCases) { column in
                                cell(day, column: column)
                            }
                        }
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .padding(.vertical, 5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if rows.count > (SpendPaging.sizes.first ?? 10) {
                    SettingsRowDivider()
                    SpendPageFooter(rows: rows.count, pageSize: $pageSize, page: $page)
                }
            }
        }
    }

    /// Clicking a column sorts by it; clicking the sorted one turns it around.
    private func header(_ column: ModelSpendSummary.DayColumn) -> some View {
        Button {
            page = 0
            if sort == column {
                ascending.toggle()
            } else {
                sort = column
                // A new column starts at the end people look at first: the
                // most recent day, or the largest figure.
                ascending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(column.title)
                if sort == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(size: 10, weight: sort == column ? .semibold : .regular))
            .foregroundStyle(sort == column ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: column == .date ? .leading : .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// One cell, by column, so the row and the header cannot get out of step.
    @ViewBuilder
    private func cell(_ day: ModelSpendSummary.Day, column: ModelSpendSummary.DayColumn) -> some View {
        switch column {
        case .date:
            Text(Self.shortDate(day.date))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .input:
            tokenCell(day.tally?.input)
        case .output:
            tokenCell(day.tally?.output)
        case .cacheRead:
            tokenCell(day.tally?.cacheRead)
        case .cacheWrite:
            tokenCell(day.tally?.cacheWrite)
        case .total:
            tokenCell(day.tokens)
        case .cost:
            CostText(cost: day.cost, unpriced: day.unpricedTokens)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// A known count shows the short form, with the exact number in its help
    /// tag; a missing one shows an em dash and has no tag.
    private func tokenCell(_ tokens: Int?) -> some View {
        Group {
            if let tokens {
                Text(tokens > 0 ? TokenCount.short(tokens) : "0")
                    .foregroundStyle(tokens > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .help(SpendFormat.tokens(tokens))
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - What the figures are not

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The same warning the combined page carries: the money is a
            // translation of records at published rates, not a bill. Generic
            // because an imported export can cover more than this Mac.
            Text(localized: "Usage records, estimated at models.dev API rates—not an actual bill.")

            // The same conditional note the combined page carries, for the same
            // reason: a source that can only attest to part of its counts makes
            // the model's totals the known subset.
            if model.hasPartialCounts {
                Text(localized: "Counts may be incomplete.")
            }

            // The same conditional note the combined page carries, for the same
            // reason: some of a model's records land on a session report date
            // and no hour.
            if model.hasAggregateTiming {
                Text(localized: "Some records use session report dates.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    // MARK: - Formatting

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }
}

/// The model day table's headings. The columns themselves live on
/// `ModelSpendSummary`; only the words belong to the settings layer.
extension ModelSpendSummary.DayColumn {
    var title: String {
        switch self {
        case .date: .localized("Date")
        case .input: .localized("Input")
        case .output: .localized("Output")
        // Short, because columns of Chinese headings in a settings pane are a
        // table that wraps.
        case .cacheRead: .localized("C. read")
        case .cacheWrite: .localized("C. write")
        case .total: .localized("Total")
        case .cost: .localized("Cost")
        }
    }
}
