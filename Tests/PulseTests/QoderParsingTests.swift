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
        #expect(windows[1].scope == "Shared")
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
        #expect(windows[1].scope == "Shared")
    }

    @Test("A well-formed cookie header is kept")
    func cookieNormalize() throws {
        let kept = try QoderSessionCookie.normalize("Cookie: sid=abc123; other=xyz")
        #expect(kept.contains("sid=abc123"))
        #expect(kept.contains("other=xyz"))
    }
}
