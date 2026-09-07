import Foundation
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
