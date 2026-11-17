import Foundation
import Testing
@testable import Pulse

/// Cursor's `usage-summary` reply, reconstructed from `CursorUsageService`'s
/// own `Reply` fields and [Docs/providers/cursor.md](../../Docs/providers/cursor.md)
/// — not captured from a live account. The weekly plan's `get-plan-info` and
/// `get-current-period-usage` replies *are* captured, from a Premium account on
/// 2026-10-16, with the marketing and model lists trimmed.
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

    /// The balance as every reported amount is written (`Money.reported`):
    /// "$", never "US$", whatever the language.
    private static func dollars(_ amount: Double) -> String {
        Money.reported(amount, code: "USD")
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

    // MARK: - A weekly plan

    private static func planInfo(_ name: String) throws -> CursorUsageService.PlanInfoReply.PlanInfo {
        let reply = try JSONDecoder().decode(CursorUsageService.PlanInfoReply.self, from: try fixture(name))
        return try #require(reply.planInfo)
    }

    private static func periodUsage(_ name: String) throws -> CursorUsageService.PeriodUsageReply {
        try JSONDecoder().decode(CursorUsageService.PeriodUsageReply.self, from: try fixture(name))
    }

    /// #87: on a Premium account the usage summary reports both pools at 0%
    /// while the week is a third gone.
    @Test("A weekly plan's week takes the place of the two monthly pools")
    func weeklyPlanReplacesThePools() throws {
        let plan = try Self.planInfo("cursor-plan-info-weekly")
        #expect(plan.isWeekly)

        let summary = CursorUsageService.windows(from: try Self.reply("cursor-ondemand"))
        let windows = CursorUsageService.weeklyWindows(
            plan: plan, usage: try Self.periodUsage("cursor-period-usage-weekly"), summary: summary
        )

        #expect(windows.map(\.id) == ["weekly", "onDemand"])
        let week = windows[0]
        #expect(week.kind == .weekly)
        #expect(abs(week.usedFraction - 0.3551462621885157) < 0.000_000_1)
        #expect(week.resetsAt == Date(timeIntervalSince1970: 1_792_475_010.907))
        #expect(week.reportsLength)
        #expect(!week.isExhausted)
    }

    @Test("A monthly plan is not weekly, so the summary's pools stand")
    func monthlyPlanIsNotWeekly() throws {
        #expect(try !Self.planInfo("cursor-plan-info-monthly").isWeekly)
    }

    @Test("The period may come as its number, and an unknown one is not weekly")
    func periodByNumber() throws {
        func period(_ json: String) throws -> Bool {
            let reply = try JSONDecoder().decode(
                CursorUsageService.PlanInfoReply.self, from: Data(#"{"planInfo":{"includedUsagePeriod":\#(json)}}"#.utf8)
            )
            return try #require(reply.planInfo).isWeekly
        }
        #expect(try period("2"))
        #expect(try !period("1"))
        #expect(try !period(#""INCLUDED_USAGE_PERIOD_FORTNIGHTLY""#))
    }

    /// No figure is no window — a week drawn at 0% would be the same mistake
    /// as the pools.
    @Test("A weekly plan with no figure draws no week, never a zero")
    func weeklyPlanWithoutAFigure() throws {
        let windows = CursorUsageService.weeklyWindows(
            plan: try Self.planInfo("cursor-plan-info-weekly"),
            usage: try Self.periodUsage("cursor-period-usage-no-figure"),
            summary: CursorUsageService.windows(from: try Self.reply("cursor-normal"))
        )
        #expect(windows.isEmpty)
    }

    // MARK: - Unreadable reply

    /// The same decode `fetch()` relies on: a reply that fails to parse at
    /// all becomes `.unreadableReply` there. The HTTP status mapping (401 /
    /// 403 / 429 / other) lives in the private `read`, alongside the request,
    /// so it is not exercised here — it would need a real network call to
    /// reach.
    @Test("A reply that is not valid JSON fails to decode")
    func garbageReplyFailsToDecode() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CursorUsageService.Reply.self, from: Data("not json at all".utf8))
        }
    }

    // MARK: - The cycle's stated length (#111)

    private static func summary(start: String?, end: String?) throws -> CursorUsageService.Reply {
        var fields: [String: Any] = [
            "membershipType": "pro",
            "individualUsage": [
                "plan": ["enabled": true, "used": 500, "limit": 2000, "remaining": 1500,
                         "autoPercentUsed": 10, "apiPercentUsed": 2],
                "onDemand": ["enabled": true, "used": 350, "limit": 1000, "remaining": 650],
            ],
        ]
        if let start { fields["billingCycleStart"] = start }
        if let end { fields["billingCycleEnd"] = end }
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(CursorUsageService.Reply.self, from: data)
    }

    @Test("Both cycle ends give every window the cycle's real length")
    func bothEndsGiveTheLength() throws {
        let windows = CursorUsageService.windows(from: try Self.summary(
            start: "2026-10-01T00:00:00.000Z", end: "2026-11-01T00:00:00.000Z"
        ))
        #expect(windows.map(\.id) == ["cursorModels", "otherModels", "onDemand"])
        // October has 31 days: the length is the stamps', not a flat thirty.
        #expect(windows.allSatisfy { $0.windowSeconds == 31 * 86_400 })
        #expect(windows.allSatisfy { $0.reportsLength })
        #expect(windows.allSatisfy { $0.resetsAt == Date(timeIntervalSince1970: 1_793_491_200) })

        // Ten of thirty-one days gone is the clock's fraction.
        let tenDaysIn = Date(timeIntervalSince1970: 1_793_491_200 - 21 * 86_400)
        let elapsed = try #require(windows[0].elapsedFraction(at: tenDaysIn))
        #expect(abs(elapsed - 10.0 / 31.0) < 0.000_001)
    }

    @Test("Without both cycle ends the thirty days stay a sort key")
    func oneEndKeepsTheSortKey() throws {
        for reply in [
            try Self.summary(start: nil, end: "2026-11-01T00:00:00.000Z"),
            try Self.summary(start: "2026-10-01T00:00:00.000Z", end: nil),
            // An end before its start is not a length either.
            try Self.summary(start: "2026-11-01T00:00:00.000Z", end: "2026-10-01T00:00:00.000Z"),
        ] {
            let windows = CursorUsageService.windows(from: reply)
            #expect(windows.count == 3)
            #expect(windows.allSatisfy { $0.windowSeconds == 30 * 86_400 })
            #expect(windows.allSatisfy { !$0.reportsLength })
            #expect(windows.allSatisfy { $0.elapsedFraction(at: Date()) == nil })
        }
    }

    @Test("The plan-money fallback takes the stated length too")
    func moneyFallbackTakesTheLength() throws {
        let windows = CursorUsageService.windows(from: try Self.reply("cursor-enterprise-overall"))
        let plan = try #require(windows.first { $0.id == "plan" })
        #expect(plan.windowSeconds == 31 * 86_400)
        #expect(plan.reportsLength)
    }
}
