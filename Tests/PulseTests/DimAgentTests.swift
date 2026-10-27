import Foundation
import Testing
@testable import Pulse

@Suite("DimAgent")
struct DimAgentTests {
    private let context = ProfileContext(provider: .dimAgent, credential: nil, serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_793_059_200)

    // Shape observed from dimcode 0.5.21; identities removed and figures replaced.
    private let sample = #"""
    {"subscription":{"product":{"name":"Max套餐"}},
     "credits":{"subscription_bucket":{"id":1,"status":"active","total_units":100000,
       "used_units":88000,"remaining_units":12000,"expires_at":"2026-11-13T02:33:55.398Z"},
       "addon_buckets":[]},
     "feature_meters":[{"feature_key":"web_search","total_allowance":5500,
       "total_used":100,"total_remaining":5400,"unlimited":false,"period_end":"2026-11-13T02:33:55.398Z"}]}
    """#

    @Test("The built-in subscription uses the CLI login and is not an API money balance")
    func registration() {
        #expect(Provider.builtIn.contains(.dimAgent))
        #expect(Provider.dimAgent.billing == .subscription)
        #expect(Provider.dimAgent.profile?.credential == .localLogin)
        #expect(Provider.dimAgent.usesAPIKey == false)
        #expect(Provider.dimAgent.profile?.spendingIsWatchedLocally == false)
    }

    @Test("Plan credits and search remain separate, with the reported amounts")
    func reading() {
        let usage = DimAgentUsageService.reading(from: Data(sample.utf8), context: context, now: now)
        #expect(usage.state == .live)
        #expect(usage.plan == "Max套餐")
        #expect(usage.windows.count == 2)
        #expect(usage.windows[0].usedFraction == 0.88)
        #expect(usage.windows[0].amounts?.remaining == 12000)
        #expect(usage.windows[0].resetsAt == nil)
        #expect(usage.windows[0].nextExpiry?.at == ProfileHTTP.date("2026-11-13T02:33:55.398Z"))
        #expect(usage.windows[0].isExhausted == false)
        #expect(usage.windows[1].usedFraction == 100.0 / 5500)
        #expect(usage.windows.allSatisfy { !$0.reportsLength })
        #expect(usage.creditRemaining == nil)
    }

    @Test("An add-on is not included in the plan denominator or treated as a reset")
    func addon() {
        let json = #"{"credits":{"addon_buckets":[{"id":9,"status":"active","total_units":1000,"used_units":200,"remaining_units":800,"expires_at":"2026-12-01T00:00:00Z"}]}}"#
        let usage = DimAgentUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.windows.map(\.kind) == [.topUp])
        #expect(usage.windows.first?.id == "dimagent.addon.9")
        #expect(usage.windows.first?.resetsAt == nil)
    }

    @Test("Missing, invalid, expired and unlimited quotas are never shown as zero", arguments: [
        #"{}"#,
        #"{"credits":{"subscription_bucket":{"status":"active","total_units":0,"used_units":0}}}"#,
        #"{"credits":{"subscription_bucket":{"status":"active","total_units":100,"used_units":-1}}}"#,
        #"{"credits":{"subscription_bucket":{"status":"active","total_units":100,"used_units":1,"expires_at":"2020-01-01T00:00:00Z"}}}"#,
        #"{"feature_meters":[{"feature_key":"web_search","unlimited":true,"total_allowance":100,"total_used":0}]}"#
    ])
    func absent(json: String) {
        #expect(DimAgentUsageService.reading(from: Data(json.utf8), context: context, now: now).state
                == .unavailable(.noLimitsReported))
    }

    @Test("Malformed replies fail explicitly", arguments: ["not json", "[]", #"{"credits":42}"#])
    func malformed(json: String) {
        #expect(DimAgentUsageService.reading(from: Data(json.utf8), context: context).state
                == .unavailable(.unreadableReply))
    }

    @Test("The helper gets mise shims and proxies, but no inherited credentials")
    func environment() {
        let env = DimAgentUsageService.environment(for: URL(fileURLWithPath: "/example/bin/dim"),
            inherited: ["HOME": "/example", "PATH": "/usr/bin", "HTTPS_PROXY": "http://localhost:1234",
                        "UNRELATED_API_KEY": "test-only", "DIMCODE_BIN_PATH": "/untrusted"], home: "/example")
        #expect(env["UNRELATED_API_KEY"] == nil)
        #expect(env["DIMCODE_BIN_PATH"] == nil)
        #expect(env["HTTPS_PROXY"] == "http://localhost:1234")
        #expect(env["PATH"]?.hasPrefix("/example/bin:/example/.local/share/mise/shims:") == true)
    }

    @Test("The installed CLI answers through the production service", .enabled(if: ProcessInfo.processInfo.environment["PULSE_TEST_DIM_LIVE"] == "1"))
    func liveCLI() async {
        let usage = await DimAgentUsageService.fetch(context)
        #expect(usage.state == .live)
        #expect(usage.windows.contains { $0.id == "dimagent.subscription" })
        #expect(usage.plan?.isEmpty == false)
    }

    @Test("Cached buckets disappear at full expiry; partial expiries do not erase the pool")
    func cachedExpiry() throws {
        let expiry = try #require(ProfileHTTP.date("2026-11-13T02:33:55.398Z"))
        let usage = DimAgentUsageService.reading(from: Data(sample.utf8), context: context,
                                                 now: expiry.addingTimeInterval(-10))
        #expect(usage.current(at: expiry.addingTimeInterval(-1))?.windows.count == 2)
        #expect(usage.current(at: expiry) == nil)
        var partial = usage
        partial.windows[0].nextExpiry?.coversRemainder = false
        #expect(partial.current(at: expiry)?.windows.map(\.id) == ["dimagent.subscription"])
        var staggered = usage
        staggered.windows[0].nextExpiry?.lots = 2
        staggered.windows[0].nextExpiry?.totalAmount = 12000
        #expect(staggered.current(at: expiry)?.windows.map(\.id) == ["dimagent.subscription"])
    }

    @Test("Pooled expiry summaries stay cached unless the profile opts into whole-bucket expiry",
          arguments: [Provider.qoder, Provider.clinePass])
    func pooledExpiry(provider: Provider) throws {
        let expiry = try #require(ProfileHTTP.date("2026-11-13T02:33:55.398Z"))
        let usage = DimAgentUsageService.reading(from: Data(sample.utf8), context: context,
                                                 now: expiry.addingTimeInterval(-10))
        let pooled = ProviderUsage(
            account: AccountKey(provider), windows: usage.windows,
            observedAt: usage.observedAt, state: .live, plan: nil, creditBalance: nil
        )
        #expect(pooled.current(at: expiry)?.windows.map(\.id) == ["dimagent.subscription"])
    }

    @Test("An expiring bucket without a reported remainder is not accepted", arguments: ["", ",\"remaining_units\":null"])
    func expiryWithoutRemainder(remainder: String) {
        let json = """
        {"credits":{"subscription_bucket":{"status":"active","total_units":100,
        "used_units":95,"expires_at":"2026-11-13T02:33:55.398Z"\(remainder)}}}
        """
        let usage = DimAgentUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("Enabling alerts after a bucket expires never warns about that bucket")
    func alertsAfterExpiry() throws {
        let expiry = try #require(ProfileHTTP.date("2026-11-13T02:33:55.398Z"))
        let usage = DimAgentUsageService.reading(
            from: Data(sample.replacingOccurrences(of: "88000", with: "95000").utf8),
            context: context, now: expiry.addingTimeInterval(-10)
        )
        func alerts(at time: Date) -> [UsageAlert] {
            var memory = AlertMemory()
            return memory.alerts(for: usage, raw: .live, as: context.account,
                                 threshold: .ninety, announcesReset: false,
                                 announcesFailure: false, lowBalance: nil,
                                 staleMeansFailure: true, now: time)
        }
        #expect(alerts(at: expiry.addingTimeInterval(-1)).map(\.window?.id) == ["dimagent.subscription"])
        #expect(alerts(at: expiry).isEmpty)
    }

    @Test("CLI login and throttling errors retain distinct remedies")
    func errors() {
        #expect(DimAgentUsageService.exitReason("Run dim auth login") == .localLoginExpired)
        #expect(DimAgentUsageService.exitReason("HTTP 429") == .rateLimited)
        #expect(DimAgentUsageService.exitReason("Connection refused") == .unreachable)
    }
}
