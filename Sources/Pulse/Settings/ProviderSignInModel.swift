// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Observation

/// Signing in from Settings: another subscription of a provider that can have
/// more than one (the browser flow, or a device code), and Copilot's own
/// GitHub sign-in.
///
/// The shell holds it, not a pane. A device-code sign-in polls for fifteen
/// minutes, and the Cancel button, the code and the error have to be where
/// the reader left them when they come back to the provider's pane.
@MainActor
@Observable
final class ProviderSignInModel {
    private let store: UsageStore
    private let settings: AppSettings
    private let navigation: SettingsNavigation
    private let credentialModel: ProviderCredentialModel

    init(store: UsageStore, settings: AppSettings, navigation: SettingsNavigation, credentials: ProviderCredentialModel) {
        self.store = store
        self.settings = settings
        self.navigation = navigation
        self.credentialModel = credentials
    }

    /// The provider a browser sign-in is currently open for, which account row
    /// started it (`nil` for "Add another account"), and what went wrong with
    /// the last one.
    var signingIn: Provider?
    var signingInTarget: AccountKey?
    var signInError: (provider: Provider, target: AccountKey?, message: String)?
    /// The providers whose **first** account Pulse can sign in to itself, from
    /// a row in its Connection card: Grok Bot (a Cursor web login, in place of
    /// the editor's) and JetBrains AI (a JetBrains account, for the quota the
    /// IDE no longer saves). Kept under `AccountKey(provider)`.
    nonisolated static let primarySignIns: Set<Provider> = [.grokBot, .jetBrainsAI]
    /// Which of those hold a login Pulse signed in to.
    private(set) var primaryLogins: Set<Provider> = []
    /// Shown while a device-code sign-in is waiting: the code the provider
    /// gave, and where to type it.
    var devicePrompt: OAuthLogin.DevicePrompt?
    /// Copilot's own sign-in, which is GitHub's device flow rather than the
    /// one the added-account button drives.
    var githubPrompt: GitHubDeviceLogin.Prompt?
    var githubTask: Task<Void, Never>?
    var githubError: String?
    /// Held so it can be called off. A device-code sign-in polls for fifteen
    /// minutes, and a sign-in that failed in the browser gives this side no
    /// sign at all — without a way out the button stays disabled for the whole
    /// quarter of an hour.
    var signInTask: Task<Void, Never>?

    /// Whether a sign-in of either kind is running, which holds the
    /// diagnostics' own sign-in remedy back.
    var isBusy: Bool { signingIn != nil || githubTask != nil }

    func hasPrimaryLogin(_ provider: Provider) -> Bool { primaryLogins.contains(provider) }

    func isSigningInPrimary(_ provider: Provider) -> Bool {
        signingIn == provider && signingInTarget == AccountKey(provider)
    }

    func primaryError(_ provider: Provider) -> String? {
        guard let signInError,
              signInError.provider == provider,
              signInError.target == AccountKey(provider)
        else { return nil }
        return signInError.message
    }

    func isSigningInAccountsRow(for account: AccountKey) -> Bool {
        guard signingIn == account.provider else { return false }
        return account.isPrimary ? signingInTarget == nil : signingInTarget == account
    }

    func accountsRowError(for account: AccountKey) -> String? {
        guard let signInError, signInError.provider == account.provider else { return nil }
        let matches = account.isPrimary ? signInError.target == nil : signInError.target == account
        return matches ? signInError.message : nil
    }

    /// Reads whether a primary account holds a Pulse-managed login, skipping
    /// storage altogether while the account is switched off.
    func seed(for account: AccountKey) {
        let provider = account.provider
        guard Self.primarySignIns.contains(provider), account == AccountKey(provider) else { return }
        guard settings.isEnabled(account), AccountCredentialStore.credentials(for: account) != nil else {
            primaryLogins.remove(provider)
            return
        }
        primaryLogins.insert(provider)
    }

    /// Forgets a primary account's login: Grok Bot falls back to Cursor's
    /// local database, JetBrains AI to the IDE's file.
    func signOutOfPrimary(_ provider: Provider) {
        let primary = AccountKey(provider)
        guard AccountCredentialStore.set(nil, for: primary) else { return }
        primaryLogins.remove(provider)
        if signInError?.provider == provider, signInError?.target == primary {
            signInError = nil
        }
        store.resetReading(for: primary)
    }

    /// The Cancel on an added account's sign-in.
    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signingIn = nil
        signingInTarget = nil
        devicePrompt = nil
    }

    /// Copilot's Sign out: forgets the token and asks for a fresh reading.
    func signOutOfGitHub(account: AccountKey) {
        _ = APIKeyStore.setKey(nil, for: .copilot)
        credentialModel.apiKey = ""
        credentialModel.savedKey = ""
        githubError = nil
        store.loadAPIKeys()
        store.refresh(account)
    }

    /// GitHub's device flow, for Copilot's quota.
    func startGitHubSignIn() {
        githubError = nil
        githubTask = Task { [self] in
            defer {
                // Only the attempt still on screen clears the pane; a cancelled
                // one has already had its state cleared by the button.
                if !Task.isCancelled {
                    githubTask = nil
                    githubPrompt = nil
                }
            }
            do {
                let prompt = try await GitHubDeviceLogin.start()
                githubPrompt = prompt
                // The clipboard is the whole convenience here: GitHub will not
                // pre-fill its field from a link, deliberately, because that is
                // the device-code phishing attack. A paste still leaves the
                // consent where it belongs.
                SettingsClipboard.copy(prompt.userCode)
                NSWorkspace.shared.open(prompt.verificationURL)

                let token = try await GitHubDeviceLogin.awaitToken(prompt)
                try Task.checkCancellation()
                guard APIKeyStore.setKey(token, for: .copilot) else {
                    githubError = String.localized("Couldn't save the login on this Mac.")
                    return
                }
                if navigation.pane == .account(AccountKey(.copilot)) {
                    credentialModel.apiKey = token
                    credentialModel.savedKey = token
                }
                store.loadAPIKeys()
                store.refresh(AccountKey(.copilot))
            } catch let failure as GitHubDeviceLogin.Failure {
                if !Task.isCancelled { githubError = failure.message }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { githubError = String.localized("Sign-in was cancelled.") }
            }
        }
    }

    func endGitHubSignIn() {
        githubTask?.cancel()
        githubTask = nil
        githubPrompt = nil
        githubError = nil
    }

    /// Runs the browser sign-in, then keeps whatever came back.
    func signIn(to provider: Provider, replacing existing: AccountKey? = nil) {
        signingIn = provider
        signingInTarget = existing
        signInError = nil

        signInTask = Task { [self] in
            defer {
                // Only an attempt that is still the one on screen clears the
                // pane. A cancelled one has already had its state cleared by
                // the button that cancelled it, and by the time it unwinds the
                // user may well have started another — which would otherwise
                // lose its Cancel button and its code to a sign-in nobody is
                // waiting for any more.
                if !Task.isCancelled {
                    signingIn = nil
                    signingInTarget = nil
                    devicePrompt = nil
                    signInTask = nil
                }
            }
            do {
                let credentials: AccountCredentials
                if provider == .grokBot {
                    // Cursor has no OAuth for a third party to drive: its page
                    // takes a challenge and a nonce and the tokens are polled
                    // for afterwards. Nothing comes back to this Mac and there
                    // is no code to type, so this branch shows neither.
                    credentials = try await CursorWebLogin.signIn()
                } else if provider == .jetBrainsAI {
                    // The Junie CLI's browser sign-in, back to a loopback port.
                    credentials = try await JetBrainsLogin.signIn()
                } else if OAuthLogin.usesDeviceCode(provider) {
                    // A code shown on the provider's own page. No local
                    // port to collide with the CLI's sign-in, and nothing
                    // redirected back to this Mac. Whether the page fills the
                    // code in itself is the provider's decision — GitHub and
                    // OpenAI send no pre-filled link, xAI does — so the code
                    // goes on the clipboard either way and the row's subtitle
                    // follows `DevicePrompt.prefilled`.
                    let prompt = try await OAuthLogin.startDevice(provider)
                    devicePrompt = prompt
                    // On the clipboard the moment it exists, like GitHub's. The
                    // same reason applies here: neither page will pre-fill from
                    // a link, so a paste is the shortest honest route.
                    SettingsClipboard.copy(prompt.userCode)
                    NSWorkspace.shared.open(prompt.verificationURL)
                    credentials = try await OAuthLogin.awaitDevice(prompt, for: provider)
                } else {
                    credentials = try await OAuthLogin.signIn(to: provider)
                }
                // Seeded from whatever the provider said about the account, so
                // two subscriptions are not both offered as "Codex".
                try Task.checkCancellation()
                if let existing, !settings.allAccounts.contains(existing) { return }
                let added = existing ?? settings.addAccount(provider, label: Self.label(for: credentials, provider: provider, in: settings))
                guard AccountCredentialStore.set(credentials, for: added) else {
                    if existing == nil { settings.removeAccount(added) }
                    signInError = (provider, existing, String.localized("Couldn't save the login on this Mac."))
                    return
                }
                if Self.primarySignIns.contains(provider), added == AccountKey(provider) {
                    primaryLogins.insert(provider)
                    store.resetReading(for: added)
                } else {
                    store.refresh(added)
                }
                navigation.pane = .account(added)
            } catch let failure as OAuthLogin.Failure {
                if !Task.isCancelled { signInError = (provider, existing, failure.message) }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { signInError = (provider, existing, String.localized("Sign-in was cancelled.")) }
            }
        }
    }

    /// What to call a newly added account.
    ///
    /// The part of the address before the "@", because the card's header is
    /// one line at a fixed width and a whole email address spends all of it.
    /// A provider that names nothing gets a number, which at least counts.
    /// Either way it is the user's to change.
    private static func label(for credentials: AccountCredentials, provider: Provider, in settings: AppSettings) -> String {
        if let name = credentials.accountName?.split(separator: "@").first, !name.isEmpty {
            return String(name)
        }

        let existing = settings.extraAccounts.filter { $0.provider == provider }.count
        return "\(provider.displayName) \(existing + 2)"
    }
}

/// The system clipboard, for the codes a sign-in puts there and the commands a
/// remedy offers.
enum SettingsClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
