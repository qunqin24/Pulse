// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Codebuff, the coding agent: its credit allowance, the credits left, and —
/// for the CLI's own login — the weekly rate limit.
///
/// Read with a key the user pastes, or failing that the login the `codebuff`
/// CLI (formerly `manicode`) saved in `~/.config/manicode/credentials.json`.
///
/// - `POST https://www.codebuff.com/api/v1/usage` — the credits used, the
///   quota, the balance and the next reset. A POST because that is how the CLI
///   asks; it carries only a fingerprint id and changes nothing.
/// - `GET https://www.codebuff.com/api/user/subscription` — the tier and the
///   weekly limit. Asked only with the CLI's login, as CodexBar does: an API
///   key reads the credits alone. Best effort — its failure leaves the credits
///   standing.
///
/// The shapes are second-hand — taken from CodexBar's Codebuff provider and
/// its tests, not from captured replies — and the fixtures in the tests say so.
extension ProviderProfile {
    static let codebuff = ProviderProfile(
        displayName: "Codebuff",
        iconResource: "extension",
        credential: .apiKey(optional: true),
        accessDescription: { .localized("Uses a key entered in Settings, or reads the login the codebuff CLI saved in ~/.config/manicode. No Keychain prompt.") },
        keySubtitle: { .localized("From codebuff.com. Optional — Pulse can use the login the codebuff CLI saved. Stored encrypted on this Mac.") },
        setupSlug: "codebuff",
        discoveryPaths: [".config/manicode"],
        fetch: { await CodebuffUsageService.fetch($0) }
    )
}

enum CodebuffUsageService {
    static let usageEndpoint = URL(string: "https://www.codebuff.com/api/v1/usage")!
    static let subscriptionEndpoint = URL(string: "https://www.codebuff.com/api/user/subscription")!

    static func fetch(
        _ context: ProfileContext,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        session: URLSession? = nil
    ) async -> ProviderUsage {
        // The pasted key first: it is the one somebody chose on purpose.
        let token: String
        let isCLILogin: Bool
        if let pasted = context.trimmedCredential {
            (token, isCLILogin) = (pasted, false)
        } else if let saved = savedToken(home: home) {
            (token, isCLILogin) = (saved, true)
        } else {
            return context.unavailable(.apiKeyMissing)
        }

        var usageRequest = ProfileHTTP.bearer(usageEndpoint, token: token)
        usageRequest.httpMethod = "POST"
        usageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        usageRequest.httpBody = Data(#"{"fingerprintId":"pulse-usage"}"#.utf8)

        async let subscription: Data? = isCLILogin
            ? try? ProfileHTTP.data(for: ProfileHTTP.bearer(subscriptionEndpoint, token: token), session: session).get()
            : nil
        let usage = await ProfileHTTP.data(
            for: usageRequest,
            refused: isCLILogin ? .localLoginExpired : .apiKeyRefused,
            session: session
        )

        switch usage {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(usage: data, subscription: await subscription, context: context)
        }
    }

    /// The token the CLI saved: `default.authToken`, or a top-level
    /// `authToken`. Only read, never written.
    static func savedToken(home: URL) -> String? {
        let file = home.appending(path: ".config/manicode/credentials.json")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let profile = root["default"] as? [String: Any]
        for candidate in [profile?["authToken"], root["authToken"]] {
            if let token = (candidate as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    // MARK: - Reading the replies

    static func reading(usage: Data, subscription: Data?, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: usage) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        var windows: [UsageWindow] = []

        // Credits used out of the quota, both as Codebuff reports them. A
        // missing or zero quota is left off — never drawn as spent.
        let used = number(root["usage"]) ?? number(root["used"])
        let quota = number(root["quota"]) ?? number(root["limit"])
        if let used, let quota, quota > 0 {
            windows.append(UsageWindow(
                id: "codebuff.credits",
                kind: .credits,
                scope: nil,
                usedFraction: used / quota,
                // No period is stated, only the next reset.
                windowSeconds: 30 * 86_400,
                resetsAt: date(root["next_quota_reset"]),
                reportsLength: false,
                isExhausted: used >= quota
            ))
        }

        // The weekly limit, when the subscription reply has one.
        var plan: String?
        if let subscription, let reply = try? JSONSerialization.jsonObject(with: subscription) as? [String: Any] {
            let details = reply["subscription"] as? [String: Any]
            let limit = reply["rateLimit"] as? [String: Any]
            let weeklyUsed = number(limit?["weeklyUsed"]) ?? number(limit?["used"])
            let weeklyLimit = number(limit?["weeklyLimit"]) ?? number(limit?["limit"])
            if let weeklyUsed, let weeklyLimit, weeklyLimit > 0 {
                windows.append(UsageWindow(
                    id: "codebuff.weekly",
                    kind: .weekly,
                    scope: nil,
                    usedFraction: weeklyUsed / weeklyLimit,
                    windowSeconds: 7 * 86_400,
                    resetsAt: date(limit?["weeklyResetsAt"]),
                    isExhausted: weeklyUsed >= weeklyLimit
                ))
            }
            plan = [details?["displayName"], reply["displayName"], details?["tier"], reply["tier"]]
                .lazy.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        windows.sort { $0.windowSeconds < $1.windowSeconds }

        // Credits, not money: the number alone, as Codex's balance is shown.
        let remaining = number(root["remainingBalance"]) ?? number(root["remaining"])
        guard !windows.isEmpty || remaining != nil else { return context.unavailable(.noLimitsReported) }
        return context.reading(
            windows,
            plan: plan,
            creditBalance: remaining.map { $0.formatted(.number.precision(.fractionLength(0...1)).locale(LocalizationSource.locale)) },
            at: now
        )
    }

    /// A figure: a finite, non-negative number, or one written as a string.
    private static func number(_ value: Any?) -> Double? {
        let figure: Double? = switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number.doubleValue
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
        guard let figure, figure.isFinite, figure >= 0 else { return nil }
        return figure
    }

    /// ISO 8601, or seconds (or milliseconds) since 1970.
    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            if let date = ProfileHTTP.date(text.trimmingCharacters(in: .whitespaces)) { return date }
            return Double(text).flatMap(epoch)
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return epoch(number.doubleValue)
    }

    private static func epoch(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}
