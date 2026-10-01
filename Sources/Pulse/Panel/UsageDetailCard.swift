import SwiftUI

/// Layout constants for the detail bubble. Shared with
/// `FloatingPanelController.Layout` (which derives `expandedWidth` from
/// these plus `DockLayout`) and with `FloatingUsagePanelView`'s vertical
/// alignment math, so the AppKit panel frame and the SwiftUI content never
/// drift apart.
enum DetailCardLayout {
    static var width: CGFloat { 250 * PanelMetrics.scale }
    static var padding: CGFloat { 18 * PanelMetrics.scale }
    /// The rings' own curve: the outer edge of a ring's stroke, 20pt at
    /// standard size.
    ///
    /// One circle sets every curve on the panel — the rail's ends are this
    /// plus the band beside a ring (`DockLayout.cornerRadius`), the card's
    /// corners are this — so the three shapes read as one family instead of
    /// three radii picked separately. It also sits where the card's own
    /// content puts it: 18pt of padding round a bar whose ends are 3pt round.
    static var cornerRadius: CGFloat { (DockLayout.ringDiameter + DockLayout.ringLineWidth) / 2 }

    static var pointerWidth: CGFloat { 20 * PanelMetrics.scale }
    static var pointerHeight: CGFloat { 40 * PanelMetrics.scale }
    /// Gap between the pointer's tip and the dock rail. The tip approaches
    /// the rail but doesn't need to touch it.
    static var horizontalGap: CGFloat { 8 * PanelMetrics.scale }

    /// Vertical rhythm between header / progress row / progress row.
    static var contentSpacing: CGFloat { 14 * PanelMetrics.scale }
    /// Spacing between a row's title line, its progress bar, and its
    /// percent line.
    static var rowInternalSpacing: CGFloat { 7 * PanelMetrics.scale }
    static var progressBarHeight: CGFloat { 6 * PanelMetrics.scale }
    /// Rendered line height of the header row (icon + title).
    static var headerHeight: CGFloat { 19 * PanelMetrics.scale }

    // Type scales with everything else. It did not, once: the card's *width*
    // followed `PanelMetrics` while every font in it was written as a constant,
    // so at Small a 205pt card still tried to hold 14pt text and truncated its
    // own title, and at Large a 305pt card held the same 11.5pt rows and read
    // as half empty next to rings that had grown. The line-height budgets above
    // were already scaled, which is what makes these ratios hold at every size.
    static var titleFontSize: CGFloat { 14 * PanelMetrics.scale }
    static var rowFontSize: CGFloat { 11.5 * PanelMetrics.scale }
    static var messageFontSize: CGFloat { 12 * PanelMetrics.scale }
    static var footnoteFontSize: CGFloat { 11 * PanelMetrics.scale }
    /// The provider's mark in the header.
    static var headerIconSize: CGFloat { 16 * PanelMetrics.scale }
    /// Rendered line height of a row's title/percent text.
    static var rowTextLineHeight: CGFloat { 14 * PanelMetrics.scale }

    static var rowHeight: CGFloat {
        rowTextLineHeight + rowInternalSpacing + progressBarHeight + rowInternalSpacing + rowTextLineHeight
            // The forecast is a fourth line under every limit, and the panel's
            // frame is worked out from this before SwiftUI lays anything out.
            // Left out, a top-docked card with five limits ran 84pt past the
            // window and was sliced flat against its edge.
            + (PanelMetrics.showsForecast ? rowInternalSpacing + rowTextLineHeight : 0)
            // The detailed card's estimated value, under any limit it can price.
            + (PanelMetrics.showsDetailedCard ? rowInternalSpacing + rowTextLineHeight : 0)
    }

    /// Starting guess for the card's height, used for the very first layout
    /// pass only. The real height depends on how many limits the provider
    /// reports, so `FloatingUsagePanelView` measures it and works from that
    /// instead — see its `cardHeight`.
    static var estimatedHeight: CGFloat { height(forWindows: 2) }

    /// Room the panel has to leave for the tallest card it might have to show.
    ///
    /// The panel's frame is fixed, and a card taller than it gets sliced off
    /// square against the window's edge — which looks like a rendering bug,
    /// not like a card that didn't fit. Providers report a variable number of
    /// limits (Codex adds one group per model with its own limits), so this
    /// budgets for more than are on screen today.
    /// One row more than the limits for Codex's reset-credit lines: the count
    /// and the soonest expiry are two text lines, which together are shorter
    /// than a limit's row and so fit inside the budget of one.
    static var maximumHeight: CGFloat { height(forWindows: 6, footnote: true) }

    static func height(forWindows count: Int, footnote: Bool = false) -> CGFloat {
        let detailed = PanelMetrics.showsDetailedCard
        return padding * 2
            + headerHeight
            + (detailed ? headerLineSpacing + footnoteHeight : 0)
            + CGFloat(count) * (contentSpacing + rowHeight)
            + (footnote ? contentSpacing + footnoteHeight : 0)
            // Budgeted whether or not this account has a history to show:
            // the frame is one size for every card.
            + (detailed ? contentSpacing + activityHeight : 0)
    }

    // MARK: Detailed card

    /// Between the title and the "updated" line under it.
    static var headerLineSpacing: CGFloat { 4 * PanelMetrics.scale }

    /// Between the parts of the activity section.
    static var activitySpacing: CGFloat { 10 * PanelMetrics.scale }
    /// A column's label, its token count and its estimated cost.
    static var figureLabelHeight: CGFloat { 13 * PanelMetrics.scale }
    static var figureValueHeight: CGFloat { 17 * PanelMetrics.scale }
    static var figureFontSize: CGFloat { 14 * PanelMetrics.scale }
    static var figuresHeight: CGFloat { unpricedFiguresHeight + 2 * PanelMetrics.scale + figureLabelHeight }
    /// Label and count only, where nothing carries a price.
    static var unpricedFiguresHeight: CGFloat { figureLabelHeight + 2 * PanelMetrics.scale + figureValueHeight }
    static var chartHeight: CGFloat { 30 * PanelMetrics.scale }

    /// The whole activity section: rule, heading, figures, chart, top model,
    /// cache hit rate, the prompt cache's lapse, the line saying what the
    /// money is. Each part is drawn at the height
    /// named here, so the budget and the drawing cannot drift.
    static var activityHeight: CGFloat {
        1
            + activitySpacing + figureLabelHeight
            + activitySpacing + figuresHeight
            + activitySpacing + chartHeight
            + activitySpacing + rowTextLineHeight
            + activitySpacing + rowTextLineHeight
            // The prompt cache's line, and under it — with several
            // conversations — the name of the one about to lapse.
            + activitySpacing + rowTextLineHeight + promptCacheNameHeight
            + activitySpacing + footnoteHeight
    }

    /// The conversation's name under the prompt cache's line: a gap and one
    /// footnote-sized line. Budgeted whether or not several conversations are
    /// running, because the frame is one size for every card.
    static var promptCacheNameHeight: CGFloat { 2 * PanelMetrics.scale + footnoteHeight }

    /// Rendered line height of the "as of …" line under the limits.
    static var footnoteHeight: CGFloat { 13 * PanelMetrics.scale }
}

struct UsageDetailCard: View {
    /// Liquid Glass instead of flat black, matching the rail.
    var usesGlass: Bool = false
    let usage: ProviderUsage
    /// What this account is called. The provider's own name for the first
    /// account of it, the user's label for the rest — two subscriptions to the
    /// same plan are told apart by nothing else, and a card headed "Codex" on
    /// both of them is a card that cannot say which one you are looking at.
    var title: String?
    /// Which screen edge the panel is docked against; the pointer goes on the
    /// side facing the rail.
    let edge: PanelEdge
    /// Show what is left rather than what is gone, matching the rail.
    var showsRemaining: Bool = false
    /// Say whether each limit will last its window.
    var showsForecast: Bool = false
    /// Codex's limit reset credits, when its switch is on and it has been
    /// asked. Nil draws no row at all.
    var resetCredits: CodexResetCredits?
    /// The detailed card: the plan, how far through each window the clock is
    /// and the account's recent activity. Set per account.
    var isDetailed = false
    /// What this Mac's records say about the account, for the detailed card.
    /// Nil draws no section: Token spend is off, or this account keeps no
    /// records here.
    var spend: Spend?
    /// When each live session's prompt cache lapses, where the logs say. The
    /// card names the soonest; Settings lists them all.
    var promptCache: PromptCacheReading?
    /// Where the pointer's tip should sit along the side facing the rail,
    /// measured from the card's own top or leading edge. The card gets pushed
    /// around by the panel's own edges (see
    /// `FloatingUsagePanelView.cardPadding`), so the pointer can't just ride
    /// at the card's centre — it has to be placed independently to keep aiming
    /// at the selected ring.
    let pointerCenter: CGFloat

    /// Where red begins, so the card's bars agree with the rail's rings.
    @Environment(\.usageWarningThreshold) private var warningThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.contentSpacing) {
            header

            // However many limits the provider reports — one account-wide
            // window for some plans, several once per-model limits apply.
            ForEach(usage.windows) { window in
                ProgressMetricRow(
                    title: window.name,
                    resetDescription: Self.resetText(window),
                    progress: showsRemaining ? window.remainingFraction : window.usedFraction,
                    accent: window.tint(warningAt: warningThreshold),
                    percentageText: window.percentText(remaining: showsRemaining),
                    isSpent: UsageTint.isSpent(window),
                    showsRemaining: showsRemaining,
                    // Every provider, not a chosen few: what this needs is a
                    // percentage, a reset and a length the provider actually
                    // stated, and `BurnRate` refuses the windows that lack one
                    // rather than being told in advance which they are.
                    burn: showsForecast ? BurnRate.reading(for: window) : nil,
                    value: valueText(window)
                )
                .transition(Self.rowTransition)
            }

            // **A card with only a title in it reads as a card that failed to
            // load.** Every provider until DeepSeek reported at least one
            // limit, so an empty body could only mean an unavailable reading
            // and the message below covered it. DeepSeek on "balance only"
            // reports money and no limits *by design*, and the money is then
            // the whole reading — so it is what the card says.
            // The count Codex reported, or that it reported none — never one
            // Pulse worked out. Then when the soonest of them lapses, to the
            // minute, since that decides whether to spend one now (issue #67).
            if let resetCredits {
                ValueRow(title: String.localized("Limit reset credits"), value: Self.resetCreditsText(resetCredits))
                if let expiry = Self.resetCreditExpiryText(resetCredits) {
                    ValueRow(title: String.localized("Next expiry"), value: expiry)
                }
            }

            // An extension may report limits and money both — a relay's
            // quota and its prepaid credit — and the ring can only draw one,
            // so the card keeps the money in view either way.
            if usage.windows.isEmpty || usage.account.provider == .pulseExtension,
               let balance = usage.creditBalance {
                ValueRow(title: String.localized("Credit balance"), value: balance)
            }

            // The same rule for the other way a body can come out empty: a
            // reading that says nothing at all still has to say *that*.
            if saysNothing {
                Text(ProviderUsage.Unavailability.noLimitsReported.message)
                    .font(.system(size: DetailCardLayout.messageFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unavailable(let reason) = usage.state {
                Text(reason.message)
                    .font(.system(size: DetailCardLayout.messageFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
            }

            if isDetailed, let spend {
                ActivitySection(spend: spend, provider: usage.provider, promptCache: promptCache)
                    .transition(Self.rowTransition)
            }
        }
        .padding(DetailCardLayout.padding)
        .frame(width: DetailCardLayout.width, alignment: .leading)
        // Room for the pointer on the side facing the rail. The shape below
        // covers the whole frame, body and pointer together.
        .padding(Self.pointerSide(for: edge), DetailCardLayout.pointerWidth)
        // **Inside the card, never ahead of it.** Switching between two cards
        // of different heights keeps this one view and swaps its rows: the
        // outline grows on the panel's spring, but a row the new card adds is
        // laid out at its final place at once, so it stood outside a card
        // that had not reached it yet — the text arriving before the card.
        // Masked to the same outline, the card uncovers it as it grows.
        // The content only: the surface keeps its own edge, where glass
        // draws a rim this would cut.
        .mask { bubble }
        // The card follows the rail's surface: a glass capsule beside a solid
        // black card reads as two different components, not one panel.
        .background(LiquidBubbleSurface(bubble: bubble, usesGlass: usesGlass))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("\(title ?? usage.provider.displayName) usage details"))
    }

    /// The soonest available credit's expiry, with the year: a credit can
    /// last past New Year, and one whose date is misread gets wasted. Nil when
    /// there is none to spend or Codex gave no date.
    static func resetCreditExpiryText(_ credits: CodexResetCredits) -> String? {
        guard case .available(let count, let expiry?) = credits, count > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
        return formatter.string(from: expiry)
    }

    static func resetCreditsText(_ credits: CodexResetCredits) -> String {
        switch credits {
        case .available(let count, _):
            count == 1 ? .localized("1 available") : .localized("\("\(count)") available")
        case .unreported:
            .localized("Not available")
        case .codexMissing:
            .localized("codex not found")
        }
    }

    /// A limit the next card has and this one did not waits for the card to
    /// grow, then settles in; one it loses leaves at once.
    ///
    /// Arriving with the outline instead — the default — put the row at its
    /// final place on the first frame, so it either stood outside a card that
    /// had not reached it yet or, masked, was wiped on by the card's edge. Both
    /// read as a row popping in. A short wait lets the outline get ahead of
    /// it, so it is a card that grew, and then filled.
    ///
    /// **Short, because the rail is swept.** Running the pointer down the
    /// rings switches cards every tenth of a second, and every switch restarts
    /// this. At 0.14s + 0.22s the card spent most of a sweep empty — a black
    /// card with nothing in it. 0.06s + 0.14s still trails the outline and is
    /// done before the next ring.
    private static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -6))
                .animation(.easeOut(duration: 0.14).delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.06))
        )
    }

    private var bubble: UsageBubbleShape {
        UsageBubbleShape(
            edge: edge,
            pointerCenter: pointerCenter,
            cornerRadius: DetailCardLayout.cornerRadius,
            pointerWidth: DetailCardLayout.pointerWidth,
            pointerHeight: DetailCardLayout.pointerHeight
        )
    }

    /// Which side of the card the tail leaves from: the one facing the rail.
    private static func pointerSide(for edge: PanelEdge) -> Edge.Set {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// Whether the body would otherwise be nothing but the header.
    ///
    /// An unavailable reading is excluded because its own message is about to
    /// say something better than "no limits reported" — which route failed,
    /// or what to sign in to.
    private var saysNothing: Bool {
        guard usage.windows.isEmpty, usage.creditBalance == nil else { return false }
        if case .unavailable = usage.state { return false }
        return true
    }

    /// A line under the limits saying how much to trust them: Claude Code's
    /// figures only refresh while a session is running, so an old reading has
    /// to say so rather than pass for current.
    private var footnote: String? {
        switch usage.state {
        case .live, .unavailable:
            nil
        case .stale:
            usage.observedAt.map { String.localized("As of \(Self.relative($0))") }
                ?? String.localized("Reading may be out of date")
        }
    }

    /// The card's line under a limit, for the menu bar's list too.
    static func resetDescription(_ window: UsageWindow) -> String { resetText(window) }

    /// What a limit is worth, on the detailed card: "Estimated value ≈$220 ·
    /// ≈$101 used". The settings pane's `BudgetEstimate`, from the ledger the
    /// card already holds — so only where that ledger carries money and its
    /// quarter-hours, which is this Mac's records and never a provider's own
    /// statistics. Nil wherever the estimator withholds it.
    private func valueText(_ window: UsageWindow) -> String? {
        guard isDetailed, case .ledger(let ledger) = spend,
              let estimate = BudgetEstimator.estimate(for: window, ledger: ledger)
        else { return nil }
        return .localized("Estimated value \(BudgetEstimator.approximate(estimate.full)) · \(BudgetEstimator.approximate(estimate.spent)) used")
    }

    /// "Updated 3 min ago".
    static func updatedText(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return .localized("Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.unitsStyle = .short
        return .localized("Updated \(formatter.localizedString(for: date, relativeTo: now))")
    }

    private static func resetText(_ window: UsageWindow) -> String {
        // **Whichever happens first.** Credits lapsing before a reset hands
        // the allowance back are the thing to know; after it, the reset is.
        if let expiry = window.nextExpiry, window.resetsAt.map({ expiry.at < $0 }) ?? true {
            return expiryText(expiry)
        }

        // **The fallback may only state a length the provider stated.**
        // `windowSeconds` is sometimes a sort key rather than a measurement —
        // Cursor's billing cycle stored as a flat 30 days, Kimi's rolling
        // weekly allowance, Grok Bot's week — and printing one here would put
        // a figure nobody reported on the card, under a heading that reads
        // like a reported one. Nothing is said instead, which is the truth.
        guard let resets = window.resetsAt else {
            return window.reportsLength ? window.lengthText : ""
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        // Same day: the time is enough. Otherwise the date matters too.
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }

    /// "10月18日 86 积分到期". The date alone unless it is today — a pack
    /// ends at whatever minute it was granted, and that minute is noise a
    /// week out.
    private static func expiryText(_ expiry: UsageWindow.Expiry) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(expiry.at) ? "jmm" : "MMMd"
        )
        // StepFun counts in Credits of which a plan holds billions: "1,599,913,834"
        // does not fit the slot, and the scale is the point, as with tokens.
        let amount = expiry.amount >= 10_000
            ? TokenCount.short(Int(expiry.amount))
            : expiry.amount.formatted(.number.precision(.fractionLength(0...1)).locale(LocalizationSource.locale))
        return String.localized("\(formatter.string(from: expiry.at)): \(amount) credits expire")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var header: some View {
        // Another account's header replaces this one rather than cross-fading
        // through it: two titles of different lengths drawn over each other
        // for the length of the fade read as a smudge. Stacked so the outgoing
        // one keeps no room in the row while it leaves.
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: DetailCardLayout.headerLineSpacing) {
                HStack(spacing: 8) {
                    LobeIconView(provider: usage.provider, size: DetailCardLayout.headerIconSize)
                        .foregroundStyle(.primary)

                    Text(localized: "\(title ?? usage.provider.displayName) Usage")
                        // One line, always. The card's height is worked out from
                        // `DetailCardLayout` before SwiftUI lays anything out, so a
                        // header that wrapped would make the card taller than the
                        // window budgeted for it and get sliced off against the edge.
                        .lineLimit(1)
                        .font(.system(size: DetailCardLayout.titleFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .layoutPriority(1)

                    // The plan as the provider names it. It gives way to the
                    // title, which is what says whose card this is.
                    if isDetailed, let plan = usage.plan, !plan.isEmpty {
                        Spacer(minLength: 0)
                        Text(verbatim: plan)
                            .lineLimit(1)
                            .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                }

                // How fresh the figures are. A stale reading says so in the
                // footnote instead, in stronger words.
                if isDetailed, case .live = usage.state, let observed = usage.observedAt {
                    Text(verbatim: Self.updatedText(observed))
                        .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.4))
                        .lineLimit(1)
                        // Level with the title, not the icon.
                        .padding(.leading, DetailCardLayout.headerIconSize + 8)
                }
            }
            .id("\(usage.id)|\(title ?? "")")
            .transition(Self.headerTransition)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The old one gone almost at once, the new one in straight away.
    ///
    /// No wait before the new one: waiting left the header blank for most of a
    /// sweep down the rail (see `rowTransition`). The overlap that remains is
    /// a few hundredths of a second with the old title nearly gone — not the
    /// two-titles smudge a plain cross-fade drew.
    private static var headerTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.06))
        )
    }
}

extension UsageDetailCard {
    /// What the detailed card can say about an account's recent activity.
    enum Spend: Equatable {
        /// The records are being read; the last figures, if any, are not in yet.
        case reading
        /// Read, and nothing in them.
        case empty
        /// Asked of the provider, which did not answer.
        case failed
        case ledger(UsageLedger)
    }
}

/// The detailed card's last section: the account's recent usage, from this
/// Mac's records at the Token spend pane's prices, or — for Z.ai and Zhipu —
/// from the statistics the provider publishes for the whole account.
///
/// **Tokens lead, money follows.** The tokens are counted; the money is those
/// counts at API prices, which a subscription does not pay — so it is the
/// smaller, dimmer line, marked as approximate, and the section says so. A
/// provider's own statistics carry no money at all, so they show none.
private struct ActivitySection: View {
    let spend: UsageDetailCard.Spend
    let provider: Provider
    var promptCache: PromptCacheReading?

    /// The provider's figures rather than this Mac's: headed and footed as
    /// such, and never priced.
    private var isAccountWide: Bool { provider.cardHistory == .accountStatistics }

    /// The chart's span, and the longest of the three figures.
    private static let span = 31

    var body: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.activitySpacing) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            Text(isAccountWide ? String.localized("Whole account") : String.localized("On this Mac"))
                .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.5))
                .frame(height: DetailCardLayout.figureLabelHeight)

            switch spend {
            case .reading:
                message(String.localized("Reading local records…"))
            case .empty:
                message(String.localized("No history yet"))
            case .failed:
                message(String.localized("Couldn't read the history."))
            case .ledger(let ledger):
                figures(ledger)
                DaysChart(days: ledger.recent(Self.span))
                    .frame(height: DetailCardLayout.chartHeight)
                topModel(ledger)
                cacheHitRate(ledger)
                if let promptCache { PromptCacheRow(reading: promptCache) }
                Text(isAccountWide
                    ? String.localized("From \(provider.displayName), for the whole account.")
                    : String.localized("Costs are estimates at API prices."))
                    .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(height: DetailCardLayout.footnoteHeight)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
            .foregroundStyle(.primary.opacity(0.45))
            .frame(height: DetailCardLayout.rowTextLineHeight)
    }

    private func figures(_ ledger: UsageLedger) -> some View {
        let today = ledger.today
        let week = ledger.total(overLast: 7)
        let month = ledger.total(overLast: Self.span)
        // No money line at all where there is no money anywhere — a provider's
        // own statistics, or nothing priced — rather than a blank band under
        // the figures. One priced column keeps the line on all three, level.
        let priced = !isAccountWide && month.cost > 0
        return HStack(alignment: .top, spacing: 8) {
            figure(String.localized("Today"), tokens: today?.tokens ?? 0, cost: today?.cost ?? 0, priced: priced)
            figure(String.localized("7 days"), tokens: week.tokens, cost: week.cost, priced: priced)
            figure(String.localized("31 days"), tokens: month.tokens, cost: month.cost, priced: priced)
        }
        .frame(height: priced ? DetailCardLayout.figuresHeight : DetailCardLayout.unpricedFiguresHeight, alignment: .top)
    }

    /// **No money line for work nobody priced.** A day spent entirely on a
    /// model with no published price costs something; "$0.00" would say it
    /// cost nothing.
    private func figure(_ label: String, tokens: Int, cost: Double, priced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2 * PanelMetrics.scale) {
            Text(verbatim: label)
                .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                .foregroundStyle(.primary.opacity(0.45))
                .frame(height: DetailCardLayout.figureLabelHeight)
            Text(verbatim: TokenCount.short(tokens))
                .font(.system(size: DetailCardLayout.figureFontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(height: DetailCardLayout.figureValueHeight)
            if priced {
                Text(verbatim: cost > 0 ? "≈" + AccountUsageCard.money(cost) : " ")
                    .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(height: DetailCardLayout.figureLabelHeight)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String.localized("\(TokenCount.short(tokens)) tokens"))
    }

    /// Over the same month as the top model. Absent, not "0%", where the
    /// records do not sort every token into its kind — a provider's own
    /// statistics never do.
    @ViewBuilder
    private func cacheHitRate(_ ledger: UsageLedger) -> some View {
        if let rate = ledger.cacheHitRate(overLast: Self.span) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized: "Cache hit rate")
                    .foregroundStyle(.primary.opacity(0.45))
                Spacer(minLength: 0)
                Text(verbatim: "\(Int((rate * 100).rounded()))%")
                    .foregroundStyle(.primary.opacity(0.9))
                    .monospacedDigit()
            }
            .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
            .lineLimit(1)
            .frame(height: DetailCardLayout.rowTextLineHeight)
        }
    }

    @ViewBuilder
    private func topModel(_ ledger: UsageLedger) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(localized: "Top model")
                .foregroundStyle(.primary.opacity(0.45))
            Spacer(minLength: 0)
            if let top = ledger.topModel(overLast: Self.span) {
                // A model id can run to thirty characters; its middle is the
                // part that says least.
                Text(verbatim: "\(top.name) · \(Int((top.share * 100).rounded()))%")
                    .foregroundStyle(.primary.opacity(0.9))
                    .truncationMode(.middle)
            } else {
                Text(verbatim: "—")
                    .foregroundStyle(.primary.opacity(0.45))
            }
        }
        .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
        .lineLimit(1)
        .frame(height: DetailCardLayout.rowTextLineHeight)
    }
}

/// The prompt cache that lapses soonest: "Prompt cache (1 hr) · 38 min left"
/// for one conversation — "At least 18 min left" for Codex, whose thirty
/// minutes are OpenAI's guaranteed floor rather than a known end. For several, "Prompt cache · 3 chats · Soonest in
/// 10 min" with **the name of that conversation under it** — a countdown
/// without a name is one the reader cannot act on, and the rest are listed in
/// Settings. "Expired" once none is alive: the next message then writes its
/// context to the cache again, at the higher rate.
///
/// **The soonest, not the latest.** The one about to lapse is the one worth
/// a message now; the one just used has an hour either way.
///
/// Ticks on its own, every half minute, so a card left open does not hold a
/// stale countdown — and a conversation that lapses meanwhile drops out of
/// the count. Gone once the last session is a day old.
private struct PromptCacheRow: View {
    let reading: PromptCacheReading

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let live = reading.alive(at: now)
            let lapsed = reading.lastLapsed ?? reading.live.map(\.lapse).max { $0.expiresAt < $1.expiresAt }
            if let urgent = live.first {
                let soonest = urgent.lapse
                VStack(alignment: .leading, spacing: 2 * PanelMetrics.scale) {
                    row(
                        live.count == 1
                            ? String.localized("Prompt cache (\(Self.duration(soonest.lifetime)))")
                            : String.localized("Prompt cache · \("\(live.count)") chats"),
                        Self.timeLeft(soonest, now: now, several: live.count > 1),
                        lapsed: false
                    )
                    if live.count > 1 {
                        Text(verbatim: urgent.displayName ?? String.localized("Untitled conversation"))
                            .font(.system(size: DetailCardLayout.footnoteFontSize, weight: .regular, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: DetailCardLayout.footnoteHeight, alignment: .leading)
                    }
                }
            } else if let lapsed, now.timeIntervalSince(lapsed.expiresAt) < PromptCacheLapse.staleAfter {
                // A guaranteed floor that has run out is not a cache known to
                // be gone — OpenAI may still hold it.
                row(String.localized("Prompt cache (\(Self.duration(lapsed.lifetime)))"),
                    lapsed.isMinimum ? String.localized("May have lapsed") : String.localized("Expired"),
                    lapsed: true)
            }
        }
    }

    private func row(_ label: String, _ value: String, lapsed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label)
                .foregroundStyle(.primary.opacity(0.45))
            Spacer(minLength: 0)
            Text(verbatim: value)
                .foregroundStyle(.primary.opacity(lapsed ? 0.45 : 0.9))
                .monospacedDigit()
        }
        .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
        .lineLimit(1)
        .frame(height: DetailCardLayout.rowTextLineHeight)
    }

    private static func duration(_ seconds: TimeInterval) -> String { PromptCacheLapse.duration(seconds) }

    /// "38 min left", or for Codex's guaranteed floor "At least 18 min left".
    ///
    /// With several conversations the floor is said the same way: the line
    /// under it names the conversation it belongs to, and "soonest" on top of
    /// "at least" did not fit the row — both halves were cut to "…".
    private static func timeLeft(_ lapse: PromptCacheLapse, now: Date, several: Bool) -> String {
        let left = duration(lapse.expiresAt.timeIntervalSince(now))
        if lapse.isMinimum { return .localized("At least \(left) left") }
        return several ? .localized("Soonest in \(left)") : .localized("\(left) left")
    }
}

/// A month of days as bars, today's lit. Static: the card is on a panel that
/// never becomes key, where a hover readout would not fire — the Token spend
/// pane is where a chart is read closely.
private struct DaysChart: View {
    let days: [LedgerDay]

    var body: some View {
        GeometryReader { proxy in
            let peak = max(days.map(\.tokens).max() ?? 1, 1)
            let count = max(days.count, 1)
            let spacing = max(proxy.size.width / CGFloat(count) * 0.3, 1.5)
            let width = max((proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(days) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    Capsule()
                        .fill(Color.primary.opacity(isToday ? 0.9 : (day.tokens > 0 ? 0.32 : 0.12)))
                        // A day with any work keeps a visible stub, so a quiet
                        // day reads as quiet rather than as missing.
                        .frame(
                            width: width,
                            height: day.tokens > 0
                                ? max(proxy.size.height * CGFloat(day.tokens) / CGFloat(peak), width)
                                : min(width, 2)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("Tokens per day"))
    }
}

/// A figure with no percentage behind it, for a provider that reports one.
///
/// No bar: there is nothing to fill it with. A bar drawn at zero beside a real
/// balance would read as an empty account, which is the opposite of what a
/// healthy balance means.
///
/// No explanatory line under it either. It said that the provider reports no
/// limit to measure the figure against, which is true and is also the one
/// thing the card has already made obvious by having nothing else on it.
private struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ProgressMetricRow: View {
    let title: String
    let resetDescription: String
    let progress: Double
    let accent: Color
    let percentageText: String
    let isSpent: Bool
    /// Which way the figure beside the bar is counted, so the word next to it
    /// can agree with it.
    let showsRemaining: Bool
    /// What the rate says about this window, or nil when nothing may be said.
    var burn: BurnRate.Reading?
    /// The detailed card's estimate of what the window is worth. Nil draws no line.
    var value: String?

    /// "88% Used", or "12% Left" when the figure is counted the other way.
    private var figureLabel: String {
        showsRemaining
            ? .localized("\(percentageText) Left")
            : .localized("\(percentageText) Used")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailCardLayout.rowInternalSpacing) {
            // The name gets the row to itself. It used to share the line with
            // the reset time, which is fine for "5-hour limit" and falls apart
            // the moment a limit is scoped to something: "5-hour limit ·
            // Claude and GPT" next to "Resets 9月6日 18:14" does not fit in a
            // 250pt card, and it was the *name* that got cut — the half that
            // says which limit this is.
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))

            ProgressView(value: progress)
                .progressViewStyle(PulseProgressStyle(accent: accent))

            // The two short facts pair off on the line below instead: what is
            // gone, and when it comes back.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // **The word has to follow the figure.** `percentageText` is
                // what is *left* when the setting is on, and this said "Used"
                // regardless — so a limit 88% gone read "12% Used" on the card
                // while the rail an inch away said "12% left".
                // Built outside the call rather than as a ternary inside it:
                // `Scripts/localization-keys.py` reads a conditional there as
                // the bare tail — "Left" — which matched an unrelated key and
                // let a missing one through the check that exists to catch it.
                Text(figureLabel)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isSpent ? Color.pulseExhausted : .primary.opacity(0.9))
                    // Swapped outright. A cross-fade drew two figures over each
                    // other; a numeric roll left the digits mid-turn — blank —
                    // for most of a sweep down the rail, since every switch
                    // restarts it. A figure that is simply the next one is
                    // readable on every frame.
                    .contentTransition(.identity)

                Spacer(minLength: 0)

                Text(resetDescription)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.45))
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Dimmer than the reported figures above it: it is the one
            // number here the provider did not say.
            if let value {
                Text(verbatim: value)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            burnLine
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            showsRemaining
                ? String.localized("\(percentageText) left. \(resetDescription)")
                : String.localized("\(percentageText) used. \(resetDescription)")
        )
    }
}

extension ProgressMetricRow {
    /// How fast it is going, and — only when the evidence carries it — when it
    /// runs out.
    ///
    /// One line, dimmer than the figures above it, because it is the one thing
    /// on this card the provider did not say — though both halves of it are
    /// figures the provider *did* say, subtracted. It is absent far more often than
    /// present, and that is the design rather than a gap: a rate is only
    /// measurable while a limit is actually moving, and the prediction is only
    /// offered when it lands before the reset.
    @ViewBuilder
    var burnLine: some View {
        if let burn, !isSpent {
            Group {
                if let seconds = burn.timeToExhaustion {
                    Text(localized: "Runs out in \(BurnRate.approximate(seconds))")
                        .foregroundStyle(Color.pulseWarning.opacity(0.9))
                } else if burn.exhaustsBeforeReset {
                    // **The verdict without the time.** Beyond the horizon the
                    // hours are not worth stating, but the answer still is —
                    // and this was silent here once, which showed the good news
                    // and hid the bad. A weekly window's exhaustion is nearly
                    // always further out than two hours, so that was most of
                    // the warnings there are.
                    Text(localized: "Won't last the window")
                        .foregroundStyle(Color.pulseWarning.opacity(0.9))
                } else {
                    Text(localized: "Expected to last the window")
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
            .lineLimit(1)
        }
    }
}

private struct PulseProgressStyle: ProgressViewStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.17))

                Capsule()
                    .fill(accent)
                    .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: DetailCardLayout.progressBarHeight)
    }
}


/// The card's surface. Solid, it is the outline filled in one go. Glass, it is
/// the body and the tail as **two pieces of glass the system fuses**.
///
/// Drawn as one outline, the glass read the tail as a narrow shape of its own:
/// thin enough to be all rim, it refracted what was behind it sharply and
/// lighter, while the body beside it blurred — over a busy backdrop the tail
/// looked like a crystal stuck onto the card. In a `GlassEffectContainer` the
/// two shapes are joined the way Liquid Glass joins any two pieces that come
/// close, with one continuous surface and a smooth neck, so the tail shades
/// on from the body. Only the surface: the content is still masked to the
/// whole outline.
///
/// The spacing is what the pieces fuse across. The tail already overlaps the
/// body, so it only has to be small; 40 was tried and rippled the body's edge
/// beside the tail.
private struct LiquidBubbleSurface: View {
    let bubble: UsageBubbleShape
    let usesGlass: Bool

    var body: some View {
        if #available(macOS 26, *), usesGlass {
            GlassEffectContainer(spacing: 12 * PanelMetrics.scale) {
                ZStack {
                    PanelSurface(shape: bubble.only(.body), usesGlass: true)
                    PanelSurface(shape: bubble.only(.tail), usesGlass: true)
                }
            }
        } else {
            PanelSurface(shape: bubble, usesGlass: usesGlass)
        }
    }
}
#Preview("Detail card") {
    UsageDetailCard(
        usage: .unavailable(.claudeCode, reason: .loading),
        edge: .right,
        pointerCenter: DetailCardLayout.estimatedHeight / 2
    )
    .padding(40)
    .background(.gray)
}
