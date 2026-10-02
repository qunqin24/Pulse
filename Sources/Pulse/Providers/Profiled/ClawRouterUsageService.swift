// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// ClawRouter, OpenClaw's routing gateway: the monthly budget on the policy a
/// key belongs to, as an amount spent and a limit the service states.
///
/// Read with a ClawRouter key the user pastes, from the hosted service's
/// `GET https://clawrouter.openclaw.ai/v1/usage`. The shape is second-hand —
/// taken from CodexBar's ClawRouter provider and its tests, not from a
/// captured reply — and the fixture in the tests says so.
///
/// Money is in micro-dollars. A policy with no budget (`configured: false`)
/// reports spend and requests and nothing to measure them against, so it is
/// "no limits reported" rather than a ring at zero. The budget's month is
/// named (`…/2026-07`) but not when, or in which zone, it turns over, so no
/// reset is inferred from it. The per-provider breakdown is spend with no
/// limit and is left out.
extension ProviderProfile {
    static let clawRouter = ProviderProfile(
        displayName: "ClawRouter",
        billing: .api,
        iconResource: "openclaw",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From clawrouter.openclaw.ai. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "clawrouter",
        fetch: { await ClawRouterUsageService.fetch($0) }
    )
}

enum ClawRouterUsageService {
    static let endpoint = URL(string: "https://clawrouter.openclaw.ai/v1/usage")!

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
        struct Budget: Decodable {
            let configured: Bool?
            let limitMicros: Int64?
            let spentMicros: Int64?
        }

        let budget: Budget?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let budget = reply.budget,
              let configured = budget.configured
        else { return context.unavailable(.unreadableReply) }

        guard configured,
              let limit = budget.limitMicros, limit > 0,
              let spent = budget.spentMicros, spent >= 0
        else { return context.unavailable(.noLimitsReported) }

        let fraction = Double(spent) / Double(limit)
        let window = UsageWindow(
            id: "clawrouter.monthly",
            kind: .monthly,
            scope: nil,
            usedFraction: fraction,
            // A calendar month: a sort key, not a stated length.
            windowSeconds: 30 * 86_400,
            resetsAt: nil,
            reportsLength: false,
            isExhausted: fraction >= 1
        )
        return context.reading([window], at: now)
    }
}
