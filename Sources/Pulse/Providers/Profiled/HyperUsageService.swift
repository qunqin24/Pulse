// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Charm's Hyper: the account's Hypercredit balance, and nothing else — the
/// service reports no allowance and no period, so there is no ring.
///
/// Read with a key the user pastes, from Hyper's credits route:
/// `GET https://hyper.charm.land/v1/credits`. The shape is second-hand —
/// taken from CodexBar's Hyper plugin, not from a captured reply — and the
/// fixture in the tests says so.
///
/// CodexBar also tries a browser session for hyper.charm.land before the key.
/// Pulse has one credential per provider, and the key reaches the same
/// figure, so the key is the only route here. Hypercredits are Charm's own
/// unit rather than money, so the balance is shown and never compared
/// against a currency.
extension ProviderProfile {
    static let hyper = ProviderProfile(
        displayName: "Hyper",
        billing: .api,
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From hyper.charm.land. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "hyper",
        fetch: { await HyperUsageService.fetch($0) }
    )
}

enum HyperUsageService {
    static let endpoint = URL(string: "https://hyper.charm.land/v1/credits")!

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

    private struct Reply: Decodable { let balance: Double? }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let balance = reply.balance, balance.isFinite, balance >= 0
        else { return context.unavailable(.unreadableReply) }
        return context.reading([], creditBalance: text(balance), at: now)
    }

    /// "1,234.5 HC". HC is Charm's own abbreviation for Hypercredits, the
    /// unit's name, and reads the same in every language.
    static func text(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.locale = LocalizationSource.locale
        let number = formatter.string(from: NSNumber(value: balance)) ?? String(balance)
        return "\(number) HC"
    }
}
