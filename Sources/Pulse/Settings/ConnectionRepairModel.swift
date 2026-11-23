// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Observation

/// What the connection diagnostics' remedies do, and the small amount of state
/// they leave behind: the line each one says, the requests to scroll to and
/// focus a field, and the nudge that makes the status line's switch look
/// again.
///
/// Every remedy ends in one of the other flows (a sign-in, a browser read, a
/// refresh), so this holds the other models and decides nothing of its own.
@MainActor
@Observable
final class ConnectionRepairModel {
    private let store: UsageStore
    private let signIn: ProviderSignInModel
    private let credentials: ProviderCredentialModel

    init(store: UsageStore, signIn: ProviderSignInModel, credentials: ProviderCredentialModel) {
        self.store = store
        self.signIn = signIn
        self.credentials = credentials
    }

    var hookGeneration = 0
    /// What each account's last remedy said, by account id.
    var messages: [String: String] = [:]
    var connectionFocusRequest = 0
    /// Separate from `connectionFocusRequest`, because the address and the key
    /// are two fields and the remedy that sent the reader here named one of
    /// them.
    var addressFocusRequest = 0

    /// Reading the settings file is cheap but not observable, so a counter
    /// nudges SwiftUI to look again after connecting or disconnecting.
    var isHookInstalled: Bool {
        _ = hookGeneration
        return StatusLineHook.isInstalled
    }

    func repair(_ remedy: ConnectionRemedy, for account: AccountKey) {
        messages[account.id] = nil
        switch remedy {
        case .signIn:
            if account.provider == .copilot { signIn.startGitHubSignIn() }
            else if !account.isPrimary || account.provider == .grokBot {
                signIn.signIn(to: account.provider, replacing: account)
            }
        case .editCredential:
            connectionFocusRequest += 1
        case .editAddress:
            addressFocusRequest += 1
        case .readBrowser:
            credentials.readSession(for: account)
        case .connectStatusLine:
            let installed = StatusLineHook.install()
            hookGeneration += 1
            messages[account.id] = installed
                ? String.localized("Connected. Use Claude Code to send a new reading.")
                : String.localized("Couldn't connect the status line. Open setup help.")
            if installed { store.refresh(account) }
        case .copyCommand(let command):
            SettingsClipboard.copy(command)
            messages[account.id] = String.localized("Copied — run \(command) in your terminal, then retry.")
        case .openApp(let name):
            let candidates = [
                URL.applicationDirectory.appending(path: "\(name).app"),
                URL.homeDirectory.appending(path: "Applications/\(name).app")
            ]
            guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                messages[account.id] = String.localized("Couldn't find \(name). Open setup help.")
                return
            }
            Task { [self] in
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    store.refresh(account)
                } catch {
                    messages[account.id] = String.localized("Couldn't open \(name). Open setup help.")
                }
            }
        case .retry: store.refresh(account)
        case .help: NSWorkspace.shared.open(ConnectionRemedy.helpURL(for: account.provider))
        }
    }
}
