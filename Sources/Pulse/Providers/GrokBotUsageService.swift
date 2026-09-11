import Foundation

/// Grok Bot's weekly allowance.
///
/// **A ring of its own, though the credential is Cursor's.** Grok Bot is xAI's,
/// sold through Cursor and billed against the Cursor account, so it is read
/// with the login the Cursor editor already stored — `CursorAppLogin` makes the
/// cookie, and nothing is held here. But it is not a share of Cursor's monthly
/// bill the way the two model pools are: it is a separate weekly allowance
/// under a name people know, so it gets its own place on the rail rather than
/// a fourth row on somebody else's card. It was the fourth row first, and the
/// question that came back was "where is Grok Bot" — asked while looking
/// straight at the Grok pane, which is the *other* Grok.
///
/// **And it is the other Grok.** `GrokUsageService` reads the weekly pool a
/// SuperGrok plan spends across every xAI product; this reads an allowance that
/// arrives with a Cursor subscription. Two companies' bills, one brand — so the
/// two never share a credential, an endpoint, or a mark.
///
/// `POST cursor.com/api/dashboard/get-sand-usage-status` — Cursor's own
/// protocol calls Grok Bot "Sand". Not public API, exactly like the usage
/// summary beside it, and it can change without notice.
struct GrokBotUsageService: Sendable {
    private static let endpoint =
        URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!

    /// An account Pulse signed in to itself, read with the token it holds for
    /// it rather than the one the editor stored. The request is otherwise the
    /// same: it is the same endpoint and the same kind of cookie, built from a
    /// different login.
    func fetch(account: AccountKey, token: String) async -> ProviderUsage {
        guard let session = CursorAppLogin.session(from: token) else {
            return .unavailable(account, reason: .signedOut)
        }
        return await fetch(session: session, for: account)
    }

    func fetch() async -> ProviderUsage {
        guard let session = CursorAppLogin.session() else {
            // The login is Cursor's, so the remedy names Cursor. That is not
            // the wrong-provider trap the rest of `Unavailability` was fixed
            // for — it is where this credential actually comes from, and
            // sending someone to Grok Bot's own app would not produce one.
            return .unavailable(
                .grokBot,
                reason: CursorAppLogin.hasStoredToken() ? .cursorLoginExpired : .cursorSignInRequired
            )
        }
        return await fetch(session: session, for: AccountKey(.grokBot))
    }

    private func fetch(session: CursorAppLogin.Session, for account: AccountKey) async -> ProviderUsage {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(session.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The dashboard's own call sends it, and an endpoint that checks the
        // origin refuses a request without one.
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15

        // The session goes out as a `Cookie` header, which `URLSession` will
        // carry across a redirect to another host — unlike `Authorization`,
        // which it strips. So redirects are refused outright, for the reason
        // `CursorUsageService` refuses them.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let http = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { http.invalidateAndCancel() }

        guard let (data, response) = try? await http.data(for: request) else {
            return .unavailable(account, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(account, reason: account.isPrimary ? .cursorLoginExpired : .signedOut)
        case 429: return .unavailable(account, reason: .rateLimited)
        default: return .unavailable(account, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(account, reason: .unreadableReply)
        }

        guard let window = Self.window(from: reply) else {
            return .unavailable(account, reason: Self.absence(reply))
        }

        return ProviderUsage(
            account: account,
            windows: [window],
            observedAt: Date(),
            state: .live,
            plan: reply.grokPlanLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilWhenEmpty,
            // The reply prices the *upgrade* — "$500 of Grok Bot usage each
            // week with Pro+" — and never what is left of this plan's own
            // allowance. An allowance is not a balance; see Antigravity.
            creditBalance: nil
        )
    }

    // MARK: - Reading the reply

    /// Every field optional: this is not public API, and a shape that changes
    /// should cost the reading rather than crash into a decoding failure that
    /// says nothing useful.
    private struct Reply: Decodable {
        let currentPeriodStart: String?
        /// Absent on every account measured here — see `window(from:)`.
        let nextResetTimestampUtc: String?
        /// How much is **gone**, 0...100.
        let usagePercent: Double?
        let hasNonZeroIncludedLimit: Bool?
        let includedLimitZero: Bool?
        /// A seat drawing on the organisation's pot has no personal allowance,
        /// so there is no individual share to draw.
        let usesPooledEnterpriseAllowance: Bool?
        /// "Grok Bot Plan" — what the dashboard calls this account's tier.
        let grokPlanLabel: String?
    }

    /// The weekly window, when the account actually has an allowance.
    ///
    /// **The reply states no reset and no length**, which was checked rather
    /// than assumed: Cursor's dashboard REST call and the Connect RPC behind
    /// it (`api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`)
    /// answer byte for byte, and neither carries the `nextResetTimestampUtc` a
    /// reference implementation decodes. So the field is read where a reply
    /// offers one, the row simply has no reset line where it does not, and the
    /// seven days are a **sort key, never a length to divide by**
    /// (`reportsLength: false`) — as Kimi's rolling week and Cursor's own
    /// billing cycle are.
    ///
    /// That it is *weekly* is xAI's own word (docs.x.ai/grok-bot/faq), not an
    /// inference from a start stamp.
    ///
    /// **An absent `usagePercent` is not a zero here, and that is the opposite
    /// of the rule `GrokUsageService` follows** — worth stating, because the
    /// two look like the same case and are not. Grok's percentage is a proto3
    /// scalar with implicit presence, so a zero is dropped on the wire; this
    /// one is declared `opt: true` in the schema Cursor ships
    /// (`{no:3,name:"usage_percent",kind:"scalar",T:1,opt:!0}`), which is
    /// explicit presence — absent means unset. The vendor's own client agrees:
    /// `if (e.usesPooledEnterpriseAllowance || e.usagePercent == null || …)
    /// return null`.
    ///
    /// **Nothing included is not nothing used.** An account with no Grok Bot
    /// allowance answers 0% too, with the rest of the reply given over to
    /// upgrade marketing — drawn literally that is a full green ring for
    /// something the account does not have, the trap Copilot's unissued quotas
    /// set. So the account has to say it has an allowance before a figure of
    /// nothing is believed to mean nothing *used*.
    private static func window(from reply: Reply) -> UsageWindow? {
        guard
            reply.usesPooledEnterpriseAllowance != true,
            reply.includedLimitZero != true,
            reply.hasNonZeroIncludedLimit == true,
            let percent = reply.usagePercent
        else { return nil }

        return UsageWindow(
            id: "grokBot",
            kind: .weekly,
            scope: nil,
            usedFraction: min(max(percent / 100, 0), 1),
            windowSeconds: 7 * 86_400,
            resetsAt: reply.nextResetTimestampUtc.flatMap(Self.date(from:)),
            reportsLength: false,
            isExhausted: percent >= 100
        )
    }

    /// Why there is no window — and the two reasons are different advice.
    ///
    /// A plan that does not include Grok Bot is not a failure to report
    /// anything: it is a complete answer, and "no limits reported" would send
    /// someone looking for a fault that isn't there.
    private static func absence(_ reply: Reply) -> ProviderUsage.Unavailability {
        // **A reply that said nothing is not a reply that said no.** Every
        // field here is optional so a shape change costs one row rather than
        // the card — but read carelessly that turns any rename into a
        // confident claim about the user's subscription. So the plan is only
        // reported as excluding Grok Bot when the reply actually *says* so;
        // a reply carrying none of these at all is one we could not read.
        // Same rule as Z.ai's, where "check your key" about a key that is fine
        // sends the user after the wrong thing.
        let saidSomething = reply.usesPooledEnterpriseAllowance != nil
            || reply.includedLimitZero != nil
            || reply.hasNonZeroIncludedLimit != nil
        guard saidSomething else { return .unreadableReply }

        let entitled = reply.usesPooledEnterpriseAllowance != true
            && reply.includedLimitZero != true
            && reply.hasNonZeroIncludedLimit == true
        return entitled ? .noLimitsReported : .grokBotNotIncluded
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`, and this
    /// parses at most one stamp a refresh.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
