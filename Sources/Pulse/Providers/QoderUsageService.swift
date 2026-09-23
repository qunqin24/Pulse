import CryptoKit
import Foundation

/// Qoder's credits, read the way its own account page reads them.
///
/// **A browser session, not a key.** Qoder publishes no usage API. The account
/// page (`/account/usage`) asks `GET /api/v2/me/usages/big_model_credits` with
/// the signed-in cookies and draws what comes back, so that session is the
/// credential — as Ollama's and Xiaomi's are, with the same consequences:
/// Safari's store needs Full Disk Access, and Chromium's asks for keychain
/// permission once.
///
/// **Two sites, two accounts.** `qoder.com` and `qoder.com.cn` are separate
/// sign-ins on separate hosts, and a session for one is never sent to the
/// other: which one is read is a setting (`AppSettings.qoderSite`), and the
/// browser is only ever asked for that host's cookies.
///
/// **Not the IDE's own figures.** The Qoder app caches a credit reading of its
/// own and exposes it over a local socket, but other monitors that read it
/// found it disagreeing with the billing page for paid accounts. The web
/// route is the one the page itself uses.
///
/// Reply shape, from the account page's own request — camelCase today, and
/// the snake_case of an earlier build is still accepted:
///
/// ```json
/// { "quotaKey": "big_model_credits", "status": "active",
///   "nextResetAt": "2024-09-01T00:00:00Z",
///   "totalQuota":  { "quotaSummary": { "usedValue": 125, "limitValue": 500,
///                    "remainingValue": 375, "usagePercentage": 25, "unit": "credit" } },
///   "sharedQuota": { "quotaSummary": { … } } }
/// ```
///
/// `totalQuota` is the account's own: the plan plus any resource pack bought
/// on top. `sharedQuota` is a team's pool, present only on a team plan. They
/// are **two rings, never one sum** — a spent personal allowance beside an
/// untouched team pool added together reads as "plenty left" about the pool
/// that is actually stopping you.
enum QoderSite: String, CaseIterable, Codable, Sendable {
    case international
    case china

    /// The account page's host, and the only host whose cookies are read.
    var host: String {
        switch self {
        case .international: "qoder.com"
        case .china: "qoder.com.cn"
        }
    }

    var origin: String { "https://\(host)" }

    var usageURL: URL { URL(string: "\(origin)/api/v2/me/usages/big_model_credits")! }

    /// Where somebody is sent to sign in, and the page that makes this request
    /// — so the `Referer` is true rather than invented.
    var accountPage: URL { URL(string: "\(origin)/account/usage")! }
}

enum QoderError: Error, Equatable {
    case missingCookie
    case invalidCookie
    /// The session is there and Qoder refused it — expired, or signed out
    /// elsewhere. Separate from `missingCookie`, because one is "set this up"
    /// and the other is "you already did, do it again".
    case sessionExpired
    case unreadableReply
    case rateLimited
    case serverError
    /// Nothing came back at all — no network, DNS, TLS, a timeout.
    case unreachable
}

/// Which of a Qoder host's cookies are forwarded.
///
/// **A deny list, where Ollama and Xiaomi keep an allow list.** Qoder's
/// session cookie has no published name, and other monitors reading this
/// route forward everything the host set. So this keeps what Qoder's host set
/// and drops what an analytics script set there — the tracking cookies a
/// usage request has no business carrying. What is kept never leaves for any
/// host but the one it came from.
enum QoderCookie {
    /// Prefixes of cookies set by third-party analytics and advertising
    /// scripts rather than by Qoder.
    ///
    /// **Alibaba's own are kept** (`cna`, `isg`, `tfstk` and the like). They
    /// look like tracking and some of them are, but the same family carries
    /// the bot screening in front of Alibaba's sites, and dropping one of those
    /// is how a session that works in the browser gets refused here.
    static let analytics = [
        "_ga", "_gid", "_gat", "_gcl", "_fbp", "_fbc", "_clck", "_clsk", "_hj",
        "_uet", "_tt_", "_ttp", "ajs_", "amp_", "mp_", "hm_", "hmaccount",
        "intercom-", "__stripe", "_rdt", "_pin",
    ]

    /// A `Cookie:` header reduced to the cookies worth sending, or a throw if
    /// none are left.
    ///
    /// Takes what a browser store hands over *or* what somebody pasted out of
    /// their network tab, which is why the `Cookie:` prefix is tolerated and
    /// why each value is checked rather than trusted: a header assembled from
    /// an arbitrary string is a header injection if a value carries a newline.
    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw QoderError.invalidCookie
        }
        var header = input.trimmingCharacters(in: .whitespaces)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw QoderError.missingCookie }
        guard header.utf8.count <= 32_768 else { throw QoderError.invalidCookie }

        var kept: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            let lowered = name.lowercased()
            guard !analytics.contains(where: { lowered.hasPrefix($0) }) else { continue }
            // A cookie this cannot pass on unaltered is one it drops, rather
            // than one that costs the whole session: an odd preference cookie
            // is not a reason to refuse the sign-in beside it.
            guard !value.contains(" "), !value.contains("\\"), !name.contains(" ") else { continue }
            // A host-only row and a domain row for one name is normal in every
            // browser store; the first wins, as it does in any cookie header.
            // See `OllamaSessionCookie.normalize`.
            guard seen.insert(name).inserted else { continue }
            kept.append("\(name)=\(value)")
        }
        guard !kept.isEmpty else { throw QoderError.invalidCookie }
        return kept.joined(separator: "; ")
    }
}

/// What one read of the account page's route returns.
struct QoderSnapshot: Equatable, Sendable {
    struct Pool: Equatable, Sendable {
        let used: Double
        let limit: Double
        /// Qoder's own remainder, when it states one. Not recomputed: absent
        /// says nothing, and zero read from silence would mark a pool spent.
        let remaining: Double?
    }

    /// The account's own credits: plan plus resource packs.
    let personal: Pool
    /// A team's shared pool. Nil off a team plan, and nil when Qoder reports
    /// an empty placeholder — a pool of zero is not one anybody can spend.
    let shared: Pool?
    let resetsAt: Date?
}

/// A read-only adapter for the account page's route. Kept apart from the app
/// so the parsing is testable without a session.
struct QoderClient: Sendable {
    /// Optional only as a test seam. Production resolves the shared session at
    /// request time so a proxy change cannot leave a client holding the one
    /// that was invalidated.
    var session: URLSession?

    func fetch(cookie: String, site: QoderSite) async throws -> QoderSnapshot {
        let header = try QoderCookie.normalize(cookie)

        var request = URLRequest(url: site.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(header, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(site.origin, forHTTPHeaderField: "Origin")
        request.setValue(site.accountPage.absoluteString, forHTTPHeaderField: "Referer")
        // What the page's own request carries, and what every monitor known to
        // read this route sends. `Bx-V` belongs to the bot screening Alibaba
        // puts in front of its sites; a request that does not look like the
        // page it stands in for is the one that screening is there to turn
        // away. A web session, so a web client's agent — the same call
        // `ClaudeDesktopSession` makes.
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("2.5.35", forHTTPHeaderField: "Bx-V")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (session ?? NetworkSession.shared).data(for: request)
        } catch {
            throw QoderError.unreachable
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try Self.parse(data)
        // A signed-out page answers the API call by redirecting it at the
        // sign-in flow; `URLSession` follows redirects, so a 3xx is only seen
        // when one was not followed, and it means the same thing.
        case .some(300..<400), 401, 403: throw QoderError.sessionExpired
        case 429: throw QoderError.rateLimited
        case .some(500...599): throw QoderError.serverError
        default: throw QoderError.unreadableReply
        }
    }

    static func parse(_ data: Data) throws -> QoderSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw QoderError.unreadableReply
        }
        guard let personal = reply.totalQuota?.quotaSummary.flatMap(Self.pool) else {
            throw QoderError.unreadableReply
        }
        let shared: QoderSnapshot.Pool?
        if let container = reply.sharedQuota {
            // An absent team pool is normal; an unreadable one is not proof
            // that no allowance remains. Only a valid zero pool is omitted.
            guard let pool = container.quotaSummary.flatMap(Self.pool) else {
                throw QoderError.unreadableReply
            }
            shared = pool.limit > 0 ? pool : nil
        } else {
            shared = nil
        }
        return QoderSnapshot(personal: personal, shared: shared, resetsAt: reply.nextResetAt)
    }

    /// A summary Qoder stated in full, or nil. Negative figures are not a
    /// reading anybody could have, so they are refused rather than clamped.
    private static func pool(_ summary: Reply.Summary) -> QoderSnapshot.Pool? {
        guard let used = summary.usedValue, let limit = summary.limitValue,
              used.isFinite, limit.isFinite, used >= 0, limit >= 0
        else { return nil }
        let remaining = summary.remainingValue.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return .init(used: used, limit: limit, remaining: remaining)
    }

    // MARK: - Reply

    struct Reply: Decodable {
        let totalQuota: Container?
        let sharedQuota: Container?
        let nextResetAt: Date?

        struct Container: Decodable {
            let quotaSummary: Summary?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: AnyKey.self)
                quotaSummary = try container.either(Summary.self, "quotaSummary", "quota_summary")
            }
        }

        struct Summary: Decodable {
            let usedValue: Double?
            let limitValue: Double?
            let remainingValue: Double?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: AnyKey.self)
                usedValue = try container.either(Double.self, "usedValue", "used_value")
                limitValue = try container.either(Double.self, "limitValue", "limit_value")
                remainingValue = try container.either(Double.self, "remainingValue", "remaining_value")
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            totalQuota = try container.either(Container.self, "totalQuota", "total_quota")
            sharedQuota = try container.either(Container.self, "sharedQuota", "shared_quota")
            nextResetAt = container.date("nextResetAt") ?? container.date("next_reset_at")
        }
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

private extension KeyedDecodingContainer where Key == QoderClient.AnyKey {
    /// The camelCase key, else the snake_case one. A value of the wrong type
    /// under either is a reply this cannot read, and says so.
    func either<T: Decodable>(_ type: T.Type, _ camel: String, _ snake: String) throws -> T? {
        try decodeIfPresent(type, forKey: .init(stringValue: camel))
            ?? decodeIfPresent(type, forKey: .init(stringValue: snake))
    }

    /// ISO 8601 text or a Unix stamp, seconds or milliseconds. **Zero and
    /// garbage are no date**: a reset drawn at 1970 is a countdown that ran
    /// out before anybody signed up.
    func date(_ name: String) -> Date? {
        let key = Key(stringValue: name)
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        }
        guard let stamp = try? decodeIfPresent(Double.self, forKey: key),
              stamp.isFinite, stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp > 10_000_000_000 ? stamp / 1000 : stamp)
    }
}

struct QoderUsageService: Sendable {
    let cookie: String?
    let site: QoderSite
    var client = QoderClient()

    func fetch() async -> ProviderUsage {
        var usage = await read()
        usage.sourceScope = Self.scope(site: site, cookie: cookie)
        return usage
    }

    /// Which site and which session a reading came from, for the cache.
    ///
    /// A reading banked for `qoder.com` must not stand in when `qoder.com.cn`
    /// fails, and one banked for a session since replaced is somebody else's
    /// until shown otherwise. The session is named by its SHA-256, never by
    /// itself. Nil without one, which never matches anything.
    static func scope(site: QoderSite, cookie: String?) -> UsageScope? {
        guard let cookie, !cookie.isEmpty else { return nil }
        let fingerprint = SHA256.hash(data: Data(cookie.utf8)).map { String(format: "%02x", $0) }.joined()
        return UsageScope(route: .webSession, organization: site.host, identity: fingerprint)
    }

    private func read() async -> ProviderUsage {
        guard let cookie, !cookie.isEmpty else {
            return .unavailable(.qoder, reason: .qoderSessionMissing)
        }
        do {
            let snapshot = try await client.fetch(cookie: cookie, site: site)
            let windows = Self.windows(from: snapshot)
            // A complete answer: the account has no allowance to display.
            guard !windows.isEmpty else { return .unavailable(.qoder, reason: .qoderNoCredits) }
            return .init(account: AccountKey(.qoder),
                         windows: windows,
                         observedAt: Date(),
                         state: .live,
                         plan: nil,
                         creditBalance: nil)
        } catch let error as QoderError {
            let reason: ProviderUsage.Unavailability = switch error {
            case .missingCookie, .invalidCookie: .qoderSessionMissing
            case .sessionExpired: .qoderSessionExpired
            case .rateLimited: .rateLimited
            case .serverError: .serverError
            case .unreadableReply: .unreadableReply
            case .unreachable: .unreachable
            }
            return .unavailable(.qoder, reason: reason)
        } catch {
            return .unavailable(.qoder, reason: .unreachable)
        }
    }

    /// The account's credits, and the team's pool beside them when there is
    /// one.
    ///
    /// The fraction is Qoder's `usedValue` over its `limitValue` rather than
    /// its `usagePercentage`, which is the same figure rounded to a whole
    /// number — the panel rounds for itself and would otherwise round a
    /// rounding. A pool with a limit of zero is **not drawn**: there is no
    /// allowance to divide by, and a ring at 100% would say something was
    /// spent that was never granted.
    static func windows(from snapshot: QoderSnapshot) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        if let window = window(snapshot.personal, id: "qoder.credits", kind: .credits,
                               resetsAt: snapshot.resetsAt) {
            windows.append(window)
        }
        // The reset Qoder states is the account's. Whether a team's pool turns
        // over on the same day is not something the reply says, so it is not
        // claimed for it.
        if let shared = snapshot.shared,
           let window = window(shared, id: "qoder.shared", kind: .sharedCredits, resetsAt: nil) {
            windows.append(window)
        }
        return windows
    }

    private static func window(_ pool: QoderSnapshot.Pool, id: String, kind: UsageWindow.Kind,
                               resetsAt: Date?) -> UsageWindow? {
        guard pool.limit > 0 else { return nil }
        return UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: min(max(pool.used / pool.limit, 0), 1),
            // Thirty days is a **sort key, not a reported length**. Qoder
            // states when the credits reset and never how long the period is
            // — a trial runs a fortnight, a plan a billing month — so
            // `reportsLength` is false and the window-clock arc and the
            // forecast leave it alone rather than dividing by a number nobody
            // stated.
            windowSeconds: 30 * 86_400,
            resetsAt: resetsAt,
            reportsLength: false,
            isExhausted: pool.remaining.map { $0 <= 0 } ?? (pool.used >= pool.limit))
    }
}
