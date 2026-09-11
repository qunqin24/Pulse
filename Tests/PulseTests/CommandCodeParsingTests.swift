import Foundation
import Testing
@testable import Pulse

/// Command Code's four reply shapes.
///
/// **The fixtures are second-hand.** Nobody here holds a Command Code account,
/// so these were written from the field names the shipped CLI reads —
/// `command-code` on npm, `dist/cli.mjs` — rather than captured from a live
/// one. That is the same standing Volcengine's fixtures have, and the reason
/// the awkward parts below are pinned rather than trusted. Replace them with a
/// real capture the first time somebody with an account can produce one. See
/// [Docs/providers/command-code.md](../../Docs/providers/command-code.md).
@Suite("Command Code parsing")
struct CommandCodeParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    private static func decode<Reply: Decodable>(_ type: Reply.Type, _ name: String) throws -> Reply {
        try JSONDecoder().decode(type, from: try fixture(name))
    }

    private static func reading(
        whoami: String? = "command-code-whoami",
        credits: String? = "command-code-credits",
        subscription: String? = "command-code-subscriptions",
        summary: String? = "command-code-summary"
    ) throws -> CommandCodeUsageService.Reading {
        CommandCodeUsageService.Reading(
            whoami: try whoami.map { try decode(CommandCodeUsageService.Whoami.self, $0) },
            credits: try credits.map { try decode(CommandCodeUsageService.CreditsReply.self, $0) },
            subscription: try subscription.map {
                try decode(CommandCodeUsageService.SubscriptionReply.self, $0)
            },
            summary: try summary.map { try decode(CommandCodeUsageService.SummaryReply.self, $0) }
        )
    }

    private static func windows() throws -> [UsageWindow] {
        CommandCodeUsageService.windows(from: try reading())
    }

    /// An account that never had a plan: no `planId` anywhere, so nothing
    /// names a grant and the pool is the only thing to measure.
    private static func neverOnAPlan() throws -> [UsageWindow] {
        CommandCodeUsageService.windows(
            from: try reading(credits: "command-code-credits-no-plan", subscription: nil)
        )
    }

    /// The same account with its plan lapsed: back on what it bought, which is
    /// a pool with both halves reported. The billing period is still stated,
    /// so this exercises the pool *and* its length.
    private static func offPlan() throws -> [UsageWindow] {
        CommandCodeUsageService.windows(
            from: try reading(subscription: "command-code-subscriptions-lapsed")
        )
    }

    // MARK: - Order and identity

    @Test("Every reported limit becomes a window, shortest first")
    func windowsAreOrderedShortestFirst() throws {
        let windows = try Self.windows()

        // "monthly", not "credits": an active plan is measured against its
        // grant, an account without one against what it bought.
        #expect(windows.map(\.id) == [
            "five-hour",                                // 5 hours
            "org.model.anthropic/claude-opus-5.daily",  // daily
            "weekly",                                   // 7 days
            "org.model.moonshotai/Kimi-K3.weekly",      // 7 days
            "org.org.monthly",                          // ~monthly
            "monthly",                                  // the billing period
        ])
        #expect(windows.map(\.windowSeconds) == windows.map(\.windowSeconds).sorted())
    }

    @Test("Two windows of equal length keep the order they were built in")
    func tiesDoNotShuffleBetweenRefreshes() throws {
        // A weekly rolling limit and a weekly org limit are both 7 days; the
        // monthly org limit and this fixture's 30-day billing period are both
        // 30. `sorted(by:)` is not stable, so this is the guard against those
        // four rows swapping places from one refresh to the next.
        let first = try Self.windows().map(\.id)
        for _ in 0..<8 {
            #expect(CommandCodeUsageService.windows(from: try Self.reading()).map(\.id) == first)
        }
    }

    @Test("Two limits of the same scope keep distinct ids")
    func idsStayUniqueWithinOneReading() throws {
        let ids = try Self.windows().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - The credit pool

    /// The plan grant, which is the one figure here that is inferred.
    ///
    /// Adding the three credit buckets together instead — the pool below — is
    /// wrong in the direction that hurts: it would draw this same subscriber at
    /// 43% while $12.50 of a $30 month is what is actually left.
    @Test("An active plan is measured against its grant, and says that it was estimated")
    func anActivePlanIsMeasuredAgainstItsGrant() throws {
        let monthly = try #require(try Self.windows().first { $0.id == "monthly" })

        // individual-pro grants 30; 12.5 left, so 17.5 of it is gone.
        #expect(abs(monthly.usedFraction - 17.5 / 30) < 0.000_001)
        #expect(monthly.kind == .monthly)
        #expect(monthly.isExhausted == false)
        // The label the card shows, because the denominator was not reported —
        // and a flag rather than a scope, so `--json` stays language-neutral.
        #expect(monthly.isEstimated)
        #expect(monthly.scope == nil)
        #expect(monthly.name.contains("estimated"))
        // And no pool row beside it: that answers a different question.
        #expect(try Self.windows().contains { $0.id == "credits" } == false)
    }

    /// The silent failure this design has, kept silent in the safe direction.
    @Test("A plan this build cannot size draws nothing at all — not zero, not the pool")
    func anUnknownPlanDrawsNothing() throws {
        let reading = try Self.reading(subscription: "command-code-subscriptions-unknown-plan")
        let windows = CommandCodeUsageService.windows(from: reading)

        #expect(windows.contains { $0.id == "monthly" } == false)
        #expect(windows.contains { $0.id == "credits" } == false)
        // The reported limits are untouched by a plan nobody can size.
        #expect(windows.contains { $0.id == "five-hour" })
        #expect(windows.contains { $0.id == "weekly" })
    }

    /// The subscription call is allowed to fail without sinking the reading, so
    /// its silence must not be read as "no plan" — that would answer with the
    /// pool, which is the wrong question and the wrong number.
    @Test("A subscription lookup that never answered still finds the plan in the credits reply")
    func aFailedSubscriptionLookupStillKnowsThePlan() throws {
        let windows = CommandCodeUsageService.windows(from: try Self.reading(subscription: nil))

        let monthly = try #require(windows.first { $0.id == "monthly" })
        #expect(abs(monthly.usedFraction - 17.5 / 30) < 0.000_001)
        // No period was stated, so the month is a sort key and nothing divides.
        #expect(monthly.reportsLength == false)
        #expect(windows.contains { $0.id == "credits" } == false)
    }

    @Test("A grant already spent reads as spent, whatever else is in the wallet")
    func aSpentGrantIsSpent() throws {
        // individual_go, underscored, with the grant at zero and $6 of top-up
        // still there. The top-up is not the plan and does not soften it.
        let windows = CommandCodeUsageService.windows(
            from: try Self.reading(whoami: nil, credits: "command-code-unlimited",
                                   subscription: nil, summary: nil)
        )
        let monthly = try #require(windows.first { $0.id == "monthly" })
        #expect(monthly.usedFraction == 1)
        #expect(monthly.isExhausted)
    }

    /// A plan that is cancelled, past due, trialing or simply gone is an
    /// account back on what it bought — and that pool has both halves.
    @Test("The pool is spent plus remaining, never a table in the client")
    func creditPoolIsTheAccountsOwnArithmetic() throws {
        let credits = try #require(try Self.offPlan().first { $0.id == "credits" })

        // 12.5 + 4 + 0.5 left, 13 spent → a pool of 30, 43.33% gone. The CLI
        // would have reached for its own `individual-pro` entry of 30 monthly
        // credits here; that it lands on the same figure is a coincidence of
        // this fixture, not the route taken.
        #expect(abs(credits.usedFraction - 13.0 / 30.0) < 0.000_001)
        #expect(credits.percentText == "43%")
        #expect(credits.isExhausted == false)
        #expect(credits.kind == .spend)
    }

    @Test("A period stated at both ends is a length; one stated at neither is not")
    func periodLengthOnlyWhenBothEndsAreGiven() throws {
        let stated = try #require(try Self.offPlan().first { $0.id == "credits" })
        #expect(stated.reportsLength)
        #expect(stated.windowSeconds == 30 * 86_400)

        // No plan and no subscription — a pay-as-you-go balance — leaves the
        // month as a sort key that nothing may divide by.
        let pool = try #require(try Self.neverOnAPlan().first { $0.id == "credits" })
        #expect(pool.reportsLength == false)
        #expect(pool.elapsedFraction(at: Date()) == nil)
    }

    /// The summary call is allowed to fail quietly, and its silence used to
    /// read as "nothing spent" — an untouched ring for an account that may be
    /// at the wall, which is the failure `CommandCodePlans` argues against at
    /// length for the plan grant.
    @Test("A summary that never arrived draws no pool at all, rather than an empty one")
    func withoutASummaryThereIsNoPool() throws {
        let windows = CommandCodeUsageService.windows(
            from: try Self.reading(subscription: "command-code-subscriptions-lapsed", summary: nil)
        )

        #expect(windows.contains { $0.id == "credits" } == false)
        // Everything the account did report is untouched by the one that failed.
        #expect(windows.contains { $0.id == "five-hour" })
        #expect(windows.contains { $0.id == "weekly" })
    }

    /// The loud half of the same mistake, and the reason it is worth a test:
    /// absent pots totalled zero, which put the whole pool in the numerator and
    /// drew a **full red ring with `isExhausted`** — which `UsageAlerts` then
    /// announces as a limit that is spent, about an account that said nothing.
    @Test("Credit fields that are absent are not a balance of zero")
    func absentCreditsAreNotAnEmptyWallet() throws {
        let credits = try JSONDecoder().decode(
            CommandCodeUsageService.CreditsReply.self,
            from: Data(#"{"success": true, "credits": {}}"#.utf8)
        )
        let reading = CommandCodeUsageService.Reading(
            whoami: nil,
            credits: credits,
            subscription: nil,
            summary: try Self.decode(CommandCodeUsageService.SummaryReply.self, "command-code-summary")
        )

        #expect(CommandCodeUsageService.windows(from: reading).isEmpty)
    }

    @Test("An account with nothing left and nothing spent reports no pool")
    func anEmptyAccountIsNotAFullOne() throws {
        let silent = CommandCodeUsageService.Reading(
            whoami: nil, credits: nil, subscription: nil, summary: nil
        )
        #expect(CommandCodeUsageService.windows(from: silent).isEmpty)
    }

    /// "The lookup failed" and "the lookup said you have no plan" are different
    /// answers, and the second one is the account's own word. Collapsing them
    /// drew a pay-as-you-go account against a $30 grant it does not receive,
    /// and hid the $200 of purchased credit it actually holds.
    @Test("A subscription reply that answered `none` is taken at its word")
    func anAnsweredAbsenceIsNotAFailedLookup() throws {
        let subscription = try JSONDecoder().decode(
            CommandCodeUsageService.SubscriptionReply.self,
            from: Data(#"{"success": true, "data": null}"#.utf8)
        )
        let windows = CommandCodeUsageService.windows(
            from: CommandCodeUsageService.Reading(
                whoami: nil,
                // Still names `individual-pro`, which is what the old rule read.
                credits: try Self.decode(CommandCodeUsageService.CreditsReply.self, "command-code-credits"),
                subscription: subscription,
                summary: try Self.decode(CommandCodeUsageService.SummaryReply.self, "command-code-summary")
            )
        )

        #expect(windows.contains { $0.id == "monthly" } == false)
        #expect(windows.contains { $0.id == "credits" })
    }

    // MARK: - Rolling windows

    @Test("`resetAt` on a window limit is epoch milliseconds")
    func rollingResetsAreMilliseconds() throws {
        let fiveHour = try #require(try Self.windows().first { $0.id == "five-hour" })
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1_788_780_000))
        #expect(abs(fiveHour.usedFraction - 0.25) < 0.000_001)
    }

    @Test("A window past its cap is spent, and the fraction stops at 100%")
    func aWindowOverItsCapIsSpent() throws {
        let weekly = try #require(try Self.windows().first { $0.id == "weekly" })
        // 21 of 20.
        #expect(weekly.usedFraction == 1)
        #expect(weekly.isExhausted)
    }

    @Test("Caps reported for an account that is not window-limited are not limits")
    func unlimitedAccountsShowNoWindows() throws {
        let windows = CommandCodeUsageService.windows(
            from: try Self.reading(whoami: nil, credits: "command-code-unlimited",
                                   subscription: nil, summary: nil)
        )
        // `limited: false`, so the five-hour cap in that reply is not something
        // the account is being held to and is not drawn as one.
        #expect(!windows.contains { $0.id == "five-hour" })
        #expect(windows.map(\.id) == ["monthly"])
    }

    // MARK: - Organisation spend limits

    @Test("Spend limits arrive already spent — no inversion")
    func orgLimitsAreNotInverted() throws {
        let daily = try #require(try Self.windows().first { $0.id == "org.model.anthropic/claude-opus-5.daily" })
        #expect(abs(daily.usedFraction - 0.9) < 0.000_001)
        #expect(daily.percentText == "90%")
        #expect(daily.scope == "Claude Opus 5")
    }

    @Test("`exceeded` is the account's verdict and outranks the arithmetic")
    func exceededOutranksThePercentage() throws {
        let weekly = try #require(try Self.windows().first { $0.id == "org.model.moonshotai/Kimi-K3.weekly" })
        // Two dollars of four is half the limit, and the account still says it
        // is done. Erring towards "you are blocked" is the safer mistake.
        #expect(abs(weekly.usedFraction - 0.5) < 0.000_001)
        #expect(weekly.isExhausted)
    }

    @Test("An org-wide limit is left unscoped")
    func orgWideLimitsCarryNoModelName() throws {
        let monthly = try #require(try Self.windows().first { $0.id == "org.org.monthly" })
        #expect(monthly.scope == nil)
        #expect(monthly.resetsAt != nil)
    }

    @Test("A day and a week are lengths; a month is only a sort key")
    func onlyExactIntervalsClaimALength() throws {
        let windows = try Self.windows()
        #expect(try #require(windows.first { $0.id == "org.model.anthropic/claude-opus-5.daily" }).reportsLength)
        #expect(try #require(windows.first { $0.id == "org.model.moonshotai/Kimi-K3.weekly" }).reportsLength)

        // 28 to 31 days stored as a flat 30, so nothing may divide by it.
        let monthly = try #require(windows.first { $0.id == "org.org.monthly" })
        #expect(monthly.reportsLength == false)
        #expect(monthly.elapsedFraction(at: Date()) == nil)
    }

    @Test("A limit missing its ceiling is dropped rather than guessed at")
    func limitsWithoutACeilingAreDropped() throws {
        // The fourth fixture row states `spent: 3` and no `limit` at all.
        // There is no denominator to build a fraction from, and a spend limit
        // shown at an invented ceiling is worse than one not shown.
        #expect(try Self.windows().count == 6)
        #expect(!(try Self.windows().contains { $0.id.hasSuffix(".total") }))
    }

    /// `-1` is the usual way to encode *unlimited*, and this side has never
    /// seen a live reply. Drawn as a ceiling already reached it would paint an
    /// untouched organisation solid red and have the alerts announce it spent.
    @Test("A ceiling of zero or less is not a denominator, so there is no row")
    func aCeilingWithNoRoomInItIsNotALimit() throws {
        for ceiling in ["-1", "0"] {
            let whoami = try JSONDecoder().decode(
                CommandCodeUsageService.Whoami.self,
                from: Data(#"{"orgLimits":[{"scope":"org","spent":4,"limit":\#(ceiling)}]}"#.utf8)
            )
            let windows = CommandCodeUsageService.windows(
                from: CommandCodeUsageService.Reading(
                    whoami: whoami, credits: nil, subscription: nil, summary: nil
                )
            )
            #expect(windows.isEmpty, "ceiling \(ceiling)")
        }
    }

    /// A pin is resolved by id, so an id that moves moves the pin with it.
    @Test("An org limit keeps its id when the array comes back in another order")
    func orgIdsSurviveAReorder() throws {
        let forwards = try Self.windows().filter { $0.id.hasPrefix("org.") }.map(\.id)

        let text = try String(decoding: Self.fixture("command-code-whoami"), as: UTF8.self)
        var json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        json["orgLimits"] = Array((json["orgLimits"] as! [Any]).reversed())
        let whoami = try JSONDecoder().decode(
            CommandCodeUsageService.Whoami.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )
        let backwards = CommandCodeUsageService.windows(
            from: CommandCodeUsageService.Reading(
                whoami: whoami, credits: nil, subscription: nil, summary: nil
            )
        ).filter { $0.id.hasPrefix("org.") }.map(\.id)

        #expect(Set(forwards) == Set(backwards))
        #expect(forwards.count == 3)
    }

    // MARK: - Plan, balance and stamps

    @Test("The plan id is tidied rather than mapped through a table")
    func planNamesArePassedThroughTidied() {
        #expect(CommandCodeUsageService.planName("individual-pro") == "Individual Pro")
        #expect(CommandCodeUsageService.planName("individual_go") == "Individual Go")
        #expect(CommandCodeUsageService.planName("teams-pro") == "Teams Pro")
        // A tier this build has never heard of still reads as something.
        #expect(CommandCodeUsageService.planName("individual-supernova") == "Individual Supernova")
        #expect(CommandCodeUsageService.planName("") == nil)
        #expect(CommandCodeUsageService.planName(nil) == nil)
    }

    @Test("The balance is the three pots added up, in the dollars the service prices in")
    func balanceAddsEveryPot() throws {
        let credits = try Self.decode(
            CommandCodeUsageService.CreditsReply.self, "command-code-credits"
        )
        // 12.5 + 4 + 0.5.
        #expect(CommandCodeUsageService.balance(credits)?.contains("17") == true)
        #expect(CommandCodeUsageService.balance(nil) == nil)
    }

    @Test("A period boundary is read whether it is a date string or an epoch number")
    func stampsInBothForms() throws {
        let iso = try JSONDecoder().decode(
            CommandCodeUsageService.Stamp.self, from: Data(#""2026-10-01T00:00:00Z""#.utf8)
        )
        #expect(iso.date == Date(timeIntervalSince1970: 1_790_812_800))
        // Handed back to the service exactly as it arrived.
        #expect(iso.query == "2026-10-01T00:00:00Z")

        let milliseconds = try JSONDecoder().decode(
            CommandCodeUsageService.Stamp.self, from: Data("1790812800000".utf8)
        )
        #expect(milliseconds.date == Date(timeIntervalSince1970: 1_790_812_800))
        #expect(milliseconds.query == "1790812800000")

        let seconds = try JSONDecoder().decode(
            CommandCodeUsageService.Stamp.self, from: Data("1790812800".utf8)
        )
        #expect(seconds.date == Date(timeIntervalSince1970: 1_790_812_800))
    }
}
