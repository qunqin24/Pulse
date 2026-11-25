// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What each limit is worth in money.
///
/// The only inferred figure in the app, so it gets its own group and says
/// plainly where it came from — rather than sitting beside the reported
/// percentages as though it were one of them.
struct EstimatedValueGroup: View {
    let account: AccountKey
    let store: UsageStore
    let history: AccountHistoryModel

    @ViewBuilder
    var body: some View {
        let ledger = history.ledgers[account.provider] ?? .empty
        let usage = store.usage(for: account)
        // A window seen spent off this Mac keeps its row, saying why there is
        // no figure — a value that quietly vanished would read as a bug.
        let entries: [(UsageWindow, BudgetEstimate?)] = usage.windows.compactMap { window in
            if store.usedElsewhere(window, account: account) { return (window, nil) }
            return BudgetEstimator.estimate(for: window, ledger: ledger, observedAt: usage.observedAt).map { (window, $0) }
        }

        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SettingsGroup(String.localized("Estimated value")) {
                    ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
                        if index > 0 { SettingsRowDivider() }

                        if let estimate = entry.1 {
                            SettingsRow(
                                entry.0.name,
                                subtitle: String.localized("\(BudgetEstimator.approximate(estimate.spent)) used so far")
                            ) {
                                // Just what the whole window is worth. The
                                // remainder used to sit here too, but it is only
                                // the other two numbers subtracted — and the
                                // percentage it comes from is already on screen,
                                // in "Current usage" directly above.
                                Text(BudgetEstimator.approximate(estimate.full))
                                    .font(.system(size: 13, weight: .medium))
                                    .monospacedDigit()
                            }
                        } else {
                            SettingsRow(
                                entry.0.name,
                                subtitle: String.localized("Also used somewhere this Mac's logs can't see")
                            ) {
                                Text(localized: "Not estimated")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Text(localized: "An estimate: this Mac's spend this window, divided by the used percentage the provider reports. It reads low when the account is also used elsewhere; if the percentage rises while this Mac spends nothing, the window is no longer estimated. Windows with too little use are left out.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}
