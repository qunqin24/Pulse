import Foundation

/// Actions for the credential or tool that this account actually uses.
enum ConnectionRemedy: Equatable {
    case signIn
    case editCredential
    case readBrowser
    case connectStatusLine
    case openApp(String)
    case copyCommand(String)
    case retry
    case help

    static func forReason(_ reason: ProviderUsage.Unavailability, account: AccountKey) -> Self? {
        if !account.isPrimary,
           [.signedOut, .claudeLoginExpired, .signInRequired, .grokLoginExpired,
            .cursorLoginExpired, .cursorSignInRequired,
            .kimiSignInRequired, .kimiLoginExpired].contains(reason) {
            return .signIn
        }
        switch reason {
        case .loading, .awaitingResponse: return nil
        case .notConnected: return .connectStatusLine
        case .claudeSignInRequired, .claudeLoginExpired: return .copyCommand("claude auth login")
        case .signInRequired: return .copyCommand("codex login")
        case .grokSignInRequired, .grokLoginExpired: return .copyCommand("grok")
        case .volcengineSignInRequired: return .copyCommand("arkcli auth login")
        case .claudeDesktopNotSignedIn, .claudeDesktopSessionExpired: return .openApp("Claude")
        case .cursorSignInRequired, .cursorLoginExpired: return .openApp("Cursor")
        case .antigravityNotRunning, .antigravityNotAnswering: return .openApp("Antigravity")
        case .notSignedIn, .signedOut, .kimiSignInRequired, .kimiLoginExpired: return .signIn
        case .apiKeyMissing, .apiKeyRefused: return .editCredential
        case .ollamaSessionMissing, .ollamaSessionExpired,
             .qoderSessionMissing, .qoderSessionExpired: return .readBrowser
        case .claudeDesktopKeyRefused, .unreachable, .rateLimited, .serverError,
             .codexServerFailed: return .retry
        case .codexNotInstalled, .volcengineCLIMissing, .noLimitsReported,
             .grokBotNotIncluded, .zaiNoCodingPlan, .ollamaPageChanged, .unreadableReply:
            return .help
        }
    }

    var title: String {
        switch self {
        case .signIn: .localized("Sign in again…")
        case .editCredential: .localized("Edit credential")
        case .readBrowser: .localized("Read from browser")
        case .connectStatusLine: .localized("Connect status line")
        case .openApp(let name): .localized("Open \(name)")
        case .copyCommand: .localized("Copy login command")
        case .retry: .localized("Retry")
        case .help: .localized("Setup help")
        }
    }

    static func helpURL(for provider: Provider) -> URL {
        let page: String = switch provider {
        case .claudeCode: "claude-code"
        case .codex: "codex"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .openCodeGo: "opencode-go"
        case .kimiCode: "kimi-code"
        case .ollamaCloud: "ollama-cloud"
        case .zai, .glmCoding: "zai"
        case .minimax, .minimaxCN: "minimax"
        case .copilot: "copilot"
        case .grok: "grok"
        case .grokBot: "grok-bot"
        case .volcengine: "volcengine"
        case .commandCode: "command-code"
        case .deepSeek: "deepseek"
        case .qoder: "qoder"
        }
        // Fork docs live here; upstream help links would send people to the wrong repo.
        return URL(string: "https://github.com/harrisliangsu/Pulse/blob/main/Docs/providers/\(page).md")!
    }
}
