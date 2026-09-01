import Foundation

/// The GLM Coding Plan's limits, from Zhipu's quota endpoint.
///
/// **Two providers, one service.** Z.ai and BigModel are the same company's
/// international and mainland storefronts, answering the same JSON at the same
/// path on different hosts — but they are separate accounts with separate
/// keys, and a key for one is refused by the other. CodexBar models this as
/// one provider with a region switch; Pulse gives each a ring, because someone
/// with only the mainland plan should not have to know that an international
/// one exists to configure their own.
///
/// `GET {host}/api/monitor/usage/quota/limit`, with the key as a bearer token.
/// Undocumented, like most of the routes here, and it can change without
/// notice. The parsing follows CodexBar's, which is the only written account
/// of this reply that exists.
///
/// **The reply wraps its payload in a status of its own** — `success` and
/// `code`, both of which have to say 200 even when HTTP did. A refused key
/// comes back as HTTP 200 with `success: false`, so reading only the status
/// line would report an empty plan rather than a bad key.
struct ZaiUsageService: Sendable {
    /// Which storefront this instance is for. It decides the host, the
    /// account the answer belongs to, and nothing else.
    let provider: Provider
    let enteredKey: String?

    /// The two hosts. `api.z.ai` is the international one; mainland accounts
    /// live on BigModel and are not reachable there.
    private var host: String {
        provider == .glmCoding ? "https://open.bigmodel.cn" : "https://api.z.ai"
    }

    private var endpoint: URL {
        URL(string: "\(host)/api/monitor/usage/quota/limit")!
    }

    /// A key already sitting on this Mac, for the mainland plan only.
    ///
    /// The relay and console tools that set GLM up write the key to a
    /// one-line file, so anyone already using it configures nothing. **Never
    /// consulted for the international route**: they are separate accounts,
    /// and quietly sending a BigModel key to `api.z.ai` would report a refused
    /// key for a plan the user does not have.
    ///
    /// Only the first readable line is taken, and it is taken **carefully**.
    /// `split(separator: "\n")` does not cut a CRLF file at all — Swift treats
    /// `\r\n` as one Character — and `CharacterSet.whitespaces` holds neither
    /// CR nor LF, so a file written on Windows yielded the whole thing as the
    /// "key". `URLRequest.setValue` then silently *discards* a header value
    /// containing a newline, so the request went out with no `Authorization`
    /// at all, came back 401, and was reported as a refused key — about a key
    /// that was correct, in a Settings field that was empty because it came
    /// from a file.
    static func storedKey(for provider: Provider) -> String? {
        guard provider == .glmCoding else { return nil }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            ".coding-relay/glm-api-key",
            ".config/bigmodel/api_key",
            ".config/zhipu/api_key",
        ]
        for path in candidates {
            guard let text = try? String(contentsOf: home.appending(path: path), encoding: .utf8)
            else { continue }
            let key = text
                .split(whereSeparator: \.isNewline).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !key.isEmpty { return key }
        }
        return nil
    }

    func fetch() async -> ProviderUsage {
        // What the user pasted wins, so a stale file cannot quietly override a
        // deliberate choice — the same order OpenCode Go's two sources take.
        let key = enteredKey.flatMap { $0.isEmpty ? nil : $0 } ?? Self.storedKey(for: provider)
        guard let key else {
            return .unavailable(provider, reason: .apiKeyMissing)
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(provider, reason: .unreachable)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(provider, reason: .apiKeyRefused)
        case 429: return .unavailable(provider, reason: .rateLimited)
        default: return .unavailable(provider, reason: .serverError)
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .unavailable(provider, reason: .unreadableReply)
        }

        // The envelope's own verdict. A key the service refuses arrives here as
        // a perfectly good HTTP 200, so this is the only place it can be seen.
        //
        // **But not every refusal is about the key.** A 500 or a rate limit
        // arrives the same way, and reporting those as a bad key sends the user
        // to check a credential that is fine. The envelope's own code says
        // which, so it is read rather than assumed.
        guard reply.success == true, reply.code == 200 else {
            return .unavailable(provider, reason: Self.problem(reply))
        }

        let windows = Self.windows(from: reply.data?.limits ?? [], provider: provider)
        guard !windows.isEmpty else {
            return .unavailable(provider, reason: .noLimitsReported)
        }

        return ProviderUsage(
            account: AccountKey(provider),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: reply.data?.planLabel,
            creditBalance: nil
        )
    }

    /// What the envelope's refusal actually was.
    private static func problem(_ reply: Reply) -> ProviderUsage.Unavailability {
        let said = (reply.msg ?? "").lowercased()
        if ["token", "auth", "key", "unauthor", "forbidden", "credential"].contains(where: said.contains) {
            return .apiKeyRefused
        }
        return switch reply.code {
        case 401, 403: .apiKeyRefused
        case 429: .rateLimited
        default: .serverError
        }
    }

    // MARK: - The reply

    /// Internal so the mapping can be driven against captured JSON: the field
    /// names are undocumented and the arithmetic below is the whole feature.
    static func windows(from limits: [Reply.Limit], provider: Provider) -> [UsageWindow] {
        limits.enumerated().compactMap { window(from: $1, at: $0, provider: provider) }
            // Shortest first, so a five-hour limit is read before a weekly one.
            .sorted { $0.windowSeconds < $1.windowSeconds }
    }

    private static func window(from limit: Reply.Limit, at index: Int, provider: Provider) -> UsageWindow? {
        // Only these three carry a quota. Anything else the service starts
        // reporting is left out rather than shown under a heading guessed at.
        guard let type = limit.type,
              ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type),
              let unit = limit.unit,
              let number = limit.number
        else { return nil }

        guard let minutes = Self.minutes(unit: unit, number: number, type: type),
              let used = Self.usedFraction(limit)
        else { return nil }

        return UsageWindow(
            // The position is in the id because two limits can share a type and
            // a duration. Ids are what a pinned window is matched on and the
            // identity three `ForEach`es use, so a collision leaves rows
            // undefined and a pin unresolvable.
            id: "\(provider.rawValue).\(type).\(unit)-\(number).\(index)",
            kind: Self.kind(forMinutes: minutes),
            // The MCP lane is a different allowance from the coding quota, and
            // saying so is the only way two rows of the same length tell apart.
            scope: type == "TIME_LIMIT" ? "MCP" : nil,
            usedFraction: used / 100,
            windowSeconds: minutes * 60,
            resetsAt: limit.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    /// How long the window runs.
    ///
    /// The reply states a `unit` code and a `number` of them. An unrecognised
    /// unit means the length cannot be read, and a window with no length can
    /// be neither named nor sorted — so it is dropped rather than given an
    /// invented one, the same rule Antigravity's buckets follow.
    private static func minutes(unit: Int, number: Int, type: String) -> Int? {
        // A monthly MCP allowance is reported as "1 minute", which is a marker
        // rather than a duration — taken literally it would sort above a
        // five-hour limit and claim to reset every minute.
        if type == "TIME_LIMIT", unit == 5, number == 1 { return 30 * 24 * 60 }

        let perUnit: [Int: Int] = [1: 1440, 3: 60, 5: 1, 6: 10080]
        guard number > 0, let multiplier = perUnit[unit] else { return nil }
        return number * multiplier
    }

    private static func kind(forMinutes minutes: Int) -> UsageWindow.Kind {
        switch minutes {
        case 300: .fiveHour
        case 10080: .weekly
        case 43200: .monthly
        default: .other(seconds: minutes * 60)
        }
    }

    /// How much of the limit is gone, 0...100.
    ///
    /// `percentage` is what the service intends to be read, but it is a whole
    /// number — so a plan whose counts are also given is worked out from those
    /// instead, which is finer. `remaining` is what is *left*, so the spend is
    /// the difference; `currentValue` is the spend directly and wins when both
    /// are present, since it is the one the service is counting up.
    private static func usedFraction(_ limit: Reply.Limit) -> Double? {
        // The counts first when they are there: `percentage` is a whole number
        // and these are finer. `remaining` is what is *left*, so the spend is
        // the difference; `currentValue` is the spend directly and wins when
        // both are present, being the one the service counts up.
        if let usage = limit.usage, usage > 0 {
            var used: Double?
            if let remaining = limit.remaining {
                used = max(usage - remaining, limit.currentValue ?? (usage - remaining))
            } else if let current = limit.currentValue {
                used = current
            }
            if let used { return min(max(min(used, usage) / usage * 100, 0), 100) }
        }

        // **Nil rather than zero.** A limit that arrives with no figure at all
        // is not a limit at 0% — it is a limit whose reading is missing, and
        // drawing a full green ring for an account that may be out of quota is
        // the one thing this app is not allowed to do.
        guard let percentage = limit.percentage else { return nil }
        return min(max(percentage, 0), 100)
    }

    struct Reply: Decodable, Sendable {
        /// The service's own verdict, separate from the HTTP status.
        let success: Bool?
        let code: Int?
        let msg: String?
        let data: Payload?

        struct Payload: Decodable, Sendable {
            let limits: [Limit]?
            /// The plan's name, under whichever of five keys this account's
            /// tier happens to use. Passed through verbatim when unfamiliar —
            /// an unknown name still beats no name.
            let planName: String?
            let plan: String?
            let planType: String?
            let packageName: String?
            let level: String?

            var planLabel: String? {
                [planName, plan, planType, packageName, level]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
            }

            enum CodingKeys: String, CodingKey {
                case limits, planName, plan, packageName, level
                case planType = "plan_type"
            }
        }

        /// Numbers are read as `Double` rather than `Int` deliberately: a
        /// service that starts reporting `12.5` where it used to report `12`
        /// would otherwise fail the whole reply and blank the ring, when the
        /// figure is perfectly usable.
        struct Limit: Decodable, Sendable {
            let type: String?
            let unit: Int?
            let number: Int?
            let percentage: Double?
            let usage: Double?
            let currentValue: Double?
            let remaining: Double?
            let nextResetTime: Double?
        }
    }
}
