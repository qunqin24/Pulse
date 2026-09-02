import SwiftUI

/// Layout constants for the detail bubble. Shared with
/// `FloatingPanelController.Layout` (which derives `expandedWidth` from
/// these plus `DockLayout`) and with `FloatingUsagePanelView`'s vertical
/// alignment math, so the AppKit panel frame and the SwiftUI content never
/// drift apart.
enum DetailCardLayout {
    static var width: CGFloat { 250 * PanelMetrics.scale }
    static var padding: CGFloat { 18 * PanelMetrics.scale }
    static var cornerRadius: CGFloat { 20 * PanelMetrics.scale }

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
    static var maximumHeight: CGFloat { height(forWindows: 5, footnote: true) }

    static func height(forWindows count: Int, footnote: Bool = false) -> CGFloat {
        padding * 2
            + headerHeight
            + CGFloat(count) * (contentSpacing + rowHeight)
            + (footnote ? contentSpacing + footnoteHeight : 0)
    }

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
    /// What each window's rate says, keyed by `UsageWindow.id`.
    var burn: [String: BurnRate.Reading] = [:]
    /// Where the pointer's tip should sit along the side facing the rail,
    /// measured from the card's own top or leading edge. The card gets pushed
    /// around by the panel's own edges (see
    /// `FloatingUsagePanelView.cardPadding`), so the pointer can't just ride
    /// at the card's centre — it has to be placed independently to keep aiming
    /// at the selected ring.
    let pointerCenter: CGFloat

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
                    accent: window.tint,
                    percentageText: window.percentText(remaining: showsRemaining),
                    isSpent: UsageTint.isSpent(window),
                    burn: burn[window.id]
                )
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
        }
        .padding(DetailCardLayout.padding)
        .frame(width: DetailCardLayout.width, alignment: .leading)
        // Room for the pointer on the side facing the rail. The shape below
        // covers the whole frame, body and pointer together.
        .padding(Self.pointerSide(for: edge), DetailCardLayout.pointerWidth)
        // The card follows the rail's surface: a glass capsule beside a solid
        // black card reads as two different components, not one panel.
        .background(
            {
                let shape = UsageBubbleShape(
                    edge: edge,
                    pointerCenter: pointerCenter,
                    cornerRadius: DetailCardLayout.cornerRadius,
                    pointerWidth: DetailCardLayout.pointerWidth,
                    pointerHeight: DetailCardLayout.pointerHeight
                )
                return PanelSurface(shape: shape, usesGlass: usesGlass)
            }()
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("\(title ?? usage.provider.displayName) usage details"))
    }

    /// Which side of the card the tail leaves from: the one facing the rail.
    private static func pointerSide(for edge: PanelEdge) -> Edge.Set {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        }
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

    private static func resetText(_ window: UsageWindow) -> String {
        guard let resets = window.resetsAt else { return window.lengthText }

        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        // Same day: the time is enough. Otherwise the date matters too.
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var header: some View {
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

            Spacer(minLength: 0)
        }
    }
}

private struct ProgressMetricRow: View {
    let title: String
    let resetDescription: String
    let progress: Double
    let accent: Color
    let percentageText: String
    let isSpent: Bool
    /// What the rate says about this window, or nil when nothing may be said.
    var burn: BurnRate.Reading?

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
                Text(localized: "\(percentageText) Used")
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(isSpent ? Color.pulseExhausted : .primary.opacity(0.9))

                Spacer(minLength: 0)

                Text(resetDescription)
                    .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.45))
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            burnLine
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String.localized("\(percentageText) used. \(resetDescription)"))
    }
}

extension ProgressMetricRow {
    /// How fast it is going, and — only when the evidence carries it — when it
    /// runs out.
    ///
    /// One line, dimmer than the figures above it, because it is the one thing
    /// on this card the provider did not say. It is absent far more often than
    /// present, and that is the design rather than a gap: a rate is only
    /// measurable while a limit is actually moving, and the prediction is only
    /// offered when it lands before the reset.
    @ViewBuilder
    var burnLine: some View {
        if let burn, !isSpent {
            HStack(spacing: 5) {
                Text(BurnRate.rateText(burn.perHour))

                if let seconds = burn.timeToExhaustion {
                    Text(localized: "· runs out in \(BurnRate.approximate(seconds))")
                        .foregroundStyle(Color.pulseWarning.opacity(0.9))
                } else if burn.exhaustsBeforeReset == false {
                    Text(localized: "· lasts the window")
                }
            }
            .font(.system(size: DetailCardLayout.rowFontSize, weight: .regular, design: .rounded))
            .foregroundStyle(.primary.opacity(0.45))
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

#Preview("Detail card") {
    UsageDetailCard(
        usage: .unavailable(.claudeCode, reason: .loading),
        edge: .right,
        pointerCenter: DetailCardLayout.estimatedHeight / 2
    )
    .padding(40)
    .background(.gray)
}
