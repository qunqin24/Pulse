// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// xKiro (not AWS's Kiro): a plan's spend windows, the daily free-token
/// allowance, and the pay-as-you-go wallet.
///
/// Read with a key the user pastes, from xKiro's documented usage route:
/// `GET https://api.xkiro.com/v1/usage`, which xKiro says costs nothing and
/// counts against no limit. The shape is second-hand — taken from CodexBar's
/// xKiro plugin and tests and from the example replies in xKiro's own docs
/// (docs.xkiro.com/api/usage), not from a captured reply — and the fixture in
/// the tests says so.
///
/// CodexBar reads only the free tokens. The plan windows and the wallet are
/// in the same documented reply, each with the figures they need — a window
/// states its length, its cap, what is spent and when it resets — so they are
/// read here too.
///
/// **The free-token reset is xKiro's documented rule**, midnight UTC, and not
/// a figure in the reply: `used_today` and `limit_per_day` name the day, and
/// the docs name its boundary.
extension ProviderProfile {
    static let xKiro = ProviderProfile(
        displayName: "xKiro",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From xkiro.com. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        spendingIsWatchedLocally: false,
        setupSlug: "xkiro",
        fetch: { await XKiroUsageService.fetch($0) }
    )
}

enum XKiroUsageService {
    static let endpoint = URL(string: "https://api.xkiro.com/v1/usage")!

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

    /// xKiro writes money as fixed-point strings: `"200.000000"`.
    struct Money: Decodable {
        let value: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                value = Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
            } else {
                value = (try? container.decode(Double.self)).flatMap { $0.isFinite ? $0 : nil }
            }
        }
    }

    private struct Reply: Decodable {
        struct Window: Decodable {
            let kind: String?
            let windowSec: Int?
            let spentUsd: Money?
            let capUsd: Money?
            let resetsInSec: Double?

            enum CodingKeys: String, CodingKey {
                case kind
                case windowSec = "window_sec"
                case spentUsd = "spent_usd"
                case capUsd = "cap_usd"
                case resetsInSec = "resets_in_sec"
            }
        }

        struct FreeTokens: Decodable {
            let usedToday: Double?
            let limitPerDay: Double?

            enum CodingKeys: String, CodingKey {
                case usedToday = "used_today"
                case limitPerDay = "limit_per_day"
            }
        }

        struct Wallet: Decodable {
            let balanceUsd: Money?

            enum CodingKeys: String, CodingKey { case balanceUsd = "balance_usd" }
        }

        let object: String?
        let plan: String?
        let windows: [Window]?
        let freeTokens: FreeTokens?
        let wallet: Wallet?

        enum CodingKeys: String, CodingKey {
            case object, plan, windows, wallet
            case freeTokens = "free_tokens"
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.object == "usage" else {
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []

        for window in reply.windows ?? [] {
            // A whole number of hours, or it can't be named without rounding.
            guard let seconds = window.windowSec, seconds >= 3_600, seconds % 3_600 == 0,
                  let spent = window.spentUsd?.value, spent >= 0,
                  let cap = window.capUsd?.value, cap > 0
            else { continue }
            windows.append(UsageWindow(
                id: "xkiro.\(window.kind ?? String(seconds))",
                kind: kind(ofLength: seconds),
                scope: nil,
                usedFraction: spent / cap,
                windowSeconds: seconds,
                resetsAt: window.resetsInSec.flatMap { $0.isFinite && $0 >= 0 ? now.addingTimeInterval($0) : nil },
                isExhausted: spent >= cap
            ))
        }

        // A null daily limit is "unlimited": a statement, not a denominator.
        if let used = reply.freeTokens?.usedToday, used.isFinite, used >= 0,
           let limit = reply.freeTokens?.limitPerDay, limit.isFinite, limit > 0 {
            windows.append(UsageWindow(
                id: "xkiro.free_tokens",
                kind: .daily,
                scope: nil,
                usedFraction: used / limit,
                windowSeconds: 86_400,
                resetsAt: nextMidnightUTC(after: now),
                isExhausted: used >= limit
            ))
        }

        let balance = reply.wallet?.balanceUsd?.value
        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }
        let plan = reply.plan?.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.reading(
            windows.sorted { $0.windowSeconds < $1.windowSeconds },
            plan: plan?.isEmpty == false ? plan?.capitalized : nil,
            creditBalance: balance.flatMap { money($0, currency: "USD") },
            creditRemaining: balance.map { ProviderUsage.CreditAmount(amount: $0, currency: "USD") },
            at: now
        )
    }

    /// Named by the length xKiro states: five hours and a week are the two
    /// it documents; anything else by its number of hours or days.
    private static func kind(ofLength seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 5 * 3_600: .fiveHour
        case 86_400: .daily
        case 7 * 86_400: .weekly
        default: .other(seconds: seconds)
        }
    }

    static func nextMidnightUTC(after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                 matchingPolicy: .nextTime)
    }

    private static func money(_ amount: Double, currency: String) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount))
    }
}
