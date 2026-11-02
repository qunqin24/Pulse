// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// OpenCode Go's second credential: the console's signed-in session, which
/// reads the account's request log for the detailed card.
///
/// **Beside the key, never instead of it.** The key answers the plan's limits;
/// this answers the history, and each has its own slot in the store, so
/// reading one can never clear the other. Read from the browser the way the
/// cookie providers' sessions are — the default browser first — and only the
/// two cookies that sign in are kept (`OpenCodeConsole.keep`).
struct OpenCodeConsoleGroup: View {
    let store: UsageStore
    let settings: AppSettings
    /// Tells the pane the session changed, so it shows — or drops — the
    /// account's history below.
    var onSessionChange: () -> Void = {}
    @State private var hasSession = OpenCodeConsole.hasSession
    @State private var message: String?
    @State private var isReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("OpenCode console")) {
                SettingsRow(
                    String.localized("Account request log"),
                    subtitle: [message ?? (hasSession
                        ? String.localized("Kept. The detailed card reads every request on the account with it.")
                        : Self.hint), cardHint].compactMap { $0 }.joined(separator: " ")
                ) {
                    HStack(spacing: 8) {
                        if isReading { ProgressView().controlSize(.small) }
                        if hasSession {
                            Button(String.localized("Remove")) { remove() }
                        }
                        Button(String.localized("Read")) { read() }
                            .disabled(isReading)
                    }
                }
            }

            Text(localized: "The request log OpenCode's console keeps for 30 days — every machine and every app on the account, and what each request cost — and the plan's limits, when no key is set or the key is turned away. Pulse keeps only the console's sign-in cookies, encrypted on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// Where the log will be seen, while that is still switched off: the
    /// card is the only place it shows, and a read that changed nothing on
    /// screen reads as a read that did nothing.
    private var cardHint: String? {
        guard hasSession, !settings.showsDetailedCard(for: AccountKey(.openCodeGo)) else { return nil }
        return String.localized("Turn on Detailed card above to see the request log on the card.")
    }

    /// Which browser is about to be opened, and whether it will ask for the
    /// keychain — said before the dialog, not after.
    private static var hint: String {
        guard let first = BrowserCookies.present().first else {
            return String.localized("Finds it in the browser you signed in with.")
        }
        return first.promptsForKeychain
            ? String.localized("Starts with \(first.name). It will ask for the keychain.")
            : String.localized("Starts with \(first.name).")
    }

    private func read() {
        let browsers = BrowserCookies.present()
        guard !browsers.isEmpty else {
            message = BrowserCookies.refusalMessage(BrowserCookies.refused())
                ?? String.localized("No browser cookie store was found.")
            return
        }
        isReading = true
        Task {
            // Off the main thread: a database or two, and maybe the keychain.
            let found = await Task.detached(priority: .userInitiated) {
                BrowserCookies.session(forHost: OpenCodeConsole.host, allowing: browsers, keep: OpenCodeConsole.keep)
            }.value
            isReading = false
            guard let found else {
                let refused = await Task.detached(priority: .userInitiated) { BrowserCookies.refused() }.value
                message = BrowserCookies.refusalMessage(refused)
                    ?? String.localized("No OpenCode console session found. Sign in at opencode.ai first.")
                return
            }
            guard APIKeyStore.setKey(found.header, for: .openCodeGo, slot: OpenCodeConsole.slot) else { return }
            store.loadAPIKeys()
            hasSession = OpenCodeConsole.hasSession
            // Tried at once, so the row says whether it works rather than
            // only that something was stored.
            isReading = true
            await OpenCodeConsoleWorkspace.shared.forget()
            let resolved = await OpenCodeConsoleWorkspace.shared.resolve(cookie: found.header)
            isReading = false
            switch resolved {
            case .workspace(let workspace):
                message = String.localized("Read from \(found.browser.name) · workspace \(workspace.name ?? workspace.id).")
            case .signedOut:
                message = String.localized("The console turned this session away. Sign in again at opencode.ai, then read it again.")
            case .failed:
                message = String.localized("Read from \(found.browser.name), but the console didn't answer. It will be tried again on the next refresh.")
            }
            // The limits can now be read without a key, and the history below
            // has something to show.
            store.refresh(AccountKey(.openCodeGo))
            onSessionChange()
        }
    }

    private func remove() {
        APIKeyStore.setKey(nil, for: .openCodeGo, slot: OpenCodeConsole.slot)
        store.loadAPIKeys()
        store.refresh(AccountKey(.openCodeGo))
        hasSession = OpenCodeConsole.hasSession
        message = nil
        onSessionChange()
    }
}
