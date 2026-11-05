import Foundation
import Testing
@testable import Pulse

/// Xiaomi's console is read with a browser session, and answers a refused one
/// with **HTTP 200** and a code in the body. Both halves of that are where this
/// provider can go quietly wrong: a credential assembled from whatever a
/// browser happened to store, and a failure that looks like a success to
/// anything reading the status line.
@Suite("Xiaomi Coding Plan")
struct XiaomiMiMoTests {
    private static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    // MARK: - The credential

    /// The session is built from a browser store that also holds analytics,
    /// preferences and whatever the site adds next. Only the named cookies may
    /// leave the process.
    @Test("Only the console's own cookies are kept")
    func normalizeKeepsOnlyWhatIsNeeded() throws {
        let header = """
        _ga=GA1.1.99; api-platform_serviceToken=abc123; \
        userId=42; sensorsdata=xyz; api-platform_ph=ph1
        """
        let kept = try XiaomiMiMoCookie.normalize(header)
        #expect(kept.contains("api-platform_serviceToken=abc123"))
        #expect(kept.contains("userId=42"))
        #expect(kept.contains("api-platform_ph=ph1"))
        #expect(!kept.contains("_ga"))
        #expect(!kept.contains("sensorsdata"))
    }

    /// Either of the two required names missing is a session that cannot be
    /// used, and saying so beats sending a request that comes back as a
    /// mysterious refusal.
    @Test("Both required cookies or nothing")
    func normalizeNeedsBothRequiredNames() {
        #expect(throws: XiaomiMiMoError.invalidCookie) {
            try XiaomiMiMoCookie.normalize("api-platform_serviceToken=abc123; _ga=1")
        }
        #expect(throws: XiaomiMiMoError.invalidCookie) {
            try XiaomiMiMoCookie.normalize("userId=42; _ga=1")
        }
    }

    /// A header pasted out of a network tab, `Cookie:` prefix and all.
    @Test("A pasted header is taken as pasted")
    func normalizeAcceptsAPastedHeader() throws {
        let kept = try XiaomiMiMoCookie.normalize("Cookie: api-platform_serviceToken=t; userId=1")
        #expect(kept == "api-platform_serviceToken=t; userId=1")
    }

    /// A value carrying a newline would end the header and start whatever came
    /// after it as a fresh one.
    @Test("A control character is refused, not forwarded")
    func normalizeRefusesInjection() {
        #expect(throws: XiaomiMiMoError.invalidCookie) {
            try XiaomiMiMoCookie.normalize("api-platform_serviceToken=a\r\nX-Evil: 1; userId=1")
        }
    }

    /// Every browser store routinely holds a host-only row and a domain row
    /// for one name. Throwing on the second discarded the whole browser — the
    /// mistake Ollama's normalizer already had to learn.
    @Test("A repeated cookie is not a broken one")
    func normalizeTakesTheFirstOfADuplicate() throws {
        let kept = try XiaomiMiMoCookie.normalize(
            "api-platform_serviceToken=first; userId=1; api-platform_serviceToken=second")
        #expect(kept.contains("api-platform_serviceToken=first"))
        #expect(!kept.contains("second"))
    }

    // MARK: - The reply

    @Test("A plan reports what is used out of what was bought")
    func planIsReadFromBothRoutes() throws {
        let plan = try #require(XiaomiMiMoClient.parsePlan(
            detail: try Self.fixture("xiaomi-plan-detail"),
            usage: try Self.fixture("xiaomi-plan-usage")))
        #expect(plan.used == 3_750_000)
        #expect(plan.limit == 10_000_000)
        #expect(plan.code == "coding-pro")
        // The console's own format, which is not ISO-8601 — parsed with a
        // formatter that knows that, or the card silently loses its reset.
        #expect(plan.periodEnd == XiaomiMiMoClient.date(from: "2026-10-01 00:00:00"))
        #expect(plan.periodEnd != nil)
    }

    /// An account with no plan buys tokens by the yuan. Nil rather than a
    /// zero: a ring at 0% would read as a full month nobody has.
    @Test("No plan is nothing to draw, not an empty plan")
    func noPlanIsNil() throws {
        #expect(XiaomiMiMoClient.parsePlan(
            detail: try Self.fixture("xiaomi-plan-detail"),
            usage: try Self.fixture("xiaomi-no-plan")) == nil)
    }

    /// A lapsed plan keeps reporting last month's figures until it renews.
    @Test("An expired plan is not a current allowance")
    func expiredPlanIsNotDrawn() throws {
        let detail = Data("""
        {"code":0,"data":{"planCode":"coding-pro","currentPeriodEnd":"2026-08-01 00:00:00","expired":true}}
        """.utf8)
        #expect(XiaomiMiMoClient.parsePlan(
            detail: detail, usage: try Self.fixture("xiaomi-plan-usage")) == nil)
    }

    /// The usage route alone is enough for a ring. The detail route only adds
    /// the reset and the plan's name, so losing it costs those and not the row.
    @Test("The plan survives losing the detail route")
    func planWorksWithoutDetail() throws {
        let plan = try #require(XiaomiMiMoClient.parsePlan(
            detail: nil, usage: try Self.fixture("xiaomi-plan-usage")))
        #expect(plan.used == 3_750_000)
        #expect(plan.periodEnd == nil)
        #expect(plan.code == nil)
    }

    @Test("The balance is read with its currency")
    func balanceIsReadWithItsCurrency() throws {
        let money = try #require(try XiaomiMiMoClient.parseBalance(try Self.fixture("xiaomi-balance")))
        #expect(money.amount == 42.75)
        #expect(money.currency == "CNY")
    }

    /// The platform puts a refused session inside an ordinary HTTP 200. Read
    /// as a success it would come out as "no plan on this account", which
    /// sends somebody to look at their subscription instead of at their login.
    @Test("A refusal inside a 200 is not read as an answer")
    func signedOutEnvelopeIsNotAPlan() throws {
        let data = try Self.fixture("xiaomi-signed-out")
        #expect(XiaomiMiMoClient.parsePlan(detail: data, usage: data) == nil)
        #expect(try XiaomiMiMoClient.parseBalance(data) == nil)
    }

    /// The envelope is read before the payload, on every route.
    ///
    /// A non-zero `code` over an HTTP 200 is a failure wearing a success's
    /// clothes. Read without checking it, a `code` 500 came out as "no Coding
    /// Plan on this account" — a fault reported as a subscription, which
    /// `UsageAlerts` then classes as an answer and uses to clear an outage.
    @Test("A non-zero code is not a plan, whatever the payload says")
    func nonZeroCodeIsNotAPlan() throws {
        let broken = Data("""
        {"code":500,"message":"internal error","data":{"monthUsage":{"percent":0,
        "items":[{"name":"Coding Plan","used":1,"limit":100,"percent":1}]}}}
        """.utf8)
        #expect(XiaomiMiMoClient.parsePlan(detail: nil, usage: broken) == nil,
                "a 500 envelope was read as an allowance")
    }

    /// The detail route's envelope too: a bad one must not contribute a reset
    /// or a plan name to a row built from the usage route.
    @Test("A non-zero detail code contributes nothing")
    func nonZeroDetailCodeIsIgnored() throws {
        let broken = Data("""
        {"code":401,"data":{"planCode":"leaked","currentPeriodEnd":"2026-10-01 00:00:00","expired":false}}
        """.utf8)
        let plan = try #require(XiaomiMiMoClient.parsePlan(
            detail: broken, usage: try Self.fixture("xiaomi-plan-usage")))
        #expect(plan.code == nil)
        #expect(plan.periodEnd == nil)
    }

    // MARK: - What the rail is told

    /// The period's end is reported and its length never is. A length is
    /// carried only so the row sorts, and drawing the window-clock arc from it
    /// would be inventing a figure the provider did not state.
    @Test("The month's length is a sort key, not a reported length")
    func monthlyWindowDoesNotClaimALength() throws {
        let plan = try #require(XiaomiMiMoClient.parsePlan(
            detail: try Self.fixture("xiaomi-plan-detail"),
            usage: try Self.fixture("xiaomi-plan-usage")))
        let window = UsageWindow(
            id: "xiaomi.plan", kind: .monthly, scope: nil,
            usedFraction: Double(plan.used) / Double(plan.limit),
            windowSeconds: 30 * 86_400, resetsAt: plan.periodEnd,
            reportsLength: false, isExhausted: false)
        #expect(!window.reportsLength)
        #expect(window.elapsedFraction() == nil)
    }

    /// A session that was never set up and one that went stale are different
    /// sentences, and the difference is what the reader has to do next.
    @Test("A missing session and an expired one are told apart")
    func noSessionIsNotAnExpiredOne() async {
        let usage = await XiaomiMiMoUsageService(cookie: nil).fetch()
        #expect(usage.state == .unavailable(.xiaomiSessionMissing))
    }

    /// The provider answers the questions the rest of the app asks of every
    /// case. Missing one is a silent fall-through into somebody else's branch.
    @Test("The provider is wired up as a session-based one")
    func providerAnswersTheSharedQuestions() {
        let provider = Provider.xiaomiMiMo
        #expect(provider.displayName == "Xiaomi Coding Plan")
        #expect(provider.usesSessionCookie)
        #expect(provider.readsBrowserStorage)
        #expect(provider.keepsOwnCredential)
        #expect(!provider.keepsLocalTranscripts)
        #expect(!provider.hasSourceChoice)
        #expect(provider.soleRoute == nil)
        // No allowance to compare a balance against, so no "warn below" line
        // is offered for something Pulse cannot say is running out.
        #expect(!provider.reportsSpendableBalance)
        // Nothing to detect on disk: the session lives in a browser, and a
        // browser is not evidence of an account.
        #expect(!Provider.installedOnThisMac().contains(.xiaomiMiMo))
    }

    /// An icon that is not in the bundle draws nothing, and a ring with no
    /// mark is indistinguishable from one that failed to load. Asked through
    /// the app's own loader, because `Bundle.module` inside a test is the
    /// *test* bundle and would answer nil for every mark there is.
    @Test("The mark loads")
    @MainActor
    func iconResourceLoads() {
        #expect(LobeIconStore.image(named: Provider.xiaomiMiMo.iconResource) != nil,
                "\(Provider.xiaomiMiMo.iconResource).svg does not load")
    }

    // MARK: - A pay-as-you-go account (#82)

    @Test("No plan with a balance is a live balance reading, not 'no plan'")
    func noPlanBalanceIsAReading() {
        let reading = XiaomiMiMoUsageService.reading(
            from: XiaomiMiMoSnapshot(plan: nil, balance: 52.3, currency: "CNY"))
        #expect(reading.state == .live)
        #expect(reading.windows.isEmpty)
        #expect(reading.creditRemaining == .init(amount: 52.3, currency: "CNY"))
        #expect(reading.creditBalance != nil)
    }

    @Test("No plan and no balance still says there is no plan")
    func noPlanNoBalance() {
        let reading = XiaomiMiMoUsageService.reading(from: XiaomiMiMoSnapshot(plan: nil, balance: nil, currency: nil))
        #expect(reading.state == .unavailable(.xiaomiNoCodingPlan))
    }

    @Test("Beside a plan the balance stays a line on the card, not a balance reading")
    func planKeepsBalanceAsALine() {
        let plan = XiaomiMiMoSnapshot.Plan(used: 1, limit: 10, periodEnd: nil, code: "coding-pro")
        let reading = XiaomiMiMoUsageService.reading(from: XiaomiMiMoSnapshot(plan: plan, balance: 52.3, currency: "CNY"))
        #expect(reading.windows.count == 1)
        #expect(reading.creditRemaining == nil)
        #expect(reading.creditBalance != nil)
    }

    /// Only a stated "no plan" may become a balance reading: a usage route that
    /// failed must not turn a subscriber into a pay-as-you-go account.
    @Test("Only a usage reply that says so means no plan")
    func onlyAStatedNoPlan() throws {
        #expect(XiaomiMiMoClient.saysNoPlan(detail: nil, usage: try Self.fixture("xiaomi-no-plan")))
        #expect(!XiaomiMiMoClient.saysNoPlan(detail: nil, usage: nil))
        #expect(!XiaomiMiMoClient.saysNoPlan(detail: nil, usage: Data(#"{"code":500,"data":{"monthUsage":{"items":[]}}}"#.utf8)))
        #expect(!XiaomiMiMoClient.saysNoPlan(detail: nil, usage: Data("not json".utf8)))
        let expired = Data(#"{"code":0,"data":{"planCode":"coding-pro","currentPeriodEnd":"2026-08-01 00:00:00","expired":true}}"#.utf8)
        #expect(XiaomiMiMoClient.saysNoPlan(detail: expired, usage: try Self.fixture("xiaomi-plan-usage")))
    }
}
