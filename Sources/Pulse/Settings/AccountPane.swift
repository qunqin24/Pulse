// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// One account's pane: its cards, in order. What each card says and does is in
/// its own view; what outlives the pane (a sign-in under way, what was read of
/// a history) is in the models the shell hands down.
struct AccountPane: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    let navigation: SettingsNavigation
    let history: AccountHistoryModel
    let flows: AccountFlows
    /// For the connection card, which scrolls itself into view when a remedy
    /// names one of its fields.
    let scroll: ScrollViewProxy

    private var provider: Provider { account.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // An extension is never a first account, and what it will do
            // when switched on is exactly what somebody should read first.
            if !settings.isEnabled(account), account.isPrimary || provider == .pulseExtension {
                Text(provider.monitoringAccessDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AccountPanelGroup(account: account, store: store, settings: settings)

            if let pulseExtension = settings.pulseExtension(for: account) {
                ExtensionProgramGroup(pulseExtension: pulseExtension)
            }

            // Claude Code's and Codex's first account: the tool sends as
            // whoever it is signed in as, which is that account.
            if account.isPrimary, WindowPrimer.providers.contains(account.provider), settings.isEnabled(account) {
                WindowStarterGroup(provider: account.provider, settings: settings)
            }

            if !settings.needsProviderSelection {
                AccountConnectionGroup(
                    account: account, store: store, settings: settings,
                    credentials: flows.credentials, signIn: flows.signIn,
                    repairs: flows.repairs, fields: flows.fields, scroll: scroll
                )
                .id("connection")

                ConnectionDiagnosticsView(
                    account: account, store: store, settings: settings,
                    isSigningIn: flows.signIn.isBusy,
                    repairMessage: flows.repairs.messages[account.id],
                    repair: { flows.repairs.repair($0, for: account) }
                )
                .id(account)

                AccountsGroup(
                    account: account, settings: settings,
                    signIn: flows.signIn, navigation: navigation
                )

                AccountLiveUsageGroup(account: account, store: store, settings: settings)

                if provider == .pulseExtension {
                    ExtensionMetricsGroup(account: account, store: store, settings: settings)
                }
            }

            // The service, not the account, so every account of it shows
            // this; a switched-off one fetches nothing.
            if let page = settings.statusPage(for: provider), settings.isEnabled(account) {
                ServiceStatusGroup(page: page)
            }

            // Its own group rather than a row under Connection, which is
            // about credentials and routes. This is a notification, and the
            // general pane's group of them is the wrong home too: the figure
            // is per account, because the providers that report a balance do
            // not price in the same currency.
            if flows.fields.reportsBalance(account) {
                SettingsGroup(String.localized("Notifications")) {
                    LowBalanceRow(account: account, fields: flows.fields)
                }
            }

            // Both are built from the transcripts the CLI leaves behind, so
            // for a provider that keeps none they would be a column of zeroes
            // claiming nothing had been spent — and for an account Pulse
            // signed in to itself they would be worse than that. Those
            // transcripts belong to whichever account the CLI is signed in to,
            // which is not this one, so showing them here would report one
            // account's spending under another's name.
            // OpenCode Go's request log is behind the console's session, a
            // second credential beside the key.
            if provider == .openCodeGo, account.isPrimary, settings.isEnabled(account) {
                OpenCodeConsoleGroup(store: store, settings: settings) { history.consoleRevision += 1 }
            }
            // DeepSeek's usage is behind its console's sign-in in the same way.
            if provider == .deepSeek, account.isPrimary, settings.isEnabled(account) {
                DeepSeekConsoleGroup(store: store, settings: settings) { history.consoleRevision += 1 }
            }

            // Qoder keeps no history on this Mac; the account's own records
            // are its history, in credits (issue #88).
            if provider == .qoder, account.isPrimary, settings.isEnabled(account) {
                QoderCreditsGroup(settings: settings)
            }

            if provider.providesHistory, account.isPrimary {
                // Live, so ahead of the history: which conversations still
                // hold a cache, and for how long — where the logs let it be
                // timed (Claude Code's tier, Codex's model).
                if PromptCacheReading.supports(provider), settings.isEnabled(account) {
                    PromptCacheSessionsGroup(provider: provider)
                }

                // The estimate is money, and money needs the token split only
                // a transcript carries. A provider whose history comes from
                // its own statistics has tokens and nothing to price them
                // with, so the estimate is left off rather than shown at zero.
                if provider.keepsLocalTranscripts {
                    EstimatedValueGroup(account: account, store: store, history: history)
                }

                AccountHistoryGroup(
                    account: account, history: history, settings: settings,
                    openTokenSpend: { navigation.open(.spend) }
                )
            }
        }
        .onChange(of: "\(account.id)|\(settings.isEnabled(account))", initial: true) { _, _ in
            flows.seed(for: account)
        }
    }
}
