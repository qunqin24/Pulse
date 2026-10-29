// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

extension ProviderProfile {
    static let dimAgent = ProviderProfile(
        displayName: "DimAgent",
        iconResource: "dimagent",
        credential: .localLogin,
        accessDescription: {
            .localized("Runs dim usage --json with the CLI's saved login. Pulse does not read or store its credentials.")
        },
        soleRoute: {
            ("Dim CLI", .localized("Uses the login saved by dim auth login."))
        },
        spendingIsWatchedLocally: false,
        expiresWholeBuckets: true,
        setupSlug: "dimagent",
        discoveryPaths: [".dimcode"],
        fetch: { await DimAgentUsageService.fetch($0) }
    )
}

enum DimAgentUsageService {
    static func fetch(_ context: ProfileContext) async -> ProviderUsage {
        guard let binary = CommandLocator.locate("dim", extra: [
            NSHomeDirectory() + "/.local/share/mise/shims/dim"
        ]) else { return context.unavailable(.localAppMissing) }
        switch await BoundedProcess.run(
            binary, ["usage", "--json"],
            environment: environment(for: binary),
            currentDirectory: FileManager.default.temporaryDirectory,
            deadline: 20, outputCeiling: 256 * 1024
        ) {
        case .success(let data): return reading(from: data, context: context)
        case .failure(.couldNotStart): return context.unavailable(.localAppMissing)
        case .failure(.timedOut): return context.unavailable(.unreachable)
        case .failure(.exited(_, let error)): return context.unavailable(exitReason(error))
        }
    }

    static func environment(for binary: URL, inherited: [String: String] = BoundedProcess.inheritedEnvironment,
                            home: String = NSHomeDirectory()) -> [String: String] {
        let allowed: Set<String> = ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
                                    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                                    "http_proxy", "https_proxy", "all_proxy", "no_proxy"]
        var result = inherited.filter { allowed.contains($0.key) }
        // GUI launches do not inherit the terminal's mise activation.
        result["PATH"] = ([home + "/.local/share/mise/shims", "/opt/homebrew/bin", "/usr/local/bin",
                           "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
                          + (inherited["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        return BoundedProcess.environment(leading: binary, over: result)
    }

    static func exitReason(_ error: String) -> ProviderUsage.Unavailability {
        let text = error.lowercased()
        if ["not logged in", "not signed in"].contains(where: text.contains) { return .localLoginMissing }
        if ["dim auth login", "unauthorized", "token expired"]
            .contains(where: text.contains) { return .localLoginExpired }
        if text.contains("429") || text.contains("rate limit") { return .rateLimited }
        return .unreachable
    }

    struct Reply: Decodable {
        struct Subscription: Decodable {
            struct Product: Decodable { let name: String? }
            let product: Product?
        }
        struct Credits: Decodable {
            let subscription_bucket: Bucket?
            let addon_buckets: [Bucket]?
        }
        let subscription: Subscription?
        let credits: Credits?
        let feature_meters: [Meter]?
    }

    struct Bucket: Decodable {
        let id: Int?
        let total_units: Double?
        let used_units: Double?
        let remaining_units: Double?
        let expires_at: String?
        let status: String?
        let window_states: [TokenWindow]?
    }

    struct TokenWindow: Decodable {
        let id: Int?
        let window_duration_hours: Double?
        let window_token_cap: Double?
        let window_token_used: Double?
        let window_expires_at: String?
    }

    struct Meter: Decodable {
        let feature_key: String?
        let total_allowance: Double?
        let total_used: Double?
        let total_remaining: Double?
        let unlimited: Bool?
        let period_end: String?
    }

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return context.unavailable(.unreadableReply)
        }
        var windows: [UsageWindow] = []
        if let bucket = reply.credits?.subscription_bucket,
           let window = window(bucket, id: "dimagent.subscription", kind: .planCredits, now: now) {
            windows.append(window)
            windows += tokenWindows(bucket, parent: window.id, now: now)
        }
        // Packs have separate expiry dates; never add them to the subscription denominator.
        for bucket in reply.credits?.addon_buckets ?? [] {
            guard let id = bucket.id,
                  let window = window(bucket, id: "dimagent.addon.\(id)", kind: .topUp, now: now),
                  !windows.contains(where: { $0.id == window.id }) else { continue }
            windows.append(window)
            windows += tokenWindows(bucket, parent: window.id, now: now)
        }
        for meter in reply.feature_meters ?? [] where meter.feature_key == "web_search" && meter.unlimited != true {
            guard let amounts = amounts(used: meter.total_used, remaining: meter.total_remaining,
                                        total: meter.total_allowance),
                  !windows.contains(where: { $0.id == "dimagent.web_search" }) else { continue }
            windows.append(UsageWindow(
                id: "dimagent.web_search", kind: .credits, scope: "Web Search",
                usedFraction: amounts.used / amounts.limit, windowSeconds: 0,
                resetsAt: ProfileHTTP.date(meter.period_end), reportsLength: false, amounts: amounts
            ))
        }
        guard !windows.isEmpty else { return context.unavailable(.noLimitsReported) }
        return context.reading(windows, plan: reply.subscription?.product?.name, at: now)
    }

    private static func window(_ bucket: Bucket, id: String, kind: UsageWindow.Kind, now: Date) -> UsageWindow? {
        guard bucket.status == "active" || bucket.status == "exhausted",
              let amounts = amounts(used: bucket.used_units, remaining: bucket.remaining_units,
                                    total: bucket.total_units) else { return nil }
        let expiry = ProfileHTTP.date(bucket.expires_at)
        guard expiry.map({ $0 > now && amounts.remaining != nil }) ?? true else { return nil }
        return UsageWindow(
            id: id, kind: kind, scope: nil, usedFraction: amounts.used / amounts.limit,
            windowSeconds: 0, resetsAt: nil, reportsLength: false,
            isExhausted: bucket.status == "exhausted",
            nextExpiry: expiry.flatMap { date in
                amounts.remaining.map { UsageWindow.Expiry(amount: $0, at: date, coversRemainder: true) }
            }, amounts: amounts, cycleID: bucket.id.map { "bucket:\($0)" }
        )
    }

    private static func tokenWindows(_ bucket: Bucket, parent: String, now: Date) -> [UsageWindow] {
        var occurrences: [String: Int] = [:]
        return (bucket.window_states ?? []).compactMap { token in
            guard let hours = token.window_duration_hours, hours.isFinite, hours > 0,
                  hours <= Double(UsageWindow.longestLength) / 3600,
                  let seconds = Int(exactly: hours * 3600),
                  let length = UsageWindow.length(seconds, unitSeconds: 1),
                  let amounts = amounts(used: token.window_token_used, remaining: nil,
                                        total: token.window_token_cap) else { return nil }
            let key = token.id.map { "id:\($0)" } ?? "seconds:\(length)"
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            let reset = ProfileHTTP.date(token.window_expires_at)
            guard token.window_expires_at == nil || reset != nil,
                  reset.map({ $0 > now }) ?? true else { return nil }
            let kind: UsageWindow.Kind = switch length {
            case 18_000: .fiveHour
            case 86_400: .daily
            case 604_800: .weekly
            default: .other(seconds: length)
            }
            return UsageWindow(
                id: "\(parent).tokens.\(key).\(occurrence)", kind: kind, scope: nil,
                usedFraction: amounts.used / amounts.limit, windowSeconds: length,
                resetsAt: reset,
                nextExpiry: ProfileHTTP.date(bucket.expires_at).map {
                    UsageWindow.Expiry(amount: max(0, amounts.limit - amounts.used), at: $0, coversRemainder: true)
                }, amounts: amounts, cycleID: bucket.id.map { "bucket:\($0)" }
            )
        }
    }

    private static func amounts(used: Double?, remaining: Double?, total: Double?) -> UsageWindow.Amounts? {
        guard let used, used.isFinite, used >= 0, let total, total.isFinite, total > 0,
              (used / total).isFinite,
              remaining.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        return UsageWindow.Amounts(used: used, remaining: remaining, limit: total)
    }
}
