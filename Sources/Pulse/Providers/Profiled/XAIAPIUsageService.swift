// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// The xAI developer platform: a team's prepaid credit, from xAI's documented
/// Management API. Not Grok — that is the consumer subscription, read by its
/// own provider — and nothing is shared between the two.
///
/// `GET https://management-api.x.ai/v1/billing/teams/{team}/prepaid/balance`,
/// with a **management** key; an inference key is refused. The ledger is
/// inverted and in cents as a string: a $10 top-up reads `"-1000"`, so what is
/// left is the negated figure. It is the **posted** ledger, which xAI updates
/// when a billing cycle closes, so mid-cycle it can read higher than the
/// console's live remainder. The shape is second-hand — from CodexBar's xAI
/// provider and its docs — and the fixture in the tests says so.
///
/// **Two values, one field.** The balance is per team and the key does not
/// name one, so the field takes `TeamID:ManagementKey`, the way Volcengine's
/// takes its key pair. Left out: the thirty-day spend history, which Pulse
/// has no place for.
extension ProviderProfile {
    static let xaiAPI = ProviderProfile(
        displayName: "xAI API",
        billing: .api,
        iconResource: "xai",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: {
            .localized("TeamID:ManagementKey, from console.x.ai. An inference key won't work. Stored encrypted on this Mac.")
        },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "xai-api",
        fetch: { await XAIAPIUsageService.fetch($0) }
    )
}

enum XAIAPIUsageService {
    /// The team and the key out of `TeamID:ManagementKey`. A team id that
    /// could step out of the path is not one.
    static func credential(_ text: String) -> (team: String, key: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let team = text[..<colon].trimmingCharacters(in: .whitespaces)
        let key = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !team.isEmpty, !key.isEmpty, !team.contains("/"), team != ".", team != ".." else { return nil }
        return (team, key)
    }

    static func endpoint(team: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "management-api.x.ai"
        components.path = "/v1/billing/teams/\(team)/prepaid/balance"
        return components.url
    }

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let text = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        // Not in the documented shape, so nothing is sent: it is not a key
        // xAI turned away, but it is the key field that needs fixing.
        guard let (team, key) = credential(text), let url = endpoint(team: team) else {
            return context.unavailable(.apiKeyRefused)
        }
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(url, token: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Total: Decodable { let val: String? }
        let total: Total?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let raw = reply.total?.val?.trimmingCharacters(in: .whitespaces),
              raw.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let cents = Double(raw)
        else { return context.unavailable(.unreadableReply) }

        let dollars = -cents / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = LocalizationSource.locale
        return context.reading(
            [],
            creditBalance: formatter.string(from: NSNumber(value: dollars)),
            creditRemaining: .init(amount: dollars, currency: "USD"),
            at: now
        )
    }
}
