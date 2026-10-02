// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// V2EX's AI Chat allowance, read with a Personal Access Token.
///
/// One documented route, `GET https://edge.v2ex.com/api/v2/chat/quota`, and —
/// unusually for this directory — a published help page behind it
/// (`https://edge.v2ex.com/help/quota`) that states the rules the numbers
/// follow.
///
/// ```json
/// { "success": true, "result": {
///     "active": false, "total_tokens": 8020000, "used_tokens": 0,
///     "remaining_tokens": 8020000, "used_percent": 0,
///     "period_start": 0, "period_end": 0,
///     "extra_usage": { "pack_count": 1, "total_tokens": 12000000,
///                      "used_tokens": 34897, "remaining_tokens": 11965103 } } }
/// ```
///
/// **The window does not run until it is used.** V2EX starts a five-hour
/// window when it receives the next message, not on a clock — so a reading with
/// `active: false` reports the size of the allowance that *would* be granted
/// and `period_start` / `period_end` of zero. That is a complete answer and not
/// a fault: the ring is drawn at whatever has been spent (nothing), and no
/// reset time and no length are claimed, so the card does not count down to a
/// moment V2EX has not promised. Asking this route never starts a window.
///
/// The extra pack (`extra_usage`, 额外用量) is a second allowance with its own
/// stated size, no expiry, and no window at all — it is only spent once the
/// five hours' worth is gone. It is reported as `UsageWindow.Kind.topUp`
/// rather than folded into the window above, because a reader whose window is
/// spent but whose pack is full is not out of quota, and a single ring saying
/// 100% would tell them they were.
struct V2EXUsageService: Sendable {
    let enteredKey: String?

    private static let endpoint = URL(string: "https://edge.v2ex.com/api/v2/chat/quota")!

    /// V2EX's own wording: "每 5 小时为一个配额窗口".
    static let windowSeconds = 5 * 3_600

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.v2ex, reason: .apiKeyMissing)
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else {
            return .unavailable(.v2ex, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.v2ex, reason: .apiKeyRefused)
        case 429: return .unavailable(.v2ex, reason: .rateLimited)
        default: return .unavailable(.v2ex, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.v2ex, reason: .unreadableReply)
        }

        // V2EX answers 200 and says no in the body. The route is scoped to the
        // token, so the one thing it can refuse is the token.
        guard reply.success != false, let quota = reply.result else {
            return .unavailable(.v2ex, reason: reply.success == false ? .apiKeyRefused : .unreadableReply)
        }

        let windows = Self.windows(from: quota)
        guard !windows.isEmpty else {
            return .unavailable(.v2ex, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.v2ex),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil,
            creditRemaining: nil
        )
    }

    // MARK: - Reading the reply

    struct Reply: Decodable {
        struct Quota: Decodable {
            /// Whether a window is running. False means one has not started —
            /// not that the account is out of quota.
            let active: Bool?
            let totalTokens: Double?
            let usedTokens: Double?
            let remainingTokens: Double?
            /// Zero when no window is running, which is why it is never read
            /// as a date without `active`.
            let periodStart: Double?
            let periodEnd: Double?
            let extraUsage: Extra?

            enum CodingKeys: String, CodingKey {
                case active
                case totalTokens = "total_tokens"
                case usedTokens = "used_tokens"
                case remainingTokens = "remaining_tokens"
                case periodStart = "period_start"
                case periodEnd = "period_end"
                case extraUsage = "extra_usage"
            }
        }

        /// The 加油包: tokens bought on top, spent only after the window's are
        /// gone, and with no expiry.
        struct Extra: Decodable {
            let packCount: Int?
            let totalTokens: Double?
            let usedTokens: Double?
            let remainingTokens: Double?

            enum CodingKeys: String, CodingKey {
                case packCount = "pack_count"
                case totalTokens = "total_tokens"
                case usedTokens = "used_tokens"
                case remainingTokens = "remaining_tokens"
            }
        }

        let success: Bool?
        let result: Quota?
    }

    // MARK: - Mapping

    /// The window, and the pack when one has been bought.
    ///
    /// The fraction is worked out from V2EX's own `used_tokens` over its own
    /// `total_tokens` rather than from `used_percent`, which is the same figure
    /// rounded to a whole number — the panel does its own rounding and would
    /// otherwise round a rounding.
    static func windows(from quota: Reply.Quota) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        let isActive = quota.active ?? false

        if let fraction = self.fraction(used: quota.usedTokens, total: quota.totalTokens) {
            windows.append(UsageWindow(
                id: "window",
                kind: .fiveHour,
                scope: nil,
                usedFraction: fraction,
                windowSeconds: windowSeconds,
                // **Only while a window is running.** `period_end` is zero
                // otherwise, and 1970 drawn as a reset time is a countdown
                // that has already expired.
                resetsAt: isActive ? date(quota.periodEnd) : nil,
                // The five hours are real, but they have not started. Claiming
                // a length with no reset to measure it against is what draws
                // an elapsed arc for a clock that is not running.
                reportsLength: isActive,
                isExhausted: isSpent(quota.remainingTokens)
            ))
        }

        if let extra = quota.extraUsage, (extra.packCount ?? 0) > 0,
           let fraction = self.fraction(used: extra.usedTokens, total: extra.totalTokens) {
            windows.append(UsageWindow(
                id: "extra",
                kind: .topUp,
                scope: nil,
                usedFraction: fraction,
                // A sort key alone: the pack never expires, so there is no
                // length and nothing to count down to. It sorts last because
                // it is spent last.
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                reportsLength: false,
                isExhausted: isSpent(extra.remainingTokens)
            ))
        }

        return windows
    }

    /// How much of a stated allowance is gone, or nil where one was not
    /// stated. A total of zero is not an allowance to divide by.
    static func fraction(used: Double?, total: Double?) -> Double? {
        guard
            let total, total.isFinite, total > 0,
            let used, used.isFinite
        else { return nil }
        return min(max(used / total, 0), 1)
    }

    /// V2EX's own remainder, not the arithmetic. A field that is absent has
    /// said nothing, and reading that as zero marks an allowance spent on the
    /// strength of silence.
    static func isSpent(_ remaining: Double?) -> Bool {
        guard let remaining, remaining.isFinite else { return false }
        return remaining <= 0
    }

    /// Unix seconds, and **zero is not a date**: it is what this route reports
    /// when there is no window, and 1 January 1970 shown as a reset is a
    /// countdown that ran out fifty-six years ago.
    static func date(_ seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func storedKey() -> String? { APIKeyStore.key(for: .v2ex) }
}
