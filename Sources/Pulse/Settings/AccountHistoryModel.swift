// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation

/// What the Settings window has read of each provider's history, held for as
/// long as the window lives rather than as long as one pane does.
///
/// The shell owns it and runs `load()` from a task keyed on `key`, so leaving
/// an account's pane cancels a read in flight and coming back reuses what was
/// read. The account pane only draws it.
@MainActor
@Observable
final class AccountHistoryModel {
    private let store: UsageStore
    private let settings: AppSettings
    private let navigation: SettingsNavigation

    init(store: UsageStore, settings: AppSettings, navigation: SettingsNavigation) {
        self.store = store
        self.settings = settings
        self.navigation = navigation
    }

    /// Read from the CLIs' own transcripts, which takes long enough on a cold
    /// start to be worth holding on to while the window is open.
    var ledgers: [Provider: UsageLedger] = [:]
    /// How each provider's last history read went — kept beside the ledger
    /// rather than folded into it.
    ///
    /// An empty chart has several causes and they must not be said the same way:
    /// telling somebody their account has no usage, because the Wi-Fi dropped,
    /// beside a ring showing 80%, is the app inventing a reading — and so is
    /// telling them the service failed when no key was ever pasted. Written on
    /// **every** path that touches `ledgers`, so it cannot describe a read
    /// other than the most recent one.
    var historyReads: [Provider: ZaiUsageService.HistoryRead] = [:]
    var codexAccount: CodexAccountUsage?
    /// Bumped when OpenCode Go's console session is read or removed, which
    /// changes whether the pane has a history to show — and asks for it.
    var consoleRevision = 0
    var loadingHistory: Provider?
    var historyReadID = UUID()

    /// What a history read depends on. A change to any of it means the
    /// sentence on screen is about to describe a read that no longer applies.
    var key: String {
        guard case .account(let account) = navigation.pane else { return "\(navigation.pane)" }
        // The reading's time too: the value estimate counts spend up to when
        // the percentage was read, and a ledger read before that is short.
        // Only where the estimate is this Mac's transcripts — another provider's
        // history is asked of it, and need not be asked at every refresh.
        let read = account.provider.keepsLocalTranscripts
            ? store.usage(for: account).observedAt?.timeIntervalSince1970 ?? 0 : 0
        // DeepSeek's money follows the currency the ring follows.
        let currency = account.provider == .deepSeek ? settings.deepSeekCurrency ?? "" : ""
        // Other agents' records are read only with Token spend on, so turning
        // it on is what fills the pane.
        let agents = if case .agents = account.provider.cardHistory { settings.readsTokenSpend } else { false }
        return "\(account.id)|\(settings.isEnabled(account))|\(consoleRevision)|\(read)|\(currency)|\(agents)"
    }

    func load() async {
        let readID = UUID()
        historyReadID = readID
        loadingHistory = nil
        // History is per provider — it is read from that CLI's transcripts,
        // which do not say which account was signed in at the time.
        guard case .account(let account) = navigation.pane else { return }
        let provider = account.provider
        guard settings.isEnabled(account), account.isPrimary else {
            ledgers[provider] = .empty
            historyReads[provider] = .notAsked
            codexAccount = nil
            return
        }

        loadingHistory = provider
        // `saveKey` can start a replacement without cancelling its predecessor.
        // A read id fences both progress and cleanup, even for the same provider.
        defer { if historyReadID == readID { loadingHistory = nil } }

        // The source the detailed card reads, so the pane and the card show
        // the same history. Most are asked of the provider rather than
        // scanned off disk: their own statistics cover the whole account, so
        // there is nothing local to read and nothing to cache between panes.
        let source = provider.cardHistory

        // OpenCode Go's comes from the console's request log, the same read
        // the detailed card makes and shares.
        if source == .accountLogs, provider == .openCodeGo {
            guard let cookie = APIKeyStore.key(for: .openCodeGo, slot: OpenCodeConsole.slot) else {
                ledgers[provider] = .empty
                historyReads[provider] = .notConfigured
                return
            }
            let requestKey = key
            let read = await OpenCodeConsoleHistory.shared.ledger(cookie: cookie) { [self] ledger in
                guard historyReadID == readID, key == requestKey else { return }
                ledgers[provider] = ledger
                historyReads[provider] = .answered(ledger)
            }
            guard !Task.isCancelled, historyReadID == readID, key == requestKey else { return }
            switch read {
            case .answered(let ledger):
                ledgers[provider] = ledger
                historyReads[provider] = .answered(ledger)
            case .signedOut, .failed:
                ledgers[provider] = .empty
                historyReads[provider] = .failed
            }
            return
        }

        if source == .accountLogs, provider == .deepSeek {
            guard let token = DeepSeekConsole.keptToken else {
                ledgers[provider] = .empty
                historyReads[provider] = .notConfigured
                return
            }
            let requestKey = key
            let read = await DeepSeekConsoleHistory.shared.ledger(token: token, currency: settings.deepSeekCurrency)
            guard !Task.isCancelled, historyReadID == readID, key == requestKey else { return }
            switch read {
            case .answered(let ledger):
                ledgers[provider] = ledger
                historyReads[provider] = .answered(ledger)
            case .signedOut, .failed:
                ledgers[provider] = .empty
                historyReads[provider] = .failed
            }
            return
        }

        if source == .accountStatistics {
            let key = APIKeyStore.key(for: provider)
            let read = await ZaiUsageService(provider: provider, enteredKey: key).history()

            // A pane switch cancels this task, and a cancelled request comes
            // back looking exactly like a failed one. Recording it would leave
            // "didn't answer" on a provider that was never given the chance to.
            guard !Task.isCancelled else { return }

            historyReads[provider] = read
            ledgers[provider] = if case .answered(let ledger) = read { ledger } else { .empty }
            return
        }

        // The Token spend agents that borrow this provider's mark — MiniMax
        // Code's log for MiniMax. Other apps' records, which Pulse reads only
        // with Token spend on, as the card does; off, nothing is read, and
        // the history group says what to turn on instead.
        if case .agents(let agents, let slices) = source {
            guard settings.readsTokenSpend else {
                ledgers[provider] = .empty
                historyReads[provider] = nil
                return
            }
            let read = await UsageLedger.reading(agents, slices: slices)
            guard !Task.isCancelled else { return }
            ledgers[provider] = read
            historyReads[provider] = .answered(read)
            return
        }

        // Refreshed rather than reused: the session running right now is
        // appending to a log as this is read, and only that file is re-parsed.
        let scanned = await UsageLedgerReader.shared.ledger(for: provider, refresh: true)
        guard !Task.isCancelled else { return }
        ledgers[provider] = scanned
        // Reading this Mac's own files always answers, even when the answer is
        // that there is nothing there.
        historyReads[provider] = .answered(scanned)

        if provider == .codex {
            codexAccount = await store.codexAccountUsage()
        }
    }
}
