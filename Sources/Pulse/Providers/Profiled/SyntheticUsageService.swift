// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Synthetic: a rolling five-hour allowance, a weekly token allowance and an
/// hourly search allowance, each stated by the service as a percentage or as
/// an amount used out of a limit.
///
/// Read with a key the user pastes, from Synthetic's documented quota route:
/// `GET https://api.synthetic.new/v2/quotas`. The shape is second-hand — taken
/// from CodexBar's Synthetic plugin and its tests, not from a captured reply —
/// and the fixture in the tests says so.
///
/// Only the three named slots are read. CodexBar falls back to any object
/// anywhere in the reply that carries a number called `limit` or `used`; that
/// guesses at what a lane is and how long it lasts, so it is not done here.
///
/// **No reset for the rolling lanes.** The five-hour and weekly allowances
/// regenerate a slice at a time: `nextTickAt` / `nextRegenAt` is the next
/// slice, not a turnover. Drawn as a reset it would move forward every few
/// minutes and every one of those would read as the window starting again.
extension ProviderProfile {
    static let synthetic = ProviderProfile(
        displayName: "Synthetic",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From synthetic.new. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "synthetic",
        fetch: { await SyntheticUsageService.fetch($0) }
    )
}

enum SyntheticUsageService {
    static let endpoint = URL(string: "https://api.synthetic.new/v2/quotas")!

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

    /// One slot. Every field is optional because the three slots report
    /// different ones: the rolling lane counts down from `max`, the weekly
    /// lane states a percentage and a dollar figure, search counts requests.
    struct Slot: Decodable {
        let percentRemaining: Double?
        let max: Double?
        let remaining: Double?
        let limit: Double?
        let requests: Double?
        let maxCredits: String?
        let remainingCredits: String?
        let limited: Bool?
        let renewsAt: String?
    }

    struct Slots: Decodable {
        struct Search: Decodable { let hourly: Slot? }

        let rollingFiveHourLimit: Slot?
        let weeklyTokenLimit: Slot?
        let search: Search?
        let plan: String?
    }

    /// The slots sit at the root or under `data`; CodexBar accepts both.
    private struct Reply: Decodable {
        let rollingFiveHourLimit: Slot?
        let weeklyTokenLimit: Slot?
        let search: Slots.Search?
        let plan: String?
        let data: Slots?

        var slots: Slots {
            if rollingFiveHourLimit != nil || weeklyTokenLimit != nil || search?.hourly != nil {
                return Slots(rollingFiveHourLimit: rollingFiveHourLimit, weeklyTokenLimit: weeklyTokenLimit,
                             search: search, plan: plan)
            }
            return data ?? Slots(rollingFiveHourLimit: nil, weeklyTokenLimit: nil, search: nil, plan: plan)
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }
        let slots = reply.slots
        var windows: [UsageWindow] = []

        if let slot = slots.rollingFiveHourLimit, let used = fraction(used: nil, remaining: slot.remaining, limit: slot.max) {
            windows.append(UsageWindow(
                id: "synthetic.five_hour",
                kind: .fiveHour,
                scope: nil,
                usedFraction: used,
                windowSeconds: 5 * 3_600,
                resetsAt: nil,
                isExhausted: slot.limited == true || used >= 1
            ))
        }

        if let slot = slots.weeklyTokenLimit, let used = weeklyFraction(slot) {
            windows.append(UsageWindow(
                id: "synthetic.weekly",
                kind: .weekly,
                scope: nil,
                usedFraction: used,
                windowSeconds: 7 * 86_400,
                resetsAt: nil,
                isExhausted: slot.limited == true || used >= 1
            ))
        }

        // "Search" is Synthetic's search API, a product of its own, so it is
        // a scope and stays untranslated.
        if let slot = slots.search?.hourly, let used = fraction(used: slot.requests, remaining: slot.remaining, limit: slot.limit) {
            windows.append(UsageWindow(
                id: "synthetic.search_hourly",
                kind: .other(seconds: 3_600),
                scope: "Search",
                usedFraction: used,
                windowSeconds: 3_600,
                resetsAt: ProfileHTTP.date(slot.renewsAt),
                isExhausted: slot.limited == true || used >= 1
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        let plan = slots.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.reading(
            windows.sorted { $0.windowSeconds < $1.windowSeconds },
            plan: plan?.isEmpty == false ? plan : nil,
            at: now
        )
    }

    /// Used out of a limit, from whichever two of used / remaining / limit
    /// the slot states. A limit of zero or less, or a negative figure, is not
    /// an allowance and gives nothing.
    static func fraction(used: Double?, remaining: Double?, limit: Double?) -> Double? {
        guard let limit, limit.isFinite, limit > 0 else { return nil }
        if let used, used.isFinite, used >= 0 { return used / limit }
        if let remaining, remaining.isFinite, remaining >= 0 { return max(limit - remaining, 0) / limit }
        return nil
    }

    /// The weekly lane states a percentage left, on a 0–100 scale; failing
    /// that, a dollar allowance and what is left of it.
    private static func weeklyFraction(_ slot: Slot) -> Double? {
        if let left = slot.percentRemaining, left.isFinite, (0...100).contains(left) {
            return (100 - left) / 100
        }
        return fraction(used: nil, remaining: dollars(slot.remainingCredits), limit: dollars(slot.maxCredits))
    }

    /// "$36.00" → 36. Anything else is not a figure.
    static func dollars(_ text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned).flatMap { $0.isFinite ? $0 : nil }
    }
}
