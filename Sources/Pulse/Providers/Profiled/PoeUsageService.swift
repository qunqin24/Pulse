// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Poe: the account's point balance. Poe reports no allowance and no period
/// beside it, so there is no ring — only the balance.
///
/// Read with a key the user pastes, from Poe's usage API:
/// `GET https://api.poe.com/usage/current_balance`. The shape is second-hand
/// — taken from CodexBar's Poe plugin and its docs, not from a captured reply
/// — and the fixture in the tests says so.
///
/// CodexBar also pages through `/usage/points_history` for points spent per
/// day and per bot. That is spend with no limit behind it, which Pulse has
/// nowhere to show yet, so it is not asked for. Points are Poe's own unit,
/// not money, and are never compared against a currency.
extension ProviderProfile {
    static let poe = ProviderProfile(
        displayName: "Poe",
        billing: .api,
        iconResource: "poe",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From poe.com/api/keys. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "poe",
        fetch: { await PoeUsageService.fetch($0) }
    )
}

enum PoeUsageService {
    static let endpoint = URL(string: "https://api.poe.com/usage/current_balance")!

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

    /// Poe writes the balance as a number, or as a numeric string.
    private struct Reply: Decodable {
        let points: Double?

        enum CodingKeys: String, CodingKey { case points = "current_point_balance" }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? container.decode(Double.self, forKey: .points) {
                points = number
            } else if let text = try? container.decode(String.self, forKey: .points) {
                points = Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                points = nil
            }
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let points = reply.points, points.isFinite
        else { return context.unavailable(.unreadableReply) }
        return context.reading([], creditBalance: text(points), at: now)
    }

    static func text(_ points: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = LocalizationSource.locale
        let number = formatter.string(from: NSNumber(value: points)) ?? String(Int(points))
        return .localized("\(number) points")
    }
}
