import Foundation
import Testing
@testable import Pulse

/// Qoder's dashboard credits reply. The fixture is the shape the account
/// usage JSON carries (plan + shared), with no account identifiers.
@Suite("Qoder credits parsing")
struct QoderParsingTests {
    private static func captured() throws -> QoderUsageService.Reply {
        let url = try #require(
            Bundle.module.url(forResource: "qoder-credits", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(QoderUsageService.Reply.self, from: Data(contentsOf: url))
    }

    @Test("Plan and shared credits become two monthly windows")
    func capturedReply() throws {
        let windows = QoderUsageService.windows(from: try Self.captured())
        #expect(windows.map(\.id) == ["qoder.plan", "qoder.shared"])
        #expect(windows.map(\.kind) == [.monthly, .monthly])
        #expect(windows[0].scope == "Team Plan")
        #expect(windows[1].scope == "Add-on Credits")
        #expect(windows.map(\.reportsLength) == [false, false])
        #expect(windows[0].usedFraction == 0.2)
        #expect(windows[1].usedFraction == 0.1)
        #expect(windows[0].isExhausted == false)
    }

    @Test("The CLI snapshot puts the shared pack on its own ring")
    func orgResourcePackage() throws {
        let url = try #require(
            Bundle.module.url(forResource: "qoder-quota-usage", withExtension: "json", subdirectory: "Fixtures")
        )
        let reply = try JSONDecoder().decode(QoderUsageService.Reply.self, from: Data(contentsOf: url))
        let windows = QoderUsageService.windows(from: reply)
        #expect(windows.map(\.id) == ["qoder.plan", "qoder.shared"])
        #expect(windows[0].usedFraction == 0.2)
        #expect(windows[1].usedFraction == 0.005)
        #expect(windows[0].scope == "Team Plan")
        #expect(windows[1].scope == "Add-on Credits")
    }

    @Test("The usage page's two bars are two JSON documents")
    func teamPlanAndOrgAddOn() throws {
        let planURL = try #require(
            Bundle.module.url(forResource: "qoder-plan-credits", withExtension: "json", subdirectory: "Fixtures")
        )
        let addOnURL = try #require(
            Bundle.module.url(forResource: "qoder-shared-credits", withExtension: "json", subdirectory: "Fixtures")
        )
        let plan = QoderUsageService.windows(from: try JSONDecoder().decode(QoderUsageService.Reply.self, from: Data(contentsOf: planURL)))
        let addOn = QoderUsageService.windows(from: try JSONDecoder().decode(QoderUsageService.Reply.self, from: Data(contentsOf: addOnURL)))
        #expect(plan.map(\.id) == ["qoder.plan"])
        #expect(plan[0].usedFraction == 51.0 / 6000.0)
        #expect(addOn.map(\.id) == ["qoder.shared"])
        #expect(addOn[0].usedFraction == 0)
        #expect(addOn[0].scope == "Add-on Credits")
    }

    @Test("A well-formed cookie header is kept")
    func cookieNormalize() throws {
        let kept = try QoderSessionCookie.normalize("Cookie: sid=abc123; other=xyz")
        #expect(kept.contains("sid=abc123"))
        #expect(kept.contains("other=xyz"))
    }
}
