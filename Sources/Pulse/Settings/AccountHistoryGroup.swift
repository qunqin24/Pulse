// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What has actually been spent over time, as opposed to how much of the
/// current limit is left.
struct AccountHistoryGroup: View {
    let account: AccountKey
    let history: AccountHistoryModel
    let settings: AppSettings
    let openTokenSpend: () -> Void

    /// Read from other agents' records, which wait for Token spend reading.
    private var needsTokenSpend: Bool {
        guard case .agents = account.provider.cardHistory else { return false }
        return !settings.readsTokenSpend
    }

    @ViewBuilder
    var body: some View {
        if needsTokenSpend {
            // Said rather than left empty: "no history yet" would claim the
            // agent has logged nothing, when Pulse has simply not looked.
            SettingsGroup(String.localized("Usage history")) {
                SettingsRow(
                    String.localized("Token spend reading is off"),
                    subtitle: String.localized("This history comes from the usage records on this Mac, which Pulse reads only while Token spend reading is on."),
                    symbol: "arrow.up.right.square"
                ) {
                    Button(String.localized("Open Token spend"), action: openTokenSpend)
                }
            }
        } else if let ledger = history.ledgers[account.provider], !ledger.days.isEmpty {
            AccountUsageCard(
                provider: account.provider,
                ledger: ledger,
                credits: account.provider == .codex ? history.codexAccount : nil,
                isReading: history.loadingHistory == account.provider
            )
        } else {
            SettingsGroup(String.localized("Usage history")) {
                SettingsRow(
                    history.loadingHistory == account.provider
                        ? Self.loadingHistoryTitle(for: account.provider)
                        : String.localized("No history yet"),
                    subtitle: history.loadingHistory == account.provider
                        ? nil
                        : Self.emptyHistoryReason(
                            for: account.provider,
                            read: history.historyReads[account.provider]
                        )
                ) {
                    if history.loadingHistory == account.provider {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    /// Both halves of the empty state have to name the **right** source.
    ///
    /// A history read from the provider's own statistics has nothing to do
    /// with this Mac, and saying "nothing has been logged on this Mac" about
    /// it sends somebody looking for a log directory that was never going to
    /// exist. Whether the source is this Mac (`CardHistorySource.readsThisMac`:
    /// the CLIs' transcripts and the agents that borrow a provider's mark) is
    /// the question, not `providesHistory`: the latter is true for every source.
    ///
    /// The two original sentences are claims about the account, and neither is
    /// one Pulse can make until a read has actually answered. A read that
    /// failed, or that Pulse chose not to make, says that instead; one that
    /// has not happened *yet* says nothing at all.
    private static func emptyHistoryReason(for provider: Provider, read: ZaiUsageService.HistoryRead?) -> String? {
        // Nothing read yet, so nothing may be said about the account. This is
        // the first frame of a pane, before `.task` has even set the spinner.
        guard let read else { return nil }

        switch read {
        case .failed:
            return .localized("\(provider.displayName) didn't answer, so there is nothing to chart yet. Try again in a moment.")
        case .notConfigured:
            return .localized("Add a key above and Pulse can read this account's history.")
        case .notAsked:
            return .localized("This account is switched off, so Pulse hasn't asked for its history.")
        case .answered:
            break
        }

        return readsThisMac(provider)
            ? .localized("Nothing has been logged on this Mac yet, so there is no history to add up.")
            : .localized("This account hasn't used anything yet, so there is nothing to chart.")
    }

    private static func loadingHistoryTitle(for provider: Provider) -> String {
        readsThisMac(provider)
            ? .localized("Reading logs")
            : .localized("Asking \(provider.displayName)")
    }

    private static func readsThisMac(_ provider: Provider) -> Bool {
        provider.cardHistory?.readsThisMac ?? false
    }
}
