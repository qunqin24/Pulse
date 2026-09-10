import Foundation

/// The route that actually answered, rather than the user's routing preference.
enum UsageRoute: String, Codable, Sendable {
    case endpoint
    case statusLine
    case desktopSession
    case appServer
    case languageServer
    case webSession
    case arkCLI

    var title: String {
        switch self {
        case .endpoint: .localized("Usage endpoint")
        case .statusLine: .localized("Claude Code status line")
        case .desktopSession: .localized("Desktop app session")
        case .appServer: .localized("Codex app server")
        case .languageServer: .localized("Local language server")
        case .webSession: .localized("Signed-in web page")
        case .arkCLI: "arkcli"
        }
    }

    /// Only single-route providers can be labelled outside their service.
    static func soleRoute(for account: AccountKey) -> UsageRoute? {
        if !account.isPrimary { return .endpoint }
        switch account.provider {
        case .claudeCode, .codex, .volcengine: return nil
        case .antigravity: return .languageServer
        case .ollamaCloud: return .webSession
        case .cursor, .openCodeGo, .kimiCode, .zai, .glmCoding, .minimax,
             .minimaxCN, .copilot, .grok, .grokBot, .commandCode, .deepSeek:
            return .endpoint
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
