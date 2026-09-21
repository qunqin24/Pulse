import Foundation
import Testing
@testable import Pulse

@Suite("Kiro usage")
struct KiroUsageTests {
    private static func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "kiro-pro-plus-usage", withExtension: "json", subdirectory: "Fixtures"
        ))
        return try Data(contentsOf: url)
    }

    @Test("Provider uses the bundled Kiro mark")
    @MainActor
    func hasBundledIcon() throws {
        #expect(Provider.kiro.iconResource == "kiro")
        #expect(LobeIconStore.image(named: Provider.kiro.iconResource) != nil,
                "\(Provider.kiro.iconResource).svg does not load")
    }

    @Test("ACP usage maps every bounded credit pool")
    func parsesUsage() throws {
        let result = try JSONDecoder().decode(KiroUsageService.Result.self, from: Self.fixture())
        let payload = try #require(result.data)
        let windows = KiroUsageService.windows(from: payload)

        #expect(result.success)
        #expect(payload.planName == "KIRO PRO+")
        #expect(windows.count == 2)
        #expect(windows.map(\.scope) == ["Credits", "Bonus credits"])
        #expect(abs(windows[0].usedFraction - 0.061725) < 0.000_001)
        #expect(windows[1].usedFraction == 0.25)
        #expect(windows.allSatisfy { $0.kind == .monthly && !$0.reportsLength })
        #expect(windows.allSatisfy { $0.resetsAt != nil })
    }

    @Test("Malformed limits are skipped rather than invented")
    func rejectsInvalidLimits() {
        let payload = KiroUsageService.Payload(
            planName: "test",
            billingCycleReset: "not-a-date",
            usageBreakdowns: [
                .init(resourceType: "ZERO", displayName: nil, used: 1, limit: 0,
                      percentage: nil, hasLimit: true),
                .init(resourceType: "UNBOUNDED", displayName: nil, used: 1, limit: 10,
                      percentage: nil, hasLimit: false),
                .init(resourceType: "PERCENT", displayName: "Percent only", used: nil, limit: 80,
                      percentage: 12.5, hasLimit: true)
            ]
        )
        let windows = KiroUsageService.windows(from: payload)
        #expect(windows.count == 1)
        #expect(windows[0].usedFraction == 0.125)
        #expect(windows[0].resetsAt == nil)
    }

    @Test("ACP failures have provider-specific remedies")
    func classifiesFailures() {
        #expect(KiroUsageService.reason(for: .executableNotFound) == .kiroNotInstalled)
        #expect(KiroUsageService.reason(for: .server("Method not found")) == .kiroVersionUnsupported)
        #expect(KiroUsageService.reason(for: "Please sign in") == .kiroSignInRequired)
        #expect(KiroUsageService.reason(for: .timedOut) == .unreachable)
    }
}
