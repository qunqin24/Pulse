import Foundation

struct OllamaCloudUsageService: Sendable {
    let cookie: String?

    func fetch() async -> ProviderUsage {
        guard let cookie, !cookie.isEmpty else {
            return .unavailable(.ollamaCloud, reason: .ollamaSessionMissing)
        }
        do {
            let snapshot = try await OllamaCloudClient().fetch(cookie: cookie)
            return .init(account: AccountKey(.ollamaCloud), windows: Self.windows(from: snapshot), observedAt: Date(), state: .live, plan: nil, creditBalance: nil)
        } catch let error as OllamaCloudError {
            return .unavailable(.ollamaCloud, reason: Self.reason(for: error))
        } catch {
            return .unavailable(.ollamaCloud, reason: .unreachable)
        }
    }

    /// Moved out of `fetch()` so a test can drive the two windows the card
    /// shows without a network call. Do not tidy it back.
    static func windows(from snapshot: OllamaCloudSnapshot) -> [UsageWindow] {
        [
            .init(id: "ollama.session", kind: .fiveHour, scope: nil,
                  usedFraction: snapshot.session.usedFraction, windowSeconds: 5 * 3600,
                  resetsAt: snapshot.session.resetsAt, isExhausted: snapshot.session.usedFraction >= 1),
            .init(id: "ollama.weekly", kind: .weekly, scope: nil,
                  usedFraction: snapshot.weekly.usedFraction, windowSeconds: 7 * 86400,
                  resetsAt: snapshot.weekly.resetsAt, isExhausted: snapshot.weekly.usedFraction >= 1),
        ]
    }

    /// Moved out of `fetch()` so a test can drive the mapping without a
    /// network call. Do not tidy it back.
    static func reason(for error: OllamaCloudError) -> ProviderUsage.Unavailability {
        switch error {
        case .missingCookie, .invalidCookie: .ollamaSessionMissing
        case .signedOut: .ollamaSessionExpired
        case .rateLimited: .rateLimited
        case .serverError: .serverError
        case .invalidPage: .ollamaPageChanged
        }
    }
}
