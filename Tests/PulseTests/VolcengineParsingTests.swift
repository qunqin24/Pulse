import Foundation
import Darwin
import Testing
@testable import Pulse

/// Volcengine Ark's three reply shapes.
///
/// **The fixtures are second-hand.** Nobody here holds an Ark coding plan, so
/// these were written from CodexBar's parser and its tests (MIT) rather than
/// captured from a live account — weaker evidence than every other provider in
/// Pulse has behind it, and the reason the quirks below are pinned rather than
/// trusted. Replace them with a real capture the first time somebody with an
/// account can produce one. See
/// [Docs/providers/volcengine.md](../../Docs/providers/volcengine.md).
@Suite("Volcengine Ark parsing")
struct VolcengineParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private static func arkcli() throws -> [UsageWindow] {
        let reply = try JSONDecoder().decode(
            VolcengineUsageService.ArkcliReply.self,
            from: try fixture("volcengine-arkcli-usage")
        )
        return VolcengineUsageService.windows(from: reply)
    }

    // MARK: - arkcli

    @Test("Each plan becomes its own windows, shortest first, named by the plan")
    func plansBecomeScopedWindows() throws {
        let windows = try Self.arkcli()

        #expect(windows.map(\.id) == [
            "coding-plan.5h", "coding-plan.weekly", "coding-plan.monthly",
            "agent-plan.5h"
        ])
        #expect(windows.map(\.scope) == ["Coding Plan", "Coding Plan", "Coding Plan", "Agent Plan"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly, .fiveHour])
    }

    @Test("`percent` is what is used — no inversion")
    func percentIsUsedNotRemaining() throws {
        let weekly = try #require(try Self.arkcli().first { $0.id == "coding-plan.weekly" })
        #expect(abs(weekly.usedFraction - 0.415) < 0.000_001)
        #expect(weekly.percentText == "42%")
        #expect(weekly.isExhausted == false)
    }

    @Test("Ark reports no spent flag, so its own figure reaching 100 is the only signal")
    func exhaustedAtItsOwnCeiling() throws {
        let spent = try #require(try Self.arkcli().first { $0.id == "agent-plan.5h" })
        #expect(spent.isExhausted)
        #expect(spent.percentText == "100%")
    }

    @Test("A plan that isn't subscribed is skipped, and so is one Pulse can't name")
    func unsubscribedAndUnknownPlansAreDropped() throws {
        let ids = try Self.arkcli().map(\.id)
        // `coding-plan-team` has `subscribed: false`; `some-future-plan` is a
        // product this version has no name for, and a window that cannot say
        // which of four plans it belongs to is worse than no window.
        #expect(!ids.contains { $0.hasPrefix("coding-plan-team") })
        #expect(!ids.contains { $0.hasPrefix("some-future-plan") })
    }

    @Test("One plan's failure does not take the others' figures with it")
    func aFailedBucketIsSkipped() throws {
        // `agent-plan-team` came back with an error and no periods at all.
        // Rejecting the whole reply for it would lose the two working plans,
        // which is the failure mode this shape exists to prevent.
        #expect(try Self.arkcli().count == 4)
    }

    @Test("Reset times arrive as ISO strings and as epoch numbers")
    func resetTimesInBothForms() throws {
        let windows = try Self.arkcli()
        let weekly = try #require(windows.first { $0.id == "coding-plan.weekly" })
        let fiveHour = try #require(windows.first { $0.id == "coding-plan.5h" })

        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 11
        components.hour = 6; components.minute = 11; components.second = 46
        components.timeZone = TimeZone(identifier: "UTC")
        #expect(weekly.resetsAt == Calendar(identifier: .gregorian).date(from: components))
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1_788_780_000))
    }

    @Test("`updated_at` is read whether it is seconds or milliseconds")
    func observedAtHandlesBothUnits() throws {
        let reply = try JSONDecoder().decode(
            VolcengineUsageService.ArkcliReply.self,
            from: try Self.fixture("volcengine-arkcli-usage")
        )
        // 1788773400000 (ms) and 1788773100 (s) are the same afternoon; the
        // later of the two wins, and neither is read in the wrong unit.
        #expect(VolcengineUsageService.observedAt(from: reply)
            == Date(timeIntervalSince1970: 1_788_773_400))
    }

    @Test("A month is a sort key, not a length")
    func monthlyDoesNotClaimALength() throws {
        let windows = try Self.arkcli()
        let monthly = try #require(windows.first { $0.id == "coding-plan.monthly" })
        let weekly = try #require(windows.first { $0.id == "coding-plan.weekly" })

        // 28 to 31 days stored as 30, so the window clock and the forecast
        // must not divide by it.
        #expect(monthly.reportsLength == false)
        #expect(monthly.elapsedFraction(at: Date()) == nil)
        #expect(weekly.reportsLength)
    }

    // MARK: - The signed API

    @Test("GetCodingPlanUsage becomes the same windows, and drops a label it can't read")
    func codingPlanReply() throws {
        let windows = try #require(
            VolcengineUsageService.codingWindows(try Self.fixture("volcengine-coding-plan"))
        )
        #expect(windows.map(\.id) == ["coding-plan.5h", "coding-plan.weekly"])
        #expect(windows.allSatisfy { $0.scope == "Coding Plan" })
        // "fortnightly" is a length Pulse has no name for. Left out rather
        // than guessed at.
        #expect(!windows.contains { $0.id.contains("fortnightly") })
    }

    @Test("A reclaimed plan answers with a status and no quota, which is not a failure")
    func codingPlanWithoutQuota() throws {
        let data = Data(#"{"Result":{"Status":"Reclaimed"}}"#.utf8)
        #expect(VolcengineUsageService.codingWindows(data)?.isEmpty == true)
    }

    @Test("GetAFPUsage divides used by quota, and skips a window the plan hasn't got")
    func agentPlanReply() throws {
        let windows = try #require(
            VolcengineUsageService.agentWindows(try Self.fixture("volcengine-agent-plan"))
        )

        #expect(windows.map(\.id) == ["agent-plan.5h", "agent-plan.weekly"])
        #expect(abs((windows[0].usedFraction) - 0.25) < 0.000_001)
        #expect(windows[1].usedFraction == 0)
        // A quota of zero is a window the plan does not have, not a full one.
        // Dividing by it would report 100% used of nothing.
        #expect(!windows.contains { $0.id.contains("monthly") })
        // `AFPDaily` has no slot on a ring and is deliberately not mapped.
        #expect(!windows.contains { $0.id.contains("daily") })
    }

    @Test("Nonsense is nil rather than an empty reading")
    func malformedRepliesAreRejected() {
        #expect(VolcengineUsageService.codingWindows(Data("not json".utf8)) == nil)
        #expect(VolcengineUsageService.agentWindows(Data("not json".utf8)) == nil)
    }

    // MARK: - The pasted pair

    @Test("The key field is split on the first colon")
    func credentialsAreSplitOnce() throws {
        let parsed = try #require(VolcengineUsageService.credentials(from: " AKLTabc : secret:with:colons "))
        #expect(parsed.accessKeyID == "AKLTabc")
        // A secret containing colons survives, which splitting on the last —
        // or on all of them — would not.
        #expect(parsed.secretAccessKey == "secret:with:colons")
        #expect(parsed.region == "cn-beijing")
    }

    @Test("Half a pair is no pair")
    func incompleteCredentialsAreRefused() {
        for entered in ["", "   ", "AKLTabc", "AKLTabc:", ":secret", ":"] {
            #expect(VolcengineUsageService.credentials(from: entered) == nil, "accepted \(entered)")
        }
        #expect(VolcengineUsageService.credentials(from: nil) == nil)
    }
}

/// The `arkcli` subprocess, which is the part of this provider that can take
/// the whole app down with it: a pass that never finishes never reschedules,
/// so a hang here freezes the rail for all sixteen providers. Neither failure
/// below is visible by reading the code — the first version of that runner
/// looked correct and had both.
@Suite("Volcengine arkcli subprocess")
struct VolcengineProcessTests {
    private static let shell = URL(fileURLWithPath: "/bin/sh")

    @Test("A child that floods stderr does not deadlock")
    func stderrFloodDoesNotDeadlock() async throws {
        // A pipe buffer is 64 KiB. Reading stdout to EOF *before* touching
        // stderr means the child blocks writing and we block reading, for
        // ever. 1 MiB is comfortably past the edge.
        let result = await VolcengineUsageService.run(
            Self.shell,
            ["-c", "yes ERROR | head -c 1048576 >&2; printf '{\"items\":[]}'"],
            deadline: 20
        )

        let data = try result.get()
        #expect(String(data: data, encoding: .utf8) == #"{"items":[]}"#)
    }

    @Test("Output past the ceiling is dropped, not read into memory for ever")
    func hugeOutputIsCapped() async throws {
        let result = await VolcengineUsageService.run(
            Self.shell,
            ["-c", "yes PADDING | head -c 4194304"],
            deadline: 20
        )

        let data = try result.get()
        // Bounded, and the process still exited cleanly — the reader kept
        // draining after it stopped keeping, which is what stops the child
        // blocking on a full pipe.
        #expect(data.count <= 512 * 1024 + 65_536)
    }

    @Test("A child that never finishes is killed at the deadline")
    func hangingChildIsTerminated() async throws {
        let started = ContinuousClock.now
        let result = await VolcengineUsageService.run(
            Self.shell,
            ["-c", "sleep 60"],
            deadline: 1
        )
        let elapsed = started.duration(to: .now)

        #expect(throws: VolcengineUsageService.Refusal.self) { try result.get() }
        // Killed, not waited out. Without this the refresh loop stops.
        #expect(elapsed < .seconds(20))
    }

    @Test("A child that ignores SIGTERM is killed, not waited on for ever")
    func sigtermIgnoringChildIsKilled() async throws {
        // The first fix bounded only the readers and then called
        // `waitUntilExit()`, which has no timeout — so this child sailed past
        // the deadline and parked the call permanently. `terminate()` is a
        // request; a CLI with a stuck graceful-shutdown path ignores it.
        let started = ContinuousClock.now
        let result = await VolcengineUsageService.run(
            Self.shell, ["-c", "trap '' TERM; sleep 60"], deadline: 1
        )
        let elapsed = started.duration(to: .now)

        #expect(throws: VolcengineUsageService.Refusal.self) { try result.get() }
        #expect(elapsed < .seconds(20))
    }

    @Test("A child that closes its pipes and keeps running is not waited on either")
    func childThatClosesPipesButLivesIsBounded() async throws {
        // The readers see EOF at once, so the group completes inside the
        // deadline — and the old code then fell through to an unbounded wait
        // for a process that had no intention of exiting.
        let started = ContinuousClock.now
        let result = await VolcengineUsageService.run(
            Self.shell, ["-c", "exec 1>&- 2>&-; sleep 60"], deadline: 1
        )
        let elapsed = started.duration(to: .now)

        #expect(throws: VolcengineUsageService.Refusal.self) { try result.get() }
        #expect(elapsed < .seconds(20))
    }

    @Test("A grandchild is terminated even after its parent exits", arguments: [false, true])
    func grandchildDoesNotHoldTheCall(ignoresTERM: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pulse-grandchild-\(UUID()).pid")
        defer { try? FileManager.default.removeItem(at: file) }
        let started = ContinuousClock.now
        let command = ignoresTERM ? "trap '' TERM; exec sleep 30" : "exec sleep 30"
        let result = await VolcengineUsageService.run(
            Self.shell,
            ["-c", "(\(command)) & printf '%s' \"$!\" > \"$1\"; exit 0", "pulse-test", file.path],
            deadline: 1
        )
        #expect(started.duration(to: .now) < .seconds(20))
        #expect(result == .failure(.init(reason: .unreachable)))
        let pid = try #require(Int32(String(contentsOf: file, encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        let until = ContinuousClock.now + .seconds(3)
        while kill(pid, 0) == 0, ContinuousClock.now < until {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH, "the runner returned but its descendant survived")
    }

    @Test("A missing binary is reported, not thrown")
    func missingBinary() async {
        let result = await VolcengineUsageService.run(
            URL(fileURLWithPath: "/nonexistent/arkcli"), [], deadline: 5
        )
        #expect(result == .failure(.init(reason: .volcengineCLIMissing)))
    }

    // MARK: - Why a non-zero exit happened

    @Test("Only a signed-out phrase reads as signed out")
    func signedOutPhrases() {
        for stderr in [
            "Error: not signed in",
            "please run `arkcli auth login`",
            "unauthorized",
            "credentials expired",
        ] {
            #expect(VolcengineUsageService.reason(forExitOf: stderr) == .volcengineSignInRequired,
                    "missed: \(stderr)")
        }
    }

    @Test("Help text is not a sign-in problem")
    func helpTextIsNotSignedOut() {
        // The trap: `"auth"` is a substring of `authentication`, `authority`,
        // and of arkcli's own subcommand list. An arkcli too old or too new
        // for `usage plan --format json` prints its usage and exits non-zero —
        // and was told to run `arkcli auth login`, which succeeds and changes
        // nothing, for ever.
        let usage = """
        Usage: arkcli [command]

        Available commands:
          auth        Manage authentication
          usage       Show plan usage
        """
        #expect(VolcengineUsageService.reason(forExitOf: usage) == .unreadableReply)
        #expect(VolcengineUsageService.reason(forExitOf: "unknown flag: --format") == .unreadableReply)
        #expect(VolcengineUsageService.reason(forExitOf: "") == .unreadableReply)
    }
}
