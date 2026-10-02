// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// DevPass, LLM Gateway's subscription: the billing cycle's plan credits, the
/// premium models' weekly allowance, and — where the key has one — the key's
/// own spending limit. Every allowance and every amount used is stated by the
/// service, in dollars of credit.
///
/// Read with a regular LLM Gateway API key the user pastes, from
/// `GET https://api.llmgateway.io/v1/key`. The shape is second-hand — taken
/// from CodexBar's DevPass provider, its tests and the public usage API it
/// cites, not from a captured reply — and the fixture in the tests says so.
///
/// The cycle's end is not in the reply, so that allowance has no reset and no
/// length; neither is inferred. An allowance of zero is no allowance and is
/// left off rather than drawn full or empty.
extension ProviderProfile {
    static let devPass = ProviderProfile(
        displayName: "DevPass",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("An API key from llmgateway.io. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "devpass",
        fetch: { await DevPassUsageService.fetch($0) }
    )
}

enum DevPassUsageService {
    static let endpoint = URL(string: "https://api.llmgateway.io/v1/key")!

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

    /// Amounts arrive as decimal strings, "212.00".
    private struct Reply: Decodable {
        struct Key: Decodable {
            let usage: String?
            let limit: String?
            let devPlan: String?
            let devPlanCreditsUsed: String?
            let devPlanCreditsLimit: String?
            let devPlanPremiumCreditsUsed: String?
            let devPlanPremiumWeeklyLimit: String?
            let devPlanPremiumWeekResetsAt: String?
        }

        let data: Key?
    }

    private static let plans = ["none", "lite", "pro", "max"]

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let key = reply.data,
              let plan = key.devPlan, plans.contains(plan)
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []
        if plan != "none" {
            // Seven days from the first premium request — a stated length.
            if let window = window(
                id: "devpass.premium_weekly", kind: .weekly,
                used: key.devPlanPremiumCreditsUsed, limit: key.devPlanPremiumWeeklyLimit,
                seconds: 7 * 86_400, reportsLength: true,
                resetsAt: ProfileHTTP.date(key.devPlanPremiumWeekResetsAt)
            ) { windows.append(window) }
            // The billing cycle's credits. No end is reported and no length is
            // claimed; thirty days only sorts it after the week.
            if let window = window(
                id: "devpass.cycle", kind: .credits,
                used: key.devPlanCreditsUsed, limit: key.devPlanCreditsLimit,
                seconds: 30 * 86_400, reportsLength: false, resetsAt: nil
            ) { windows.append(window) }
        }
        // The key's own spending limit, against everything it has ever spent.
        // Never resets, so it has no clock and sorts last.
        if let window = window(
            id: "devpass.key_limit", kind: .spend,
            used: key.usage, limit: key.limit,
            seconds: 365 * 86_400, reportsLength: false, resetsAt: nil
        ) { windows.append(window) }

        guard !windows.isEmpty else {
            // Pay as you go with no key limit: an answer, not an outage.
            return context.unavailable(plan == "none" ? .noPlan : .noLimitsReported)
        }
        let name = plan == "none" ? nil : plan.prefix(1).uppercased() + plan.dropFirst()
        return context.reading(windows, plan: name, at: now)
    }

    /// A window from an amount used and an allowance, both as DevPass wrote
    /// them. Nil when either is missing, unreadable or negative, or when the
    /// allowance is zero.
    private static func window(
        id: String,
        kind: UsageWindow.Kind,
        used: String?,
        limit: String?,
        seconds: Int,
        reportsLength: Bool,
        resetsAt: Date?
    ) -> UsageWindow? {
        guard let used = amount(used), let limit = amount(limit), limit > 0 else { return nil }
        let fraction = used / limit
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            isExhausted: fraction >= 1
        )
    }

    private static func amount(_ text: String?) -> Double? {
        guard let text, let value = Double(text.trimmingCharacters(in: .whitespaces)),
              value.isFinite, value >= 0
        else { return nil }
        return value
    }
}
