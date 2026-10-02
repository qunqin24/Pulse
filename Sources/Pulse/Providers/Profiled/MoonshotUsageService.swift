// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Moonshot, the Kimi Open Platform API: the money left on the account. Not
/// Kimi Code, which is a subscription with windows and its own provider.
///
/// Read with an API key the user pastes, from the platform's own balance
/// endpoint, `GET /v1/users/me/balance`. There are two platforms with two
/// hosts, and a key is issued by one of them:
///
/// - international, `api.moonshot.ai`, priced in US dollars;
/// - China mainland, `api.moonshot.cn`, priced in yuan.
///
/// **Which one is found by asking, not chosen in Settings** — Pulse has no
/// region picker for a profiled provider. The international host is asked
/// first; a key it refuses is asked of the China host, which is Moonshot's
/// too. Whichever accepted it is remembered for the rest of the launch, so a
/// China key is not offered to the other host every refresh. The currency
/// follows the host that answered: the reply itself names none.
///
/// The shape is second-hand — taken from CodexBar's Moonshot plugin and its
/// tests, not from a captured reply — and the fixture in the tests says so.
/// The platform reports a balance and no allowance, so there is no ring.
extension ProviderProfile {
    static let moonshot = ProviderProfile(
        displayName: "Moonshot",
        billing: .api,
        iconResource: "moonshot",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From the Kimi Open Platform console, international or China. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "moonshot",
        fetch: { await MoonshotUsageService.fetch($0) }
    )
}

enum MoonshotUsageService {
    enum Region: CaseIterable, Sendable {
        case international
        case china

        var endpoint: URL {
            switch self {
            case .international: URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
            case .china: URL(string: "https://api.moonshot.cn/v1/users/me/balance")!
            }
        }

        /// What the platform prices in. Stated by the region, not the reply.
        var currency: String {
            switch self {
            case .international: "USD"
            case .china: "CNY"
            }
        }
    }

    /// The host each key was last accepted by, for this launch only.
    private actor Accepted {
        var regions: [String: Region] = [:]
        func region(for key: String) -> Region? { regions[key] }
        func remember(_ region: Region, for key: String) { regions[key] = region }
    }

    private static let accepted = Accepted()

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }

        // The host that took this key last time first, then the other.
        let known = await accepted.region(for: key)
        let order = known.map { first in [first] + Region.allCases.filter { $0 != first } } ?? Region.allCases

        for region in order {
            switch await ProfileHTTP.data(for: ProfileHTTP.bearer(region.endpoint, token: key), session: session) {
            case .success(let data):
                await accepted.remember(region, for: key)
                return reading(from: data, region: region, context: context)
            // Refused by one platform: it may be the other's key.
            case .failure(.apiKeyRefused):
                continue
            // Anything else is an answer about the service, not the key.
            case .failure(let reason):
                return context.unavailable(reason)
            }
        }
        return context.unavailable(.apiKeyRefused)
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Balance: Decodable {
            let available: Double?

            enum CodingKeys: String, CodingKey { case available = "available_balance" }
        }

        let code: Int?
        let status: Bool?
        let data: Balance?
    }

    static func reading(from data: Data, region: Region, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let code = reply.code, let status = reply.status
        else { return context.unavailable(.unreadableReply) }
        guard code == 0, status else { return context.unavailable(.serverError) }
        guard let available = reply.data?.available, available.isFinite
        else { return context.unavailable(.unreadableReply) }

        // Kept as reported, below zero included: an account in deficit is
        // one somebody should see, not one to round up to nothing.
        return context.reading(
            [],
            creditBalance: money(available, currency: region.currency),
            creditRemaining: ProviderUsage.CreditAmount(amount: available, currency: region.currency),
            at: now
        )
    }

    static func money(_ amount: Double, currency: String) -> String {
        amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }
}
