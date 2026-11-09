import AppKit
import SwiftUI
import Testing
@testable import Pulse

@Suite("Detail card viewport")
struct DetailCardViewportTests {
    private func layout(_ limit: CGFloat, summary: CGFloat = 80, details: CGFloat = 300) -> DetailCardViewport {
        DetailCardViewport(limit: limit, summary: summary, details: details,
                           spacing: 14, padding: 18, minimumDetailHeight: 34)
    }

    @Test("Short cards keep their natural height; a long card reserves a details viewport")
    func naturalAndBounded() {
        let short = layout(500, details: 30)
        #expect(short.height == 160)
        #expect(short.detailHeight == 30)
        #expect(short.fixesSummary && !short.scrolls)
        let long = layout(300)
        #expect(long.height == 300)
        #expect(long.detailHeight == 170)
        #expect(long.fixesSummary && long.scrolls)
        #expect(layout(430).scrolls == false)
        #expect(layout(429).scrolls)
        #expect(layout(429).fixesSummary)
    }

    @Test("A tiny placement scrolls the whole summary rather than stranding details", arguments: [CGFloat(-10), 0, 1, 80, 150])
    func tiny(limit: CGFloat) {
        let result = layout(limit)
        #expect(!result.fixesSummary)
        #expect(result.scrolls)
        #expect(result.height == max(limit, 0))
        #expect(result.detailHeight >= 0)
    }

    @Test("A title-only card has no extra details gap")
    func titleOnly() {
        let result = layout(300, details: 0)
        #expect(result.height == 116)
        #expect(result.detailHeight == 0)
        #expect(!result.scrolls)
    }

    @Test("Finite screen limits replace the fallback; only vertical pointers consume height")
    func bodyBudget() {
        for room: CGFloat? in [nil, .infinity] {
            #expect(DetailCardViewport.bodyLimit(maxHeight: room, fallbackHeight: 300, pointerHeight: 0) == 300)
        }
        #expect(DetailCardViewport.bodyLimit(maxHeight: 300, fallbackHeight: 300, pointerHeight: 0) == 300)
        #expect(DetailCardViewport.bodyLimit(maxHeight: 900, fallbackHeight: 300, pointerHeight: 0) == 900)
        #expect(DetailCardViewport.bodyLimit(maxHeight: 300, fallbackHeight: 300, pointerHeight: 20) == 280)
        #expect(DetailCardViewport.bodyLimit(maxHeight: 900, fallbackHeight: 300, pointerHeight: 20) == 880)
        #expect(DetailCardViewport.bodyLimit(maxHeight: nil, fallbackHeight: 300, pointerHeight: 20) == 300)
        #expect(DetailCardViewport.bodyLimit(maxHeight: 10, fallbackHeight: 300, pointerHeight: 20) == 0)
    }
}

extension PanelGlobalsSuite {
    /// Hosted layout and programmatic scrolling are local probes, not evidence
    /// of wheel/trackpad delivery to the actual non-key accessory panel.
    @MainActor
    @Suite("Detail card overflow")
    struct DetailCardOverflowTests {
        private func reading(count: Int = 20, slot: String = "overflow-fixture") -> ProviderUsage {
            let limits = (0..<count).map { index in
                #"{"id":"quota-\#(index)","label":"Quota \#(index)","usedPercent":\#(index == 0 ? 100 : 33)}"#
            }.joined(separator: ",")
            let series = #"[{"t":"2026-11-01T00:00:00Z","v":10},{"t":"2026-11-01T01:00:00Z","v":20}]"#
            let report = #"{"schemaVersion":1,"limits":[\#(limits)],"balance":{"amount":16,"currency":"USD"},"metrics":[{"id":"first","label":"Latency","value":20,"history":\#(series)},{"id":"second","label":"Rate","value":20,"history":\#(series)},{"id":"third","label":"Requests","value":30},{"id":"last","label":"Last metric","value":40}]}"#
            return ExtensionReport.reading(from: Data(report.utf8),
                for: AccountKey(.pulseExtension, slot: slot), now: Date(timeIntervalSince1970: 1_000))
        }

        @Test("Every size, bar style and forecast/detail budget bounds every edge")
        func budgets() {
            let size = PanelSize.allCases.first { $0.scale == PanelMetrics.scale } ?? .default
            let style = PanelMetrics.usageBarStyle
            let forecast = PanelMetrics.showsForecast
            let detailed = PanelMetrics.showsDetailedCard
            defer {
                PanelMetrics.use(size)
                PanelMetrics.use(style)
                PanelMetrics.showForecast(forecast)
                PanelMetrics.showDetailedCard(detailed)
            }
            for size in PanelSize.allCases {
                PanelMetrics.use(size)
                for style in UsageBarStyle.allCases {
                    PanelMetrics.use(style)
                    for detailed in [false, true] {
                        PanelMetrics.showDetailedCard(detailed)
                        for forecast in [false, true] {
                            PanelMetrics.showForecast(forecast)
                            for edge in [PanelEdge.left, .right, .top, .bottom] {
                                let pointer = edge.isVertical ? 0 : DetailCardLayout.pointerWidth
                                let limit = DetailCardViewport.bodyLimit(maxHeight: 240,
                                    fallbackHeight: DetailCardLayout.maximumHeight, pointerHeight: pointer)
                                let layout = DetailCardViewport(limit: limit,
                                    summary: DetailCardLayout.headerHeight + DetailCardLayout.contentSpacing + DetailCardLayout.rowHeight,
                                    details: DetailCardLayout.height(forWindows: 20),
                                    spacing: DetailCardLayout.contentSpacing, padding: DetailCardLayout.padding,
                                    minimumDetailHeight: DetailCardLayout.rowHeight)
                                #expect(layout.height + pointer <= 240)
                                #expect(layout.height <= DetailCardLayout.maximumHeight)
                                #expect(layout.scrolls)
                                #expect(layout.detailHeight >= 0)
                            }
                        }
                    }
                }
            }
        }

        private func settle(_ host: NSView) async throws {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        private func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }

        private func capture(_ host: NSView, to url: URL) throws {
            host.display()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: url)
        }

        @Test("A long hosted card fits on every edge even without a restrictive screen limit",
               arguments: [PanelEdge.left, .right, .top, .bottom])
        func hosted(edge: PanelEdge) async throws {
            let usage = reading()
            for room: CGFloat? in [nil, DetailCardLayout.maximumHeight, DetailCardLayout.maximumHeight * 2] {
                let card = UsageDetailCard(usage: usage,
                    edge: edge, pointerCenter: 60, maxHeight: room)
                let host = NSHostingView(rootView: card.fixedSize().environment(\.colorScheme, .dark))
                host.setFrameSize(CGSize(width: 500, height: 1_400))
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                defer { window.contentView = nil; window.close() }
                try await settle(host)
                let pointer = edge.isVertical ? 0 : DetailCardLayout.pointerWidth
                let limit = room ?? (DetailCardLayout.maximumHeight + pointer)
                #expect(host.fittingSize.height <= limit + 0.5)
                if let room, room > DetailCardLayout.maximumHeight {
                    #expect(host.fittingSize.height > DetailCardLayout.maximumHeight + pointer)
                }
                let scroll = try #require(scrollView(in: host))
                let document = try #require(scroll.documentView)
                #expect(document.bounds.height > scroll.contentView.bounds.height)
                let captureDirectory = edge == .right && room == nil
                    ? ProcessInfo.processInfo.environment["PULSE_DETAIL_CARD_CAPTURE_DIR"].map { URL(fileURLWithPath: $0) } : nil
                if let captureDirectory {
                    try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
                    window.setContentSize(host.fittingSize)
                    window.isOpaque = false
                    window.backgroundColor = .clear
                    try await settle(host)
                    try capture(host, to: captureDirectory.appendingPathComponent("detail-top.png"))
                }
                let firstY = document.isFlipped ? document.bounds.minY
                    : max(document.bounds.maxY - scroll.contentView.bounds.height, document.bounds.minY)
                #expect(abs(scroll.contentView.bounds.minY - firstY) < 1)
                let lastY = document.isFlipped
                    ? max(document.bounds.maxY - scroll.contentView.bounds.height, document.bounds.minY)
                    : document.bounds.minY
                let last = scroll.contentView.constrainBoundsRect(CGRect(
                    x: 0, y: lastY, width: scroll.contentView.bounds.width,
                    height: scroll.contentView.bounds.height))
                scroll.contentView.scroll(to: last.origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                #expect(abs(scroll.contentView.bounds.minY - lastY) < 1)
                if let captureDirectory {
                    try await settle(host)
                    try capture(host, to: captureDirectory.appendingPathComponent("detail-bottom.png"))
                }
            }
        }

        @Test("Switching a long reading to a balance-only reading and back recovers height")
        func longShortLong() async throws {
            let long = reading()
            let short = ExtensionReport.reading(from: Data(#"{"schemaVersion":1,"balance":{"amount":2,"currency":"USD"}}"#.utf8),
                for: long.account, now: Date(timeIntervalSince1970: 1_000))
            func card(_ usage: ProviderUsage) -> some View {
                UsageDetailCard(usage: usage, edge: .right, pointerCenter: 60).fixedSize()
            }
            let host = NSHostingView(rootView: card(long))
            host.setFrameSize(CGSize(width: 500, height: 1_400))
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            try await settle(host)
            let tall = host.fittingSize.height
            host.rootView = card(short)
            try await settle(host)
            #expect(host.fittingSize.height < tall)
            host.rootView = card(long)
            try await settle(host)
            #expect(abs(host.fittingSize.height - tall) < 1)
            #expect(host.fittingSize.height <= DetailCardLayout.maximumHeight + 0.5)
        }
    }
}
