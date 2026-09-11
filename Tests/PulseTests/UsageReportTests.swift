import Foundation
import Testing
@testable import Pulse

/// `Pulse --json`. The output is a contract that other people's status lines
/// are built on, so the shape is pinned here rather than left to whatever the
/// encoder happened to do last.
@Suite("JSON output")
struct UsageReportTests {
    private static let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(
        _ id: String,
        kind: UsageWindow.Kind = .weekly,
        used: Double,
        scope: String? = nil,
        seconds: Int = 7 * 86_400,
        reportsLength: Bool = true,
        estimate: UsageWindow.Estimate? = nil,
        resetsAt: Date? = nil
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: scope,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            estimate: estimate
        )
    }

    private static func reading(_ account: AccountKey, _ windows: [UsageWindow], observedAt: Date) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: windows,
            observedAt: observedAt,
            state: .stale,
            plan: "Max 5x",
            creditBalance: nil
        )
    }

    /// Decoded back to plain JSON, so the assertions are about what a script
    /// actually receives rather than about Swift types.
    private static func object(
        rail: AppSettings.StoredRail,
        readings: [String: ProviderUsage]
    ) throws -> [String: Any] {
        let data = try #require(UsageReport.encode(rail: rail, readings: readings, generatedAt: generatedAt))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func accounts(_ root: [String: Any]) throws -> [[String: Any]] {
        try #require(root["accounts"] as? [[String: Any]])
    }

    @Test("Every account on the rail appears, in rail order, reading or not")
    func railOrderAndGaps() throws {
        let claude = AccountKey(.claudeCode)
        let codex = AccountKey(.codex)
        let rail = AppSettings.StoredRail(accounts: [codex, claude], labels: [:], pinnedWindows: [:])

        let root = try Self.object(
            rail: rail,
            readings: [claude.id: Self.reading(claude, [Self.window("w", used: 0.5)], observedAt: Self.generatedAt)]
        )
        let list = try Self.accounts(root)

        #expect(list.map { $0["id"] as? String } == ["codex", "claudeCode"])
        // The one with nothing banked is present and plainly empty, rather
        // than missing — a script should be able to see that Pulse knows
        // about it and has no figures.
        #expect(list[0]["observedAt"] == nil)
        #expect((list[0]["windows"] as? [Any])?.isEmpty == true)
        #expect(list[0]["headline"] == nil)
    }

    @Test("The figure matches the one the ring shows")
    func percentagesFollowTheDisplayRule() throws {
        let account = AccountKey(.cursor)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])

        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(
            account,
            [Self.window("tiny", used: 0.0003), Self.window("nearly", used: 0.996)],
            observedAt: Self.generatedAt
        )])
        let windows = try #require(try Self.accounts(root)[0]["windows"] as? [[String: Any]])

        // Anything used never reads 0%, and not quite full never reads 100%.
        #expect(windows[0]["usedPercent"] as? Int == 1)
        #expect(windows[1]["usedPercent"] as? Int == 99)
        // And the raw reading is there too, for anything doing its own sums.
        #expect(windows[0]["usedFraction"] as? Double == 0.0003)
    }

    @Test("The headline is the fullest limit, or the pinned one")
    func headlineFollowsThePin() throws {
        let account = AccountKey(.codex)
        let windows = [Self.window("small", used: 0.2), Self.window("big", used: 0.8)]
        let readings = [account.id: Self.reading(account, windows, observedAt: Self.generatedAt)]

        let byDefault = try Self.object(
            rail: AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:]),
            readings: readings
        )
        let head = try #require(try Self.accounts(byDefault)[0]["headline"] as? [String: Any])
        #expect(head["windowId"] as? String == "big")
        #expect(head["usedPercent"] as? Int == 80)

        let pinned = try Self.object(
            rail: AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [account.id: "small"]),
            readings: readings
        )
        #expect((try Self.accounts(pinned)[0]["headline"] as? [String: Any])?["windowId"] as? String == "small")
    }

    @Test("Window kinds are flat tokens a script can switch on")
    func kindTokens() throws {
        let account = AccountKey(.openCodeGo)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])

        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(account, [
            Self.window("a", kind: .fiveHour, used: 0.1),
            Self.window("b", kind: .weekly, used: 0.1),
            Self.window("c", kind: .spend, used: 0.1),
            Self.window("d", kind: .monthly, used: 0.1),
            Self.window("e", kind: .other(seconds: 10_800), used: 0.1)
        ], observedAt: Self.generatedAt)])
        let windows = try #require(try Self.accounts(root)[0]["windows"] as? [[String: Any]])

        #expect(windows.map { $0["kind"] as? String } == ["fiveHour", "weekly", "spend", "monthly", "other:10800"])
    }

    @Test("Nothing translated is printed")
    func nothingLocalizedLeaks() throws {
        let account = AccountKey(.claudeCode)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])
        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(
            account, [Self.window("w", used: 0.5, scope: "Opus")], observedAt: Self.generatedAt
        )])
        let window = try #require((try Self.accounts(root)[0]["windows"] as? [[String: Any]])?.first)

        // `UsageWindow.name` is localized and would change under a script's
        // feet, so it is deliberately not a field. `scope` is a product name.
        #expect(window["name"] == nil)
        #expect(window["scope"] as? String == "Opus")
    }

    @Test("Age is reported so nothing has to be assumed current")
    func ageIsReported() throws {
        let account = AccountKey(.codex)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])
        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(
            account, [Self.window("w", used: 0.5)], observedAt: Self.generatedAt.addingTimeInterval(-900)
        )])
        let entry = try Self.accounts(root)[0]

        #expect(entry["ageSeconds"] as? Int == 900)
        #expect(entry["observedAt"] as? String == "2027-01-15T07:45:00Z")
        #expect(root["generatedAt"] as? String == "2027-01-15T08:00:00Z")
    }

    @Test("A sort key is flagged rather than passed off as a length")
    func sortKeysAreFlagged() throws {
        let account = AccountKey(.kimiCode)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])
        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(account, [
            Self.window("rolling", used: 0.3, reportsLength: false)
        ], observedAt: Self.generatedAt)])
        let window = try #require((try Self.accounts(root)[0]["windows"] as? [[String: Any]])?.first)

        #expect(window["reportsLength"] as? Bool == false)
    }

    /// The contract's answer to "is this figure the provider's own?", which is
    /// the whole promise `--json` makes. It has to be on **every** window, not
    /// only the one that sets it, or a script cannot filter on its absence.
    @Test("An inferred denominator is flagged, and the flag is on every window")
    func inferredDenominatorsAreFlagged() throws {
        let account = AccountKey(.commandCode)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])
        let root = try Self.object(rail: rail, readings: [account.id: Self.reading(account, [
            Self.window("five-hour", kind: .fiveHour, used: 0.25, seconds: 5 * 3_600),
            Self.window("monthly", kind: .monthly, used: 0.58, seconds: 30 * 86_400, estimate: .planPrice),
        ], observedAt: Self.generatedAt)])
        let windows = try #require(try Self.accounts(root)[0]["windows"] as? [[String: Any]])

        #expect(windows.count == 2)
        #expect(windows.allSatisfy { $0["estimated"] != nil })
        #expect(windows.first { $0["id"] as? String == "five-hour" }?["estimated"] as? Bool == false)
        #expect(windows.first { $0["id"] as? String == "monthly" }?["estimated"] as? Bool == true)
        // Which inference, as a token a script can switch on rather than a
        // translated word.
        #expect(windows.first { $0["id"] as? String == "monthly" }?["estimatedFrom"] as? String == "planPrice")
        #expect(windows.first { $0["id"] as? String == "five-hour" }?["estimatedFrom"] == nil)
        // And it is a flag, not a translated word hidden in a product field.
        #expect(windows.allSatisfy { $0["scope"] == nil })
    }

    @Test("An added account is named by the user's own label")
    func addedAccountsCarryTheirLabel() throws {
        let extra = AccountKey(.claudeCode, slot: "work")
        let rail = AppSettings.StoredRail(accounts: [extra], labels: [extra.id: "Work"], pinnedWindows: [:])
        let entry = try Self.accounts(try Self.object(rail: rail, readings: [:]))[0]

        #expect(entry["id"] as? String == "claudeCode#work")
        #expect(entry["label"] as? String == "Work")
        // The product is still named, so a script can group by it.
        #expect(entry["name"] as? String == "Claude Code")
        #expect(entry["provider"] as? String == "claudeCode")
        #expect(entry["settingsURL"] as? String == "pulse://account/claudeCode%23work")
        #expect(entry["source"] == nil)
    }

    @Test("The JSON source is the reading's actual origin, not a route preference")
    func actualSource() throws {
        let account = AccountKey(.claudeCode)
        let rail = AppSettings.StoredRail(accounts: [account], labels: [:], pinnedWindows: [:])
        let reading = Self.reading(account, [Self.window("w", used: 0.5)], observedAt: Self.generatedAt)
            .recording(.desktopSession)
        let entry = try Self.accounts(try Self.object(rail: rail, readings: [account.id: reading]))[0]
        #expect(entry["source"] as? String == "desktopSession")
        #expect(entry["settingsURL"] as? String == "pulse://account/claudeCode")
    }
}
