// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Chutes: a subscription's rolling window and its monthly allowance, each an
/// amount used out of a limit the service states.
///
/// Read with a key the user pastes, from Chutes' management API:
/// `GET https://api.chutes.ai/users/me/subscription_usage`. The shape is
/// second-hand — taken from CodexBar's Chutes plugin and its tests, not from
/// a captured reply — and the fixture in the tests says so.
///
/// **Narrower than CodexBar on purpose.** It searches the whole reply for
/// anything with a `limit` and a `used`, guesses a lane from the word
/// "rolling" or "month", fills in four hours or thirty days where no length
/// is given, and reads a percentage under 1 as a fraction. None of that is
/// done here: the rolling window is read only where its length is stated —
/// in minutes, hours or seconds, or in its name — and the monthly one only
/// where it is named so. The per-chute pay-as-you-go quotas CodexBar fetches
/// one request at a time state no period at all, and are left off.
extension ProviderProfile {
    static let chutes = ProviderProfile(
        displayName: "Chutes",
        iconResource: "chutes",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From chutes.ai. Stored encrypted on this Mac.") },
        spendingIsWatchedLocally: false,
        setupSlug: "chutes",
        fetch: { await ChutesUsageService.fetch($0) }
    )
}

enum ChutesUsageService {
    static let endpoint = URL(string: "https://api.chutes.ai/users/me/subscription_usage")!

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

    /// Keys compared the way CodexBar compares them: lower-cased, with
    /// everything but letters and digits dropped, so `rolling_window`,
    /// `rollingWindow` and `RollingWindow` are one name.
    private static func normalized(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The rolling lane, and how long each name says it is, where it says.
    private static let rollingKeys: [String: Int?] = [
        "rolling": nil, "rollingwindow": nil,
        "rolling4h": 4 * 3_600, "fourhour": 4 * 3_600, "fourhourusage": 4 * 3_600, "window4h": 4 * 3_600,
    ]
    private static let monthlyKeys = ["monthly", "monthlyusage", "billingperiod"]

    private static let limitKeys = ["limit", "cap", "max", "quota", "monthlylimit", "requestlimit", "tokenlimit"]
    private static let usedKeys = ["used", "usage", "consumed", "requests", "requestcount", "tokens", "tokenusage"]
    private static let remainingKeys = ["remaining", "available", "left"]
    private static let percentUsedKeys = ["percentused", "usagepercent", "usedpercent"]
    private static let resetKeys = ["resetat", "resetsat", "nextresetat", "renewsat", "periodend", "currentperiodend", "windowend"]

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            return context.unavailable(.unreadableReply)
        }
        // Some replies wrap everything in `data` or `result`.
        let body = (value(in: root, keys: ["data", "result"]) as? [String: Any]) ?? root
        let subscription = (value(in: body, keys: ["subscription", "currentsubscription"]) as? [String: Any]) ?? [:]

        var windows: [UsageWindow] = []

        if case let (payload, seconds)? = rolling(in: body),
           case let (used, limit)? = figures(payload) {
            windows.append(UsageWindow(
                id: "chutes.rolling",
                kind: seconds == 5 * 3_600 ? .fiveHour : seconds == 86_400 ? .daily : .other(seconds: seconds),
                scope: nil,
                usedFraction: used / limit,
                windowSeconds: seconds,
                resetsAt: date(value(in: payload, keys: resetKeys)),
                isExhausted: used >= limit
            ))
        }

        if let payload = value(in: body, keys: monthlyKeys) as? [String: Any],
           case let (used, limit)? = figures(payload) {
            windows.append(UsageWindow(
                id: "chutes.monthly",
                kind: .monthly,
                scope: nil,
                usedFraction: used / limit,
                // A billing month: a sort key, not a stated length.
                windowSeconds: 30 * 86_400,
                resetsAt: date(value(in: payload, keys: resetKeys)),
                reportsLength: false,
                isExhausted: used >= limit
            ))
        }

        guard !windows.isEmpty else {
            // An answer rather than an outage: the account has no plan.
            return context.unavailable(isActive(subscription) == false ? .noPlan : .noLimitsReported)
        }
        let plan = (value(in: subscription, keys: ["planname", "plan", "tier"]) as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return context.reading(
            windows.sorted { $0.windowSeconds < $1.windowSeconds },
            plan: plan?.isEmpty == false ? plan : nil,
            at: now
        )
    }

    private static func value(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let entry = object.first(where: { normalized($0.key) == key }), !(entry.value is NSNull) {
                return entry.value
            }
        }
        return nil
    }

    /// The rolling lane whose length is stated — by the payload itself or by
    /// its name — or nil. A lane that states none is passed over, so a bare
    /// `rolling_window` never hides a `four_hour` beside it.
    private static func rolling(in body: [String: Any]) -> (payload: [String: Any], seconds: Int)? {
        for (key, value) in body.sorted(by: { $0.key < $1.key }) {
            guard let named = rollingKeys[normalized(key)], let payload = value as? [String: Any],
                  let seconds = statedSeconds(payload) ?? named
            else { continue }
            return (payload, seconds)
        }
        return nil
    }

    /// A length the payload states in so many minutes, hours or seconds.
    private static func statedSeconds(_ payload: [String: Any]) -> Int? {
        let units: [([String], Double)] = [
            (["windowminutes", "periodminutes", "durationminutes"], 60),
            (["windowhours", "periodhours", "durationhours"], 3_600),
            (["windowseconds", "periodseconds", "durationseconds"], 1),
        ]
        for (keys, multiplier) in units {
            if let number = number(value(in: payload, keys: keys)), number > 0 {
                let seconds = (number * multiplier).rounded()
                return seconds >= 3_600 && seconds < Double(Int32.max) ? Int(seconds) : nil
            }
        }
        return nil
    }

    /// Used and limit, both as the service states them — or a percentage it
    /// states, on a 0–100 scale. A limit of zero is no allowance.
    private static func figures(_ payload: [String: Any]) -> (used: Double, limit: Double)? {
        if let percent = number(value(in: payload, keys: percentUsedKeys)), percent >= 0 {
            return (percent, 100)
        }
        guard let limit = number(value(in: payload, keys: limitKeys)), limit > 0 else { return nil }
        if let used = number(value(in: payload, keys: usedKeys)), used >= 0 { return (used, limit) }
        if let remaining = number(value(in: payload, keys: remainingKeys)), remaining >= 0 {
            return (max(limit - remaining, 0), limit)
        }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.doubleValue.isFinite ? number.doubleValue : nil
        case let text as String:
            return Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default:
            return nil
        }
    }

    /// ISO 8601, or epoch seconds or milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String, let date = ProfileHTTP.date(text) { return date }
        guard let number = number(value), number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
    }

    private static func isActive(_ subscription: [String: Any]) -> Bool? {
        if let flag = value(in: subscription, keys: ["active", "isactive"]) as? Bool { return flag }
        guard let status = (value(in: subscription, keys: ["status", "state"]) as? String)?.lowercased() else { return nil }
        if status == "active" { return true }
        if ["free", "inactive", "canceled", "cancelled", "expired", "none"].contains(status) { return false }
        return nil
    }
}
