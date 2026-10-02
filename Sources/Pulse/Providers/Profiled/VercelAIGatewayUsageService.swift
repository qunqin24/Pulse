// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Vercel AI Gateway: the team's remaining credit, in US dollars. There is no
/// allowance and no period, so there is no ring to draw — only a balance.
///
/// Read with an AI Gateway API key the user pastes, from
/// `GET https://ai-gateway.vercel.sh/v1/credits`. The shape is second-hand —
/// taken from CodexBar's Vercel provider and Vercel's public API reference it
/// cites, not from a captured reply — and the fixture in the tests says so.
///
/// The reply also carries lifetime spend. Spend with no limit beside it has
/// nowhere to go in Pulse yet, so it is left out.
extension ProviderProfile {
    static let vercelAIGateway = ProviderProfile(
        displayName: "Vercel AI Gateway",
        billing: .api,
        iconResource: "vercel",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("An AI Gateway API key from vercel.com. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "vercel-ai-gateway",
        fetch: { await VercelAIGatewayUsageService.fetch($0) }
    )
}

enum VercelAIGatewayUsageService {
    static let endpoint = URL(string: "https://ai-gateway.vercel.sh/v1/credits")!

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

    /// Both figures are decimal strings, "95.50", in US dollars.
    private struct Reply: Decodable {
        let balance: String?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let text = reply.balance?.trimmingCharacters(in: .whitespaces),
              let amount = Double(text), amount.isFinite
        else { return context.unavailable(.unreadableReply) }

        // Zero and below are kept: an empty or overdrawn team is a reading.
        let balance = ProviderUsage.CreditAmount(amount: amount, currency: "USD")
        return context.reading(
            [],
            creditBalance: money(amount, currency: "USD"),
            creditRemaining: balance,
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
