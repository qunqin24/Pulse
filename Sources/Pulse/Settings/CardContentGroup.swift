// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What this account's card shows beyond its limits, one switch a part
/// (`CardPart`). Only the parts this account can show are listed.
struct CardContentGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let parts = CardPart.available(for: account)
        let shown = settings.cardParts(for: account)

        SettingsGroup(String.localized("Card contents")) {
            ForEach(Array(parts.enumerated()), id: \.element) { index, part in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(part.title, subtitle: note(for: part)) {
                    Toggle("", isOn: Binding(
                        get: { shown.contains(part) },
                        set: { on in
                            settings.setCardPart(part, shown: on, for: account)
                            // Asked of Codex's app server on demand, not on
                            // the refresh timer.
                            if part == .resetCredits { store.refreshCodexResetCredits() }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    /// Said only where the part cannot appear yet, or costs something.
    private func note(for part: CardPart) -> String? {
        switch part {
        case .figures, .chart, .topModel, .cacheHitRate, .promptCache, .lastStep, .value:
            guard let history = account.provider.cardHistory, history.readsThisMac, !settings.readsTokenSpend else { return nil }
            return String.localized("Needs Token spend on.")
        case .resetCredits:
            return String.localized("Asks Codex's app server on every refresh.")
        case .plan, .updated, .forecast, .amounts:
            return nil
        }
    }
}
