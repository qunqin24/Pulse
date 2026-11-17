import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// Draws a row of rings with the second ring and the window clock on, for
/// looking at, not for checking:
///
///     PULSE_RING_PREVIEW=/tmp/rings swift test --filter RingStyleRenderTests
///
/// writes `rings.png`. Without the variable the test is skipped.
@MainActor
@Suite("Ring style render", .serialized)
struct RingStyleRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_RING_PREVIEW"] != nil))
    func render() throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_RING_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // (provider, outer used, inner used, clock)
        let rings: [(Provider, Double?, Double?, Double?)] = [
            (.claudeCode, 0.22, 0.40, 0.70), (.codex, 0.48, 0.30, 0.40), (.cursor, 0.27, 0.55, 0.55),
            (.grokBot, 0.62, 0.70, 0.90), (.antigravity, 0.01, 0.20, 0.30), (.kimiCode, 0.01, 0.05, 0.20),
            (.commandCode, nil, nil, nil),
        ]
        func row(clock: Bool) -> some View {
            HStack(spacing: DockLayout.itemSpacing) {
                ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                    VStack(spacing: DockLayout.ringToTextSpacing) {
                        UsageRingView(
                            provider: ring.0, usedFraction: ring.1, hasReading: ring.1 != nil,
                            diameter: DockLayout.ringDiameter, lineWidth: DockLayout.ringLineWidth,
                            windowClockFraction: clock ? ring.3 : nil,
                            secondFraction: ring.2, secondIsSpent: false
                        )
                        Text(verbatim: ring.1.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        let view = VStack(spacing: 28) { row(clock: true); row(clock: false) }
            .padding(24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
        try write(view, to: folder.appendingPathComponent("rings.png"))
    }

    private func write<V: View>(_ view: V, to url: URL) throws {
        let appearance = NSAppearance(named: .darkAqua)!
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.contentView = nil
    }
}
