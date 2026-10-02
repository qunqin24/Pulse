// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// v0, Vercel's app builder: the account's billing allowance and its request
/// rate limit, each as a size and a remainder the service states.
///
/// Read with a v0 Platform API key the user pastes, from
/// `GET https://api.v0.dev/v1/user/billing` and `GET …/v1/rate-limits`. The
/// shapes are second-hand — taken from CodexBar's v0 provider, its tests and
/// the API reference it cites, not from a captured reply — and the fixtures in
/// the tests say so.
///
/// Billing comes in two shapes, named by `billingType`: `token`, a balance
/// with a total and a remainder and a cycle end, and `legacy`, a limit and a
/// remainder. Either way the units are v0's own; nothing here calls them
/// dollars. The on-demand balance beside the token allowance is in the same
/// unnamed unit and is left out rather than labelled with a guess. A
/// remainder that is not reported leaves that window off — the size alone is
/// not a percentage.
///
/// The rate limit is best-effort: the billing allowance is the reading, and a
/// rate limit that cannot be had leaves it standing.
extension ProviderProfile {
    static let v0 = ProviderProfile(
        displayName: "v0",
        iconResource: "v0",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From v0.app. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "v0",
        fetch: { await V0UsageService.fetch($0) }
    )
}

enum V0UsageService {
    static let billingEndpoint = URL(string: "https://api.v0.dev/v1/user/billing")!
    static let rateLimitEndpoint = URL(string: "https://api.v0.dev/v1/rate-limits")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let key = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        let billing: Data
        switch await ProfileHTTP.data(for: ProfileHTTP.bearer(billingEndpoint, token: key), session: session) {
        case .failure(let reason): return context.unavailable(reason)
        case .success(let data): billing = data
        }
        let rateLimit = try? await ProfileHTTP.data(
            for: ProfileHTTP.bearer(rateLimitEndpoint, token: key),
            session: session
        ).get()
        return reading(billing: billing, rateLimit: rateLimit, context: context)
    }

    // MARK: - Reading the reply

    /// A size, what is left of it, and when it resets — the legacy billing
    /// shape and the rate limit are both this.
    private struct Quota: Decodable {
        let limit: Double?
        let remaining: Double?
        let reset: Double?
    }

    private struct TokenBilling: Decodable {
        struct Balance: Decodable {
            let total: Double?
            let remaining: Double?
        }

        struct Cycle: Decodable { let end: Double? }

        let balance: Balance?
        let billingCycle: Cycle?
    }

    private struct Billing: Decodable {
        let billingType: String?
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload?
    }

    static func reading(billing: Data, rateLimit: Data? = nil, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let kind = try? JSONDecoder().decode(Billing.self, from: billing) else {
            return context.unavailable(.unreadableReply)
        }

        let allowance: (total: Double?, remaining: Double?, reset: Double?)
        switch kind.billingType {
        case "token":
            guard let token = (try? JSONDecoder().decode(Envelope<TokenBilling>.self, from: billing))?.data
            else { return context.unavailable(.unreadableReply) }
            allowance = (token.balance?.total, token.balance?.remaining, token.billingCycle?.end)
        case "legacy":
            guard let legacy = (try? JSONDecoder().decode(Envelope<Quota>.self, from: billing))?.data
            else { return context.unavailable(.unreadableReply) }
            allowance = (legacy.limit, legacy.remaining, legacy.reset)
        default:
            return context.unavailable(.unreadableReply)
        }

        var windows: [UsageWindow] = []
        // v0's own credits over a billing cycle whose length is not stated.
        if let window = window(
            id: "v0.billing", kind: .credits,
            limit: allowance.total, remaining: allowance.remaining, reset: allowance.reset,
            seconds: 30 * 86_400
        ) { windows.append(window) }
        // Counted in requests, with a reset and no stated length. A day is
        // only where it sorts.
        if let data = rateLimit, let quota = try? JSONDecoder().decode(Quota.self, from: data),
           let window = window(
               id: "v0.rate_limit", kind: .messages,
               limit: quota.limit, remaining: quota.remaining, reset: quota.reset,
               seconds: 86_400
           ) { windows.append(window) }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows.sorted { $0.windowSeconds < $1.windowSeconds }, at: now)
    }

    /// Used is the size less what is left, both as reported. A remainder above
    /// the size reads as nothing used, not as a negative share.
    private static func window(
        id: String,
        kind: UsageWindow.Kind,
        limit: Double?,
        remaining: Double?,
        reset: Double?,
        seconds: Int
    ) -> UsageWindow? {
        guard let limit, limit.isFinite, limit > 0,
              let remaining, remaining.isFinite
        else { return nil }
        let fraction = max(limit - remaining, 0) / limit
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: fraction,
            windowSeconds: seconds,
            resetsAt: date(reset),
            reportsLength: false,
            isExhausted: remaining <= 0
        )
    }

    /// Unix time, in seconds or in milliseconds; CodexBar accepts either, and
    /// so does this. Zero or less is no reset.
    static func date(_ stamp: Double?) -> Date? {
        guard let stamp, stamp.isFinite, stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp >= 1_000_000_000_000 ? stamp / 1_000 : stamp)
    }
}
