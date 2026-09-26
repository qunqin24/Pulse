import Foundation
import Testing
@testable import Pulse

/// OpenCode Go's `zen/go/v1/usage` reply, reconstructed from
/// `OpenCodeGoUsageService`'s own `Reply` fields and
/// [Docs/providers/opencode-go.md](../../Docs/providers/opencode-go.md) — not
/// captured from a live account.
@Suite("OpenCode Go parsing")
struct OpenCodeGoParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func reply(_ name: String) throws -> OpenCodeGoUsageService.Reply {
        try JSONDecoder().decode(OpenCodeGoUsageService.Reply.self, from: try fixture(name))
    }

    private static func decode(_ json: String) throws -> OpenCodeGoUsageService.Reply {
        try JSONDecoder().decode(OpenCodeGoUsageService.Reply.self, from: Data(json.utf8))
    }

    private static func dateComponents(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d; components.hour = h
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - The three windows

    /// **The window the reply calls "rolling" is the five-hour one** — its own
    /// id keeps the reply's key so a pinned window still matches, but the
    /// `kind` is `.fiveHour`, not something rolling-shaped. `percent` is how
    /// much is **gone**, read directly with no inversion.
    @Test("A normal reply becomes rolling/weekly/monthly, shortest first")
    func normalReply() throws {
        let windows = OpenCodeGoUsageService.windows(from: try Self.reply("opencode-go-normal"))

        #expect(windows.map(\.id) == ["rolling", "weekly", "monthly"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])
        #expect(abs(windows[0].usedFraction - 0.425) < 0.000_001)
        #expect(abs(windows[1].usedFraction - 0.10) < 0.000_001)
        #expect(abs(windows[2].usedFraction - 0.05) < 0.000_001)
        #expect(windows.allSatisfy { !$0.isExhausted })

        // Milliseconds and bare-second ISO stamps both parse.
        #expect(windows[0].resetsAt == Self.dateComponents(2026, 9, 26, 18))
        #expect(windows[2].resetsAt == Self.dateComponents(2026, 10, 1, 0))
    }

    // MARK: - Missing fields

    /// A window with no `percent` at all draws nothing for that window — not
    /// a zero — while the windows that do report one are unaffected.
    @Test("A window with no percent is left out; the others are unaffected")
    func partialReplyDropsOnlyTheMissingWindow() throws {
        let windows = OpenCodeGoUsageService.windows(from: try Self.reply("opencode-go-partial"))
        #expect(windows.map(\.id) == ["rolling"])
        #expect(abs(windows[0].usedFraction - 0.12) < 0.000_001)
    }

    @Test("An empty usage block draws nothing")
    func emptyUsageBlockDrawsNothing() throws {
        #expect(OpenCodeGoUsageService.windows(from: try Self.reply("opencode-go-empty")).isEmpty)
    }

    @Test("No usage key at all draws nothing, not a crash")
    func noUsageKeyDrawsNothing() throws {
        #expect(OpenCodeGoUsageService.windows(from: try Self.decode("{}")).isEmpty)
    }

    // MARK: - Exhausted

    /// **The provider's own verdict, not the arithmetic.** A `status` other
    /// than `"ok"` is treated as spent even though `percent` here is only 8% —
    /// erring towards "you're blocked" is the safer way to be wrong.
    @Test("A status other than ok is exhausted regardless of the percentage")
    func nonOkStatusIsExhausted() throws {
        let windows = OpenCodeGoUsageService.windows(from: try Self.reply("opencode-go-blocked"))
        let rolling = try #require(windows.first { $0.id == "rolling" })
        #expect(abs(rolling.usedFraction - 0.08) < 0.000_001)
        #expect(rolling.isExhausted)
    }

    @Test("A missing status defaults to ok, not exhausted")
    func missingStatusDefaultsToOK() throws {
        let reply = try Self.decode(#"{"usage":{"rolling":{"percent":1,"resetsAt":"2026-09-26T18:00:00.000Z"}}}"#)
        let window = try #require(OpenCodeGoUsageService.windows(from: reply).first)
        #expect(!window.isExhausted)
    }

    // MARK: - Unreadable reply

    /// The same decode `fetch()` relies on: a reply that fails to parse at all
    /// becomes `.unreadableReply` there. The HTTP status mapping (401 / 403 /
    /// 429 / other) is a plain `switch` inline in `fetch()`, not a separate
    /// function — including the deliberate choice of `.apiKeyRefused` over
    /// `.signInRequired`, which names Codex — so it needs a real network call
    /// to reach and is not exercised here.
    @Test("A reply that is not valid JSON fails to decode")
    func garbageReplyFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(OpenCodeGoUsageService.Reply.self, from: Data("not json at all".utf8))
        }
    }
}
