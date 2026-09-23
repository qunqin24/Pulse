import Foundation
import Testing
@testable import Pulse

private final class QoderFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = String((request.value(forHTTPHeaderField: "Cookie") ?? "").dropFirst(4))
        if scenario == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status: Int
        let body: String
        switch scenario {
        case "rateLimited": status = 429; body = "{}"
        case "serverError": status = 500; body = "{}"
        case "expired": status = 401; body = "{}"
        case "malformed": status = 200; body = "{}"
        case "invalidShared":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}},"sharedQuota":{"quotaSummary":{"usedValue":-1,"limitValue":100}}}"#
        case "incompleteShared":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}},"sharedQuota":{"quotaSummary":{"usedValue":0}}}"#
        case "missingSharedSummary":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}},"sharedQuota":{}}"#
        case "spent":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":500,"limitValue":500,"remainingValue":0}}}"#
        case "sharedOnly":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}},"sharedQuota":{"quotaSummary":{"usedValue":20,"limitValue":100,"remainingValue":80}}}"#
        case "emptyAbsentShared":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}}}"#
        case "emptyNullShared":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}},"sharedQuota":null}"#
        case "empty":
            status = 200
            body = #"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0,"remainingValue":0}},"sharedQuota":{"quotaSummary":{"usedValue":0,"limitValue":0,"remainingValue":0}}}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Qoder cache lifecycle")
struct QoderCacheTests {
    private static let account = AccountKey(.qoder)

    private func fetch(_ scenario: String) async -> ProviderUsage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QoderFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await QoderUsageService(
            cookie: "sid=\(scenario)", site: .international, client: QoderClient(session: session)
        ).fetch()
    }

    private func previous(_ scenario: String) -> ProviderUsage {
        var usage = ProviderUsage(
            account: Self.account,
            windows: QoderUsageService.windows(from: .init(
                personal: .init(used: 125, limit: 500, remaining: 375), shared: nil, resetsAt: nil
            )),
            observedAt: Date().addingTimeInterval(-60), state: .live, plan: nil, creditBalance: nil
        )
        usage.sourceScope = QoderUsageService.scope(site: .international, cookie: "sid=\(scenario)")
        return usage
    }

    @Test("A confirmed empty answer removes the old reading from memory, disk and JSON output", arguments: [
        "empty", "emptyAbsentShared", "emptyNullShared"
    ])
    func confirmedEmptyInvalidatesCache(scenario: String) async throws {
        let file = URL.temporaryDirectory.appending(path: "PulseQoderCache-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        _ = await cache.reconciled(previous(scenario))
        let other = ProviderUsage(
            account: AccountKey(.codex), windows: previous(scenario).windows,
            observedAt: Date(), state: .live, plan: nil, creditBalance: nil
        )
        _ = await cache.reconciled(other)

        let raw = await fetch(scenario)
        #expect(raw.state == .unavailable(.qoderNoCredits))
        let displayed = await cache.reconciled(raw)
        #expect(displayed.state == .unavailable(.qoderNoCredits))
        #expect(displayed.windows.isEmpty)
        #expect(await cache.lastReading(for: Self.account) == nil)

        let reopened = UsageCache(file: file)
        let restored = await reopened.lastReading(for: Self.account)
        #expect(restored == nil)
        #expect(await reopened.lastReading(for: other.account)?.windows == other.windows)
        let readings = restored.map { [Self.account.id: $0] } ?? [:]
        let data = try #require(UsageReport.encode(
            rail: .init(accounts: [Self.account], labels: [:], pinnedWindows: [:]),
            readings: readings, generatedAt: Date()
        ))
        let report = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let row = try #require((report["accounts"] as? [[String: Any]])?.first)
        #expect((row["windows"] as? [Any])?.isEmpty == true)
        #expect(row["headline"] == nil)

        // A later failure must not bring the removed reading back.
        var failure = ProviderUsage.unavailable(.qoder, reason: .unreachable)
        failure.sourceScope = raw.sourceScope
        #expect(await reopened.reconciled(failure).state == .unavailable(.unreachable))
        // A new grant can be banked normally after an empty answer.
        let renewed = await reopened.reconciled(previous(scenario))
        #expect(renewed.state == .live)
        #expect(await UsageCache(file: file).lastReading(for: Self.account)?.windows == renewed.windows)
    }

    @Test("Failures retain the last valid reading", arguments: [
        "offline", "rateLimited", "serverError", "expired", "malformed", "invalidShared",
        "incompleteShared", "missingSharedSummary"
    ])
    func failuresKeepCache(scenario: String) async throws {
        let file = URL.temporaryDirectory.appending(path: "PulseQoderFailure-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let old = previous(scenario)
        _ = await cache.reconciled(old)
        let raw = await fetch(scenario)
        #expect(raw.state != .unavailable(.qoderNoCredits))
        if ["malformed", "invalidShared", "incompleteShared", "missingSharedSummary"].contains(scenario) {
            #expect(raw.state == .unavailable(.unreadableReply))
        }
        let displayed = await cache.reconciled(raw)
        #expect(displayed.state == .stale)
        #expect(displayed.windows == old.windows)
        #expect(await UsageCache(file: file).lastReading(for: Self.account)?.windows == old.windows)
    }

    @Test("A spent allowance and a remaining team pool are still readings", arguments: ["spent", "sharedOnly"])
    func zeroRemainingIsNotNoAllowance(scenario: String) async throws {
        let file = URL.temporaryDirectory.appending(path: "PulseQoderPools-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        _ = await cache.reconciled(previous(scenario))
        let raw = await fetch(scenario)
        let displayed = await cache.reconciled(raw)
        #expect(displayed.state == .live)
        #expect(displayed.windows.count == 1)
        if scenario == "spent" {
            #expect(displayed.windows.first?.isExhausted == true)
            #expect(displayed.windows.first?.usedFraction == 1)
        } else {
            #expect(displayed.windows.first?.kind == .sharedCredits)
            #expect(displayed.windows.first?.usedFraction == 0.2)
        }
        #expect(await UsageCache(file: file).lastReading(for: Self.account)?.windows == displayed.windows)
    }
}
