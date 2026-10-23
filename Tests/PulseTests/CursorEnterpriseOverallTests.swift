import Foundation
import Testing
@testable import Pulse

@Suite("Cursor enterprise overall allowance")
struct CursorEnterpriseOverallTests {
    @Test("An enterprise overall allowance becomes the monthly window and balance")
    func enterpriseOverall() throws {
        let url = try #require(Bundle.module.url(
            forResource: "cursor-enterprise-overall", withExtension: "json", subdirectory: "Fixtures"
        ))
        let reply = try JSONDecoder().decode(
            CursorUsageService.Reply.self,
            from: Data(contentsOf: url)
        )
        let windows = CursorUsageService.windows(from: reply)

        #expect(windows.map(\.id) == ["plan"])
        #expect(windows[0].kind == .monthly)
        #expect(windows[0].usedFraction == 0.001)
        #expect(windows[0].amounts?.used == 0.8)
        #expect(windows[0].amounts?.limit == 800)
        #expect(windows[0].amounts?.remaining == 799.2)
        #expect(windows[0].amounts?.currency == "USD")
        let dollars = { Money.reported($0, code: "USD") }
        #expect(UsageDetailCard.amountText(windows[0], remaining: false) == "\(dollars(0.8)) / \(dollars(800))")
        #expect(UsageDetailCard.amountText(windows[0], remaining: true) == "\(dollars(799.2)) / \(dollars(800))")
        #expect(CursorUsageService.remaining(reply) == "$799.20")
    }
}
