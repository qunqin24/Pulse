import Foundation
import Testing
@testable import Pulse

/// Qoder's credits are read from its account page's own request, with the
/// browser session that page uses. The fixtures are sanitized from the shapes
/// other monitors of this route recorded — camelCase today, snake_case in an
/// earlier build — not from a capture made here.
@Suite("Qoder")
struct QoderParsingTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    private static let resetDate = Date(timeIntervalSince1970: 1_725_148_800)
    /// A day before the fixtures' reset, so their date is still ahead.
    private static let before = resetDate.addingTimeInterval(-86_400)

    // MARK: - The credential

    /// Qoder's session cookie has no published name, so the filter drops what
    /// third-party analytics set and keeps the rest of what the host set.
    @Test("Analytics cookies are dropped, the host's own are kept")
    func normalizeDropsAnalytics() throws {
        let kept = try QoderCookie.normalize(
            "_ga=GA1.1.9; _gcl_au=1.1; qoder_session=abc; Hm_lvt_x=1; cna=dev1; locale=zh"
        )
        #expect(kept == "qoder_session=abc; cna=dev1; locale=zh")
    }

    @Test("A pasted header is taken as pasted")
    func normalizeAcceptsAPastedHeader() throws {
        #expect(try QoderCookie.normalize("Cookie: sid=abc; lang=en") == "sid=abc; lang=en")
    }

    /// A value carrying a newline would end the header and start whatever came
    /// after it as a fresh one.
    @Test("A control character is refused, not forwarded")
    func normalizeRefusesControlCharacters() {
        #expect(throws: QoderError.invalidCookie) {
            try QoderCookie.normalize("sid=abc\r\nX-Injected: 1")
        }
    }

    @Test("Nothing but analytics is no session")
    func normalizeNeedsSomethingOfTheHost() {
        #expect(throws: QoderError.invalidCookie) { try QoderCookie.normalize("_ga=1; _gid=2") }
        #expect(throws: QoderError.missingCookie) { try QoderCookie.normalize("Cookie: ") }
    }

    /// The browser hands back a host-only and a domain row for one name; the
    /// first wins rather than the whole session being thrown away.
    @Test("A repeated name keeps the first")
    func normalizeKeepsFirstOfRepeatedName() throws {
        #expect(try QoderCookie.normalize("sid=first; sid=second") == "sid=first")
    }

    // MARK: - The reply

    @Test("The account's credits, with Qoder's own reset")
    func parsesCamelCase() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits"))
        #expect(snapshot.personal == .init(used: 125, limit: 500, remaining: 375))
        #expect(snapshot.shared == nil)
        #expect(snapshot.resetsAt == Self.resetDate)

        let windows = QoderUsageService.windows(from: snapshot, at: Self.before)
        #expect(windows.count == 1)
        #expect(windows[0].kind == .credits)
        #expect(windows[0].usedFraction == 0.25)
        #expect(windows[0].resetsAt == Self.resetDate)
        #expect(!windows[0].reportsLength)
        #expect(!windows[0].isExhausted)
    }

    /// The earlier build's field names, and a reset stated in milliseconds.
    /// `total_quota` already includes the plan and the packs, so those two are
    /// not added on top.
    @Test("The snake_case reply reads the same")
    func parsesSnakeCase() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-snake"))
        #expect(snapshot.personal == .init(used: 125, limit: 500, remaining: 375))
        #expect(snapshot.resetsAt == Self.resetDate)
    }

    /// A spent personal allowance beside a team pool with room in it. Summed,
    /// they read as 68% — "plenty left" about the pool that is actually
    /// stopping the reader. Two rings, and the personal one says spent.
    @Test("A team pool is a second ring, never a sum")
    func teamPoolIsItsOwnRing() throws {
        let windows = QoderUsageService.windows(from: try QoderClient.parse(Self.fixture("qoder-credits-team")), at: Self.before)
        #expect(windows.map(\.kind) == [.credits, .sharedCredits])
        #expect(windows[0].usedFraction == 1)
        #expect(windows[0].isExhausted)
        #expect(windows[1].usedFraction == 0.2)
        #expect(!windows[1].isExhausted)
        // Qoder states the account's reset, not the team's.
        #expect(windows[1].resetsAt == nil)
    }

    /// The mainland trial reply from issue #59: 586 of 600 credits left and a
    /// `nextResetAt` a month in the past. The credits are drawn; the stale
    /// date is not, or the cache would drop the ring as already reset and say
    /// no limits were reported.
    @Test("A reset date already past is dropped, not the credits")
    func staleResetIsDropped() async throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-trial-stale-reset"))
        #expect(snapshot.personal == .init(used: 14, limit: 600, remaining: 586))
        #expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_787_304_668.180))

        let read = Date(timeIntervalSince1970: 1_790_179_680) // 2026-09-23T16:08Z
        let windows = QoderUsageService.windows(from: snapshot, at: read)
        #expect(windows.count == 1)
        #expect(windows[0].resetsAt == nil)
        #expect(!windows[0].isExhausted)
        // What the card says instead: the pack with 86 left, lapsing first.
        #expect(windows[0].nextExpiry == .init(amount: 86, at: Date(timeIntervalSince1970: 1_792_313_971.562)))

        let usage = ProviderUsage(account: AccountKey(.qoder), windows: windows, observedAt: Date(),
                                  state: .live, plan: nil, creditBalance: nil)
        let shown = await UsageCache(file: FileManager.default.temporaryDirectory
            .appending(path: "pulse-qoder-test-\(UUID().uuidString).json")).reconciled(usage)
        #expect(shown.state == .live)
        #expect(shown.windows.count == 1)
    }

    /// Six bonus packs, each ending on its own day. The plan's entry has no
    /// date and is not one of them; the one with credits left that ends first
    /// is what the card names.
    @Test("The packs' end dates are read, soonest first")
    func packsAreRead() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-trial-stale-reset"))
        #expect(snapshot.packs.count == 6)
        #expect(snapshot.packs.map(\.remaining).reduce(0, +) == 586)
    }

    /// Packs ending the same day are one line on the card, added up; a pack
    /// already gone or already spent is none.
    @Test("Packs lapsing the same day are added up")
    func sameDayPacksAddUp() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let morning = now.addingTimeInterval(3 * 86_400)
        let packs: [QoderSnapshot.Pack] = [
            .init(remaining: 40, expiresAt: now.addingTimeInterval(-60)),
            .init(remaining: 100, expiresAt: morning.addingTimeInterval(3_600)),
            .init(remaining: 86, expiresAt: morning),
            .init(remaining: 100, expiresAt: morning.addingTimeInterval(2 * 86_400)),
        ]
        let expiry = QoderUsageService.nextExpiry(of: packs, at: now, calendar: utc)
        #expect(expiry == .init(amount: 186, at: morning))
        #expect(QoderUsageService.nextExpiry(of: [], at: now) == nil)
    }

    /// Older fixtures carry no detail at all, and a detail list this cannot
    /// read must not cost the summary beside it.
    @Test("No detail, or an unreadable one, is no expiry")
    func unreadableDetailIsNoExpiry() throws {
        #expect(try QoderClient.parse(Self.fixture("qoder-credits")).packs.isEmpty)
        let odd = try QoderClient.parse(Data(#"""
            {"total_quota":{"quota_summary":{"used_value":1,"limit_value":10},"quota_detail":"soon"}}
            """#.utf8))
        #expect(odd.personal.limit == 10)
        #expect(odd.packs.isEmpty)
    }

    /// Banked with the reading, so a restart does not lose the line; a cache
    /// written before it existed reads as no expiry.
    @Test("The expiry survives the cache, and its absence reads as none")
    func expiryIsBanked() throws {
        let expiry = UsageWindow.Expiry(amount: 86, at: Date(timeIntervalSince1970: 1_792_313_971))
        let window = UsageWindow(id: "qoder.credits", kind: .credits, scope: nil, usedFraction: 0.02,
                                 windowSeconds: 30 * 86_400, resetsAt: nil, reportsLength: false,
                                 nextExpiry: expiry)
        let data = try JSONEncoder().encode(window)
        #expect(try JSONDecoder().decode(UsageWindow.self, from: data).nextExpiry == expiry)

        let old = UsageWindow(id: "qoder.credits", kind: .credits, scope: nil, usedFraction: 0.02,
                              windowSeconds: 30 * 86_400, resetsAt: nil)
        #expect(try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(old)).nextExpiry == nil)
    }

    /// A limit of zero is an account with nothing granted. Not a ring at 100%,
    /// which would say something was spent.
    @Test("No credits at all draws nothing")
    func zeroLimitDrawsNothing() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-none"))
        #expect(snapshot.shared == nil)
        #expect(QoderUsageService.windows(from: snapshot, at: Self.before).isEmpty)
    }

    @Test("A reply without the account's summary is unreadable, not empty")
    func missingSummaryIsUnreadable() {
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data(#"{"quotaKey":"big_model_credits"}"#.utf8))
        }
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data("<html>sign in</html>".utf8))
        }
        #expect(throws: QoderError.unreadableReply) {
            try QoderClient.parse(Data(#"{"totalQuota":{"quotaSummary":{"usedValue":-1,"limitValue":5}}}"#.utf8))
        }
    }

    /// Without a remainder the arithmetic decides; with one, Qoder's word does.
    @Test("Spent follows Qoder's remainder when it gives one")
    func exhaustionFollowsTheRemainder() {
        let stated = QoderSnapshot(personal: .init(used: 10, limit: 10, remaining: 3), shared: nil, resetsAt: nil)
        #expect(QoderUsageService.windows(from: stated, at: Self.before).first?.isExhausted == false)
        let silent = QoderSnapshot(personal: .init(used: 10, limit: 10, remaining: nil), shared: nil, resetsAt: nil)
        #expect(QoderUsageService.windows(from: silent, at: Self.before).first?.isExhausted == true)
    }

    /// A pack bought on top raises the limit, and the fraction falls with
    /// nothing reset. Only Qoder's reset date moving forward says it turned
    /// over — otherwise a purchase would be announced as a reset.
    @Test("A pack bought on top is not a reset")
    func purchaseIsNotAReset() throws {
        let before = Date(timeIntervalSince1970: 1_725_148_800)
        let bought = QoderSnapshot(personal: .init(used: 450, limit: 2_500, remaining: 2_050),
                                   shared: nil, resetsAt: before)
        let window = try #require(QoderUsageService.windows(from: bought, at: Self.before).first)
        #expect(!window.hasTurnedOver(since: 0.9, resetsAt: before))

        let team = QoderSnapshot(personal: .init(used: 0, limit: 10, remaining: 10),
                                 shared: .init(used: 10, limit: 5_000, remaining: 4_990), resetsAt: nil)
        let shared = try #require(QoderUsageService.windows(from: team, at: Self.before).last)
        #expect(!shared.hasTurnedOver(since: 0.9, resetsAt: nil))

        let renewed = QoderSnapshot(personal: .init(used: 5, limit: 500, remaining: 495),
                                    shared: nil, resetsAt: before.addingTimeInterval(30 * 86_400))
        let next = try #require(QoderUsageService.windows(from: renewed, at: Self.before).first)
        #expect(next.hasTurnedOver(since: 0.9, resetsAt: before))
    }

    // MARK: - The parts

    /// The figures from issue #76, which the fixture's shape follows: a total
    /// at 43% used holding a resource pack at 95%. The details' `source` names
    /// and the pack's undated entry are written to the trial reply's shape,
    /// not captured from this account.
    private static let partsRead = Date(timeIntervalSince1970: 1_791_590_400) // 2026-10-10T00:00Z

    @Test("The parts are read beside the total")
    func partsAreRead() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-parts"))
        #expect(snapshot.personal == .init(used: 6_068, limit: 14_000, remaining: 7_932))
        #expect(snapshot.plan?.pool == .init(used: 157, limit: 6_000, remaining: 5_843))
        #expect(snapshot.resourcePack?.pool == .init(used: 1_900, limit: 2_000, remaining: 100))
        #expect(snapshot.dedicated?.pool == .init(used: 4_011, limit: 6_000, remaining: 1_989))
    }

    /// Off, the card is what it always was. On, the parts follow the total,
    /// and the ring's automatic choice — the fullest — is the pack at 95%
    /// rather than the total at 43%.
    @Test("The parts are drawn only when asked, after the total")
    func partsFollowTheTotal() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-parts"))
        #expect(QoderUsageService.windows(from: snapshot, at: Self.partsRead).map(\.id) == ["qoder.credits"])

        let windows = QoderUsageService.windows(from: snapshot, at: Self.partsRead, showsParts: true)
        #expect(windows.map(\.id) == ["qoder.credits", "qoder.plan", "qoder.pack", "qoder.dedicated"])
        #expect(windows.map(\.kind) == [.credits, .planCredits, .topUp, .dedicatedCredits])
        #expect(windows[2].usedFraction == 0.95)

        let usage = ProviderUsage(account: AccountKey(.qoder), windows: windows, observedAt: Self.partsRead,
                                  state: .live, plan: nil, creditBalance: nil)
        #expect(usage.headlineWindow()?.id == "qoder.pack")
    }

    /// Only the plan refreshes; the packs lapse. Each part's expiry is its
    /// own, so the 1,989 lapsing on 7 November sits on the dedicated row.
    @Test("Only the plan has a reset, and each part its own expiry")
    func partsKeepTheirOwnDates() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-parts"))
        let windows = QoderUsageService.windows(from: snapshot, at: Self.partsRead, showsParts: true)
        let reset = Date(timeIntervalSince1970: 1_794_186_000)
        let lapse = Date(timeIntervalSince1970: 1_794_063_600)
        #expect(windows.map(\.resetsAt) == [reset, reset, nil, nil])
        #expect(windows[0].nextExpiry == .init(amount: 1_989, at: lapse))
        #expect(windows[1].nextExpiry == nil)
        #expect(windows[2].nextExpiry == nil)
        #expect(windows[3].nextExpiry == .init(amount: 1_989, at: lapse))
        // A pack bought on top of a part is not a reset either.
        #expect(!windows[1].hasTurnedOver(since: 0.9, resetsAt: reset))
        #expect(!windows[3].hasTurnedOver(since: 0.9, resetsAt: nil))
    }

    /// The trial reply has one part with an allowance; drawn, it would be the
    /// total again under another name.
    @Test("One part alone is not drawn twice")
    func onePartIsTheTotal() throws {
        let snapshot = try QoderClient.parse(Self.fixture("qoder-credits-trial-stale-reset"))
        let read = Date(timeIntervalSince1970: 1_790_179_680)
        #expect(QoderUsageService.windows(from: snapshot, at: read, showsParts: true).map(\.id) == ["qoder.credits"])
    }

    /// A part this cannot read is left out; the total it belongs to is not.
    @Test("An unreadable part never costs the total")
    func unreadablePartIsDropped() throws {
        let reply = Data("""
        { "total_quota": { "quota_summary": { "used_value": 10, "limit_value": 100, "remaining_value": 90 } },
          "plan_quota": { "quota_summary": { "used_value": "many", "limit_value": 50 } },
          "resource_package_quota": "nonsense" }
        """.utf8)
        let snapshot = try QoderClient.parse(reply)
        #expect(snapshot.personal == .init(used: 10, limit: 100, remaining: 90))
        #expect(snapshot.plan == nil)
        #expect(snapshot.resourcePack == nil)
    }

    // MARK: - Sites

    @Test("Each site asks its own host, and only its own")
    func sitesStayApart() {
        #expect(QoderSite.international.usageURL.absoluteString == "https://qoder.com/api/v2/me/usages/big_model_credits")
        #expect(QoderSite.china.usageURL.absoluteString == "https://qoder.com.cn/api/v2/me/usages/big_model_credits")
        #expect(QoderSite.china.accountPage.absoluteString == "https://qoder.com.cn/account/usage")
    }

    @Test("A missing session is said, not fetched")
    func missingSessionIsReported() async {
        let usage = await QoderUsageService(cookie: nil, site: .international).fetch()
        #expect(usage.state == .unavailable(.qoderSessionMissing))
        #expect(usage.sourceScope == nil)
    }
}
