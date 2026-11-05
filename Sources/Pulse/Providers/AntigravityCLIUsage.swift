// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Antigravity's limits as its CLI, `agy`, reports them.
///
/// `agy -p "/usage" --output-format json` answers the read-only `/usage`
/// command without starting an agent turn, spending quota or leaving a
/// conversation behind, and its `command.data` carries the same groups and
/// buckets as the language server's `RetrieveUserQuotaSummary` — the same
/// bucket ids, windows, remaining fractions and reset times, in snake case.
/// Measured on 2026-10-14 with `agy` 1.3.5; see
/// [Docs/providers/antigravity.md](../../Docs/providers/antigravity.md).
///
/// It uses the login the CLI saved. Pulse starts the program and reads its
/// standard output; it never reads the CLI's credentials.
extension AntigravityUsageService {
    /// What the CLI said, before it is weighed against the language server.
    enum CLIAnswer: Equatable {
        /// Limits, already inverted into what is gone.
        case windows([UsageWindow])
        /// A successful answer with no limits in it.
        case noLimits
        /// It ran and did not answer. The reason is for the diagnostics.
        case failed(ProviderUsage.Unavailability)
        /// It was not asked: it would not start (`.antigravityCLIMissing`), or
        /// is too old to be asked safely (`.antigravityCLIOutdated`, see
        /// `cliMinimumVersion`).
        case notAsked(ProviderUsage.Unavailability)
    }

    /// The first `agy` that answers `-p "/usage"` itself.
    ///
    /// **Older versions must not be asked.** Before 1.1.11 a slash command in
    /// print mode fell through as literal prompt text, so `-p "/usage"` was
    /// *sent to the model*: it would spend the quota it is meant to measure and
    /// leave a conversation behind, on every refresh. Pulse sends nothing on
    /// the user's behalf, so a version that cannot be read counts as too old.
    static let cliMinimumVersion = [1, 1, 11]

    /// `--log-file /dev/null` because each run otherwise writes a new log file
    /// and repoints the CLI's `cli.log` link at it, away from the log of the
    /// session the user is actually running.
    static let cliArguments = ["--log-file", "/dev/null", "-p", "/usage", "--output-format", "json"]

    /// A run took 8.5 seconds when measured, most of it the CLI's own
    /// eligibility check over the network.
    private static let cliDeadline: TimeInterval = 30
    private static let versionDeadline: TimeInterval = 10
    private static let cliOutputCeiling = 512 * 1024

    /// The installer puts `agy` in `~/.local/bin`; Homebrew's cask links it
    /// into its own `bin`. Only `agy` is looked for: `antigravity` is also the
    /// name of the editor's own shell command, which is a different program.
    ///
    /// **Then the copy Gemini.app keeps.** The Gemini desktop app carries
    /// Antigravity and installs the same CLI to `~/.gemini/bin/agy`, kept up
    /// to date by its own updater (`agy.version.json` beside it); it runs no
    /// language server of its own. Someone who has only Gemini.app has only
    /// this copy (#106). Last, so a CLI installed on purpose is the one asked.
    static func locateCLI(home: String = NSHomeDirectory(),
                          isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        CommandLocator.locate("agy") ?? geminiAppCLI(home: home, isExecutable: isExecutable)
    }

    static func geminiAppCLI(home: String, isExecutable: (String) -> Bool) -> URL? {
        let path = "\(home)/.gemini/bin/agy"
        return isExecutable(path) ? URL(fileURLWithPath: path) : nil
    }

    static func askCLI(_ binary: URL) async -> CLIAnswer {
        let environment = BoundedProcess.environment(leading: binary, over: BoundedProcess.inheritedEnvironment)

        switch await BoundedProcess.run(
            binary, ["--version"],
            environment: environment,
            deadline: versionDeadline,
            outputCeiling: 4 * 1024
        ) {
        case .success(let printed) where answersUsageItself(version: String(decoding: printed, as: UTF8.self)):
            break
        case .failure(.couldNotStart):
            return .notAsked(.antigravityCLIMissing)
        default:
            return .notAsked(.antigravityCLIOutdated)
        }

        switch await BoundedProcess.run(
            binary, cliArguments,
            environment: environment,
            // An empty folder rather than wherever Pulse was started: the CLI
            // looks for project files around the folder it runs in.
            currentDirectory: FileManager.default.temporaryDirectory,
            deadline: cliDeadline,
            outputCeiling: cliOutputCeiling
        ) {
        case .success(let data): return cliAnswer(from: data)
        case .failure(.couldNotStart): return .notAsked(.antigravityCLIMissing)
        case .failure(.timedOut): return .failed(.unreachable)
        // A failed run exits 1 with `status: "ERROR"` and a message, which
        // does not say reliably whether the cause is the network or the login.
        case .failure(.exited): return .failed(.unreadableReply)
        }
    }

    /// Whether `agy --version` names a version at or past `cliMinimumVersion`.
    static func answersUsageItself(version printed: String) -> Bool {
        let text = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        // "1.3.5", possibly with a suffix such as "-beta" on the last part.
        let parts = text.split(separator: ".").map { part in Int(part.prefix { $0.isNumber }) }
        guard parts.count >= 2, !parts.contains(nil) else { return false }

        let numbers = parts.compactMap { $0 }
        for (index, minimum) in cliMinimumVersion.enumerated() {
            let value = index < numbers.count ? numbers[index] : 0
            if value != minimum { return value > minimum }
        }
        return true
    }

    /// Internal so a test can hold a captured reply against it; do not tidy it
    /// back to `private`.
    static func cliAnswer(from data: Data) -> CLIAnswer {
        guard
            let reply = try? JSONDecoder().decode(CLIReply.self, from: data),
            reply.status == "SUCCESS",
            let usage = reply.command?.data
        else { return .failed(.unreadableReply) }

        let windows = windows(from: usage.asQuotaReply)
        return windows.isEmpty ? .noLimits : .windows(windows)
    }

    /// The CLI's answer next to the language server's.
    ///
    /// **When the CLI does not answer, the language server's reason stands.**
    /// The CLI is a fallback, and it fails in ways that do not say why: a run
    /// that exits with an error may be a network fault or a CLI that was never
    /// signed in. Reporting that as a failure would raise a notification for
    /// someone who installed `agy`, never used it, and closed the editor. The
    /// CLI's attempt is still recorded, so the diagnostics show it.
    static func weigh(server: ProviderUsage, cli: CLIAnswer, now: Date = Date()) -> ProviderUsage {
        switch cli {
        case .windows(let windows):
            return ProviderUsage(
                account: AccountKey(.antigravity),
                windows: windows,
                observedAt: now,
                state: .live,
                // `/usage` does not name the plan, and nothing else the CLI
                // answers in print mode does either.
                plan: nil,
                // `/credits` reports a separate AI-credit balance, not the
                // plan's quota. Not read; see the provider's page.
                creditBalance: nil
            )
            .recording(.antigravityCLI, after: server.attempts)

        case .noLimits:
            // The account answered and has no limits on it. That is a better
            // account than "open Antigravity", whatever the server said.
            return ProviderUsage.unavailable(.antigravity, reason: .noLimitsReported)
                .recording(.antigravityCLI, after: server.attempts)

        case .failed(let reason):
            var result = server
            result.attempts.append(.init(route: .antigravityCLI, state: .unavailable(reason)))
            return result

        case .notAsked:
            return server
        }
    }

    /// The CLI's answer when it is the only route asked (Settings → *Read
    /// usage from* → *CLI*). Unlike `weigh`, every way it can fail is
    /// reported as itself: there is no other route's reason to stand
    /// instead, and a pinned route that fails quietly is a setting that lies.
    static func cliOnly(_ cli: CLIAnswer, now: Date = Date()) -> ProviderUsage {
        switch cli {
        case .windows:
            return weigh(server: .unavailable(.antigravity, reason: .loading), cli: cli, now: now)
        case .noLimits:
            return ProviderUsage.unavailable(.antigravity, reason: .noLimitsReported).recording(.antigravityCLI)
        case .failed(let reason), .notAsked(let reason):
            return ProviderUsage.unavailable(.antigravity, reason: reason).recording(.antigravityCLI)
        }
    }

    /// The part of the CLI's JSON envelope Pulse reads. The envelope also has
    /// a tab-separated `response` text, whose percentages are rounded, and a
    /// token `usage` block that is all zeroes for a slash command.
    struct CLIReply: Decodable {
        struct Bucket: Decodable {
            let id: String?
            let window: String?
            let remainingFraction: Double?
            let resetTime: String?

            enum CodingKeys: String, CodingKey {
                case id, window
                case remainingFraction = "remaining_fraction"
                case resetTime = "reset_time"
            }
        }

        struct Group: Decodable {
            let name: String?
            let buckets: [Bucket]?
        }

        struct Usage: Decodable {
            let groups: [Group]?

            /// The same shape the language server answers, so both routes go
            /// through one mapping and cannot drift apart.
            var asQuotaReply: Reply {
                Reply(response: Reply.Response(groups: (groups ?? []).map { group in
                    Reply.Group(
                        displayName: group.name,
                        buckets: (group.buckets ?? []).map { bucket in
                            Reply.Bucket(
                                bucketId: bucket.id,
                                window: bucket.window,
                                remainingFraction: bucket.remainingFraction,
                                resetTime: bucket.resetTime
                            )
                        }
                    )
                }))
            }
        }

        struct Command: Decodable {
            let name: String?
            let data: Usage?
        }

        let status: String?
        let command: Command?
    }
}
