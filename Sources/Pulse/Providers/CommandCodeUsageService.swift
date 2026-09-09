import Foundation

/// Command Code's plan limits, credit pool and org spend limits.
///
/// Command Code is a terminal coding agent published by CommandCodeAI and
/// installed from npm as `command-code` (its binaries are `cmd`, `cmdc`,
/// `command-code` and `commandcode`). It bills a **credit balance in US
/// dollars** rather than a token allowance, and layers rolling usage windows
/// and per-organisation spend limits on top of it.
///
/// The credential comes from one of two places, in this order:
///
/// 1. **A key pasted into Settings**, kept encrypted on this Mac. It wins, for
///    the same reason it does for OpenCode Go: somebody who typed a key meant
///    that one, and a stale login left behind by the CLI should not quietly
///    override a deliberate choice.
/// 2. **What `cmd auth login` saved**, in `~/.commandcode/auth.json` — a plain
///    JSON object carrying `apiKey` alongside `userId`, `userName`, `keyName`
///    and `authenticatedAt`, written owner-only.
///
/// The CLI also honours a `COMMAND_CODE_API_KEY` environment variable. That is
/// deliberately **not** read here: Pulse is a launched app and does not inherit
/// the user's shell environment, so looking would find nothing on the machines
/// where it is set and would only add a way to be confusing about it.
///
/// ## The route
///
/// Four undocumented account routes on `https://api.commandcode.ai`, each
/// carrying `Authorization: Bearer <apiKey>` — the same four the CLI's own
/// `/usage` overlay reads, in the same order:
///
/// - `GET /alpha/whoami?limits=1` — the organisation id the other three are
///   scoped by, and the org's spend limits.
/// - `GET /alpha/billing/credits` — the remaining credit, split into monthly,
///   purchased and free, plus the rolling window limits.
/// - `GET /alpha/billing/subscriptions` — the plan and the billing period.
/// - `GET /alpha/usage/summary?since=<period start>` — what has been spent
///   inside that period.
///
/// None of this is documented by the vendor; it can change without notice,
/// exactly like the undocumented routes the other agents here are read from.
///
/// **What is not done:** the CLI carries a hard-coded table of monthly credit
/// allowances per plan id and prefers it as the denominator when a subscription
/// is active. Pulse does not use it. A number that lives in a client rather
/// than in the reply is not something the provider reported, and building a
/// percentage on it would be exactly the invention this app does not make. The
/// pool used here is what the account actually said: the credit still there
/// plus the money already spent in this period — which is the CLI's own
/// fallback whenever it has no plan entry to reach for.
struct CommandCodeUsageService: Sendable {
    /// The key the user entered, read by the caller so this stays free of both
    /// UI and storage concerns.
    let enteredKey: String?

    private static let host = "api.commandcode.ai"

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) ?? Self.storedKey() else {
            return .unavailable(.commandCode, reason: .apiKeyMissing)
        }

        // `whoami` first, and alone: it is the cheapest call, it is what says
        // whether the key is any good, and the organisation id it returns is
        // what scopes the other three. Failing here ends the fetch rather than
        // firing three more requests with a credential already known to be bad.
        let whoami: Whoami
        switch await Self.get(
            Whoami.self,
            path: "/alpha/whoami",
            items: [URLQueryItem(name: "limits", value: "1")],
            key: key
        ) {
        case .reply(let value): whoami = value
        case .failed(let reason): return .unavailable(.commandCode, reason: reason)
        }

        let org = whoami.org?.id
        // Independent of each other, so they run side by side.
        async let creditsCall = Self.get(
            CreditsReply.self, path: "/alpha/billing/credits", items: Self.org(org), key: key
        )
        async let subscriptionCall = Self.get(
            SubscriptionReply.self, path: "/alpha/billing/subscriptions", items: Self.org(org), key: key
        )
        let (creditsFetch, subscriptionFetch) = await (creditsCall, subscriptionCall)

        // The credit pool is the reading. Losing it is losing the answer, so
        // its failure is reported rather than papered over with the windows
        // that happen to have arrived.
        let credits: CreditsReply
        switch creditsFetch {
        case .reply(let value): credits = value
        case .failed(let reason): return .unavailable(.commandCode, reason: reason)
        }

        // A subscription this account has not got is not a failure — a
        // pay-as-you-go balance is a complete answer — so this one is allowed
        // to come back empty and the billing period simply goes unstated.
        let subscription = subscriptionFetch.value

        // The period start is passed through exactly as it arrived: it is a
        // query parameter to the service that produced it, not a date this
        // side has any business reformatting.
        var summaryItems = Self.org(org)
        if let since = subscription?.data?.currentPeriodStart?.query {
            summaryItems.append(URLQueryItem(name: "since", value: since))
        }
        let summary = await Self.get(
            SummaryReply.self, path: "/alpha/usage/summary", items: summaryItems, key: key
        ).value

        let reading = Reading(
            whoami: whoami, credits: credits, subscription: subscription, summary: summary
        )
        let windows = Self.windows(from: reading)
        guard !windows.isEmpty else {
            return .unavailable(.commandCode, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(.commandCode),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: Self.planName(subscription?.data?.planId ?? credits.credits?.planId),
            creditBalance: Self.balance(credits)
        )
    }

    /// The key `cmd auth login` wrote.
    ///
    /// Only the production file. The CLI writes `auth.staging.json` and
    /// `auth.local.json` when it is pointed at the vendor's own staging or a
    /// developer's laptop, and neither is a credential for the service Pulse
    /// reports on.
    static func storedKey() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".commandcode/auth.json")

        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let key = root["apiKey"] as? String,
            !key.isEmpty
        else { return nil }

        return key
    }

    // MARK: - Requests

    private static func org(_ id: String?) -> [URLQueryItem] {
        id.map { [URLQueryItem(name: "orgId", value: $0)] } ?? []
    }

    /// One call's outcome. Not `Result`: its failure has to be an `Error`, and
    /// `Unavailability` is deliberately a plain description of what to tell the
    /// user rather than something thrown.
    private enum Fetched<Reply> {
        case reply(Reply)
        case failed(ProviderUsage.Unavailability)

        /// For the two calls whose absence is survivable.
        var value: Reply? {
            if case .reply(let value) = self { return value }
            return nil
        }
    }

    private static func get<Reply: Decodable>(
        _ type: Reply.Type,
        path: String,
        items: [URLQueryItem],
        key: String
    ) async -> Fetched<Reply> {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !items.isEmpty { components.queryItems = items }

        guard let url = components.url else { return .failed(.unreadableReply) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failed(.unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        // Not `.signInRequired`: that message names Codex, and a message
        // naming the wrong provider is the trap this file's neighbours were
        // fixed for once already.
        case 401, 403: return .failed(.apiKeyRefused)
        case 429: return .failed(.rateLimited)
        default: return .failed(.serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .failed(.unreadableReply)
        }
        return .reply(reply)
    }

    // MARK: - Reading the replies

    /// The four replies of one pass, so the mapping below can be driven from
    /// captured JSON without a network.
    struct Reading {
        let whoami: Whoami?
        let credits: CreditsReply?
        let subscription: SubscriptionReply?
        let summary: SummaryReply?
    }

    struct Whoami: Decodable {
        struct Org: Decodable {
            let id: String?
            let login: String?
        }

        /// One organisation spend limit. `spent` and `limit` are US dollars,
        /// and `exceeded` is the account's own verdict rather than a
        /// comparison made here.
        struct SpendLimit: Decodable {
            /// `"model"` when the limit applies to one model; anything else is
            /// the organisation as a whole.
            let scope: String?
            let model: String?
            let modelLabel: String?
            let spent: Double?
            let limit: Double?
            let exceeded: Bool?
            /// `daily`, `weekly`, `monthly` or `total`.
            let resetInterval: String?
            let resetAt: String?
        }

        let org: Org?
        let orgLimits: [SpendLimit]?
    }

    struct CreditsReply: Decodable {
        /// **What is left, not what is gone.** Three separate pots, all in US
        /// dollars, which is why they are added rather than compared.
        struct Credits: Decodable {
            let planId: String?
            let monthlyCredits: Double?
            let purchasedCredits: Double?
            let freeCredits: Double?
        }

        /// A rolling window. `used` and `cap` are dollars, and `resetAt` is
        /// **epoch milliseconds** — the CLI compares it against `Date.now()`
        /// directly rather than parsing it.
        struct Window: Decodable {
            let used: Double?
            let cap: Double?
            let resetAt: Double?
        }

        /// `limited` is the account's own statement that these windows are in
        /// force. The CLI draws the section only when it is set, and a cap
        /// reported for an account that is not window-limited is not a limit
        /// anybody is being held to — so it is not shown as one here either.
        struct WindowLimits: Decodable {
            let limited: Bool?
            let fiveHour: Window?
            let weekly: Window?
        }

        let credits: Credits?
        let windowLimits: WindowLimits?
    }

    /// The one reply that nests: the subscription arrives under `data`, where
    /// the other three put their fields at the top level.
    struct SubscriptionReply: Decodable {
        struct Subscription: Decodable {
            let planId: String?
            /// `"active"` when the plan is running. Anything else is a plan
            /// that is not currently paying for anything.
            let status: String?
            let currentPeriodStart: Stamp?
            let currentPeriodEnd: Stamp?
        }

        let data: Subscription?
    }

    struct SummaryReply: Decodable {
        /// US dollars spent inside the period asked for.
        let totalCost: Double?
        let totalCount: Double?
    }

    /// A billing-period boundary, which the reply may spell either as a date
    /// string or as an epoch number.
    ///
    /// The CLI hands both straight to JavaScript's `Date`, which takes either
    /// without saying which it got, so neither form can be ruled out from the
    /// client alone. Both are accepted, and the text that arrived is kept so
    /// the period start can be handed back to the service verbatim.
    struct Stamp: Decodable, Equatable {
        let query: String
        let date: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let text = try? container.decode(String.self) {
                query = text
                date = CommandCodeUsageService.date(from: text)
                return
            }

            let number = try container.decode(Double.self)
            // Seconds and milliseconds are told apart by magnitude at 1e11, the
            // same boundary and the same reasoning `VolcengineUsageService`
            // uses: 1e11 seconds is the year 5138 and 1e11 milliseconds is
            // 1973, so nothing real is anywhere near it.
            date = Date(timeIntervalSince1970: abs(number) > 100_000_000_000 ? number / 1_000 : number)
            // Handed back to the service as it arrived, so a whole number does
            // not acquire a decimal point on the way. `Int64(_:)` traps rather
            // than saturating, so a value that could not be one is left as the
            // double it is instead.
            let whole = number == number.rounded() && abs(number) < 9e18
            query = whole ? String(Int64(number)) : String(number)
        }
    }

    // MARK: - Mapping

    /// Internal so the mapping can be driven against captured replies: every
    /// field name here is undocumented, and the credit pool below is the whole
    /// feature.
    ///
    /// Shortest window first, which is the order the other providers' limits
    /// arrive in and the order they matter in — the one about to bite leads.
    ///
    /// **Ties keep the order they were built in.** `sorted(by:)` is not a
    /// stable sort, and this provider produces equal lengths as a matter of
    /// course: a weekly rolling limit beside a weekly org limit, a monthly org
    /// limit beside a billing period that happens to be thirty days. Left to
    /// `sorted` those rows could swap between one refresh and the next, which
    /// is the shuffling `headlineWindow`'s own tie rule exists to avoid.
    static func windows(from reading: Reading) -> [UsageWindow] {
        let built = rollingWindows(reading.credits)
            + orgWindows(reading.whoami)
            + [creditWindow(reading)].compactMap { $0 }

        return built.enumerated()
            .sorted { ($0.element.windowSeconds, $0.offset) < ($1.element.windowSeconds, $1.offset) }
            .map(\.element)
    }

    /// The two rolling limits, when the account says it is subject to them.
    ///
    /// `reportsLength` is true because the reply *names* the lengths: the
    /// fields are `fiveHour` and `weekly`, which is a statement of five hours
    /// and of a week in the same way OpenCode Go's are. Whether either window
    /// rolls rather than sitting on a fixed boundary has not been established
    /// from a live account; if a capture ever shows it does, this is the flag
    /// that has to change, exactly as it did for Kimi's rolling week.
    private static func rollingWindows(_ reply: CreditsReply?) -> [UsageWindow] {
        guard let limits = reply?.windowLimits, limits.limited == true else { return [] }

        return [
            rolling(limits.fiveHour, id: "five-hour", kind: .fiveHour, seconds: 5 * 3_600),
            rolling(limits.weekly, id: "weekly", kind: .weekly, seconds: 7 * 86_400),
        ].compactMap { $0 }
    }

    private static func rolling(
        _ window: CreditsReply.Window?,
        id: String,
        kind: UsageWindow.Kind,
        seconds: Int
    ) -> UsageWindow? {
        guard
            let window,
            let cap = window.cap,
            cap > 0,
            let used = window.used
        else { return nil }

        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(used / cap, 0), 1),
            windowSeconds: seconds,
            // Milliseconds, not seconds: the CLI subtracts this from
            // `Date.now()` to say how long is left.
            resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
            isExhausted: used >= cap
        )
    }

    /// The organisation's spend limits, which are money rather than tokens and
    /// arrive already counted as **spent** — no inversion here.
    ///
    /// A limit of zero or less is not a limit with room in it: the account
    /// treats it as reached, and so does this. `exceeded` is the account's own
    /// verdict and outranks the arithmetic, which is the same rule every other
    /// provider's spent flag follows.
    private static func orgWindows(_ whoami: Whoami?) -> [UsageWindow] {
        (whoami?.orgLimits ?? []).enumerated().compactMap { index, limit -> UsageWindow? in
            guard let ceiling = limit.limit, let spent = limit.spent else { return nil }

            // A model-scoped limit names its model; anything else is the
            // organisation as a whole and is left unscoped, because a row
            // reading "Spend limit · Org-wide" says nothing the heading does
            // not already say.
            let named = (limit.modelLabel ?? limit.model)?
                .trimmingCharacters(in: .whitespaces)
            let scope = limit.scope == "model"
                ? named.flatMap { $0.isEmpty ? nil : $0 }
                : nil

            let (seconds, stated) = interval(limit.resetInterval)

            return UsageWindow(
                // **Unique within one reading.** An organisation can hold a
                // limit per model and an org-wide one at once, and duplicate
                // ids collapse rows in the card and leave a pin unresolvable,
                // so the position settles what the scope cannot.
                id: "org.\(index).\(limit.scope ?? "org")",
                kind: .spend,
                scope: scope,
                usedFraction: ceiling > 0 ? min(max(spent / ceiling, 0), 1) : 1,
                windowSeconds: seconds,
                resetsAt: limit.resetAt.flatMap(Self.date(from:)),
                reportsLength: stated,
                isExhausted: limit.exceeded == true || ceiling <= 0
            )
        }
    }

    /// A reset interval as a length, and whether that length is one the
    /// provider actually **stated**.
    ///
    /// A day and a week are exact. A month is 28 to 31 days and is stored as a
    /// flat 30 so the row sorts after the others — the same stand-in Cursor's
    /// billing cycle and Copilot's calendar month use, and it must not feed the
    /// window clock or the forecast. `total` is a lifetime cap with no period
    /// at all, so its seconds are nothing but a sort key that puts it last.
    private static func interval(_ name: String?) -> (seconds: Int, stated: Bool) {
        switch name {
        case "daily": (86_400, true)
        case "weekly": (7 * 86_400, true)
        case "monthly": (30 * 86_400, false)
        default: (365 * 86_400, false)
        }
    }

    /// The monthly row: the plan's grant while one is running, the purchased
    /// balance when none is.
    ///
    /// Two different questions, and answering the wrong one is the failure this
    /// splits to avoid. A plan's allowance resets every period and purchased
    /// credit does not, so adding the pots together draws a Pro subscriber who
    /// holds $200 of top-up and has burnt $28 of a $30 month at **12%** —
    /// silence, and then a wall.
    private static func creditWindow(_ reading: Reading) -> UsageWindow? {
        guard let credits = reading.credits?.credits else { return nil }

        return isOnAPlan(reading) ? planWindow(reading, credits) : poolWindow(reading, credits)
    }

    /// How much of this month's plan grant is gone.
    ///
    /// The grant is not reported by anything — see `CommandCodePlans`, which is
    /// where that compromise is argued and where it goes stale. What *is*
    /// reported is the remainder, so the subtraction is the account's own
    /// number and only the denominator is inferred. The row is scoped
    /// `estimated` so the card says which half that was.
    ///
    /// **A plan this build cannot size draws nothing.** Falling through to the
    /// pool below would answer the other question, and answer it wrongly; a
    /// zero would be worse still.
    private static func planWindow(_ reading: Reading, _ credits: CreditsReply.Credits) -> UsageWindow? {
        guard
            let grant = CommandCodePlans.monthlyCredits(forPlan: planID(reading)),
            grant > 0,
            // Absent is not zero. Without the remainder there is no numerator,
            // and a plan drawn as wholly spent is the loudest way to be wrong.
            let reported = credits.monthlyCredits
        else { return nil }

        let remaining = min(max(reported, 0), grant)
        let period = billingPeriod(reading)

        return UsageWindow(
            id: "monthly",
            kind: .monthly,
            scope: .localized("estimated"),
            usedFraction: (grant - remaining) / grant,
            windowSeconds: period.seconds ?? 30 * 86_400,
            resetsAt: period.end,
            reportsLength: period.seconds != nil,
            // The remainder is the account's own statement of what is left, and
            // nothing left is spent whatever the percentage rounds to.
            isExhausted: reported <= 0
        )
    }

    /// What an account with no plan has bought, as a spend limit.
    ///
    /// Both halves are reported here: what is left arrives directly, what is
    /// gone arrives from the summary, and their sum is the money this period
    /// started with. Where either half is missing there is no denominator the
    /// provider gave, and so no window — a percentage cannot be built out of
    /// one of the two numbers and a guess at the other.
    private static func poolWindow(_ reading: Reading, _ credits: CreditsReply.Credits) -> UsageWindow? {
        let remaining = max(0, credits.monthlyCredits ?? 0)
            + max(0, credits.purchasedCredits ?? 0)
            + max(0, credits.freeCredits ?? 0)
        let spent = max(0, reading.summary?.totalCost ?? 0)
        let pool = remaining + spent
        // Nothing left and nothing spent is an account that has said nothing
        // about a pool at all, which is not the same as one that is empty.
        guard pool > 0 else { return nil }

        let period = billingPeriod(reading)

        return UsageWindow(
            id: "credits",
            kind: .spend,
            scope: nil,
            usedFraction: min(max(spent / pool, 0), 1),
            windowSeconds: period.seconds ?? 30 * 86_400,
            resetsAt: period.end,
            reportsLength: period.seconds != nil,
            isExhausted: remaining <= 0
        )
    }

    /// The billing period, and a length only where the reply gave both ends of
    /// it. Otherwise the month is a sort key and nothing divides by it.
    private static func billingPeriod(_ reading: Reading) -> (end: Date?, seconds: Int?) {
        let period = reading.subscription?.data
        let start = period?.currentPeriodStart?.date
        let end = period?.currentPeriodEnd?.date
        let seconds = start.flatMap { start in end.map { $0.timeIntervalSince(start) } }
            .flatMap { $0 > 0 ? Int($0) : nil }
        return (end, seconds)
    }

    /// The plan this account is on, from whichever reply named it.
    ///
    /// `credits` carries a `planId` of its own, and it is the one that survives
    /// the subscription lookup failing — which is a real state, because that
    /// call is allowed to come back empty rather than sink the whole reading.
    static func planID(_ reading: Reading) -> String? {
        let id = reading.subscription?.data?.planId ?? reading.credits?.credits?.planId
        return id?.isEmpty == false ? id : nil
    }

    /// Whether a plan is paying for this account right now.
    ///
    /// `"active"` is the CLI's own test, and anything else — cancelled, past
    /// due, trialing, a plan that lapsed — is an account back on what it has
    /// bought, which is a pool this *can* measure from reported numbers alone.
    static func isOnAPlan(_ reading: Reading) -> Bool {
        // The subscription lookup is allowed to fail without sinking the
        // reading, so its silence is not evidence of no plan — and treating it
        // as such would answer with the pooled balance, which is the wrong
        // question for a subscriber. `credits.planId` still names the plan.
        guard let status = reading.subscription?.data?.status else {
            return planID(reading) != nil
        }
        return status.lowercased() == "active"
    }

    /// `individual-pro` → "Individual Pro". The plan id is passed through
    /// tidied rather than mapped: the CLI's own table of plan names is a table
    /// in a client, so a tier added after this build would be blanked by it,
    /// and an unfamiliar name still beats none.
    static func planName(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }

        return id
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// What is left, in the dollars the service prices in — hence a fixed
    /// currency code rather than the reader's own.
    static func balance(_ reply: CreditsReply?) -> String? {
        guard let credits = reply?.credits else { return nil }

        let amounts = [credits.monthlyCredits, credits.purchasedCredits, credits.freeCredits]
        guard amounts.contains(where: { $0 != nil }) else { return nil }

        return amounts.compactMap { $0 }.reduce(0) { $0 + max(0, $1) }
            .formatted(
                .currency(code: "USD")
                    .precision(.fractionLength(2))
                    .locale(LocalizationSource.locale)
            )
    }

    /// Built per call: `ISO8601DateFormatter` is not `Sendable`.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
