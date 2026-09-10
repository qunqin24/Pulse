import Foundation

/// The latest completed check, kept separately from the reading the cache chose.
struct ConnectionDiagnostic: Equatable, Sendable {
    struct Attempt: Equatable, Sendable {
        let route: UsageRoute
        let state: ProviderUsage.State
        var discardedForAccountMismatch = false

        var token: String {
            discardedForAccountMismatch ? "accountMismatch" : ConnectionDiagnostic.token(state)
        }

        var message: String {
            discardedForAccountMismatch
                ? .localized("Skipped: the desktop account does not match.")
                : ConnectionDiagnostic.message(state)
        }
    }

    let checkedAt: Date
    let state: ProviderUsage.State
    let attempts: [Attempt]
    let lastSuccessfulReadingAt: Date?

    init(raw: ProviderUsage, displayed: ProviderUsage, previous: Self?, now: Date) {
        checkedAt = now
        state = raw.state
        attempts = raw.attempts
        // A captured reading keeps its own timestamp. Re-reading it is not a
        // newly observed figure, and a newer cache may still outrank it.
        lastSuccessfulReadingAt = [
            previous?.lastSuccessfulReadingAt,
            raw.reportsSomething ? raw.observedAt : nil,
            displayed.reportsSomething ? displayed.observedAt : nil
        ].compactMap { $0 }.max()
    }

    /// A fixed allowlist, rather than redacting a dump of arbitrary app state.
    /// Account labels, ids, paths, plan names, balances and credentials never enter.
    static func report(
        account: AccountKey,
        preference: UsageSource,
        displayed: ProviderUsage,
        diagnostic: Self?,
        version: String,
        now: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        func stamp(_ date: Date?) -> String { date.map(formatter.string) ?? "unknown" }
        var lines = [
            "Pulse connection diagnostic (v1)",
            "version: \(version)",
            "generatedAt: \(stamp(now))",
            "provider: \(account.provider.rawValue)",
            "accountType: \(account.isPrimary ? "primary" : "added")",
            "preference: \(account.isPrimary ? preference.rawValue : "endpoint")",
            "checkedAt: \(stamp(diagnostic?.checkedAt))",
            "checkResult: \(diagnostic.map { token($0.state) } ?? "notChecked")",
            "displayState: \(token(displayed.state))",
            "displayOrigin: \(displayed.origin?.rawValue ?? "unknown")",
            "displayUsesCache: \(displayed.isCached)",
            "observedAt: \(stamp(displayed.observedAt))",
            "lastSuccessfulReadingAt: \(stamp(diagnostic?.lastSuccessfulReadingAt ?? displayed.observedAt))"
        ]
        for (index, attempt) in (diagnostic?.attempts ?? []).enumerated() {
            lines.append("route[\(index + 1)]: \(attempt.route.rawValue) -> \(attempt.token)")
        }
        return lines.joined(separator: "\n")
    }

    static func token(_ state: ProviderUsage.State) -> String {
        switch state {
        case .live: "live"
        case .stale: "stale"
        case .unavailable(let reason): reason.rawValue
        }
    }

    static func message(_ state: ProviderUsage.State) -> String {
        switch state {
        case .live: .localized("Reading received")
        case .stale: .localized("Older reading received")
        case .unavailable(let reason): reason.message
        }
    }
}
