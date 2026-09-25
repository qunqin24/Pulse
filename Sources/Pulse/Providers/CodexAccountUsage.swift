import Foundation

/// Codex's account-level history: how many tokens went through, day by day,
/// plus the one-off credits that reset a rate limit early.
///
/// This is background rather than at-a-glance, so it lives in settings and is
/// fetched when that pane is opened — not on the panel's refresh loop.
///
/// Codex reports tokens here and never money, so the cost shown alongside it
/// in settings comes from `UsageLedger` instead — the local transcripts, which
/// record which model ran, priced at the rates `ModelPrices` publishes. What
/// stays here is what only Codex knows: the account's real lifetime total, and
/// the reset credits.
struct CodexAccountUsage: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        let date: Date
        let tokens: Int

        var id: Date { date }
    }

    /// A credit that clears a rate limit ahead of its reset.
    struct ResetCredit: Equatable, Sendable {
        let title: String
        let expiresAt: Date?
    }

    let days: [Day]
    let lifetimeTokens: Int
    let peakDailyTokens: Int
    let currentStreakDays: Int
    let longestStreakDays: Int
    let availableResetCredits: Int
    /// The credit expiring soonest, which is the one worth spending first.
    let nextExpiringCredit: ResetCredit?

    var todayTokens: Int { days.last?.tokens ?? 0 }

    func tokens(overLast days: Int) -> Int {
        self.days.suffix(days).reduce(0) { $0 + $1.tokens }
    }

    /// The tail of the history, for the chart.
    func recent(_ count: Int) -> [Day] { Array(days.suffix(count)) }
}

/// The reset credits alone, as the card shows them.
///
/// **What Codex said, or that it said nothing.** `unreported` is a reply with
/// no reset-credit block in it, or no app server to ask; it is shown as "Not
/// available" rather than a count Pulse worked out.
enum CodexResetCredits: Equatable, Sendable {
    case available(count: Int, nextExpiry: Date?)
    case unreported
    /// No `codex` anywhere Pulse looks, so nothing was asked. Said apart from
    /// `unreported` because the remedy is different, and "Not available" for
    /// both left two Macs with several credits guessing which (issue #67).
    case codexMissing
}

/// Reads `account/usage/read` and the reset credits from `codex app-server`.
///
/// Only the app server offers these — the usage endpoint the panel normally
/// uses carries limits, not history — so this is unavailable when the `codex`
/// command can't be found.
struct CodexAccountUsageService: Sendable {
    let server: CodexAppServer

    func fetch() async -> CodexAccountUsage? {
        async let usage = server.accountUsage()
        async let limits = server.rateLimits()

        guard
            let usageData = try? await usage,
            let usageRoot = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any]
        else { return nil }

        let limitsRoot = (try? await limits)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        return parse(usage: usageRoot, limits: limitsRoot)
    }

    /// Only the reset credits, from `account/rateLimits/read` — what the card
    /// asks for on every Codex refresh while its switch is on. One call, not
    /// the history's two.
    func resetCredits() async -> CodexResetCredits {
        let data: Data
        do {
            data = try await server.rateLimits()
        } catch CodexAppServer.Failure.executableNotFound {
            return .codexMissing
        } catch {
            return .unreported
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreported }
        return Self.resetCredits(in: root)
    }

    /// Internal and static so the parsing is testable without a server.
    static func resetCredits(in limits: [String: Any]) -> CodexResetCredits {
        guard let credits = limits["rateLimitResetCredits"] as? [String: Any] else { return .unreported }
        let available = availableCredits(in: limits)
        // `Int(_:)` traps past its range, and a number in somebody's JSON is
        // not bounded by anything.
        let stated = number(credits["availableCount"]).flatMap { $0.isFinite && $0 >= 0 && $0 < 1_000_000 ? Int($0) : nil }
        guard let count = stated ?? (credits["credits"] != nil ? available.count : nil)
        else { return .unreported }
        let soonest = available.compactMap { number($0["expiresAt"]).map { Date(timeIntervalSince1970: $0) } }.min()
        return .available(count: count, nextExpiry: soonest)
    }

    /// The credits Codex lists as available, and none of the rest.
    private static func availableCredits(in limits: [String: Any]) -> [[String: Any]] {
        ((limits["rateLimitResetCredits"] as? [String: Any])?["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String) == "available" }
    }

    private func parse(usage: [String: Any], limits: [String: Any]) -> CodexAccountUsage {
        let summary = usage["summary"] as? [String: Any] ?? [:]

        let days = (usage["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> CodexAccountUsage.Day? in
            guard
                let text = bucket["startDate"] as? String,
                let date = Self.dayFormatter.date(from: text),
                let tokens = Self.number(bucket["tokens"])
            else { return nil }
            return CodexAccountUsage.Day(date: date, tokens: Int(tokens))
        }

        // The count, from the one reading of it the card uses too, so the two
        // cannot disagree about a reply. Settings hides the row at zero, which
        // is also how it shows a reply that stated none.
        let count: Int = switch Self.resetCredits(in: limits) {
        case .available(let count, _): count
        case .unreported, .codexMissing: 0
        }

        // The one expiring soonest is the one worth spending first — with its
        // title, which only this pane shows.
        let soonest = Self.availableCredits(in: limits)
            .compactMap { credit -> CodexAccountUsage.ResetCredit? in
                guard let title = credit["title"] as? String else { return nil }
                return CodexAccountUsage.ResetCredit(
                    title: title,
                    expiresAt: Self.number(credit["expiresAt"]).map { Date(timeIntervalSince1970: $0) }
                )
            }
            .min { lhs, rhs in
                (lhs.expiresAt ?? .distantFuture) < (rhs.expiresAt ?? .distantFuture)
            }

        return CodexAccountUsage(
            days: days,
            lifetimeTokens: Int(Self.number(summary["lifetimeTokens"]) ?? 0),
            peakDailyTokens: Int(Self.number(summary["peakDailyTokens"]) ?? 0),
            currentStreakDays: Int(Self.number(summary["currentStreakDays"]) ?? 0),
            longestStreakDays: Int(Self.number(summary["longestStreakDays"]) ?? 0),
            availableResetCredits: count,
            nextExpiringCredit: soonest
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }
}
