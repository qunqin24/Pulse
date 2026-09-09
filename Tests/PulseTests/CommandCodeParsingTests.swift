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

    // MARK: - Order and identity

    @Test("Every reported limit becomes a window, shortest first")
    func windowsAreOrderedShortestFirst() throws {
        let windows = try Self.windows()

        #expect(windows.map(\.id) == [
            "five-hour",      // 5 hours
            "org.1.model",    // daily
            "weekly",         // 7 days
            "org.2.model",    // 7 days
            "org.0.org",      // ~monthly
            "credits",        // the billing period, also 30 days
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

    @Test("The pool is spent plus remaining, never a table in the client")
    func creditPoolIsTheAccountsOwnArithmetic() throws {
        let credits = try #require(try Self.windows().first { $0.id == "credits" })

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
        let stated = try #require(try Self.windows().first { $0.id == "credits" })
        #expect(stated.reportsLength)
        #expect(stated.windowSeconds == 30 * 86_400)

        // No subscription at all — a pay-as-you-go balance — leaves the month
        // as a sort key that nothing may divide by.
        let loose = CommandCodeUsageService.windows(
            from: try Self.reading(subscription: nil)
        )
        let pool = try #require(loose.first { $0.id == "credits" })
        #expect(pool.reportsLength == false)
        #expect(pool.elapsedFraction(at: Date()) == nil)
    }

    @Test("A summary that never arrived shows nothing spent, not an estimate of it")
    func withoutASummaryNothingIsInvented() throws {
        let windows = CommandCodeUsageService.windows(from: try Self.reading(summary: nil))
        let pool = try #require(windows.first { $0.id == "credits" })

        // What is left is still reported, so the pool is what is left and
        // nothing reads as gone — rather than a percentage built from one real
        // number and a guess at the other.
        #expect(pool.usedFraction == 0)
        #expect(pool.isExhausted == false)
    }

    @Test("An account with nothing left and nothing spent reports no pool")
    func anEmptyAccountIsNotAFullOne() throws {
        let reading = CommandCodeUsageService.Reading(
            whoami: nil,
            credits: try Self.decode(CommandCodeUsageService.CreditsReply.self, "command-code-credits"),
            subscription: nil,
            summary: nil
        )
        #expect(CommandCodeUsageService.windows(from: reading).contains { $0.id == "credits" })

        let silent = CommandCodeUsageService.Reading(
            whoami: nil, credits: nil, subscription: nil, summary: nil
        )
        #expect(CommandCodeUsageService.windows(from: silent).isEmpty)
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
        #expect(windows.map(\.id) == ["credits"])
    }

    // MARK: - Organisation spend limits

    @Test("Spend limits arrive already spent — no inversion")
    func orgLimitsAreNotInverted() throws {
        let daily = try #require(try Self.windows().first { $0.id == "org.1.model" })
        #expect(abs(daily.usedFraction - 0.9) < 0.000_001)
        #expect(daily.percentText == "90%")
        #expect(daily.scope == "Claude Opus 5")
    }

    @Test("`exceeded` is the account's verdict and outranks the arithmetic")
    func exceededOutranksThePercentage() throws {
        let weekly = try #require(try Self.windows().first { $0.id == "org.2.model" })
        // Two dollars of four is half the limit, and the account still says it
        // is done. Erring towards "you are blocked" is the safer mistake.
        #expect(abs(weekly.usedFraction - 0.5) < 0.000_001)
        #expect(weekly.isExhausted)
    }

    @Test("An org-wide limit is left unscoped")
    func orgWideLimitsCarryNoModelName() throws {
        let monthly = try #require(try Self.windows().first { $0.id == "org.0.org" })
        #expect(monthly.scope == nil)
        #expect(monthly.resetsAt != nil)
    }

    @Test("A day and a week are lengths; a month is only a sort key")
    func onlyExactIntervalsClaimALength() throws {
        let windows = try Self.windows()
        #expect(try #require(windows.first { $0.id == "org.1.model" }).reportsLength)
        #expect(try #require(windows.first { $0.id == "org.2.model" }).reportsLength)

        // 28 to 31 days stored as a flat 30, so nothing may divide by it.
        let monthly = try #require(windows.first { $0.id == "org.0.org" })
        #expect(monthly.reportsLength == false)
        #expect(monthly.elapsedFraction(at: Date()) == nil)
    }

    @Test("A limit missing its ceiling is dropped rather than guessed at")
    func limitsWithoutACeilingAreDropped() throws {
        // The fourth fixture row states `spent: 3` and no `limit` at all.
        // There is no denominator to build a fraction from, and a spend limit
        // shown at an invented ceiling is worse than one not shown.
        #expect(!(try Self.windows().contains { $0.id == "org.3.org" }))
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
