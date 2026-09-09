import Foundation

/// The MiniMax Coding Plan's limits, from its token-plan endpoint.
///
/// **Two providers, one service**, for the same reason as the GLM plan:
/// `api.minimax.io` and `api.minimaxi.com` are one company's international and
/// mainland storefronts, and a key for one is refused by the other. CodexBar
/// models this as a region switch inside one provider; each gets its own ring
/// here.
///
/// `GET {host}/v1/token_plan/remains` with the key as a bearer token, falling
/// back to the older coding-plan path. Undocumented, and it can change without
/// notice — the parsing follows CodexBar's, which is the only written account
/// of this reply that exists.
///
/// Three things about the reply are worth knowing before changing anything here.
///
/// - **It reports what is *left*, not what is gone.** `current_*_remaining_percent`
///   at 96 means 4% spent. Antigravity is the only other provider that does
///   this, and the inversion happens here so everything downstream stays in
///   terms of what has been used.
/// - **Numbers arrive as strings or as numbers, interchangeably.** The same
///   field is `"96"` in one reply and `75` in another, so every figure goes
///   through a reader that takes either.
/// - **Lanes exist that are not part of the subscription.** They come back with
///   status 3, zero counts and 100% remaining — a video lane on a plan with no
///   video. Read literally that is a ring pinned at 0% for a thing the account
///   cannot use, so they are left out.
struct MiniMaxUsageService: Sendable {
    let provider: Provider
    let enteredKey: String?

    /// The mainland service is a different host *and* a different account.
    private var apiHost: String {
        provider == .minimaxCN ? "https://api.minimaxi.com" : "https://api.minimax.io"
    }

    /// The current path first, then the one it replaced. A plan that answers
    /// 404 on the first is not a failure, it is an older account.
    private var endpoints: [URL] {
        [
            URL(string: "\(apiHost)/v1/token_plan/remains")!,
            URL(string: "\(apiHost)/v1/api/openplatform/coding_plan/remains")!,
        ]
    }

    func fetch() async -> ProviderUsage {
        guard let key = enteredKey.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(provider, reason: .apiKeyMissing)
        }

        // **Both paths are tried on any failure**, which is what the reference
        // does — an account on the older plan answers 401 on the current path,
        // not 404, so stopping at the first refusal would strand it. The
        // comment here used to claim only a 404 continued, which the code has
        // never done; it is load-bearing enough that someone would have
        // "fixed" the code to match and broken that fallback.
        //
        // The **first** reason is kept, not the last: a `.apiKeyRefused` from
        // the current path is what the user can act on, and it should not be
        // masked by a `.serverError` from a path their plan does not use.
        var firstProblem: ProviderUsage.Unavailability?
        for endpoint in endpoints {
            switch await attempt(endpoint, key: key) {
            case .success(let usage): return usage
            case .notFound: continue
            case .failed(let reason): firstProblem = firstProblem ?? reason
            }
        }
        return .unavailable(provider, reason: firstProblem ?? .unreachable)
    }

    private enum Attempt {
        case success(ProviderUsage)
        case notFound
        case failed(ProviderUsage.Unavailability)
    }

    private func attempt(_ endpoint: URL, key: String) async -> Attempt {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failed(.unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 404: return .notFound
        case 401, 403: return .failed(.apiKeyRefused)
        case 429: return .failed(.rateLimited)
        default: return .failed(.serverError)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(.unreadableReply)
        }

        // The service's own verdict, which is not the HTTP status: a refused
        // key comes back as a perfectly good 200 with a non-zero status here.
        //
        // **Not every non-zero status is a bad key**, and saying so sends the
        // user to check a credential that is fine. 1004 is the credential one;
        // the rest are the service having a bad day.
        let base = root["base_resp"] as? [String: Any]
        let status = Self.number(base?["status_code"]) ?? 0
        if status != 0 {
            let said = (base?["status_msg"] as? String)?.lowercased() ?? ""
            let credential = status == 1004
                || ["token", "auth", "login", "cookie", "credential"].contains(where: said.contains)
            return .failed(credential ? .apiKeyRefused : .serverError)
        }

        // **The payload is not always wrapped.** Some replies put `data` at the
        // root instead, and the reference decoder takes either — most of its own
        // captured replies are the unwrapped shape. Reading only `data` reported
        // a perfectly good account as "no limits reported".
        let payload = (root["data"] as? [String: Any]) ?? root
        let windows = Self.windows(from: payload, provider: provider)
        guard !windows.isEmpty else { return .failed(.noLimitsReported) }

        return .success(ProviderUsage(
            account: AccountKey(provider),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: Self.first(payload, of: [
                "current_subscribe_title", "plan_name", "combo_title", "current_plan_title",
            ]),
            creditBalance: Self.balance(payload, of: [
                "points_balance", "point_balance", "credits_balance", "credit_balance", "balance",
            ])
        ))
    }

    // MARK: - Mapping

    /// Internal so the mapping can be driven against captured replies: the
    /// field names are undocumented and the inversion below is the whole
    /// feature.
    static func windows(from payload: [String: Any]?, provider: Provider) -> [UsageWindow] {
        let models = (payload?["model_remains"] as? [[String: Any]]) ?? []

        return models.enumerated().flatMap { index, model -> [UsageWindow] in
            let name = (model["model_name"] as? String)?
                .trimmingCharacters(in: .whitespaces).nilWhenEmpty
            // "general" is the plan itself rather than a model, so it is left
            // unscoped — a row reading "5-hour limit · general" says nothing.
            let scope = (name?.lowercased() == "general" ? nil : name)?.nilWhenEmpty

            // **The id has to be unique within one reading.** It is the identity
            // three `ForEach`es use and what a pinned window is matched on, so a
            // second nameless lane sharing "general" leaves rows undefined and a
            // pin unresolvable. The position settles it when the name cannot.
            let key = name ?? "lane\(index)"

            return [
                interval(model, scope: scope, key: key, provider: provider),
                weekly(model, scope: scope, key: key, provider: provider),
            ].compactMap { $0 }
        }
        .sorted { $0.windowSeconds < $1.windowSeconds }
    }

    /// The short window. Its length is measured from the timestamps rather
    /// than assumed: they are the only statement of it the reply makes, and a
    /// window with no length can be neither named nor sorted — so it is
    /// dropped rather than given an invented one.
    private static func interval(
        _ model: [String: Any],
        scope: String?,
        key: String,
        provider: Provider
    ) -> UsageWindow? {
        guard !isUnavailable(
            status: number(model["current_interval_status"]),
            total: number(model["current_interval_total_count"]),
            remainingPercent: number(model["current_interval_remaining_percent"])
        ) else { return nil }

        guard let used = spent(
                  percentRemaining: number(model["current_interval_remaining_percent"]),
                  total: number(model["current_interval_total_count"]),
                  left: number(model["current_interval_usage_count"])
              ),
              let start = number(model["start_time"]),
              let end = number(model["end_time"]),
              end > start
        else { return nil }

        // Sub-second intervals would floor to zero and read as "0-hour limit".
        let seconds = Int((end - start) / 1000)
        guard seconds > 0 else { return nil }
        return UsageWindow(
            id: "\(provider.rawValue).\(key).interval",
            kind: kind(forSeconds: seconds),
            scope: scope,
            usedFraction: used / 100,
            windowSeconds: seconds,
            resetsAt: Date(timeIntervalSince1970: end / 1000)
        )
    }

    /// The weekly window. Unlike the one above this one names its own length,
    /// so it survives a reply that omits the timestamps.
    private static func weekly(
        _ model: [String: Any],
        scope: String?,
        key: String,
        provider: Provider
    ) -> UsageWindow? {
        guard !isUnavailable(
            status: number(model["current_weekly_status"]),
            total: number(model["current_weekly_total_count"]),
            remainingPercent: number(model["current_weekly_remaining_percent"])
        ) else { return nil }

        guard let used = spent(
            percentRemaining: number(model["current_weekly_remaining_percent"]),
            total: number(model["current_weekly_total_count"]),
            left: number(model["current_weekly_usage_count"])
        ) else { return nil }

        return UsageWindow(
            id: "\(provider.rawValue).\(key).weekly",
            kind: .weekly,
            scope: scope,
            usedFraction: used / 100,
            windowSeconds: 7 * 86_400,
            resetsAt: number(model["weekly_end_time"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// A lane the schema has but this subscription does not.
    ///
    /// Status 3 with nothing issued and nothing spent is how the service says
    /// "not part of your plan" — a video lane on a plan with no video. Taken
    /// at face value it draws a ring pinned at 0% for something the account
    /// cannot use at all. The same shape covers a lane that is genuinely
    /// unlimited, which has no percentage worth showing either.
    private static func isUnavailable(status: Double?, total: Double?, remainingPercent: Double?) -> Bool {
        status == 3 && (total ?? 0) == 0 && (remainingPercent ?? 0) >= 100
    }

    /// How much of the lane is gone, 0...100, or nil when the reply says
    /// nothing usable about it.
    ///
    /// **Everything here is stated as what is *left*.** A percentage of 96 is
    /// 4 spent — and the counts are the same way round despite their name:
    /// `current_interval_usage_count` is the **remaining** quota, not the used
    /// one. The reference implementation says so in as many words, and reading
    /// it as a spend inverts every figure on the card.
    ///
    /// The percentage is preferred because it is what the service intends to
    /// be read; the counts are the fallback, and are the only thing the older
    /// endpoint returns.
    private static func spent(percentRemaining: Double?, total: Double?, left: Double?) -> Double? {
        if let percentRemaining { return min(max(100 - percentRemaining, 0), 100) }
        guard let total, total > 0, let left else { return nil }
        return min(max((total - left) / total * 100, 0), 100)
    }

    private static func kind(forSeconds seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 5 * 3600: .fiveHour
        case 7 * 86_400: .weekly
        case 30 * 86_400: .monthly
        default: .other(seconds: seconds)
        }
    }

    /// The first of several names that carries a usable string. Which one a
    /// reply uses varies by account, and reading only one leaves the card
    /// blank for everybody else.
    private static func first(_ payload: [String: Any]?, of keys: [String]) -> String? {
        for key in keys {
            if let text = (payload?[key] as? String)?.trimmingCharacters(in: .whitespaces),
               !text.isEmpty { return text }
        }
        return nil
    }

    private static func balance(_ payload: [String: Any]?, of keys: [String]) -> String? {
        guard let points = keys.lazy.compactMap({ number(payload?[$0]) }).first(where: { $0 > 0 })
        else { return nil }
        let count = Int(points).formatted(.number.locale(LocalizationSource.locale))
        return .localized("\("\(count)") points")
    }

    /// **Every figure in this reply can be a string or a number**, sometimes
    /// the same field in two different replies, so nothing here may assume
    /// which. Reading only one shape would blank a window for the accounts
    /// that happen to get the other.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
