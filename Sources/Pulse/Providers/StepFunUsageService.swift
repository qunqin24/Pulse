// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CryptoKit
import Foundation

/// StepFun's Step Plan, read the way its own console reads it.
///
/// **A browser session, not a key.** The Step API key buys inference; the
/// plan's allowance is only on the console, which asks
/// `POST /api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit` with the
/// signed-in cookies. So that session is the credential, as Qoder's and
/// Xiaomi's are. The documented `GET /v1/accounts` answers a key, but with the
/// account's prepaid balance, which is a separate system from the plan.
///
/// **Two sites, two accounts.** `platform.stepfun.com` and
/// `platform.stepfun.ai` are separate sign-ins; which one is read is a setting
/// (`AppSettings.stepFunSite`), and a session for one is never sent to the
/// other.
///
/// **Two plans, two shapes.** Since 2026-06-18 StepFun sells a Token Plan: a
/// monthly pool of Credits plus 30-day top-up packs, each a bucket with its own
/// size, remainder and end date. The Coding Plan before it — still renewed for
/// anybody who kept auto-renew on — meters a five-hour and a weekly window as
/// a remaining fraction and a reset time. One reply carries whichever the
/// account has, the other's fields zeroed. Measured on a Token Plan (Plus,
/// 2026-09-24); the Coding Plan shape is second-hand.
enum StepFunSite: String, CaseIterable, Codable, Sendable {
    case china
    case international

    /// The console's host, and the only host whose cookies are read.
    var host: String {
        switch self {
        case .china: "platform.stepfun.com"
        case .international: "platform.stepfun.ai"
        }
    }

    /// What the site picker shows: the domain without `platform.`, which
    /// fits the segmented control and is how people name the two.
    var label: String {
        switch self {
        case .china: "stepfun.com"
        case .international: "stepfun.ai"
        }
    }

    var origin: String { "https://\(host)" }

    func endpoint(_ method: String) -> URL {
        URL(string: "\(origin)/api/step.openapi.devcenter.Dashboard/\(method)")!
    }

    /// The page that makes this request, so the `Referer` is true.
    var usagePage: URL { URL(string: "\(origin)/plan-usage")! }
}

enum StepFunError: Error, Equatable {
    case missingCookie
    case invalidCookie
    /// The session is there and StepFun refused it. Separate from
    /// `missingCookie`: one is "set this up", the other "do it again".
    case sessionExpired
    /// The session works and the account has no Step Plan on it. A complete
    /// answer, not a fault.
    case noPlan
    case unreadableReply
    case rateLimited
    case serverError
    /// Nothing came back at all — no network, DNS, TLS, a timeout.
    case unreachable
}

/// The cookie names the console's own requests carry.
///
/// **An allow list**, as Xiaomi's is: the session has published names, so
/// nothing else the host set is forwarded.
enum StepFunCookie {
    /// The session itself. The console answers nothing without it.
    static let required = ["Oasis-Token"]
    /// Sent when present. `Oasis-Webid` has to agree with the device the token
    /// was issued to; `INGRESSCOOKIE` pins the load balancer.
    static let optional = ["Oasis-Webid", "INGRESSCOOKIE"]

    /// A `Cookie:` header reduced to the names above, or a throw if the token
    /// is not in it. Tolerates a pasted `Cookie:` prefix and refuses control
    /// characters: a header built from an arbitrary string is a header
    /// injection if a value carries a newline.
    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw StepFunError.invalidCookie
        }
        var header = input.trimmingCharacters(in: .whitespaces)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw StepFunError.missingCookie }
        guard header.utf8.count <= 32_768 else { throw StepFunError.invalidCookie }

        let wanted = Set(required + optional)
        var kept: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard wanted.contains(name) else { continue }
            guard !value.isEmpty, !value.contains("\""), !value.contains("\\"),
                  !value.contains(" ") else {
                throw StepFunError.invalidCookie
            }
            // The first of a host-only and a domain row wins, as in any cookie
            // header; see `OllamaSessionCookie.normalize`.
            guard seen.insert(name).inserted else { continue }
            kept.append("\(name)=\(value)")
        }
        guard required.allSatisfy({ seen.contains($0) }) else { throw StepFunError.invalidCookie }
        return kept.joined(separator: "; ")
    }

    /// The device id the console sends as `oasis-webid`, which must match the
    /// one the token was issued to.
    ///
    /// The `Oasis-Webid` cookie when the session carries it. Otherwise the
    /// token's own `device_id` claim: the token is a JWT, or an
    /// `access...refresh` pair whose refresh half carries the claim. Read, not
    /// verified — it only has to be repeated back to the server that signed it.
    static func webID(in header: String) -> String? {
        var values: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        if let webid = values["Oasis-Webid"], !webid.isEmpty { return webid }
        guard let token = values["Oasis-Token"] else { return nil }
        for half in token.components(separatedBy: "...").reversed() {
            if let id = deviceID(inJWT: half) { return id }
        }
        return nil
    }

    private static func deviceID(inJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = claims["device_id"] as? String, !id.isEmpty
        else { return nil }
        return id
    }
}

/// What one read of the console returns.
struct StepFunSnapshot: Equatable, Sendable {
    /// One of the Token Plan's credit buckets: the month's pool, or a top-up
    /// pack. Sizes in Credits (1M Credit = ¥1).
    struct Bucket: Equatable, Sendable {
        let total: Double
        let remaining: Double
        /// When what is left in it lapses. Nil when not stated.
        let expiresAt: Date?
        /// When it is refilled — a quarterly or yearly plan's next monthly
        /// issue. Nil when not stated, which on a monthly plan it is not.
        let nextResetAt: Date?
    }

    /// A Coding Plan window: what is left, as StepFun states it, and when it
    /// resets.
    struct Window: Equatable, Sendable {
        let remainingFraction: Double
        let resetsAt: Date
    }

    enum Plan: Equatable, Sendable {
        /// The Token Plan. Buckets when the reply lists them; otherwise only
        /// the remaining fractions it states, which cannot be added together
        /// because their sizes are not given.
        case credits(buckets: [Bucket], subscriptionLeft: Double?, topUpLeft: Double?)
        /// The Coding Plan's two windows. Either may be absent.
        case windows(fiveHour: Window?, weekly: Window?)
    }

    let plan: Plan
    /// "Plus", "Mini" — the subscription's own name. Nil when the second
    /// request failed; the figures do not depend on it.
    var planName: String?
}

/// A read-only adapter for the console's route. Kept apart from the app so the
/// parsing is testable without a session.
struct StepFunClient: Sendable {
    /// Optional only as a test seam; production resolves the shared session at
    /// request time.
    var session: URLSession?

    func fetch(cookie: String, site: StepFunSite) async throws -> StepFunSnapshot {
        let header = try StepFunCookie.normalize(cookie)
        let data = try await post("QueryStepPlanRateLimit", header: header, site: site)
        var snapshot = try Self.parse(data)
        // The plan's name is a second request and a nicety. Its failure costs
        // the name and nothing else.
        if let status = try? await post("GetStepPlanStatus", header: header, site: site) {
            snapshot.planName = Self.planName(status)
        }
        return snapshot
    }

    private func post(_ method: String, header: String, site: StepFunSite) async throws -> Data {
        var request = URLRequest(url: site.endpoint(method))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue(header, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(site.origin, forHTTPHeaderField: "Origin")
        request.setValue(site.usagePage.absoluteString, forHTTPHeaderField: "Referer")
        // What the console's own request carries: its app id, its platform,
        // and the device the token belongs to. A token presented from another
        // device id is refused as stolen.
        request.setValue("10300", forHTTPHeaderField: "oasis-appid")
        request.setValue("web", forHTTPHeaderField: "oasis-platform")
        if let webid = StepFunCookie.webID(in: header) {
            request.setValue(webid, forHTTPHeaderField: "oasis-webid")
        }
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
            throw StepFunError.unreachable
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        // Signed out: `{"code":"unauthenticated","message":"auth failed: …"}`
        // with a 401, measured.
        case 401, 403: throw StepFunError.sessionExpired
        case 429: throw StepFunError.rateLimited
        case .some(500...599): throw StepFunError.serverError
        default: throw StepFunError.unreadableReply
        }
    }

    static func parse(_ data: Data) throws -> StepFunSnapshot {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StepFunError.unreadableReply
        }
        guard number(reply["status"]) == 1 else {
            // A refusal inside a 200. The console words an auth failure as
            // such; anything else is a reply this cannot use.
            let words = [reply["desc"], reply["message"], reply["code"]]
                .compactMap { $0 as? String }.joined(separator: " ").lowercased()
            throw words.contains("auth") || words.contains("token")
                ? StepFunError.sessionExpired : StepFunError.unreadableReply
        }

        let fiveHour = window(left: reply["five_hour_usage_left_rate"], reset: reply["five_hour_usage_reset_time"])
        let weekly = window(left: reply["weekly_usage_left_rate"], reset: reply["weekly_usage_reset_time"])
        // **Classified by what the reply carries, not by `plan_family`.** A
        // live window — a reset stated — is the Coding Plan; a Token Plan
        // sends its windows as zero with a reset of "0", which is "no window",
        // not "spent".
        if fiveHour != nil || weekly != nil {
            return StepFunSnapshot(plan: .windows(fiveHour: fiveHour, weekly: weekly))
        }

        let credit = reply["plan_credit_rate_limit"] as? [String: Any] ?? [:]
        let buckets = (credit["credit_buckets"] as? [[String: Any]] ?? []).compactMap { entry -> StepFunSnapshot.Bucket? in
            guard let total = number(entry["credit_total"]), total > 0,
                  let residual = number(entry["credit_residual"]), residual >= 0
            else { return nil }
            return .init(total: total, remaining: min(residual, total),
                         expiresAt: date(entry["expire_at"]), nextResetAt: date(entry["next_reset_at"]))
        }
        let subscriptionLeft = fraction(credit["subscription_credit_left_rate"])
        let topUpLeft = fraction(credit["topup_credit_left_rate"])
        guard !buckets.isEmpty || subscriptionLeft != nil else { throw StepFunError.noPlan }
        return StepFunSnapshot(plan: .credits(buckets: buckets, subscriptionLeft: subscriptionLeft, topUpLeft: topUpLeft))
    }

    /// `subscription.name` from `GetStepPlanStatus`, when the reply succeeded.
    static func planName(_ data: Data) -> String? {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(reply["status"]) == 1,
              let subscription = reply["subscription"] as? [String: Any],
              let name = subscription["name"] as? String
        else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
    }

    // MARK: - Values

    /// A window only when it states a reset: StepFun zeroes both fields for a
    /// window the plan does not have.
    private static func window(left: Any?, reset: Any?) -> StepFunSnapshot.Window? {
        guard let resetsAt = date(reset), let remaining = number(left), remaining.isFinite else { return nil }
        return .init(remainingFraction: min(max(remaining, 0), 1), resetsAt: resetsAt)
    }

    /// A stated fraction, 0…1. StepFun sends zero for "not on this plan" as
    /// well as for "none left", so a zero on its own is not taken as either.
    private static func fraction(_ value: Any?) -> Double? {
        guard let value = number(value), value.isFinite, value > 0 else { return nil }
        return min(value, 1)
    }

    /// Numbers arrive as JSON numbers or as decimal strings — the bucket sizes
    /// are strings, the rates are not.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    /// A Unix stamp in seconds or milliseconds. **Zero is no date**: StepFun
    /// writes "0" for every time it does not have.
    private static func date(_ value: Any?) -> Date? {
        guard let stamp = number(value), stamp.isFinite, stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp > 10_000_000_000 ? stamp / 1000 : stamp)
    }
}

struct StepFunUsageService: Sendable {
    let cookie: String?
    let site: StepFunSite
    var client = StepFunClient()

    func fetch() async -> ProviderUsage {
        var usage = await read()
        usage.sourceScope = Self.scope(site: site, cookie: cookie)
        return usage
    }

    /// Which site and which session a reading came from, for the cache. Named
    /// by its SHA-256, never by itself. See `QoderUsageService.scope`.
    static func scope(site: StepFunSite, cookie: String?) -> UsageScope? {
        guard let cookie, !cookie.isEmpty else { return nil }
        let fingerprint = SHA256.hash(data: Data(cookie.utf8)).map { String(format: "%02x", $0) }.joined()
        return UsageScope(route: .webSession, organization: site.host, identity: fingerprint)
    }

    private func read() async -> ProviderUsage {
        guard let cookie, !cookie.isEmpty else {
            return .unavailable(.stepFun, reason: .stepFunSessionMissing)
        }
        do {
            let snapshot = try await client.fetch(cookie: cookie, site: site)
            let now = Date()
            let windows = Self.windows(from: snapshot, at: now)
            guard !windows.isEmpty else { return .unavailable(.stepFun, reason: .stepFunNoPlan) }
            return .init(account: AccountKey(.stepFun),
                         windows: windows,
                         observedAt: now,
                         state: .live,
                         plan: snapshot.planName,
                         creditBalance: nil)
        } catch let error as StepFunError {
            let reason: ProviderUsage.Unavailability = switch error {
            case .missingCookie, .invalidCookie: .stepFunSessionMissing
            case .sessionExpired: .stepFunSessionExpired
            case .noPlan: .stepFunNoPlan
            case .rateLimited: .rateLimited
            case .serverError: .serverError
            case .unreadableReply: .unreadableReply
            case .unreachable: .unreachable
            }
            return .unavailable(.stepFun, reason: reason)
        } catch {
            return .unavailable(.stepFun, reason: .unreachable)
        }
    }

    static func windows(from snapshot: StepFunSnapshot, at now: Date) -> [UsageWindow] {
        switch snapshot.plan {
        case .windows(let fiveHour, let weekly):
            // The Coding Plan's two windows are the plan's stated lengths, so
            // they are reported ones.
            return [
                fiveHour.map { window($0, id: "stepfun.5h", kind: .fiveHour, seconds: 5 * 3600) },
                weekly.map { window($0, id: "stepfun.weekly", kind: .weekly, seconds: 7 * 86_400) },
            ].compactMap { $0 }

        case .credits(let buckets, let subscriptionLeft, let topUpLeft):
            if !buckets.isEmpty {
                // **One ring for the month's pool and any packs**, as Qoder's
                // plan-plus-packs total is: they are spent from one balance,
                // soonest-lapsing first, so what is left is their sum.
                let total = buckets.reduce(0) { $0 + $1.total }
                let remaining = buckets.reduce(0) { $0 + $1.remaining }
                return [UsageWindow(
                    id: "stepfun.credits",
                    kind: .credits,
                    scope: nil,
                    usedFraction: min(max((total - remaining) / total, 0), 1),
                    // Thirty days as a sort key, not a stated length: the
                    // pool is a month and a pack is its own thirty days,
                    // counted from different starts.
                    windowSeconds: 30 * 86_400,
                    // A refill the reply states and that is still ahead. A
                    // monthly plan states none: its pool simply ends, which
                    // is `nextExpiry`, not a reset.
                    resetsAt: buckets.compactMap(\.nextResetAt).filter { $0 > now }.min(),
                    reportsLength: false,
                    isExhausted: remaining <= 0,
                    nextExpiry: UsageWindow.Expiry.soonest(
                        of: buckets.compactMap { bucket in bucket.expiresAt.map { (bucket.remaining, $0) } },
                        after: now))]
            }
            // No sizes, only fractions. The subscription's is the plan; a
            // pack's fraction of an unstated size cannot be added to it.
            guard let left = subscriptionLeft ?? topUpLeft else { return [] }
            return [UsageWindow(id: "stepfun.credits", kind: .credits, scope: nil,
                                usedFraction: 1 - left, windowSeconds: 30 * 86_400,
                                resetsAt: nil, reportsLength: false, isExhausted: left <= 0)]
        }
    }

    private static func window(_ window: StepFunSnapshot.Window, id: String, kind: UsageWindow.Kind,
                               seconds: Int) -> UsageWindow {
        UsageWindow(id: id, kind: kind, scope: nil,
                    usedFraction: 1 - window.remainingFraction,
                    windowSeconds: seconds, resetsAt: window.resetsAt,
                    isExhausted: window.remainingFraction <= 0)
    }
}
