// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Figures, motion and eyes by Open Bot Avatar
// (https://github.com/DominikScholz/open-bot-avatar, v0.4.0),
// Copyright (c) 2026 Dominik Scholz, MIT License — see THIRD_PARTY_NOTICES.md.
import SwiftUI

/// One of Open Bot Avatar's figures, drawn in a ring in place of the
/// provider's mark. The original's renderer decides every frame
/// (`BotAvatarEngine`); this view only asks for it and paints it.
///
/// `size` is the figure's 0 0 100 100 box. The figure hops, turns and sweeps
/// ribbons past that box, so it is painted into `room` — the whole inside of
/// the ring — and cut to that circle, as an overlay that takes no layout: the
/// ring around it is measured exactly as with a provider mark.
struct RobotMarkView: View {
    let mood: RobotMood
    /// What just happened, shown once as it becomes true.
    let gesture: RobotGesture?
    let size: CGFloat
    /// The circle the figure may be painted in, centred on it.
    var room: CGFloat? = nil
    /// False while the rail is collapsed: the figure is invisible then, and
    /// nothing may animate for nobody.
    let isLive: Bool
    /// The body's colour, or nil for the panel's foreground.
    var ink: RobotInk?
    /// Drawn exactly as picked, rather than adjusted to stand out from the
    /// panel. See `RobotInk.legible(onDark:)`.
    var inkIsChosen = false
    var figure: String = RobotFigures.automatic[0]
    /// Flat, or Open Bot Avatar's fur, drawn with Metal (`FluffyRenderer`).
    /// Where fur cannot be drawn the figure is drawn flat.
    var material: RobotMaterial = .flat
    /// Drawn until the figure's first frame arrives — a moment while the
    /// engine builds a figure it has not drawn before — and for good if the
    /// engine cannot run, so the ring is never left empty.
    var placeholder: AnyView = AnyView(EmptyView())
    /// Moves every figure's clock along by its own amount, so neighbouring
    /// figures do not breathe and blink in step. Seconds.
    var phase: TimeInterval = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// How much fur is drawn depends on the pixels it covers.
    @Environment(\.displayScale) private var displayScale
    /// The figure's animator inside the engine, one per drawing.
    @State private var key = UUID().uuidString
    @State private var shown: (gesture: RobotGesture, until: TimeInterval)?
    /// The last frame the engine returned. Nil until the first arrives, which
    /// for a figure not drawn before takes a moment (`BotAvatarEngine`).
    @State private var frame: BotAvatarFrame?

    /// Thirty frames a second while the figure is busy, fifteen for the calm
    /// states, whose motion is a slow breath.
    private func interval(at now: TimeInterval) -> TimeInterval {
        switch state(at: now) {
        case .working, .thinking, .done: 1 / 30
        case .idle, .waiting, .blocked: 1 / 15
        }
    }

    /// What restarts the frame loop when it changes. Everything the loop reads
    /// that is not read fresh on each pass.
    private struct Inputs: Equatable {
        var figure: String
        var mood: RobotMood
        var live: Bool
        var still: Bool
        var size: CGFloat
        var colour: String
        var material: RobotMaterial
        var displayScale: CGFloat
        var gestureEnds: TimeInterval?
    }

    var body: some View {
        let room = max(room ?? size, size)
        let colours = colours
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if frame == nil { placeholder }
            }
            .overlay {
                Canvas { context, canvas in
                    guard let frame else { return }
                    context.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: canvas)))
                    let box = CGRect(x: (canvas.width - size) / 2, y: (canvas.height - size) / 2,
                                     width: size, height: size)
                    frame.draw(in: &context, box: box, body: colours.body, eyes: colours.eyes)
                }
                .frame(width: room, height: room)
                .allowsHitTesting(false)
            }
            .task(id: Inputs(figure: figure, mood: mood, live: isLive, still: reduceMotion, size: size,
                             colour: colours.hex, material: material, displayScale: displayScale,
                             gestureEnds: shown?.until)) {
                await play(colour: colours.hex, eyes: colours.eyesHex)
            }
            .onChange(of: gesture, initial: true) { _, new in
                if let new { shown = (new, Date.timeIntervalSinceReferenceDate + new.duration) }
            }
            .onDisappear { BotAvatarEngine.shared.forget(key: key) }
            .accessibilityHidden(true)
    }

    /// Asks for frames until the view goes or what it shows changes. One
    /// frame and no more while collapsed or under Reduce Motion: the original
    /// holds still then too.
    private func play(colour: String, eyes: String) async {
        repeat {
            let now = Date.timeIntervalSinceReferenceDate
            let next = await BotAvatarEngine.shared.frame(
                key: key, figure: figure, state: state(at: now), happy: happy(at: now),
                time: ProcessInfo.processInfo.systemUptime + phase, now: now,
                reducedMotion: reduceMotion, size: size, colour: colour,
                material: material, eyes: eyes, pixelScale: displayScale
            )
            // A fluffy figure whose fur is still being built keeps what is
            // shown — the provider's mark at first — rather than flashing flat.
            if let next, !Task.isCancelled, !(next.isFluffyPending && frame == nil) {
                frame = next
            }
            if next?.isFluffyPending == true {
                try? await Task.sleep(for: .seconds(0.1))
                continue
            }
            if !isLive || reduceMotion {
                // A still frame of a cheer or a nod has to give way to the
                // mood's own once the gesture is over, or it stays.
                guard let until = shown?.until, until > now else { return }
                try? await Task.sleep(for: .seconds(until - now + 0.05))
                continue
            }
            try? await Task.sleep(for: .seconds(interval(at: now)))
        } while !Task.isCancelled
    }

    /// The state at a moment: a cheer while it lasts, otherwise the mood's.
    private func state(at now: TimeInterval) -> BotAvatarEngine.State {
        if let shown, shown.gesture == .cheer, now < shown.until { return .done }
        return mood.state
    }

    /// Happy for a moment after a finished turn or a reset.
    private func happy(at now: TimeInterval) -> Bool {
        guard let shown else { return false }
        return now < shown.until
    }

    /// The body in the robot's colour, legible on this panel; the eyes in
    /// near-black, or near-white on a body too dark for them.
    private var colours: (body: Color, eyes: Color, hex: String, eyesHex: String) {
        let ink = ink.map { inkIsChosen ? $0 : $0.legible(onDark: colorScheme == .dark) }
            ?? (colorScheme == .dark ? RobotInk(red: 0.92, green: 0.92, blue: 0.92) : RobotInk(red: 0.15, green: 0.15, blue: 0.15))
        let eyes = ink.luminance < 0.18 ? RobotInk(red: 0.94, green: 0.94, blue: 0.94) : RobotInk(rgb: 0x151515)
        return (ink.color, eyes.color, ink.hexString, eyes.hexString)
    }
}

#Preview("Figures") {
    HStack(spacing: 16) {
        ForEach(Array([RobotMood.idle, .working, .refreshing, .spent, .asleep].enumerated()), id: \.offset) { index, mood in
            RobotMarkView(mood: mood, gesture: nil, size: 40, room: 52, isLive: true,
                          ink: RobotInk(red: 0.26, green: 0.52, blue: 0.96), figure: RobotFigures.automatic[index])
        }
    }
    .padding()
    .background(.black)
}
