// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// DeepInfra, pay-as-you-go inference: the prepaid balance in US dollars, and
/// — only where the account has set one — the billing cycle's spend against
/// its own spending limit.
///
/// Read with an API key the user pastes, from
/// `GET https://api.deepinfra.com/payment/checklist?compute_owed=true`. The
/// shape is second-hand — taken from CodexBar's DeepInfra provider and its
/// tests, not from a captured reply — and the fixture in the tests says so.
///
/// DeepInfra keeps its ledger inverted: prepaid money is a **negative**
/// `stripe_balance`, and spend not yet billed is `recent`. What is left is the
/// one taken from the other, both as reported; a positive result is money
/// owed and is shown as a negative balance, not as nothing.
///
/// Left out on purpose: the month's spend (a figure with no limit beside it),
/// and a suspended account shown as a full ring — the checklist's flag is not
/// a share of anything, and drawing 100% from it would be a figure nobody
/// reported.
extension ProviderProfile {
    static let deepInfra = ProviderProfile(
        displayName: "DeepInfra",
        billing: .api,
        iconResource: "deepinfra",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From deepinfra.com. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "deepinfra",
        fetch: { await DeepInfraUsageService.fetch($0) }
    )
}

enum DeepInfraUsageService {
    static let endpoint = URL(string: "https://api.deepinfra.com/payment/checklist?compute_owed=true")!

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

    /// All in US dollars.
    private struct Reply: Decodable {
        let stripeBalance: Double?
        let recent: Double?
        let limit: Double?

        enum CodingKeys: String, CodingKey {
            case stripeBalance = "stripe_balance"
            case recent, limit
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let ledger = reply.stripeBalance, ledger.isFinite,
              let recent = reply.recent, recent.isFinite
        else { return context.unavailable(.unreadableReply) }

        // A negative `recent` is not spend; it is read as none. Subtracted
        // from zero rather than negated, so an empty account is $0.00 and
        // not -$0.00.
        let unbilled = max(recent, 0)
        let available = 0 - (ledger + unbilled)

        var windows: [UsageWindow] = []
        // The account's own limit, where it has set one. No limit, or a
        // limit of zero or less, is no ring — never a ring at zero.
        if let limit = reply.limit, limit.isFinite, limit > 0 {
            let fraction = unbilled / limit
            windows.append(UsageWindow(
                id: "deepinfra.spend",
                kind: .spend,
                scope: nil,
                usedFraction: fraction,
                // A billing cycle, whose length is not stated: a sort key.
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: fraction >= 1
            ))
        }

        return context.reading(
            windows,
            creditBalance: money(available, currency: "USD"),
            creditRemaining: .init(amount: available, currency: "USD"),
            at: now
        )
    }

    private static func money(_ amount: Double, currency: String) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount))
    }
}
