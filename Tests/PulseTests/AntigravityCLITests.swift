import Foundation
import Testing
@testable import Pulse

/// Antigravity's second route: `agy -p "/usage" --output-format json`.
///
/// The fixture has the shape `agy` 1.3.5 printed on 2026-10-14, with the
/// fractions changed so that it carries no real account's figures — see
/// [Docs/providers/antigravity.md](../../Docs/providers/antigravity.md).
@Suite("Antigravity CLI quota")
struct AntigravityCLITests {
    private static func captured() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "antigravity-cli-usage", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private static func windows() throws -> [UsageWindow] {
        guard case .windows(let windows) = AntigravityUsageService.cliAnswer(from: try captured()) else {
            Issue.record("The captured reply did not produce windows")
            return []
        }
        return windows
    }

    // MARK: - The reply

    @Test("The captured reply becomes four windows, shortest first within each group")
    func capturedReply() throws {
        let windows = try Self.windows()
        #expect(windows.map(\.id) == ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .fiveHour, .weekly])
        #expect(windows.map(\.scope) == ["Gemini", "Gemini", "Claude and GPT", "Claude and GPT"])
    }

    /// The shape a Pro account printed on 2026-11-05 (#106), fractions
    /// changed: a third group, Gemini 4 Argon, with a weekly bucket alone.
    @Test("Gemini 4 Argon is a third group with one weekly window, and splits into a third ring")
    func argonGroup() throws {
        let url = try #require(
            Bundle.module.url(forResource: "antigravity-cli-usage-argon", withExtension: "json", subdirectory: "Fixtures")
        )
        guard case .windows(let windows) = AntigravityUsageService.cliAnswer(from: try Data(contentsOf: url)) else {
            Issue.record("The Argon reply did not produce windows")
            return
        }
        let argon = try #require(windows.first { $0.id == "gemini-argon-wtu-weekly" })
        #expect(argon.kind == .weekly)
        #expect(argon.scope == "Gemini 4 Argon")
        #expect(abs(argon.usedFraction - 0.6) < 1e-9)

        let usage = ProviderUsage(account: AccountKey(.antigravity), windows: windows, observedAt: Date(),
                                  state: .live, plan: nil, creditBalance: nil)
        let groups = RailSlot.modelGroups(of: usage)
        #expect(groups == ["Gemini", "Claude and GPT", "Gemini 4 Argon"])
        let slots = RailSlot.rail(for: [AccountKey(.antigravity)], isSplit: { _ in true }, groups: { _ in groups })
        #expect(slots.count == 3)
    }

    @Test("What is left is turned into what is gone, from the fraction rather than the rounded text")
    func remainingIsInverted() throws {
        let windows = try Self.windows()
        let fiveHour = try #require(windows.first { $0.id == "gemini-5h" })
        #expect(abs(fiveHour.usedFraction - 0.6) < 0.000_001)
        let weekly = try #require(windows.first { $0.id == "gemini-weekly" })
        #expect(abs(weekly.usedFraction - 0.25) < 0.000_001)
        let untouched = try #require(windows.first { $0.id == "3p-weekly" })
        #expect(untouched.usedFraction == 0)
        #expect(untouched.isExhausted == false)
    }

    @Test("Reset times are read as real dates")
    func resetTimes() throws {
        let weekly = try #require(try Self.windows().first { $0.id == "gemini-weekly" })
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 18
        components.hour = 10
        components.minute = 19
        components.second = 51
        components.timeZone = TimeZone(identifier: "UTC")
        #expect(weekly.resetsAt == Calendar(identifier: .gregorian).date(from: components))
    }

    @Test("Both routes go through one mapping")
    func sameMappingAsTheLanguageServer() throws {
        let server = try JSONDecoder().decode(AntigravityUsageService.Reply.self, from: Data("""
        {"response":{"groups":[
          {"displayName":"Gemini Models","buckets":[
            {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.75,"resetTime":"2026-10-18T10:19:51Z"},
            {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.4,"resetTime":"2026-10-14T11:34:51Z"}]},
          {"displayName":"Claude and GPT models","buckets":[
            {"bucketId":"3p-weekly","window":"weekly","remainingFraction":1,"resetTime":"2026-10-21T06:34:51Z"},
            {"bucketId":"3p-5h","window":"5h","remainingFraction":1,"resetTime":"2026-10-14T11:34:51Z"}]}
        ]}}
        """.utf8))
        #expect(try Self.windows() == AntigravityUsageService.windows(from: server))
    }

    @Test("Nothing left is spent")
    func exhausted() throws {
        let answer = AntigravityUsageService.cliAnswer(from: Data("""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[
          {"id":"gemini-5h","window":"5h","remaining_fraction":0}
        ]}]}}}
        """.utf8))
        guard case .windows(let windows) = answer, let window = windows.first else {
            Issue.record("Expected one window, got \(answer)")
            return
        }
        #expect(window.isExhausted)
        #expect(window.percentText == "100%")
    }

    @Test("A successful answer with no limits says so")
    func noLimits() {
        #expect(AntigravityUsageService.cliAnswer(from: Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[]}}}"#.utf8)) == .noLimits)
        #expect(AntigravityUsageService.cliAnswer(from: Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{}}}"#.utf8)) == .noLimits)
    }

    @Test("An error, an agent turn's answer, or anything else is not read as limits")
    func unreadable() {
        let error = #"{"conversation_id":"","status":"ERROR","response":"","error":"Eligibility check failed","num_turns":0}"#
        // What a turn prints: a response and no `command`. Never parsed for figures.
        let turn = #"{"conversation_id":"abc","status":"SUCCESS","response":"Your usage is fine.","num_turns":1}"#
        for body in [error, turn, "", "not json"] {
            #expect(AntigravityUsageService.cliAnswer(from: Data(body.utf8)) == .failed(.unreadableReply))
        }
    }

    // MARK: - The version gate

    @Test("Only a version that answers /usage itself is asked")
    func versionGate() {
        for version in ["1.3.5\n", "1.1.11", "1.1.12", "1.2.0", "2.0", "1.2.0-beta", "10.0.0"] {
            #expect(AntigravityUsageService.answersUsageItself(version: version), "\(version)")
        }
        // Before 1.1.11, `-p "/usage"` was sent to the model as a prompt.
        for version in ["1.1.10", "1.1.3", "1.0.16", "0.9.0", "", "agy version 1.3.5", "1", "unknown"] {
            #expect(!AntigravityUsageService.answersUsageItself(version: version), "\(version)")
        }
    }

    @Test("The CLI is asked for /usage alone, with its log kept out of the user's")
    func arguments() {
        #expect(AntigravityUsageService.cliArguments == ["--log-file", "/dev/null", "-p", "/usage", "--output-format", "json"])
    }

    // MARK: - Weighing it against the language server

    private static let closed = ProviderUsage.unavailable(.antigravity, reason: .antigravityNotRunning)
        .recording(.languageServer)

    @Test("Limits from the CLI are live and say which route answered")
    func cliAnswers() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = AntigravityUsageService.weigh(server: Self.closed, cli: .windows(try Self.windows()), now: now)

        #expect(result.state == .live)
        #expect(result.windows.count == 4)
        #expect(result.observedAt == now)
        #expect(result.plan == nil)
        #expect(result.origin == .antigravityCLI)
        #expect(result.attempts.map(\.route) == [.languageServer, .antigravityCLI])
        #expect(result.attempts.first?.state == .unavailable(.antigravityNotRunning))
    }

    @Test("A CLI that fails leaves the language server's reason standing, and is recorded")
    func cliFails() {
        for reason in [ProviderUsage.Unavailability.unreadableReply, .unreachable] {
            let result = AntigravityUsageService.weigh(server: Self.closed, cli: .failed(reason))
            #expect(result.state == .unavailable(.antigravityNotRunning))
            #expect(result.origin == nil)
            #expect(result.attempts.map(\.route) == [.languageServer, .antigravityCLI])
            #expect(result.attempts.last?.state == .unavailable(reason))
        }
    }

    @Test("A CLI that answers with no limits is reported as such")
    func cliNoLimits() {
        let result = AntigravityUsageService.weigh(server: Self.closed, cli: .noLimits)
        #expect(result.state == .unavailable(.noLimitsReported))
        #expect(result.attempts.map(\.route) == [.languageServer, .antigravityCLI])
    }

    @Test("A CLI that was not asked changes nothing")
    func cliNotAsked() {
        let result = AntigravityUsageService.weigh(server: Self.closed, cli: .notAsked(.antigravityCLIMissing))
        #expect(result.state == Self.closed.state)
        #expect(result.attempts == Self.closed.attempts)
    }

    @Test("Antigravity offers automatic, the CLI and the desktop app, automatic by default")
    func offersItsRoutes() {
        let account = AccountKey(.antigravity)
        #expect(Provider.antigravity.hasSourceChoice)
        #expect(Provider.antigravity.soleRoute == nil)
        #expect(UsageSource.options(for: account) == [.automatic, .tooling, .desktopApp])
        #expect(UsageSource.tooling.title(for: .antigravity) != UsageSource.tooling.title)
    }

    @Test("Pinned to the CLI, every way it fails is reported as itself")
    func cliOnlyReportsItsOwnReasons() {
        #expect(AntigravityUsageService.cliOnly(.notAsked(.antigravityCLIMissing)).state == .unavailable(.antigravityCLIMissing))
        #expect(AntigravityUsageService.cliOnly(.notAsked(.antigravityCLIOutdated)).state == .unavailable(.antigravityCLIOutdated))
        #expect(AntigravityUsageService.cliOnly(.failed(.unreachable)).state == .unavailable(.unreachable))
        #expect(AntigravityUsageService.cliOnly(.noLimits).state == .unavailable(.noLimitsReported))
        let failed = AntigravityUsageService.cliOnly(.failed(.unreachable))
        #expect(failed.attempts.map(\.route) == [.antigravityCLI])
    }
}
