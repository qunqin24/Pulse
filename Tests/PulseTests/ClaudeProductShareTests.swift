import Foundation
import Testing
@testable import Pulse

/// Token spend's estimate for every Claude product: the week's split by
/// product from the usage reply, and Claude Code's measured amount divided by
/// its part.
///
/// The split is undocumented, so most of what is pinned here is that an odd or
/// missing field yields no estimate rather than a guessed one.
@Suite("Claude product share")
struct ClaudeProductShareTests {
    private func fixture(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func reply(_ rows: [[String: Any]]) -> [String: Any] {
        ["seven_day_breakdown": ["rows": rows]]
    }

    @Test("reads every row of the split, in the reply's order")
    func readsRows() throws {
        let share = try #require(ClaudeProductShare.parse(try fixture("claude-usage-breakdown")))
        #expect(share.rows.map(\.key) == ["claude_code", "chat", "cowork", "duet", "other"])
        #expect(share.rows.map(\.name) == ["Claude Code", "Chats", "Cowork", "Claude Duet", "Other"])
        #expect(share.rows.map(\.percent) == [92, 0, 3, 5, 0])
    }

    @Test("$1,200 of Claude Code at 92% is about $1,304 in all")
    func scalesClaudeCode() throws {
        let share = try #require(ClaudeProductShare.parse(try fixture("claude-usage-breakdown")))
        let whole = try #require(share.estimatedTotal(fromClaudeCode: 1200))
        #expect(abs(whole - 1200 / 0.92) < 1e-9)
        #expect(Int(whole.rounded()) == 1304)
    }

    @Test("the parts add up to the whole and Claude Code's part is the measured amount")
    func partsReconcile() throws {
        let share = try #require(ClaudeProductShare.parse(try fixture("claude-usage-breakdown")))
        let whole = try #require(share.estimatedTotal(fromClaudeCode: 1200))
        #expect(abs(share.parts.reduce(0) { $0 + $1.fraction } - 1) < 1e-9)
        let code = try #require(share.parts.first { $0.id == "claude_code" })
        #expect(abs(whole * code.fraction - 1200) < 1e-9)
    }

    @Test("rows rounded to 101 are taken against their own sum")
    func normalisesRounding() throws {
        let share = try #require(ClaudeProductShare.parse(reply([
            ["key": "claude_code", "display_name": "Claude Code", "percent": 51],
            ["key": "chat", "display_name": "Chats", "percent": 50],
        ])))
        #expect(abs(try #require(share.claudeCodeFraction) - 51.0 / 101.0) < 1e-12)
    }

    @Test("no split, no estimate")
    func missingSplit() throws {
        #expect(ClaudeProductShare.parse([:]) == nil)
        #expect(ClaudeProductShare.parse(["seven_day_breakdown": NSNull()]) == nil)
        #expect(ClaudeProductShare.parse(["seven_day_breakdown": ["rows": "x"]]) == nil)
        #expect(ClaudeProductShare.parse(reply([])) == nil)
    }

    @Test("odd rows are skipped, not repaired")
    func oddRows() throws {
        let share = try #require(ClaudeProductShare.parse(reply([
            ["key": "claude_code", "percent": 80],
            ["display_name": "No key", "percent": 10],
            ["key": "chat", "percent": "ten"],
            ["key": "cowork", "percent": 140],
            ["key": "other", "percent": -5],
            ["key": "duet", "percent": 20.0],
        ])))
        #expect(share.rows.map(\.key) == ["claude_code", "duet"])
        // A row with no display name keeps its key as its name.
        #expect(share.rows.first?.name == "claude_code")
    }

    @Test("no Claude Code row, or a zero one, gives nothing to divide by")
    func noClaudeCode() throws {
        let without = try #require(ClaudeProductShare.parse(reply([["key": "chat", "percent": 100]])))
        #expect(without.claudeCodeFraction == nil)
        #expect(without.estimatedTotal(fromClaudeCode: 1200) == nil)

        let zero = try #require(ClaudeProductShare.parse(reply([
            ["key": "claude_code", "percent": 0],
            ["key": "chat", "percent": 100],
        ])))
        #expect(zero.claudeCodeFraction == nil)
        #expect(zero.estimatedTotal(fromClaudeCode: 1200) == nil)
    }

    @Test("nothing measured, nothing to scale")
    func nothingMeasured() throws {
        let share = try #require(ClaudeProductShare.parse(try fixture("claude-usage-breakdown")))
        #expect(share.estimatedTotal(fromClaudeCode: 0) == nil)
        #expect(share.estimatedTotal(fromClaudeCode: .nan) == nil)
    }

    @Test("the split survives a relaunch")
    func roundTrip() throws {
        let suite = "ClaudeProductShareTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ClaudeProductShare.stored(in: defaults) == nil)
        let share = try #require(ClaudeProductShare.parse(
            try fixture("claude-usage-breakdown"),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        ClaudeProductShare.store(share, in: defaults)
        #expect(ClaudeProductShare.stored(in: defaults) == share)

        defaults.set(Data("not json".utf8), forKey: ClaudeProductShare.defaultsKey)
        #expect(ClaudeProductShare.stored(in: defaults) == nil)
    }

    @Test("the setting is on unless turned off, and is kept")
    func settingRoundTrip() throws {
        let suite = "ClaudeProductShareTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppSettings.storedEstimatesAllClaudeProducts(in: defaults))
        AppSettings.storeEstimatesAllClaudeProducts(false, in: defaults)
        #expect(AppSettings.storedEstimatesAllClaudeProducts(in: defaults) == false)
    }
}
