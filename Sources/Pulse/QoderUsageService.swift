import Foundation

/// Qoder's plan Credits, from the signed-in account dashboard.
///
/// There is no public personal quota API. The dashboard JSON the website
/// itself loads is the figure Qoder reports (`usedValue` / `limitValue` and
/// an optional reset). Pulse does not invent a percentage from local work.
///
/// Credentials, in this order: a **personal access token** (`pt-…`) if the
/// stored string is one, otherwise a **browser session** for `qoder.com` /
/// `qoder.com.cn`. Tokens last for the expiry the console set; cookies expire
/// and have to be read again. The CLI's `~/.qoder/.auth` file is encrypted
/// and is not borrowed.
struct QoderUsageService: Sendable {
    let cookie: String?

    func fetch() async -> ProviderUsage {
        guard let raw = cookie.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.qoder, reason: .qoderSessionMissing)
        }

        let token = QoderSessionCookie.accessToken(in: raw)
        let header = token == nil ? (try? QoderSessionCookie.normalize(raw)) : nil
        guard token != nil || header != nil else {
            return .unavailable(.qoder, reason: .qoderSessionMissing)
        }

        // Team Plan and Add-on Credits are **two JSON documents**.
        // `…/usages/big_model_credits` is only the plan (the 6,000 on a Team
        // card). The 314,000 Add-on bar is `…/organization-shared-usages/…`.
        // Measured 2026-09-08 against a signed-in usage page.
        let origins = ["https://qoder.com", "https://qoder.com.cn"]
        var sawExpiry = false
        for origin in origins {
            let planURL = URL(string: "\(origin)/api/v2/me/usages/big_model_credits")!
            let sharedURL = URL(string: "\(origin)/api/v1/me/organization-shared-usages/big_model_credits")!
            switch await load(url: planURL, origin: origin, token: token, cookie: header) {
            case .ok(let plan):
                let shared: Reply?
                if case .ok(let extra) = await load(url: sharedURL, origin: origin, token: token, cookie: header) {
                    shared = extra
                } else {
                    shared = nil
                }
                let windows = Self.windows(from: plan, shared: shared)
                guard !windows.isEmpty else {
                    return .unavailable(.qoder, reason: .noLimitsReported)
                }
                return ProviderUsage(
                    account: AccountKey(.qoder),
                    windows: windows,
                    observedAt: Date(),
                    state: .live,
                    plan: plan.userType,
                    creditBalance: nil
                )
            case .expired, .missing:
                sawExpiry = true
            case .failed(let usage):
                return usage
            }
        }
        return .unavailable(.qoder, reason: sawExpiry ? .qoderSessionExpired : .unreachable)
    }

    private enum Load {
        case ok(Reply)
        case expired
        case missing
        case failed(ProviderUsage)
    }

    private func load(url: URL, origin: String, token: String?, cookie: String?) async -> Load {
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/account/usage", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failed(.unavailable(.qoder, reason: .unreachable))
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .expired
        case 404: return .missing
        case 429: return .failed(.unavailable(.qoder, reason: .rateLimited))
        default: return .failed(.unavailable(.qoder, reason: .serverError))
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .failed(.unavailable(.qoder, reason: .unreadableReply))
        }
        return .ok(reply)
    }

    /// Internal so a fixture test can hold it. Not a public contract.
    struct Reply: Decodable {
        struct Summary: Decodable {
            let usedValue: Double?
            let limitValue: Double?
            let remainingValue: Double?
            let unit: String?

            enum CodingKeys: String, CodingKey {
                case usedValue, limitValue, remainingValue, unit
                case used_value, limit_value, remaining_value
                case used, total, remaining, cap
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                usedValue = Self.number(c, .usedValue) ?? Self.number(c, .used_value) ?? Self.number(c, .used)
                limitValue = Self.number(c, .limitValue) ?? Self.number(c, .limit_value)
                    ?? Self.number(c, .total) ?? Self.number(c, .cap)
                remainingValue = Self.number(c, .remainingValue) ?? Self.number(c, .remaining_value)
                    ?? Self.number(c, .remaining)
                unit = try c.decodeIfPresent(String.self, forKey: .unit)
            }

            private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
                if let value = try? c.decode(Double.self, forKey: key) { return value }
                if let value = try? c.decode(Int.self, forKey: key) { return Double(value) }
                if let value = try? c.decode(String.self, forKey: key) { return Double(value) }
                return nil
            }
        }

        struct Quota: Decodable {
            let quotaSummary: Summary?

            enum CodingKeys: String, CodingKey {
                case quotaSummary, quota_summary
            }

            init(from decoder: Decoder) throws {
                // Dashboard JSON wraps figures in quotaSummary. The CLI
                // snapshot (`org_resource_package`) is flat: cap / used /
                // remaining. Both are the same Credits the user is asking to see.
                if let nested = try? decoder.container(keyedBy: CodingKeys.self),
                   let summary = try nested.decodeIfPresent(Summary.self, forKey: .quotaSummary)
                    ?? nested.decodeIfPresent(Summary.self, forKey: .quota_summary) {
                    quotaSummary = summary
                    return
                }
                quotaSummary = try Summary(from: decoder)
            }
        }

        let planQuota: Quota?
        let totalQuota: Quota?
        let sharedQuota: Quota?
        let addOnQuota: Quota?
        let userQuota: Quota?
        let orgResourcePackage: Quota?
        let userType: String?
        let nextResetAt: Date?

        enum CodingKeys: String, CodingKey {
            case planQuota, totalQuota, sharedQuota, addOnQuota, userQuota, orgResourcePackage, userType, nextResetAt
            case plan_quota, total_quota, shared_quota, add_on_quota, user_quota, org_resource_package, user_type, next_reset_at
            case resourcePackageQuota, resource_package_quota
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            planQuota = try c.decodeIfPresent(Quota.self, forKey: .planQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .plan_quota)
            totalQuota = try c.decodeIfPresent(Quota.self, forKey: .totalQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .total_quota)
                ?? c.decodeIfPresent(Quota.self, forKey: .userQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .user_quota)
            sharedQuota = try c.decodeIfPresent(Quota.self, forKey: .sharedQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .shared_quota)
                ?? c.decodeIfPresent(Quota.self, forKey: .orgResourcePackage)
                ?? c.decodeIfPresent(Quota.self, forKey: .org_resource_package)
            addOnQuota = try c.decodeIfPresent(Quota.self, forKey: .addOnQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .add_on_quota)
                ?? c.decodeIfPresent(Quota.self, forKey: .resourcePackageQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .resource_package_quota)
            userQuota = try c.decodeIfPresent(Quota.self, forKey: .userQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .user_quota)
            orgResourcePackage = try c.decodeIfPresent(Quota.self, forKey: .orgResourcePackage)
                ?? c.decodeIfPresent(Quota.self, forKey: .org_resource_package)
            userType = try c.decodeIfPresent(String.self, forKey: .userType)
                ?? c.decodeIfPresent(String.self, forKey: .user_type)
            nextResetAt = Self.date(c, .nextResetAt) ?? Self.date(c, .next_reset_at)
        }

        private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
            if let text = try? c.decode(String.self, forKey: key) {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: text) { return date }
                fractional.formatOptions = [.withInternetDateTime]
                return fractional.date(from: text)
            }
            if let value = try? c.decode(Double.self, forKey: key) {
                let seconds = value > 10_000_000_000 ? value / 1_000 : value
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = try? c.decode(Int.self, forKey: key) {
                let seconds = value > 10_000_000_000 ? Double(value) / 1_000 : Double(value)
                return Date(timeIntervalSince1970: seconds)
            }
            return nil
        }
    }

    /// Internal so a fixture test can hold it. Not a public contract.
    static func windows(from reply: Reply) -> [UsageWindow] {
        windows(from: reply, shared: nil)
    }

    /// Team Plan and Add-on Credits are two JSON documents. The shared one
    /// has no `nextResetAt`; both bars turn over on the same date, so the
    /// plan's reset is copied onto any extra window that arrived without one.
    static func windows(from plan: Reply, shared: Reply?) -> [UsageWindow] {
        var windows = decodeWindows(plan)
        if let shared {
            for extra in decodeWindows(shared) where !windows.contains(where: { $0.id == extra.id }) {
                windows.append(extra)
            }
        }
        return inheritingReset(windows)
    }

    private static func decodeWindows(_ reply: Reply) -> [UsageWindow] {
        [
            window(
                id: "qoder.plan",
                summary: reply.planQuota?.quotaSummary
                    ?? reply.totalQuota?.quotaSummary
                    ?? reply.userQuota?.quotaSummary,
                resetsAt: reply.nextResetAt,
                scope: "Team Plan"
            ),
            window(
                id: "qoder.addon",
                summary: reply.addOnQuota?.quotaSummary,
                resetsAt: reply.nextResetAt,
                scope: "Add-on"
            ),
            window(
                id: "qoder.shared",
                summary: reply.sharedQuota?.quotaSummary ?? reply.orgResourcePackage?.quotaSummary,
                resetsAt: reply.nextResetAt,
                scope: "Add-on Credits"
            ),
        ].compactMap { $0 }
    }

    /// Add-on Credits is a second document with no reset of its own. The
    /// usage page shows the same date on both bars (measured 2026-09-08).
    private static func inheritingReset(_ windows: [UsageWindow]) -> [UsageWindow] {
        guard let reset = windows.first(where: { $0.resetsAt != nil })?.resetsAt else {
            return windows
        }
        return windows.map { window in
            guard window.resetsAt == nil else { return window }
            return window.with(resetsAt: reset)
        }
    }

    private static func window(
        id: String,
        summary: Reply.Summary?,
        resetsAt: Date?,
        scope: String? = nil
    ) -> UsageWindow? {
        guard let summary, let limit = summary.limitValue, limit > 0 else { return nil }
        let used = max(summary.usedValue ?? 0, 0)
        let remaining = summary.remainingValue ?? max(limit - used, 0)
        return UsageWindow(
            id: id,
            kind: .monthly,
            scope: scope,
            usedFraction: used / limit,
            windowSeconds: 30 * 86_400,
            resetsAt: resetsAt,
            reportsLength: false,
            isExhausted: remaining <= 0 || used >= limit
        )
    }

}

/// Retain cookies that can authenticate a Qoder dashboard request.
///
/// The host is already chosen by `BrowserCookies`. Names are not published,
/// so every well-formed pair from that host is kept — the same safety checks
/// as Ollama (printable, no injection, a size cap), without guessing a name.
enum QoderSessionCookie {
    /// A console PAT (`pt-…`) lasts for the expiry the user set. A cookie
    /// header always contains `=`.
    static func accessToken(in raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("pt-") || trimmed.hasPrefix("jt-") { return trimmed }
        return nil
    }

    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw QoderCookieError.invalid
        }
        var header = input.trimmingCharacters(in: .whitespaces)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw QoderCookieError.missing }
        guard header.utf8.count <= 32_768 else { throw QoderCookieError.invalid }

        var found: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty,
                  !value.contains("\""), !value.contains("\\"), !value.contains(" ")
            else { continue }
            guard seen.insert(name).inserted else { continue }
            found.append("\(name)=\(value)")
        }
        guard !found.isEmpty else { throw QoderCookieError.missing }
        return found.joined(separator: "; ")
    }

    enum QoderCookieError: Error {
        case missing, invalid
    }
}
