// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Where a provider's figures come from, plus anything that route needs
/// setting up.
///
/// **Not drawn when it would be empty.** An added account of a provider
/// with one route has nothing here: no picker, no key field, and the
/// route row below is the primary account's. Drawn anyway it is a
/// "Connection" heading over an empty box, which reads as a control that
/// failed to load rather than as a section with nothing to say.
struct AccountConnectionGroup: View {
    let account: AccountKey
    let store: UsageStore
    let settings: AppSettings
    @Bindable var credentials: ProviderCredentialModel
    let signIn: ProviderSignInModel
    let repairs: ConnectionRepairModel
    let fields: AccountEntryFields
    /// The pane's scroll position, for the remedy that sends the reader to a
    /// field further down.
    let scroll: ScrollViewProxy

    @FocusState private var credentialFocused: Bool
    @FocusState private var addressFocused: Bool

    @ViewBuilder
    var body: some View {
        if hasConnectionControls {
            group
                // A remedy that names the key or the address brings the reader
                // to it and puts the cursor there.
                .onChange(of: repairs.connectionFocusRequest) {
                    scroll.scrollTo("connection", anchor: .top)
                    credentialFocused = true
                }
                .onChange(of: repairs.addressFocusRequest) {
                    scroll.scrollTo("connection", anchor: .top)
                    addressFocused = true
                }
        }
    }

    private var group: some View {
        let source = settings.source(for: account)

        return SettingsGroup(String.localized("Connection")) {
            // A account.provider with a single route gets told, not asked. A picker
            // with one entry is a control that cannot do anything.
            if account.isPrimary, account.provider.hasSourceChoice {
                SettingsRow(
                    String.localized("Read usage from"),
                    subtitle: source.detail(for: account.provider),
                    symbol: "point.3.connected.trianglepath.dotted"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.source(for: account) },
                        set: { settings.setSource($0, for: account) }
                    )) {
                        // A route this Mac cannot take is a choice whose only
                        // outcome is an error — the same rule the browser list
                        // follows. A route already *pinned* is still offered,
                        // so deleting the desktop app says so on the card
                        // rather than silently switching to another route.
                        // Claude's desktop route only: Antigravity's desktop
                        // app is asked whether it is installed or not.
                        ForEach(UsageSource.options(for: account).filter {
                            $0 != .desktopApp || account.provider != .claudeCode
                                || ClaudeDesktopSession.isAvailable || source == .desktopApp
                        }) { option in
                            Text(option.title(for: account.provider)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            } else if account.provider == .copilot {
                // A sign-in, not a pasted token. The endpoint would accept the
                // one `gh` holds, but that carries `repo` and `workflow` — the
                // run of someone's source code, handed over to draw a
                // percentage. This asks for `read:user`.
                SettingsRow(
                    String.localized("GitHub account"),
                    subtitle: signIn.githubError
                        ?? (credentials.savedKey.isEmpty
                            ? String.localized("Opens GitHub's own page. Pulse asks to read your profile, nothing else.")
                            : String.localized("Signed in. Pulse holds a read-only token for this Mac.")),
                    symbol: "person.crop.circle"
                ) {
                    if signIn.githubTask != nil {
                        Button(String.localized("Cancel")) { signIn.endGitHubSignIn() }
                    } else if credentials.savedKey.isEmpty {
                        Button(String.localized("Sign in…")) { signIn.startGitHubSignIn() }
                    } else {
                        Button(String.localized("Sign out")) { signIn.signOutOfGitHub(account: account) }
                    }
                }

                // While it waits, the code is the whole interaction: it is
                // typed on GitHub's page, not here.
                if let githubPrompt = signIn.githubPrompt {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Code"),
                        subtitle: String.localized("Copied — paste it on the page that opened."),
                        symbol: "number"
                    ) {
                        HStack(spacing: 10) {
                            Text(githubPrompt.userCode)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)

                            Button(String.localized("Copy")) { SettingsClipboard.copy(githubPrompt.userCode) }

                            Button(String.localized("Open page")) {
                                NSWorkspace.shared.open(githubPrompt.verificationURL)
                            }
                        }
                    }
                }
            }

            // **Its own `if`, not the tail of that chain.** A provider can want
            // both a route picker *and* a credential — Volcengine does: the
            // `arkcli` route needs nothing pasted and the signed-endpoint route
            // needs an access key pair. Chained behind `hasSourceChoice` the
            // field was never drawn at all, so the endpoint route it belongs to
            // could not be configured from Settings by any means. A divider
            // where both are shown, and none where the picker was not.
            if account.provider.hasSourceChoice, account.provider.usesAPIKey {
                SettingsRowDivider()
            }

            // **Above the key, because it is asked first.** Nothing can be
            // sent anywhere until Pulse knows where, and a key field at the
            // top of a pane for a self-hosted service is a step out of order.
            if account.provider.usesServerAddress {
                ServerAddressRow(account: account, settings: settings, fields: fields, focus: $addressFocused)
                SettingsRowDivider()
            }

            // Above the session for the same reason: which site decides which
            // cookies the browser is asked for.
            if account.provider == .qoder {
                QoderSiteRow(account: account, settings: settings, credentials: credentials)
                SettingsRowDivider()
            }
            if account.provider == .stepFun {
                StepFunSiteRow(account: account, settings: settings, credentials: credentials)
                SettingsRowDivider()
            }
            // Above the key: which site decides which key the field holds.
            if account.provider == .minimax {
                MiniMaxSiteRow(account: account, settings: settings, credentials: credentials)
                SettingsRowDivider()
            }

            if account.provider.usesAPIKey {
                // Takes precedence over the key OpenCode saved for itself —
                // see OpenCodeGoUsageService for why that way round.
                // What this provider wants is not always a key. Ollama has no
                // quota API, so the figures come from its signed-in settings
                // page and a browser session is the only credential there is —
                // calling it an API key would send people looking for one that
                // does not exist.
                SettingsRow(
                    account.provider.usesSessionCookie
                        ? String.localized("Session cookie")
                        : account.provider.profile != nil && account.provider.readsBrowserStorage
                        ? String.localized("Browser session")
                        : account.provider.usesKeyPair
                            ? String.localized("Access keys")
                            // Devin's is a token *and* an organization, and
                            // calling it an API key sends people looking for a
                            // page that issues one. There isn't one.
                            : account.provider == .devin
                                ? String.localized("Token and organization")
                                : String.localized("API key"),
                    subtitle: Self.keySubtitle(for: account.provider, minimaxSite: settings.minimaxSite),
                    symbol: "key"
                ) {
                    HStack(spacing: 8) {
                        Group {
                            if credentials.revealsKey {
                                TextField("", text: $credentials.apiKey)
                            } else {
                                SecureField("", text: $credentials.apiKey)
                            }
                        }
                        .focused($credentialFocused)
                        .textFieldStyle(.roundedBorder)
                        // Narrower by the eye's button, so the row is as wide
                        // as it was and Save is not squeezed.
                        .frame(width: SettingsLayout.controlWidth - 44)
                        .onSubmit { credentials.saveKey(for: account) }

                        Button {
                            credentials.revealsKey.toggle()
                        } label: {
                            Image(systemName: credentials.revealsKey ? "eye.slash" : "eye")
                                .frame(width: 16)
                        }
                        .help(credentials.revealsKey ? String.localized("Hide") : String.localized("Show"))
                        .accessibilityLabel(credentials.revealsKey ? String.localized("Hide") : String.localized("Show"))

                        Button(String.localized("Save")) { credentials.saveKey(for: account) }
                            .disabled(credentials.apiKey == credentials.savedKey)
                            .fixedSize()
                    }
                }

                // Only where a browser session *is* the credential. Every
                // other provider borrows a login its own tool stored, and none
                // of them should be going through anybody's cookies to do it.
                if account.provider.readsBrowserStorage {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Read from browser"),
                        // Says which one it will open, and that it may ask —
                        // Chromium keeps its cookies under a key in the login
                        // keychain, and being told a second before the dialog
                        // appears is the difference between a step and a scare.
                        subtitle: credentials.sessionMessage
                            ?? Self.browserHint(settings.sessionBrowser(for: account), for: account.provider),
                        symbol: "globe"
                    ) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { settings.sessionBrowser(for: account) },
                                set: {
                                    settings.setSessionBrowser($0, for: account)
                                    credentials.sessionMessage = nil
                                }
                            )) {
                                Text(Self.defaultBrowserLabel(for: account.provider)).tag(BrowserCookies.Browser?.none)

                                // Only what is actually installed. A browser
                                // that isn't there is a choice that can only
                                // fail.
                                // Devin's is in a LevelDB, which only the
                                // Chromium browsers keep — offering Safari or
                                // Firefox there is a choice that cannot work.
                                ForEach(account.provider.usesSessionCookie
                                    ? BrowserCookies.present()
                                    : ChromiumLocalStorage.present()) { browser in
                                    Text(browser.name).tag(BrowserCookies.Browser?.some(browser))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)

                            Button(String.localized("Read")) { credentials.readSession(for: account) }
                        }
                    }
                }
            } else {
                // One route, so it is stated rather than offered — but what
                // that route is differs: a server one of them runs while it is
                // open, a login the others already saved. The wording belongs
                // to the provider (`Provider.soleRoute`), where the switch is
                // exhaustive: this was a ternary that gave every provider but
                // Cursor Antigravity's sentence.
                // Primary only. What this row names is the login the
                // provider's own tool stored, and an account Pulse signed in
                // to itself does not use it — `fetchAdded` goes straight over
                // HTTP with the token Pulse holds. Stating the CLI's route
                // there would name a credential this account never touches.
                if account.isPrimary, let route = account.provider.soleRoute {
                    SettingsRow(String.localized("Read usage from"), subtitle: route.note, symbol: "point.3.connected.trianglepath.dotted") {
                        Text(route.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    }
                }
            }

            // Every API account that reports money, as DeepSeek's did first:
            // the ring has no denominator until one of three is chosen.
            if fields.hasBalanceRing(account) {
                SettingsRowDivider()
                BalanceBasisRow(account: account, settings: settings)
                if settings.balanceBasis(for: account) == .budget {
                    SettingsRowDivider()
                    BalanceBudgetRow(account: account, fields: fields)
                }
            }

            // The status line has to be registered before it can report
            // anything, so the control for that follows the choice that needs
            // it.
            if account.isPrimary, account.provider == .claudeCode, source != .endpoint {
                SettingsRowDivider()
                ClaudeCodeStatusLineRow(store: store, repairs: repairs)
            }
        }
    }

    /// Whether the card has anything to put in it — the same
    /// four questions it asks, answered before the heading is drawn.
    private var hasConnectionControls: Bool {
        guard account.isPrimary else { return false }
        if account.provider.hasSourceChoice { return true }
        if account.provider == .copilot { return true }
        if account.provider.usesAPIKey { return true }
        return account.isPrimary && account.provider.soleRoute != nil
    }

    /// What to say under the key field.
    ///
    /// Usually just where it is kept — but z.ai and GLM are one company's two
    /// storefronts, and a key from the wrong console is refused with no hint
    /// as to why, so those two name the site instead of leaving the user to
    /// guess which of the two they signed up for.
    private static func keySubtitle(for provider: Provider, minimaxSite: MiniMaxSite) -> String {
        switch provider {
        case _ where provider.profile?.keySubtitle != nil:
            provider.profile?.keySubtitle?() ?? ""
        case _ where provider.usesSessionCookie:
            .localized("Copied from your browser. Stored encrypted on this Mac.")
        case .zai:
            .localized("From z.ai. Stored encrypted on this Mac.")
        case .glmCoding:
            .localized("From bigmodel.cn. Stored encrypted on this Mac.")
        // The key field is the chosen site's: each keeps its own.
        case .minimax where minimaxSite == .china:
            .localized("From platform.minimaxi.com. Stored encrypted on this Mac.")
        case .minimax:
            .localized("From platform.minimax.io. Stored encrypted on this Mac.")
        // The one field holding two secrets. Says the format, because a pair
        // pasted the wrong way round fails as a signature mismatch — a 403
        // with nothing in it to suggest what went wrong.
        case .volcengine:
            .localized("AccessKeyID:SecretAccessKey, from Volcengine. Optional — arkcli needs none. Stored encrypted on this Mac.")
        // Optional, like Volcengine's: `cmd login` already leaves a key
        // Pulse can read, and this field is for anyone whose account is signed
        // in somewhere other than this Mac.
        case .commandCode:
            .localized("From commandcode.ai. Optional — Pulse can use the login Command Code saved. Stored encrypted on this Mac.")
        case .deepSeek:
            .localized("From platform.deepseek.com. Stored encrypted on this Mac.")
        // A group key from whoever runs the deployment, not an account
        // password — and it is only ever sent to the address in the row above.
        case .sub2api:
            .localized("A group API key from your sub2api deployment. Sent only to the address above. Stored encrypted on this Mac.")
        // The same `sk-` key already in the reader's client config — there is
        // no second credential to go and find.
        case .newAPI:
            .localized("The same key your AI client uses for this gateway. Sent only to the address above. Stored encrypted on this Mac.")
        case .v2ex:
            .localized("A Personal Access Token from v2ex.com. Stored encrypted on this Mac.")
        // Two values in one field, because the quota path is scoped by an
        // organisation and nothing on this Mac carries one. Optional, like
        // Volcengine's: without it Pulse reads the plan Devin's own app saved.
        case .devin:
            .localized("A Bearer token from app.devin.ai, then a space, then your organization. Optional — Pulse can read what Devin's app saved. Stored encrypted on this Mac.")
        default:
            .localized("Stored encrypted on this Mac.")
        }
    }

    /// Names the browser about to be opened, and warns when opening it will
    /// ask for the keychain.
    private static func browserHint(_ chosen: BrowserCookies.Browser?, for provider: Provider) -> String {
        // A `localStorage` entry is not encrypted, so nothing is ever asked
        // for and the hint must not say it might be.
        guard provider.usesSessionCookie else {
            guard let browser = chosen ?? defaultBrowser(for: provider) else {
                return String.localized("Pulse can't read your default browser. Choose a browser from the list.")
            }
            return String.localized("Only \(browser.name).")
        }

        // Named, it is the only one opened — the rest are not tried, so a
        // failure is reported rather than answered from a browser the user
        // never signed in to. That is the same bargain `UsageSource` makes.
        // Default browser is one browser too: the rest are not tried.
        guard let browser = chosen ?? defaultBrowser(for: provider) else {
            return String.localized("Pulse can't read your default browser. Choose a browser from the list.")
        }
        return browser.promptsForKeychain
            ? String.localized("Only \(browser.name). It will ask for the keychain.")
            : String.localized("Only \(browser.name).")
    }

    /// This Mac's default browser, when Pulse can read this provider's
    /// sign-in from it: any browser for a cookie, a Chromium one for Devin's
    /// `localStorage`.
    private static func defaultBrowser(for provider: Provider) -> BrowserCookies.Browser? {
        BrowserCookies.defaultOnly(
            among: provider.usesSessionCookie ? BrowserCookies.present() : ChromiumLocalStorage.present()
        ).first
    }

    /// The first entry of the browser menu: "Default browser", with its name
    /// when Pulse can read it.
    private static func defaultBrowserLabel(for provider: Provider) -> String {
        guard let browser = defaultBrowser(for: provider) else { return String.localized("Default browser") }
        return String.localized("Default browser (\(browser.name))")
    }
}
