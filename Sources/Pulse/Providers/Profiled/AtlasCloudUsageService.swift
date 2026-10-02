// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Atlas Cloud: the account's available balance, in the currency the service
/// states. A balance, not an allowance — so no ring.
///
/// Read with a key the user pastes, from Atlas Cloud's billing API:
/// `GET https://api.atlascloud.ai/public/v1/balance`. Reading it needs a key
/// with account-balance permission: the account owner's, or a team's
/// Account Admin or Finance key. The shape is second-hand — taken from
/// CodexBar's Atlas Cloud plugin and its docs, not from a captured reply —
/// and the fixture in the tests says so.
///
/// Coding Plan quotas are a separate meter behind another route and are not
/// read. A negative balance is kept as reported: it is money owed.
extension ProviderProfile {
    static let atlasCloud = ProviderProfile(
        displayName: "Atlas Cloud",
        billing: .api,
        iconResource: "atlascloud",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From atlascloud.ai, with permission to read the balance. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "atlas-cloud",
        fetch: { await AtlasCloudUsageService.fetch($0) }
    )
}

enum AtlasCloudUsageService {
    static let endpoint = URL(string: "https://api.atlascloud.ai/public/v1/balance")!

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
        struct Available: Decodable {
            let value: String?
            let currency: String?
        }

        let object: String?
        let scope: String?
        let available: Available?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.object == "balance", reply.scope == "account",
              let text = reply.available?.value?.trimmingCharacters(in: .whitespaces),
              let amount = Double(text), amount.isFinite,
              let currency = reply.available?.currency?.trimmingCharacters(in: .whitespaces).uppercased(),
              currency.count == 3, currency.allSatisfy(\.isLetter)
        else { return context.unavailable(.unreadableReply) }

        return context.reading(
            [],
            creditBalance: money(amount, currency: currency),
            creditRemaining: ProviderUsage.CreditAmount(amount: amount, currency: currency),
            at: now
        )
    }

    static func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }
}
