import Foundation
import Testing
@testable import Pulse

/// The account's own usage statistics, which is the second way a history can
/// reach Pulse — the first being a scan of this Mac's transcripts.
///
/// The shape was captured from `open.bigmodel.cn` on 2026-09-07; the numbers
/// in the fixture are invented, because the live account had never been used
/// and every series was zero. What is measured is the **structure**: hourly
/// `x_time` labels, one aligned total series, and one series per model.
@Suite("Provider usage statistics")
struct ZaiHistoryTests {
    private static func payload() throws -> ZaiUsageService.Statistics.Payload {
        let url = try #require(
            Bundle.module.url(forResource: "glm-model-usage", withExtension: "json", subdirectory: "Fixtures")
        )
        let reply = try JSONDecoder().decode(
            ZaiUsageService.Statistics.self, from: try Data(contentsOf: url)
        )
        return try #require(reply.data)
    }

    private static func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    @Test("Hourly buckets are folded into days")
    func hoursBecomeDays() throws {
        let ledger = try #require(ZaiUsageService.ledger(from: try Self.payload()))

        // Five hourly buckets across three dates, and a chart of days.
        #expect(ledger.days.map(\.date) == ["2026-09-05", "2026-09-06", "2026-09-07"].map(Self.day))
        #expect(ledger.days.map(\.tokens) == [1600, 5000, 900])
    }

    @Test("A daily answer needs no folding")
    func dailyLabelsAlsoWork() throws {
        // The server picks the granularity from the span, so both label shapes
        // arrive at different times and neither may be assumed.
        #expect(ZaiUsageService.day(from: "2026-09-06") == Self.day("2026-09-06"))
        #expect(ZaiUsageService.day(from: "2026-09-06 01:00") == Self.day("2026-09-06"))
        #expect(ZaiUsageService.day(from: "nonsense") == nil)
    }

    @Test("Per-model totals are kept, summed across the day's hours")
    func modelTotals() throws {
        let ledger = try #require(ZaiUsageService.ledger(from: try Self.payload()))
        let fifth = try #require(ledger.days.first { $0.date == Self.day("2026-09-05") })

        #expect(fifth.models["glm-4.6"] == 1400)
        #expect(fifth.models["glm-4-flash"] == 200)
    }

    @Test("Every token is unpriced, and the ledger says where it came from")
    func nothingIsPriced() throws {
        let ledger = try #require(ZaiUsageService.ledger(from: try Self.payload()))

        // One token total per model, with no split between input, output and
        // cache — so no price list can turn it into money, and the card must
        // not print a zero as though it were a cost.
        #expect(ledger.origin == .providerStatistics)
        let allUnpriced = ledger.days.allSatisfy { $0.cost == 0 && $0.unpricedTokens == $0.tokens }
        #expect(allUnpriced)
        // Rate-window spend needs the moment work happened; a day bucket
        // cannot answer it, so nothing pretends to.
        #expect(ledger.slots.isEmpty)
    }

    @Test("An account with no usage yet is no history, not a history of zeroes")
    func emptyIsNil() throws {
        let empty = try JSONDecoder().decode(
            ZaiUsageService.Statistics.self,
            from: Data(#"{"code":200,"success":true,"data":{"x_time":[],"tokensUsage":[],"modelDataList":[]}}"#.utf8)
        )
        #expect(ZaiUsageService.ledger(from: try #require(empty.data)) == nil)

        let allZero = try JSONDecoder().decode(
            ZaiUsageService.Statistics.self,
            from: Data(#"{"code":200,"success":true,"data":{"x_time":["2026-09-06"],"tokensUsage":[0],"modelDataList":[]}}"#.utf8)
        )
        // This is the live account's answer today: buckets exist and every one
        // is zero. A chart of nothing is worse than no card.
        #expect(ZaiUsageService.ledger(from: try #require(allZero.data)) == nil)
    }

    @Test("The span is local wall-clock, encoded, and inside what the server answers")
    func requestShape() throws {
        let now = Date(timeIntervalSince1970: 1_788_768_000)
        let url = ZaiUsageService.statisticsURL(from: now, days: ZaiUsageService.historyDays)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.host == "open.bigmodel.cn")
        #expect(url.path == "/api/monitor/usage/model-usage")
        #expect(items.map(\.name).sorted() == ["endTime", "startTime"])
        // 90 days comes back a 500, so the window has to stay inside what the
        // service will answer.
        #expect(ZaiUsageService.historyDays <= 30)
        // No zone offset and no `T`: the service wants plain local time.
        let start = try #require(items.first { $0.name == "startTime" }?.value)
        #expect(start.contains(" ") && !start.contains("T") && !start.contains("+"))
    }
}
