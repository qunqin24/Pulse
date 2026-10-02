// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Alibaba Cloud's Token Plan (Model Studio / Bailian): a five-hour, a weekly
/// and a monthly allowance, each reported by the service as the share of it
/// already used.
///
/// Read by running Alibaba's own Bailian CLI, `bl`, with the login it already
/// saved: `bl usage token-plan --console-region … --console-site … --output
/// json`. Pulse passes it no credential and reads none of its files. The
/// international console is asked first and the China mainland one second,
/// because a login belongs to one site and nothing on this Mac says which.
/// The shape is second-hand — taken from CodexBar's Alibaba Token Plan
/// provider and its tests, not from a captured run.
///
/// **What is left out.** A Team plan's shared credit pool is read by CodexBar
/// from the console with a browser session, on a site the reader picks; that
/// needs a region choice Pulse has no control for, so it is not read here. A
/// CLI output with no rolling windows says so as "No limits reported". The
/// monthly window needs a recent `bl`: older ones print only the five-hour and
/// weekly figures, and the monthly row is then absent rather than guessed.
extension ProviderProfile {
    static let alibabaTokenPlan = ProviderProfile(
        displayName: "Alibaba Token Plan",
        iconResource: "alibabacloud",
        credential: .localLogin,
        accessDescription: {
            .localized("Runs the Bailian CLI (bl) with its saved login. Pulse does not read or store its credentials.")
        },
        soleRoute: {
            (.localized("Bailian CLI"), .localized("Uses the login the Bailian CLI already saved."))
        },
        brandColor: 0xFF6A00,
        setupSlug: "alibaba-token-plan",
        fetch: { await AlibabaTokenPlanUsageService.fetch($0) }
    )
}

enum AlibabaTokenPlanUsageService {
    /// The two consoles, in the CLI's own words for them.
    static let sites: [(site: String, region: String)] = [
        ("international", "ap-southeast-1"),
        ("domestic", "cn-beijing"),
    ]

    static func arguments(site: String, region: String) -> [String] {
        ["usage", "token-plan", "--console-region", region, "--console-site", site, "--output", "json"]
    }

    static func fetch(_ context: ProfileContext) async -> ProviderUsage {
        guard let binary = locateCLI() else { return context.unavailable(.localLoginMissing) }

        var firstReason: ProviderUsage.Unavailability?
        for (site, region) in sites {
            let usage = switch await run(binary, arguments(site: site, region: region)) {
            case .success(let output): reading(from: output, context: context)
            case .failure(let reason): context.unavailable(reason)
            }
            guard case .unavailable(let reason) = usage.state else { return usage }
            // A CLI that cannot be started will not start for the other site.
            if reason == .localLoginMissing { return usage }
            guard let first = firstReason else {
                firstReason = reason
                continue
            }
            // The site the login does not belong to refuses it; the one it
            // does belong to says more, whatever it says.
            return context.unavailable(reason == .localLoginExpired ? first : reason)
        }
        return context.unavailable(firstReason ?? .unreadableReply)
    }

    // MARK: - The CLI

    /// A GUI app inherits almost no `PATH`, so the usual install locations are
    /// checked by hand, as `VolcengineUsageService.locateArkcli` does.
    static func locateCLI() -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/bl" }
        }
        candidates += [
            "\(home)/.local/bin/bl",
            "\(home)/.npm-global/bin/bl",
            "\(home)/.bun/bin/bl",
            "/opt/homebrew/bin/bl",
            "/usr/local/bin/bl",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static let deadline: TimeInterval = 15
    private static let outputCeiling = 256 * 1024

    /// Only what the CLI needs to find itself, its login and the network.
    /// Keys, cookies and cloud credentials in Pulse's own environment never
    /// cross into it.
    static func environment(for binary: URL) -> [String: String] {
        let inherited = BoundedProcess.inheritedEnvironment
        let kept: Set<String> = [
            "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
        ]
        var environment = inherited.filter { kept.contains($0.key) }
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (directories + (inherited["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        // The CLI may be a script whose interpreter sits beside it.
        return BoundedProcess.environment(leading: binary, over: environment)
    }

    static func run(_ binary: URL, _ arguments: [String]) async -> Result<Data, ProviderUsage.Unavailability> {
        switch await BoundedProcess.run(
            binary, arguments,
            environment: environment(for: binary),
            deadline: deadline,
            outputCeiling: outputCeiling
        ) {
        case .success(let data): .success(data)
        case .failure(.couldNotStart): .failure(.localLoginMissing)
        case .failure(.timedOut): .failure(.unreachable)
        case .failure(.exited(_, let problem)): .failure(reason(forExitOf: problem))
        }
    }

    /// Why the CLI stopped, as far as its own words say. Matched on sign-in
    /// phrases only: a CLI too old for the command prints its usage and exits
    /// non-zero too, and telling that reader to sign in again would be a
    /// remedy that changes nothing.
    static func reason(forExitOf stderr: String) -> ProviderUsage.Unavailability {
        let phrases = ["not signed in", "not logged in", "unauthorized", "unauthenticated", "login required",
                       "please login", "please log in", "bl login", "token expired", "session expired",
                       "credentials expired", "needlogin"]
        let text = stderr.lowercased()
        return phrases.contains(where: text.contains) ? .localLoginExpired : .unreadableReply
    }

    // MARK: - Reading the output

    static func reading(from data: Data, context: ProfileContext, now: Date = Date()) -> ProviderUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let tree = AlibabaConsoleJSON.expanded(object) as? [String: Any]
        else { return context.unavailable(.unreadableReply) }

        let windows = rollingWindows(in: tree, id: "alibabaTokenPlan", ceiling: 1, now: now)
        if !windows.isEmpty { return context.reading(windows, at: now) }

        switch AlibabaConsoleJSON.failure(in: tree) {
        case .signedOut: return context.unavailable(.localLoginExpired)
        case .failed: return context.unavailable(.serverError)
        case nil: return context.unavailable(.noLimitsReported)
        }
    }

    /// The rolling windows of a Token Plan's personal usage, which the CLI
    /// prints and Qwen Cloud's console returns in the same words: a share
    /// used, as a ratio, and a reset in epoch milliseconds, per window.
    ///
    /// A negative figure is never read. `ceiling` is where the CLI's are
    /// held to 1: its unit is not documented, and a figure past a ratio's
    /// range may be a percentage — left off rather than misread a hundredfold.
    /// A month is a billing month, so its length is not claimed.
    static func rollingWindows(in tree: Any, id prefix: String, ceiling: Double? = nil,
                               now: Date) -> [UsageWindow] {
        let keys = Set(rolling.map(\.key))
        guard let usage = AlibabaConsoleJSON.firstObject(in: tree, where: { !keys.isDisjoint(with: $0.keys) })
        else { return [] }
        return rolling.compactMap { window -> UsageWindow? in
            guard let ratio = AlibabaConsoleJSON.number(usage[window.key]), ratio >= 0,
                  ceiling.map({ ratio <= $0 }) ?? true
            else { return nil }
            // Epoch milliseconds only: a reset in the past is a stale figure,
            // not a new window, and is left off rather than moved forward.
            let reset = AlibabaConsoleJSON.number(usage[window.reset])
                .map { Date(timeIntervalSince1970: $0 / 1_000) }
                .flatMap { $0 > now ? $0 : nil }
            return UsageWindow(
                id: "\(prefix).\(window.id)",
                kind: window.kind,
                scope: nil,
                usedFraction: ratio,
                windowSeconds: window.seconds,
                resetsAt: reset,
                reportsLength: window.reportsLength,
                isExhausted: ratio >= 1
            )
        }
    }

    private static let rolling: [(key: String, reset: String, id: String, kind: UsageWindow.Kind,
                                  seconds: Int, reportsLength: Bool)] = [
        ("per5HourPercentage", "per5HourResetTime", "fiveHour", .fiveHour, 5 * 3_600, true),
        ("per1WeekPercentage", "per1WeekResetTime", "weekly", .weekly, 7 * 86_400, true),
        ("per1MonthPercentage", "per1MonthResetTime", "monthly", .monthly, 30 * 86_400, false),
    ]
}
