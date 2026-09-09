import Foundation

/// Reads Claude Code's usage.
///
/// The main route is the account's own usage endpoint, reached with the OAuth
/// credentials Claude Code already stored in the login keychain. It answers
/// with every limit at once — the 5-hour session window, the weekly window,
/// and any per-model weekly limits — and it answers whenever asked, rather
/// than only while a session happens to be running.
///
/// When there is no usable token, it falls back to whatever `StatusLineHook`
/// last captured. That route is officially documented and needs no
/// credentials, but it is a push: Claude Code only hands over figures after a
/// response, so between sessions the reading ages. Hence `.stale`, rather than
/// passing an old number off as current.
///
/// The endpoint isn't public API — it is what Claude Code itself calls — so it
/// can change without notice, which is the other reason the status line route
/// is kept rather than deleted.
struct ClaudeCodeUsageService: Sendable {
    var keychainService = "Claude Code-credentials"

    /// Where the CLI keeps credentials when it isn't using the keychain.
    var credentialsFile: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: ".claude/.credentials.json")

    var endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var cacheFile: URL = StatusLineHook.cacheFile

    /// Past this, a status line reading is labelled as old rather than live. A
    /// session refreshes it after every response, so anything beyond a few
    /// minutes means the session has gone quiet.
    var freshFor: TimeInterval = 10 * 60

    /// An account Pulse signed in to itself, read with the token it holds for
    /// it. There is no route to choose here: the status-line fallback and the
    /// stored CLI login both belong to whichever account the CLI is signed in
    /// to, which is not this one.
    func fetch(account: AccountKey, token: String) async -> ProviderUsage {
        switch await fetchOverHTTP(token: token, for: account) {
        case .success(let usage): return usage
        case .needsFreshCredentials: return .unavailable(account, reason: .claudeLoginExpired)
        case .failed(let reason): return .unavailable(account, reason: reason)
        }
    }

    func fetch(source: UsageSource = .automatic) async -> ProviderUsage {
        switch source {
        case .tooling:
            // Pinned to the status line, so a missing reading is reported as
            // such rather than quietly answered from somewhere else.
            // Pinned here, the endpoint is never tried — so a stored token
            // says nothing about whether it still works, and calling it
            // expired would be a guess about something this route never asked.
            return readCapturedUsage()
                ?? .unavailable(.claudeCode, reason: StatusLineHook.isInstalled ? .awaitingResponse : .notConnected)

        case .desktopApp:
            // Pinned here for the same reason as the other two: a failure is
            // reported rather than quietly answered from somewhere else. It is
            // never reached from `.automatic` — see `UsageSource.desktopApp`.
            return await ClaudeDesktopSession.usage(for: AccountKey(.claudeCode))

        case .endpoint:
            guard let token = loadAccessToken() else {
                return .unavailable(.claudeCode, reason: .claudeSignInRequired)
            }
            switch await fetchOverHTTP(token: token, for: AccountKey(.claudeCode)) {
            case .success(let usage): return usage
            // A token was found and refused, which is not the same thing as
            // never having signed in.
            case .needsFreshCredentials: return .unavailable(.claudeCode, reason: .claudeLoginExpired)
            case .failed(let reason): return .unavailable(.claudeCode, reason: reason)
            }

        case .automatic:
            // Read once. Both answers come out of the same blob: an expired
            // token is still evidence of a login, and asking twice means
            // spawning `security` twice a pass — which is the thing the read
            // was pulled out of the loop to stop.
            let credentials = storedCredentials()
            let hadCredentials = credentials != nil
            if let token = credentials.flatMap(Self.unexpiredAccessToken) {
                switch await fetchOverHTTP(token: token, for: AccountKey(.claudeCode)) {
                case .success(let usage):
                    return usage
                case .needsFreshCredentials:
                    break // fall through to the desktop session, then the status line
                case .failed(let reason):
                    // A network stumble shouldn't hide a perfectly good
                    // captured reading, so prefer that and keep the error in
                    // reserve.
                    return readCapturedUsage() ?? .unavailable(.claudeCode, reason: reason)
                }
            }

            // **Before the status line, not after it.** That route is a push:
            // it only moves while a session runs, and a Mac driven through the
            // desktop app never renders a status line at all — so what it
            // holds can be a day old and still pass, which is exactly how a
            // panel came to sit on yesterday's figures with a refresh button
            // that appeared to do nothing. A live reading outranks a captured
            // one; the capture keeps its turn when there is no live reading to
            // be had. Silent only — see `usageIfAlreadyPermitted`.
            if let desktop = await ClaudeDesktopSession.usageIfAlreadyPermitted(for: AccountKey(.claudeCode)) {
                return desktop
            }

            return readCapturedUsage()
                ?? .unavailable(.claudeCode, reason: capturedUsageProblem(hadCredentials: hadCredentials))
        }
    }

    // MARK: - The usage endpoint

    private enum HTTPOutcome {
        case success(ProviderUsage)
        case needsFreshCredentials
        case failed(ProviderUsage.Unavailability)
    }

    private func fetchOverHTTP(token: String, for account: AccountKey) async -> HTTPOutcome {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli (external, cli)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for attempt in 0...Self.retryLimit {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .failed(.unreachable) }

                switch http.statusCode {
                case 200:
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return .failed(.unreadableReply)
                    }
                    // **Whatever is already known, and no waiting.** Awaiting
                    // the profile call held the usage reading for as long as
                    // that request took — measured at 3.2s against a slow
                    // reply, on every launch and once per account every six
                    // hours. The figures had already arrived and parsed. So
                    // the plan is taken from the cache, and a miss is filled
                    // in for the next pass rather than paid for on this one.
                    let plan = await ClaudePlan.shared.cached(for: account)
                    await ClaudePlan.shared.refreshIfStale(for: account, token: token)
                    return .success(Self.parse(root, for: account, plan: plan))
                case 401, 403:
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

    private static let retryLimit = 2

    /// A proxy or VPN dropping a connection shows up as `-1005`, which
    /// retrying usually clears. Same point as in `CodexUsageService`.
    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .networkConnectionLost, .timedOut, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed
        ].contains(urlError.code)
    }

    // MARK: - Credentials

    private func loadAccessToken() -> String? {
        storedCredentials().flatMap(Self.unexpiredAccessToken)
    }

    /// The blob as stored, expired or not.
    ///
    /// Kept apart from `loadAccessToken` because the two answer different
    /// questions: "is there a usable token" and "is this person signed in at
    /// all". Reading only the first cannot tell an expired login from no login,
    /// which is the whole distinction the card is trying to draw.
    private func storedCredentials() -> [String: Any]? {
        readKeychainCredentials() ?? readCredentialsFile()
    }

    /// The credentials blob Claude Code stores, or nil if it can't be read.
    ///
    /// Shelling out to `security` keeps this to the same access the CLI itself
    /// uses. Note the first read can raise a permission prompt; the process is
    /// short-lived and its failure is handled, so a refused prompt degrades to
    /// the status line route rather than hanging the panel.
    private func readKeychainCredentials() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func readCredentialsFile() -> [String: Any]? {
        guard let data = try? Data(contentsOf: credentialsFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func unexpiredAccessToken(_ credentials: [String: Any]) -> String? {
        guard
            let oauth = credentials["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { return nil }

        // Expiry is in milliseconds. Nothing here renews the token, so an
        // expired one counts as absent rather than being spent on a call that
        // can only come back 401.
        if let expiresAt = number(oauth["expiresAt"]),
           Date(timeIntervalSince1970: expiresAt / 1000) <= Date() {
            return nil
        }

        return token
    }

    // MARK: - The plan

    /// The plan's name, which the usage reply does not carry.
    ///
    /// **A second endpoint, and so a second request** — `GET /api/oauth/profile`,
    /// the same one the CLI uses to know whose account it is on. It is asked
    /// rarely rather than every pass: a subscription changes about as often as
    /// a person changes their mind about paying for one, while the refresh loop
    /// comes round every few minutes.
    ///
    /// Only the plan-shaped fields are read. The same reply carries the
    /// account's name, its email address and its organisation's identifiers,
    /// which are the user's and no use to Pulse — the same rule Antigravity's
    /// `GetUserStatus` call follows.
    actor ClaudePlan {
        static let shared = ClaudePlan()

        /// Long enough that this is a handful of requests a day, short enough
        /// that an upgrade shows up the same session.
        private static let freshFor: TimeInterval = 6 * 3600

        private var known: [String: (name: String?, at: Date)] = [:]
        /// Accounts with a request already out, so two passes cannot send two.
        private var asking: Set<String> = []

        /// What is known now. Never waits, never asks.
        func cached(for account: AccountKey) -> String? { known[account.id]?.name }

        /// Asks again when what is known has aged out, without anyone waiting
        /// for the answer.
        func refreshIfStale(for account: AccountKey, token: String) {
            if let seen = known[account.id], Date().timeIntervalSince(seen.at) < Self.freshFor {
                return
            }
            // Claimed before the request goes out, so a second pass arriving
            // while this one is in flight does not send another.
            guard !asking.contains(account.id) else { return }
            asking.insert(account.id)

            Task { [weak self] in
                guard let self else { return }
                let fetched = await self.fetch(token: token)
                await self.remember(fetched, for: account)
            }
        }

        private func remember(_ name: String?, for account: AccountKey) {
            // A failure is remembered too — the plan is a nicety and must never
            // cost the usage reading a retry every pass.
            known[account.id] = (name, Date())
            asking.remove(account.id)
        }

        private func fetch(token: String) async -> String? {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-cli (external, cli)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            // The one moment this can be asked: the desktop route needs to
            // know whose account the CLI is on, and by the time it asks, the
            // token that would answer has expired. See `ClaudeAccountIdentity`.
            ClaudeAccountIdentity.remember(ClaudeAccountIdentity.fingerprint(fromProfile: root))

            return planName(from: root)
        }

        /// The name on the plan, from the tier the account is rate limited at.
        ///
        /// `subscription_type` first where a reply carries it; otherwise
        /// `rate_limit_tier`, which is where the multiplier lives — a Max plan
        /// is sold as 5× or 20× and the two are different products, so the
        /// figure belongs in the name. Anything unfamiliar is passed through
        /// tidied rather than blanked: an unknown name still beats none, and
        /// it is the only clue left when a new tier appears.
        nonisolated func planName(from root: [String: Any]) -> String? {
            let organization = root["organization"] as? [String: Any]

            let tier = (organization?["rate_limit_tier"] as? String)?.lowercased()
            // The multiplier only ever lives on the tier, so it is read first
            // and kept whichever name wins: a Max 5x and a Max 20x are
            // different products, and a stated "max" that dropped the figure
            // would be the less useful of the two answers.
            let multiplier = tier.flatMap { t in ["20x", "5x"].first { t.hasSuffix("_" + $0) } }

            if let stated = (organization?["subscription_type"] as? String)
                ?? (root["subscription_type"] as? String) {
                let name = tidy(stated)
                return multiplier.map { "\(name) \($0)" } ?? name
            }

            guard let tier else {
                return (organization?["organization_type"] as? String).map(tidy)
            }
            let base: String = if tier.contains("max") {
                "Max"
            } else if tier.contains("team") {
                "Team"
            } else if tier.contains("enterprise") {
                "Enterprise"
            } else if tier.contains("pro") {
                "Pro"
            } else if tier.contains("free") {
                "Free"
            } else {
                tidy(tier)
            }
            return multiplier.map { "\(base) \($0)" } ?? base
        }

        /// `claude_max` reads as a field name; "Claude Max" reads as a plan.
        nonisolated private func tidy(_ raw: String) -> String {
            raw.split(whereSeparator: { $0 == "_" || $0 == "-" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    // MARK: - Parsing

    /// Internal rather than private because the desktop route answers with
    /// the very same shape — `limits[]` carrying `kind`/`percent`/`severity`/
    /// `resets_at`/`scope`, with the older top-level pair behind it — and two
    /// readers of one payload is two chances to disagree about what a window
    /// is. See `ClaudeDesktopSession`.
    static func parse(
        _ root: [String: Any],
        for account: AccountKey,
        plan: String? = nil
    ) -> ProviderUsage {
        // `limits` is the fuller answer: it carries per-model windows too,
        // which the top-level `five_hour`/`seven_day` fields don't.
        var windows = (root["limits"] as? [[String: Any]] ?? []).compactMap(window(fromLimit:))

        if windows.isEmpty {
            windows = [("five_hour", UsageWindow.Kind.fiveHour), ("seven_day", .weekly)]
                .compactMap { key, kind -> UsageWindow? in
                    guard
                        let node = root[key] as? [String: Any],
                        let percent = number(node["utilization"])
                    else { return nil }

                    return UsageWindow(
                        id: "claudeCode.\(key)",
                        kind: kind,
                        scope: nil,
                        usedFraction: percent / 100,
                        windowSeconds: kind == .fiveHour ? 5 * 3600 : 7 * 86_400,
                        resetsAt: (node["resets_at"] as? String).flatMap(date(fromISO8601:)),
                        isExhausted: isSpent(node)
                    )
                }
        }

        return ProviderUsage(
            account: account,
            windows: windows,
            observedAt: Date(),
            state: windows.isEmpty ? .unavailable(.noLimitsReported) : .live,
            plan: plan,
            creditBalance: nil
        )
    }

    private static func window(fromLimit limit: [String: Any]) -> UsageWindow? {
        guard
            let kindName = limit["kind"] as? String,
            let percent = number(limit["percent"])
        else { return nil }

        let kind: UsageWindow.Kind
        let seconds: Int
        switch kindName {
        case "session":
            kind = .fiveHour
            seconds = 5 * 3600
        case "weekly_all", "weekly_scoped":
            kind = .weekly
            seconds = 7 * 86_400
        default:
            return nil
        }

        // A scoped limit names the model it applies to; an unscoped one covers
        // the whole account.
        let scope = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String

        return UsageWindow(
            id: "claudeCode.\(kindName).\(scope ?? "all")",
            kind: kind,
            scope: scope,
            usedFraction: percent / 100,
            windowSeconds: seconds,
            resetsAt: (limit["resets_at"] as? String).flatMap(date(fromISO8601:)),
            isExhausted: isSpent(limit)
        )
    }

    /// Whether Claude Code says this limit is spent.
    ///
    /// `severity` is the provider's own judgement and only its vocabulary is
    /// documented loosely, so anything that isn't plainly fine is treated as
    /// spent rather than guessed at — an unknown value erring towards "you're
    /// blocked" is the safer way to be wrong. `locked_reason` is unambiguous.
    private static func isSpent(_ limit: [String: Any]) -> Bool {
        if limit["locked_reason"] != nil, !(limit["locked_reason"] is NSNull) { return true }

        guard let severity = (limit["severity"] as? String)?.lowercased() else { return false }
        return !["normal", "ok", "none", "healthy"].contains(severity)
    }

    private static func date(fromISO8601 text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    // MARK: - The status line fallback

    private func readCapturedUsage() -> ProviderUsage? {
        guard
            let data = try? Data(contentsOf: cacheFile),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = root["rate_limits"] as? [String: Any]
        else { return nil }

        let windows = Self.capturedWindows(from: limits)
        guard !windows.isEmpty else { return nil }

        let captured = (root["capturedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let age = captured.map { Date().timeIntervalSince($0) } ?? .infinity

        return ProviderUsage(
            account: AccountKey(.claudeCode),
            windows: windows,
            observedAt: captured,
            state: age <= freshFor ? .live : .stale,
            plan: nil,
            creditBalance: nil
        )
    }

    /// Why there is nothing to show, told apart properly.
    ///
    /// "Sign in to Claude Code" is wrong for someone who *is* signed in and
    /// whose saved token merely went stale — which is the common case, since it
    /// expires in hours and only Claude Code itself renews it. Saying that to
    /// them sends them to re-authenticate something that isn't broken.
    private func capturedUsageProblem(hadCredentials: Bool) -> ProviderUsage.Unavailability {
        if StatusLineHook.isInstalled { return .awaitingResponse }
        return hadCredentials ? .claudeLoginExpired : .claudeSignInRequired
    }

    /// The windows Claude Code hands to the status line. Each can be absent on
    /// its own, and Claude Code drops one once it has reset, so a missing
    /// entry is normal rather than an error.
    ///
    /// **A window whose reset time has passed is dropped, not aged.** This is
    /// a push, not a pull: the figures only move while a session runs, so a
    /// Mac that hasn't run Claude Code since yesterday is still holding
    /// yesterday's blob — and a five-hour window in it reset long ago. Shown
    /// with an "as of" line it still reads as a limit you are inside, when in
    /// truth it is a number about a window that no longer exists. `UsageCache`
    /// has had this rule from the start; this route is the other place an old
    /// reading can come from, and it went without.
    private static func capturedWindows(from limits: [String: Any], now: Date = Date()) -> [UsageWindow] {
        let known: [(key: String, kind: UsageWindow.Kind, seconds: Int)] = [
            ("five_hour", .fiveHour, 5 * 3600),
            ("seven_day", .weekly, 7 * 86_400),
            ("spend_limit", .spend, 0)
        ]

        return known.compactMap { entry in
            guard
                let node = limits[entry.key] as? [String: Any],
                let percent = StatusLineHook.percent(node["used_percentage"])
            else { return nil }

            let resets = (node["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                ?? (node["resets_at"] as? Int).map { Date(timeIntervalSince1970: Double($0)) }

            guard resets ?? .distantFuture > now else { return nil }

            return UsageWindow(
                id: "claudeCode.\(entry.key)",
                kind: entry.kind,
                scope: nil,
                usedFraction: percent / 100,
                windowSeconds: entry.seconds,
                resetsAt: resets
            )
        }
    }
}
