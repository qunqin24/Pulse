import Foundation

/// The route that actually answered, rather than the user's routing preference.
enum UsageRoute: String, Codable, Sendable {
    case endpoint
    case statusLine
    case desktopSession
    case appServer
    case kiroACP
    case languageServer
    case webSession
    case arkCLI
    /// A reading taken out of a desktop app's own saved state rather than
    /// asked of anybody. Devin's: written when that app starts.
    case appCache
    /// A program in the extensions folder, which answered on stdout.
    case extensionProgram = "extension"

    var title: String {
        switch self {
        case .endpoint: .localized("Usage endpoint")
        case .statusLine: .localized("Claude Code status line")
        case .desktopSession: .localized("Desktop app session")
        case .appServer: .localized("Codex app server")
        case .kiroACP: .localized("Kiro CLI ACP")
        case .languageServer: .localized("Local language server")
        case .webSession: .localized("Signed-in web page")
        case .arkCLI: "arkcli"
        case .appCache: .localized("The app's saved plan")
        case .extensionProgram: .localized("Extension program")
        }
    }

    /// Only single-route providers can be labelled outside their service.
    static func soleRoute(for account: AccountKey) -> UsageRoute? {
        // Before the added-account rule: every extension is an account of
        // one provider, and none of them is its first.
        if account.provider == .pulseExtension { return .extensionProgram }
        if !account.isPrimary { return .endpoint }
        // A browser session is read like any other signed-in page; everything
        // else a profiled provider does is a request to the service.
        guard let written = account.provider.handWritten else {
            switch account.provider.profile?.credential {
            case .sessionCookie, .browserStorage: return .webSession
            default: return .endpoint
            }
        }
        switch written {
        case .claudeCode, .codex, .volcengine, .devin: return nil
        case .antigravity: return .languageServer
        // All four read a signed-in browser session rather than a key.
        case .ollamaCloud, .xiaomiMiMo, .qoder, .stepFun: return .webSession
        case .kiro: return .kiroACP
        case .cursor, .openCodeGo, .kimiCode, .zai, .glmCoding, .minimax,
             .minimaxCN, .copilot, .grok, .grokBot, .commandCode, .deepSeek,
             .sub2api, .newAPI, .v2ex:
            return .endpoint
        case .pulseExtension: return .extensionProgram
        }
    }
}

extension ProviderUsage {
    /// Retains earlier route outcomes when automatic routing falls through.
    /// Contains only typed outcomes, never request headers or response bodies.
    func recording(_ route: UsageRoute, after earlier: [ConnectionDiagnostic.Attempt] = []) -> Self {
        var result = self
        result.origin = reportsSomething ? route : nil
        result.attempts = earlier + [.init(route: route, state: state)]
        return result
    }

    func recordingSoleRoute() -> Self {
        guard attempts.isEmpty, let route = UsageRoute.soleRoute(for: account) else { return self }
        return recording(route)
    }
}
