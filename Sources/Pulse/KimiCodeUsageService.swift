import Foundation

/// Kimi Code's limits, from its own usage endpoint.
///
/// Two credentials, same `GET /usages`, in this order:
///
/// 1. **A key pasted into Settings.** It wins, because someone who typed a
///    key meant that one to be used.
/// 2. **A device-code login Pulse drove itself**, stored in
///    `AccountCredentialStore`. Subscription users sign in this way rather
///    than creating a console key. Pulse renews its own refresh token, so a
///    rotation cannot sign the official CLI out.
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
        if let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) {
            return await fetch(token: key, refused: .apiKeyRefused, account: AccountKey(.kimiCode))
        }
        return await fetchSignedIn(AccountKey(.kimiCode), missing: .kimiSignInRequired, expired: .kimiLoginExpired)
    }

    /// An account Pulse signed in to itself. Never looks at a pasted key —
    /// that key belongs to the primary, which is a different subscription.
    func fetch(account: AccountKey, token: String) async -> ProviderUsage {
        await fetch(token: token, refused: .signedOut, account: account)
    }

    /// Pulse's own login, renewed here because nothing else will. The access
    /// token lasts about fifteen minutes (measured); the adaptive interval
    /// can be longer than that, so a pass that does not renew is a pass that
    /// reports signed-out for a still-valid account.
    private func fetchSignedIn(
        _ account: AccountKey,
        missing: ProviderUsage.Unavailability,
        expired: ProviderUsage.Unavailability
    ) async -> ProviderUsage {
        guard var credentials = AccountCredentialStore.credentials(for: account) else {
            return .unavailable(account, reason: missing)
        }

        if !credentials.isFresh {
            guard let renewed = await renew(credentials, for: account) else {
                return .unavailable(account, reason: expired)
            }
            credentials = renewed
        }

        let first = await fetch(token: credentials.accessToken, refused: expired, account: account)
        if case .unavailable(let reason) = first.state, reason == expired {
            // Still marked fresh, but the host refused it — clock skew, or a
            // revocation. One renewal is the difference between "sign in
            // again" and a token that had a few seconds left.
            guard let renewed = await renew(credentials, for: account) else { return first }
            return await fetch(token: renewed.accessToken, refused: expired, account: account)
        }
        return first
    }

    private func renew(_ credentials: AccountCredentials, for account: AccountKey) async -> AccountCredentials? {
        guard let renewed = try? await OAuthLogin.refresh(credentials, for: .kimiCode) else {
            return nil
        }
        AccountCredentialStore.renewed(renewed, for: account)
        return renewed
    }

    private func fetch(token: String, refused: ProviderUsage.Unavailability, account: AccountKey) async -> ProviderUsage {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(account, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(account, reason: refused)
        case 429: return .unavailable(account, reason: .rateLimited)
        default: return .unavailable(account, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(account, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .unavailable(account, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: account,
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

    /// Internal so a fixture test can hold it. Not a public contract.
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

        let user: User?
        let usage: Detail?
        let limits: [Limit]?
    }

    /// Internal so a fixture test can hold it. Not a public contract.
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

        return found.sorted { $0.windowSeconds < $1.windowSeconds }
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
