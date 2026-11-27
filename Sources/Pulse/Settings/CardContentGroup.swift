// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What this account's card shows beyond its limits, one switch a part
/// (`CardPart`), behind one row that opens them: an advanced setting, closed
/// by default. Only the parts this account can show are listed.
struct CardContentGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings

    /// Closed until somebody opens it: the default card is the whole card,
    /// and choosing parts of it is a setting few will want.
    @State private var expanded = false

    var body: some View {
        let parts = CardPart.available(for: account)
        let shown = settings.cardParts(for: account)

        SettingsGroup(String.localized("Card contents")) {
            // The whole row opens it, as the diagnostics' disclosures do: on
            // macOS a chevron alone is a small target.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                SettingsRow(
                    String.localized("Choose what the card shows"),
                    subtitle: String.localized("\("\(shown.count)") of \("\(parts.count)") shown."),
                    symbol: "slider.horizontal.3"
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(parts, id: \.self) { part in
                    SettingsRowDivider()
                    SettingsRow(part.title, subtitle: note(for: part), symbol: part.symbol) {
                        Toggle("", isOn: Binding(
                            get: { shown.contains(part) },
                            set: { on in
                                settings.setCardPart(part, shown: on, for: account)
                                // Asked of Codex's app server on demand, not
                                // on the refresh timer.
                                if part == .resetCredits { store.refreshCodexResetCredits() }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
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
