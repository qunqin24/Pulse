// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Neuralwatt, inference priced by energy: a subscription's kilowatt-hour
/// allowance for the current period, the key's own spending allowance where
/// one is set, and the prepaid balance in US dollars.
///
/// Read with an API key the user pastes, from
/// `GET https://api.neuralwatt.com/v1/quota`. The shape is second-hand — taken
/// from CodexBar's Neuralwatt provider and its tests, not from a captured
/// reply — and the fixture in the tests says so.
///
/// The prepaid balance and the subscription are separate things: credits do
/// not reset and are spent as you go, the allowance is billed against kWh and
/// turns over with the period. Neither is folded into the other. A key that
/// has been blocked is not drawn as a full ring — the flag is not a figure —
/// and the month's spend, which has no limit beside it, is left out.
extension ProviderProfile {
    static let neuralwatt = ProviderProfile(
        displayName: "Neuralwatt",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From portal.neuralwatt.com. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "neuralwatt",
        fetch: { await NeuralwattUsageService.fetch($0) }
    )
}

enum NeuralwattUsageService {
    static let endpoint = URL(string: "https://api.neuralwatt.com/v1/quota")!

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
        struct Balance: Decodable {
            let creditsRemainingUsd: Double?
            let totalCreditsUsd: Double?
            let creditsUsedUsd: Double?
        }

        struct Subscription: Decodable {
            let plan: String?
            let billingInterval: String?
            let currentPeriodStart: String?
            let currentPeriodEnd: String?
            let kwhIncluded: Double?
            let kwhUsed: Double?
            let kwhRemaining: Double?
        }

        struct Key: Decodable {
            struct Allowance: Decodable {
                let limitUsd: Double?
                let spentUsd: Double?
                let period: String?
            }

            let allowance: Allowance?
        }

        let balance: Balance?
        let subscription: Subscription?
        let key: Key?
    }

    /// Neuralwatt writes snake_case throughout.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? decoder.decode(Reply.self, from: data),
              let balance = reply.balance
        else { return context.unavailable(.unreadableReply) }

        // The subscription first: it is what the plan is, and it drives the
        // ring. The key's own allowance, where set, beside it.
        var windows: [UsageWindow] = []
        if let subscription = reply.subscription, let window = allowance(subscription) {
            windows.append(window)
        }
        if let allowance = reply.key?.allowance, let window = keyAllowance(allowance) {
            windows.append(window)
        }

        let prepaid = remaining(balance)
        guard !windows.isEmpty || prepaid != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(
            windows,
            plan: plan(reply.subscription?.plan),
            creditBalance: prepaid.flatMap { money($0, currency: "USD") },
            creditRemaining: prepaid.map { .init(amount: $0, currency: "USD") },
            at: now
        )
    }

    /// The subscription's kWh for this period. The allowance is the one
    /// stated, or failing that what was used plus what is left — both stated.
    private static func allowance(_ subscription: Reply.Subscription) -> UsageWindow? {
        guard let used = nonNegative(subscription.kwhUsed) else { return nil }
        let included = positive(subscription.kwhIncluded)
            ?? nonNegative(subscription.kwhRemaining).flatMap { positive(used + $0) }
        guard let included else { return nil }

        // The period is stated by its two ends, so its length may be divided
        // by. Without both, thirty days is only where it sorts.
        let start = ProfileHTTP.date(subscription.currentPeriodStart)
        let end = ProfileHTTP.date(subscription.currentPeriodEnd)
        let stated = start.flatMap { start in end.map { Int($0.timeIntervalSince(start)) } }.flatMap { $0 > 0 ? $0 : nil }
        let kind: UsageWindow.Kind = switch subscription.billingInterval?.lowercased() {
        case "month", "monthly": .monthly
        default: stated.map { .other(seconds: $0) } ?? .credits
        }
        let fraction = used / included
        return UsageWindow(
            id: "neuralwatt.subscription",
            kind: kind,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: stated ?? 30 * 86_400,
            resetsAt: end,
            reportsLength: stated != nil,
            isExhausted: fraction >= 1
        )
    }

    /// The key's own spending allowance, where one is set.
    private static func keyAllowance(_ allowance: Reply.Key.Allowance) -> UsageWindow? {
        guard let spent = nonNegative(allowance.spentUsd), let limit = positive(allowance.limitUsd) else { return nil }
        let length: (seconds: Int, stated: Bool) = switch allowance.period?.lowercased() {
        case "daily", "day": (86_400, true)
        case "weekly", "week": (7 * 86_400, true)
        default: (30 * 86_400, false)
        }
        let fraction = spent / limit
        return UsageWindow(
            id: "neuralwatt.key_allowance",
            kind: .spend,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: length.seconds,
            resetsAt: nil,
            reportsLength: length.stated,
            isExhausted: fraction >= 1
        )
    }

    /// Prepaid credit left, as stated, or the total less what was used when
    /// only those two are.
    private static func remaining(_ balance: Reply.Balance) -> Double? {
        if let remaining = nonNegative(balance.creditsRemainingUsd) { return remaining }
        guard let total = nonNegative(balance.totalCreditsUsd), let used = nonNegative(balance.creditsUsedUsd) else {
            return nil
        }
        return max(total - used, 0)
    }

    private static func plan(_ plan: String?) -> String? {
        guard let plan = plan?.trimmingCharacters(in: .whitespaces), !plan.isEmpty else { return nil }
        return plan.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func nonNegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func money(_ amount: Double, currency: String) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount))
    }
}
