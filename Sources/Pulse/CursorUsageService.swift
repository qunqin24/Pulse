import Foundation

/// Cursor's limits, read from the account with the login the editor already
/// stored — see `CursorAppLogin` for how a cookie is made out of it.
///
/// Cursor bills a **month** rather than a rolling window, and what the plan
/// includes is **two separate pools**, which is how the account page draws it:
/// one for Cursor's own models (Composer, Cursor Grok) and one for everything
/// else. Spending past the first eats into the second, and past that into
/// whatever extra spend the account has agreed to — so they are three
/// different limits and are reported as three windows, all resetting with the
/// billing cycle.
///
/// `GET cursor.com/api/usage-summary` is not public API, exactly like the two
/// CLI routes, and can change without notice.
struct CursorUsageService: Sendable {
    private static let endpoint = URL(string: "https://cursor.com/api/usage-summary")!

    func fetch() async -> ProviderUsage {
        guard let session = CursorAppLogin.session() else {
            return .unavailable(.cursor, reason: .cursorSignInRequired)
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue(session.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.cursor, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // The token parsed and had months left on it, and the account still
        // refused it — so it is the login that has gone bad, not the absence
        // of one, and the remedy is to open Cursor rather than to sign in.
        case 401, 403: return .unavailable(.cursor, reason: .cursorLoginExpired)
        case 429: return .unavailable(.cursor, reason: .rateLimited)
        default: return .unavailable(.cursor, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(.cursor, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .unavailable(.cursor, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.cursor),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: Self.planName(reply.membershipType),
            creditBalance: Self.remaining(reply)
        )
    }

    // MARK: - Reading the reply

    private struct Reply: Decodable {
        /// One pot of money. `used`, `limit` and `remaining` are **cents**;
        /// the lane percentages are percentages.
        struct Allowance: Decodable {
            let enabled: Bool?
            let used: Double?
            let limit: Double?
            let remaining: Double?
            /// Cursor's own models — what the account page calls "Cursor
            /// Models · Includes Cursor Grok and Composer".
            let autoPercentUsed: Double?
            /// Everything else, which the page calls "Other Models".
            let apiPercentUsed: Double?
        }

        struct Individual: Decodable {
            let plan: Allowance?
            let onDemand: Allowance?
        }

        /// The same two pots for an account billed as a team.
        struct Team: Decodable {
            let pooled: Allowance?
            let onDemand: Allowance?
        }

        let billingCycleEnd: String?
        let membershipType: String?
        let individualUsage: Individual?
        let teamUsage: Team?
    }

    private static func windows(from reply: Reply) -> [UsageWindow] {
        let resets = reply.billingCycleEnd.flatMap(Self.date(from:))
        // A team account reports the same shape under another name.
        let plan = reply.individualUsage?.plan ?? reply.teamUsage?.pooled
        var found: [UsageWindow] = []

        // The two pools the plan includes, in the order and under the names
        // the account page gives them.
        if let pool = pool(plan?.autoPercentUsed, id: "cursorModels", scope: "Cursor Models", resets: resets) {
            found.append(pool)
        }
        if let pool = pool(plan?.apiPercentUsed, id: "otherModels", scope: "Other Models", resets: resets) {
            found.append(pool)
        }

        // An account shape that reports no pools at all still has the money:
        // what the plan is worth and how much of it has gone. Only used as a
        // fallback, since on an account that *does* report pools this is a
        // different denominator and would read as a third, contradictory
        // limit — see the note on `money(_:)`.
        if found.isEmpty, let window = money(plan, id: "plan", kind: .monthly, resets: resets) {
            found.append(window)
        }

        // Spending past the plan. Off unless the account has turned it on, and
        // left out entirely when it is — a row reading "0% of nothing" says
        // less than no row at all.
        if let window = money(
            reply.individualUsage?.onDemand ?? reply.teamUsage?.onDemand,
            id: "onDemand",
            kind: .spend,
            resets: resets
        ) {
            found.append(window)
        }

        return found
    }

    /// One of the plan's two pools.
    ///
    /// **The figure is a percentage, not a fraction** — 0.0267 means 0.0267%,
    /// not 2.67%. That is worth stating because it looks like a fraction and
    /// reading it as one would be a hundredfold overstatement. It was settled
    /// by arithmetic rather than assumed: on an account 12¢ in, the three
    /// percentages the reply carries imply pools of $450 for Cursor's own
    /// models and $22.50 for the rest, and a combined $472.50 that matches
    /// `totalPercentUsed` to the cent. Three numbers that agree are a system,
    /// not a coincidence.
    ///
    /// One consequence to expect: Cursor's own page shows **1%** for anything
    /// above zero, so a pool Pulse reads as 0.03% — and rounds to 0% like every
    /// other figure in the app — reads as 1% there. Both are true; only the
    /// rounding differs.
    private static func pool(
        _ percent: Double?,
        id: String,
        scope: String,
        resets: Date?
    ) -> UsageWindow? {
        guard let percent else { return nil }

        return UsageWindow(
            id: id,
            kind: .monthly,
            scope: scope,
            usedFraction: min(max(percent / 100, 0), 1),
            windowSeconds: 30 * 86_400,
            resetsAt: resets,
            isExhausted: percent >= 100
        )
    }

    /// A pot measured in money rather than as a share of a pool: how many of
    /// its cents have gone.
    ///
    /// This is a **different denominator** from the two pools above — it is the
    /// plan's cash value, $20 on Pro, against which the pools are worth $472.50
    /// — so the two must never be shown side by side as though they were the
    /// same kind of thing. It is what the extra-spend limit is, and what the
    /// plan falls back to when an account reports no pools.
    private static func money(
        _ allowance: Reply.Allowance?,
        id: String,
        kind: UsageWindow.Kind,
        resets: Date?
    ) -> UsageWindow? {
        guard
            let allowance,
            allowance.enabled != false,
            let used = allowance.used,
            let limit = allowance.limit,
            limit > 0
        else { return nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(used / limit, 0), 1),
            // The billing cycle. Only the reset stamp is ever displayed; this
            // is what orders the two rows.
            windowSeconds: 30 * 86_400,
            resetsAt: resets,
            isExhausted: used >= limit
        )
    }

    /// What is left of the plan's allowance, in dollars.
    ///
    /// A real balance rather than an allowance, which is why it is reported
    /// here and not for Antigravity: the account says how much of the money is
    /// still there, not merely how much it started with.
    private static func remaining(_ reply: Reply) -> String? {
        guard
            let allowance = reply.individualUsage?.plan ?? reply.teamUsage?.pooled,
            let remaining = allowance.remaining
        else { return nil }

        // Cents, and Cursor prices in dollars whatever the reader's own
        // currency is — hence a fixed code rather than the locale's.
        return (remaining / 100).formatted(
            .currency(code: "USD")
                .precision(.fractionLength(2))
                .locale(LocalizationSource.locale)
        )
    }

    /// "pro_plus" → "Pro+". An unfamiliar tier is tidied and passed through
    /// rather than blanked: an unknown name still beats none, and it is the
    /// only clue left when a new one appears.
    private static func planName(_ membership: String?) -> String? {
        guard let membership, !membership.isEmpty else { return nil }

        return membership
            .split(separator: "_")
            .map { part -> String in
                part == "plus" ? "+" : part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            .reduce(into: "") { name, part in
                // "+" joins on to the word before it; anything else is a word.
                name += (name.isEmpty || part == "+") ? part : " " + part
            }
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`, and this
    /// parses one stamp a refresh. The stamps carry milliseconds.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
