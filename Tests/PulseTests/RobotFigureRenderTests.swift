import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// Every Open Bot Avatar figure in a ring, and one figure in each mood, for
/// looking at, not for checking:
///
///     PULSE_ROBOT_PREVIEW=/tmp/robots swift test --filter RobotFigureRenderTests
///
/// writes `figures.png` and `moods.png` on the dark panel at 2×. Without the
/// variable the test is skipped.
@MainActor
@Suite("Robot figure render", .serialized)
struct RobotFigureRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_ROBOT_PREVIEW"] != nil))
    func render() async throws {
        // Each figure's first frame builds its volume on the engine's queue,
        // hundreds of milliseconds apiece; build them all before drawing.
        for figure in RobotFigures.automatic {
            _ = await BotAvatarEngine.shared.frame(key: "render-warm", figure: figure, state: .idle, happy: false,
                                                   time: 0, now: 0, reducedMotion: false, size: 27, colour: "#ffffff")
        }
        BotAvatarEngine.shared.forget(key: "render-warm")
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_ROBOT_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inks = RobotAutomatic.inks(for: Array(repeating: Provider.codex, count: RobotFigures.automatic.count),
                                       custom: Array(repeating: nil, count: RobotFigures.automatic.count))

        let figures = VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<3) { row in
                HStack(spacing: DockLayout.itemSpacing) {
                    ForEach(Array(RobotFigures.automatic.enumerated()).filter { $0.offset / 8 == row }, id: \.offset) { index, figure in
                        cell(figure, mood: .idle, used: 0.3, ink: inks[index].ink, label: RobotFigures.title(figure))
                    }
                }
            }
        }
        try await write(figures, to: folder.appendingPathComponent("figures.png"))

        let moods: [(RobotMood, RobotGesture?, String)] = [
            (.idle, nil, "idle"), (.working, nil, "working"), (.refreshing, nil, "refreshing"),
            (.spent, nil, "spent"), (.asleep, nil, "no reading"), (.idle, .cheer, "reset"), (.idle, .nod, "turn done"),
        ]
        let blue = RobotInk(rgb: 0x4285F4)
        let moodRows = VStack(alignment: .leading, spacing: 18) {
            ForEach([false, true], id: \.self) { second in
                HStack(spacing: DockLayout.itemSpacing) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { _, entry in
                        cell("mug", mood: entry.0, gesture: entry.1, used: entry.0 == .spent ? 1 : 0.45,
                             ink: blue, label: entry.2, second: second ? 0.7 : nil)
                    }
                }
            }
        }
        try await write(moodRows, to: folder.appendingPathComponent("moods.png"))
    }

    private func cell(_ figure: String, mood: RobotMood, gesture: RobotGesture? = nil, used: Double,
                      ink: RobotInk, label: String, second: Double? = nil) -> some View {
        VStack(spacing: DockLayout.ringToTextSpacing) {
            UsageRingView(
                provider: .codex, usedFraction: mood == .asleep ? nil : used, hasReading: mood != .asleep,
                isSpent: mood == .spent,
                diameter: DockLayout.ringDiameter, lineWidth: DockLayout.ringLineWidth,
                isBusy: mood == .working, isRefreshing: mood == .refreshing,
                secondFraction: second, secondIsSpent: false,
                robot: RobotCue(justReset: gesture == .cheer, justFinished: gesture == .nod, ink: ink, figure: figure)
            )
            Text(verbatim: label).font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize()
        }
        .frame(width: 64)
    }

    private func write<V: View>(_ view: V, to url: URL) async throws {
        let content = view
            .padding(24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Long enough for a cheer to be under way and a mood change to settle.
        // A sleep, not a run of the run loop: the figures' frames arrive on
        // the main actor, which a blocked run loop never gives them.
        try await Task.sleep(for: .seconds(1.5))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.contentView = nil
    }
}
