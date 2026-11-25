import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// Every Open Bot Avatar figure in a ring, and one figure in each mood, for
/// looking at, not for checking:
///
///     PULSE_ROBOT_PREVIEW=/tmp/robots swift test --filter RobotFigureRenderTests
///
/// writes `figures.png` and `moods.png` on the dark panel at 2×, the same in
/// fluffy (`figures-fluffy.png`, `moods-fluffy.png`), and a few fluffy figures
/// large, drawn in full detail, to set beside the original's own
/// (`fluffy-large.png`). Without the variable the test is skipped.
@MainActor
@Suite("Robot figure render", .serialized)
struct RobotFigureRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_ROBOT_PREVIEW"] != nil))
    func render() async throws {
        // Each figure's first frame builds its volume on the engine's queue,
        // tens of milliseconds apiece; build them all before drawing.
        for figure in RobotFigures.automatic {
            _ = await BotAvatarEngine.shared.frame(key: "render-warm", figure: figure, state: .idle, happy: false,
                                                   time: 0, now: 0, reducedMotion: false, size: 27, colour: "#ffffff")
        }
        BotAvatarEngine.shared.forget(key: "render-warm")
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_ROBOT_PREVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for material in RobotMaterial.allCases {
            let suffix = material == .flat ? "" : "-\(material.rawValue)"
            // Fluffy meshes are built as jobs of their own while the figures
            // already draw: give them time to come in.
            try await write(figures(material), to: folder.appendingPathComponent("figures\(suffix).png"),
                            settle: material == .flat ? 1.5 : 15)
            // The moods' figure is built first, so the cheer is still under
            // way when the page is taken.
            if material == .fluffy { await warm("mug") }
            try await write(moods(material), to: folder.appendingPathComponent("moods\(suffix).png"), settle: 1.5)
        }
        try await write(large, to: folder.appendingPathComponent("fluffy-large.png"), settle: 8)
    }

    private func warm(_ figure: String) async {
        for _ in 0..<200 {
            let frame = await BotAvatarEngine.shared.frame(
                key: "render-warm-fluffy", figure: figure, state: .idle, happy: false, time: 0, now: 0,
                reducedMotion: false, size: 27, colour: "#4285f4", material: .fluffy
            )
            if frame?.isFluffyPending != true { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        BotAvatarEngine.shared.forget(key: "render-warm-fluffy")
    }

    private func figures(_ material: RobotMaterial) -> some View {
        let inks = RobotAutomatic.inks(for: Array(repeating: Provider.codex, count: RobotFigures.automatic.count),
                                       custom: Array(repeating: nil, count: RobotFigures.automatic.count))
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<3) { row in
                HStack(spacing: DockLayout.itemSpacing) {
                    ForEach(Array(RobotFigures.automatic.enumerated()).filter { $0.offset / 8 == row }, id: \.offset) { index, figure in
                        cell(figure, mood: .idle, used: 0.3, ink: inks[index].ink, label: RobotFigures.title(figure),
                             material: material)
                    }
                }
            }
        }
    }

    private func moods(_ material: RobotMaterial) -> some View {
        let moods: [(RobotMood, RobotGesture?, String)] = [
            (.idle, nil, "idle"), (.working, nil, "working"), (.refreshing, nil, "refreshing"),
            (.spent, nil, "spent"), (.asleep, nil, "no reading"), (.idle, .cheer, "reset"), (.idle, .nod, "turn done"),
        ]
        let blue = RobotInk(rgb: 0x4285F4)
        return VStack(alignment: .leading, spacing: 18) {
            ForEach([false, true], id: \.self) { second in
                HStack(spacing: DockLayout.itemSpacing) {
                    ForEach(Array(moods.enumerated()), id: \.offset) { _, entry in
                        cell("mug", mood: entry.0, gesture: entry.1, used: entry.0 == .spent ? 1 : 0.45,
                             ink: blue, label: entry.2, second: second ? 0.7 : nil, material: material)
                    }
                }
            }
        }
    }

    /// Figures at 128pt, from which the original draws a coat in full, in a
    /// few of its studio's colours.
    private var large: some View {
        let entries: [(String, UInt32)] = [("cloud", 0x14B3A5), ("cat", 0xF8A01C), ("ghost", 0xF4F4F4),
                                           ("magnifier", 0x1F7CF2), ("bunny", 0xEC4899)]
        return HStack(spacing: 24) {
            ForEach(entries, id: \.0) { figure, rgb in
                RobotMarkView(mood: .idle, gesture: nil, size: 128, room: 150, isLive: false,
                              ink: RobotInk(rgb: rgb), inkIsChosen: true, figure: figure, material: .fluffy)
                    .frame(width: 150, height: 150)
            }
        }
    }

    private func cell(_ figure: String, mood: RobotMood, gesture: RobotGesture? = nil, used: Double,
                      ink: RobotInk, label: String, second: Double? = nil, material: RobotMaterial) -> some View {
        VStack(spacing: DockLayout.ringToTextSpacing) {
            UsageRingView(
                provider: .codex, usedFraction: mood == .asleep ? nil : used, hasReading: mood != .asleep,
                isSpent: mood == .spent,
                diameter: DockLayout.ringDiameter, lineWidth: DockLayout.ringLineWidth,
                isBusy: mood == .working, isRefreshing: mood == .refreshing,
                secondFraction: second, secondIsSpent: false,
                robot: RobotCue(justReset: gesture == .cheer, justFinished: gesture == .nod, ink: ink, figure: figure,
                                material: material)
            )
            Text(verbatim: label).font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize()
        }
        .frame(width: 64)
    }

    private func write<V: View>(_ view: V, to url: URL, settle: Double) async throws {
        let content = view
            .padding(24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.displayScale, 2)
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
        try await Task.sleep(for: .seconds(settle))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.contentView = nil
    }
}
