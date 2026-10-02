// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// OpenAI's API platform: the prepaid credit left on the account, and nothing
/// else.
///
/// Read with a key the user pastes, from the billing route OpenAI's own
/// dashboard used for the balance:
/// `GET https://api.openai.com/v1/dashboard/billing/credit_grants`. It is not in
/// OpenAI's current public reference and it answers older user keys only; the
/// shape is second-hand — taken from CodexBar's OpenAI plugin, not from a
/// captured reply — and the fixture in the tests says so.
///
/// **No ring.** The API has no allowance to be a fraction of: what OpenAI
/// reports is money granted, spent and left. The balance is shown as a
/// balance. The organization's spend over the last days — what an Admin key
/// reads, and what CodexBar draws — is a total with no limit behind it, and
/// Pulse has nowhere to show one yet.
///
/// **A key the balance route turns away is not yet a bad key.** Admin and
/// project keys are refused there by design, so the refusal is checked
/// against the Admin API's cost route before anything is said: a key that
/// reads costs works, and the honest answer is that it reports no limits.
extension ProviderProfile {
    static let openAIPlatform = ProviderProfile(
        displayName: "OpenAI API",
        billing: .api,
        iconResource: "openai",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From platform.openai.com. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "openai-api",
        fetch: { await OpenAIPlatformUsageService.fetch($0) }
    )
}

enum OpenAIPlatformUsageService {
    static let creditGrants = URL(string: "https://api.openai.com/v1/dashboard/billing/credit_grants")!

    /// One day of the organization's costs, asked for only to learn whether
    /// the key is an Admin key. The figures are not read.
    static func costsProbe(now: Date = Date()) -> URL {
        let start = Int(now.timeIntervalSince1970) - 86_400
        return URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(start)&limit=1")!
    }

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.reply(for: ProfileHTTP.bearer(creditGrants, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let reply):
            switch reply.status {
            case 200..<300, 429, 500...:
                switch ProfileHTTP.classify(reply) {
                case .success(let data): return reading(from: data, context: context)
                case .failure(let reason): return context.unavailable(reason)
                }
            default:
                // Refused, or a route this key's kind cannot see: ask the
                // Admin API whether the key itself is any good.
                let probe = ProfileHTTP.bearer(costsProbe(), token: key)
                switch await ProfileHTTP.data(for: probe, session: session) {
                case .success: return context.unavailable(.noLimitsReported)
                case .failure(let reason): return context.unavailable(reason)
                }
            }
        }
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        let totalGranted: Double?
        let totalUsed: Double?
        let totalAvailable: Double?

        enum CodingKeys: String, CodingKey {
            case totalGranted = "total_granted"
            case totalUsed = "total_used"
            case totalAvailable = "total_available"
        }
    }

    /// The route's figures are dollars. It names no currency because the
    /// platform bills in one.
    static let currency = "USD"

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.totalGranted != nil || reply.totalUsed != nil || reply.totalAvailable != nil
        else { return context.unavailable(.unreadableReply) }
        // A balance that isn't one is left off, and then there is nothing.
        guard let available = reply.totalAvailable, available.isFinite, available >= 0 else {
            return context.unavailable(.noLimitsReported)
        }
        return context.reading(
            [],
            creditBalance: money(available),
            creditRemaining: .init(amount: available, currency: currency),
            at: now
        )
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
