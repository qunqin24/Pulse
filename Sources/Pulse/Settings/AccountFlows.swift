// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The models behind an account's pane, built once and wired to each other.
///
/// One object so the shell holds one thing rather than four, and so how they
/// depend on each other — repair drives sign-in and the browser read, sign-in
/// writes the credential, saving a key asks the history to read again — is
/// written down in one place.
@MainActor
final class AccountFlows {
    let credentials: ProviderCredentialModel
    let signIn: ProviderSignInModel
    let repairs: ConnectionRepairModel
    let fields: AccountEntryFields

    init(
        store: UsageStore,
        settings: AppSettings,
        navigation: SettingsNavigation,
        alerts: UsageAlerts,
        history: AccountHistoryModel
    ) {
        let credentials = ProviderCredentialModel(
            store: store, settings: settings, navigation: navigation, history: history)
        let signIn = ProviderSignInModel(
            store: store, settings: settings, navigation: navigation, credentials: credentials)
        self.credentials = credentials
        self.signIn = signIn
        repairs = ConnectionRepairModel(store: store, signIn: signIn, credentials: credentials)
        fields = AccountEntryFields(store: store, settings: settings, alerts: alerts)
    }

    /// The account pane opened, or its account or its switch changed.
    func seed(for account: AccountKey) {
        credentials.seed(for: account)
        signIn.seed(for: account)
        fields.seed(for: account)
    }
}
