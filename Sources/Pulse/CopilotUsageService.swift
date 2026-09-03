import Foundation

/// GitHub Copilot's quotas, from the endpoint its own editor plugins use.
///
/// `GET api.github.com/copilot_internal/user`, with a GitHub OAuth token as
/// `Authorization: token …` and the editor headers the plugins send. Not public
/// API — the name says so — and it can change without notice.
///
/// **The reply reports what is *left*.** `percent_remaining` at 90 means 10%
/// spent, the same way round as Antigravity and MiniMax, so the inversion
/// happens here and everything downstream stays in terms of what is gone.
///
/// Three quotas come back — `completions`, `chat` and `premium_interactions` —
/// and which of them an account actually has depends on the plan.
struct CopilotUsageService: Sendable {
    private static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!

    let token: String?

    func fetch() async -> ProviderUsage {
        guard let token = token.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.copilot, reason: .signedOut)
        }

        var request = URLRequest(url: Self.endpoint)
        // "token", not "Bearer": this endpoint takes the OAuth token in
        // GitHub's older scheme, and refuses the other one.
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        // It answers a plugin, so it is asked as one. Dropping these has been
        // reported to change what comes back.
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.copilot, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.copilot, reason: .signedOut)
        case 429: return .unavailable(.copilot, reason: .rateLimited)
        default: return .unavailable(.copilot, reason: .serverError)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable(.copilot, reason: .unreadableReply)
        }

        let windows = Self.windows(from: root)
        guard !windows.isEmpty else { return .unavailable(.copilot, reason: .noLimitsReported) }

        return ProviderUsage(
            account: AccountKey(.copilot),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: Self.planName(root["copilot_plan"] as? String),
            creditBalance: nil
        )
    }

    // MARK: - Mapping

    /// The three quotas, in the order they are worth reading.
    ///
    /// `completions` is included, and is the one a reference implementation
    /// this was checked against leaves out — on a free plan it is the largest
    /// allowance of the three (2,000 against chat's 200), so dropping it hides
    /// most of what the account has.
    private static let lanes: [(key: String, scope: String)] = [
        ("premium_interactions", "Premium requests"),
        ("chat", "Chat"),
        ("completions", "Completions"),
    ]

    /// Internal so the mapping can be driven against a captured reply: the
    /// fields are undocumented and the placeholder rule below is the whole
    /// difference between a useful ring and a wrong one.
    static func windows(from root: [String: Any]) -> [UsageWindow] {
        let snapshots = root["quota_snapshots"] as? [String: Any] ?? [:]

        // One reset for the account, not one per quota: the per-snapshot
        // `quota_reset_at` comes back as 0. It lands on the first of a month.
        let resets = (root["quota_reset_date_utc"] as? String).flatMap(parseDate)
            ?? (root["quota_reset_date"] as? String).flatMap(parseDate)

        return lanes.compactMap { lane in
            guard let snapshot = snapshots[lane.key] as? [String: Any] else { return nil }
            return window(snapshot, scope: lane.scope, key: lane.key, resets: resets)
        }
    }

    private static func window(
        _ snapshot: [String: Any],
        scope: String,
        key: String,
        resets: Date?
    ) -> UsageWindow? {
        let entitlement = number(snapshot["entitlement"]) ?? 0
        let unlimited = snapshot["unlimited"] as? Bool ?? false

        // **A quota the plan does not include is left out, not drawn at 100%.**
        // It comes back with `has_quota: false`, nothing issued, and
        // `percent_remaining: 0` — which read literally is a full red ring for
        // something the account never had. `has_quota` states it outright;
        // the zero entitlement is checked too, since older replies omit it.
        let hasQuota = snapshot["has_quota"] as? Bool
        if hasQuota == false { return nil }

        // Without that flag, an older reply is told apart by the *percentage*:
        // a lane the plan excludes reads 100% remaining with nothing issued,
        // while a lane you have **run out of** also has nothing left — and
        // dropping that one hides the alarm at the moment it matters. So the
        // zero counts alone are not enough to call it a placeholder.
        if hasQuota == nil, !unlimited, entitlement <= 0,
           (number(snapshot["remaining"]) ?? 0) <= 0,
           (number(snapshot["percent_remaining"]) ?? 0) >= 100 { return nil }

        // An unlimited lane has no share to show, so there is no ring to draw
        // for it — the same rule the other providers' unlimited lanes follow.
        guard !unlimited, let remaining = number(snapshot["percent_remaining"]) else { return nil }

        return UsageWindow(
            id: "copilot.\(key)",
            // A calendar month, which is what the reset date describes.
            kind: .monthly,
            scope: scope,
            usedFraction: min(max((100 - remaining) / 100, 0), 1),
            // Enough to sort by, and **not** a length the service stated: a
            // calendar month is 28 to 31 days, so the clock arc must not
            // divide by it.
            windowSeconds: 30 * 86_400,
            resetsAt: resets,
            reportsLength: false,
            // **Spent is not the same as over the allowance.** A lane with
            // overage permitted keeps working past its included share and is
            // billed for it — Copilot's own client treats exhausted as
            // `used >= quota && !overageEnabled && !unlimited` and lets the
            // request through otherwise. So `overage_count` above zero means
            // the opposite of blocked: it is the count of what has already
            // been spent that way. Reading it as spent painted a red ring for
            // someone who had deliberately paid to carry on.
            isExhausted: remaining <= 0 && !(snapshot["overage_permitted"] as? Bool ?? false)
        )
    }

    /// GitHub's internal plan names, tidied. Anything unfamiliar is passed
    /// through rather than blanked — an unknown name still beats none.
    static func planName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return switch raw.lowercased() {
        case "individual": "Individual"
        case "free": "Free"
        case "business": "Business"
        case "enterprise": "Enterprise"
        default: raw
        }
    }

    /// `2026-10-01T00:00:00.000Z`, or the bare `2026-10-01` older replies give.
    private static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }

        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: text)
    }

    /// Figures have arrived as both `200` and `200.0`; take either.
    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
