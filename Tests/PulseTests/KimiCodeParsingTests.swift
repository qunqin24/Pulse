import Foundation
import Testing
@testable import Pulse

/// Kimi Code's `coding/v1/usages` reply, reconstructed from
/// `KimiCodeUsageService`'s own `Reply` fields and
/// [Docs/providers/kimi-code.md](../../Docs/providers/kimi-code.md) — not
/// captured from a live account.
@Suite("Kimi Code parsing")
struct KimiCodeParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func reply(_ name: String) throws -> KimiCodeUsageService.Reply {
        try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: try fixture(name))
    }

    private static func decode(_ json: String) throws -> KimiCodeUsageService.Reply {
        try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: Data(json.utf8))
    }

    private static func dateComponents(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d
        components.hour = h; components.minute = min
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Two kinds of limit

    /// `limits[]` are read as the service states them; `usage` is the weekly
    /// allowance, which reports a reset and **no length** because the window
    /// rolls. A third `limits[]` entry with a time unit nobody documented is
    /// dropped rather than guessed at.
    @Test("A normal reply sorts the timed limits ahead of the weekly allowance, shortest first")
    func normalReply() throws {
        let windows = KimiCodeUsageService.windows(from: try Self.reply("kimi-code-normal"))

        #expect(windows.map(\.id) == ["limit.0.18000", "weekly", "limit.1.2592000"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])

        // limits[0]: 120 of 300.
        #expect(abs(windows[0].usedFraction - 0.4) < 0.000_001)
        #expect(windows[0].reportsLength)
        #expect(windows[0].resetsAt == Self.dateComponents(2026, 9, 26, 18, 0))

        // usage: 250 of 1000, no stated length.
        #expect(abs(windows[1].usedFraction - 0.25) < 0.000_001)
        #expect(!windows[1].reportsLength)
        #expect(windows[1].resetsAt == Self.dateComponents(2026, 10, 1, 0, 0))

        // limits[1]: no `used`, so it is `limit - remaining` = 5000 - 1500.
        #expect(abs(windows[2].usedFraction - 0.7) < 0.000_001)
        #expect(windows[2].reportsLength)

        #expect(KimiCodeUsageService.planName(try Self.reply("kimi-code-normal").user?.membership?.level) == "Intermediate")
    }

    /// `TIME_UNIT_FORTNIGHT` isn't one of the four recognised units — a window
    /// with no readable length can't be named or sorted, so it is left out
    /// rather than guessed at, and the other two limits are unaffected.
    @Test("A limit with an unrecognised time unit is dropped, not guessed at")
    func unrecognisedTimeUnitIsDropped() throws {
        let windows = KimiCodeUsageService.windows(from: try Self.reply("kimi-code-normal"))
        #expect(!windows.contains { $0.id.hasPrefix("limit.2") })
        #expect(windows.count == 3)
    }

    /// Every count in the reply is a JSON **string** — `"250"`, not `250` —
    /// which is exactly what every fixture in this file uses. If that ever
    /// stopped decoding, every test here would fail at the `reply(_:)` step.
    @Test("Counts arrive as strings and are read as numbers")
    func countsAreStrings() throws {
        let reply = try Self.reply("kimi-code-normal")
        #expect(reply.usage?.used == "250")
        #expect(KimiCodeUsageService.windows(from: reply).map(\.usedFraction).allSatisfy { $0 > 0 })
    }

    // MARK: - Nothing reported

    /// No `used`, no `remaining` on a `limits[]` entry — nothing to subtract
    /// and nothing to read directly, so it is dropped rather than shown as an
    /// empty or full ring. `usage` being `null` drops the weekly row the same
    /// way, and the whole reply draws nothing rather than a zero.
    @Test("A limit with neither used nor remaining, and no usage block, draws nothing")
    func missingFieldsDrawNothing() throws {
        let reply = try Self.reply("kimi-code-missing-fields")
        #expect(KimiCodeUsageService.windows(from: reply).isEmpty)
        #expect(KimiCodeUsageService.planName(reply.user?.membership?.level) == nil)
    }

    // MARK: - Exhausted

    @Test("Spent is the arithmetic here: used at or over the limit is exhausted")
    func exhaustedWeeklyAllowance() throws {
        let windows = KimiCodeUsageService.windows(from: try Self.reply("kimi-code-exhausted"))
        let weekly = try #require(windows.first { $0.id == "weekly" })
        #expect(weekly.usedFraction == 1)
        #expect(weekly.isExhausted)
        #expect(KimiCodeUsageService.planName("LEVEL_ADVANCED") == "Advanced")
    }

    // MARK: - Duration units and edge cases

    @Test("Minutes and seconds convert to the same seconds a hard-coded window would")
    func minutesAndSecondsConvert() throws {
        let reply = try Self.decode("""
        {"limits":[
          {"window":{"duration":90,"timeUnit":"TIME_UNIT_SECOND"},"detail":{"limit":"10","used":"5"}},
          {"window":{"duration":3,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"10","used":"5"}}
        ]}
        """)
        let windows = KimiCodeUsageService.windows(from: reply)
        #expect(windows.map(\.id) == ["limit.0.90", "limit.1.180"])
        #expect(windows.map(\.kind) == [.other(seconds: 90), .other(seconds: 180)])
    }

    /// A window length this app has no name for still gets a window — it is
    /// read as `.other(seconds:)` rather than dropped, unlike a length that
    /// cannot be read at all.
    @Test("An unnamed window length is understood, not dropped")
    func unnamedWindowLengthIsKept() throws {
        let reply = try Self.decode("""
        {"limits":[{"window":{"duration":3,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":"10","used":"5"}}]}
        """)
        let windows = KimiCodeUsageService.windows(from: reply)
        #expect(windows.map(\.kind) == [.other(seconds: 3 * 3_600)])
    }

    @Test("A zero or negative duration has no length and is dropped")
    func nonPositiveDurationIsDropped() throws {
        let reply = try Self.decode("""
        {"limits":[
          {"window":{"duration":0,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":"10","used":"5"}},
          {"window":{"duration":-5,"timeUnit":"TIME_UNIT_DAY"},"detail":{"limit":"10","used":"5"}}
        ]}
        """)
        #expect(KimiCodeUsageService.windows(from: reply).isEmpty)
    }

    // MARK: - Plan names

    @Test("The LEVEL_ prefix is dropped and the rest is tidied; unfamiliar tiers pass through")
    func planNameMapping() {
        #expect(KimiCodeUsageService.planName("LEVEL_INTERMEDIATE") == "Intermediate")
        #expect(KimiCodeUsageService.planName("LEVEL_ADVANCED_PLUS") == "Advanced Plus")
        #expect(KimiCodeUsageService.planName("mystery") == "Mystery")
        #expect(KimiCodeUsageService.planName("") == nil)
        #expect(KimiCodeUsageService.planName(nil) == nil)
    }

    // MARK: - Unreadable reply

    /// The same decode `fetch()` relies on: a reply that fails to parse at all
    /// becomes `.unreadableReply` there. The HTTP status mapping (401 / 403 /
    /// 429 / other) is a plain `switch` inline in `fetch()`, not a separate
    /// function, so it needs a real network call to reach and is not
    /// exercised here.
    @Test("A reply that is not valid JSON fails to decode")
    func garbageReplyFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: Data("not json at all".utf8))
        }
    }
}
