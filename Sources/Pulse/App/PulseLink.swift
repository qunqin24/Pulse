import Foundation

/// Navigation only. A URL cannot change settings, run commands, or start a login.
enum PulseLink: Equatable {
    case settings
    case integrations
    case account(AccountKey)

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "pulse", parts.user == nil,
              parts.password == nil, parts.port == nil, parts.query == nil,
              parts.fragment == nil else { return nil }
        switch parts.host?.lowercased() {
        case "settings" where parts.path.isEmpty || parts.path == "/": self = .settings
        case "integrations" where parts.path.isEmpty || parts.path == "/": self = .integrations
        case "account":
            let path = parts.path
            guard path.hasPrefix("/") else { return nil }
            let id = String(path.dropFirst())
            guard !id.contains("/"), let account = AccountKey(id: id),
                  account.id == id, id.filter({ $0 == "#" }).count <= 1,
                  !id.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
            self = .account(account)
        default: return nil
        }
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "pulse"
        switch self {
        case .settings: parts.host = "settings"
        case .integrations: parts.host = "integrations"
        case .account(let account):
            parts.host = "account"
            parts.path = "/\(account.id)"
        }
        return parts.url!
    }
}
