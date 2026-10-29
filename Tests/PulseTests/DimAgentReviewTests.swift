import Foundation
import Testing
@testable import Pulse

@Suite("DimAgent review regressions")
struct DimAgentReviewTests {
    private let context = ProfileContext(provider: .dimAgent, credential: nil, serverAddress: nil)
    private let now = Date(timeIntervalSince1970: 1_793_059_200)

    private func reading(bucket: Int = 1, used: Int, at time: Date, expiry: Date,
                         tokenWindows: String = "[]") -> ProviderUsage {
        let json = """
        {"credits":{"subscription_bucket":{"id":\(bucket),"status":"active",
        "total_units":100,"used_units":\(used),"remaining_units":\(100 - used),
        "expires_at":"\(expiry.ISO8601Format())","window_states":\(tokenWindows)},"addon_buckets":[]}}
        """
        return DimAgentUsageService.reading(from: Data(json.utf8), context: context, now: time)
    }

    private func alerts(_ reading: ProviderUsage, memory: inout AlertMemory, at time: Date) -> [UsageAlert] {
        memory.alerts(for: reading, raw: reading.state, as: context.account,
                      threshold: .ninety, announcesReset: true, announcesFailure: false,
                      lowBalance: nil, staleMeansFailure: true, now: time)
    }

    @Test("A full reported token window drives the headline and spent alert despite low plan usage")
    func tokenWindow() throws {
        let reset = now.addingTimeInterval(3600)
        let windows = """
        [{"window_duration_hours":5,"window_token_cap":1000,"window_token_used":1000,
          "window_expires_at":"\(reset.ISO8601Format())"}]
        """
        let usage = reading(used: 10, at: now, expiry: now.addingTimeInterval(86400), tokenWindows: windows)
        let window = try #require(usage.windows.first { $0.kind == .fiveHour })
        #expect(window.usedFraction == 1)
        #expect(window.windowSeconds == 18000)
        #expect(window.reportsLength)
        #expect(window.resetsAt == reset)
        #expect(window.amounts?.used == 1000)
        #expect(window.amounts?.limit == 1000)
        #expect(usage.headlineWindow(preferring: nil)?.id == window.id)
        var memory = AlertMemory()
        #expect(alerts(usage, memory: &memory, at: now).map(\.kind) == [.spent])
    }

    @Test("Token windows retain fractional durations and distinct IDs while rejecting invalid limits")
    func tokenWindowValidation() {
        let windows = """
        [{"id":7,"window_duration_hours":0.5,"window_token_cap":100,"window_token_used":10},
         {"id":8,"window_duration_hours":0.5,"window_token_cap":100,"window_token_used":20},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":30},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":40},
         {"window_duration_hours":1e100,"window_token_cap":100,"window_token_used":1},
         {"window_duration_hours":-1,"window_token_cap":100,"window_token_used":1},
         {"window_duration_hours":5,"window_token_cap":0,"window_token_used":1},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":-1},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":1,"window_expires_at":"bad"},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":1,"window_expires_at":"2020-01-01T00:00:00Z"}]
        """
        let usage = reading(used: 10, at: now, expiry: now.addingTimeInterval(86400), tokenWindows: windows)
        let tokens = usage.windows.filter { $0.kind != .planCredits }
        #expect(tokens.map(\.usedFraction) == [0.1, 0.2, 0.3, 0.4])
        #expect(tokens.map(\.windowSeconds) == [1800, 1800, 18000, 18000])
        #expect(Set(tokens.map(\.id)).count == 4)
    }

    @Test("Token limits cannot outlive their parent grant", arguments: [true, false])
    func parentExpiry(hasReset: Bool) throws {
        let expiry = now.addingTimeInterval(60)
        let reset = hasReset ? "\"\(now.addingTimeInterval(3600).ISO8601Format())\"" : "null"
        let windows = """
        [{"window_duration_hours":5,"window_token_cap":100,"window_token_used":95,
          "window_expires_at":\(reset)}]
        """
        let usage = reading(used: 10, at: now, expiry: expiry, tokenWindows: windows)
        #expect(usage.current(at: expiry.addingTimeInterval(-1))?.windows.count == 2)
        #expect(usage.current(at: expiry) == nil)
        var memory = AlertMemory()
        #expect(alerts(usage, memory: &memory, at: expiry).isEmpty)
        var restored = usage
        restored.windows = try JSONDecoder().decode([UsageWindow].self, from: JSONEncoder().encode(usage.windows))
        #expect(restored.current(at: expiry) == nil)
    }

    @Test("Filtering a reset window does not renumber a surviving same-duration row")
    func tokenIdentityAfterReset() throws {
        let windows = """
        [{"window_duration_hours":5,"window_token_cap":100,"window_token_used":95,
          "window_expires_at":"\(now.addingTimeInterval(60).ISO8601Format())"},
         {"window_duration_hours":5,"window_token_cap":100,"window_token_used":95,
          "window_expires_at":"\(now.addingTimeInterval(3600).ISO8601Format())"}]
        """
        let before = reading(used: 10, at: now, expiry: now.addingTimeInterval(86400), tokenWindows: windows)
        let survivor = try #require(before.windows.last)
        var memory = AlertMemory()
        #expect(alerts(before, memory: &memory, at: now).count == 2)
        let time = now.addingTimeInterval(61)
        let after = reading(used: 10, at: time, expiry: now.addingTimeInterval(86400), tokenWindows: windows)
        #expect(after.windows.last?.id == survivor.id)
        #expect(after.headlineWindow(preferring: survivor.id)?.id == survivor.id)
        #expect(alerts(after, memory: &memory, at: time).isEmpty)
    }

    @Test("Add-on buckets retain their own reported token limits")
    func addonTokenWindow() {
        let json = """
        {"credits":{"addon_buckets":[{"id":9,"status":"active","total_units":100,
        "used_units":10,"remaining_units":90,"window_states":[{"id":1,
        "window_duration_hours":24,"window_token_cap":1000,"window_token_used":950}]}]}}
        """
        let usage = DimAgentUsageService.reading(from: Data(json.utf8), context: context, now: now)
        #expect(usage.windows.map(\.kind) == [.topUp, .daily])
        #expect(usage.headlineWindow(preferring: nil)?.usedFraction == 0.95)
    }

    @Test("Each new subscription grant warns once without turning expiry into a reset")
    func newGrant() throws {
        var memory = AlertMemory()
        let expiry = now.addingTimeInterval(60)
        let first = reading(used: 95, at: now, expiry: expiry)
        #expect(alerts(first, memory: &memory, at: now).map(\.kind) == [.approaching(percent: 90)])
        #expect(alerts(first, memory: &memory, at: now).isEmpty)
        let nextTime = expiry.addingTimeInterval(1)
        let second = reading(bucket: 2, used: 10, at: nextTime, expiry: expiry.addingTimeInterval(86400))
        #expect(alerts(second, memory: &memory, at: nextTime).isEmpty)
        #expect(second.windows.first?.id == first.windows.first?.id)
        #expect(second.windows.first?.resetsAt == nil)
        // A relaunch must retain the new grant's alert state.
        memory = try JSONDecoder().decode(AlertMemory.self, from: JSONEncoder().encode(memory))
        let full = reading(bucket: 2, used: 95, at: nextTime, expiry: expiry.addingTimeInterval(86400))
        #expect(alerts(full, memory: &memory, at: nextTime).map(\.kind) == [.approaching(percent: 90)])
        #expect(alerts(full, memory: &memory, at: nextTime).isEmpty)
        let restored = try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(full.windows[0]))
        #expect(restored.cycleID == full.windows[0].cycleID)
        memory = try JSONDecoder().decode(AlertMemory.self, from: JSONEncoder().encode(memory))
        #expect(alerts(full, memory: &memory, at: nextTime).isEmpty)
    }

    @Test("Old saved windows adopt a grant identity without duplicating a warning")
    func legacyGrant() throws {
        let usage = reading(used: 95, at: now, expiry: now.addingTimeInterval(86400))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(usage.windows[0])) as? [String: Any])
        object.removeValue(forKey: "cycleID")
        var legacy = usage
        legacy.windows[0] = try JSONDecoder().decode(UsageWindow.self, from: JSONSerialization.data(withJSONObject: object))
        var memory = AlertMemory()
        #expect(alerts(legacy, memory: &memory, at: now).count == 1)
        memory = try JSONDecoder().decode(AlertMemory.self, from: JSONEncoder().encode(memory))
        #expect(alerts(usage, memory: &memory, at: now).isEmpty)
        #expect(alerts(legacy, memory: &memory, at: now).isEmpty)
        #expect(alerts(usage, memory: &memory, at: now).isEmpty)
    }

    @Test("An explicit sign-out bypasses cached quotas while transient failures retain them")
    func signedOut() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "dimagent-review-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        let time = Date()
        let live = reading(used: 50, at: time, expiry: time.addingTimeInterval(86400))
        let banked = await cache.reconciled(live)
        #expect(banked.state == .live)
        let transient = await cache.reconciled(context.unavailable(.unreachable))
        #expect(transient.state == .stale)
        #expect(transient.windows.first?.usedFraction == 0.5)
        let reason = DimAgentUsageService.exitReason("Not signed in to DimAgent. Run: dim auth login --provider dimcode-api-oauth")
        let signedOut = await cache.reconciled(context.unavailable(reason))
        #expect(signedOut.state == .unavailable(.localLoginMissing))
        #expect(signedOut.windows.isEmpty)
    }
}
