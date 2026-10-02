// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// ClinePass, Cline's subscription: a five-hour, a weekly and a monthly limit,
/// each reported as a percentage by the service itself.
///
/// Read with a key the user pastes, from the endpoint Cline's own app calls:
/// `GET https://api.cline.bot/api/v1/users/me/plan/usage-limits`. The shape is
/// second-hand — taken from CodexBar's ClinePass provider and its tests, not
/// from a captured reply — and the fixture in the tests says so.
///
/// Only the three named limits are read. A limit type this build does not know
/// is left off rather than guessed at: its length is not stated anywhere, so
/// neither its name nor its window clock could be said honestly.
extension ProviderProfile {
    static let clinePass = ProviderProfile(
        displayName: "ClinePass",
        iconResource: "cline",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From app.cline.bot. Stored encrypted on this Mac.") },
        setupSlug: "clinepass",
        fetch: { await ClinePassUsageService.fetch($0) }
    )
}

enum ClinePassUsageService {
    static let endpoint = URL(string: "https://api.cline.bot/api/v1/users/me/plan/usage-limits")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(endpoint, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Limit: Decodable {
            let type: String?
            let percentUsed: Double?
            let resetsAt: String?
        }

        struct Payload: Decodable { let limits: [Limit]? }

        let success: Bool?
        let data: Payload?
    }

    /// The limits Cline names, with the length each one is. `monthly` is a
    /// billing month rather than a fixed thirty days, so its length is only
    /// a sort key and is not claimed.
    private static let known: [String: (kind: UsageWindow.Kind, seconds: Int, reportsLength: Bool)] = [
        "five_hour": (.fiveHour, 5 * 3_600, true),
        "weekly": (.weekly, 7 * 86_400, true),
        "monthly": (.monthly, 30 * 86_400, false),
    ]

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.success == true,
              let limits = reply.data?.limits
        else { return context.unavailable(.unreadableReply) }

        let windows = limits.compactMap { limit -> UsageWindow? in
            guard let type = limit.type, let shape = known[type],
                  let percent = limit.percentUsed, percent.isFinite, percent >= 0
            else { return nil }
            return UsageWindow(
                id: "clinepass.\(type)",
                kind: shape.kind,
                scope: nil,
                usedFraction: percent / 100,
                windowSeconds: shape.seconds,
                resetsAt: ProfileHTTP.date(limit.resetsAt),
                reportsLength: shape.reportsLength,
                isExhausted: percent >= 100
            )
        }
        .sorted { $0.windowSeconds < $1.windowSeconds }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, at: now)
    }
}
