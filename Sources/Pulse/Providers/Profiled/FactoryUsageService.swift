// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Factory, the company behind the Droid agent: either a five-hour, a weekly
/// and a monthly limit, each a percentage Factory states, or — on the older
/// billing — a Standard and a Premium token allowance for the billing period.
///
/// Read with a key the user pastes (`fk-…`, from app.factory.ai's API keys
/// page), sent as a bearer token to `api.factory.ai` and nowhere else. Three
/// requests, in the order Factory's own web app makes them:
///
/// 1. `GET /api/app/auth/me` — the plan's name and the user's id. This is the
///    one that says whether the key is any good.
/// 2. `GET /api/billing/limits` — the token-rate-limits billing. Only an
///    account that says `usesTokenRateLimitsBilling` is read from here; any
///    other answer, including a failure, means the older billing is asked.
/// 3. `GET /api/organization/subscription/usage` — the Standard and Premium
///    allowances, for everyone else.
///
/// The shapes are second-hand — taken from CodexBar's Factory provider and
/// its tests, not from a captured reply — and the fixtures in the tests say so.
///
/// **What CodexBar does and this does not.** It draws a window whose stated
/// end has passed as 0%, because Factory's own page does; here a figure for a
/// window that is over is left off, and comes back when the service states a
/// new one. It treats an allowance over a trillion tokens as "unlimited" and
/// draws usage against a hundred million it chose; here that limit is left
/// off. And it reads a `usedRatio` above 1 as a percentage when the allowance
/// is missing; here a ratio whose scale is a guess is not read at all.
extension ProviderProfile {
    static let factory = ProviderProfile(
        displayName: "Factory",
        iconResource: "extension",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From app.factory.ai. Stored encrypted on this Mac.") },
        // The extra-usage balance is shown, but it is overflow: spent only once
        // the limits are, and the limits are the reading. Droid spends them
        // from this Mac, so the provider stays watched rather than being paced
        // like a prepaid wallet.
        reportsSpendableBalance: false,
        setupSlug: "factory",
        discoveryPaths: [".factory"],
        fetch: { await FactoryUsageService.fetch($0) }
    )
}

enum FactoryUsageService {
    static let base = URL(string: "https://api.factory.ai")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }

        let me: Data
        switch await ProfileHTTP.data(for: request(base.appendingPathComponent("api/app/auth/me"), key: key),
                                      session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): me = data
        }
        let identity = account(from: me)

        // The newer billing, when the account is on it. Anything else — a
        // failure included — is Factory saying to ask the older route, which
        // is what its own web app does.
        if case .success(let data) = await ProfileHTTP.data(
            for: request(base.appendingPathComponent("api/billing/limits"), key: key), session: session),
           let reading = limitsReading(from: data, plan: identity.plan, context: context) {
            return reading
        }

        var components = URLComponents(url: base.appendingPathComponent("api/organization/subscription/usage"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "useCache", value: "true")]
            + (identity.userID.map { [URLQueryItem(name: "userId", value: $0)] } ?? [])
        switch await ProfileHTTP.data(for: request(components.url!, key: key), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return allowanceReading(from: data, plan: identity.plan, context: context)
        }
    }

    /// The headers Factory's web app sends, which are the ones CodexBar has
    /// seen it accept a key with.
    private static func request(_ url: URL, key: String) -> URLRequest {
        var request = ProfileHTTP.bearer(url, token: key)
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")
        request.setValue("https://app.factory.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://app.factory.ai/", forHTTPHeaderField: "Referer")
        return request
    }

    // MARK: - Who is asking

    private struct Me: Decodable {
        struct Organization: Decodable {
            struct Subscription: Decodable {
                struct Orb: Decodable {
                    struct Plan: Decodable { let name: String? }
                    let plan: Plan?
                }

                let factoryTier: String?
                let orbSubscription: Orb?
            }

            let subscription: Subscription?
        }

        struct Profile: Decodable { let id: String? }

        let organization: Organization?
        let userProfile: Profile?
    }

    /// The plan's name and the user's id, when the reply carries them. Neither
    /// is needed for a reading, so a reply without them is not a failure.
    static func account(from data: Data) -> (plan: String?, userID: String?) {
        guard let me = try? JSONDecoder().decode(Me.self, from: data) else { return (nil, nil) }
        let subscription = me.organization?.subscription
        let plan = [subscription?.orbSubscription?.plan?.name, subscription?.factoryTier.map(\.capitalized)]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let userID = me.userProfile?.id?.trimmingCharacters(in: .whitespaces)
        return (plan, userID?.isEmpty == false ? userID : nil)
    }

    // MARK: - The token-rate-limits billing

    private struct Limits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let windowEnd: FactoryDate?
            let secondsRemaining: Double?
        }

        struct Pool: Decodable {
            let fiveHour: Window?
            let weekly: Window?
            let monthly: Window?
        }

        struct Pools: Decodable {
            let standard: Pool?
            let core: Pool?
        }

        let usesTokenRateLimitsBilling: Bool?
        let limits: Pools?
        let extraUsageBalanceCents: Int?
        let extraUsageAllowed: Bool?
    }

    /// A date Factory writes as seconds, as milliseconds, as either in a
    /// string, or as ISO 8601 — CodexBar has seen all four.
    private struct FactoryDate: Decodable {
        let date: Date?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                date = Self.epoch(number)
            } else if let text = try? container.decode(String.self) {
                date = Double(text).flatMap(Self.epoch) ?? ProfileHTTP.date(text)
            } else {
                date = nil
            }
        }

        /// Anything past 10¹² is milliseconds: as seconds it would be the year
        /// 33,000.
        private static func epoch(_ number: Double) -> Date? {
            guard number.isFinite, number > 0 else { return nil }
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1_000 : number)
        }
    }

    /// The three windows, each with the length its name states. `monthly` is
    /// a billing month rather than a fixed thirty days, so its length is only
    /// a sort key and is not claimed.
    private static func shapes(of pool: Limits.Pool)
        -> [(window: Limits.Window?, name: String, kind: UsageWindow.Kind, seconds: Int, reportsLength: Bool)] {
        [
            (pool.fiveHour, "fiveHour", .fiveHour, 5 * 3_600, true),
            (pool.weekly, "weekly", .weekly, 7 * 86_400, true),
            (pool.monthly, "monthly", .monthly, 30 * 86_400, false),
        ]
    }

    /// The newer billing's reading, or nil when this account is not on it and
    /// the older route should be asked instead.
    static func limitsReading(from data: Data, plan: String?, context: ProfileContext,
                              now: Date = Date()) -> ProviderUsage? {
        guard let reply = try? JSONDecoder().decode(Limits.self, from: data),
              reply.usesTokenRateLimitsBilling == true,
              let pools = reply.limits
        else { return nil }

        var windows = pools.standard.map { windowsOf($0, scope: nil, now: now) } ?? []
        // Core is its own pool of models. CodexBar draws it only once it has
        // something in it, and so does this: an empty pool with no clock is a
        // pool the account is not using.
        if let core = pools.core {
            let coreWindows = windowsOf(core, scope: "Core", now: now)
            if coreWindows.contains(where: { $0.usedFraction > 0 || $0.resetsAt != nil }) {
                windows += coreWindows
            }
        }

        let balance = extraUsage(reply)
        guard !windows.isEmpty || balance != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(
            windows,
            plan: plan,
            creditBalance: balance.map(money),
            creditRemaining: balance,
            at: now
        )
    }

    private static func windowsOf(_ pool: Limits.Pool, scope: String?, now: Date) -> [UsageWindow] {
        shapes(of: pool).compactMap { shape -> UsageWindow? in
            guard let window = shape.window,
                  let percent = window.usedPercent, percent.isFinite, percent >= 0
            else { return nil }

            let reset: Date? = if let seconds = window.secondsRemaining, seconds.isFinite, seconds > 0 {
                now.addingTimeInterval(seconds)
            } else if let end = window.windowEnd?.date, end > now {
                end
            } else {
                nil
            }
            // The window this figure belongs to is over and no new one has
            // been stated. CodexBar draws it as 0%; the figure is simply gone.
            if reset == nil, window.windowEnd?.date != nil { return nil }

            return UsageWindow(
                id: "factory.\(scope.map { "\($0.lowercased())." } ?? "")\(shape.name)",
                kind: shape.kind,
                scope: scope,
                usedFraction: percent / 100,
                windowSeconds: shape.seconds,
                resetsAt: reset,
                reportsLength: shape.reportsLength,
                isExhausted: percent >= 100
            )
        }
    }

    /// Money bought on top of the limits, in US cents. Shown when the account
    /// can use it or has some; an account that has never been offered it is
    /// not told it has none.
    private static func extraUsage(_ reply: Limits) -> ProviderUsage.CreditAmount? {
        guard let cents = reply.extraUsageBalanceCents, cents >= 0,
              cents > 0 || reply.extraUsageAllowed == true
        else { return nil }
        return .init(amount: Double(cents) / 100, currency: "USD")
    }

    static func money(_ amount: ProviderUsage.CreditAmount) -> String {
        amount.amount.formatted(
            .currency(code: amount.currency)
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    // MARK: - The older billing

    private struct Usage: Decodable {
        struct Tokens: Decodable {
            let userTokens: Double?
            let totalAllowance: Double?
            let usedRatio: Double?
        }

        struct Period: Decodable {
            let startDate: FactoryDate?
            let endDate: FactoryDate?
            let standard: Tokens?
            let premium: Tokens?
        }

        let usage: Period?
    }

    /// Above this an allowance is Factory's way of writing "unlimited", and a
    /// fraction of it is not a figure anybody reported.
    private static let unlimited = 1e12

    static func allowanceReading(from data: Data, plan: String?, context: ProfileContext,
                                 now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Usage.self, from: data),
              let period = reply.usage
        else { return context.unavailable(.unreadableReply) }

        let end = period.endDate?.date
        // The period's length is stated when both ends are; otherwise thirty
        // days is a sort key and nothing more.
        let stated = period.startDate?.date.flatMap { start in
            end.map { Int($0.timeIntervalSince(start)) }
        }.flatMap { $0 > 0 ? $0 : nil }

        let windows = [("standard", "Standard", period.standard), ("premium", "Premium", period.premium)]
            .compactMap { id, scope, tokens -> UsageWindow? in
                guard let tokens, let fraction = fraction(of: tokens) else { return nil }
                return UsageWindow(
                    id: "factory.\(id)",
                    kind: .monthly,
                    scope: scope,
                    usedFraction: fraction,
                    windowSeconds: stated ?? 30 * 86_400,
                    resetsAt: end,
                    reportsLength: stated != nil,
                    isExhausted: fraction >= 1
                )
            }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan, at: now)
    }

    /// Factory's own ratio where it gives a usable one, and otherwise the
    /// tokens used against the allowance, both as reported.
    ///
    /// The ratio is on a 0…1 scale. CodexBar clamps a hair over either end and
    /// so does this; anything further out is a scale nobody stated. A ratio of
    /// zero beside tokens used and a real allowance is Factory's cache lagging,
    /// and the two counts are read instead — also CodexBar's rule. A zero with
    /// no allowance at all is a pool this plan does not have.
    private static func fraction(of tokens: Usage.Tokens) -> Double? {
        let used = tokens.userTokens.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let allowance = tokens.totalAllowance.flatMap { $0.isFinite && $0 > 0 && $0 <= unlimited ? $0 : nil }

        if let ratio = tokens.usedRatio, ratio.isFinite, ratio >= -0.001, ratio <= 1.001 {
            let lagging = ratio <= 0 && (used ?? 0) > 0 && allowance != nil
            let absent = ratio <= 0 && allowance == nil
            if !lagging && !absent { return min(max(ratio, 0), 1) }
        }
        guard let used, let allowance else { return nil }
        return used / allowance
    }
}
