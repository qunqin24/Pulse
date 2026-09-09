import Foundation

struct OllamaCloudUsageService: Sendable {
    let cookie: String?

    func fetch() async -> ProviderUsage {
        guard let cookie, !cookie.isEmpty else {
            return .unavailable(.ollamaCloud, reason: .ollamaSessionMissing)
        }
        do {
            let snapshot = try await OllamaCloudClient().fetch(cookie: cookie)
            let windows: [UsageWindow] = [
                .init(id: "ollama.session", kind: .fiveHour, scope: nil,
                      usedFraction: snapshot.session.usedFraction, windowSeconds: 5 * 3600,
                      resetsAt: snapshot.session.resetsAt, isExhausted: snapshot.session.usedFraction >= 1),
                .init(id: "ollama.weekly", kind: .weekly, scope: nil,
                      usedFraction: snapshot.weekly.usedFraction, windowSeconds: 7 * 86400,
                      resetsAt: snapshot.weekly.resetsAt, isExhausted: snapshot.weekly.usedFraction >= 1)
            ]
            return .init(account: AccountKey(.ollamaCloud), windows: windows, observedAt: Date(), state: .live, plan: nil, creditBalance: nil)
        } catch let error as OllamaCloudError {
            let reason: ProviderUsage.Unavailability = switch error {
            case .missingCookie, .invalidCookie: .ollamaSessionMissing
            case .signedOut: .ollamaSessionExpired
            case .rateLimited: .rateLimited
            case .serverError: .serverError
            case .invalidPage: .ollamaPageChanged
            }
            return .unavailable(.ollamaCloud, reason: reason)
        } catch {
            return .unavailable(.ollamaCloud, reason: .unreachable)
        }
    }
}
