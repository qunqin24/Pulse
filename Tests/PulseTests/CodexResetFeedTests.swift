import Foundation
import Testing
import SwiftUI
@testable import Pulse

@Suite("Codex reset details")
struct CodexResetFeedTests {
    private func fixture() throws -> CodexResetFeed {
        let url = try #require(Bundle.module.url(forResource: "codex-resets", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try CodexResetFeed.decode(Data(contentsOf: url))
    }

    @Test("The summary preserves the API title and schedule label")
    func originalText() throws {
        let feed = try fixture()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-20T00:00:00Z"))
        let event = try #require(feed.nextEvent(now: now))
        #expect(event.title == "Tibo 预告发放重置卡")
        #expect(event.schedule?.label == "北京时间预计 9月22日 15:00–9月23日 15:00")
        #expect(feed.nextEvent(now: now.addingTimeInterval(7 * 86400)) == nil)
    }

    @Test("Only strictly future end times qualify; earliest start wins regardless of input order")
    func selection() {
        let now = Date(timeIntervalSince1970: 1000)
        func event(_ title: String, from: Double, through: Double) -> CodexResetFeed.Event {
            .init(title: title, schedule: .init(label: title,
                from: Date(timeIntervalSince1970: from), through: Date(timeIntervalSince1970: through)))
        }
        let feed = CodexResetFeed(events: [
            event("Later", from: 1200, through: 1400),
            event("Expired", from: 700, through: 999),
            event("Ends now", from: 800, through: 1000),
            .init(title: "No schedule", schedule: nil),
            event("Ongoing", from: 900, through: 1100)
        ])
        #expect(feed.nextEvent(now: now)?.title == "Ongoing")
        #expect(feed.nextEvent(now: Date(timeIntervalSince1970: 1100))?.title == "Later")
        #expect(feed.nextEvent(now: Date(timeIntervalSince1970: 1400)) == nil)
    }

    @Test("Confirmed events also qualify if their schedule has not ended")
    func noStatusFilter() throws {
        let feed = try fixture()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))
        #expect(feed.nextEvent(now: now)?.title == "Codex 额度重置已完成")
    }

    @Test("The compact summary fits its reserved height at every panel size")
    @MainActor
    func layoutBudget() throws {
        let previous = PanelSize.allCases.first { $0.scale == PanelMetrics.scale } ?? .default
        defer { PanelMetrics.use(previous) }
        let feed = try fixture()
        let event = try #require(feed.events.first)
        for size in PanelSize.allCases {
            PanelMetrics.use(size)
            let view = CodexResetSection(event: event)
                .frame(width: DetailCardLayout.width - 2 * DetailCardLayout.padding)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: view)
            let image = try #require(renderer.cgImage)
            #expect(CGFloat(image.height) <= DetailCardLayout.resetSectionHeight)
        }
    }

    @Test("Invalid schedule timestamps fail the reading instead of inventing dates")
    func invalidFeed() {
        #expect(throws: (any Error).self) {
            try CodexResetFeed.decode(Data(#"{"events":[{"title":"Event","schedule":{"label":"When","from":"invalid","through":"invalid"}}]}"#.utf8))
        }
    }
}
