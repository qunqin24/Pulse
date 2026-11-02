// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// The credential typed or read for the provider whose pane is open: the key
/// field, whether it shows what is in it, what the last look through the
/// browsers found, and the two actions that put a credential on disk.
///
/// The shell holds it, because a browser read can outlive the pane that
/// started it (the keychain dialog may stay up while somebody changes pane)
/// and its result is checked against the pane that is showing by then.
@MainActor
@Observable
final class ProviderCredentialModel {
    private let store: UsageStore
    private let settings: AppSettings
    private let navigation: SettingsNavigation
    private let history: AccountHistoryModel

    init(store: UsageStore, settings: AppSettings, navigation: SettingsNavigation, history: AccountHistoryModel) {
        self.store = store
        self.settings = settings
        self.navigation = navigation
        self.history = history
    }

    /// The key field's contents. Seeded from the store when the pane opens;
    /// the store is a file, not something SwiftUI can observe.
    var apiKey = ""
    /// Whether the key field shows what is in it. Hidden again whenever
    /// another pane opens, so a key shown once is not left on screen.
    var revealsKey = false
    var savedKey = ""
    /// What the last look through the browsers found.
    var sessionMessage: String?

    /// The account pane opened, or its account or its switch changed: what the
    /// store holds is what the field shows.
    func seed(for account: AccountKey) {
        let shown = account.provider
        revealsKey = false
        // Copilot has no key field, but its token lives in the same store
        // and the pane needs to know whether there is one.
        guard settings.isEnabled(account), account.isPrimary,
              shown.usesAPIKey || shown == .copilot else {
            apiKey = ""
            savedKey = ""
            return
        }
        apiKey = APIKeyStore.key(for: shown, slot: settings.keySlot(for: shown)) ?? ""
        savedKey = apiKey
    }

    /// Changing a site discards the saved session, which belongs to the other
    /// host; this is what follows the discard.
    func forgetSession(of provider: Provider, for account: AccountKey) {
        guard APIKeyStore.setKey(nil, for: provider) else { return }
        apiKey = ""
        savedKey = ""
        sessionMessage = nil
        store.loadAPIKeys()
        store.refresh(account)
    }

    /// Finds this provider's session in whichever browser signed in.
    ///
    /// The default browser leads, because that is where the session actually
    /// is — another browser may hold one months out of date, and finding that
    /// is worse than the keychain asking. Whatever turns up goes through the
    /// provider's own filter before it is kept, so only the cookies that
    /// actually authenticate ever reach the store; everything else read along
    /// the way is discarded unseen.
    func readSession(for account: AccountKey) {
        // Devin's credential is not a cookie and is not saved: the service
        // reads it from the browser on every pass, so this button's job is to
        // say whether there is one to read and where it was found.
        guard account.provider.usesSessionCookie else {
            readBrowserStorage(for: account)
            return
        }

        // Named, that one and no other. Left automatic, the default browser
        // leads and the rest follow.
        let chosen = settings.sessionBrowser(for: account).map { [$0] }
        let browsers = chosen ?? BrowserCookies.present()

        guard !browsers.isEmpty else {
            sessionMessage = BrowserCookies.refusalMessage(BrowserCookies.refused(chosen ?? BrowserCookies.Browser.allCases))
                ?? String.localized("No browser cookie store was found.")
            return
        }

        Task { [self] in
            // Off the main thread: this opens a database or two and may ask
            // the keychain, and the settings window should not freeze while it
            // does.
            // **Which site, and which cookies of it are worth keeping.** Two
            // providers read a session now, and the normalizer is the thing
            // that decides what leaves the browser — a shared one that kept
            // everything it found would forward whichever cookie either site
            // adds next.
            //
            // **Exhaustive, no `default`.** A fall-through would hand the next
            // provider added Ollama's host and Ollama's filter, and it would
            // find nothing and say so in that provider's own pane — the
            // failure `Provider.soleRoute` was made exhaustive to prevent,
            // where Grok's pane described Antigravity's language server.
            let host: String
            let keep: @Sendable (String) -> String?
            if let written = account.provider.handWritten {
                switch written {
                case .ollamaCloud:
                    host = "ollama.com"
                    keep = { try? OllamaSessionCookie.normalize($0) }
                case .xiaomiMiMo:
                    host = XiaomiMiMoClient.host
                    keep = { try? XiaomiMiMoCookie.normalize($0) }
                // The chosen site's host and no other: `qoder.com.cn`'s session
                // is not `qoder.com`'s, and is never read on its behalf.
                case .qoder:
                    host = settings.qoderSite.host
                    keep = { try? QoderCookie.normalize($0) }
                // Likewise StepFun: the chosen console's host only.
                case .stepFun:
                    host = settings.stepFunSite.host
                    keep = { try? StepFunCookie.normalize($0) }
                case .claudeCode, .codex, .kiro, .antigravity, .cursor, .openCodeGo,
                     .kimiCode, .zai, .glmCoding, .minimax, .copilot,
                     .grok, .grokBot, .volcengine, .commandCode, .deepSeek, .devin,
                     .sub2api, .newAPI, .v2ex, .pulseExtension:
                    // Not session-based: `readSession` sends those to
                    // `readBrowserStorage` before it gets here.
                    return
                }
            } else {
                // The profile names the host and the cookies worth keeping.
                guard case .sessionCookie(let profileHost, let cookies) = account.provider.profile?.credential
                else { return }
                host = profileHost
                keep = { ProviderProfile.keep($0, cookies: cookies) }
            }

            let found = await Task.detached(priority: .userInitiated) {
                BrowserCookies.session(forHost: host, allowing: browsers, keep: keep)
            }.value

            if let found {
                guard APIKeyStore.setKey(found.header, for: account.provider) else { return }
                store.loadAPIKeys()
                store.refresh(account)
                // The keychain dialog may outlive the pane that opened it.
                if navigation.pane == .account(account) {
                    apiKey = found.header
                    savedKey = found.header
                    sessionMessage = String.localized("Read from \(found.browser.name).")
                }
                return
            }

            // A store macOS kept shut is said as that, not as a missing
            // sign-in (issue #101).
            let refused = await Task.detached(priority: .userInitiated) {
                BrowserCookies.refused(chosen ?? BrowserCookies.Browser.allCases)
            }.value
            if navigation.pane == .account(account), let message = BrowserCookies.refusalMessage(refused) {
                sessionMessage = message
                return
            }

            if navigation.pane == .account(account) {
                // Named per provider for the same reason the switch above is
                // exhaustive: a shared sentence would send somebody to the
                // wrong site.
                sessionMessage = switch account.provider {
                case .xiaomiMiMo:
                    String.localized("No Xiaomi session found. Sign in at platform.xiaomimimo.com first.")
                case .qoder:
                    String.localized("No Qoder session found. Sign in at \(settings.qoderSite.host) first.")
                case .stepFun:
                    String.localized("No StepFun session found. Sign in at \(settings.stepFunSite.host) first.")
                case _ where account.provider.profile != nil:
                    String.localized("No session found. Sign in at \(host) first.")
                default:
                    String.localized("No Ollama session found. Sign in at ollama.com first.")
                }
            }
        }
    }

    /// Devin: look now, say what was found, and ask for a refresh.
    ///
    /// **Nothing is stored.** A saved copy would be a second place for the
    /// session to go stale and the one that cannot renew itself; reading it
    /// each pass costs about forty milliseconds and is always current.
    private func readBrowserStorage(for account: AccountKey) {
        let chosen = settings.sessionBrowser(for: account)
        guard !(chosen.map { [$0] } ?? ChromiumLocalStorage.present()).isEmpty else {
            sessionMessage = String.localized("No Chromium browser was found.")
            return
        }

        // A profiled provider's sign-in is saved like a pasted key, because
        // its fetch reads the credential it is handed and never the browser.
        if case .browserStorage(let origin, let keys) = account.provider.profile?.credential {
            Task { [self] in
                let found = await Task.detached(priority: .userInitiated) {
                    ChromiumLocalStorage.find(
                        origin: origin,
                        in: chosen.map { [$0] } ?? ChromiumLocalStorage.present(),
                        accept: { ProviderProfile.storageCredential(from: $0, keys: keys) != nil }
                    )
                }.value
                guard let found, let credential = ProviderProfile.storageCredential(from: found.values, keys: keys),
                      APIKeyStore.setKey(credential, for: account.provider)
                else {
                    if navigation.pane == .account(account) {
                        let host = URL(string: origin)?.host() ?? origin
                        sessionMessage = String.localized("No session found. Sign in at \(host) first.")
                    }
                    return
                }
                store.loadAPIKeys()
                store.refresh(account)
                if navigation.pane == .account(account) {
                    apiKey = credential
                    savedKey = credential
                    sessionMessage = String.localized("Read from \(found.browser.name).")
                }
            }
            return
        }

        Task { [self] in
            // Off the main thread: it opens every table in a browser profile's
            // storage, and the settings window should not freeze while it does.
            let found = await Task.detached(priority: .userInitiated) {
                DevinUsageService.fromBrowser(chosen)
            }.value

            guard navigation.pane == .account(account) else { return }
            guard let found else {
                sessionMessage = String.localized("No Devin session found. Sign in at app.devin.ai first.")
                return
            }

            sessionMessage = String.localized("Read from \(found.browser.name).")
            store.refresh(account)
        }
    }

    func saveKey(for account: AccountKey) {
        // Only call it saved if it was. Otherwise the Save button greys out
        // over a key that never reached disk.
        guard APIKeyStore.setKey(apiKey, for: account.provider, slot: settings.keySlot(for: account.provider)) else { return }
        savedKey = apiKey
        // The store keeps keys for the life of the launch, so it has to be
        // told; otherwise the key is saved and nothing uses it until restart.
        store.loadAPIKeys()
        // And a key is only worth entering if something tries it now.
        store.refresh(account)
        // Including the history, which otherwise keeps saying there is no key
        // until the pane is left and come back to.
        Task { [self] in await history.load() }
    }
}
