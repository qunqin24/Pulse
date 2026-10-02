// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// T3 Chat: the four-hour window and the monthly allowance, each reported as
/// a percentage by the service itself.
///
/// Read with a browser session the user imports, from the call T3 Chat's own
/// settings page makes: `GET https://t3.chat/api/trpc/getCustomerData`. The
/// reply is tRPC's streamed JSON, one value per line, with the customer's
/// record somewhere inside one of them. The shape is second-hand — taken
/// from CodexBar's T3 Chat plugin and its tests, not from a captured reply —
/// and the fixture in the tests says so. **Which cookies carry the session is
/// not in CodexBar either** (it forwards every cookie for the site); the
/// names kept here are unverified.
///
/// A percentage T3 Chat leaves out is left off, never drawn as zero — which
/// is what CodexBar does. `usagePeriodPercentage` is not read in place of the
/// monthly figure: nothing says which period it is.
extension ProviderProfile {
    static let t3Chat = ProviderProfile(
        displayName: "T3 Chat",
        iconResource: "extension",
        credential: .sessionCookie(host: "t3.chat", cookies: ["wos-session", "_vcrcs"]),
        accessDescription: {
            .localized("Uses a browser session you import in Settings. Importing may ask for browser Keychain access.")
        },
        spendingIsWatchedLocally: false,
        setupSlug: "t3-chat",
        fetch: { await T3ChatUsageService.fetch($0) }
    )
}

enum T3ChatUsageService {
    /// The batch input the settings page sends: one call, no session id.
    static let endpoint: URL = {
        var parts = URLComponents(string: "https://t3.chat/api/trpc/getCustomerData")!
        parts.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(
                name: "input",
                value: #"{"0":{"json":{"sessionId":null},"meta":{"values":{"sessionId":["undefined"]}}}}"#
            ),
        ]
        return parts.url!
    }()

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let cookie = context.trimmedCredential else { return context.unavailable(.sessionMissing) }
        var request = URLRequest(url: endpoint)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://t3.chat", forHTTPHeaderField: "Origin")
        request.setValue("https://t3.chat/settings/customization", forHTTPHeaderField: "Referer")
        request.setValue("application/jsonl", forHTTPHeaderField: "trpc-accept")
        request.setValue("web-client", forHTTPHeaderField: "x-trpc-source")
        request.setValue("true", forHTTPHeaderField: "x-trpc-batch")
        request.timeoutInterval = 15

        switch await ProfileHTTP.data(for: request, refused: .sessionExpired, session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    // MARK: - Reading the reply

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let text = String(data: data, encoding: .utf8),
              let customer = text.split(whereSeparator: \.isNewline).lazy
                .compactMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) })
                .compactMap(customerRecord(in:))
                .first
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []

        // "Four hour" is in the field's name, so the length is stated.
        if let percent = percent(customer["usageFourHourPercentage"]) {
            windows.append(UsageWindow(
                id: "t3chat.four_hour",
                kind: .other(seconds: 4 * 3_600),
                scope: nil,
                usedFraction: percent / 100,
                windowSeconds: 4 * 3_600,
                resetsAt: date(customer["usageFourHourNextResetAt"]) ?? date(customer["usageWindowNextResetAt"]),
                isExhausted: percent >= 100
            ))
        }

        // The subscription's billing period: a name and a sort key, with the
        // reset the subscription states. `billingNextResetAt` is the usage
        // window's, not this one's, and is not used for it.
        if let percent = percent(customer["usageMonthPercentage"]) {
            let subscription = customer["subscription"] as? [String: Any]
            windows.append(UsageWindow(
                id: "t3chat.monthly",
                kind: .monthly,
                scope: nil,
                usedFraction: percent / 100,
                windowSeconds: 30 * 86_400,
                resetsAt: date(subscription?["currentPeriodEnd"]),
                reportsLength: false,
                isExhausted: percent >= 100
            ))
        }

        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: plan(customer), at: now)
    }

    /// The first object anywhere in `value` that is the customer's record.
    static func customerRecord(in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if object["usageFourHourPercentage"] != nil || object["usageMonthPercentage"] != nil
                || (object["subscription"] != nil && object["usageBand"] != nil) {
                return object
            }
            for child in object.values {
                if let found = customerRecord(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = customerRecord(in: child) { return found }
            }
        }
        return nil
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        return percent.isFinite && percent >= 0 ? percent : nil
    }

    /// Epoch milliseconds, or seconds when the figure is too small to be
    /// milliseconds — T3 Chat uses both.
    static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }

    /// "pro" → "Pro", "pro-max" → "Pro Max". T3 Chat's own plan name.
    private static func plan(_ customer: [String: Any]) -> String? {
        let subscription = customer["subscription"] as? [String: Any]
        let raw = (subscription?["productName"] as? String) ?? (customer["subTier"] as? String)
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
