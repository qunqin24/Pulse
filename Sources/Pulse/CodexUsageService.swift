import Foundation

/// Reads Codex's usage.
///
/// The main path is the one Codex's own client uses: take the OAuth
/// credentials Codex already stored in `~/.codex/auth.json` and ask
/// `chatgpt.com/backend-api/wham/usage`, which answers with the account-wide
/// windows and any per-model limits. It is a plain HTTPS call with nothing
/// left running, so it is quick, and it works even when the `codex` command
/// isn't somewhere we can find it.
///
/// Two things to keep in mind. The endpoint isn't public API — it is what the
/// CLI uses internally, and it can change without warning. And the stored
/// access token expires: Codex refreshes it while you are using Codex, but
/// nothing refreshes it on our behalf. So when the token is missing or
/// refused, this falls back to `codex app-server`, which is signed in on its
/// own terms and renews its credentials itself.
struct CodexUsageService: Sendable {
    /// Fallback for when the stored token is missing or no longer accepted.
    let server: CodexAppServer

    var authFile: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: ".codex/auth.json")

    var endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetch(source: UsageSource = .automatic) async -> ProviderUsage {
        if source == .tooling { return await fetchViaAppServer() }

        switch await fetchOverHTTP() {
        case .success(let usage):
            return usage
        case .needsFreshCredentials:
            // Pinned to the endpoint, so a dead token is reported rather than
            // quietly answered by the app server.
            return source == .endpoint
                ? .unavailable(.codex, reason: .signInRequired)
                : await fetchViaAppServer()
        case .failed(let reason):
            return .unavailable(.codex, reason: reason)
        }
    }

    // MARK: - The direct call

    private enum HTTPOutcome {
        case success(ProviderUsage)
        /// No usable token — worth asking the app server, which holds its own.
        case needsFreshCredentials
        case failed(ProviderUsage.Unavailability)
    }

    private func fetchOverHTTP() async -> HTTPOutcome {
        guard let credentials = loadCredentials() else { return .needsFreshCredentials }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // `URLSession` follows the system proxy settings, so on a machine
        // behind a VPN or proxy client this call rides that tunnel — which is
        // what you want, since the endpoint may only be reachable through it.
        // The cost is that a tunnel dropping a connection surfaces as a
        // request failure, so a stumble is retried before it becomes an error
        // in the UI.
        for attempt in 0...Self.retryLimit {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failed(.unreachable) }

                switch http.statusCode {
                case 200:
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return .failed(.unreadableReply)
                    }
                    return .success(Self.parseUsageResponse(root))
                case 401, 403:
                    // The stored token has aged out; the app server can renew it.
                    return .needsFreshCredentials
                case 429:
                    return .failed(.rateLimited)
                default:
                    return .failed(.serverError)
                }
            } catch {
                guard attempt < Self.retryLimit, Self.isWorthRetrying(error) else {
                    return .failed(.unreachable)
                }
                try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
            }
        }

        return .failed(.unreachable)
    }

    /// How many extra attempts a stumbling connection gets.
    private static let retryLimit = 2

    /// Whether an error looks like the connection tripping rather than
    /// something that will fail again the same way. A proxy or VPN dropping a
    /// connection shows up as `-1005`, which retrying usually clears.
    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        return [
            .networkConnectionLost,
            .timedOut,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed
        ].contains(urlError.code)
    }

    private struct Credentials {
        let accessToken: String
        let accountID: String
    }

    private func loadCredentials() -> Credentials? {
        guard
            let data = try? Data(contentsOf: authFile),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String,
            let account = tokens["account_id"] as? String
        else { return nil }

        return Credentials(accessToken: token, accountID: account)
    }

    /// The shape `wham/usage` returns.
    private static func parseUsageResponse(_ root: [String: Any]) -> ProviderUsage {
        var windows: [UsageWindow] = []

        // Account-wide limits, which the server leaves unnamed.
        let spendReached = (root["spend_control"] as? [String: Any])?["reached"] as? Bool ?? false

        if let limit = root["rate_limit"] as? [String: Any] {
            windows += Self.markingSpent(
                httpWindows(from: limit, idPrefix: "codex", scope: nil),
                // These flags describe the *group*, so they are pinned to the
                // window actually up against its limit rather than smeared
                // across every window in the group.
                if: Self.isGroupSpent(limit)
                    || root["rate_limit_reached_type"] != nil && !(root["rate_limit_reached_type"] is NSNull)
                    || spendReached
            )
        }

        // Then per-model limits, which it does name.
        for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let limit = extra["rate_limit"] as? [String: Any] else { continue }
            let label = extra["limit_name"] as? String
            let key = extra["metered_feature"] as? String ?? label ?? "extra"
            windows += Self.markingSpent(
                httpWindows(from: limit, idPrefix: key, scope: label),
                if: Self.isGroupSpent(limit)
            )
        }

        let credits = root["credits"] as? [String: Any]

        return ProviderUsage(
            provider: .codex,
            windows: windows,
            observedAt: Date(),
            state: windows.isEmpty ? .unavailable(.noLimitsReported) : .live,
            plan: (root["plan_type"] as? String).map(planName),
            creditBalance: (credits?["unlimited"] as? Bool == true)
                ? nil
                : credits?["balance"] as? String
        )
    }

    private static func httpWindows(
        from limit: [String: Any],
        idPrefix: String,
        scope: String?
    ) -> [UsageWindow] {
        // `primary_window` and `secondary_window` are not tied to particular
        // durations, and which windows exist depends on the plan — ChatGPT Pro
        // has no 5-hour limit, only the tiers below it do. On a plan without
        // one, the account-wide group reports its *weekly* window as primary
        // and has no secondary at all, while a per-model group uses primary
        // for its 5-hour window. So a window's kind comes from its duration,
        // never from which slot it arrived in, and the UI draws however many
        // come back rather than expecting a fixed pair.
        ["primary_window", "secondary_window"].compactMap { slot in
            guard
                let node = limit[slot] as? [String: Any],
                let percent = number(node["used_percent"])
            else { return nil }

            let seconds = number(node["limit_window_seconds"]).map { Int($0) }
            let resets = number(node["reset_at"]).map { Date(timeIntervalSince1970: $0) }

            return UsageWindow(
                id: "\(idPrefix).\(slot)",
                kind: seconds.map { kind(seconds: $0) } ?? .other(seconds: 0),
                scope: scope,
                usedFraction: percent / 100,
                windowSeconds: seconds ?? 0,
                resetsAt: resets
            )
        }
    }

    // MARK: - The fallback

    private func fetchViaAppServer() async -> ProviderUsage {
        do {
            let data = try await server.rateLimits()
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable(.codex, reason: .unreadableReply)
            }
            return Self.parseAppServerResponse(result)
        } catch CodexAppServer.Failure.executableNotFound {
            // Neither route is open: no usable token, and no CLI to ask.
            return .unavailable(.codex, reason: .signInRequired)
        } catch CodexAppServer.Failure.startFailed {
            return .unavailable(.codex, reason: .codexServerFailed)
        } catch CodexAppServer.Failure.timedOut {
            return .unavailable(.codex, reason: .unreachable)
        } catch CodexAppServer.Failure.server(let message) {
            let text = message.lowercased()
            let isAuth = ["auth", "login", "sign in", "unauthor", "credential"]
                .contains { text.contains($0) }
            return .unavailable(.codex, reason: isAuth ? .signInRequired : .serverError)
        } catch {
            return .unavailable(.codex, reason: .serverError)
        }
    }

    /// The shape `account/rateLimits/read` returns, which names its fields
    /// differently from the HTTP endpoint.
    private static func parseAppServerResponse(_ result: [String: Any]) -> ProviderUsage {
        let groups = result["rateLimitsByLimitId"] as? [String: [String: Any]]
            ?? (result["rateLimits"] as? [String: Any]).map { ["codex": $0] }
            ?? [:]

        // Unnamed account-wide group first, then named per-model ones in a
        // stable order, so rows don't jump around between refreshes.
        let ordered = groups.sorted { lhs, rhs in
            let lhsNamed = (lhs.value["limitName"] as? String) != nil
            let rhsNamed = (rhs.value["limitName"] as? String) != nil
            if lhsNamed != rhsNamed { return !lhsNamed }
            return lhs.key < rhs.key
        }

        var windows: [UsageWindow] = []
        var plan: String?
        var credits: String?

        for (key, group) in ordered {
            let scope = group["limitName"] as? String

            windows += ["primary", "secondary"].compactMap { slot -> UsageWindow? in
                guard
                    let node = group[slot] as? [String: Any],
                    let percent = number(node["usedPercent"])
                else { return nil }

                let minutes = number(node["windowDurationMins"]).map { Int($0) }
                let resets = number(node["resetsAt"]).map { Date(timeIntervalSince1970: $0) }

                return UsageWindow(
                    id: "\(key).\(slot)",
                    kind: minutes.map { kind(seconds: $0 * 60) } ?? .other(seconds: 0),
                    scope: scope,
                    usedFraction: percent / 100,
                    windowSeconds: (minutes ?? 0) * 60,
                    resetsAt: resets
                )
            }

            windows = Self.markingSpent(windows, if: group["spendControlReached"] as? Bool == true
                || (group["rateLimitReachedType"].map { !($0 is NSNull) } ?? false))

            plan = plan ?? group["planType"] as? String
            if credits == nil, let node = group["credits"] as? [String: Any] {
                credits = (node["unlimited"] as? Bool == true) ? nil : node["balance"] as? String
            }
        }

        return ProviderUsage(
            provider: .codex,
            windows: windows,
            observedAt: Date(),
            state: windows.isEmpty ? .unavailable(.noLimitsReported) : .live,
            plan: plan.map(planName),
            creditBalance: credits
        )
    }

    // MARK: - Shared

    private static func isGroupSpent(_ limit: [String: Any]) -> Bool {
        if limit["limit_reached"] as? Bool == true { return true }
        if limit["allowed"] as? Bool == false { return true }
        return false
    }

    /// Marks the group's most-used window as spent.
    ///
    /// Codex reports "limit reached" for a whole group, but a group can hold
    /// both a 5-hour and a weekly window and only one of them is the reason.
    /// Flagging the fullest one keeps the claim as precise as the data allows.
    private static func markingSpent(_ windows: [UsageWindow], if spent: Bool) -> [UsageWindow] {
        guard spent,
              let fullest = windows.max(by: { $0.usedFraction < $1.usedFraction })
        else { return windows }

        return windows.map { window in
            guard window.id == fullest.id else { return window }
            var marked = window
            marked.isExhausted = true
            return marked
        }
    }

    private static func kind(seconds: Int) -> UsageWindow.Kind {
        switch seconds {
        case 18_000: .fiveHour
        case 604_800: .weekly
        default: .other(seconds: seconds)
        }
    }

    /// What the plan is actually called, from the identifier Codex reports.
    ///
    /// The API answers with an internal tier name — `prolite`, `plus` — which
    /// is not the name on the plan anywhere the user has seen it. Anything
    /// unrecognised is passed through as-is rather than blanked: a name we
    /// don't know is still better than no name, and it is the only clue left
    /// if OpenAI adds a tier.
    static func planName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "free": "Free"
        case "go": "Go"
        case "plus": "Plus"
        case "pro": "Pro"
        // Reported for the 5× Pro tier.
        case "prolite": "Pro 5x"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case "edu": "Edu"
        default: raw
        }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }
}
