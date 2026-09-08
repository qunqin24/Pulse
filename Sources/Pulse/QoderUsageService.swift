import Foundation

/// Qoder's plan Credits, from the signed-in account dashboard.
///
/// There is no public personal quota API. The dashboard JSON the website
/// itself loads is the figure Qoder reports (`usedValue` / `limitValue` and
/// an optional reset). Pulse does not invent a percentage from local work.
///
/// The credential is a **browser session**, same arrangement as Ollama Cloud:
/// Settings reads the cookies for `qoder.com` or `qoder.com.cn` and stores
/// the header in `keys.dat`. The CLI's `~/.qoder/.auth` file is encrypted and
/// is not borrowed.
struct QoderUsageService: Sendable {
    let cookie: String?

    private static let international = URL(string: "https://qoder.com/api/v2/me/usages/big_model_credits")!
    private static let china = URL(string: "https://qoder.com.cn/api/v2/me/usages/big_model_credits")!

    func fetch() async -> ProviderUsage {
        guard let cookie = cookie.flatMap({ $0.isEmpty ? nil : $0 }) else {
            return .unavailable(.qoder, reason: .qoderSessionMissing)
        }

        guard let header = try? QoderSessionCookie.normalize(cookie) else {
            return .unavailable(.qoder, reason: .qoderSessionMissing)
        }

        let first = await fetch(url: Self.international, origin: "https://qoder.com", cookie: header)
        switch first {
        case .success(let usage): return usage
        case .expired, .missing:
            break
        case .other(let usage):
            return usage
        }

        let second = await fetch(url: Self.china, origin: "https://qoder.com.cn", cookie: header)
        switch second {
        case .success(let usage): return usage
        case .expired, .missing:
            return .unavailable(.qoder, reason: .qoderSessionExpired)
        case .other(let usage):
            return usage
        }
    }

    private enum Attempt {
        case success(ProviderUsage)
        case expired
        case missing
        case other(ProviderUsage)
    }

    private func fetch(url: URL, origin: String, cookie: String) async -> Attempt {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/account/usage", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .other(.unavailable(.qoder, reason: .unreachable))
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .expired
        case 404: return .missing
        case 429: return .other(.unavailable(.qoder, reason: .rateLimited))
        default: return .other(.unavailable(.qoder, reason: .serverError))
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return .other(.unavailable(.qoder, reason: .unreadableReply))
        }

        let windows = Self.windows(from: reply)
        guard !windows.isEmpty else {
            return .other(.unavailable(.qoder, reason: .noLimitsReported))
        }

        return .success(ProviderUsage(
            account: AccountKey(.qoder),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: reply.userType,
            creditBalance: Self.balance(from: reply)
        ))
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
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                usedValue = Self.number(c, .usedValue) ?? Self.number(c, .used_value)
                limitValue = Self.number(c, .limitValue) ?? Self.number(c, .limit_value)
                remainingValue = Self.number(c, .remainingValue) ?? Self.number(c, .remaining_value)
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
                let c = try decoder.container(keyedBy: CodingKeys.self)
                quotaSummary = try c.decodeIfPresent(Summary.self, forKey: .quotaSummary)
                    ?? c.decodeIfPresent(Summary.self, forKey: .quota_summary)
            }
        }

        let totalQuota: Quota?
        let sharedQuota: Quota?
        let userType: String?
        let nextResetAt: Date?

        enum CodingKeys: String, CodingKey {
            case totalQuota, sharedQuota, userType, nextResetAt
            case total_quota, shared_quota, user_type, next_reset_at
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            totalQuota = try c.decodeIfPresent(Quota.self, forKey: .totalQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .total_quota)
            sharedQuota = try c.decodeIfPresent(Quota.self, forKey: .sharedQuota)
                ?? c.decodeIfPresent(Quota.self, forKey: .shared_quota)
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
            return nil
        }
    }

    /// Internal so a fixture test can hold it. Not a public contract.
    static func windows(from reply: Reply) -> [UsageWindow] {
        [
            window(id: "qoder.plan", summary: reply.totalQuota?.quotaSummary, resetsAt: reply.nextResetAt),
            window(id: "qoder.shared", summary: reply.sharedQuota?.quotaSummary, resetsAt: reply.nextResetAt, scope: "Shared"),
        ].compactMap { $0 }
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

    private static func balance(from reply: Reply) -> String? {
        let remaining = [reply.totalQuota?.quotaSummary, reply.sharedQuota?.quotaSummary]
            .compactMap { summary -> Double? in
                guard let summary, let limit = summary.limitValue, limit > 0 else { return nil }
                return summary.remainingValue ?? max(limit - (summary.usedValue ?? 0), 0)
            }
            .reduce(0, +)
        guard remaining > 0 else { return nil }
        let unit = reply.totalQuota?.quotaSummary?.unit
            ?? reply.sharedQuota?.quotaSummary?.unit
            ?? "credits"
        if remaining.rounded() == remaining {
            return "\(Int(remaining)) \(unit)"
        }
        return String(format: "%.2f %@", remaining, unit)
    }
}

/// Retain cookies that can authenticate a Qoder dashboard request.
///
/// The host is already chosen by `BrowserCookies`. Names are not published,
/// so every well-formed pair from that host is kept — the same safety checks
/// as Ollama (printable, no injection, a size cap), without guessing a name.
enum QoderSessionCookie {
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
