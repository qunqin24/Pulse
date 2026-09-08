import Foundation
import Testing
@testable import Pulse

/// Kimi Code's `/usages` reply, and the two ways Pulse can be looking at it.
///
/// The fixture is the shape a live `METHOD_ACCESS_TOKEN` reply carried on
/// 2026-09-08, with account identifiers left out. When the other end changes
/// shape, this is what says so.
@Suite("Kimi Code usage")
struct KimiCodeTests {
    private static func captured() throws -> KimiCodeUsageService.Reply {
        let url = try #require(
            Bundle.module.url(forResource: "kimi-code-usages", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(KimiCodeUsageService.Reply.self, from: Data(contentsOf: url))
    }

    @Test("The captured reply becomes the 5-hour window, then the rolling week")
    func capturedReply() throws {
        let windows = KimiCodeUsageService.windows(from: try Self.captured())
        #expect(windows.map(\.id) == ["limit.0.18000", "weekly"])
        #expect(windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(windows.map(\.reportsLength) == [true, false])
        #expect(windows[0].usedFraction == 0.11)
        #expect(windows[1].usedFraction == 0.25)
    }

    @Test("LEVEL_ADVANCED is tidied rather than blanked")
    func planName() {
        #expect(KimiCodeUsageService.planName("LEVEL_ADVANCED") == "Advanced")
        #expect(KimiCodeUsageService.planName("LEVEL_INTERMEDIATE") == "Intermediate")
    }

    @Test("Device-code sign-in is the subscription route")
    func deviceCodeIsConfigured() {
        #expect(OAuthLogin.usesDeviceCode(.kimiCode))
        #expect(OAuthLogin.Configuration.of(.kimiCode)?.clientID == "17e5f671-d194-4dfb-9706-5516cb48c098")
        #expect(Provider.kimiCode.supportsMultipleAccounts)
    }
}
