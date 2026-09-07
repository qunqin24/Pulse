import Foundation

/// The Volcengine Coding Plan, sold on Volcengine Ark.
///
/// Two routes, and unusually for Pulse neither is a browser session:
///
/// - **`arkcli`**, Volcengine's own CLI. `arkcli usage plan --format json`
///   answers with every plan the account is subscribed to — Coding and Agent,
///   personal and team — each with its five-hour, weekly and monthly windows.
///   Nothing to paste; it uses the login `arkcli auth login` already stored.
/// - **An access key pair**, signed against Volcengine's Top OpenAPI
///   (`GetCodingPlanUsage` and `GetAFPUsage`). For anyone who has keys but
///   doesn't run the CLI on this Mac.
///
/// `.automatic` prefers **configured keys over the CLI**, which is the one
/// place this differs from every other automatic in Pulse. The reason is
/// account identity rather than reliability: `arkcli` carries an ambient SSO
/// session that can be signed in to a different account than the keys, and
/// silently reporting the wrong account's limits is worse than either answer.
/// If you pasted keys, you meant those. (The rule and its reasoning are
/// CodexBar's, MIT.)
///
/// **A third route was deliberately left out.** Ark returns
/// `x-ratelimit-remaining-requests` on a chat completion, and CodexBar reads
/// it as a fallback. Pulse cannot: reading it means *sending a completion*,
/// so every refresh would spend a piece of the quota it is measuring, every
/// two to thirty minutes, for ever. And a request-rate throttle is not the
/// coding plan's quota — it would put a number under the ring that answers a
/// different question.
///
/// **Not verified against a live account.** Nobody on this side has a Volcengine
/// plan. The response shapes below are second-hand from CodexBar's parser and
/// its tests rather than measured, which is weaker evidence than every other
/// provider in Pulse has behind it, and it is why the parsing is covered by
/// fixtures and the failure copy is specific. See
/// [Docs/providers/volcengine.md](../../Docs/providers/volcengine.md).
struct VolcengineUsageService: Sendable {
    /// Carries an `Unavailability` through a `Result` without making that
    /// shared enum an `Error` for the whole app's benefit.
    private struct Refusal: Error {
        let reason: ProviderUsage.Unavailability
    }

    private let credentials: VolcengineSigner.Credentials?

    /// The pasted field is one string holding two secrets, split on the first
    /// colon: `AccessKeyID:SecretAccessKey`. Split on the *first* so a secret
    /// containing a colon survives.
    init(enteredKey: String?) {
        credentials = Self.credentials(from: enteredKey)
    }

    static func credentials(from entered: String?) -> VolcengineSigner.Credentials? {
        guard let entered = entered?.trimmingCharacters(in: .whitespacesAndNewlines), !entered.isEmpty,
              let separator = entered.firstIndex(of: ":")
        else { return nil }

        let id = String(entered[entered.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
        let secret = String(entered[entered.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !secret.isEmpty else { return nil }

        return VolcengineSigner.Credentials(accessKeyID: id, secretAccessKey: secret)
    }

    func fetch(source: UsageSource) async -> ProviderUsage {
        switch source {
        case .endpoint:
            guard let credentials else { return .unavailable(.volcengine, reason: .apiKeyMissing) }
            return await signed(credentials)

        case .tooling:
            return await cli()

        case .automatic, .desktopApp:
            guard let credentials else { return await cli() }

            let keyed = await signed(credentials)
            // Keys that are simply wrong should say so rather than falling
            // through to a CLI that might be a different account: the fallback
            // would look like the keys working.
            if case .unavailable(.unreachable) = keyed.state { return await cli() }
            return keyed
        }
    }

    // MARK: - arkcli

    private func cli() async -> ProviderUsage {
        guard let binary = Self.locateArkcli() else {
            return .unavailable(.volcengine, reason: .volcengineCLIMissing)
        }

        let output: Data
        switch Self.run(binary, ["usage", "plan", "--format", "json"]) {
        case .success(let data): output = data
        case .failure(let refusal): return .unavailable(.volcengine, reason: refusal.reason)
        }

        guard let reply = try? JSONDecoder().decode(ArkcliReply.self, from: output) else {
            return .unavailable(.volcengine, reason: .unreadableReply)
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else { return .unavailable(.volcengine, reason: .noLimitsReported) }

        return ProviderUsage(
            account: AccountKey(.volcengine),
            windows: windows,
            observedAt: Self.observedAt(from: reply) ?? Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    /// A GUI app inherits almost no `PATH`, so the usual install locations are
    /// checked by hand — the same problem `CodexAppServer.locateCodex` solves.
    /// `ARKCLI_PATH` first, for anyone who put it somewhere else.
    static func locateArkcli() -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["ARKCLI_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/arkcli" }
        }
        candidates += [
            "\(home)/.local/bin/arkcli",
            "/opt/homebrew/bin/arkcli",
            "/usr/local/bin/arkcli"
        ]

        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Runs it with a ceiling on both time and output.
    ///
    /// **Both matter.** This is on the refresh pass, so a CLI waiting on a
    /// login prompt would stall every other provider behind it; and a command
    /// that decides to stream would be read into memory for ever. A timeout
    /// here is a stale reading, which the cache already knows how to show.
    private static func run(_ binary: URL, _ arguments: [String]) -> Result<Data, Refusal> {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        // Nothing to answer with, so a CLI that asks gets EOF rather than
        // blocking on a terminal that is not there.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .failure(Refusal(reason: .volcengineCLIMissing))
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let problem = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // The one failure worth telling apart, because the remedy is a
            // command rather than a bug report.
            let text = (problem + " " + (String(data: data, encoding: .utf8) ?? "")).lowercased()
            let signedOut = ["auth", "login", "unauthorized", "credential", "not signed in"]
                .contains { text.contains($0) }
            return .failure(Refusal(reason: signedOut ? .volcengineSignInRequired : .unreadableReply))
        }

        return .success(data)
    }

    // MARK: - The signed API

    private static let codingPlanURL = URL(
        string: "https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01"
    )!
    /// AFP is "Agent Flow Points". An account can hold both plans, and the two
    /// actions are independent, so a missing Agent Plan must not lose the
    /// Coding Plan's windows.
    private static let agentPlanURL = URL(
        string: "https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01"
    )!

    private func signed(_ credentials: VolcengineSigner.Credentials) async -> ProviderUsage {
        async let coding = Self.ask(Self.codingPlanURL, credentials: credentials, decode: Self.codingWindows)
        async let agent = Self.ask(Self.agentPlanURL, credentials: credentials, decode: Self.agentWindows)

        let (codingResult, agentResult) = await (coding, agent)

        // A refusal on *both* is a refusal; a refusal on one plan the account
        // simply doesn't hold is not, and must not take the other's figures
        // down with it.
        if case .failure(let refusal) = codingResult, case .failure = agentResult {
            return .unavailable(.volcengine, reason: refusal.reason)
        }

        let windows = ((try? codingResult.get()) ?? []) + ((try? agentResult.get()) ?? [])
        guard !windows.isEmpty else { return .unavailable(.volcengine, reason: .noLimitsReported) }

        return ProviderUsage(
            account: AccountKey(.volcengine),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: nil
        )
    }

    private static func ask(
        _ url: URL,
        credentials: VolcengineSigner.Credentials,
        decode: @Sendable (Data) -> [UsageWindow]?
    ) async -> Result<[UsageWindow], Refusal> {
        let body = Data()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        for (field, value) in VolcengineSigner.headers(
            method: "GET",
            url: url,
            body: body,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            credentials: credentials,
            date: Date()
        ) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failure(Refusal(reason: .unreachable))
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .failure(Refusal(reason: .apiKeyRefused))
        case 429: return .failure(Refusal(reason: .rateLimited))
        // 404 is how an account that doesn't hold this plan answers.
        case 404: return .failure(Refusal(reason: .noLimitsReported))
        default: return .failure(Refusal(reason: .serverError))
        }

        guard let windows = decode(data) else { return .failure(Refusal(reason: .unreadableReply)) }
        return .success(windows)
    }
}

// MARK: - Reading the replies

extension VolcengineUsageService {
    /// `arkcli usage plan --format json`.
    ///
    /// A product bucket can fail on its own — an item with an `error` and no
    /// `periods` — so `periods` is optional and a failed bucket is skipped
    /// rather than rejecting the whole reply. Losing a working plan because
    /// the other one errored is the failure mode this shape exists to avoid.
    struct ArkcliReply: Decodable {
        struct Item: Decodable {
            let product: String
            let subscribed: Bool?
            let periods: [Period]?
            let updatedAt: Double?

            enum CodingKeys: String, CodingKey {
                case product, subscribed, periods
                case updatedAt = "updated_at"
            }
        }

        struct Period: Decodable {
            let label: String
            /// **Used**, 0–100. Not remaining — no inversion here, unlike
            /// Antigravity.
            let percent: Double
            let resetAt: Stamp?

            enum CodingKeys: String, CodingKey {
                case label, percent
                case resetAt = "reset_at"
            }
        }

        /// `reset_at` and `updated_at` have both shipped as an ISO string and
        /// as a number, and the number as both seconds and milliseconds across
        /// versions. Guessing by magnitude: 1e11 seconds is the year 5138 and
        /// 1e11 milliseconds is 1973, so nothing real sits near the boundary.
        enum Stamp: Decodable {
            case text(String)
            case number(Double)

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Double.self) {
                    self = .number(number)
                } else {
                    self = .text(try container.decode(String.self))
                }
            }

            var date: Date? {
                switch self {
                case .text(let value):
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: value)
                        ?? {
                            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            return formatter.date(from: value)
                        }()
                case .number(let value):
                    return Self.date(fromEpoch: value)
                }
            }

            static func date(fromEpoch value: Double) -> Date? {
                guard value > 0 else { return nil }
                return Date(timeIntervalSince1970: value >= 1e11 ? value / 1000 : value)
            }
        }

        let items: [Item]
    }

    /// Which plan a window belongs to, as the `scope` shown after its name —
    /// "Weekly limit · Coding Plan". Product names, so never translated.
    ///
    /// An unrecognised product is dropped rather than shown unlabelled: with
    /// four plans possible on one account, a window that cannot say which one
    /// it is about is worse than no window.
    static func planName(for product: String) -> String? {
        switch product.lowercased() {
        case "coding-plan": "Coding Plan"
        case "agent-plan": "Agent Plan"
        case "coding-plan-team": "Coding Plan · Team"
        case "agent-plan-team": "Agent Plan · Team"
        default: nil
        }
    }

    static func windows(from reply: ArkcliReply) -> [UsageWindow] {
        reply.items.flatMap { item -> [UsageWindow] in
            guard item.subscribed != false, let plan = planName(for: item.product) else { return [] }

            return (item.periods ?? [])
                .compactMap { period in
                    window(
                        id: "\(item.product.lowercased()).\(period.label.lowercased())",
                        label: period.label,
                        usedPercent: period.percent,
                        scope: plan,
                        resetsAt: period.resetAt?.date
                    )
                }
                .sorted { $0.windowSeconds < $1.windowSeconds }
        }
    }

    static func observedAt(from reply: ArkcliReply) -> Date? {
        reply.items
            .compactMap { $0.updatedAt.flatMap(ArkcliReply.Stamp.date(fromEpoch:)) }
            .max()
    }

    // MARK: - The signed API's two shapes

    private struct CodingPlanReply: Decodable {
        struct Quota: Decodable {
            let level: String
            let percent: Double
            let resetTimestamp: Double?

            enum CodingKeys: String, CodingKey {
                case level = "Level"
                case percent = "Percent"
                case resetTimestamp = "ResetTimestamp"
            }
        }

        struct Payload: Decodable {
            let quotaUsage: [Quota]

            enum CodingKeys: String, CodingKey {
                case quotaUsage = "QuotaUsage"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // A reclaimed or inactive plan answers with a status and no
                // `QuotaUsage` at all. That is "nothing to report", not a
                // malformed reply, and it must not fail the Agent Plan beside
                // it.
                quotaUsage = try container.decodeIfPresent([Quota].self, forKey: .quotaUsage) ?? []
            }
        }

        let result: Payload

        enum CodingKeys: String, CodingKey {
            case result = "Result"
        }
    }

    /// `GetAFPUsage` — Agent Flow Points. Reports quota and used rather than a
    /// percentage, and names its windows in the keys instead of in a list.
    private struct AgentPlanReply: Decodable {
        struct Window: Decodable {
            let quota: Double
            let used: Double
            let resetTime: Double?

            enum CodingKeys: String, CodingKey {
                case quota = "Quota"
                case used = "Used"
                case resetTime = "ResetTime"
            }
        }

        struct Payload: Decodable {
            let fiveHour: Window?
            let weekly: Window?
            let monthly: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "AFPFiveHour"
                case weekly = "AFPWeekly"
                case monthly = "AFPMonthly"
            }
        }

        let result: Payload

        enum CodingKeys: String, CodingKey {
            case result = "Result"
        }
    }

    static func codingWindows(_ data: Data) -> [UsageWindow]? {
        guard let reply = try? JSONDecoder().decode(CodingPlanReply.self, from: data) else { return nil }

        return reply.result.quotaUsage
            .compactMap { quota in
                window(
                    id: "coding-plan.\(quota.level.lowercased())",
                    label: quota.level,
                    usedPercent: quota.percent,
                    scope: "Coding Plan",
                    resetsAt: quota.resetTimestamp.flatMap(ArkcliReply.Stamp.date(fromEpoch:))
                )
            }
            .sorted { $0.windowSeconds < $1.windowSeconds }
    }

    static func agentWindows(_ data: Data) -> [UsageWindow]? {
        guard let reply = try? JSONDecoder().decode(AgentPlanReply.self, from: data) else { return nil }

        let named: [(label: String, window: AgentPlanReply.Window?)] = [
            ("5h", reply.result.fiveHour),
            ("weekly", reply.result.weekly),
            ("monthly", reply.result.monthly)
        ]

        return named.compactMap { entry -> UsageWindow? in
            // A quota of zero is not a full window, it is a plan that has no
            // such window. Dividing by it would report 100% used of nothing.
            guard let reported = entry.window, reported.quota > 0 else { return nil }

            return window(
                id: "agent-plan.\(entry.label)",
                label: entry.label,
                usedPercent: reported.used / reported.quota * 100,
                scope: "Agent Plan",
                resetsAt: reported.resetTime.flatMap(ArkcliReply.Stamp.date(fromEpoch:))
            )
        }
    }

    // MARK: - One window

    /// A window whose label cannot be read is **left out rather than guessed
    /// at** — the same rule Antigravity's buckets get. A label Pulse does not
    /// know is a window it cannot name, sort, or say the length of.
    ///
    /// `reportsLength` is false for the monthly one on purpose: a month is 28
    /// to 31 days, so 30 is a sort key and not a measurement, and dividing by
    /// it would draw a window-clock arc and a forecast nobody reported. Five
    /// hours and a week are exact.
    static func window(
        id: String,
        label: String,
        usedPercent: Double,
        scope: String,
        resetsAt: Date?
    ) -> UsageWindow? {
        let kind: UsageWindow.Kind
        let seconds: Int
        var reportsLength = true

        switch label.lowercased() {
        case "5h", "5-hour", "five_hour", "session":
            (kind, seconds) = (.fiveHour, 5 * 3_600)
        case "weekly", "week":
            (kind, seconds) = (.weekly, 7 * 86_400)
        case "monthly", "month":
            (kind, seconds) = (.monthly, 30 * 86_400)
            reportsLength = false
        default:
            return nil
        }

        let used = min(max(usedPercent / 100, 0), 1)
        return UsageWindow(
            id: id,
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            // Ark reports no "you are blocked" flag of its own, so the only
            // honest signal is its own figure reaching its own ceiling.
            isExhausted: used >= 1
        )
    }
}
