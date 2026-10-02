// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A sub2api deployment's own accounting, read with a group API key.
///
/// sub2api is an open-source gateway somebody runs themselves: it fronts their
/// Claude, Codex, Gemini and Grok subscriptions and re-sells them as an
/// OpenAI-shaped API. Pulse carries it because it is the one shape this class
/// of service actually shares — the field names below are the ones a reader's
/// gateway answers with whether or not its operator has ever said what it runs.
///
/// One route, `GET {address}/v1/usage`, with the group key as a bearer token.
/// Nothing is ever sent through it: this reads accounting and does not make
/// model requests.
///
/// **The address is the reader's, and that is the whole difference from every
/// other provider here.** The other twenty know where to go; this one is told,
/// which means Pulse can be pointed at any host on the internet. So the
/// address is checked before a key is ever attached to a request — see
/// `usageURL(from:)` — and the rule is HTTPS, except on a private network
/// where there is nothing to intercept.
///
/// The reply carries whichever of four shapes the key's group is configured
/// for, and a key usually has exactly one:
///
/// ```json
/// { "isValid": true, "planName": "…", "unit": "USD",
///   "balance": 16.34, "remaining": 16.34,            // wallet
///   "quota": { "limit": 50, "used": 12, "remaining": 38 },
///   "subscription": { "daily_usage_usd": 3, "daily_limit_usd": 10, … },
///   "rate_limits": [ { "window": "5h", "limit": 100, "used": 9,
///                      "remaining": 91, "reset_at": "…" } ] }
/// ```
///
/// **A wallet is money and not an allowance**, so it draws no percentage at
/// all — the same rule DeepSeek's `.balanceOnly` follows, and for the same
/// reason: there is no denominator, and Pulse does not invent one. The rail
/// shows the money instead. The other three shapes state their own
/// denominators and are ordinary windows.
struct Sub2APIUsageService: Sendable {
    let enteredKey: String?
    /// The deployment's address, as the reader typed it. There is no default
    /// and nothing to fall back to: every one of these is somebody else's
    /// server.
    let address: String?

    /// Every reading is stamped with the deployment and key it came from, so a
    /// cached reading from another server or account never stands in for this
    /// one's failure —
    /// see `ProviderUsage.requiresScopeMatch`. Moving from one deployment to
    /// another used to leave the old server's balance on the ring, marked
    /// stale, for up to a day whenever the new one refused.
    func fetch() async -> ProviderUsage {
        var usage = await read()
        usage.sourceScope = GatewayAddress.scope(of: address, key: enteredKey)
        return usage
    }

    private func read() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.sub2api, reason: .apiKeyMissing)
        }

        let typed = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return .unavailable(.sub2api, reason: .serverAddressMissing)
        }
        guard let endpoint = Self.usageURL(from: typed) else {
            return .unavailable(.sub2api, reason: .serverAddressRefused)
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else {
            return .unavailable(.sub2api, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.sub2api, reason: .apiKeyRefused)
        case 429: return .unavailable(.sub2api, reason: .rateLimited)
        default: return .unavailable(.sub2api, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.sub2api, reason: .unreadableReply)
        }

        // The deployment's own word for a key it will not serve. It answers 200
        // and says so in the body, so this is not an HTTP status away.
        if reply.isValid == false {
            return .unavailable(.sub2api, reason: .apiKeyRefused)
        }

        let windows = Self.windows(from: reply)
        let wallet = Self.wallet(from: reply)

        guard !windows.isEmpty || wallet != nil else {
            return .unavailable(.sub2api, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.sub2api),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: reply.planName.flatMap { $0.isEmpty ? nil : $0 },
            creditBalance: wallet.map(Self.money),
            creditRemaining: wallet
        )
    }

    // MARK: - The address

    /// The usage URL for an address the reader typed, or nil if it may not be
    /// used.
    ///
    /// The rules — https except on a private network, no user info, no
    /// fragment, no query — are `GatewayAddress`'s, shared with the other
    /// self-hosted gateway. What is sub2api's alone is the route and the two
    /// suffixes a reader may already have typed: people paste the deployment's
    /// root, and people paste the route they tested with curl.
    static func usageURL(from typed: String) -> URL? {
        GatewayAddress.url(from: typed, path: "/v1/usage", trimming: ["/v1", "/v1/usage"])
    }

    // MARK: - Reading the reply

    struct Reply: Decodable {
        /// A key's total allowance, where the group sells one.
        struct Quota: Decodable {
            let limit: Double?
            let used: Double?
            let remaining: Double?
            let unit: String?
        }

        /// A subscription group's spend against its own daily, weekly and
        /// monthly ceilings. **No boundaries are reported** — the reply says
        /// how much has gone in each period and never when a period turns
        /// over — which is why these windows state no length and no reset.
        struct Subscription: Decodable {
            let dailyUsage: Double?
            let weeklyUsage: Double?
            let monthlyUsage: Double?
            let dailyLimit: Double?
            let weeklyLimit: Double?
            let monthlyLimit: Double?

            enum CodingKeys: String, CodingKey {
                case dailyUsage = "daily_usage_usd"
                case weeklyUsage = "weekly_usage_usd"
                case monthlyUsage = "monthly_usage_usd"
                case dailyLimit = "daily_limit_usd"
                case weeklyLimit = "weekly_limit_usd"
                case monthlyLimit = "monthly_limit_usd"
            }
        }

        /// A rolling window, and the one shape here that reports a real reset.
        struct RateLimit: Decodable {
            /// `5h`, `1d`, `7d` — a count and a unit, which is also the only
            /// statement of the window's length.
            let window: String?
            let limit: Double?
            let used: Double?
            let remaining: Double?
            let resetAt: String?

            enum CodingKeys: String, CodingKey {
                case window, limit, used, remaining
                case resetAt = "reset_at"
            }
        }

        /// The deployment's own word for whether it will serve this key.
        let isValid: Bool?
        let planName: String?
        let balance: Double?
        let remaining: Double?
        let unit: String?
        let quota: Quota?
        let subscription: Subscription?
        let rateLimits: [RateLimit]?

        enum CodingKeys: String, CodingKey {
            case isValid, planName, balance, remaining, unit, quota, subscription
            case rateLimits = "rate_limits"
        }
    }

    // MARK: - Mapping

    /// Every limit the reply states a denominator for, shortest first.
    ///
    /// **Nothing here is inferred.** A shape whose limit is missing, zero or
    /// not finite produces no window rather than a fraction of a number nobody
    /// gave, and the wallet produces none at all because money is not an
    /// allowance.
    static func windows(from reply: Reply) -> [UsageWindow] {
        var windows: [UsageWindow] = []

        // Rolling windows first: they are the only ones that report a reset,
        // so they are the only ones whose length may be drawn as a clock.
        for rate in reply.rateLimits ?? [] {
            guard
                let label = rate.window?.trimmingCharacters(in: .whitespaces), !label.isEmpty,
                let seconds = self.seconds(of: label),
                let fraction = self.fraction(used: rate.used, limit: rate.limit)
            else { continue }

            windows.append(UsageWindow(
                id: "rate.\(label.lowercased())",
                kind: kind(ofLength: seconds),
                scope: nil,
                usedFraction: fraction,
                windowSeconds: seconds,
                resetsAt: date(rate.resetAt),
                // The label *is* the length — "5h" is a statement, not a sort
                // key — so this one may be divided by.
                reportsLength: true,
                isExhausted: isSpent(rate.remaining)
            ))
        }

        if let quota = reply.quota, let fraction = fraction(used: quota.used, limit: quota.limit) {
            windows.append(UsageWindow(
                id: "quota",
                kind: .spend,
                scope: nil,
                usedFraction: fraction,
                // A total allowance with no period at all. Thirty days is a
                // sort key so it lands after the rolling windows, and
                // `reportsLength` says so.
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: isSpent(quota.remaining)
            ))
        }

        if let subscription = reply.subscription {
            let periods: [(String, UsageWindow.Kind, Int, Double?, Double?)] = [
                ("daily", .daily, 86_400, subscription.dailyUsage, subscription.dailyLimit),
                ("weekly", .weekly, 7 * 86_400, subscription.weeklyUsage, subscription.weeklyLimit),
                ("monthly", .monthly, 30 * 86_400, subscription.monthlyUsage, subscription.monthlyLimit),
            ]
            for (id, kind, seconds, used, limit) in periods {
                guard let fraction = fraction(used: used, limit: limit) else { continue }
                windows.append(UsageWindow(
                    id: "subscription.\(id)",
                    kind: kind,
                    scope: nil,
                    usedFraction: fraction,
                    windowSeconds: seconds,
                    // The reply names the period and never says when it turns
                    // over, so there is no clock to draw and no length to
                    // divide by — only a name and a sort order.
                    resetsAt: nil,
                    reportsLength: false
                ))
            }
        }

        return windows.sorted { $0.windowSeconds < $1.windowSeconds }
    }

    /// `5h` / `1d` / `7d` as seconds. A count and one of two units, so a
    /// deployment that reports `3h` is read rather than dropped.
    ///
    /// **Not `m`.** In a scheme of hours and days it could as well be a month
    /// as a minute, and read as minutes a `1m` window drew a sixty-second
    /// clock. A length Pulse cannot be sure of is not stated.
    static func seconds(of window: String) -> Int? {
        let text = window.lowercased()
        guard let unit = text.last, let count = Int(text.dropLast()), count > 0 else { return nil }
        switch unit {
        case "h": return count * 3_600
        case "d": return count * 86_400
        default: return nil
        }
    }

    /// The named kind for the three lengths Pulse has words for, and a plain
    /// length for everything else.
    static func kind(ofLength seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 5 * 3_600: .fiveHour
        case 86_400: .daily
        case 7 * 86_400: .weekly
        default: .other(seconds: seconds)
        }
    }

    /// How much of a stated allowance is gone, or nil where one was not
    /// stated.
    ///
    /// **A limit of zero is not a limit.** Dividing by it produces infinity,
    /// which the display clamps to a full ring — an account reported as spent
    /// on the strength of a field the deployment left blank.
    static func fraction(used: Double?, limit: Double?) -> Double? {
        guard
            let limit, limit.isFinite, limit > 0,
            let used, used.isFinite
        else { return nil }
        return min(max(used / limit, 0), 1)
    }

    /// Whether the deployment says this limit has nothing left.
    ///
    /// Its own `remaining`, not the arithmetic above: a field that is absent
    /// has said nothing, and reading that as zero marks a limit spent on the
    /// strength of silence.
    static func isSpent(_ remaining: Double?) -> Bool {
        guard let remaining, remaining.isFinite else { return false }
        return remaining <= 0
    }

    /// The wallet, where the group sells one.
    ///
    /// `balance` is the deployment's own word for it. Root `remaining` is the
    /// same figure in a wallet group and the remainder of something else in
    /// the others, so it is read as money only when there is no quota and no
    /// subscription for it to be the remainder *of*.
    static func wallet(from reply: Reply) -> ProviderUsage.CreditAmount? {
        let walletOnly = reply.quota == nil && reply.subscription == nil
        guard
            let amount = reply.balance ?? (walletOnly ? reply.remaining : nil),
            amount.isFinite,
            let currency = self.currency(reply)
        else { return nil }
        return .init(amount: amount, currency: currency)
    }

    /// What the wallet is denominated in, or nil if it cannot be said.
    ///
    /// **Nil rather than a default.** A deployment selling credits reports a
    /// `unit` that is not a currency, and calling those dollars is a figure
    /// with the wrong name on it. A missing unit is the ordinary case and is
    /// USD, which is what sub2api's own dashboard assumes.
    static func currency(_ reply: Reply) -> String? {
        let unit = (reply.unit ?? reply.quota?.unit)?
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        guard let unit, !unit.isEmpty else { return "USD" }
        guard unit.count == 3, unit.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return unit
    }

    static func money(_ wallet: ProviderUsage.CreditAmount) -> String {
        wallet.amount.formatted(
            .currency(code: wallet.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`, and this
    /// parses at most a handful of stamps a refresh. Deployments differ on
    /// whether they send fractional seconds, so both are tried.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func storedKey() -> String? { APIKeyStore.key(for: .sub2api) }
}
