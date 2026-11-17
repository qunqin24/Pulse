// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Kimi Code's limits, from its own documented usage endpoint.
///
/// Reached with a key the user pastes into Settings, kept encrypted on this Mac —
/// the same arrangement as OpenCode Go, and for now without the fallback to a
/// credential another tool stored.
///
/// The reply has **two kinds of limit in it and they are not the same figure**:
///
/// - `limits[]` — windows the service actually times, each stating a duration
///   and a unit (300 minutes, say). These are read as they are given.
/// - `usage` — the weekly allowance. The reply gives it a reset time and no
///   length, and the reset can land anywhere inside the week since the window
///   rolls, so the length is not inferable from it — it is named from what the
///   plan actually is.
/// - `usages` — what replaced `usage` on accounts whose plan is counted by
///   the month (#112, a reporter's reply of 2026-11-17): `limit_month_code`
///   and `limit_month_total`, the second being Kimi and Kimi Code together,
///   each a `used_ratio` from 0 to 1 and a `reset_time`, again with no length.
///   `limit_5h` repeats the five-hour entry of `limits[]` and is not read.
///
/// Every count arrives as a *string*, and `detail` reports what is left rather
/// than what is spent, so both are converted here and everything downstream
/// stays in whole numbers of what is gone.
struct KimiCodeUsageService: Sendable {
    let enteredKey: String?

    private static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.kimiCode, reason: .apiKeyMissing)
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, response) = try? await NetworkSession.shared.recordedData(for: request) else {
            return .unavailable(.kimiCode, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.kimiCode, reason: .apiKeyRefused)
        case 429: return .unavailable(.kimiCode, reason: .rateLimited)
        default: return .unavailable(.kimiCode, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.kimiCode, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .unavailable(.kimiCode, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.kimiCode),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: Self.planName(reply.user?.membership?.level),
            // `totalQuota` comes back empty and `parallel.limit` is how many
            // requests may run at once, which is not a balance.
            creditBalance: nil
        )
    }

    // MARK: - Reading the reply

    /// Internal rather than private, and deliberately: this and `windows(from:)`
    /// / `planName(_:)` below are what a fixture test holds a reconstructed
    /// reply against. Nothing outside the module can see them either way. Do
    /// not tidy these back to `private` — that takes the fixture test with it.
    struct Reply: Decodable {
        struct Detail: Decodable {
            let limit: String?
            let used: String?
            let remaining: String?
            let resetTime: String?
        }

        struct Window: Decodable {
            let duration: Int?
            let timeUnit: String?
        }

        struct Limit: Decodable {
            let window: Window?
            let detail: Detail?
        }

        struct Membership: Decodable { let level: String? }
        struct User: Decodable { let membership: Membership? }

        /// One allowance in `usages`: how much is gone, 0...1, and when it
        /// resets. Snake case, unlike the rest of the reply.
        struct Ratio: Decodable {
            let usedRatio: Double?
            let resetTime: String?

            enum CodingKeys: String, CodingKey {
                case usedRatio = "used_ratio"
                case resetTime = "reset_time"
            }
        }

        struct Usages: Decodable {
            let monthCode: Ratio?
            let monthTotal: Ratio?

            enum CodingKeys: String, CodingKey {
                case monthCode = "limit_month_code"
                case monthTotal = "limit_month_total"
            }
        }

        let user: User?
        let usage: Detail?
        let usages: Usages?
        let limits: [Limit]?
    }

    static func windows(from reply: Reply) -> [UsageWindow] {
        var found: [UsageWindow] = []

        // The timed windows first, named by the length the service states.
        for (index, limit) in (reply.limits ?? []).enumerated() {
            guard
                let seconds = duration(of: limit.window),
                let window = window(
                    from: limit.detail,
                    // The position too: two windows of the same length is
                    // exactly the shape the other providers' per-model limits
                    // take, and duplicate ids collapse rows in the card.
                    id: "limit.\(index).\(seconds)",
                    kind: kind(forSeconds: seconds),
                    seconds: seconds
                )
            else { continue }

            found.append(window)
        }

        // Then the weekly allowance, which the reply carries separately and
        // does not put a length on. Only its reset time is ever displayed; the
        // seconds are what sort it after the shorter windows.
        if let weekly = window(from: reply.usage, id: "weekly", kind: .weekly,
                               seconds: 7 * 86_400, reportsLength: false) {
            found.append(weekly)
        }

        // The month, Kimi Code's own and everything together, under the
        // names Kimi's usage page gives them. A month is 28 to 31 days and
        // the reply states none, so thirty only sorts the rows.
        if let code = monthly(reply.usages?.monthCode, id: "month.code", scope: "Code") {
            found.append(code)
        }
        if let total = monthly(reply.usages?.monthTotal, id: "month.total", scope: "Total") {
            found.append(total)
        }

        // Shortest first; windows of one length keep the order above, so the
        // two monthly rows do not trade places between refreshes.
        return found.enumerated()
            .sorted { ($0.element.windowSeconds, $0.offset) < ($1.element.windowSeconds, $1.offset) }
            .map(\.element)
    }

    /// One of the monthly allowances in `usages`, or nil without a finite
    /// ratio: no figure is no row, never a month at 0%.
    private static func monthly(_ ratio: Reply.Ratio?, id: String, scope: String) -> UsageWindow? {
        guard let used = ratio?.usedRatio, used.isFinite else { return nil }
        return UsageWindow(
            id: id,
            kind: .monthly,
            scope: scope,
            usedFraction: min(max(used, 0), 1),
            windowSeconds: 30 * 86_400,
            resetsAt: ratio?.resetTime.flatMap(Self.date(from:)),
            reportsLength: false,
            isExhausted: used >= 1
        )
    }

    private static func window(
        from detail: Reply.Detail?,
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int,
        reportsLength: Bool = true
    ) -> UsageWindow? {
        guard
            let detail,
            let limit = number(detail.limit),
            limit > 0
        else { return nil }

        // `used` when it is given, otherwise what the limit and the remainder
        // imply. `limits[].detail` carries no `used` at all.
        let used = number(detail.used) ?? number(detail.remaining).map { limit - $0 }
        guard let used else { return nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(used / limit, 0), 1),
            windowSeconds: seconds,
            resetsAt: detail.resetTime.flatMap(Self.date(from:)),
            // The rolling allowance states a reset and no length, so `seconds`
            // is what sorts it rather than something to divide by. It is the
            // *caller* that knows which one this is: testing the kind instead
            // would also catch a limit that genuinely states seven days, and
            // silently take away its forecast and its clock arc.
            reportsLength: reportsLength,
            isExhausted: used >= limit
        )
    }

    /// A window's length in seconds, or nil for a unit that isn't recognised —
    /// a window with no length can't be named or sorted, and inventing one
    /// would put a figure under a heading that isn't true.
    private static func duration(of window: Reply.Window?) -> Int? {
        guard let window, let duration = window.duration, duration > 0 else { return nil }

        let unit: Int? = switch window.timeUnit {
        case "TIME_UNIT_SECOND": 1
        case "TIME_UNIT_MINUTE": 60
        case "TIME_UNIT_HOUR": 3_600
        case "TIME_UNIT_DAY": 86_400
        default: nil
        }
        return unit.flatMap { UsageWindow.length(duration, unitSeconds: $0) }
    }

    private static func kind(forSeconds seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 5 * 3_600: .fiveHour
        case 7 * 86_400: .weekly
        case 30 * 86_400: .monthly
        default: .other(seconds: seconds)
        }
    }

    /// "LEVEL_INTERMEDIATE" → "Intermediate". An unfamiliar tier is passed
    /// through tidied rather than blanked: an unknown name still beats none,
    /// and it is the only clue left when a new tier appears.
    static func planName(_ level: String?) -> String? {
        guard let level, !level.isEmpty else { return nil }

        let bare = level.hasPrefix("LEVEL_") ? String(level.dropFirst("LEVEL_".count)) : level
        return bare
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func number(_ text: String?) -> Double? {
        text.flatMap(Double.init)
    }

    /// The stamps carry sub-second precision, which the plain internet-date
    /// options refuse.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
