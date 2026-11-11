// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Signing in to another subscription of the same provider, and getting
/// rid of one.
///
/// Only shown where it can work. The other providers are read from a login
/// their own tool stored, and that store holds exactly one — a second
/// account of theirs is not something Pulse can be shown, so offering it
/// would be a control that cannot do anything.
struct AccountsGroup: View {
    let account: AccountKey
    let settings: AppSettings
    let signIn: ProviderSignInModel
    let navigation: SettingsNavigation

    @ViewBuilder
    var body: some View {
        if account.provider.supportsMultipleAccounts {
            SettingsGroup(String.localized("Accounts")) {
                Group {
                    SettingsRow(
                        account.isPrimary ? String.localized("Add another account") : String.localized("Sign in again…"),
                        // The one thing someone should know before they start:
                        // whose name is on the page that opens.
                        subtitle: String.localized("Opens the provider's own sign-in page."),
                        symbol: account.isPrimary ? "plus.circle" : "person.crop.circle"
                    ) {
                        // One sign-in at a time, and its Cancel, code and
                        // error belong to the provider it was started for:
                        // a Codex device code shown on the Claude Code pane
                        // reads as Claude Code asking for it.
                        if signIn.signingIn == account.provider {
                            Button(String.localized("Cancel")) { signIn.cancelSignIn() }
                        } else {
                            Button(String.localized("Sign in…")) {
                                signIn.signIn(to: account.provider, replacing: account.isPrimary ? nil : account)
                            }
                            .disabled(signIn.signingIn != nil)
                        }
                    }

                    // While a device-code sign-in is waiting, the code is the
                    // whole interaction: it is typed on the provider's page,
                    // not here, and nothing comes back to this Mac.
                    if let devicePrompt = signIn.devicePrompt, signIn.signingIn == account.provider {
                        SettingsRowDivider()
                        SettingsRow(
                            String.localized("Code"),
                            // The sign-in half is not decoration: OpenAI's own
                            // hand-off to a Google account fails with
                            // `token_exchange_failed` when the browser has no
                            // session, and this row is the only place that
                            // says so. Which half is said depends on whether
                            // the provider's own link already carries the
                            // code — telling someone to paste on a page that
                            // filled itself in is an instruction to undo.
                            subtitle: devicePrompt.prefilled
                                ? String.localized("Already on the page. Sign in there first if asked, then approve it.")
                                : String.localized("Copied. Sign in there first if asked, then paste it."),
                            symbol: "number"
                        ) {
                            HStack(spacing: 10) {
                                Text(devicePrompt.userCode)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(String.localized("Copy")) { SettingsClipboard.copy(devicePrompt.userCode) }

                                Button(String.localized("Open page")) {
                                    NSWorkspace.shared.open(devicePrompt.verificationURL)
                                }
                            }
                        }
                    }

                    if let signInError = signIn.signInError, signInError.provider == account.provider {
                        SettingsRowDivider()
                        SettingsRow(String.localized("Sign-in"), subtitle: signInError.message, symbol: "exclamationmark.triangle") { EmptyView() }
                    }
                }
                if !account.isPrimary {
                    SettingsRowDivider()
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
                        subtitle: String.localized("Forgets its login and takes it off the rail."),
                        symbol: "trash"
                    ) {
                        Button(String.localized("Remove"), role: .destructive) {
                            AccountCredentialStore.set(nil, for: account)
                            settings.removeAccount(account)
                            navigation.pane = .appearance
                        }
                    }
                }
            }
        }
    }
}
