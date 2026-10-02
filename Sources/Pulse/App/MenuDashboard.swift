// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// What the menu bar item's menu remembers between openings: which tab was
/// last looked at, and the spend ledgers it has read.
@MainActor
@Observable
final class MenuDashboardModel {
    /// The account whose tab is open, by id. Nil is the overview.
    var selected: String? {
        didSet { if selected != oldValue { onSelect?() } }
    }
    /// So the menu can show the items that belong to the tab.
    @ObservationIgnored var onSelect: (() -> Void)?
    /// Read on demand, when a tab that shows spend is opened with Token spend
    /// on. Kept for the session: the reader's own cache makes a re-read cheap,
    /// but a menu should not sit empty while it happens.
    var ledgers: [Provider: UsageLedger] = [:]
    /// When each was read. A tab opened after `ledgerLifetime` reads it again.
    var ledgerReadAt: [Provider: Date] = [:]
    var readingLedger: Provider?
    /// Long enough that flicking between tabs does not rescan, short enough
    /// that "Today" is today's.
    static let ledgerLifetime: TimeInterval = 5 * 60
}

/// The top of the menu bar item's menu: a tab per account on the rail and an
/// overview, each drawn from the figures the rail already has.
///
/// **Nothing here fetches a limit.** The tabs read `UsageStore`, which the
/// rail keeps current; the only read this starts is the spend ledger, and only
/// with Token spend switched on in Settings — the same opt-in that pane has.
struct MenuDashboard: View {
    let store: UsageStore
    let settings: AppSettings
    @Bindable var model: MenuDashboardModel
    /// Tells the menu the view's height changed, so the menu can grow with it.
    var onResize: (CGSize) -> Void = { _ in }

    static let width: CGFloat = 320
    /// The menu's own margins, measured against its items on macOS 26: the
    /// figures end where "⌘Q" does.
    static let leading: CGFloat = 14
    static let trailing: CGFloat = 15.5

    private var accounts: [AccountKey] { settings.shownAccounts }

    private var selectedAccount: AccountKey? {
        model.selected.flatMap(AccountKey.init(id:)).flatMap { accounts.contains($0) ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 8)

            Divider().padding(.horizontal, Self.leading)

            Group {
                if let account = selectedAccount {
                    MenuAccountDetail(account: account, store: store, settings: settings, model: model)
                } else {
                    overview
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onResize($0) }
    }

    // MARK: - Tabs

    private var tabs: some View {
        // Labels only while they fit: past five accounts the marks carry it and
        // the name is in the tooltip.
        let labelled = accounts.count <= 5
        return HStack(spacing: 2) {
            tab(id: nil, label: String.localized("Overview"), labelled: labelled) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
            }
            ForEach(accounts, id: \.id) { account in
                tab(id: account.id, label: settings.label(for: account), labelled: labelled) {
                    LobeIconView(resource: account.provider.iconResource, size: 15)
                }
            }
        }
    }

    private func tab<Icon: View>(id: String?, label: String, labelled: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        // The overview is selected whenever no account's tab is, including a
        // remembered account that has since left the rail.
        let isSelected = id == nil ? selectedAccount == nil : selectedAccount?.id == id
        return Button {
            model.selected = id
        } label: {
            VStack(spacing: 3) {
                icon()
                    .frame(height: 16)
                if labelled {
                    // Shrunk a little before it is cut: "Claude Code" in a
                    // sixth of the menu is a few points too wide at 10pt.
                    Text(verbatim: label)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, labelled ? 5 : 7)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(accounts, id: \.id) { account in
                Button {
                    model.selected = account.id
                } label: {
                    overviewRow(account)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.trailing)
    }

    private func overviewRow(_ account: AccountKey) -> some View {
        let reading = MenuBarReading.of(
            account,
            usage: store.usage(for: account),
            pinned: settings.pinnedWindow(for: account),
            warningAt: settings.warningThreshold.fraction
        )
        let detail = reading.window.map { window in
            [window.name, UsageDetailCard.resetDescription(window)].filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? (reading.money == nil ? String.localized("No reading") : nil)

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            LobeIconView(resource: account.provider.iconResource, size: 15)
                .foregroundStyle(.primary)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: settings.label(for: account))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(verbatim: reading.text(remaining: settings.showsRemaining))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(reading.isAlert ? Color.red : Color.primary)
                }
                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
    }
}

/// One account's tab: its plan and how fresh the reading is, every limit with
/// its bar and reset, what else the provider reports, and — with Token spend
/// on — what the local transcripts say it has cost.
private struct MenuAccountDetail: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    @Bindable var model: MenuDashboardModel

    private var usage: ProviderUsage { store.usage(for: account) }

    /// Only the providers whose transcripts are on this Mac, only the account
    /// the CLI is signed in to, and only with the reader's own switch on.
    private var showsSpend: Bool {
        settings.readsTokenSpend && account.isPrimary && account.provider.keepsLocalTranscripts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if case .unavailable(let reason) = usage.state {
                Text(reason.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(usage.windows) { window in
                limitRow(window)
            }

            extras

            if showsSpend {
                Divider()
                spend
            }
        }
        .padding(.leading, MenuDashboard.leading)
        .padding(.trailing, MenuDashboard.trailing)
        .task(id: account.id) { await readLedgerIfNeeded() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: settings.label(for: account))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let plan = usage.plan {
                    Text(verbatim: plan)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let observed = usage.observedAt {
                Text(verbatim: Self.updated(observed))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func updated(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return .localized("Updated just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.unitsStyle = .short
        return .localized("Updated \(formatter.localizedString(for: date, relativeTo: Date()))")
    }

    // MARK: Limits

    private func limitRow(_ window: UsageWindow) -> some View {
        let remaining = settings.showsRemaining
        let spent = UsageTint.isSpent(window)
        let percent = window.percentText(remaining: remaining)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: window.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(verbatim: UsageDetailCard.resetDescription(window))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                let fraction = remaining && !spent ? window.remainingFraction : window.usedFraction
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(window.tint(warningAt: settings.warningThreshold.fraction))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            Text(verbatim: remaining ? String.localized("\(percent) Left") : String.localized("\(percent) Used"))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(spent ? Color.red : Color.secondary)
        }
    }

    // MARK: What else the provider reports

    @ViewBuilder
    private var extras: some View {
        if account == AccountKey(.codex), let credits = store.codexResetCredits {
            valueRow(
                String.localized("Limit reset credits"),
                [UsageDetailCard.resetCreditsText(credits), UsageDetailCard.resetCreditExpiryText(credits)]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
        if let balance = usage.creditBalance {
            credit(balance)
        }
    }

    /// What is left, as the provider stated it, and nothing more: no bar,
    /// because no provider here says what it was out of — Codex reports its
    /// credits as a balance alone. Money is headed as a balance; anything else
    /// (Codex's credits) as credits.
    private func credit(_ balance: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: usage.creditRemaining == nil
                ? String.localized("Usage credits")
                : String.localized("Balance"))
                .font(.system(size: 12, weight: .medium))
            Text(verbatim: String.localized("\(balance) remaining"))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title).font(.system(size: 12))
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .lineLimit(1)
        }
    }

    // MARK: Spend

    @ViewBuilder
    private var spend: some View {
        if let ledger = model.ledgers[account.provider], !ledger.days.isEmpty {
            // The same four figures, over the same span, as the account's
            // usage history in Settings — one set of numbers, two places.
            let span = 31
            let today = ledger.today
            let recent = ledger.total(overLast: span)
            let busiest = ledger.busiestDay(overLast: span)
            let all = ledger.allTime
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        figure(String.localized("Today"), cost: today?.cost ?? 0, tokens: today?.tokens ?? 0)
                        figure(String.localized("Busiest day"), cost: busiest?.cost ?? 0, tokens: busiest?.tokens ?? 0)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 10) {
                        figure(String.localized("Last 31 days"), cost: recent.cost, tokens: recent.tokens)
                        figure(String.localized("All time"), cost: all.cost, tokens: all.tokens)
                    }
                    .frame(width: 120, alignment: .leading)
                }
                if ledger.days.count > 1 {
                    DailyTokensChart(days: ledger.recent(span))
                        .frame(height: 44)
                }
                Text(localized: "Estimated from token counts at API prices — not your subscription bill.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.readingLedger == account.provider {
            Text(localized: "Reading local records…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text(localized: "No history yet")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func figure(_ title: String, cost: Double, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(verbatim: AccountUsageCard.money(cost))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(verbatim: String.localized("\(TokenCount.short(tokens)) tokens"))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// The ledger for this provider, read when the tab opens unless it was
    /// read in the last few minutes. Incremental — only transcripts that
    /// changed since the last read are parsed again — and the previous figures
    /// stay on screen while it runs.
    private func readLedgerIfNeeded() async {
        let provider = account.provider
        let fresh = model.ledgerReadAt[provider].map { Date().timeIntervalSince($0) < MenuDashboardModel.ledgerLifetime } ?? false
        guard showsSpend, !fresh, model.readingLedger != provider else { return }
        model.readingLedger = provider
        let ledger = await UsageLedgerReader.shared.ledger(for: provider, refresh: true)
        model.ledgers[provider] = ledger
        model.ledgerReadAt[provider] = Date()
        if model.readingLedger == provider { model.readingLedger = nil }
    }
}
