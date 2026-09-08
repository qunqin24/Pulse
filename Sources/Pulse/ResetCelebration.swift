import AppKit
import SwiftUI

/// Full-screen ribbons when a limit turns over, named for the provider.
///
/// Off until asked for (`AppSettings.celebratesReset`). Not a notification:
/// it never talks to `UNUserNotificationCenter`, so it works in a `swift run`
/// build and does not need a grant. One play at a time; a second account that
/// resets while this is up waits its turn.
@MainActor
final class ResetCelebration {
    static let shared = ResetCelebration()

    private var queue: [String] = []
    private var windows: [NSPanel] = []
    private var playTask: Task<Void, Never>?
    private var name = ""
    private var ribbons: [Ribbon] = []
    private var playing = false

    func play(name: String) {
        queue.append(name)
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard !playing, let next = queue.first else { return }
        queue.removeFirst()
        playing = true
        show(next)
    }

    private func show(_ name: String) {
        self.name = name
        ribbons = (0..<160).map(Ribbon.init(index:))
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            playing = false
            startNextIfIdle()
            return
        }

        windows = screens.map { screen in
            let panel = CelebrationPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.setFrame(screen.frame, display: false)
            let hosting = NSHostingView(rootView: ResetCelebrationView(name: name, elapsed: 0, ribbons: ribbons))
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            panel.contentView = hosting
            panel.orderFrontRegardless()
            return panel
        }

        playTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                self?.render(elapsed: elapsed)
                if elapsed >= Self.duration { break }
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            self?.finish()
        }
    }

    private static let duration: TimeInterval = 3.8

    private func render(elapsed: TimeInterval) {
        let view = ResetCelebrationView(name: name, elapsed: elapsed, ribbons: ribbons)
        for window in windows {
            (window.contentView as? NSHostingView<ResetCelebrationView>)?.rootView = view
        }
    }

    private func finish() {
        playTask = nil
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        playing = false
        startNextIfIdle()
    }
}

/// Click-through overlay. Pulse is an accessory; becoming key would steal
/// the session the user is in the middle of.
private final class CelebrationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct ResetCelebrationView: View {
    let name: String
    let elapsed: TimeInterval
    let ribbons: [Ribbon]

    var body: some View {
        ZStack {
            Color.black.opacity(scrim)
            Canvas { context, size in
                for ribbon in ribbons {
                    ribbon.draw(in: &context, size: size, elapsed: elapsed)
                }
            }
            VStack(spacing: 12) {
                Text(verbatim: name)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 2)
                Text(verbatim: String.localized("This limit has reset."))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 1)
            }
            .opacity(labelOpacity)
            .scaleEffect(labelScale)
        }
        .allowsHitTesting(false)
    }

    private var scrim: Double {
        0.22 * fade
    }

    private var fade: Double {
        if elapsed < 0.12 { return elapsed / 0.12 }
        if elapsed > 3.2 { return max(0, 1 - (elapsed - 3.2) / 0.6) }
        return 1
    }

    private var labelOpacity: Double { fade }

    private var labelScale: CGFloat {
        if elapsed < 0.22 {
            return 0.86 + 0.14 * CGFloat(elapsed / 0.22)
        }
        return 1
    }
}

/// One falling strip. Generated once per play so the rain does not reshuffle
/// every frame.
struct Ribbon {
    let xFrac: CGFloat
    let delay: TimeInterval
    let speed: CGFloat
    let length: CGFloat
    let thickness: CGFloat
    let hue: Double
    let spin: Double
    let sway: CGFloat
    let phase: Double

    init(index: Int) {
        let column = CGFloat(index % 24) / 23.0
        xFrac = column + .random(in: -0.04...0.04)
        delay = Double(index % 10) * 0.1 + .random(in: 0...0.35)
        speed = .random(in: 280...680)
        length = .random(in: 18...48)
        thickness = .random(in: 5...13)
        let hues = [0.00, 0.07, 0.12, 0.33, 0.46, 0.55, 0.63, 0.75, 0.83, 0.92]
        hue = hues[index % hues.count]
        spin = .random(in: -6.5...6.5)
        sway = .random(in: 16...86)
        phase = .random(in: 0...(2 * .pi))
    }

    func draw(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let local = elapsed - delay
        guard local > 0 else { return }
        let y = -length + CGFloat(local) * speed
        guard y < size.height + length else { return }
        let x = xFrac * size.width + sin(local * 2.5 + phase) * sway
        var localContext = context
        localContext.translateBy(x: x, y: y)
        localContext.rotate(by: .radians(local * spin))
        let rect = CGRect(x: -thickness / 2, y: -length / 2, width: thickness, height: length)
        let fade = min(1, local / 0.12)
        localContext.opacity = fade
        localContext.fill(
            Path(roundedRect: rect, cornerRadius: thickness / 2),
            with: .color(Color(hue: hue, saturation: 0.82, brightness: 0.98))
        )
    }
}

#Preview("Reset ribbons") {
    ResetRibbonPreview()
}

private struct ResetRibbonPreview: View {
    private let ribbons = (0..<160).map(Ribbon.init(index:))
    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { timeline in
            ResetCelebrationView(
                name: "Qoder",
                elapsed: timeline.date.timeIntervalSince(start),
                ribbons: ribbons
            )
        }
        .frame(width: 900, height: 560)
        .background(Color.gray.opacity(0.35))
    }
}
