import Foundation
import Testing
@testable import Pulse

/// OpenCode's console: the request log that becomes the Go card's history,
/// and the plan's limits read with the same session. Built from replies in
/// the console's shape with every identifying field made up or left out.
struct OpenCodeConsoleTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func item(
        _ id: String, hoursAgo: Double, product: String = "go", model: String = "deepseek-flash",
        input: Int? = 100, output: Int? = 20, cacheRead: Int? = 900, cacheWrite: Int? = 0, cost: Double? = 0.002
    ) -> OpenCodeConsole.Item {
        OpenCodeConsole.Item(
            id: id, startedAt: now.addingTimeInterval(-hoursAgo * 3600).timeIntervalSince1970 * 1000,
            product: product, model: model, inputTokens: input, outputTokens: output,
            cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite, cost: cost
        )
    }

    // MARK: The session

    @Test func onlyTheSignInCookiesAreKept() {
        let header = "__stripe_mid=x; __Host-console_session=st_1; oc_locale=zh; auth=Fe26.2**abc; __stripe_sid=y"
        #expect(OpenCodeConsole.keep(header) == "__Host-console_session=st_1; auth=Fe26.2**abc")
        // No console session: nothing worth keeping.
        #expect(OpenCodeConsole.keep("auth=Fe26.2**abc; oc_locale=zh") == nil)
        #expect(OpenCodeConsole.keep("__Host-console_session=") == nil)
    }

    // MARK: The log

    @Test func aPageDecodesWithoutTheFieldsPulseDoesNotHold() throws {
        let json = #"""
        {"items":[{"id":"r1","workspaceID":"wrk_X","startedAt":1790850000000,"outcome":"succeeded","product":"go",
          "model":"deepseek-flash","country":"US","city":"Somewhere","serviceAPIKeyID":"key_X",
          "requestHeaders":{"user-agent":"x"},"inputTokens":7305,"outputTokens":420,"reasoningTokens":19,
          "cacheReadTokens":2688,"cacheWriteTokens":0,"cost":0.00135581},
          {"id":"r2","startedAt":1790849000000,"outcome":"failed","product":"go","model":"gpt-6-luna",
          "statusCode":403,"inputTokens":null,"outputTokens":null,"cost":null}],
         "nextCursor":"{\"v\":2,\"after\":{\"id\":\"r2\"}}","until":1790853898774,"retentionDays":30}
        """#
        let page = try JSONDecoder().decode(OpenCodeConsole.Page.self, from: Data(json.utf8))
        #expect(page.items.map(\.id) == ["r1", "r2"])
        #expect(page.items[0].tally == TokenTally(input: 7305, cacheWrite: 0, cacheRead: 2688, output: 420))
        #expect(page.items[1].tally.total == 0)
        #expect(page.nextCursor?.isEmpty == false)
    }

    @Test func theGoPlansRequestsBecomeAMonthPricedAsCharged() throws {
        let ledger = OpenCodeConsole.ledger(from: [
            item("a", hoursAgo: 1, cost: 0.002),
            item("b", hoursAgo: 2, cost: 0.003),
            // A failed request spends nothing and prices nothing.
            item("c", hoursAgo: 3, input: nil, output: nil, cacheRead: nil, cacheWrite: nil, cost: nil),
            // Another product on the workspace is not the Go plan's.
            item("d", hoursAgo: 1, product: "zen", cost: 5),
            item("e", hoursAgo: 49, model: "glm-5", cost: 0.01),
            // Older than the console keeps, and older than the month.
            item("f", hoursAgo: 24 * 40, cost: 1),
        ], now: now, calendar: calendar)

        #expect(ledger.origin == .providerLogs)
        #expect(ledger.days.count == 32)
        #expect(calendar.isDate(try #require(ledger.days.last).date, inSameDayAs: now))
        // The fixture's own day, not the clock's: `today` asks the real one.
        let today = try #require(ledger.days.last)
        #expect(today.tokens == 2 * 1020)
        #expect(abs(today.cost - 0.005) < 1e-9)
        #expect(abs(ledger.total(overLast: 31, now: now).cost - 0.015) < 1e-9)
        #expect(ledger.topModel(overLast: 31)?.name == "deepseek-flash")
        // Every token sorted into its kind: the hit rate can be stated.
        #expect(abs(try #require(ledger.cacheHitRate(overLast: 31, now: now)) - 0.9) < 1e-9)
        // Quarter-hours for the value estimate, with the money in them.
        #expect(abs(ledger.spend(since: now.addingTimeInterval(-90 * 60)).cost - 0.002) < 1e-9)
    }

    // MARK: Paging

    private func page(_ ids: [String], next: String?) -> OpenCodeConsole.PageResult {
        .page(OpenCodeConsole.Page(items: ids.map { item($0, hoursAgo: 1) }, nextCursor: next))
    }

    @Test func pagesAreFollowedToTheServersEnd() async {
        let walk = await OpenCodeConsole.collect(retryDelay: .zero) { cursor in
            switch cursor {
            case nil: page(["1", "2"], next: "c1")
            case "c1": page(["3"], next: "c2")
            default: page([], next: nil)
            }
        }
        #expect(walk.items.map(\.id) == ["1", "2", "3"])
        #expect(walk.complete)
    }

    /// A page the console held past the timeout is asked for again, and the
    /// walk is still whole when it then arrives.
    @Test func aPageThatFailsOnceIsAskedAgain() async {
        let attempts = Counter()
        let walk = await OpenCodeConsole.collect(retryDelay: .zero) { cursor in
            switch cursor {
            case nil: return page(["1"], next: "c1")
            default:
                return await attempts.next() == 1 ? .failed : page(["2"], next: nil)
            }
        }
        #expect(walk.items.map(\.id) == ["1", "2"])
        #expect(walk.complete)
    }

    private actor Counter {
        private var value = 0
        func next() -> Int { value += 1; return value }
    }

    @Test func aWalkThatStopsShortSaysSo() async {
        // The same cursor handed back: a loop, not a month.
        let looping = await OpenCodeConsole.collect(retryDelay: .zero) { _ in page(["1"], next: "same") }
        #expect(looping.items.count == 2)
        #expect(!looping.complete)

        // A page that fails after others arrived keeps what came.
        let broken = await OpenCodeConsole.collect(retryDelay: .zero) { cursor in
            cursor == nil ? page(["1"], next: "c1") : .failed
        }
        #expect(broken.items.map(\.id) == ["1"])
        #expect(!broken.complete)
        #expect(broken.outcome == nil)

        // Turned away on the first page: that is the answer.
        let signedOut = await OpenCodeConsole.collect(retryDelay: .zero) { _ in .signedOut }
        if case .signedOut = signedOut.outcome {} else { Issue.record("expected signedOut") }
    }

    // MARK: The limits

    @Test func theConsoleLimitsAreTheKeysThreeWindows() throws {
        let json = #"""
        {"subscriberUserId":"acc_X","product":"go","paymentMethodKind":"card",
         "access":{"startsAt":"2026-09-14T02:01:39.000Z","endsAt":"2026-10-14T02:01:39.000Z",
          "meters":{
           "fiveHour":{"startsAt":"2026-10-01T10:06:17.039Z","resetsAt":"2026-10-01T15:06:17.039Z","limitMicroCents":"1200000000","usedMicroCents":"641286"},
           "week":{"startsAt":"2026-09-28T00:00:00.000Z","resetsAt":"2026-10-05T00:00:00.000Z","limitMicroCents":"3000000000","usedMicroCents":"3000000000"},
           "month":{"resetsAt":"2026-10-14T02:01:39.000Z","limitMicroCents":"6000000000","usedMicroCents":"1283388501"}}}}
        """#
        let status = try JSONDecoder().decode(OpenCodeGoUsageService.ConsoleStatus.self, from: Data(json.utf8))
        let windows = OpenCodeGoUsageService.windows(from: status)

        // The ids the key route uses, so a pinned limit survives either route.
        #expect(windows.map(\.id) == ["rolling", "weekly", "monthly"])
        #expect(abs(windows[0].usedFraction - 641_286.0 / 1_200_000_000) < 1e-12)
        #expect(windows[0].windowSeconds == 5 * 3600)
        #expect(windows[0].reportsLength)
        #expect(!windows[0].isExhausted)
        // Used up to the limit: spent, on the console's own figures.
        #expect(windows[1].isExhausted)
        #expect(windows[1].usedFraction == 1)
        // The month starts with the billing period, which ends with it.
        #expect(windows[2].reportsLength)
        #expect(windows[2].windowSeconds == 30 * 86_400)
    }

    @Test func noPlanIsNoWindows() throws {
        let status = try JSONDecoder().decode(OpenCodeGoUsageService.ConsoleStatus.self, from: Data(#"{"product":null}"#.utf8))
        #expect(OpenCodeGoUsageService.windows(from: status).isEmpty)
    }

    // MARK: The workspace

    /// Every console route wants `x-org-id`; the list it is chosen from.
    @Test func theWorkspaceListDecodes() throws {
        let list = try JSONDecoder().decode([OpenCodeConsole.Workspace].self,
                                            from: Data(#"[{"id":"wrk_A","name":"Mine"},{"id":"wrk_B","name":null}]"#.utf8))
        #expect(list.map(\.id) == ["wrk_A", "wrk_B"])
        #expect(list[0].name == "Mine")
        #expect(list[1].name == nil)
    }
}
