// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Raycast AI: the account's AI credits — how many are left out of the
/// period's total, and when the next ones arrive.
///
/// Read with a browser session the user imports, from the call Raycast's own
/// settings page makes: `GET https://www.raycast.com/frontend_api/current_user/ai_credits`.
/// Only `__raycast_session` and `csrf_token` are kept, as CodexBar keeps
/// them. The shape is second-hand — taken from CodexBar's Raycast plugin, not
/// from a captured reply — and the fixture in the tests says so.
///
/// **Credits, not a month.** `next_credits_at` is when the allowance renews;
/// nothing states how long the period is, so none is claimed.
extension ProviderProfile {
    static let raycastAI = ProviderProfile(
        displayName: "Raycast AI",
        iconResource: "extension",
        credential: .sessionCookie(host: "www.raycast.com", cookies: ["__raycast_session", "csrf_token"]),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        spendingIsWatchedLocally: false,
        setupSlug: "raycast-ai",
        discoveryPaths: ["/Applications/Raycast.app"],
        fetch: { await RaycastAIUsageService.fetch($0) }
    )
}

enum RaycastAIUsageService {
    static let endpoint = URL(string: "https://www.raycast.com/frontend_api/current_user/ai_credits")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        var request = URLRequest(url: endpoint)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.raycast.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.raycast.com/settings", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        switch await ProfileHTTP.data(for: request, refused: .sessionExpired, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    /// Raycast writes its amounts as numbers or as numeric strings.
    struct Amount: Decodable {
        let value: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let text = try? container.decode(String.self) {
                value = Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                value = nil
            }
        }
    }

    private struct Reply: Decodable {
        struct Funding: Decodable { let tier: String? }

        let remainingBalanceCredits: Amount?
        let totalBalanceCredits: Amount?
        let nextCreditsAt: String?
        let fundingSubscription: Funding?

        enum CodingKeys: String, CodingKey {
            case remainingBalanceCredits = "remaining_balance_credits"
            case totalBalanceCredits = "total_balance_credits"
            case nextCreditsAt = "next_credits_at"
            case fundingSubscription = "funding_subscription"
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        // Both figures from Raycast, or no ring: a total of zero is no
        // allowance, and a remainder alone has nothing to be a fraction of.
        if let remaining = reply.remainingBalanceCredits?.value, remaining.isFinite, remaining >= 0,
           let total = reply.totalBalanceCredits?.value, total.isFinite, total > 0 {
            windows.append(UsageWindow(
                id: "raycast.ai_credits",
                kind: .credits,
                scope: nil,
                usedFraction: max(total - remaining, 0) / total,
                windowSeconds: 30 * 86_400,
                resetsAt: ProfileHTTP.date(reply.nextCreditsAt),
                reportsLength: false,
                isExhausted: remaining <= 0
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan(reply.fundingSubscription?.tier), at: now)
    }

    /// Raycast's plan names, as its own pages write them.
    static func plan(_ tier: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty else { return nil }
        switch tier {
        case "pro": return "Pro"
        case "pro_plus": return "Pro+"
        case "max": return "Max"
        default: return tier
        }
    }
}
