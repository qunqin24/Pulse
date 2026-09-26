import Foundation
import Testing
@testable import Pulse

/// Grok Bot's dashboard call is Cursor's own private RPC, not published API,
/// and nobody here holds a Cursor plan that includes it to capture a reply
/// from. Every fixture below is built by hand from the field names
/// `GrokBotUsageService` decodes and from `Docs/providers/grok-bot.md` — not
/// captured from a live account.
@Suite("Grok Bot parsing")
struct GrokBotParsingTests {
    private static func reply(_ name: String) throws -> GrokBotUsageService.Reply {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode(GrokBotUsageService.Reply.self, from: try Data(contentsOf: url))
    }

    // MARK: - A normal reply

    @Test("A normal reply becomes one weekly window with a stated reset")
    func normalReplyBecomesOneWeeklyWindow() throws {
        let window = try #require(GrokBotUsageService.window(from: try Self.reply("grok-bot-normal")))

        #expect(window.id == "grokBot")
        #expect(window.kind == .weekly)
        #expect(abs(window.usedFraction - 0.30) < 0.000_001)
        #expect(window.windowSeconds == 7 * 86_400)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_767_830_400)) // 2026-01-08T00:00:00Z
        // Seven days are a sort key here, never a divisor — the opposite of
        // Grok's own weekly pool.
        #expect(!window.reportsLength)
        #expect(!window.isExhausted)
    }

    /// Cursor's dashboard REST call and the Connect RPC behind it were both
    /// observed with no `nextResetTimestampUtc` at implementation time. The
    /// row simply has no reset line rather than falling back to
    /// `currentPeriodStart + 7 days`, which the vendor's own client does not
    /// do either.
    @Test("A reply that never states a reset draws a window with no reset line")
    func noStatedResetMeansNoResetLine() throws {
        let window = try #require(GrokBotUsageService.window(from: try Self.reply("grok-bot-no-reset")))
        #expect(window.resetsAt == nil)
        #expect(!window.reportsLength)
    }

    // MARK: - Presence rules, the opposite of Grok's

    /// Cursor's schema declares `usage_percent` with explicit presence
    /// (`opt: true`): absent means unset, not a zero the serialiser dropped.
    /// This is the **opposite** of `GrokUsageService`, whose proto3 scalar
    /// treats an absent percentage inside a running period as zero.
    @Test("An absent usagePercent produces no window, even on an included plan")
    func absentPercentageProducesNoWindowEvenWhenIncluded() throws {
        #expect(GrokBotUsageService.window(from: try Self.reply("grok-bot-percent-absent-included")) == nil)
    }

    /// Nothing included is not nothing used: a plan without Grok Bot answers
    /// 0% too, with the rest of the reply given over to upgrade marketing.
    /// Drawn literally that is a full green ring for something the account
    /// does not have, so the flags must say the plan actually includes it
    /// before a figure of nothing is believed to mean nothing used.
    @Test("A plan that excludes Grok Bot draws no window despite a 0% figure")
    func excludedPlanDrawsNoWindowDespiteZeroPercent() throws {
        #expect(GrokBotUsageService.window(from: try Self.reply("grok-bot-not-included")) == nil)
    }

    @Test("Excluded via includedLimitZero is reported as not included, not unreadable")
    func excludedIsReportedAsNotIncluded() throws {
        let reply = try Self.reply("grok-bot-not-included")
        #expect(GrokBotUsageService.absence(reply) == .grokBotNotIncluded)
    }

    /// A seat drawing on the organisation's pot has no personal allowance
    /// either, and is the same "not included" message as a plan that simply
    /// lacks the feature.
    @Test("A pooled enterprise allowance is also not included")
    func pooledEnterpriseAllowanceIsNotIncluded() throws {
        let reply = try JSONDecoder().decode(GrokBotUsageService.Reply.self, from: Data(#"""
            {"usagePercent": 0, "usesPooledEnterpriseAllowance": true, "hasNonZeroIncludedLimit": true}
            """#.utf8))
        #expect(GrokBotUsageService.window(from: reply) == nil)
        #expect(GrokBotUsageService.absence(reply) == .grokBotNotIncluded)
    }

    /// A reply carrying none of the three entitlement flags at all was one
    /// this parser could not read — a shape change, not a confident claim
    /// about the subscription. Reading it as "not included" would send
    /// someone looking for an upgrade that has nothing to do with the actual
    /// problem.
    @Test("A reply saying nothing about entitlement at all is unreadable, not excluded")
    func replySayingNothingIsUnreadable() throws {
        let reply = try Self.reply("grok-bot-unreadable")
        #expect(GrokBotUsageService.window(from: reply) == nil)
        #expect(GrokBotUsageService.absence(reply) == .unreadableReply)
    }

    // MARK: - Spent

    @Test("A usagePercent of 100 marks the window exhausted")
    func usagePercentOf100MarksExhausted() throws {
        let window = try #require(GrokBotUsageService.window(from: try Self.reply("grok-bot-exhausted")))
        #expect(window.usedFraction == 1)
        #expect(window.isExhausted)
    }
}
