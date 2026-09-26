import Foundation

/// Actions for the credential or tool that this account actually uses.
enum ConnectionRemedy: Equatable {
    case signIn
    case editCredential
    /// The server address, for a provider whose address is the reader's own.
    /// Its own remedy rather than `editCredential`, which focuses the key
    /// field — a button saying "Edit credential" under a message about an
    /// address is a control pointing at the wrong row.
    case editAddress
    case readBrowser
    case connectStatusLine
    case openApp(String)
    case copyCommand(String)
    case retry
    case help

    static func forReason(_ reason: ProviderUsage.Unavailability, account: AccountKey) -> Self? {
        if !account.isPrimary,
           [.signedOut, .claudeLoginExpired, .signInRequired, .grokLoginExpired,
            .cursorLoginExpired, .cursorSignInRequired].contains(reason) {
            return .signIn
        }
        switch reason {
        case .loading, .awaitingResponse: return nil
        case .notConnected: return .connectStatusLine
        case .claudeSignInRequired, .claudeLoginExpired: return .copyCommand("claude auth login")
        case .signInRequired: return .copyCommand("codex login")
        case .kiroSignInRequired: return .copyCommand("kiro-cli login")
        case .grokSignInRequired, .grokLoginExpired: return .copyCommand("grok")
        case .volcengineSignInRequired: return .copyCommand("arkcli auth login")
        case .claudeDesktopNotSignedIn, .claudeDesktopSessionExpired: return .openApp("Claude")
        case .cursorSignInRequired, .cursorLoginExpired: return .openApp("Cursor")
        case .antigravityNotRunning, .antigravityNotAnswering: return .openApp("Antigravity")
        // The remedy for both is the same thing: start it. A plan it has never
        // recorded is one sign-in away, and opening the app is the step before
        // that either way.
        case .devinAppMissing, .devinPlanUnread: return .openApp("Devin")
        case .notSignedIn, .signedOut: return .signIn
        case .apiKeyMissing, .apiKeyRefused, .devinOrganizationMissing: return .editCredential
        case .serverAddressMissing, .serverAddressRefused: return .editAddress
        case .ollamaSessionMissing, .ollamaSessionExpired,
             .xiaomiSessionMissing, .xiaomiSessionExpired,
             .qoderSessionMissing, .qoderSessionExpired,
             .stepFunSessionMissing, .stepFunSessionExpired: return .readBrowser
        case .claudeDesktopKeyRefused, .unreachable, .rateLimited, .serverError,
             .codexServerFailed, .extensionTimedOut, .extensionFailed: return .retry
        // Its login is the program's own, so the page that says how an
        // extension works is the nearest thing to a remedy Pulse has.
        case .extensionMissing, .extensionSignedOut: return .help
        case .sessionMissing, .sessionExpired: return .readBrowser
        case .localLoginMissing, .localLoginExpired, .localAppMissing, .noPlan: return .help
        case .codexNotInstalled, .kiroNotInstalled, .kiroVersionUnsupported,
             .volcengineCLIMissing, .noLimitsReported,
             .grokBotNotIncluded, .zaiNoCodingPlan, .xiaomiNoCodingPlan, .qoderNoCredits,
             .stepFunNoPlan,
             .ollamaPageChanged, .unreadableReply:
            return .help
        }
    }

    var title: String {
        switch self {
        case .signIn: .localized("Sign in again…")
        case .editCredential: .localized("Edit credential")
        case .editAddress: .localized("Edit address")
        case .readBrowser: .localized("Read from browser")
        case .connectStatusLine: .localized("Connect status line")
        case .openApp(let name): .localized("Open \(name)")
        case .copyCommand: .localized("Copy login command")
        case .retry: .localized("Retry")
        case .help: .localized("Setup help")
        }
    }

    /// The user's setup page, not the provider's developer doc: where the key
    /// comes from and where it goes. One page per link — the two providers
    /// that share a service share a page too.
    static func helpURL(for provider: Provider) -> URL {
        // Not a setup page: what an extension has to print, which is what
        // anyone looking at a failing one needs.
        if provider == .pulseExtension {
            return URL(string: "https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md")!
        }
        let page: String
        if let written = provider.handWritten {
            page = switch written {
            case .claudeCode: "claude-code"
            case .codex: "codex"
            case .kiro: "kiro"
            case .antigravity: "antigravity"
            case .cursor: "cursor"
            case .openCodeGo: "opencode-go"
            case .kimiCode: "kimi-code"
            case .ollamaCloud: "ollama-cloud"
            case .xiaomiMiMo: "xiaomi-coding-plan"
            case .zai, .glmCoding: "zai"
            case .minimax, .minimaxCN: "minimax"
            case .copilot: "copilot"
            case .grok: "grok"
            case .grokBot: "grok-bot"
            case .volcengine: "volcengine"
            case .commandCode: "command-code"
            case .deepSeek: "deepseek"
            case .devin: "devin"
            case .sub2api: "sub2api"
            case .newAPI: "newapi"
            case .v2ex: "v2ex"
            case .qoder: "qoder"
            case .stepFun: "stepfun"
            // Answered above.
            case .pulseExtension: "extensions"
            }
        } else {
            page = provider.profile?.setupSlug ?? provider.rawValue
        }
        return URL(string: "https://github.com/qunqin24/Pulse/blob/main/Docs/setup/\(page).md")!
    }
}
