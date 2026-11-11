// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// DeepSeek's second credential: the web console's sign-in, which reads the
/// account's usage day by day — and the balance, when no key is set.
///
/// **Beside the key, never instead of it.** Each has its own slot in the
/// store, so reading one can never clear the other. Read out of a Chromium
/// browser's `localStorage`, which is not encrypted, so no keychain prompt
/// (`DeepSeekConsole.fromBrowser`).
struct DeepSeekConsoleGroup: View {
    let store: UsageStore
    let settings: AppSettings
    /// Tells the pane the sign-in changed, so it shows — or drops — the
    /// account's history below.
    var onSessionChange: () -> Void = {}
    @State private var hasSession = DeepSeekConsole.hasSession
    @State private var message: String?
    @State private var isReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup(String.localized("DeepSeek console")) {
                SettingsRow(
                    String.localized("Account usage"),
                    subtitle: message ?? (hasSession
                        ? String.localized("Kept. The usage history below and the detailed card read the whole account with it.")
                        : Self.hint),
                    symbol: "globe"
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

            Text(localized: "The usage DeepSeek's console keeps for the account — every key and every machine, day by day, and what was charged — and the balance, when no key is set or the key is turned away. Pulse keeps only the console's sign-in, encrypted on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    /// Which browser is about to be read — said before, not after. No
    /// keychain: the sign-in is in `localStorage`, which is not encrypted.
    private static var hint: String {
        guard let first = ChromiumLocalStorage.present().first else {
            return String.localized("Reads Chrome, Edge, Brave, Arc and other Chromium browsers.")
        }
        return String.localized("Starts with \(first.name).")
    }

    private func read() {
        let browsers = ChromiumLocalStorage.present()
        guard !browsers.isEmpty else {
            message = String.localized("No Chromium browser was found. Sign in at platform.deepseek.com in Chrome, Edge, Brave or Arc.")
            return
        }
        isReading = true
        Task {
            // Off the main thread: a LevelDB per browser profile.
            let found = await Task.detached(priority: .userInitiated) {
                DeepSeekConsole.fromBrowser(in: browsers)
            }.value
            isReading = false
            guard let found else {
                message = String.localized("No DeepSeek console sign-in found. Sign in at platform.deepseek.com first.")
                return
            }
            guard APIKeyStore.setKey(found.token, for: .deepSeek, slot: DeepSeekConsole.slot) else { return }
            await DeepSeekConsoleHistory.shared.forget()
            store.loadAPIKeys()
            hasSession = DeepSeekConsole.hasSession
            // Tried at once, so the row says whether it works rather than
            // only that something was stored.
            isReading = true
            let answer = await DeepSeekConsole.balance(token: found.token)
            isReading = false
            switch answer {
            case .success:
                message = String.localized("Read from \(found.browser.name).")
            case .failure(.signedOut):
                message = String.localized("The console turned this sign-in away. Sign in again at platform.deepseek.com, then read it again.")
            case .failure(.failed):
                message = String.localized("Read from \(found.browser.name), but the console didn't answer. It will be tried again on the next refresh.")
            }
            store.refresh(AccountKey(.deepSeek))
            onSessionChange()
        }
    }

    private func remove() {
        APIKeyStore.setKey(nil, for: .deepSeek, slot: DeepSeekConsole.slot)
        Task { await DeepSeekConsoleHistory.shared.forget() }
        store.loadAPIKeys()
        store.refresh(AccountKey(.deepSeek))
        hasSession = DeepSeekConsole.hasSession
        message = nil
        onSessionChange()
    }
}
