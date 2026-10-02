// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// ZenMux, a model gateway sold by subscription: a rolling five-hour and a
/// rolling seven-day quota, each reported as a share used by the service
/// itself, and a pay-as-you-go balance in US dollars beside them.
///
/// Read with a **Management** API key the user pastes — ZenMux's ordinary
/// inference keys are refused by these endpoints — from
/// `GET https://zenmux.ai/api/v1/management/subscription/detail`, and the
/// balance from `…/payg/balance`. The shapes are second-hand — taken from
/// CodexBar's ZenMux provider and its tests, not from a captured reply — and
/// the fixtures in the tests say so.
///
/// The balance is best-effort: the quotas are the reading, and a balance that
/// cannot be had leaves them standing rather than failing the refresh. A
/// monthly allowance the reply sizes but does not say how much of is used is
/// left off.
extension ProviderProfile {
    static let zenMux = ProviderProfile(
        displayName: "ZenMux",
        iconResource: "zenmux",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("A Management API key from zenmux.ai. An ordinary API key won't work. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "zenmux",
        fetch: { await ZenMuxUsageService.fetch($0) }
    )
}

enum ZenMuxUsageService {
    static let subscriptionEndpoint = URL(string: "https://zenmux.ai/api/v1/management/subscription/detail")!
    static let balanceEndpoint = URL(string: "https://zenmux.ai/api/v1/management/payg/balance")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        let subscription: Data
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(subscriptionEndpoint, token: key), session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): subscription = data
        }
        // Asked only once the quotas are in hand; whatever becomes of it, the
        // quotas are what is shown.
        let balance = try? await ProfileHTTP.data(
            for: ProfileHTTP.bearer(balanceEndpoint, token: key),
            session: session
        ).get()
        return reading(from: subscription, balance: balance, context: context)
    }

    // MARK: - Reading the reply

    private struct Envelope<Payload: Decodable>: Decodable {
        let success: Bool?
        let data: Payload?
    }

    private struct Subscription: Decodable {
        struct Plan: Decodable { let tier: String? }

        struct Quota: Decodable {
            /// A fraction, 0.0715 for 7.15%, as ZenMux writes it.
            let usagePercentage: Double?
            let resetsAt: String?
        }

        let plan: Plan?
        let quota5Hour: Quota?
        let quota7Day: Quota?
    }

    private struct Balance: Decodable {
        let currency: String?
        let totalCredits: Double?
    }

    /// ZenMux writes snake_case throughout.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func reading(from data: Data, balance: Data? = nil, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? decoder.decode(Envelope<Subscription>.self, from: data),
              reply.success == true,
              let detail = reply.data
        else { return context.unavailable(.unreadableReply) }

        // Both quotas are named for their length, so the length is stated.
        let named: [(String, Subscription.Quota?, UsageWindow.Kind, Int)] = [
            ("five_hour", detail.quota5Hour, .fiveHour, 5 * 3_600),
            ("seven_day", detail.quota7Day, .weekly, 7 * 86_400),
        ]
        let windows = named.compactMap { id, quota, kind, seconds -> UsageWindow? in
            guard let fraction = quota?.usagePercentage, fraction.isFinite, fraction >= 0 else { return nil }
            return UsageWindow(
                id: "zenmux.\(id)",
                kind: kind,
                scope: nil,
                usedFraction: fraction,
                windowSeconds: seconds,
                resetsAt: ProfileHTTP.date(quota?.resetsAt),
                reportsLength: true,
                isExhausted: fraction >= 1
            )
        }

        let payg = balance.flatMap(Self.balance(from:))
        guard !windows.isEmpty || payg != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(
            windows,
            plan: plan(detail.plan?.tier),
            creditBalance: payg.flatMap { money($0.amount, currency: $0.currency) },
            creditRemaining: payg,
            at: now
        )
    }

    /// The pay-as-you-go balance, in the currency ZenMux names. Kept negative
    /// when it is: an overdue account is not an empty one.
    static func balance(from data: Data) -> ProviderUsage.CreditAmount? {
        guard let reply = try? decoder.decode(Envelope<Balance>.self, from: data),
              reply.success == true,
              let amount = reply.data?.totalCredits, amount.isFinite,
              let currency = reply.data?.currency?.trimmingCharacters(in: .whitespaces).uppercased(),
              currency.count == 3
        else { return nil }
        return .init(amount: amount, currency: currency)
    }

    private static func plan(_ tier: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespaces), !tier.isEmpty else { return nil }
        return tier.prefix(1).uppercased() + tier.dropFirst().lowercased()
    }

    private static func money(_ amount: Double, currency: String) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount))
    }
}
