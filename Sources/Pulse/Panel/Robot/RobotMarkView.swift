// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Drawing ported from Agent Robot Avatar
// (https://github.com/CX-ArtLab/agent-robot-avatar, v0.7.1),
// Copyright (c) 2026 CX ART Lab, MIT License — see THIRD_PARTY_NOTICES.md.
import SwiftUI

/// CX ArtLab's robot, drawn in a ring in place of the provider's mark.
///
/// The head is one colour with the eyes cut out, rather than the original's
/// black and white: the eyes then show whatever surface is behind, glass
/// included. With no colour of its own the head is the foreground style, so
/// it follows the panel the way the provider mark does — light on the dark
/// panel, dark on the light one.
struct RobotMarkView: View {
    let mood: RobotMood
    /// What just happened, played once as it becomes true.
    let gesture: RobotGesture?
    /// The robot's width; it is a little taller with its antenna.
    let size: CGFloat
    /// False while the rail is collapsed: the robot is invisible then, and
    /// nothing may animate for nobody.
    let isLive: Bool
    /// The head and antenna's colour, or nil for the foreground style.
    var ink: RobotInk?
    /// Drawn exactly as picked, rather than adjusted to stand out from the
    /// panel. See `RobotInk.legible(onDark:)`.
    var inkIsChosen = false
    var personality: RobotPersonality = .curious
    var shape: RobotShape = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var motion = RobotMotion()
    /// Set once the face can no longer move — asleep, settled — so the
    /// timeline stops until a fact changes.
    @State private var atRest = false

    /// The original runs at thirty frames a second, and so does this.
    private static let frameInterval: TimeInterval = 1 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !isLive || atRest)) { timeline in
            Canvas { context, canvasSize in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let frame = motion.frame(at: now, mood: mood, personality: personality,
                                         reduceMotion: reduceMotion)
                Self.draw(frame, shape: shape, ink: shading, in: &context, size: canvasSize)
            }
        }
        .frame(width: size, height: size * Self.aspect)
        .onChange(of: gesture) { _, new in
            if let new { motion.play(new, at: Date.timeIntervalSinceReferenceDate) }
            atRest = false
        }
        .onChange(of: mood) { atRest = false }
        // Asleep is the one mood that ends in stillness. Look again once its
        // sequence has had time to finish; until then the timeline runs.
        //
        // **A cancelled wait must not pause anything.** `try?` here once
        // swallowed the cancellation that a change of mood sends, so a robot
        // that woke within those four seconds — the usual case at launch, when
        // a reading arrives — was frozen asleep by the old mood's task.
        .task(id: mood) {
            guard mood == .asleep else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            if motion.isAtRest(at: Date.timeIntervalSinceReferenceDate) { atRest = true }
        }
        .onAppear {
            if let gesture { motion.play(gesture, at: Date.timeIntervalSinceReferenceDate) }
        }
        .accessibilityHidden(true)
    }

    private var shading: GraphicsContext.Shading {
        guard let ink else { return .foreground }
        return .color((inkIsChosen ? ink : ink.legible(onDark: colorScheme == .dark)).color)
    }

    /// Height over width of what is drawn.
    static let aspect = RobotFace.drawnBounds.height / RobotFace.drawnBounds.width

    private static func draw(_ frame: RobotFrame, shape: RobotShape, ink: GraphicsContext.Shading,
                             in context: inout GraphicsContext, size: CGSize) {
        let bounds = RobotFace.drawnBounds
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        context.translateBy(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                            y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
        context.scaleBy(x: scale, y: scale)

        context.fill(
            Path(ellipseIn: CGRect(x: frame.antenna.x - RobotFace.antennaRadius,
                                   y: frame.antenna.y - RobotFace.antennaRadius,
                                   width: RobotFace.antennaRadius * 2,
                                   height: RobotFace.antennaRadius * 2)),
            with: ink
        )

        context.drawLayer { head in
            head.translateBy(x: 120, y: 120)
            head.rotate(by: .degrees(frame.headTilt))
            head.translateBy(x: 0, y: frame.headDrop)
            head.scaleBy(x: frame.headScale, y: frame.headScale)
            head.translateBy(x: -120, y: -120)

            let outline = RobotFace.headPath(shape)
            head.fill(outline, with: ink)

            // The eyes are holes in the head, and only in the head.
            head.clip(to: outline)
            head.blendMode = .destinationOut
            for eye in [frame.left, frame.right] {
                head.drawLayer { layer in
                    drawEye(eye, in: &layer)
                }
            }
        }
    }

    /// One eye: the white, less whatever the lids cover.
    private static func drawEye(_ eye: RobotFrame.Eye, in context: inout GraphicsContext) {
        context.translateBy(x: eye.centre.x, y: eye.centre.y)
        context.scaleBy(x: eye.scale.width, y: eye.scale.height)
        context.fill(
            Path(ellipseIn: CGRect(x: -eye.radii.width, y: eye.lift - eye.radii.height,
                                   width: eye.radii.width * 2, height: eye.radii.height * 2)),
            with: .color(.white)
        )

        context.blendMode = .destinationOut
        context.clip(to: Path(RobotFace.lidMask))

        var top = context
        top.translateBy(x: 0, y: eye.topLid)
        top.rotate(by: .degrees(eye.tilt))
        top.fill(Path(CGRect(x: -70, y: -90, width: 140, height: 90)), with: .color(.white))

        context.fill(Path(CGRect(x: -70, y: eye.bottomLid, width: 140, height: 90)), with: .color(.white))
    }
}

#Preview("Robot moods") {
    HStack(spacing: 16) {
        ForEach([RobotMood.idle, .working, .refreshing, .spent, .asleep], id: \.self) { mood in
            RobotMarkView(mood: mood, gesture: nil, size: 48, isLive: true)
        }
    }
    .padding()
    .background(.black)
    .foregroundStyle(.white)
}
