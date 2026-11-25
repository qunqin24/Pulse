// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Adding another deployment of a self-hosted gateway, naming it, and getting
/// rid of it (#125).
///
/// `AccountsGroup`'s counterpart for the providers whose added accounts are
/// typed in rather than signed in to (`Provider.addsAccountsByAddress`). There
/// is no page to open and nothing to wait for: adding one puts a new row in
/// the sidebar and opens its pane, whose Connection group asks for the address
/// and the key like the first account's does.
struct GatewayAccountsGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    let navigation: SettingsNavigation

    var body: some View {
        SettingsGroup(String.localized("Accounts")) {
            if account.isPrimary {
                SettingsRow(
                    String.localized("Add another account"),
                    subtitle: String.localized("Another gateway with its own address, key and name."),
                    symbol: "plus.circle"
                ) {
                    Button(String.localized("Add")) {
                        guard let added = settings.addGatewayAccount(account.provider) else { return }
                        navigation.pane = .account(added)
                    }
                }
            } else {
                SettingsRow(String.localized("Name"), symbol: "tag") {
                    TextField("", text: Binding(
                        get: { settings.label(for: account) },
                        set: { settings.rename(account, to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Remove account"),
                    subtitle: String.localized("Forgets its address and key and takes it off the rail."),
                    symbol: "trash"
                ) {
                    Button(String.localized("Remove"), role: .destructive) {
                        guard settings.removeGatewayAccount(account) else { return }
                        store.forgetRemoved(account)
                        navigation.pane = .appearance
                    }
                }
            }
        }
    }
}
