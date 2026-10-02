// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Amp, the coding agent: its free daily allowance, a paid tier's monthly
/// agent and Orb allowances, and the individual credit balance.
///
/// Read with an access token the user pastes, from the RPC Amp's own CLI
/// calls: `POST https://ampcode.com/api/internal?userDisplayBalanceInfo`. The
/// reply carries no fields — only `result.displayText`, the same lines
/// `amp usage` prints — so those lines are what is read. No other route gives
/// the figures as data: the settings page only embeds the old free-tier
/// object. The shape is second-hand, from CodexBar's Amp provider and its
/// tests, not from a captured reply.
///
/// Every figure drawn is one the text states in both halves: "$18.57 of $20
/// remaining", "61% remaining today". Amp's old "time to full" is not read —
/// it was an estimate from the replenishment rate, never a stated reset — and
/// neither are workspace balances, which Pulse has nowhere to show beside
/// the account's own.
extension ProviderProfile {
    static let amp = ProviderProfile(
        displayName: "Amp",
        iconResource: "amp",
        credential: .apiKey(optional: false),
        accessDescription: { .localized("Uses only the API key you enter in Settings. No Keychain prompt.") },
        keySubtitle: { .localized("From ampcode.com/settings. Stored encrypted on this Mac.") },
        reportsSpendableBalance: true,
        setupSlug: "amp",
        discoveryPaths: [".local/share/amp", ".config/amp"],
        fetch: { await AmpUsageService.fetch($0) }
    )
}

enum AmpUsageService {
    static let endpoint = URL(string: "https://ampcode.com/api/internal?userDisplayBalanceInfo")!

    static func fetch(_ context: ProfileContext, session: URLSession? = nil) async -> ProviderUsage {
        guard let token = context.trimmedCredential else { return context.unavailable(.apiKeyMissing) }
        switch await ProfileHTTP.data(for: request(token: token), session: session) {
        case .failure(let reason):
            return context.unavailable(reason)
        case .success(let data):
            return reading(from: data, context: context)
        }
    }

    /// A read-only RPC: it names the method and passes nothing.
    static func request(token: String) -> URLRequest {
        var request = ProfileHTTP.bearer(endpoint, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"method":"userDisplayBalanceInfo","params":{}}"#.utf8)
        return request
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        struct Result: Decodable { let displayText: String? }
        struct Failure: Decodable { let code: String? }

        let ok: Bool?
        let result: Result?
        let error: Failure?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }
        // Amp answers a dead token with an envelope rather than a status.
        if reply.ok == false {
            return context.unavailable(reply.error?.code == "auth-required" ? .apiKeyRefused : .serverError)
        }
        guard reply.ok == true, let text = reply.result?.displayText, !text.isEmpty else {
            return context.unavailable(.unreadableReply)
        }
        return reading(text: text, context: context, now: now)
    }

    /// The lines Amp prints, one at a time. A line this build doesn't know
    /// is skipped, never guessed at.
    static func reading(text: String, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        let lines = clean(text).split(whereSeparator: \.isNewline).map(String.init)
        var windows: [UsageWindow] = []
        var plan: String?
        var credits: Double?

        // The dollar form is exact; the percentage one is rounded, so it only
        // counts when the other is not there.
        if let free = lines.lazy.compactMap(freeDollars).first ?? lines.lazy.compactMap(freePercent).first {
            windows.append(free)
        }
        for line in lines {
            if let tier = tier(line) {
                plan = plan ?? tier.plan
                windows += tier.windows
            } else if let legacy = subscription(line) {
                plan = plan ?? legacy.plan
                windows += legacy.windows
            } else if credits == nil, let found = match(#"^\s*Individual credits:\s*\$?"# + number + #"\s+remaining"#, line) {
                credits = amount(found[0]).flatMap { $0 >= 0 ? $0 : nil }
            }
        }

        if windows.isEmpty, credits == nil {
            return context.unavailable(looksSignedOut(text) ? .apiKeyRefused : .unreadableReply)
        }
        // Tier and subscription lines describe the same allowance; the first
        // one Amp printed stands.
        var seen: Set<String> = []
        windows = windows.filter { seen.insert($0.id).inserted }
            .sorted { $0.windowSeconds < $1.windowSeconds }
        return context.reading(
            windows,
            plan: plan,
            creditBalance: credits.map(dollars),
            creditRemaining: credits.map { .init(amount: $0, currency: "USD") },
            at: now
        )
    }

    // MARK: - The lines

    private static let number = #"([0-9][0-9,]*(?:\.[0-9]+)?)"#
    private static let month = 30 * 86_400

    /// "Amp Free: $6/$10 remaining (replenishes +$0.5/hour)". It refills by
    /// the hour and never turns over, so it has no reset and no length.
    private static func freeDollars(_ line: String) -> UsageWindow? {
        guard let found = match(#"^\s*Amp Free:\s*\$?"# + number + #"\s*/\s*\$?"# + number + #"\s+remaining"#, line),
              let used = usedFraction(remaining: amount(found[0]), of: amount(found[1]))
        else { return nil }
        return UsageWindow(
            id: "amp.free", kind: .credits, scope: "Amp Free", usedFraction: used,
            windowSeconds: 86_400, resetsAt: nil, reportsLength: false, isExhausted: used >= 1
        )
    }

    /// "Amp Free: 61% remaining today (resets daily)". Daily is stated; the
    /// hour it turns over is not, so no reset is given.
    private static func freePercent(_ line: String) -> UsageWindow? {
        guard let found = match(#"^\s*Amp Free:\s*"# + number + #"\s*%\s+remaining(\s+today)?(\s*\(resets daily\))?"#, line),
              let remaining = amount(found[0]), remaining >= 0
        else { return nil }
        let used = max(0, 100 - min(remaining, 100)) / 100
        return UsageWindow(
            id: "amp.free", kind: .daily, scope: "Amp Free", usedFraction: used,
            windowSeconds: 86_400, resetsAt: nil,
            reportsLength: !found[1].isEmpty || !found[2].isEmpty, isExhausted: used >= 1
        )
    }

    /// "Amp Megawatt Tier: agent usage $18.57 of $20 remaining (93%), orb
    /// usage 732.8h of 750h a1.small orb hours remaining (98%) - period
    /// 2026-09-13 to 2026-10-13, resets upon renewal in 27 days". Dollars and
    /// hours, not the rounded percentages beside them.
    private static func tier(_ line: String) -> (plan: String, windows: [UsageWindow])? {
        guard let found = match(#"^\s*Amp\s+(.+?)\s+Tier:\s*agent usage\s+\$"# + number + #"\s+of\s+\$"# + number + #"\s+remaining\b(.*)$"#, line)
        else { return nil }
        let rest = found[3]
        let resetsAt = periodEnd(rest)
        var windows: [UsageWindow] = []
        if let used = usedFraction(remaining: amount(found[1]), of: amount(found[2])) {
            windows.append(monthly("amp.agent", scope: nil, used: used, resetsAt: resetsAt))
        }
        // Only the unit Amp names its allowance in; another size of machine
        // would be another allowance.
        if let orb = match(#"\borb usage\s+"# + number + #"h\s+of\s+"# + number + #"h\s+a1\.small orb hours remaining\b"#, rest),
           let used = usedFraction(remaining: amount(orb[0]), of: amount(orb[1])) {
            windows.append(monthly("amp.orb", scope: "Orb", used: used, resetsAt: resetsAt))
        }
        return (found[0], windows)
    }

    /// The older wording, in percentages remaining: "Amp Megawatt
    /// Subscription: 68% other usage and 97% orb usage remaining - resets upon
    /// renewal in 5 days", or "Subscription Megawatt: …".
    private static func subscription(_ line: String) -> (plan: String, windows: [UsageWindow])? {
        let tail = #":\s*"# + number + #"\s*%\s+other usage and\s+"# + number + #"\s*%\s+orb usage remaining"#
        guard let found = match(#"^\s*Amp\s+(.+?)\s+Subscription"# + tail, line)
            ?? match(#"^\s*Subscription\s+(.+?)"# + tail, line)
        else { return nil }
        let parts: [(id: String, scope: String?, remaining: String)] = [
            ("amp.agent", nil, found[1]), ("amp.orb", "Orb", found[2]),
        ]
        let windows = parts.compactMap { id, scope, text -> UsageWindow? in
            guard let remaining = amount(text), remaining >= 0 else { return nil }
            return monthly(id, scope: scope, used: max(0, 100 - min(remaining, 100)) / 100, resetsAt: nil)
        }
        return (found[0], windows)
    }

    /// A paid allowance renews with the billing period, which is a month
    /// that is not a fixed length: thirty days is a sort key only.
    private static func monthly(_ id: String, scope: String?, used: Double, resetsAt: Date?) -> UsageWindow {
        UsageWindow(
            id: id, kind: .monthly, scope: scope, usedFraction: used,
            windowSeconds: month, resetsAt: resetsAt, reportsLength: false, isExhausted: used >= 1
        )
    }

    /// "period 2026-09-13 to 2026-10-13": dates only, so the renewal is taken
    /// as the start of that day in UTC. The countdown beside it ("in 27
    /// days") is rounded and moves every refresh, so it is not used.
    private static func periodEnd(_ text: String) -> Date? {
        guard let found = match(#"\bperiod\s+(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})\b"#, text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let start = formatter.date(from: found[0]), let end = formatter.date(from: found[1]),
              formatter.string(from: end) == found[1], end > start
        else { return nil }
        return end
    }

    // MARK: - Helpers

    /// Used over limit, from what is left of a stated limit. More left than
    /// the limit is nothing used, not a negative.
    private static func usedFraction(remaining: Double?, of limit: Double?) -> Double? {
        guard let remaining, let limit, remaining.isFinite, limit.isFinite, remaining >= 0, limit > 0 else { return nil }
        return max(0, limit - remaining) / limit
    }

    private static func amount(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    static func dollars(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    /// Terminal colour codes and Markdown bold, which the text may carry.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
    }

    private static func looksSignedOut(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !lower.contains("signed in as") && (lower.contains("sign in") || lower.contains("log in") || lower.contains("login"))
    }

    /// The capture groups of the first match, case-insensitively; an
    /// unmatched optional group is an empty string.
    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        }
    }
}
