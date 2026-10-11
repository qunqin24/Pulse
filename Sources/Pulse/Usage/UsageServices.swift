// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// One account's request, closed over everything it needs.
///
/// Built on the main actor, at the start of a pass, so every setting and
/// credential it depends on is read at that moment and the fetch itself
/// touches no main-actor state. Run it from anywhere.
typealias UsageFetch = @Sendable () async -> ProviderUsage

/// How `UsageStore` turns an account into a request.
///
/// **The store's only way of asking a provider.** The full pass and the
/// per-account refresh both go through `fetch(for:key:)`, so there is one place
/// that decides which service answers for which account. It is also the seam a
/// test drives the scheduling through: the production `LiveUsageServices`
/// talks to the real providers, a fake answers from memory.
@MainActor
protocol UsageServiceFactory {
    /// The credential Pulse holds for a provider, read from storage now.
    ///
    /// For a provider's own pane in Settings, which is reachable while its rail
    /// slot is switched off — so its key is not in the store's launch-time
    /// cache.
    func storedKey(for provider: Provider) -> String?

    /// The request for one account, with `key` as the credential it is to use.
    ///
    /// Primary accounts answer by their provider (hand-written or profiled),
    /// an extension answers by its program (or says it is gone), and any other
    /// added account by the login Pulse itself holds.
    func fetch(for account: AccountKey, key: String?) -> UsageFetch
}

/// The real providers.
@MainActor
final class LiveUsageServices: UsageServiceFactory {
    private let settings: AppSettings
    private let codex: CodexUsageService
    private let kiro = KiroUsageService()
    private let claudeCode = ClaudeCodeUsageService()
    private let antigravity = AntigravityUsageService()
    private let grok = GrokUsageService()
    private let grokBot = GrokBotUsageService()
    private let cursor = CursorUsageService()

    init(settings: AppSettings, appServer: CodexAppServer) {
        self.settings = settings
        codex = CodexUsageService(server: appServer)
    }

    func storedKey(for provider: Provider) -> String? {
        APIKeyStore.key(for: provider)
    }

    func fetch(for account: AccountKey, key: String?) -> UsageFetch {
        let provider = account.provider
        if provider == .pulseExtension {
            // Gone from the folder since it was listed: say so rather than
            // leave the ring on a reading from a program that is not there
            // any more.
            let service = settings.pulseExtension(for: account).map(ExtensionUsageService.init(pulseExtension:))
            return { await service?.fetch() ?? .unavailable(account, reason: .extensionMissing) }
        }
        guard account.isPrimary else {
            let (claudeCode, codex, grok, grokBot) = (self.claudeCode, self.codex, self.grok, self.grokBot)
            return { await Self.fetchAdded(account, claudeCode: claudeCode, codex: codex, grok: grok, grokBot: grokBot) }
        }
        guard let written = provider.handWritten else {
            // A profiled provider: the fetch its own file built.
            guard let profile = provider.profile else { return { .unavailable(account, reason: .loading) } }
            let context = profileContext(for: provider, key: key)
            return { await profile.fetch(context) }
        }

        // Read here rather than inside the services, which stay free of
        // storage concerns.
        let source = settings.source(for: account)
        switch written {
        case .codex:
            let codex = self.codex
            return { await codex.fetch(source: source) }
        case .kiro:
            let kiro = self.kiro
            return { await kiro.fetch() }
        case .claudeCode:
            let claudeCode = self.claudeCode
            return { await claudeCode.fetch(source: source) }
        case .antigravity:
            let antigravity = self.antigravity
            return { await antigravity.fetch() }
        case .cursor:
            let cursor = self.cursor
            return { await cursor.fetch() }
        case .openCodeGo:
            let service = OpenCodeGoUsageService(
                enteredKey: key,
                consoleCookie: APIKeyStore.key(for: .openCodeGo, slot: OpenCodeConsole.slot)
            )
            return { await service.fetch() }
        case .kimiCode:
            let service = KimiCodeUsageService(enteredKey: key)
            return { await service.fetch() }
        case .ollamaCloud:
            let service = OllamaCloudUsageService(cookie: key)
            return { await service.fetch() }
        case .zai, .glmCoding:
            let service = ZaiUsageService(provider: provider, enteredKey: key)
            return { await service.fetch() }
        case .minimax, .minimaxCN:
            let service = MiniMaxUsageService(provider: provider, enteredKey: key)
            return { await service.fetch() }
        case .copilot:
            let service = CopilotUsageService(token: key)
            return { await service.fetch() }
        case .grok:
            let grok = self.grok
            return { await grok.fetch() }
        case .grokBot:
            let grokBot = self.grokBot
            return { await grokBot.fetch() }
        case .volcengine:
            let service = VolcengineUsageService(enteredKey: key)
            return { await service.fetch(source: source) }
        case .commandCode:
            let service = CommandCodeUsageService(enteredKey: key)
            return { await service.fetch() }
        case .deepSeek:
            let service = DeepSeekUsageService(
                enteredKey: key,
                basis: settings.deepSeekBasis,
                budget: settings.deepSeekBudget,
                currency: settings.deepSeekCurrency,
                consoleToken: DeepSeekConsole.keptToken
            )
            return { await service.fetch() }
        case .devin:
            let service = DevinUsageService(enteredKey: key, browser: settings.sessionBrowser(for: account))
            return { await service.fetch(source: source) }
        case .xiaomiMiMo:
            let service = XiaomiMiMoUsageService(cookie: key)
            return { await service.fetch() }
        case .sub2api:
            let service = Sub2APIUsageService(enteredKey: key, address: settings.serverAddress(for: account))
            return { await service.fetch() }
        case .newAPI:
            let service = NewAPIUsageService(enteredKey: key, address: settings.serverAddress(for: account))
            return { await service.fetch() }
        case .v2ex:
            let service = V2EXUsageService(enteredKey: key)
            return { await service.fetch() }
        case .qoder:
            let service = QoderUsageService(cookie: key, site: settings.qoderSite,
                                            showsParts: settings.qoderShowsParts)
            return { await service.fetch() }
        case .stepFun:
            let service = StepFunUsageService(cookie: key, site: settings.stepFunSite)
            return { await service.fetch() }
        // Every extension is a slot of its own, answered above.
        case .pulseExtension:
            return { .unavailable(account, reason: .extensionMissing) }
        }
    }

    /// What a profiled provider's fetch is handed: the credential Pulse holds
    /// for it and the address it is to be sent to, read here on the main
    /// actor so the fetch itself touches no settings.
    private func profileContext(for provider: Provider, key: String?) -> ProfileContext {
        ProfileContext(
            provider: provider,
            credential: key,
            serverAddress: provider.usesServerAddress ? settings.serverAddress(for: AccountKey(provider)) : nil
        )
    }

    /// An account Pulse signed in to itself.
    ///
    /// Its token is renewed here when it is close to expiring, because nothing
    /// else will: the CLI keeps its own login fresh, and this one is not that.
    /// A renewal that fails leaves the account signed out rather than
    /// reporting a network error — the remedy is the same either way, and it
    /// is one the user can act on.
    private nonisolated static func fetchAdded(
        _ account: AccountKey,
        claudeCode: ClaudeCodeUsageService,
        codex: CodexUsageService,
        grok: GrokUsageService,
        grokBot: GrokBotUsageService
    ) async -> ProviderUsage {
        guard var credentials = AccountCredentialStore.credentials(for: account) else {
            return .unavailable(account, reason: .signedOut)
        }

        if !credentials.isFresh {
            // Grok Bot lands in the `else` deliberately: `OAuthLogin` has no
            // configuration for it, because its sign-in is not OAuth and no
            // refresh endpoint was found in Cursor's own client. Its tokens
            // run **sixty days** (measured), so signing in again twice a year
            // is the honest answer rather than a renewal that cannot happen.
            guard let renewed = try? await OAuthLogin.refresh(credentials, for: account.provider) else {
                return .unavailable(account, reason: .signedOut)
            }
            credentials = renewed
            // Compare-and-set: a pass that was given up on can still be in
            // here, and its answer must not replace a newer login.
            AccountCredentialStore.renewed(credentials, for: account)
        }

        // Nothing else can be signed in to, so nothing else gets here —
        // including every profiled provider.
        guard let written = account.provider.handWritten else {
            return .unavailable(account, reason: .loading)
        }
        return switch written {
        case .claudeCode: await claudeCode.fetch(account: account, token: credentials.accessToken)
        case .codex: await codex.fetch(account: account, credentials: credentials)
        case .grok: await grok.fetch(account: account, token: credentials.accessToken)
        case .grokBot: await grokBot.fetch(account: account, token: credentials.accessToken)
        case .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .volcengine,
             .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api, .newAPI,
             .v2ex, .qoder, .stepFun, .pulseExtension:
            .unavailable(account, reason: .loading)
        }
    }
}
