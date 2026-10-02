// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Bifrost, a self-hosted AI gateway: the budgets its governance puts on one
/// virtual key — dollars spent out of dollars allowed, per period.
///
/// Read with the virtual key the user pastes and the gateway address they
/// enter, from the gateway's own governance route:
/// `GET <address>/api/governance/virtual-keys/quota`, key in `x-bf-vk`. The
/// key goes to that address and nowhere else. The shape is second-hand —
/// taken from CodexBar's Bifrost plugin, not from a captured reply — and the
/// fixture in the tests says so.
///
/// **Budgets only.** The key's rate limits are left off: a token limit and a
/// request limit over the same period would both be named "1-hour limit",
/// and nothing here can tell the reader which is which without a unit label
/// Pulse does not have. The per-model spend breakdown is spend with no limit
/// and has nowhere to go either.
extension ProviderProfile {
    static let bifrost = ProviderProfile(
        displayName: "Bifrost",
        billing: .api,
        iconResource: "extension",
        credential: .keyAndAddress,
        accessDescription: {
            .localized("Sends the key you enter only to the server address you enter. No Keychain prompt.")
        },
        keySubtitle: { .localized("The same key your AI client uses for this gateway. Sent only to the address above. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        requiresScopeMatch: true,
        setupSlug: "bifrost",
        fetch: { await BifrostUsageService.fetch($0) }
    )
}

enum BifrostUsageService {
    static let path = "/api/governance/virtual-keys/quota"

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        var usage = await read(context, session: session)
        // Stamped with the gateway and key, so a reading from one never
        // stands in for another's failure.
        usage.sourceScope = GatewayAddress.scope(of: context.serverAddress, key: context.trimmedCredential)
        return usage
    }

    private static func read(_ context: ProfileContext, session: URLSession?) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        let typed = (context.serverAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return context.unavailable(.serverAddressMissing) }
        // People paste the OpenAI-compatible base, which ends in `/v1`.
        guard let url = GatewayAddress.url(from: typed, path: path, trimming: ["/v1"]) else {
            return context.unavailable(.serverAddressRefused)
        }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-bf-vk")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        switch await ProfileHTTP.data(for: request, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    struct Budget: Decodable {
        let id: String?
        let maxLimit: Double?
        let currentUsage: Double?
        let resetDuration: String?
        let lastReset: String?
        let overrideAmount: Double?
        let overrideMode: String?
        let overrideCyclesRemaining: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case maxLimit = "max_limit"
            case currentUsage = "current_usage"
            case resetDuration = "reset_duration"
            case lastReset = "last_reset"
            case overrideAmount = "override_amount"
            case overrideMode = "override_mode"
            case overrideCyclesRemaining = "override_cycles_remaining"
        }
    }

    private struct Scoped: Decodable {
        let provider: String?
        let modelName: String?
        let budgets: [Budget]?

        enum CodingKeys: String, CodingKey {
            case provider, budgets
            case modelName = "model_name"
        }
    }

    private struct Reply: Decodable {
        let isActive: Bool?
        let budgets: [Budget]?
        let providerConfigs: [Scoped]?
        let modelConfigs: [Scoped]?

        enum CodingKeys: String, CodingKey {
            case budgets
            case isActive = "is_active"
            case providerConfigs = "provider_configs"
            case modelConfigs = "model_configs"
        }
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }

        // The key's own budgets, then those it has per upstream provider and
        // per model, each scoped by the name the gateway gives it.
        var scoped: [(scope: String?, idPrefix: String, budget: Budget)] = []
        scoped += (reply.budgets ?? []).map { (nil, "", $0) }
        for (index, config) in (reply.providerConfigs ?? []).enumerated() {
            let name = clean(config.provider)
            scoped += (config.budgets ?? []).map { (name, "provider\(index).", $0) }
        }
        for (index, config) in (reply.modelConfigs ?? []).enumerated() {
            let name = clean(config.modelName) ?? clean(config.provider)
            scoped += (config.budgets ?? []).map { (name, "model\(index).", $0) }
        }

        let windows = scoped.compactMap { window(for: $0.budget, scope: $0.scope, idPrefix: $0.idPrefix, now: now) }
            .sorted { $0.windowSeconds < $1.windowSeconds }

        guard !windows.isEmpty else {
            // An inactive key with nothing on it is a key the gateway won't
            // honour, not a key with no limits.
            return context.unavailable(reply.isActive == false ? .apiKeyRefused : .noLimitsReported)
        }
        return context.reading(windows, at: now)
    }

    private static func window(for budget: Budget, scope: String?, idPrefix: String, now: Date) -> UsageWindow? {
        guard let id = clean(budget.id),
              let used = budget.currentUsage, used.isFinite, used >= 0,
              let base = budget.maxLimit, base.isFinite
        else { return nil }

        // A temporary raise the gateway reports on top of the budget counts
        // while it is in force: for good, or for cycles it says remain.
        var limit = base
        if let extra = budget.overrideAmount, extra.isFinite, extra > 0 {
            let cycles = budget.overrideCyclesRemaining ?? 0
            if budget.overrideMode == "forever" || (budget.overrideMode == "cycles" && cycles > 0) {
                limit += extra
            }
        }
        guard limit > 0 else { return nil }

        let period = Period.parse(budget.resetDuration)
        return UsageWindow(
            id: "bifrost.\(idPrefix)\(id)",
            kind: period.kind,
            scope: scope,
            usedFraction: used / limit,
            windowSeconds: period.seconds,
            resetsAt: period.isFixed ? nextReset(after: ProfileHTTP.date(budget.lastReset), period: period.seconds, now: now) : nil,
            reportsLength: period.reportsLength,
            isExhausted: used >= limit
        )
    }

    /// The reset that follows the one the gateway reports, if it is still
    /// ahead. Only for a fixed-length period: one counted in days or longer
    /// may be aligned to the calendar, and the reply does not say.
    static func nextReset(after last: Date?, period: Int, now: Date) -> Date? {
        guard let last, period > 0 else { return nil }
        let next = last.addingTimeInterval(TimeInterval(period))
        return next > now ? next : nil
    }

    /// A budget's `reset_duration`, as Bifrost writes it: a Go duration such
    /// as `1h` or `30m`, or a count of days, weeks, months, quarters or years
    /// (`1d`, `1w`, `1M`, `1Q`, `1Y`).
    struct Period: Equatable {
        let kind: UsageWindow.Kind
        let seconds: Int
        let reportsLength: Bool
        /// Counted in hours or less, so its next reset follows from the last.
        let isFixed: Bool

        /// A budget with no length this can state: a spend limit, sorted by
        /// `sortKey`.
        private static func unstated(_ sortKey: Int) -> Period {
            Period(kind: .spend, seconds: sortKey, reportsLength: false, isFixed: false)
        }

        static func parse(_ raw: String?) -> Period {
            let text = raw?.trimmingCharacters(in: .whitespaces) ?? ""
            if let seconds = fixedSeconds(text) {
                // Named by its length only when that is a whole number of
                // hours: "30m" read as a "1-hour limit" would be a claim.
                guard seconds % 3_600 == 0 else {
                    return Period(kind: .spend, seconds: seconds, reportsLength: false, isFixed: true)
                }
                let kind: UsageWindow.Kind = seconds == 5 * 3_600 ? .fiveHour
                    : seconds == 86_400 ? .daily : .other(seconds: seconds)
                return Period(kind: kind, seconds: seconds, reportsLength: true, isFixed: true)
            }
            guard let last = text.last, let count = Int(text.dropLast()), count > 0, count < 1_000 else {
                return unstated(30 * 86_400)
            }
            switch (last, count) {
            case ("d", 1): return Period(kind: .daily, seconds: 86_400, reportsLength: true, isFixed: false)
            case ("d", 7), ("w", 1): return Period(kind: .weekly, seconds: 7 * 86_400, reportsLength: true, isFixed: false)
            case ("d", _): return Period(kind: .other(seconds: count * 86_400), seconds: count * 86_400, reportsLength: true, isFixed: false)
            case ("w", _):
                return Period(kind: .other(seconds: count * 7 * 86_400), seconds: count * 7 * 86_400, reportsLength: true, isFixed: false)
            // A month is not a fixed length: a name and a sort key only.
            case ("M", 1): return Period(kind: .monthly, seconds: 30 * 86_400, reportsLength: false, isFixed: false)
            // Several months, a quarter or a year: a length nothing here can
            // name without claiming a number of days.
            case ("M", _): return unstated(count * 30 * 86_400)
            case ("Q", _): return unstated(count * 90 * 86_400)
            case ("Y", _): return unstated(count * 365 * 86_400)
            default: return unstated(30 * 86_400)
            }
        }

        /// `1h`, `90m`, `1h30m`: whole seconds, or nil if it isn't one.
        static func fixedSeconds(_ text: String) -> Int? {
            let units: [(String, Double)] = [("h", 3_600), ("m", 60), ("s", 1)]
            var rest = Substring(text)
            var total = 0.0
            var matched = false
            while !rest.isEmpty {
                let digits = rest.prefix { $0.isNumber || $0 == "." }
                guard !digits.isEmpty, let value = Double(digits) else { return nil }
                rest = rest.dropFirst(digits.count)
                guard let unit = units.first(where: { rest.hasPrefix($0.0) && !rest.hasPrefix("ms") }) else { return nil }
                rest = rest.dropFirst(unit.0.count)
                total += value * unit.1
                matched = true
            }
            guard matched, total.isFinite, total >= 1, total < Double(Int32.max) else { return nil }
            return Int(total.rounded())
        }
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
