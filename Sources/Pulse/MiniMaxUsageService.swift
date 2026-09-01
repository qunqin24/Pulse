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

        var lastProblem = ProviderUsage.Unavailability.unreachable
        for endpoint in endpoints {
            switch await attempt(endpoint, key: key) {
            case .success(let usage): return usage
            // Only a 404 is worth trying the other path for: anything else is
            // an answer about this account rather than about this URL.
            case .notFound: continue
            case .failed(let reason): lastProblem = reason
            }
        }
        return .unavailable(provider, reason: lastProblem)
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
        let status = Self.number((root["base_resp"] as? [String: Any])?["status_code"]) ?? 0
        guard status == 0 else { return .failed(.apiKeyRefused) }

        let payload = root["data"] as? [String: Any]
        let windows = Self.windows(from: payload, provider: provider)
        guard !windows.isEmpty else { return .failed(.noLimitsReported) }

        return .success(ProviderUsage(
            account: AccountKey(provider),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: (payload?["current_subscribe_title"] as? String)?
                .trimmingCharacters(in: .whitespaces)
                .nilWhenEmpty,
            creditBalance: Self.balance(payload?["points_balance"])
        ))
    }

    // MARK: - Mapping

    /// Internal so the mapping can be driven against captured replies: the
    /// field names are undocumented and the inversion below is the whole
    /// feature.
    static func windows(from payload: [String: Any]?, provider: Provider) -> [UsageWindow] {
        let models = (payload?["model_remains"] as? [[String: Any]]) ?? []

        return models.flatMap { model -> [UsageWindow] in
            let name = (model["model_name"] as? String)?.trimmingCharacters(in: .whitespaces)
            // "general" is the plan itself rather than a model, so it is left
            // unscoped — a row reading "5-hour limit · general" says nothing.
            let scope = (name?.lowercased() == "general" ? nil : name)?.nilWhenEmpty

            return [
                interval(model, scope: scope, name: name, provider: provider),
                weekly(model, scope: scope, name: name, provider: provider),
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
        name: String?,
        provider: Provider
    ) -> UsageWindow? {
        guard !isUnavailable(
            status: number(model["current_interval_status"]),
            total: number(model["current_interval_total_count"]),
            remainingPercent: number(model["current_interval_remaining_percent"])
        ) else { return nil }

        guard let remaining = number(model["current_interval_remaining_percent"]),
              let start = number(model["start_time"]),
              let end = number(model["end_time"]),
              end > start
        else { return nil }

        let seconds = Int((end - start) / 1000)
        return UsageWindow(
            id: "\(provider.rawValue).\(name ?? "general").interval",
            kind: kind(forSeconds: seconds),
            scope: scope,
            usedFraction: spent(remaining) / 100,
            windowSeconds: seconds,
            resetsAt: Date(timeIntervalSince1970: end / 1000)
        )
    }

    /// The weekly window. Unlike the one above this one names its own length,
    /// so it survives a reply that omits the timestamps.
    private static func weekly(
        _ model: [String: Any],
        scope: String?,
        name: String?,
        provider: Provider
    ) -> UsageWindow? {
        guard !isUnavailable(
            status: number(model["current_weekly_status"]),
            total: number(model["current_weekly_total_count"]),
            remainingPercent: number(model["current_weekly_remaining_percent"])
        ) else { return nil }

        guard let remaining = number(model["current_weekly_remaining_percent"]) else { return nil }

        return UsageWindow(
            id: "\(provider.rawValue).\(name ?? "general").weekly",
            kind: .weekly,
            scope: scope,
            usedFraction: spent(remaining) / 100,
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

    /// **The reply says what is left; everything downstream is in terms of
    /// what is gone.** 96 remaining is 4 spent.
    private static func spent(_ remaining: Double) -> Double {
        min(max(100 - remaining, 0), 100)
    }

    private static func kind(forSeconds seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 5 * 3600: .fiveHour
        case 7 * 86_400: .weekly
        case 30 * 86_400: .monthly
        default: .other(seconds: seconds)
        }
    }

    private static func balance(_ value: Any?) -> String? {
        guard let points = number(value), points > 0 else { return nil }
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
