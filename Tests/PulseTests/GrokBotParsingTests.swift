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
        // Both ends stated, so their difference is a measured length (#111).
        #expect(window.reportsLength)
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

    // MARK: - The period's stated length (#111)

    private static func reply(start: String?, reset: String?) throws -> GrokBotUsageService.Reply {
        var fields: [String: Any] = [
            "usagePercent": 30,
            "hasNonZeroIncludedLimit": true,
            "includedLimitZero": false,
            "usesPooledEnterpriseAllowance": false,
        ]
        if let start { fields["currentPeriodStart"] = start }
        if let reset { fields["nextResetTimestampUtc"] = reset }
        return try JSONDecoder().decode(
            GrokBotUsageService.Reply.self, from: try JSONSerialization.data(withJSONObject: fields)
        )
    }

    @Test("A start and a reset make the period's length, which the clock divides by")
    func bothStampsGiveTheLength() throws {
        let window = try #require(GrokBotUsageService.window(from: try Self.reply(
            start: "2026-01-01T12:00:00Z", reset: "2026-01-08T00:00:00Z"
        )))
        // Six and a half days: the stamps' difference, not seven.
        #expect(window.windowSeconds == 6 * 86_400 + 12 * 3_600)
        #expect(window.reportsLength)
        let halfway = Date(timeIntervalSince1970: 1_767_830_400 - 3 * 86_400 - 6 * 3_600)
        let elapsed = try #require(window.elapsedFraction(at: halfway))
        #expect(abs(elapsed - 0.5) < 0.000_001)
    }

    @Test("A reset without a start, or a start without a reset, draws no clock")
    func oneStampIsNoLength() throws {
        let resetOnly = try #require(GrokBotUsageService.window(from: try Self.reply(
            start: nil, reset: "2026-01-08T00:00:00Z"
        )))
        #expect(resetOnly.windowSeconds == 7 * 86_400)
        #expect(!resetOnly.reportsLength)
        #expect(resetOnly.resetsAt != nil)
        #expect(resetOnly.elapsedFraction(at: Date(timeIntervalSince1970: 1_767_600_000)) == nil)

        let startOnly = try #require(GrokBotUsageService.window(from: try Self.reply(
            start: "2026-01-01T00:00:00Z", reset: nil
        )))
        #expect(!startOnly.reportsLength)
        // The reset is never start + 7 days.
        #expect(startOnly.resetsAt == nil)

        let backwards = try #require(GrokBotUsageService.window(from: try Self.reply(
            start: "2026-01-08T00:00:00Z", reset: "2026-01-01T00:00:00Z"
        )))
        #expect(!backwards.reportsLength)

        // A month's start beside a weekly reset does not bound the week.
        let month = try #require(GrokBotUsageService.window(from: try Self.reply(
            start: "2025-12-08T00:00:00Z", reset: "2026-01-08T00:00:00Z"
        )))
        #expect(!month.reportsLength)
        #expect(month.windowSeconds == 7 * 86_400)
    }

    // MARK: - Primary credential resolution

    private static func jwt(expiry: TimeInterval) -> String {
        func base64URL(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(#"{"alg":"none"}"#)
        let payload = base64URL(#"{"sub":"auth0|user_test","exp":\#(Int(expiry))}"#)
        return "\(header).\(payload).sig"
    }

    private static func storedCredentials(token: String, expiresAt: Date = Date(timeIntervalSince1970: 4_102_444_800)) -> AccountCredentials {
        AccountCredentials(
            accessToken: token,
            refreshToken: "refresh-test",
            expiresAt: expiresAt,
            accountName: nil,
            accountID: nil
        )
    }

    @Test("A stored Settings web login takes precedence over Cursor's database")
    func storedWebLoginWinsWithoutAskingCursor() throws {
        let token = Self.jwt(expiry: 4_102_444_800)
        var askedCursor = false
        let resolved = GrokBotUsageService.primarySession(
            storedLogin: Self.storedCredentials(token: token),
            cursorLogin: {
                askedCursor = true
                return .absent
            }
        )
        let expected = try #require(CursorAppLogin.session(from: token))
        #expect(resolved == .session(expected, usesStoredLogin: true))
        #expect(!askedCursor)
    }

    @Test("An expired or unreadable stored web login fails closed without falling back to Cursor")
    func invalidStoredWebLoginDoesNotFallBackToCursor() {
        for badToken in [Self.jwt(expiry: 1), "not-a-jwt"] {
            var askedCursor = false
            let resolved = GrokBotUsageService.primarySession(
                storedLogin: Self.storedCredentials(token: badToken),
                cursorLogin: {
                    askedCursor = true
                    return .token(Self.jwt(expiry: 4_102_444_800))
                }
            )
            #expect(resolved == .unavailable(.signedOut))
            #expect(!askedCursor)
        }
    }

    @Test("Without a stored web login, primary falls back to Cursor's saved token or reports specific absences")
    func cursorFallbackResolution() async throws {
        let validToken = Self.jwt(expiry: 4_102_444_800)
        let validSession = try #require(CursorAppLogin.session(from: validToken))
        #expect(
            GrokBotUsageService.primarySession(storedLogin: nil, cursorLogin: { .token(validToken) })
                == .session(validSession, usesStoredLogin: false)
        )
        #expect(
            GrokBotUsageService.primarySession(storedLogin: nil, cursorLogin: { .absent })
                == .unavailable(.notSignedIn)
        )
        #expect(
            await GrokBotUsageService().fetch(storedLogin: nil, cursorLogin: { .absent }).state
                == .unavailable(.notSignedIn)
        )
        #expect(
            GrokBotUsageService.primarySession(storedLogin: nil, cursorLogin: { .keychainRefused })
                == .unavailable(.cursorKeyRefused)
        )
        #expect(
            GrokBotUsageService.primarySession(storedLogin: nil, cursorLogin: { .unreadable })
                == .unavailable(.cursorLoginExpired)
        )
        #expect(
            GrokBotUsageService.primarySession(storedLogin: nil, cursorLogin: { .token(Self.jwt(expiry: 1)) })
                == .unavailable(.cursorLoginExpired)
        )
    }

    @Test("Server refusal reason distinguishes Settings web login from Cursor's local login")
    func serverRefusalReasonMatchesSource() {
        #expect(GrokBotUsageService.refusedReason(usesStoredLogin: true) == .signedOut)
        #expect(GrokBotUsageService.refusedReason(usesStoredLogin: false) == .cursorLoginExpired)
        #expect(Provider.grokBot.soleRoute == nil)
    }
}
