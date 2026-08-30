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

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
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
            provider: .kimiCode,
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

    private struct Reply: Decodable {
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

        let user: User?
        let usage: Detail?
        let limits: [Limit]?
    }

    private static func windows(from reply: Reply) -> [UsageWindow] {
        var found: [UsageWindow] = []

        // The timed windows first, named by the length the service states.
        for limit in reply.limits ?? [] {
            guard
                let seconds = duration(of: limit.window),
                let window = window(
                    from: limit.detail,
                    id: "limit.\(seconds)",
                    kind: kind(forSeconds: seconds),
                    seconds: seconds
                )
            else { continue }

            found.append(window)
        }

        // Then the weekly allowance, which the reply carries separately and
        // does not put a length on. Only its reset time is ever displayed; the
        // seconds are what sort it after the shorter windows.
        if let weekly = window(from: reply.usage, id: "weekly", kind: .weekly, seconds: 7 * 86_400) {
            found.append(weekly)
        }

        return found.sorted { $0.windowSeconds < $1.windowSeconds }
    }

    private static func window(
        from detail: Reply.Detail?,
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int
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
            isExhausted: used >= limit
        )
    }

    /// A window's length in seconds, or nil for a unit that isn't recognised —
    /// a window with no length can't be named or sorted, and inventing one
    /// would put a figure under a heading that isn't true.
    private static func duration(of window: Reply.Window?) -> Int? {
        guard let window, let duration = window.duration, duration > 0 else { return nil }

        return switch window.timeUnit {
        case "TIME_UNIT_SECOND": duration
        case "TIME_UNIT_MINUTE": duration * 60
        case "TIME_UNIT_HOUR": duration * 3_600
        case "TIME_UNIT_DAY": duration * 86_400
        default: nil
        }
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
    private static func planName(_ level: String?) -> String? {
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
