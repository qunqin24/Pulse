import Foundation

/// Kiro subscription credits, read through Kiro CLI's native ACP process.
/// Kiro owns authentication and refresh; Pulse never reads its tokens.
struct KiroUsageService: Sendable {
    let client: KiroACPClient

    init(client: KiroACPClient = KiroACPClient()) {
        self.client = client
    }

    func fetch() async -> ProviderUsage {
        let data: Data
        do {
            data = try await client.usage()
        } catch let failure as KiroACPClient.Failure {
            return .unavailable(.kiro, reason: Self.reason(for: failure)).recording(.kiroACP)
        } catch {
            return .unavailable(.kiro, reason: .unreachable).recording(.kiroACP)
        }

        guard let result = try? JSONDecoder().decode(Result.self, from: data) else {
            return .unavailable(.kiro, reason: .unreadableReply).recording(.kiroACP)
        }
        guard result.success else {
            return .unavailable(.kiro, reason: Self.reason(for: result.message)).recording(.kiroACP)
        }
        guard let payload = result.data else {
            return .unavailable(.kiro, reason: .noLimitsReported).recording(.kiroACP)
        }

        let windows = Self.windows(from: payload)
        guard !windows.isEmpty else {
            return .unavailable(.kiro, reason: .noLimitsReported).recording(.kiroACP)
        }

        return ProviderUsage(
            account: AccountKey(.kiro),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: payload.planName,
            creditBalance: nil
        ).recording(.kiroACP)
    }

    struct Result: Decodable, Sendable {
        let success: Bool
        let message: String?
        let data: Payload?
    }

    struct Payload: Decodable, Sendable {
        let planName: String?
        let billingCycleReset: String?
        let usageBreakdowns: [Breakdown]
    }

    struct Breakdown: Decodable, Sendable {
        let resourceType: String?
        let displayName: String?
        let used: Double?
        let limit: Double?
        let percentage: Double?
        let hasLimit: Bool?
    }

    static func windows(from payload: Payload) -> [UsageWindow] {
        let reset = payload.billingCycleReset.flatMap(date(from:))
        return payload.usageBreakdowns.enumerated().compactMap { index, item in
            guard item.hasLimit != false, let limit = item.limit, limit.isFinite, limit > 0 else { return nil }
            let used: Double
            if let reported = item.used, reported.isFinite {
                used = reported
            } else if let percent = item.percentage, percent.isFinite {
                used = percent / 100 * limit
            } else {
                return nil
            }
            let resource = item.resourceType?.lowercased() ?? "usage"
            return UsageWindow(
                id: "\(resource).\(index)",
                kind: .monthly,
                scope: item.displayName ?? item.resourceType,
                usedFraction: min(max(used / limit, 0), 1),
                windowSeconds: 30 * 86_400,
                resetsAt: reset,
                reportsLength: false,
                isExhausted: used >= limit
            )
        }
    }

    static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func reason(for failure: KiroACPClient.Failure) -> ProviderUsage.Unavailability {
        switch failure {
        case .executableNotFound: .kiroNotInstalled
        case .server(let message): reason(for: message)
        case .startFailed, .timedOut, .closed: .unreachable
        }
    }

    static func reason(for message: String?) -> ProviderUsage.Unavailability {
        let text = message?.lowercased() ?? ""
        if text.contains("sign in") || text.contains("not authenticated") || text.contains("login") {
            return .kiroSignInRequired
        }
        if text.contains("method not found") || text.contains("unsupported") || text.contains("agent-engine") {
            return .kiroVersionUnsupported
        }
        return .unreadableReply
    }
}
