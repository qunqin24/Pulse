// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// An account's Current usage card: when it was last read, each limit's
/// figure and reset, and, where the provider reports one, how the week splits
/// between its products.
struct AccountLiveUsageGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    /// A reading to draw instead of the store's, for a preview or a rendered
    /// picture; the pane always reads its own.
    var reading: ProviderUsage? = nil

    var body: some View {
        let usage = reading ?? store.usage(for: account)

        return SettingsGroup(String.localized("Current usage")) {
            if !settings.isEnabled(account) {
                SettingsRow(
                    String.localized("Not shown"),
                    subtitle: String.localized("Enable a service in its settings to start monitoring.")
                ) {
                    EmptyView()
                }
            } else {
                // Says how current these figures are, and offers to make them
                // current. The rail has the same on a ring click, but nobody
                // reading a settings pane should have to go and find it there.
                SettingsRow(String.localized("Last read")) {
                    HStack(spacing: 10) {
                        // `Text`'s relative style keeps counting on its own. A
                        // string worked out once said "just now" for the whole
                        // half hour until something else redrew the view.
                        if let observed = usage.observedAt {
                            Text(observed, style: .relative)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                // Every other date in the app is pinned to the
                                // language chosen in Settings; this one formats
                                // with the environment's locale, which follows the
                                // system. Without this, an English Pulse on a
                                // Chinese Mac prints "4分钟" beside "Refresh".
                                .environment(\.locale, LocalizationSource.locale)
                        } else {
                            Text(localized: "Not yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Button(String.localized("Refresh")) { store.refresh(account) }
                            // Any pass, not just this account.provider's: during a
                            // background one the press would only queue, with
                            // nothing on screen to say so.
                            .disabled(store.isRefreshing)
                    }
                }

                SettingsRowDivider()

                if usage.windows.isEmpty {
                    SettingsRow(
                        String.localized("No reading"),
                        subtitle: {
                            if case .unavailable(let reason) = usage.state { return reason.message }
                            return nil
                        }()
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(usage.windows.enumerated()), id: \.element.id) { index, window in
                        if index > 0 { SettingsRowDivider() }

                        SettingsRow(window.name, subtitle: resetText(window)) {
                            Text(window.percentText(remaining: settings.showsRemaining))
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }

                if let share = Self.visibleShare(of: usage, at: Date()) {
                    SettingsRowDivider()
                    ProductShareRow(share: share)
                }

                if let plan = usage.plan {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Plan")) {
                        Text(plan)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if let credit = usage.creditBalance {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Credit balance")) {
                        Text(credit)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The split, unless the week it describes is over: once the weekly limit
    /// has reset, last week's shares beside this week's figure would describe
    /// a different week.
    nonisolated static func visibleShare(of usage: ProviderUsage, at now: Date) -> ProductShare? {
        guard let share = usage.productShare else { return nil }
        let week = usage.windows.first { $0.kind == .weekly && $0.scope == nil }
        if let resets = week?.resetsAt, resets <= now { return nil }
        return share
    }

    private func resetText(_ window: UsageWindow) -> String? {
        // **The same rule as `UsageDetailCard.resetText`, and it has to be
        // stated in both places.** `windowSeconds` is sometimes a sort key
        // rather than a measurement, and printing one here put a figure nobody
        // reported under a heading that reads like a reported one — with the
        // panel's own card, an inch away, deliberately saying nothing.
        guard let resets = window.resetsAt else {
            return window.reportsLength ? window.lengthText : nil
        }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }
}

/// "Share of this week's usage", what it is, and one line per product. The
/// figures are deliberately quieter than a limit's: they are shares of the
/// week, not of an allowance, and the caption says so.
private struct ProductShareRow: View {
    let share: ProductShare

    var body: some View {
        SettingsRow(
            String.localized("Share of this week's usage"),
            subtitle: String.localized("As Anthropic reports it. Together the shares make up the whole week; they are not shares of the limit.")
        ) {
            VStack(alignment: .trailing, spacing: 2) {
                // By position: nothing stops two products sharing a name.
                ForEach(Array(share.rows.enumerated()), id: \.offset) { _, row in
                    Text(verbatim: "\(row.name) \(Self.percent(row.percent))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    /// Whole percentages, as the provider reports them; a share too small to
    /// round to one is "<1%", never a 0% it did not report.
    static func percent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded == 0 ? "<1%" : "\(rounded)%"
    }
}
