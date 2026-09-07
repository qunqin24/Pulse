import Foundation
import Testing
@testable import Pulse

/// Antigravity's quota reply, held against a payload actually captured from a
/// language server on this Mac rather than one written to match the parser.
///
/// The fixture is what `Antigravity IDE.app` answered to
/// `RetrieveUserQuotaSummary` on 2026-09-06 — see
/// [Docs/providers/antigravity.md](../../Docs/providers/antigravity.md). When
/// the other end changes shape, this is what says so.
@Suite("Antigravity quota parsing")
struct AntigravityParsingTests {
    private static func decode(_ json: String) throws -> AntigravityUsageService.Reply {
        try JSONDecoder().decode(AntigravityUsageService.Reply.self, from: Data(json.utf8))
    }

    private static func captured() throws -> AntigravityUsageService.Reply {
        let url = try #require(
            Bundle.module.url(forResource: "antigravity-quota", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(AntigravityUsageService.Reply.self, from: Data(contentsOf: url))
    }

    @Test("The captured reply becomes four windows, shortest first within each group")
    func capturedReply() throws {
        let windows = AntigravityUsageService.windows(from: try Self.captured())

        #expect(windows.map(\.id) == ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .fiveHour, .weekly])
    }

    @Test("A group's name becomes the scope, with a trailing \"models\" trimmed")
    func scopes() throws {
        let windows = AntigravityUsageService.windows(from: try Self.captured())
        #expect(windows.map(\.scope) == ["Gemini", "Gemini", "Claude and GPT", "Claude and GPT"])
    }

    @Test("What is left is turned into what is gone, exactly once")
    func remainingIsInverted() throws {
        let weekly = try #require(
            AntigravityUsageService.windows(from: try Self.captured()).first { $0.id == "gemini-weekly" }
        )
        // remainingFraction 0.9949068 in the reply.
        #expect(abs(weekly.usedFraction - 0.0050932) < 0.000_001)
        #expect(weekly.percentText == "1%")
        #expect(weekly.isExhausted == false)

        let untouched = try #require(
            AntigravityUsageService.windows(from: try Self.captured()).first { $0.id == "3p-weekly" }
        )
        #expect(untouched.usedFraction == 0)
    }

    @Test("Reset times are read as real dates")
    func resetTimes() throws {
        let weekly = try #require(
            AntigravityUsageService.windows(from: try Self.captured()).first { $0.id == "gemini-weekly" }
        )
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 11
        components.hour = 6
        components.minute = 11
        components.second = 46
        components.timeZone = TimeZone(identifier: "UTC")

        #expect(weekly.resetsAt == Calendar(identifier: .gregorian).date(from: components))
    }

    @Test("Nothing left is spent")
    func exhausted() throws {
        let reply = try Self.decode("""
        {"response":{"groups":[{"displayName":"Gemini Models","buckets":[
          {"bucketId":"gemini-5h","window":"5h","remainingFraction":0}
        ]}]}}
        """)
        let window = try #require(AntigravityUsageService.windows(from: reply).first)
        #expect(window.isExhausted)
        #expect(window.percentText == "100%")
    }

    @Test("A bucket whose window cannot be read is left out, not guessed at")
    func unreadableWindowIsDropped() throws {
        let reply = try Self.decode("""
        {"response":{"groups":[{"displayName":"Gemini Models","buckets":[
          {"bucketId":"mystery","window":"fortnightly","remainingFraction":0.5},
          {"bucketId":"nameless","remainingFraction":0.5},
          {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.5}
        ]}]}}
        """)
        #expect(AntigravityUsageService.windows(from: reply).map(\.id) == ["gemini-5h"])
    }

    @Test("A window length not seen before is understood rather than dropped")
    func numberedWindows() throws {
        let reply = try Self.decode("""
        {"response":{"groups":[{"displayName":"Gemini Models","buckets":[
          {"bucketId":"a","window":"3h","remainingFraction":1},
          {"bucketId":"b","window":"7d","remainingFraction":1},
          {"bucketId":"c","window":"30d","remainingFraction":1}
        ]}]}}
        """)
        let windows = AntigravityUsageService.windows(from: reply)
        #expect(windows.map(\.id) == ["a", "b", "c"])
        #expect(windows.map(\.kind) == [.other(seconds: 3 * 3_600), .weekly, .other(seconds: 30 * 86_400)])
    }

    @Test("An empty reply is no windows, not a crash")
    func emptyReply() throws {
        #expect(AntigravityUsageService.windows(from: try Self.decode("{}")).isEmpty)
        #expect(AntigravityUsageService.windows(from: try Self.decode(#"{"response":{"groups":[]}}"#)).isEmpty)
    }
}
