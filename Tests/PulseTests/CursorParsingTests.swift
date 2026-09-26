import Foundation
import Testing
@testable import Pulse

/// Cursor's `usage-summary` reply, reconstructed from `CursorUsageService`'s
/// own `Reply` fields and [Docs/providers/cursor.md](../../Docs/providers/cursor.md)
/// — not captured from a live account.
@Suite("Cursor parsing")
struct CursorParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static func reply(_ name: String) throws -> CursorUsageService.Reply {
        try JSONDecoder().decode(CursorUsageService.Reply.self, from: try fixture(name))
    }

    private static let resetDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static func dollars(_ amount: Double) -> String {
        amount.formatted(
            .currency(code: "USD").precision(.fractionLength(2)).locale(LocalizationSource.locale)
        )
    }

    // MARK: - The two pools

    @Test("A normal reply becomes the two model pools, the plan name, and the balance")
    func normalReply() throws {
        let reply = try Self.reply("cursor-normal")
        let windows = CursorUsageService.windows(from: reply)

        #expect(windows.map(\.id) == ["cursorModels", "otherModels"])
        #expect(windows.map(\.kind) == [.monthly, .monthly])
        #expect(windows.map(\.scope) == ["Cursor Models", "Other Models"])
        #expect(windows.allSatisfy { $0.resetsAt == Self.resetDate })
        #expect(windows.allSatisfy { !$0.reportsLength })
        #expect(windows.allSatisfy { !$0.isExhausted })

        #expect(CursorUsageService.planName(reply.membershipType) == "Pro+")
        #expect(CursorUsageService.remaining(reply) == Self.dollars(8))
    }

    /// **The two fields are percentages, not fractions.** `autoPercentUsed`
    /// arrives as `0.0267`, meaning 0.0267% — dividing by 100 a second time,
    /// or not at all, would be a hundredfold error either way.
    @Test("A pool's percentage is divided by 100, not read as a fraction")
    func percentagesAreNotFractions() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-normal"))

        #expect(abs(windows[0].usedFraction - 0.000267) < 0.000_000_1)
        #expect(abs(windows[1].usedFraction - 0.0005) < 0.000_000_1)
        // Both are non-zero, so `UsageWindow.percentText`'s "some is never 0%"
        // rule rounds up to 1% for display — a different provider's own rule,
        // not this file's, but worth confirming the tiny fraction survives it.
        #expect(windows[0].percentText == "1%")
    }

    // MARK: - On-demand spend

    @Test("On-demand spend is a third window only once the account has turned it on")
    func onDemandIsAThirdWindowWhenEnabled() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-ondemand"))

        #expect(windows.map(\.id) == ["cursorModels", "otherModels", "onDemand"])
        #expect(windows.last?.kind == .spend)
        #expect(abs(windows.last!.usedFraction - 0.35) < 0.000_001)
        #expect(windows.last?.isExhausted == false)
    }

    /// `cursor-normal`'s `onDemand.enabled` is `false` — a row reading "0% of
    /// nothing" says less than no row at all, so it is left out entirely
    /// rather than drawn at 0%.
    @Test("On-demand spend the account has not turned on draws no window")
    func onDemandOffIsNotAWindow() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-normal"))
        #expect(!windows.contains { $0.id == "onDemand" })
    }

    // MARK: - The fallback

    /// **A different denominator.** With no pools reported at all, the only
    /// figure left is the plan's cash value, so that becomes the one window
    /// there is — never added beside the pools, which would read as a third,
    /// contradictory limit.
    @Test("An account with no pools falls back to the plan's money")
    func fallbackWhenNoPoolsReported() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-fallback-no-pools"))

        #expect(windows.map(\.id) == ["plan"])
        #expect(windows[0].kind == .monthly)
        #expect(abs(windows[0].usedFraction - 0.25) < 0.000_001)
        #expect(!windows[0].reportsLength)
    }

    // MARK: - Team accounts

    @Test("A team account's pooled/onDemand pair stands in for the individual one")
    func teamAccountSubstitution() throws {
        let reply = try Self.reply("cursor-team")
        let windows = CursorUsageService.windows(from: reply)

        #expect(windows.map(\.id) == ["cursorModels", "otherModels", "onDemand"])
        #expect(abs(windows[0].usedFraction - 0.15) < 0.000_001)
        #expect(abs(windows[1].usedFraction - 0.03) < 0.000_001)
        #expect(abs(windows[2].usedFraction - 0.2) < 0.000_001)
        #expect(CursorUsageService.remaining(reply) == Self.dollars(70))
    }

    // MARK: - Nothing reported

    @Test("Missing pools and missing plan money draw nothing, never a zero")
    func missingFieldsDrawNothing() throws {
        let reply = try Self.reply("cursor-missing-fields")

        #expect(CursorUsageService.windows(from: reply).isEmpty)
        #expect(CursorUsageService.planName(reply.membershipType) == nil)
        #expect(CursorUsageService.remaining(reply) == nil)
    }

    // MARK: - Exhausted

    @Test("A pool at or over 100% is exhausted; one at 0 is not")
    func exhaustedPool() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-exhausted"))

        #expect(windows[0].usedFraction == 1) // clamped, even though the reply says 105.
        #expect(windows[0].isExhausted)
        #expect(windows[1].usedFraction == 0)
        #expect(!windows[1].isExhausted)
    }

    // MARK: - Plan names

    @Test("An unfamiliar plan name is tidied and passed through, never blanked")
    func planNameMapping() {
        #expect(CursorUsageService.planName("pro_plus") == "Pro+")
        #expect(CursorUsageService.planName("free") == "Free")
        #expect(CursorUsageService.planName("mystery_tier") == "Mystery Tier")
        #expect(CursorUsageService.planName("") == nil)
        #expect(CursorUsageService.planName(nil) == nil)
    }

    // MARK: - Unreadable reply

    /// The same decode `fetch()` relies on: a reply that fails to parse at
    /// all becomes `.unreadableReply` there. The HTTP status mapping (401 /
    /// 403 / 429 / other) is a plain `switch` inline in `fetch()`, not a
    /// separate function, so it is not exercised here — it would need a real
    /// network call to reach.
    @Test("A reply that is not valid JSON fails to decode")
    func garbageReplyFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CursorUsageService.Reply.self, from: Data("not json at all".utf8))
        }
    }
}
