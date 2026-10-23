// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
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
/// **Unless the plan's included usage is weekly.** Cursor's newer plans,
/// Premium among them, include usage by the **week**, and the usage summary does not see it: on such an account it
/// reports both monthly pools at 0% while Cursor's own page says a quarter of
/// the week is gone (#87). The editor draws that week from two other calls —
/// the plan's period and reset from `GetPlanInfo`, the figure from
/// `GetCurrentPeriodUsage` — and so does this, through the dashboard's REST
/// form of each: one weekly window takes the place of the two pools.
///
/// Grok Bot is on this account too and is **not** read here — it is a weekly
/// included allowance rather than a share of the monthly bill, so it is its
/// own provider with its own ring. It borrows this file's login: see
/// `GrokBotUsageService`.
///
/// `GET cursor.com/api/usage-summary` is not public API, exactly like the two
/// CLI routes, and can change without notice.
struct CursorUsageService: Sendable {
    private static let endpoint = URL(string: "https://cursor.com/api/usage-summary")!
    private static let planInfoEndpoint = URL(string: "https://cursor.com/api/dashboard/get-plan-info")!
    private static let periodUsageEndpoint =
        URL(string: "https://cursor.com/api/dashboard/get-current-period-usage")!

    func fetch() async -> ProviderUsage {
        let session: CursorAppLogin.Session
        switch CursorAppLogin.load() {
        case .token(let token):
            // A token that is stored but spent is a login gone stale, not an
            // absent one — so say what actually helps.
            guard let built = CursorAppLogin.session(from: token) else {
                return .unavailable(.cursor, reason: .cursorLoginExpired)
            }
            session = built
        case .keychainRefused:
            return .unavailable(.cursor, reason: .cursorKeyRefused)
        // A key that opens nothing even read afresh: what Cursor wrote is not
        // something this can read, and opening Cursor rewrites it.
        case .unreadable:
            return .unavailable(.cursor, reason: .cursorLoginExpired)
        case .absent:
            return .unavailable(.cursor, reason: .cursorSignInRequired)
        }

        // The session goes out as a `Cookie` header, which `URLSession` will
        // happily carry across a redirect to another host — unlike
        // `Authorization`, which it strips. So redirects are refused outright.
        let configuration = NetworkSession.configured(.ephemeral)
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let http = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { http.invalidateAndCancel() }

        let reply: Reply
        switch await Self.read(Reply.self, from: Self.request(Self.endpoint, session: session), with: http) {
        case .success(let read): reply = read
        case .failure(let refusal): return .unavailable(.cursor, reason: refusal.reason)
        }

        var windows = Self.windows(from: reply)

        // A plan whose included usage is weekly: the two monthly pools are not
        // what it spends, so they give way to the week. A plan-info call that
        // fails says nothing about the period, and the summary stands as it
        // always has; once the plan *has* said weekly, though, a week that
        // cannot be read is a failed read — the pools would be a confident
        // 0% of the wrong thing.
        if case .success(let planInfo) = await Self.read(
            PlanInfoReply.self, from: Self.post(Self.planInfoEndpoint, session: session), with: http
        ), let plan = planInfo.planInfo, plan.isWeekly {
            let usage: PeriodUsageReply
            switch await Self.read(
                PeriodUsageReply.self, from: Self.post(Self.periodUsageEndpoint, session: session), with: http
            ) {
            case .success(let read): usage = read
            case .failure(let refusal): return .unavailable(.cursor, reason: refusal.reason)
            }
            windows = Self.weeklyWindows(plan: plan, usage: usage, summary: windows)
        }

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

    // MARK: - Requests

    private static func request(_ url: URL, session: CursorAppLogin.Session) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(session.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    /// The dashboard's calls, which are `POST {}` with the dashboard's own
    /// origin — the same shape Grok Bot's status is read with.
    private static func post(_ url: URL, session: CursorAppLogin.Session) -> URLRequest {
        var request = request(url, session: session)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.httpBody = Data("{}".utf8)
        return request
    }

    private struct Refusal: Error {
        let reason: ProviderUsage.Unavailability
    }

    private static func read<Value: Decodable>(
        _ type: Value.Type,
        from request: URLRequest,
        with http: URLSession
    ) async -> Result<Value, Refusal> {
        guard let (data, response) = try? await http.recordedData(for: request) else {
            return .failure(Refusal(reason: .unreachable))
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // The token parsed and had months left on it, and the account still
        // refused it — so it is the login that has gone bad, not the absence
        // of one, and the remedy is to open Cursor rather than to sign in.
        case 401, 403: return .failure(Refusal(reason: .cursorLoginExpired))
        case 429: return .failure(Refusal(reason: .rateLimited))
        default: return .failure(Refusal(reason: .serverError))
        }

        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return .failure(Refusal(reason: .unreadableReply))
        }
        return .success(value)
    }

    // MARK: - Reading the reply

    /// Internal rather than private, and deliberately: this and the mapping
    /// functions below are what a fixture test holds a reconstructed reply
    /// against. Nothing outside the module can see them either way. Do not
    /// tidy these back to `private` — that takes the fixture test with it.
    struct Reply: Decodable {
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
            /// Enterprise plans report one shared allowance here rather than
            /// the two model pools. Its money fields are cents.
            let overall: Allowance?
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

    /// `get-plan-info`: what the plan includes and over what period.
    ///
    /// The dashboard's REST form of `aiserver.v1.DashboardService/GetPlanInfo`.
    /// Its 64-bit stamps are milliseconds and may come as strings, which is
    /// how protobuf's JSON writes them; the period is an enum that may come as
    /// its name or its number.
    struct PlanInfoReply: Decodable {
        struct PlanInfo: Decodable {
            let includedUsagePeriod: Period?
            let includedUsageResetsAt: Stamp?

            var isWeekly: Bool { includedUsagePeriod?.isWeekly == true }
        }

        let planInfo: PlanInfo?
    }

    /// `INCLUDED_USAGE_PERIOD_WEEKLY`, or `2`, its number in the editor's
    /// schema. Anything else — monthly, unspecified, a name not seen yet — is
    /// not weekly, and the summary's pools stand.
    struct Period: Decodable {
        let isWeekly: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                isWeekly = number == 2
            } else {
                let name = try container.decode(String.self).uppercased()
                isWeekly = name == "INCLUDED_USAGE_PERIOD_WEEKLY" || name == "WEEKLY"
            }
        }
    }

    /// A moment in **milliseconds**, written as a number or as a string.
    /// Absent or unreadable is nil, never the epoch.
    struct Stamp: Decodable {
        let date: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let milliseconds: Double? = if let number = try? container.decode(Double.self) {
                number
            } else if let text = try? container.decode(String.self) {
                Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                nil
            }
            date = milliseconds.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        }
    }

    /// `get-current-period-usage`, the REST form of `GetCurrentPeriodUsage`.
    /// Only the one figure the editor draws as the week is read.
    struct PeriodUsageReply: Decodable {
        struct PlanUsage: Decodable {
            /// A percentage, like the pools' — 25 means 25%.
            let totalPercentUsed: Double?
        }

        let planUsage: PlanUsage?
    }

    /// The week, in place of the two monthly pools; extra spend, when the
    /// account has it, stays as it was.
    ///
    /// The figure is `totalPercentUsed`, because that is what the editor draws
    /// under "Weekly usage limit" on such a plan, with `includedUsageResetsAt`
    /// as its reset. The period is the plan's own word, so the seven days are
    /// a stated length. **No figure is no window** — not a week at 0%.
    static func weeklyWindows(
        plan: PlanInfoReply.PlanInfo,
        usage: PeriodUsageReply,
        summary: [UsageWindow]
    ) -> [UsageWindow] {
        var found: [UsageWindow] = []
        if let percent = usage.planUsage?.totalPercentUsed, percent.isFinite {
            found.append(UsageWindow(
                id: "weekly",
                kind: .weekly,
                scope: nil,
                usedFraction: min(max(percent / 100, 0), 1),
                windowSeconds: 7 * 86_400,
                resetsAt: plan.includedUsageResetsAt?.date,
                isExhausted: percent >= 100
            ))
        }
        return found + summary.filter { $0.kind == .spend }
    }

    static func windows(from reply: Reply) -> [UsageWindow] {
        let resets = reply.billingCycleEnd.flatMap(Self.date(from:))
        // A team account reports the same shape under another name.
        let plan = reply.individualUsage?.plan ?? reply.teamUsage?.pooled
        let overall = reply.individualUsage?.overall
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
        if found.isEmpty, let window = money(plan ?? overall, id: "plan", kind: .monthly, resets: resets) {
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
            // A billing cycle, which runs 28 to 31 days. Thirty is what orders
            // the rows; it is not a length Cursor reported, so it is not one to
            // divide by either.
            windowSeconds: 30 * 86_400,
            resetsAt: resets,
            reportsLength: false,
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
            // is what orders the two rows — and, being chosen rather than
            // reported, is not something to divide by.
            windowSeconds: 30 * 86_400,
            resetsAt: resets,
            reportsLength: false,
            isExhausted: used >= limit,
            amounts: .init(
                used: used / 100,
                remaining: allowance.remaining.map { $0 / 100 },
                limit: limit / 100,
                currency: "USD"
            )
        )
    }

    /// What is left of the plan's allowance, in dollars.
    ///
    /// A real balance rather than an allowance, which is why it is reported
    /// here and not for Antigravity: the account says how much of the money is
    /// still there, not merely how much it started with.
    static func remaining(_ reply: Reply) -> String? {
        guard
            let allowance = reply.individualUsage?.plan ?? reply.teamUsage?.pooled
                ?? reply.individualUsage?.overall,
            let remaining = allowance.remaining
        else { return nil }

        // Cents, and Cursor prices in dollars whatever the reader's own
        // currency is — hence a fixed code rather than the locale's.
        return (remaining / 100).formatted(Money.reportedStyle("USD"))
    }

    /// "pro_plus" → "Pro+". An unfamiliar tier is tidied and passed through
    /// rather than blanked: an unknown name still beats none, and it is the
    /// only clue left when a new one appears.
    static func planName(_ membership: String?) -> String? {
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
