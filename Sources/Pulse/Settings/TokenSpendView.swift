import SwiftUI

/// What every coding agent on this Mac has cost, added up.
///
/// **Deliberately not the account card.** That one is per provider, opened
/// from that provider's own pane, and answers "how heavily am I using this".
/// This answers a question no pane could answer before, because its subject is
/// not a provider: *across everything I use, where did the work go.* The
/// figures here are sums the card cannot show and splits it has no room for —
/// a share per agent, a ranking per model — and none of it appears on the
/// rail, which is for what is left rather than for what is gone.
///
/// **Only sources that leave local records.** Money is reconstructed from the
/// records and exports Pulse reads at models.dev's published rates; a provider
/// that reports its own statistics instead gives one token total per model and
/// no money at all, and folding that into a combined cost would put a figure
/// on the total that half of it cannot carry. An export can cover more than
/// this Mac, which is why the prose names records rather than a machine.
struct TokenSpendView: View {
    let summary: SpendSummary
    /// The agent being looked at on its own, or nil for the combined view.
    @Binding var focus: SpendAgent?
    /// That agent's figures, worked out over the same span. Built by the same
    /// function as the combined one, from a dictionary of one — so the split
    /// and the whole cannot drift apart or be counted differently.
    let focused: SpendSummary
    /// The model being looked at on its own — a name, which is what the
    /// summary is keyed by — or nil for the list. Cleared by `SettingsView`
    /// when the agent changes: a model opened under one agent means nothing
    /// under another.
    @Binding var modelFocus: String?
    /// That model's figures, from the same ledgers and the same span, narrowed
    /// to the agent on screen first where there is one. Kept beside the agent's
    /// own summary for the same reason that one is kept beside the combined:
    /// both come out of one function, so they cannot count a span two ways.
    let modelSummary: ModelSpendSummary
    /// Sources that are present — installed, or captured/exported to a folder
    /// Pulse reads — but produced no token records.
    ///
    /// **Not a zero reading and not a login prompt.** These are named at the
    /// foot of the combined pane so "nothing here" can be told from "nothing
    /// was read", without pretending their silence is a measurement or asking
    /// the reader to set anything up. A source that reports money but no
    /// tokens is here too: it has no usage records to show.
    let noRecords: [SpendAgent]
    /// Whether any present source held history a reader could only partly
    /// decode. Shown as one short, generic sentence; the readers' own English
    /// diagnostics never reach the view.
    let hasReadLimitations: Bool
    @Binding var span: SpendSpan
    let isLoading: Bool
    let refresh: () -> Void

    /// Which column the day table is sorted by. Its own state rather than a
    /// setting: it is a way of reading the table in front of you, not a
    /// preference about the app.
    @State private var sort = DayColumn.date
    @State private var ascending = false
    /// How many rows a page holds, and which page is on screen. Ten by
    /// default: a table long enough to scroll past is a table nobody reads to
    /// the end of, and the span picker above is the coarse control.
    @State private var pageSize = 10
    @State private var page = 0
    /// The session list pages separately: it is hundreds of rows where the day
    /// table is tens, and a shared page number would jump both at once.
    @State private var sessionPageSize = 10
    @State private var sessionPage = 0
    /// Whether the model list is showing every model or just the first few.
    @State private var showAllModels = false

    /// Enough to see where the work goes without turning the pane into a
    /// table. The rest is in the ledger and nobody reads a fortieth row.
    private static let modelLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let modelFocus {
                modelHeader(modelFocus)
            } else if let focus {
                agentHeader(focus)
            }

            SettingsGroup(String.localized("Span")) {
                SettingsRow(
                    String.localized("Counting"),
                    subtitle: String.localized("Read from local records and exports, priced at models.dev's published rates.")
                ) {
                    HStack(spacing: 8) {
                        Picker("", selection: $span) {
                            ForEach(SpendSpan.allCases) { span in
                                Text(span.title).tag(span)
                            }
                        }
                        .labelsHidden()
                        // The picker's own title is empty and the row's label is
                        // to its left, which VoiceOver does not join to it.
                        .accessibilityLabel(String.localized("Counting"))
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)

                        Button(String.localized("Rescan")) { refresh() }
                            .disabled(isLoading)
                    }
                }
            }

            // **A partial read is stated, not hidden.** A source can hold
            // history this Mac cannot decode (a compressed transcript) while
            // other records read fine; without this line the readable subset
            // would look like the whole. One generic sentence, in every
            // sub-view, and no control attached.
            if hasReadLimitations {
                Text(localized: "Some compressed records could not be read.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            // The span picker stays in every view, so narrowing the window
            // while looking at one agent or one model does not throw the reader
            // back out.
            if let modelFocus {
                if modelSummary.isEmpty {
                    nothingForModel(modelFocus)
                } else {
                    ModelSpendDetailView(model: modelSummary)
                }
            } else if let focus {
                if focused.isEmpty {
                    nothingForAgent(focus)
                } else {
                    total(focused)
                    kinds(focused)
                    streaks(focused)
                    if span != .today { hourly(focused) }
                    if span != .today { daily(focused) }
                    if focused.months.count > 1 { monthly(focused) }
                    if !focused.models.isEmpty { models(focused).id("models") }
                    if !focused.projects.isEmpty { projects(focused) }
                    if !focused.sessions.isEmpty { sessions(focused) }
                    footnote(focused)
                }
            } else if summary.isEmpty {
                empty
            } else {
                total(summary)
                kinds(summary)
                streaks(summary)
                if span != .today { hourly(summary) }
                if span != .today { daily(summary) }
                if summary.months.count > 1 { monthly(summary) }
                agents
                // Even one model is an entry point now: tapping it opens that
                // model's own detail, which is the only place its split lives.
                if !summary.models.isEmpty { models(summary).id("models") }
                if !summary.projects.isEmpty { projects(summary) }
                if !summary.sessions.isEmpty { sessions(summary) }
                footnote(summary)
            }

            // **Only for the combined pane.** A source with no records is a
            // fact about the whole page; under one agent or one model it would
            // read as a per-agent absence the same list already shows.
            if modelFocus == nil, focus == nil, !noRecords.isEmpty {
                noRecordsGroup
            }
        }
    }

    // MARK: - Nothing read from a source

    /// The present-but-silent sources, named once at the foot of the page.
    ///
    /// Deliberately short: names only, no control and no explanation of how to
    /// make one produce records. A source that is absent entirely is not here —
    /// fifty-one empty rows would be worse than nothing.
    private var noRecordsGroup: some View {
        SettingsGroup(String.localized("No usage data read")) {
            SettingsRow(noRecords.map(\.displayName).joined(separator: " · ")) {
                EmptyView()
            }
        }
    }

    // MARK: - One agent

    /// The way back, and what is being looked at. A row rather than a bare
    /// button: this pane has no navigation stack of its own, so the only thing
    /// saying "you have gone one level in" is on screen here.
    private func agentHeader(_ agent: SpendAgent) -> some View {
        Button {
            focus = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(localized: "All agents")
                    .font(.system(size: 12))
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                if let icon = agent.iconResource { LobeIconView(resource: icon, size: 13) }
                Text(agent.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    private func nothingForAgent(_ agent: SpendAgent) -> some View {
        SettingsGroup(agent.displayName) {
            SettingsRow(
                String.localized("Nothing in this span"),
                subtitle: String.localized("Try a longer span, or rescan.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - One model

    /// The way back, and which model is being looked at. Where the model was
    /// opened from an agent's own list the back label is that agent, because
    /// that is the list it returns to; from the combined list it is all models.
    private func modelHeader(_ name: String) -> some View {
        let back = focus.map(\.displayName) ?? String.localized("All models")

        return Button {
            modelFocus = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(back)
                    .font(.system(size: 12))
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
    }

    private func nothingForModel(_ name: String) -> some View {
        SettingsGroup(name) {
            SettingsRow(
                String.localized("Nothing in this span"),
                subtitle: String.localized("Try a longer span, or rescan.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - Nothing to show

    private var empty: some View {
        SettingsGroup(String.localized("Total")) {
            SettingsRow(
                isLoading ? String.localized("Reading…") : String.localized("Nothing yet"),
                // **No agent is promised and none is promised absent.** The
                // page reads records and exports from a catalogue of sources,
                // and any of them can be the one that has nothing; naming one
                // here would be wrong for everyone else.
                subtitle: isLoading
                    ? String.localized("Going through local records and exports.")
                    : String.localized("No local records or exports have been found yet.")
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - The figure

    private func total(_ summary: SpendSummary) -> some View {
        SettingsGroup(focus == nil ? String.localized("Total") : String.localized("This agent")) {
            VStack(alignment: .leading, spacing: 10) {
                // **An hour profile is complete only when its hours are the
                // whole day.** Some records carry a session or report date and
                // no hour, so summing the quarter-hour buckets can fall short
                // of the total; drawing it anyway would present a partial day
                // as the day's shape.
                let hoursComplete = Self.hoursComplete(summary)
                // **No price is not a price of zero.** When every token in
                // scope is unpriced there is no money figure to show; a
                // `$0.00` would read as a real, very cheap measurement. A
                // genuine free rate keeps its own real zero.
                let noPriceAtAll = summary.tokens > 0 && summary.unpricedTokens == summary.tokens
                // The amount covers only the priced subset when some tokens
                // had no price, or when the source itself could only attest to
                // part of its counts. Either way the figure is a partial one
                // and says so; only the all-unpriced case is no figure at all.
                let partialEstimate = !noPriceAtAll
                    && (summary.unpricedTokens > 0 || summary.hasPartialCounts)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if noPriceAtAll {
                        Text(localized: "Estimate unavailable")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(SpendFormat.money(summary.cost))
                            .font(.system(size: 28, weight: .semibold))
                            .monospacedDigit()

                        if partialEstimate {
                            Text(localized: "Partial estimate")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(String.localized("\(TokenCount.short(summary.tokens)) tokens"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // **A day is not one bar.** Over any other span the bars are
                // days; over today there is only one of those, and the shape
                // worth seeing is the hours it was spread across.
                if span == .today {
                    if hoursComplete {
                        HourProfile(hours: summary.hours)
                            .frame(height: 78)
                    } else {
                        // The existing unavailable line, in place of a shape
                        // that would be only part of the day.
                        Text(localized: "Hourly detail unavailable.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if summary.days.count > 1 {
                    SpendBarChart(bars: summary.days.map { .init(date: $0.date, tokens: $0.tokens) })
                        .frame(height: 78)
                }

                HStack(spacing: 16) {
                    if span == .today {
                        // Both captions read the hour series, so both are
                        // withheld when it does not cover the day rather than
                        // report a partial figure as the whole.
                        if hoursComplete {
                            SpendCaption(
                                String.localized("Active hours"),
                                String.localized("\("\(summary.activeHours)") of \("24")")
                            )
                            if let hour = summary.peakHour {
                                // Its own label: "busiest" is a day over every
                                // other span and an hour over this one, and
                                // Chinese names each of those outright.
                                SpendCaption(
                                    String.localized("Busiest hour"),
                                    "\(SpendFormat.hour(hour)) · \(TokenCount.short(summary.hours[hour] ?? 0))"
                                )
                            }
                        }
                    } else {
                        // Days with work on them, not days in the span: the
                        // second is the picker's own setting read back.
                        SpendCaption(
                            String.localized("Active days"),
                            String.localized("\("\(summary.activeDays)") of \("\(max(summary.days.count, 1))")")
                        )

                        if let busiest = summary.busiestDay, busiest.tokens > 0 {
                            SpendCaption(
                                String.localized("Busiest"),
                                "\(Self.shortDate(busiest.date)) · \(TokenCount.short(busiest.tokens))"
                            )
                        }
                    }

                    if focus == nil, summary.agents.count > 1 {
                        SpendCaption(String.localized("Agents"), "\(summary.agents.count)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - What kind of token

    /// Fresh input, cache written, cache read, output.
    ///
    /// **The split is the point, not the total.** These four are priced an
    /// order of magnitude apart — a cache read costs a tenth of fresh input on
    /// most price lists — so a bill that looks surprising next to a token
    /// count is usually explained here and nowhere else. The rows themselves
    /// are shared with the model detail, which is why they take a bare tally.
    private func kinds(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By kind")) {
            // **A partial split is not four zeroes.** Where some tokens belong
            // to no kind — a bare or session total records the source never
            // broke down — the four kinds do not add up to the total, and
            // drawing the shortfall as a zero would read as a measurement of
            // "none". The existing unavailable line says what is true instead.
            if summary.tally.total == summary.tokens {
                TokenKindBreakdown(tally: summary.tally)
            } else {
                SettingsRow(String.localized("Token breakdown unavailable.")) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Day by day

    /// Every day in the span, with the split and the money beside it.
    ///
    /// **The rows are days with work on them**, not every day in the span: the
    /// chart above is the one that has to keep its gaps to stay a calendar,
    /// and a table of empty rows is a table you have to read past.
    private func daily(_ summary: SpendSummary) -> some View {
        let rows = SpendSummary.sorted(summary.days.filter { $0.tokens > 0 }, by: sort, ascending: ascending)
        let pages = max((rows.count + pageSize - 1) / pageSize, 1)
        // Clamped rather than trusted: the span and the sort can both shorten
        // the table under a page that is already on screen.
        let current = min(max(page, 0), pages - 1)
        let shown = Array(rows.dropFirst(current * pageSize).prefix(pageSize))

        return SettingsGroup(String.localized("Day by day")) {
            VStack(spacing: 0) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                    GridRow {
                        ForEach(DayColumn.allCases) { column in
                            header(column)
                        }
                    }
                    .padding(.vertical, 8)

                    ForEach(shown) { day in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            Text(Self.tableDate(day.date))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // **The kinds are shown only when they add up.** A
                            // day whose categories do not equal its own total
                            // has tokens outside the four kinds; the category
                            // cells go blank rather than draw a zero that was
                            // never measured. The total column is the day's
                            // own figure and always stands.
                            let complete = day.tally.total == day.tokens
                            cell(complete ? day.tally.input : nil)
                            cell(complete ? day.tally.output : nil)
                            cell(complete ? day.tally.cacheRead : nil)
                            cell(complete ? day.tally.cacheWrite : nil)
                            cell(day.tokens)
                            // **An all-unpriced day is not a free day.** The
                            // day's own money is a priced subset; when nothing
                            // in it had a price the cell shows the same
                            // unavailable mark a model's day would, not
                            // `$0.00`. A partial day keeps its amount with the
                            // `*` the footnote explains.
                            CostText(
                                cost: day.tokens > 0 && day.unpricedTokens == day.tokens ? nil : day.cost,
                                unpriced: day.unpricedTokens
                            )
                            .frame(maxWidth: .infinity, alignment: .trailing)
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
    private func header(_ column: DayColumn) -> some View {
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

    /// A known count shows the short form; an absent one — either a kind the
    /// day did not report, or a zero the store wrote — shows an em dash.
    private func cell(_ tokens: Int?) -> some View {
        Group {
            if let tokens, tokens > 0 {
                Text(TokenCount.short(tokens))
                    .foregroundStyle(AnyShapeStyle(.primary))
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(AnyShapeStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private static func tableDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(LocalizationSource.locale))
    }

    // MARK: - When

    /// The hours of the day, as a profile.
    ///
    /// Read off the ledger's quarter-hour buckets, which are the only place
    /// the time of day survives — a day has already thrown it away.
    private func hourly(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By hour")) {
            if Self.hoursComplete(summary) {
                HourProfile(hours: summary.hours)
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

    /// Whether the quarter-hour buckets account for every token in the span.
    ///
    /// A record with only session- or report-level timing contributes to the
    /// total and to no hour, so a short sum is the signal that the profile
    /// cannot stand for the whole. Equality is the test, not "has any hours".
    private static func hoursComplete(_ summary: SpendSummary) -> Bool {
        summary.hours.values.reduce(0, +) == summary.tokens
    }

    /// Whether any row shows an amount with a `*` beside it — a partly priced
    /// agent, day or month. A row that priced nothing shows an em dash instead,
    /// and a row that priced everything has no `*`, so neither needs the
    /// legend.
    private static func hasPartialAmounts(_ summary: SpendSummary) -> Bool {
        func partial(_ unpriced: Int, _ tokens: Int) -> Bool {
            unpriced > 0 && unpriced < tokens
        }
        return summary.agents.contains { partial($0.unpricedTokens, $0.tokens) }
            || summary.days.contains { partial($0.unpricedTokens, $0.tokens) }
            || summary.months.contains { partial($0.unpricedTokens, $0.tokens) }
            || summary.projects.contains { partial($0.unpricedTokens, $0.tokens) }
            || summary.sessions.contains { partial($0.session.unpricedTokens, $0.session.tokens) }
    }

    /// Whole months, for the spans long enough to have more than one.
    private func monthly(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("By month")) {
            VStack(spacing: 0) {
                ForEach(Array(summary.months.reversed().enumerated()), id: \.element.id) { index, month in
                    if index > 0 { SettingsRowDivider() }
                    SettingsRow(
                        month.date.formatted(.dateTime.year().month(.wide).locale(LocalizationSource.locale)),
                        subtitle: String.localized("\(TokenCount.short(month.tokens)) tokens")
                    ) {
                        // The same rule as a day row: a month whose tokens
                        // were all unpriced has no amount to show, and a
                        // partly priced month keeps its `*`.
                        CostText(
                            cost: month.tokens > 0 && month.unpricedTokens == month.tokens ? nil : month.cost,
                            unpriced: month.unpricedTokens
                        )
                        .font(.system(size: 12))
                    }
                }
            }
        }
    }

    // MARK: - The pattern

    /// Which days, rather than how much — and the habits that follow from it.
    ///
    /// The bar chart above answers "how heavy was each day"; this answers
    /// "which days, and how consistently". Same data, and the second question
    /// is not readable off the first: a run of light days and a run of gaps
    /// look alike in a bar chart and are opposites here.
    /// How consistently, and when.
    private func streaks(_ summary: SpendSummary) -> some View {
        SettingsGroup(String.localized("Pattern")) {
            HStack(spacing: 16) {
                SpendCaption(
                    String.localized("Current streak"),
                    String.localized("\("\(summary.currentStreak)") days")
                )
                SpendCaption(
                    String.localized("Longest streak"),
                    String.localized("\("\(summary.longestStreak)") days")
                )
                // Only a complete hour series has a peak worth naming.
                if Self.hoursComplete(summary), let hour = summary.peakHour {
                    SpendCaption(String.localized("Peak hour"), SpendFormat.hour(hour))
                }
                if let model = summary.models.first {
                    SpendCaption(String.localized("Favourite model"), model.name)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Where it went

    private var agents: some View {
        SettingsGroup(String.localized("By agent")) {
            ForEach(Array(summary.agents.enumerated()), id: \.element.id) { index, agent in
                if index > 0 { SettingsRowDivider() }

                // The whole row opens the agent, not a disclosure arrow at
                // the end of it: the row is what the reader is looking at, and
                // a target the width of a chevron is a target most people miss.
                Button {
                    focus = agent.agent
                } label: {
                    SettingsRow(
                        agent.agent.displayName,
                        subtitle: String.localized("\(TokenCount.short(agent.tokens)) tokens"),
                        icon: agent.agent.iconResource
                    ) {
                        HStack(spacing: 10) {
                            ShareBar(share: summary.tokens > 0
                                ? Double(agent.tokens) / Double(summary.tokens)
                                : 0)
                                .frame(width: 64, height: 6)

                            // A cost-only agent whose tokens were all
                            // unpriced shows no amount rather than `$0.00`; a
                            // partly priced one keeps its `*`.
                            CostText(
                                cost: agent.tokens > 0 && agent.unpricedTokens == agent.tokens
                                    ? nil : agent.cost,
                                unpriced: agent.unpricedTokens
                            )
                            .font(.system(size: 12))
                            .frame(width: 76, alignment: .trailing)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // A button's label does not take clicks where the row's
                    // own background is transparent, which is most of it.
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One row a model, and **the whole row opens it** — the same shape the
    /// agent list uses, because a target the width of a chevron is a target
    /// most people miss.
    ///
    /// The same rows serve the combined list and one agent's: which ledgers are
    /// behind them is `SettingsView`'s job. The row ranks by tokens, which is
    /// what the combined page can sum without pricing each model; the API
    /// estimate for one model lives behind the row, in its drill-down.
    private func models(_ summary: SpendSummary) -> some View {
        let shown = showAllModels
            ? summary.models
            : Array(summary.models.prefix(Self.modelLimit))

        return SettingsGroup(String.localized("By model")) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, model in
                if index > 0 { SettingsRowDivider() }

                Button {
                    modelFocus = model.name
                } label: {
                    SettingsRow(
                        model.name,
                        // Which agents sent work to it — one model can belong
                        // to two, and the row would otherwise look like it
                        // belongs to whichever is listed first above.
                        subtitle: model.agents.map(\.displayName).joined(separator: " · ")
                    ) {
                        HStack(spacing: 10) {
                            ShareBar(share: model.share)
                                .frame(width: 64, height: 6)

                            Text(String.localized("\(TokenCount.short(model.tokens)) tokens"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 76, alignment: .trailing)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // A button's label does not take clicks where the row's own
                    // background is transparent, which is most of it.
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String.localized("Show this model's details"))
            }

            // More models than fit a glance are still all reachable: the first
            // few are a preview, and this opens the rest rather than hiding
            // them behind the span picker.
            if summary.models.count > Self.modelLimit {
                SettingsRowDivider()
                Button {
                    showAllModels.toggle()
                } label: {
                    SettingsRow(showAllModels
                        ? String.localized("Show fewer")
                        : String.localized("Show all models")) {
                        Image(systemName: showAllModels ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Where the work happened

    /// One row per project identity, with ambiguous directory names expanded.
    private func projects(_ summary: SpendSummary) -> some View {
        let total = max(summary.projects.reduce(0) { $0 + $1.tokens }, 1)

        return SettingsGroup(String.localized("By project")) {
            VStack(spacing: 0) {
                ForEach(Array(summary.projects.prefix(Self.modelLimit).enumerated()), id: \.element.id) { index, project in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        project.name,
                        subtitle: String.localized("\("\(project.sessions)") sessions · last used \(Self.shortDate(project.lastUsed))")
                    ) {
                        HStack(spacing: 10) {
                            ShareBar(share: Double(project.tokens) / Double(total))
                                .frame(width: 64, height: 6)

                            CostText(cost: project.estimatedCost, unpriced: project.unpricedTokens)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
        }
    }

    /// One row a transcript, newest first.
    private func sessions(_ summary: SpendSummary) -> some View {
        let rows = summary.sessions
        let pages = max((rows.count + sessionPageSize - 1) / sessionPageSize, 1)
        let current = min(max(sessionPage, 0), pages - 1)
        let shown = Array(rows.dropFirst(current * sessionPageSize).prefix(sessionPageSize))

        return SettingsGroup(String.localized("By session")) {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        // What the conversation was called. The directory is
                        // the fallback and the file's own name the last
                        // resort — a uuid tells the reader nothing, but it is
                        // at least what the session is called.
                        row.session.title ?? summary.projectName(for: row) ?? row.session.name,
                        subtitle: Self.sessionSubtitle(row, project: summary.projectName(for: row)),
                        icon: row.agent.iconResource
                    ) {
                        HStack(spacing: 10) {
                            Text(String.localized("\(TokenCount.short(row.session.tokens)) tokens"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            CostText(cost: row.session.estimatedCost, unpriced: row.session.unpricedTokens)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                if rows.count > (SpendPaging.sizes.first ?? 10) {
                    SettingsRowDivider()
                    SpendPageFooter(rows: rows.count, pageSize: $sessionPageSize, page: $sessionPage)
                }
            }
        }
    }

    /// When it ran and for how long, and the file's own name where the row's
    /// title is already the directory.
    private static func sessionSubtitle(_ row: SpendSummary.Session, project: String?) -> String {
        let when = row.session.end.formatted(
            .dateTime.month(.abbreviated).day().hour().minute().locale(LocalizationSource.locale)
        )
        // The directory belongs here once the title has taken the row's own
        // line — it is what tells two conversations about the same thing
        // apart.
        guard let project, row.session.title != nil else { return when }
        return "\(when) · \(project)"
    }

    // MARK: - What the figures are not

    private func footnote(_ summary: SpendSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The same warning the card carries, and for the same reason: it
            // would be easy to read this as a bill, and it is not one. The
            // wording is generic on purpose — some records come from an export
            // that can cover more than this Mac, so "local logs" would make a
            // promise about the account that Pulse cannot keep.
            Text(localized: "Usage records, estimated at models.dev API rates—not an actual bill.")

            // **Some sources can only attest to part of their counts.** Where
            // one of those fed this span, the totals are the known subset; the
            // sentence says so rather than leaving a reader to trust a figure
            // the store itself did not fully state. Not an error, so it is a
            // plain note and never an empty page.
            if summary.hasPartialCounts {
                Text(localized: "Counts may be incomplete.")
            }

            // The legend for the `*` a partly priced row carries. A row whose
            // every token was unpriced shows no amount and needs no legend, so
            // this is shown only where an amount and a `*` are.
            if Self.hasPartialAmounts(summary) {
                Text(localized: "Excludes unpriced tokens.")
            }

            // **A short, conditional note about the dates.** Some stores state
            // only a session or report date, so the day a record lands on is
            // right while the hour is not. Said once, where the hour figures
            // are, rather than left to be inferred from a missing profile.
            if summary.hasAggregateTiming {
                Text(localized: "Some records use session report dates.")
            }

            if !summary.unpricedModels.isEmpty {
                // **Counted, not listed.** Naming them was fine at two and is
                // a paragraph at thirty — and the names are the least useful
                // part of the sentence, which is that some tokens have no
                // price. The list stays a hover away.
                Text(String.localized("\("\(summary.unpricedModels.count)") models without public pricing: tokens only."))
                    .help(summary.unpricedModels.joined(separator: ", "))
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

/// How far back the pane counts.
///
/// Not the card's fixed month: the question here is "where has it all gone",
/// which is asked over a week and over a year, and the answer changes shape at
/// each end.
enum SpendSpan: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case quarter
    case all

    /// The span the pane opens on: the last week, the shortest window that
    /// shows a work rhythm rather than a single day. The reader's own pick is
    /// kept by `AppSettings.spendSpan`.
    static let `default` = SpendSpan.week

    var id: String { rawValue }

    /// Nil counts everything the transcripts go back to.
    var days: Int? {
        switch self {
        // One day, which is the day in progress rather than the last
        // twenty-four hours: the ledger's rows are local midnights.
        case .today: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }

    var title: String {
        switch self {
        // Interpolate a string, never the integer: an `Int` in a localization
        // key produces `%lld`, which will not match a `%@` entry.
        case .today: .localized("Today")
        case .week: .localized("Last \("7") days")
        case .month: .localized("Last \("30") days")
        case .quarter: .localized("Last \("90") days")
        case .all: .localized("All time")
        }
    }
}

/// The day table's columns, which are also what it can be sorted by.
enum DayColumn: String, CaseIterable, Identifiable, Sendable {
    case date
    case input
    case output
    case cacheRead
    case cacheWrite
    case total
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: .localized("Date")
        case .input: .localized("Input")
        case .output: .localized("Output")
        // Short, because seven columns of Chinese headings in a settings pane
        // is a table that wraps.
        case .cacheRead: .localized("C. read")
        case .cacheWrite: .localized("C. write")
        case .total: .localized("Total")
        case .cost: .localized("Cost")
        }
    }
}
