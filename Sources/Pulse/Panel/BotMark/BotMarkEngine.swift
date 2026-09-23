import CoreGraphics
import Foundation
import SwiftUI

/// The animation engine, ported from the upstream `grok-bot-engine.js`,
/// `physics-system.js` and `state-behavior-system.js`.
///
/// Same springs at the same frequencies, same per-state motion formulas, same
/// blink queue and expression pools, same gestures. Time is kept in
/// milliseconds because the upstream formulas are written in milliseconds;
/// `delta` is in seconds for the same reason.
final class BotMarkEngine {
    private let library = BotMarkLibrary.shared
    private var headCentre: Double { library.headCentre }

    // MARK: State

    private(set) var state = "idle"
    var stateStartedAt = 0.0
    private var clockTime = 0.0
    private var lastTimestamp: Double?
    private var delta = 1.0 / 60

    // MARK: Expression

    private var expressionFrom: [[CGPoint]]
    private var expressionTo: [[CGPoint]]
    // Readable by the choreography test: short beats must not freeze the eye
    // pool at its first entry forever. Mutation remains inside the engine.
    private(set) var expressionIndex = 0
    private var expressionSpring = BotMarkSpring(1)
    private var expressionFrequency = 7.0
    private var expressionCursor = 0
    private var expressionNext = 0.0

    // MARK: Springs

    private var rotation = BotMarkSpring(0)
    /// Which way the gaze is aimed: +1 as the engine works, -1 turned round.
    /// A spring rather than the boolean it comes from, so dragging the rail
    /// to the other edge sends the eyes across instead of teleporting them.
    ///
    /// Nil until the first frame, and set to the target outright there: a
    /// mark that appears on a right-hand rail has not looked anywhere, and
    /// animating it would have every ring swing its eyes on launch.
    private var facing: BotMarkSpring?
    private var headX = BotMarkSpring(0)
    private var headY = BotMarkSpring(0)
    private var scaleY = BotMarkSpring(1)
    private var eyeOpen = BotMarkSpring(1)
    private var eyeScale = BotMarkSpring(1)
    private var aimX = BotMarkSpring(0)
    private var aimY = BotMarkSpring(0)
    var morph = BotMarkSpring(0)
    var morphBlend = BotMarkSpring(1)
    private var shapeBlend = BotMarkSpring(1)
    var turn = BotMarkSpring(0)
    private var notify = BotMarkSpring(0)
    private var humming = BotMarkSpring(0)
    private var spinSpring: BotMarkSpring?

    // MARK: Timers and one-shots

    private var blinkNext = 0.0
    private var gazeNext = 0.0
    private var blinkQueue: [(at: Double, value: Double)] = []
    private var blinkTarget: Double?
    private var wakeBurst = false
    private var drowsyStartedAt = 0.0
    private var listenNodUntil = 0.0
    private var listenNodNext = 0.0
    private var impulseNext = 0.0
    private var impulseUntil = 0.0
    private var behaviorNext = 0.0
    private var winkAt = -Double.infinity
    private var winkEye = 0
    private var winkNext = 0.0
    private var dragCycle = -1
    private var notifyTriggered = false
    private var spinAngle = 0.0

    // MARK: Gestures

    private struct Gesture {
        var kind: String
        var startedAt: Double
        var direction: Double
        var turns: Double
    }

    // MARK: Morphs
    //
    // Internal rather than private: the morph port lives in BotMorphs.swift,
    // and `private` in Swift is file-scoped.

    var requestedMorphEffect: String?
    var morphEffect: String?
    var previousMorphEffect: String?
    var morphVisible = false
    var morphStartedAt = 0.0
    var morphShotStartedAt = 0.0
    var morphRestStartedAt = 0.0
    var oneShotResting = false
    var receiveCycle = -1
    var receiveAngle = -0.7
    /// The line the pencil morph has drawn so far.
    var writingTrail: [CGPoint] = []

    /// The orbiting ribbons and the confetti.
    let particles = BotMarkParticles()

    // MARK: Programme

    private var playlist: [String] = []
    private var playlistOrder: BotMarkProgramme.Order = .random
    private var playlistCursor = 0
    private var playlistNext = 0.0
    private var playedMood: BotMarkMood?
    private var playedEvent: BotMarkEvent?
    private var eventUntil = 0.0
    private var particleSpinAngle = 0.0
    /// Returning to a short pose should not always select the first pair of
    /// eyes and leave the rest of its expression pool permanently unused.
    private var expressionEntries: [String: Int] = [:]

    /// The unit circle the head blends into for every morph but the pencil.
    let circlePath: CGPath
    /// The pencil morph's head: the teardrop, turned upside down.
    let pencilRing: [CGPoint]
    let pencilGlyph: CGPath
    let alertGlyph: CGPath

    private var gesture: Gesture?
    private var bounceStartedAt = -1.0
    private var ambientNext = 0.0
    private var celebrateCycle = -1
    private(set) var celebrateWildActive = false
    var turnDirection = 1.0

    private var directTurn = 0.0
    private var directRotation = 0.0
    /// What was last drawn, and in which state — so a change of state is
    /// caught up with rather than jumped to. See `render`.
    private var drawn: (x: Double, y: Double, degrees: Double, turn: Double)?
    private var drawnState = ""
    /// What is left of the difference between the last frame of one state and
    /// the first of the next, eased away over about a third of a second.
    private var carryX = BotMarkSpring(0)
    private var carryY = BotMarkSpring(0)
    private var carryDegrees = BotMarkSpring(0)
    private var carryTurn = BotMarkSpring(0)
    private var directX = 0.0
    private var directY = 0.0
    private var directGazeX = 0.0
    private var directGazeY = 0.0

    // MARK: Shape blending

    private var shapeId = "blob"
    private var shapeFromRing: [CGPoint]
    private var shapeFromFace: BotMarkFace
    private var shapeFromTiltScale: Double
    private var shapeFromBeltRadius: Double
    private var shapeChangeCycle = 0
    private var shapeChangeWide = false
    private(set) var currentBeltRadius: Double

    // MARK: Pointer

    /// How open the eyes are right now.
    var eyelid: Double { eyeOpen.value }

    /// Whether a blink is in flight.
    ///
    /// **This, and not `eyelid`, is what a still frame has to wait out.** A
    /// state's resting eyelid is not 1: `drowsy` sits at 0.34 and never blinks
    /// at all, `bored` at 0.6, `sad` at 0.7. Waiting for the eyelid to pass
    /// 0.92 therefore never finishes for those states — and where it does
    /// finish, it finishes on the 1.08 overshoot at the *top* of a blink,
    /// which is precisely the frame it was meant to avoid.
    var isBlinking: Bool { !blinkQueue.isEmpty || blinkTarget != nil }

    /// Where the pointer is, as a fraction of the view from its centre. Nil
    /// is "not pointed at".
    var pointer: CGPoint?
    private var pointerX = 0.0
    private var pointerY = 0.0
    private var pointerTargetX = 0.0
    private var pointerTargetY = 0.0

    init() {
        let blob = library.shape("blob")
        let centre = library.headCentre
        circlePath = BotMarkGeometry.ringOutline(library.circleRing)
        let teardrop = library.shape("teardrop").ring
        let half = teardrop.count / 2
        pencilRing = (0..<teardrop.count).map { index in
            // Upstream shifts the ring half a turn and rotates the points by
            // the same angle, which lands the point at the bottom.
            let point = teardrop[((index - half) % teardrop.count + teardrop.count) % teardrop.count]
            return CGPoint(x: centre - (point.x - centre), y: centre - (point.y - centre))
        }
        pencilGlyph = CGPath(roundedRect: CGRect(x: centre - 15, y: centre - 44, width: 30, height: 88),
                             cornerWidth: 15, cornerHeight: 15, transform: nil)
        let alert = CGMutablePath()
        alert.move(to: CGPoint(x: centre - 15, y: centre - 33))
        alert.addArc(center: CGPoint(x: centre, y: centre - 33), radius: 15,
                     startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        alert.addLine(to: CGPoint(x: centre + 8.5, y: centre + 39.5))
        alert.addArc(center: CGPoint(x: centre, y: centre + 39.5), radius: 8.5,
                     startAngle: 0, endAngle: .pi, clockwise: false)
        alert.closeSubpath()
        alertGlyph = alert
        expressionFrom = library.expressions[0]
        expressionTo = library.expressions[0]
        shapeFromRing = blob.ring
        shapeFromFace = blob.face
        shapeFromTiltScale = blob.tiltScale
        shapeFromBeltRadius = blob.beltRadius
        currentBeltRadius = blob.beltRadius
        shapeChangeCycle = Int(BotMath.random(0, 5))
        winkNext = BotMath.random(3000, 8000)
        ambientNext = BotMath.random(2500, 5000)
        setState("idle", immediate: true, config: BotMarkConfig())
    }

    // MARK: - Frame

    /// Advances to a wall-clock timestamp in seconds and returns the frame to
    /// draw, taking the next state of the programme when one is due.
    ///
    /// The playlist is stepped here rather than by the caller because this is
    /// what holds the clock — and because every change of state rebuilds the
    /// per-state table, which a view redrawing at 30fps has no way to time.
    func advance(to timestamp: Double, programme: BotMarkProgramme) -> BotMarkFrame {
        let previous = lastTimestamp ?? timestamp
        lastTimestamp = timestamp
        // The upstream clamps a frame to 100ms, so a tab that was away wakes
        // up where it is instead of replaying the gap.
        delta = BotMath.clamp(timestamp - previous, 0, 0.1)
        clockTime += delta * 1000

        pointer = programme.pointer
        let config = step(programme: programme)
        aimFacing(at: config.flipX ? -1 : 1)
        updateMorph(now: clockTime, config: config)
        updateStateTargets(now: clockTime, config: config)
        stepPhysics(delta: delta)
        var frame = render(now: clockTime, config: config)

        if let spin = spinSpring,
           abs(spin.target - spin.value) < 0.004, abs(spin.velocity) < 0.015 {
            spinSpring = nil
            shapeChangeWide = false
        }

        // Whatever is turning the character is what the particles ride: a
        // spin, a gesture's own turn, or the humming/loading wheel.
        if let spin = spinSpring {
            particleSpinAngle = spin.value
        } else if abs(directTurn) > 0.001 {
            particleSpinAngle = directTurn
        } else if state == "humming" || state == "loading" {
            particleSpinAngle = spinAngle
        }
        // Particles are sized against the canvas, so a 16pt bot does not get
        // invisible ones.
        let sizeScale = BotMath.clamp(pow(340 / max(config.viewWidth, 1), 0.7), 1, 2.6)
        particles.update(now: clockTime, delta: delta, spinAngle: particleSpinAngle,
                         sizeScale: sizeScale,
                         wideStyle: state == "humming" || celebrateWildActive || shapeChangeWide,
                         enabled: config.particlesEnabled,
                         beltRadius: currentBeltRadius)
        frame.backParticles = particles.back
        frame.frontParticles = particles.front
        return frame
    }

    /// Picks what should be playing this frame and returns its config.
    ///
    /// Three things can move it: an event, which interrupts everything for its
    /// own duration; a change of mood, which starts the new playlist at once;
    /// and the hold timer, which takes the next state of a playlist that has
    /// more than one.
    private func step(programme: BotMarkProgramme) -> BotMarkConfig {
        // An event that has already been played is not replayed: the caller
        // reports "a limit reset in the last few seconds" for as long as that
        // is true, which is many frames.
        if let event = programme.event, event != playedEvent {
            playedEvent = event
            eventUntil = clockTime + event.duration
            playlist = []
            let eventState = programme.state(for: event)
            let config = programme.configuration(for: eventState, isEvent: true)
            setState(eventState, config: config)
            return config
        }
        if programme.event == nil { playedEvent = nil }
        if clockTime < eventUntil {
            // Mid-event: hold it, and keep its own table.
            return programme.configuration(for: state, isEvent: true)
        }

        let due = clockTime >= playlistNext
        if playlist != programme.states || programme.mood != playedMood || playlistOrder != programme.order {
            playlist = programme.states
            playlistOrder = programme.order
            playedMood = programme.mood
            // Authored scenes enter at the signature pose. Raw random
            // playlists may enter elsewhere, but idle always starts awake.
            playlistCursor = programme.order == .random && programme.mood != .idle && programme.states.count > 1
                ? Int(BotMath.random(0, Double(programme.states.count)))
                : 0
        } else if due, programme.states.count > 1 {
            // Authored scenes visit every beat. Random callers still choose
            // a different state, never an immediate repeat.
            let step = programme.order == .sequence
                ? 1 : 1 + Int(BotMath.random(0, Double(programme.states.count - 1)))
            playlistCursor = (playlistCursor + step) % programme.states.count
        } else if !due {
            return programme.configuration(for: state)
        }

        let next = programme.states[min(playlistCursor, programme.states.count - 1)]
        let hold = programme.holdDuration(for: next)
        playlistNext = clockTime + BotMath.random(hold.lowerBound, hold.upperBound)
        let config = programme.configuration(for: next)
        setState(next, config: config)
        return config
    }

    func setState(_ identifier: String, config: BotMarkConfig) {
        guard identifier != state else { return }
        setState(identifier, immediate: true, config: config)
    }

    private func setState(_ identifier: String, immediate: Bool, config: BotMarkConfig) {
        let now = clockTime
        state = identifier
        stateStartedAt = now
        let pool = config.expressionPool
        expressionCursor = pool.isEmpty ? 0 : (expressionEntries[identifier] ?? 0) % pool.count
        if !pool.isEmpty { expressionEntries[identifier] = (expressionCursor + 1) % pool.count }
        expressionNext = now + BotMath.random(config.expressionCadence.0, config.expressionCadence.1) * config.tempo
        blinkNext = now + BotMath.random(1500, 7000)
        gazeNext = now + BotMath.random(500, 1400)
        listenNodNext = now + BotMath.random(1200, 2200)
        impulseNext = now + BotMath.random(500, 1200)
        behaviorNext = now + (identifier == "excited" ? BotMath.random(400, 1100)
                              : identifier == "searching" ? BotMath.random(800, 1600)
                               : identifier == "working" ? BotMath.random(1200, 2400)
                               : identifier == "playful" ? BotMath.random(1200, 2400)
                              : BotMath.random(6000, 10000))
        winkNext = now + BotMath.random(3000, 8000)
        blinkQueue = []
        blinkTarget = nil
        wakeBurst = false
        drowsyStartedAt = 0
        dragCycle = -1
        notifyTriggered = false
        celebrateWildActive = false
        if identifier == "celebrate" {
            turnDirection = Double.random(in: 0...1) < 0.5 ? 1 : -1
            celebrateCycle = -1
        }
        let firstExpression = pool.isEmpty ? 0 : pool[expressionCursor]
        if identifier != "waking" && identifier != "sleeping" {
            if identifier != "drowsy" { scheduleBlink(now) }
            setExpression(firstExpression, frequency: identifier == "excited" ? 10 : 8)
        }
    }

    private func setExpression(_ index: Int, frequency: Double = 7) {
        guard index != expressionIndex || expressionSpring.target != 1 else { return }
        let amount = BotMath.clamp(expressionSpring.value, 0, 1)
        expressionFrom = [
            BotMarkGeometry.lerpRing(expressionFrom[0], expressionTo[0], amount),
            BotMarkGeometry.lerpRing(expressionFrom[1], expressionTo[1], amount),
        ]
        expressionTo = library.expressions[index]
        expressionIndex = index
        expressionSpring.value = 0
        expressionSpring.velocity = 0
        expressionSpring.target = 1
        expressionFrequency = frequency
    }

    /// Close, hold, overshoot open, settle — and one blink in seven is a
    /// double.
    private func scheduleBlink(_ now: Double) {
        blinkTarget = eyeOpen.target
        blinkQueue.append(contentsOf: [
            (now, 0.05), (now + 70, 0.05), (now + 150, 1.08), (now + 300, 1),
        ])
        if Double.random(in: 0...1) < 0.14 {
            blinkQueue.append(contentsOf: [(now + 370, 0.05), (now + 480, 1)])
        }
    }

    /// Point the mark the way the rail wants it.
    ///
    /// The first frame snaps, every later one springs: see `facing`.
    private func aimFacing(at target: Double) {
        if facing == nil {
            facing = BotMarkSpring(target)
        } else {
            facing?.target = target
        }
    }

    /// Which way the gaze is aimed: +1 as the engine works, -1 turned round,
    /// and everything between while it is moving. Zero is simply a mark
    /// looking straight ahead, which is what it passes through.
    private var facingValue: Double { facing?.value ?? 1 }

    private func stepPhysics(delta: Double) {
        let steps = max(1, Int((delta / BotMath.fixedStep).rounded(.up)))
        let step = delta / Double(steps)
        for _ in 0..<steps {
            expressionSpring.step(frequency: expressionFrequency, damping: 1, delta: step)
            rotation.step(frequency: 5, damping: 0.9, delta: step)
            // Slower than the gaze spring it scales (13), so a change of
            // edge reads as the mark deciding to look the other way rather
            // than as another glance. About a third of a second, slightly
            // under-damped, so the eyes arrive with a small settle.
            facing?.step(frequency: 9, damping: 0.85, delta: step)
            headX.step(frequency: 3.5, damping: 1, delta: step)
            headY.step(frequency: 4, damping: 1, delta: step)
            scaleY.step(frequency: 10, damping: 0.8, delta: step)
            eyeOpen.step(frequency: 26, damping: 1, delta: step)
            eyeScale.step(frequency: 9, damping: 0.85, delta: step)
            aimX.step(frequency: 13, damping: 1, delta: step)
            aimY.step(frequency: 13, damping: 1, delta: step)
            morph.step(frequency: 14, damping: 1, delta: step)
            morphBlend.step(frequency: 11, damping: 1, delta: step)
            shapeBlend.step(frequency: 10, damping: 1, delta: step)
            turn.step(frequency: 14, damping: 1, delta: step)
            notify.step(frequency: 9, damping: 0.55, delta: step)
            humming.step(frequency: 6, damping: 1, delta: step)
            if spinSpring != nil { spinSpring!.step(frequency: 6.2, damping: 1, delta: step) }
            carryX.step(frequency: 12, damping: 1, delta: step)
            carryY.step(frequency: 12, damping: 1, delta: step)
            carryDegrees.step(frequency: 12, damping: 1, delta: step)
            carryTurn.step(frequency: 12, damping: 1, delta: step)
        }
    }

    // MARK: - Per-state motion

    private struct GesturePose {
        var turn = 0.0
        var rotation = 0.0
        var x = 0.0
        var y = 0.0
        var bounceY = 0.0
        var gazeX = 0.0
        var gazeY = 0.0
        var eyeOpen: Double?
        var eyeScale: Double?
    }

    private func updateStateTargets(now: Double, config: BotMarkConfig) {
        let elapsed = (now - stateStartedAt) / 1000
        let runtime = now / 1000
        let motion = config.motionScale
        var eyeOpenTarget = 1.0
        var eyeScaleTarget = 1.0
        var rotationTarget = 0.0
        var x = 0.0
        var y = 0.0
        var scaleYTarget = 1.0
        var gesture = updateGestures(now: now)

        switch state {
        case "sleeping":
            if config.expressionPool.contains(expressionIndex) {
                eyeOpenTarget = expressionSpring.value > 0.85 ? 1 : 0.08
            } else if elapsed < 1.2 {
                eyeOpenTarget = max(0.08, 1 - min(1, elapsed) * (1 + 0.15 * sin(6.5 * elapsed)))
            } else {
                eyeOpenTarget = 0.08
                if eyeOpen.value < 0.18 { setExpression(13, frequency: 11) }
            }
            let settle = min(elapsed / 2, 1)
            let dip = sin(BotMath.clamp(elapsed / 0.5, 0, 1) * .pi)
            rotationTarget = 4 * settle + 2 * sin(0.25 * runtime)
            x = -2 * settle
            y = 8 * settle + 3 * sin(0.55 * runtime) - 5 * dip
            scaleYTarget = 1 + 0.016 * sin(0.55 * runtime) + 0.05 * dip
        case "waking":
            if elapsed < 0.5 {
                eyeOpenTarget = 0.07
                setExpression(3, frequency: 12)
                y = 6
            } else if elapsed < 1.2 {
                eyeOpenTarget = 1
                eyeScaleTarget = 1.12
                y = -5
                scaleYTarget = 1.04
                if !wakeBurst {
                    particles.burst(count: Int(BotMath.random(9, 13).rounded()), force: 0.8)
                    wakeBurst = true
                }
            } else if elapsed < 2.2 {
                if blinkQueue.isEmpty && elapsed < 1.4 { scheduleBlink(now) }
                setExpression(0)
            } else {
                let settle = min((elapsed - 2.2) / 0.8, 1)
                rotationTarget = 6 * sin(settle * .pi * 3) * (1 - settle)
                y = 2 * sin(0.9 * runtime)
            }
        case "idle":
            rotationTarget = 1.5 * sin(0.5 * runtime) + 0.6 * sin(0.17 * runtime)
            x = sin(0.27 * runtime)
            y = 1.2 * sin(0.85 * runtime)
            scaleYTarget = 1 + 0.007 * sin(0.85 * runtime)
        case "listening":
            rotationTarget = 8 + 1.5 * sin(0.5 * runtime)
            x = 2
            y = -2 + 0.8 * sin(0.8 * runtime)
            scaleYTarget = 1.015
            if now >= listenNodNext {
                listenNodUntil = now + 380
                listenNodNext = now + BotMath.random(1800, 3200)
            }
            if now < listenNodUntil {
                let phase = 1 - (listenNodUntil - now) / 380
                y += 4.5 * sin(phase * .pi)
                rotationTarget += 2 * sin(phase * .pi)
            }
        case "thinking":
            rotationTarget = -9 + 5 * sin(0.35 * runtime)
            x = 5 * sin(0.3 * runtime)
            y = 2.5 * sin(0.6 * runtime)
        case "searching":
            let wave = sin(1.3 * runtime)
            rotationTarget = 13 * wave
            x = 7 * wave
            y = 3 * sin(1.7 * runtime)
        case "working":
            let wave = sin(runtime * .pi * 3.2)
            rotationTarget = 4 + 2.5 * wave
            x = 3
            y = 1.5 + 3 * max(0, wave)
            scaleYTarget = 1 - 0.02 * max(0, wave)
        case "excited":
            let phase = (2.2 * runtime).truncatingRemainder(dividingBy: 1)
            y = -10 * sin(phase * .pi) + 2
            scaleYTarget = phase < 0.1 ? 0.92 : phase < 0.3 ? 1.05 : 1
            x = 4 * sin(1.1 * runtime)
            eyeScaleTarget = 1.06
            rotationTarget = 7 * sin(runtime * .pi * 2.2)
        case "surprised":
            let settle = min(elapsed / 1.2, 1)
            x = -4 * (1 - settle)
            y = -8 * (1 - settle)
            scaleYTarget = elapsed < 0.2 ? 1.08 : 1
            eyeScaleTarget = 1.15 - 0.08 * settle
            rotationTarget = 1.5 * sin(11 * runtime) * (1 - settle)
        case "suspicious":
            rotationTarget = -6 + 3 * sin(0.3 * runtime)
            x = -4 * sin(0.25 * runtime)
            y = 1 + 1.2 * sin(0.45 * runtime)
            eyeOpenTarget = 0.85
            if now >= impulseNext {
                rotation.velocity += 30 * .pi / 180
                impulseNext = now + BotMath.random(4000, 7000)
            }
        case "angry":
            if now >= impulseNext {
                impulseUntil = now + 420
                headY.velocity += 70
                impulseNext = now + BotMath.random(1800, 3200)
            }
            rotationTarget = now < impulseUntil ? 4.5 * sin(0.05 * now) : 0
            y = 3.5
            scaleYTarget = 0.975
        case "drowsy":
            rotationTarget = 2.5 * sin(0.32 * runtime)
            x = 1.5 * sin(0.2 * runtime)
            y = 6 + 2.2 * sin(0.36 * runtime)
            scaleYTarget = 1 + 0.022 * sin(0.36 * runtime)
            eyeOpenTarget = 0.34 + 0.07 * sin(0.8 * runtime)
            if now >= listenNodNext && drowsyStartedAt == 0 { drowsyStartedAt = now }
            if drowsyStartedAt != 0 {
                let phase = (now - drowsyStartedAt) / 1000
                if phase < 1.7 {
                    let progress = phase / 1.7
                    let squared = progress * progress
                    y = 6 + 19 * squared + 2.2 * sin(progress * .pi * 2.5) * (1 - progress)
                    rotationTarget = 10 * squared
                    eyeOpenTarget = 0.34 - squared * 0.3
                    scaleYTarget = 1 - 0.045 * squared
                } else if phase < 2 {
                    let rebound = sin((phase - 1.7) / 0.3 * .pi)
                    y = 25 - 7 * rebound
                    rotationTarget = 10 - 4 * rebound
                    eyeOpenTarget = 0.04 + 0.42 * rebound
                } else if phase < 3.5 {
                    let progress = (phase - 2) / 1.5
                    let recovery = 1 - pow(1 - progress, 2.2)
                    y = 25 - 19 * recovery
                    rotationTarget = 10 * (1 - recovery)
                    eyeOpenTarget = 0.46 - 0.12 * recovery
                    if progress > 0.32 && progress < 0.46 { eyeOpenTarget = 0.05 }
                } else {
                    drowsyStartedAt = 0
                    listenNodNext = now + BotMath.random(1500, 3500)
                }
            }
        case "happy":
            let wave = sin(2.4 * runtime)
            rotationTarget = 3 * sin(1.2 * runtime)
            x = 2.5 * sin(1.1 * runtime)
            y = -3 * abs(wave)
            scaleYTarget = 1 + 0.02 * wave
            eyeScaleTarget = 1.05
        case "curious":
            rotationTarget = 10 + 6 * sin(0.7 * runtime)
            x = 5 * sin(0.6 * runtime)
            y = -2 + 1.5 * sin(0.9 * runtime)
            scaleYTarget = 1.01
            eyeScaleTarget = 1.08
            if now >= listenNodNext {
                listenNodUntil = now + 440
                listenNodNext = now + BotMath.random(1600, 2800)
            }
            if now < listenNodUntil {
                let phase = 1 - (listenNodUntil - now) / 440
                x += 8 * sin(phase * .pi)
                rotationTarget += 5 * sin(phase * .pi)
            }
        case "confused":
            let wave = sin(0.8 * runtime)
            rotationTarget = 12 * wave
            x = 3 * wave
            y = 2 * sin(0.5 * runtime)
            eyeOpenTarget = 0.9
            if now >= impulseNext {
                rotation.velocity += 22 * .pi / 180
                impulseNext = now + BotMath.random(2600, 4200)
            }
        case "bored":
            rotationTarget = -3 + 4 * sin(0.25 * runtime)
            x = 4 * sin(0.2 * runtime)
            y = 5 + 1.5 * sin(0.35 * runtime)
            scaleYTarget = 0.99
            eyeOpenTarget = 0.6
            eyeScaleTarget = 0.98
            if now >= impulseNext {
                impulseUntil = now + 600
                impulseNext = now + BotMath.random(4000, 7000)
            }
            if now < impulseUntil {
                let phase = 1 - (impulseUntil - now) / 600
                scaleYTarget = 1 + 0.05 * sin(phase * .pi)
                y += 3 * sin(phase * .pi)
            }
        case "proud":
            rotationTarget = 2.5 * sin(0.4 * runtime)
            x = 2 * sin(0.35 * runtime)
            y = -4 + sin(0.6 * runtime)
            scaleYTarget = 1.03
            eyeScaleTarget = 1.02
            eyeOpenTarget = 0.9
        case "shy":
            rotationTarget = -8 + 3 * sin(0.5 * runtime)
            x = -3 + 2 * sin(0.4 * runtime)
            y = 3
            scaleYTarget = 0.98
            eyeScaleTarget = 0.95
            eyeOpenTarget = 0.85
        case "sad":
            rotationTarget = 3 + 2 * sin(0.3 * runtime)
            x = 1.5 * sin(0.25 * runtime)
            y = 7 + sin(0.4 * runtime)
            scaleYTarget = 0.97
            eyeScaleTarget = 0.97
            eyeOpenTarget = 0.7
        case "laughing":
            let wave = sin(runtime * .pi * 6.4)
            rotationTarget = 4 * wave
            x = 2 * sin(2 * runtime)
            y = -5 * abs(wave)
            scaleYTarget = 1 + 0.03 * wave
            eyeOpenTarget = 0.7
        case "scared":
            rotationTarget = 2 * sin(0.04 * now)
            x = -2 + 1.5 * sin(0.05 * now)
            y = 2 + sin(1.5 * runtime)
            scaleYTarget = 0.97
            eyeScaleTarget = 1.12
            eyeOpenTarget = 1.05
        case "playful":
            rotationTarget = 8 * sin(1.4 * runtime)
            x = 4 * sin(1.1 * runtime)
            y = -3 * abs(sin(2.2 * runtime))
            scaleYTarget = 1 + 0.015 * sin(2.2 * runtime)
            eyeScaleTarget = 1.06
        case "celebrate":
            y = -2.5 * abs(sin(1.6 * runtime))
            eyeScaleTarget = 1.1
            eyeOpenTarget = 1.1
            gesture = celebratePose(elapsed: elapsed)
        case "dragging":
            let phase = elapsed.truncatingRemainder(dividingBy: 3.4) / 3.4
            let cycle = Int(elapsed / 3.4)
            if phase < 0.12 {
                x = -16
                y = -22
                rotationTarget = -5
            } else if phase < 0.62 {
                x = -16 + 32 * BotMath.cubicInOut((phase - 0.12) / 0.5)
                y = -22 + 2 * sin(1.4 * runtime)
                rotationTarget = 6 * sin(2.6 * runtime)
                eyeScaleTarget = 1.06
            } else {
                if cycle != dragCycle {
                    dragCycle = cycle
                    headY.velocity += 90
                }
                x = 16
            }
        case "humming":
            rotationTarget = 2 * sin(0.4 * runtime)
            x = 1.5 * sin(0.3 * runtime)
            y = 1.5 * sin(0.7 * runtime)
        case "notifying":
            if !notifyTriggered && elapsed > 0.12 {
                notifyTriggered = true
                headY.velocity -= 26
                scheduleBlink(now)
            }
            eyeScaleTarget = 1 + 0.05 * exp(-3 * elapsed)
            rotationTarget = 3
            x = 2
            y = -1
        default:
            break
        }

        let blinkOverride = updateExpressionAndBlink(now: now, config: config)
        updateAim(now: now, config: config)

        if let value = gesture.eyeOpen { eyeOpenTarget = value }
        if let value = gesture.eyeScale { eyeScaleTarget = value }
        directTurn = gesture.turn
        directRotation = gesture.rotation
        directX = gesture.x
        directY = gesture.y + gesture.bounceY
        directGazeX = gesture.gazeX
        directGazeY = gesture.gazeY

        rotation.target = (rotationTarget * motion * config.rotationScale
                           + config.headRotation) * .pi / 180
        headX.target = x * motion + config.headX
        headY.target = y * motion + config.headY
        // The deviation from a resting body is what gets exaggerated, so a
        // state that does not squash at all still does not.
        //
        // **And it is bounded.** The exaggeration multiplies whatever the
        // state already does, and the states differ by an order of magnitude:
        // `working` squashes 2%, where `excited` squashes 8% and stretches 5%.
        // Unbounded, the same multiplier that makes working visible collapsed
        // an excited body to a fifth of its height and stretched it to half
        // again — read as the mark resizing itself rather than as motion.
        let squashed = 1 + (scaleYTarget - 1) * config.squashScale
        scaleY.target = BotMath.clamp(squashed, 0.9, 1.12) * config.scaleY
        eyeOpen.target = (blinkOverride ?? eyeOpenTarget) * config.eyeOpen
        eyeScale.target = eyeScaleTarget * config.eyeScale
        notify.target = state == "notifying" ? 1 : 0
        humming.target = state == "humming" ? 1 : 0

        if state == "humming" || state == "loading" {
            let settled = state == "loading" ? 3.0 : 1.6
            let speed = elapsed < 0.5
                ? 7 * BotMath.cubicInOut(elapsed / 0.5)
                : elapsed < 1.3
                    ? 7 + (settled - 7) * BotMath.cubicInOut((elapsed - 0.5) / 0.8)
                    : settled + 0.3 * sin(0.5 * elapsed)
            spinAngle += speed * delta
        } else if state != "celebrate" {
            spinAngle *= 0.94
        }
    }

    /// Rotates through the state's expression pool, and runs the blink queue.
    /// Returns an eyelid override while a blink is in flight.
    private func updateExpressionAndBlink(now: Double, config: BotMarkConfig) -> Double? {
        if state != "waking" && state != "sleeping" && now >= expressionNext {
            let pool = config.expressionPool
            if !pool.isEmpty {
                // The upstream steps the cursor by a random amount so the
                // same face never repeats twice in a row.
                expressionCursor = (expressionCursor + 1 + Int(BotMath.random(0, Double(max(pool.count - 1, 1)))))
                    % pool.count
                setExpression(pool[expressionCursor],
                              frequency: state == "searching" || state == "excited" ? 10 : 6)
            }
            expressionNext = now + BotMath.random(config.expressionCadence.0, config.expressionCadence.1) * config.tempo
        }
        if let cadence = config.blinkCadence, now >= blinkNext {
            scheduleBlink(now)
            blinkNext = now + BotMath.random(cadence.0, cadence.1) * config.tempo
        }
        while let first = blinkQueue.first, now >= first.at {
            blinkTarget = first.value
            blinkQueue.removeFirst()
        }
        if !blinkQueue.isEmpty { return blinkTarget }
        if let target = blinkTarget {
            blinkTarget = nil
            return target
        }
        return nil
    }

    /// Turn a glance the rail's way, most of the time.
    ///
    /// **A constant offset is not enough on its own.** `gazeBias` is worth 7
    /// units; the glance the state picks is worth up to 15, and 18 for a
    /// persona that looks about more than most. Added together, a mark on the
    /// right-hand edge still spent about half its glances staring off the side
    /// of the display — measured, not guessed — because the lean only moved
    /// the middle of a swing that was twice as wide as the lean itself.
    ///
    /// So the direction of the glance is decided here rather than only its
    /// centre: four in five are folded toward the screen, and the fifth is
    /// left alone. Reflecting every one of them would be worse — a mark whose
    /// eyes can only ever travel one way reads as stuck, and the point of the
    /// autonomous gaze is that it wanders.
    /// The lean is always *positive* in the engine's own space — `facing` is
    /// what decides which way that lands on screen — so folding a glance
    /// inward means folding it to +x and letting the turn take it from there.
    private func inward(_ x: Double, config: BotMarkConfig) -> Double {
        guard config.gazeBias != 0, Double.random(in: 0...1) < 0.8 else { return x }
        return abs(x)
    }

    /// Where the eyes look next, and how long until they look somewhere else.
    private func updateAim(now: Double, config: BotMarkConfig) {
        guard now >= gazeNext else { return }
        func direction() -> Double { Double.random(in: 0...1) < 0.5 ? -1 : 1 }
        var x = 0.0
        var y = 0.0
        var low = 2500.0
        var high = 5000.0
        switch state {
        case "idle": low = 2500; high = 5500
        case "listening": x = 15 * BotMath.random(-0.3, 0.3); y = 9 * BotMath.random(-0.25, 0.25); low = 2200; high = 4200
        case "thinking": x = direction() * BotMath.random(0.5, 1) * 15; y = -9 * BotMath.random(0.4, 1); low = 1500; high = 2800
        case "searching": x = direction() * BotMath.random(0.7, 1) * 15; y = 9 * BotMath.random(-1, 1); low = 550; high = 1150
        case "working": x = 15 * BotMath.random(-0.4, 0.4); y = 9 * BotMath.random(0.4, 1); low = 1200; high = 2400
        case "excited": x = 15 * BotMath.random(-1, 1); y = 9 * BotMath.random(-1, 0.3); low = 700; high = 1400
        case "surprised": low = 1600; high = 2600
        case "suspicious": x = 15 * direction(); y = 2.7; low = 2200; high = 4200
        case "angry": x = 15 * BotMath.random(-0.2, 0.2); y = 1.8; low = 1800; high = 3200
        case "drowsy": x = 15 * BotMath.random(-0.4, 0.4); y = 9 * BotMath.random(0.4, 1); low = 2500; high = 4500
        case "happy": x = 15 * BotMath.random(-0.7, 0.7); y = -9 * BotMath.random(0, 0.6); low = 1800; high = 3400
        case "curious": x = direction() * BotMath.random(0.6, 1) * 15; y = 9 * BotMath.random(-1, 1); low = 950; high = 1900
        case "confused": x = direction() * BotMath.random(0.5, 1) * 15; y = 9 * BotMath.random(-0.6, 1); low = 1100; high = 2300
        case "bored": x = direction() * BotMath.random(0.7, 1) * 15; y = 9 * BotMath.random(0.4, 0.9); low = 3000; high = 6000
        case "proud": x = 15 * BotMath.random(-0.3, 0.3); y = -9 * BotMath.random(0.3, 0.7); low = 2600; high = 4600
        case "shy": x = direction() * BotMath.random(0.6, 1) * 15; y = 9 * BotMath.random(0.5, 1); low = 2000; high = 4000
        case "sad": x = 15 * BotMath.random(-0.3, 0.3); y = 9 * BotMath.random(0.6, 1); low = 2800; high = 5000
        case "laughing": x = 15 * BotMath.random(-0.5, 0.5); y = -9 * BotMath.random(0.2, 0.6); low = 800; high = 1700
        case "scared": x = direction() * BotMath.random(0.7, 1) * 15; y = 9 * BotMath.random(-0.6, 0.6); low = 450; high = 1050
        case "playful": x = direction() * BotMath.random(0.5, 1) * 15; y = -9 * BotMath.random(0, 0.6); low = 900; high = 1800
        case "notifying":
            let focused = Double.random(in: 0...1) < 0.72
            x = (focused ? 0.45 : 0.1) * 15
            y = -9 * (focused ? 0.3 : 0.05)
            low = 1200
            high = 2400
        default:
            x = 15 * BotMath.random(-0.4, 0.4)
            y = 9 * BotMath.random(-0.3, 0.3)
        }
        aimX.target = inward(x, config: config) * config.gazeScale
        aimY.target = y * config.gazeScale
        gazeNext = now + BotMath.random(low, high) * config.tempo
    }

    // MARK: - Gestures

    private func startSpin(turns: Double = 1, direction: Double? = nil) -> Bool {
        guard spinSpring == nil else { return false }
        let chosen = direction ?? (Double.random(in: 0...1) < 0.5 ? 1 : -1)
        var spring = BotMarkSpring(0)
        spring.target = turns * 2 * .pi * chosen
        spinSpring = spring
        return true
    }

    private func startGesture(_ kind: String) {
        guard gesture == nil, spinSpring == nil else { return }
        let turns = kind == "spinDizzy" ? (BotMath.random(3, 4)).rounded() : 1
        self.gesture = Gesture(kind: kind, startedAt: clockTime,
                               direction: Double.random(in: 0...1) < 0.5 ? 1 : -1, turns: turns)
    }

    // Engine time in milliseconds. Frame tests trigger the same gesture here
    // without waiting for the random ambient scheduler to choose it.
    func startBounce(_ now: Double) {
        if bounceStartedAt < 0 { bounceStartedAt = now }
    }

    private func updateGestures(now: Double) -> GesturePose {
        var output = GesturePose()
        if ["idle", "happy", "excited", "curious", "playful"].contains(state), now >= winkNext {
            winkAt = now
            winkEye = Double.random(in: 0...1) < 0.5 ? 0 : 1
            winkNext = now + BotMath.random(4500, 10000)
        }
        if now >= behaviorNext, gesture == nil, spinSpring == nil {
            switch state {
            case "searching": _ = startSpin(); behaviorNext = now + BotMath.random(4000, 7000)
            case "working": _ = startSpin(turns: 1, direction: 1); behaviorNext = now + BotMath.random(6000, 9000)
            case "excited": _ = startSpin(turns: 1); behaviorNext = now + BotMath.random(2800, 5000)
            case "playful": _ = startSpin(turns: 1); behaviorNext = now + BotMath.random(3500, 6000)
            default: break
            }
        }
        if now >= ambientNext {
            if gesture == nil, spinSpring == nil {
                let roll = Double.random(in: 0...1)
                if ["happy", "excited", "proud"].contains(state) {
                    if roll < 0.55 { _ = startSpin(turns: 1) } else { startGesture("spinBounce") }
                } else if state == "playful" {
                    if roll < 0.34 { startGesture("spinBounce") }
                    else if roll < 0.62 { startBounce(now) }
                    else if roll < 0.86 { startGesture("spinDizzy") }
                    else { _ = startSpin(turns: 1) }
                }
            }
            ambientNext = now + BotMath.random(9000, 18000)
        }
        if let active = gesture {
            let elapsed = (now - active.startedAt) / 1000
            if active.kind == "spinBounce" {
                if elapsed < 0.7 {
                    output.turn = active.turns * 2 * .pi * active.direction * BotMath.cubicInOut(elapsed / 0.7)
                } else {
                    startBounce(now)
                    gesture = nil
                }
            } else if active.kind == "spinDizzy" {
                let spinDuration = 0.55 + 0.16 * active.turns
                if elapsed < spinDuration {
                    output.turn = active.turns * 2 * .pi * active.direction * pow(elapsed / spinDuration, 2)
                } else if elapsed < spinDuration + 1.5 {
                    let shakeTime = elapsed - spinDuration
                    let envelope = pow(1 - shakeTime / 1.5, 1.3)
                    output.rotation = 17 * sin(10 * shakeTime) * active.direction * envelope
                    output.x = 10 * cos(10 * shakeTime) * active.direction * envelope
                    output.y = 3 * sin(20 * shakeTime) * envelope
                    output.eyeOpen = 0.46 + 0.14 * sin(21 * shakeTime)
                    output.eyeScale = 1.03
                } else {
                    gesture = nil
                }
            }
        }
        if bounceStartedAt >= 0 {
            let sequence: [(height: Double, duration: Double)] = [
                (48, 0.5), (28, 0.382), (14, 0.27), (6, 0.177),
            ]
            var elapsed = (now - bounceStartedAt) / 1000
            var step = 0
            while step < sequence.count && elapsed >= sequence[step].duration {
                elapsed -= sequence[step].duration
                step += 1
            }
            if step >= sequence.count {
                bounceStartedAt = -1
            } else {
                let phase = elapsed / sequence[step].duration
                output.bounceY = -4 * sequence[step].height * phase * (1 - phase)
            }
        }
        return output
    }

    /// The celebrate loop: a wind-up, nine turns, then a dizzy shake.
    private func celebratePose(elapsed: Double) -> GesturePose {
        var output = GesturePose()
        celebrateWildActive = false
        let activeElapsed = elapsed - 0.14
        if activeElapsed < 0 { return output }
        let cycleIndex = Int(activeElapsed / 6.2)
        if cycleIndex != celebrateCycle {
            celebrateCycle = cycleIndex
            turnDirection = Double.random(in: 0...1) < 0.5 ? 1 : -1
        }
        let cycle = activeElapsed.truncatingRemainder(dividingBy: 6.2)
        if cycle > 5.49 { return output }
        celebrateWildActive = true
        let turns = 9.0
        let direction = turnDirection
        let speed = (turns * 2 * .pi + 0.5) / (0.15 + 2 + 0.3125)
        var angle: Double
        if cycle < 0.24 {
            angle = -0.25 * (1 - cos(cycle / 0.24 * .pi))
        } else if cycle < 0.54 {
            let time = cycle - 0.24
            angle = -0.5 + speed * time * time / 0.6
        } else if cycle < 2.54 {
            angle = -0.5 + speed * (0.15 + cycle - 0.54)
        } else if cycle < 3.79 {
            angle = -0.5 + speed * 2.15 + 1.25 * speed * (1 - pow(1 - (cycle - 2.54) / 1.25, 4)) / 4
        } else {
            angle = turns * 2 * .pi
        }
        output.turn = angle * direction
        var envelope = 0.0
        if cycle > 2.54 {
            let progress = min((cycle - 2.54) / 1.25, 1)
            envelope = progress < 0.4 ? 0 : pow((progress - 0.4) / 0.6, 2)
            if cycle >= 3.79 { envelope = max(0, pow(1 - (cycle - 3.79) / 1.7, 1.6)) }
        }
        let shakeTime = max(cycle - 2.54, 0)
        output.rotation = angle / (turns * 2 * .pi) * 1080 * direction
            + 11 * sin(9.2 * shakeTime) * direction * envelope
        output.x = (cos(9.2 * shakeTime) - 1) * 6 * direction * envelope
        output.y = 2.6 * sin(18.4 * shakeTime) * envelope
        output.gazeX = 13 * sin(11.5 * shakeTime) * direction * envelope
        output.gazeY = (cos(9 * shakeTime) - 1) * 3.5 * envelope
        output.eyeOpen = 1.14 - 0.44 * envelope + 0.1 * sin(16 * shakeTime) * envelope
        output.eyeScale = 1.12 - 0.09 * envelope
        return output
    }

    /// Changing shape is itself an event: the upstream cycles through five
    /// different reactions so it never looks like a dissolve.
    private func triggerShapeChangeMotion() {
        shapeChangeCycle = (shapeChangeCycle + 1) % 5
        switch shapeChangeCycle {
        case 0: _ = startSpin(turns: 1)
        case 1: shapeChangeWide = startSpin(turns: 2)
        case 2: startGesture("spinBounce")
        case 3: startGesture("spinDizzy")
        default:
            _ = startSpin(turns: 1)
            particles.burst(count: 16, force: 0.95, curl: 0.3)
        }
    }

    // MARK: - Shape resolution

    private struct ResolvedShape {
        var shape: BotMarkShape
        var identifier: String
        var transitioning: Bool
        var ring: [CGPoint]
        var face: BotMarkFace
        var tiltScale: Double
        var beltRadius: Double
    }

    private func resolveShape(_ requested: String) -> ResolvedShape {
        let identifier = library.shapes[requested] != nil ? requested : "blob"
        if identifier != shapeId {
            let previous = library.shape(shapeId)
            let currentAmount = BotMath.cubicInOut(BotMath.clamp(shapeBlend.value, 0, 1))
            shapeFromRing = currentAmount >= 1
                ? previous.ring
                : BotMarkGeometry.lerpRing(shapeFromRing, previous.ring, currentAmount)
            shapeFromFace = currentAmount >= 1
                ? previous.face
                : BotMarkFace.blend(shapeFromFace, previous.face, currentAmount)
            shapeFromTiltScale += (previous.tiltScale - shapeFromTiltScale) * currentAmount
            shapeFromBeltRadius += (previous.beltRadius - shapeFromBeltRadius) * currentAmount
            shapeId = identifier
            shapeBlend.value = 0
            shapeBlend.velocity = 0
            shapeBlend.target = 1
            triggerShapeChangeMotion()
        }
        let shape = library.shape(shapeId)
        let amount = BotMath.cubicInOut(BotMath.clamp(shapeBlend.value, 0, 1))
        let transitioning = amount < 0.999
        return ResolvedShape(
            shape: shape,
            identifier: shapeId,
            transitioning: transitioning,
            ring: transitioning ? BotMarkGeometry.lerpRing(shapeFromRing, shape.ring, amount) : shape.ring,
            face: transitioning ? BotMarkFace.blend(shapeFromFace, shape.face, amount) : shape.face,
            tiltScale: transitioning
                ? shapeFromTiltScale + (shape.tiltScale - shapeFromTiltScale) * amount
                : shape.tiltScale,
            beltRadius: transitioning
                ? shapeFromBeltRadius + (shape.beltRadius - shapeFromBeltRadius) * amount
                : shape.beltRadius)
    }

    /// A spring standing at `value` and heading for nothing. **Not**
    /// `BotMarkSpring(value)`, which makes `value` its target too: the carry
    /// then never decayed, every switch added to it, and within a few the
    /// body had been pushed off the canvas.
    private static func carry(_ value: Double) -> BotMarkSpring {
        var spring = BotMarkSpring(0)
        spring.value = value
        return spring
    }

    /// `value` brought into the half-period either side of zero, so a carried
    /// angle unwinds the short way rather than back through every turn.
    private static func wrapped(_ value: Double, period: Double) -> Double {
        value - period * (value / period).rounded()
    }

    // MARK: - Render

    private func render(now: Double, config: BotMarkConfig) -> BotMarkFrame {
        let geometry = resolveShape(config.shape)
        let shape = geometry.shape
        let top = geometry.transitioning ? geometry.ring.map { Double($0.y) }.min()! : shape.top
        let bottom = geometry.transitioning ? geometry.ring.map { Double($0.y) }.max()! : shape.bottom
        let spanSamples = geometry.transitioning ? nil : shape.spanSamples

        let morphAmount = BotMath.clamp(morph.value, 0, 1)
        // The loading whirl widens the particle belt as it comes in.
        currentBeltRadius = geometry.beltRadius
            + (state == "loading" ? (52 - geometry.beltRadius) * morphAmount : 0)
        let blend = BotMath.clamp(morphBlend.value, 0, 1)
        let previous = blend < 0.999 ? previousMorphEffect : nil

        // A morph turns the character half a revolution as it arrives, so the
        // turn spring counts as part of the yaw while it is moving.
        let morphIsTurning = morph.value > 0.001 || abs(turn.target - turn.value) > 0.01
        let rawTurn = (morphIsTurning ? turn.value : 0) + (spinSpring?.value ?? 0) + directTurn
        // **A change of state never teleports the body.** Several things are
        // drawn straight rather than through a spring: celebrate's nine turns
        // (`directRotation`, `directTurn`, hundreds of degrees by the end), a
        // gesture's shake, and a morph's pose — the pencil's sweep, the ball's
        // drop. Each is recomputed from the *new* state on the first frame
        // after a switch, so a scene beat, a mood, a one-shot or the pointer
        // interrupting one of them moved the body up to 144° or 108 units in
        // a single frame, then carried on as if nothing had happened: a
        // one-frame glitch, easy to glimpse and impossible to catch again.
        // Measured over ten simulated minutes per persona with realistic
        // switching. The difference at the switch is handed to springs that
        // ease it away; angles take the short way round.
        let handingOff = drawn != nil && state != drawnState
        if handingOff, let drawn {
            carryTurn = Self.carry(Self.wrapped(drawn.turn - rawTurn, period: 2 * .pi))
        }
        let turnAngle = rawTurn + carryTurn.value
        let shapeRing = abs(turnAngle) > 0.001 && !geometry.transitioning
            ? BotMarkGeometry.turnedShapeRing(shape, identifier: geometry.identifier,
                                          angle: turnAngle, headCentre: headCentre)
            : geometry.ring

        let activeMorphRing = morphEffect == "pencil" ? pencilRing : library.circleRing
        let previousMorphRing = previous == "pencil" ? pencilRing : library.circleRing
        let morphRing = previous != nil
            ? BotMarkGeometry.lerpRing(previousMorphRing, activeMorphRing, BotMath.cubicInOut(blend))
            : activeMorphRing
        // The outline is all the way to the effect's shape by 0.62 of the
        // morph, so the parts arrive on a settled body.
        let morphPathAmount = BotMath.clamp(morphAmount / 0.62, 0, 1)

        let headPath: CGPath
        if morphPathAmount <= 0 {
            if geometry.transitioning
                || (abs(turnAngle) > 0.001 && (shape.solid != nil || shape.sides > 0)) {
                headPath = BotMarkGeometry.ringOutline(shapeRing)
            } else {
                headPath = shape.path
            }
        } else {
            headPath = BotMarkGeometry.ringOutline(
                BotMarkGeometry.lerpRing(shapeRing, morphRing, BotMath.cubicInOut(morphPathAmount)))
        }

        let eyes = renderEyes(now: now, config: config, shape: shape, face: geometry.face,
                              shapeRing: shapeRing, spanSamples: spanSamples,
                              top: top, bottom: bottom, turnAngle: turnAngle,
                              morphAmount: morphAmount)

        let activeMorphSize = morphEffect.flatMap { Self.morphSizes[$0] } ?? 19
        let previousMorphSize = previous.flatMap { Self.morphSizes[$0] } ?? activeMorphSize
        let morphSize = activeMorphSize * blend + previousMorphSize * (1 - blend)
        let morphScale = morphSize / headCentre

        var shapes: [BotMarkFrame.Shape] = []
        let pose = renderMorphEffects(morphAmount: morphAmount, morphBlend: blend,
                                      previous: previous, morphSize: morphSize, now: now,
                                      into: &shapes)

        let normal = 1 - morphAmount
        // **Bounded to the room the viewBox has.** The box is 259 units
        // around a 229-unit body, so the character has about 15 units to move
        // in — and `drowsy` nods 25, a bounce gesture throws it 48, and
        // `dragging` slides 16. Off the canvas it is simply clipped: the top
        // of the head disappears, which reads as a glitch rather than as a
        // jump. Bounded here rather than at the spring targets, so the physics
        // stay the upstream's and only what is drawn is kept inside. Morph
        // poses are left alone: an effect brings its own wider viewBox.
        let room = 12.0
        let travelX = (headX.value + directX) * normal
        let travelY = (headY.value + directY) * normal
        let rawX = travelX + pose.x
        let rawY = travelY + pose.y
        let rawDegrees = rotation.value * 180 / .pi * geometry.tiltScale * normal
            + directRotation * normal + pose.rotation
        if handingOff, let drawn {
            carryX = Self.carry(drawn.x - rawX)
            carryY = Self.carry(drawn.y - rawY)
            carryDegrees = Self.carry(Self.wrapped(drawn.degrees - rawDegrees, period: 360))
        }
        // A state handoff contributes motion too. Bound the complete body
        // translation, then add the effect's own pose. Fade the constraint
        // with the body so a carried morph pose does not snap at the boundary.
        let shiftedX = travelX + carryX.value
        let shiftedY = travelY + carryY.value
        let translateX = BotMath.mix(BotMath.clamp(shiftedX, -room, room), shiftedX, morphAmount) + pose.x
        let translateY = BotMath.mix(BotMath.clamp(shiftedY, -room, room), shiftedY, morphAmount) + pose.y
        let degrees = rawDegrees + carryDegrees.value
        drawn = (translateX, translateY, degrees, turnAngle)
        drawnState = state


        var transform = CGAffineTransform(translationX: headCentre + translateX,
                                          y: headCentre + translateY)
        transform = transform.rotated(by: degrees * .pi / 180)
        transform = transform.scaledBy(x: config.scaleX * normal + morphScale * pose.scale * morphAmount,
                                       y: scaleY.value * normal + morphScale * pose.scale * morphAmount)
        transform = transform.translatedBy(x: -headCentre, y: -headCentre)

        var badge: BotMarkFrame.Badge?
        let badgeAmount = BotMath.clamp(notify.value, 0, 1.4)
        if badgeAmount > 0.01 {
            let anchor = shapeRing[Int((7 * Double(shapeRing.count) / 8).rounded()) % shapeRing.count]
            badge = BotMarkFrame.Badge(centre: anchor, radius: 20 * config.badgeScale * badgeAmount)
        }

        let hummingAmount = BotMath.clamp(humming.value, 0, 1)
        if hummingAmount > 0.01 {
            for index in 0..<2 {
                let angle = 0.85 * spinAngle + Double(index) * .pi
                let radius = 1.3 * shape.radius
                let depth = 0.55 + 0.45 * BotMath.clamp((cos(angle) + 1) / 2, 0, 1)
                let size = 7.5 * depth * hummingAmount
                let centre = CGPoint(x: headCentre + radius * sin(angle),
                                     y: headCentre - 0.38 * radius * cos(angle) - 8)
                shapes.append(BotMarkFrame.Shape(
                    path: CGPath(ellipseIn: CGRect(x: centre.x - size, y: centre.y - size,
                                                   width: size * 2, height: size * 2),
                                 transform: nil),
                    opacity: (0.3 + 0.7 * depth) * hummingAmount))
            }
        }

        // The viewBox opens up for a morph, but only on a small canvas: at
        // 96pt and up there is already room.
        let responsive = 1 - BotMath.smoothstep(BotMath.clamp((config.viewWidth - 44) / 90, 0, 1))
        let activeExpansion = morphEffect.flatMap { Self.morphViewBoxes[$0] } ?? 1
        let previousExpansion = previous.flatMap { Self.morphViewBoxes[$0] } ?? activeExpansion
        let expansion = activeExpansion * blend + previousExpansion * (1 - blend)
        let viewBoxRadius = 129.5 / (1 + (expansion - 1) * morphAmount * responsive)

        return BotMarkFrame(headPath: headPath, transform: transform, opacity: pose.opacity,
                        eyes: eyes, badge: badge, shapes: shapes,
                        viewBoxRadius: viewBoxRadius, morphAmount: morphAmount,
                        facing: facingValue)
    }

    /// A ring mirrored left-to-right about a vertical line.
    ///
    /// Walked backwards from its own first point, so the winding survives and
    /// index *k* still lands on the same place round the outline — which is
    /// what a point-by-point blend between the two needs. Reflecting in place
    /// would pair each point with the one opposite and turn the halfway blend
    /// into a crease.
    private static func reflected(_ ring: [CGPoint], about axis: Double) -> [CGPoint] {
        let count = ring.count
        return (0..<count).map { index in
            let source = ring[(count - index) % count]
            return CGPoint(x: 2 * axis - source.x, y: source.y)
        }
    }

    private func renderEyes(now: Double, config: BotMarkConfig, shape: BotMarkShape,
                            face: BotMarkFace, shapeRing: [CGPoint],
                            spanSamples: [(Double, Double)]?,
                            top: Double, bottom: Double, turnAngle: Double,
                            morphAmount: Double) -> [BotMarkFrame.Eye] {
        let amount = BotMath.clamp(expressionSpring.value, 0, 1)
        var eyeRings = [
            BotMarkGeometry.lerpRing(expressionFrom[0], expressionTo[0], amount),
            BotMarkGeometry.lerpRing(expressionFrom[1], expressionTo[1], amount),
        ]
        // **The expression is drawn already looking somewhere.** The eye pair
        // an expression carries is not centred in the face: across the
        // twenty-five of them the pair's own centre runs from 44 units left of
        // the head's to 76 right, because a glance is drawn into the artwork
        // rather than added to it. That is the single biggest thing aiming a
        // mark, far past the standing lean of 7 — it is why `bored` and
        // `proud` stared off the right-hand edge no matter how hard the lean
        // pulled, and why turning only the gaze terms below is not enough.
        //
        // So the pair is reflected too, and blended point by point the way
        // two bodies are, which puts a symmetric pair of eyes halfway through
        // the turn: the mark looks across, not away. Reflected about the head
        // and swapped, because the left eye of a mark looking right is the
        // right eye of the same mark looking left.
        // Clamped because `facing` is under-damped and overshoots past ±1,
        // and `lerpRing` extrapolates rather than clamping its own amount —
        // so an un-clamped `turn` draws the eyes slightly *past* the mirror
        // on the way in. Sub-pixel at today's damping; it scales with any
        // future overshoot, which is what makes it worth pinning here.
        let turn = BotMath.clamp((1 - facingValue) / 2, 0, 1)
        if turn > 0.001 {
            eyeRings = (0..<2).map { index in
                BotMarkGeometry.lerpRing(
                    eyeRings[index],
                    Self.reflected(eyeRings[1 - index], about: headCentre),
                    turn)
            }
        }
        let centres = eyeRings.map(BotMarkGeometry.centroid)
        // Where the expression itself is looking, before anything is added.
        let pairOffset = (centres[0].x + centres[1].x) / 2 - headCentre
        var scanTop = top
        var scanBottom = bottom
        if abs(turnAngle) > 0.001 {
            scanTop = shapeRing.map { Double($0.y) }.min() ?? top
            scanBottom = shapeRing.map { Double($0.y) }.max() ?? bottom
        }
        var leftHalf = 0.0
        var rightHalf = 0.0
        for point in eyeRings[0] { leftHalf = max(leftHalf, abs(point.x - centres[0].x)) }
        for point in eyeRings[1] { rightHalf = max(rightHalf, abs(point.x - centres[1].x)) }
        let distance = abs(centres[1].x - centres[0].x) * face.sx
        let fit = leftHalf + rightHalf > 0.5
            ? BotMath.clamp((distance - 5) / (leftHalf + rightHalf), 0.35, 4)
            : 4

        if config.pointer, let pointer {
            // Not turned around with the gaze: the pointer is a real place on
            // the screen, and the eyes follow it there whichever way the mark
            // is facing.
            pointerTargetX = 22 * BotMath.clamp(pointer.x, -0.6, 0.6)
            pointerTargetY = 14 * BotMath.clamp(pointer.y, -0.6, 0.6)
        } else {
            pointerTargetX = 0
            pointerTargetY = 0
        }
        // Frame-rate corrected exponential smoothing, as upstream.
        let smoothing = 1 - exp(60 * log(0.91) * delta)

        let bodyExtents = shapeRing.reduce(
            into: (minimum: Double.infinity, maximum: -Double.infinity)
        ) { extents, point in
            extents.minimum = min(extents.minimum, Double(point.x))
            extents.maximum = max(extents.maximum, Double(point.x))
        }
        let edgeClearance = max(bodyExtents.maximum - bodyExtents.minimum, 0) * 0.025
        var output: [BotMarkFrame.Eye] = []
        for index in 0..<2 {
            // Upstream advances the pointer once per eye, so it settles twice
            // as fast as the smoothing constant suggests. Kept as it is.
            pointerX += (pointerTargetX - pointerX) * smoothing
            pointerY += (pointerTargetY - pointerY) * smoothing

            let ring = eyeRings[index]
            let centre = centres[index]
            var localCentre = headCentre + face.x
            var offsetX = (centre.x - headCentre) * face.sx
            var perspectiveX = 1.0
            var visible = true
            var perspectiveFade = 1.0
            if abs(turnAngle) > 0.001 {
                let scanY = BotMath.clamp(headCentre + face.y + (centre.y - headCentre) * face.sy,
                                  scanTop + 2, scanBottom - 2)
                let (left, right) = BotMarkGeometry.spanAt(shapeRing, scanY, headCentre: headCentre)
                let radius = max((right - left) / 2, 12)
                localCentre = (left + right) / 2
                let initial = asin(BotMath.clamp(offsetX / radius, -1, 1))
                let turned = initial + turnAngle
                let cosine = cos(turned)
                let baseCosine = max(cos(initial), 0.02)
                visible = cosine > 0.02
                perspectiveX = max(cosine, 0.02) / baseCosine
                offsetX = radius * sin(turned)
                perspectiveFade = BotMath.smoothstep(BotMath.clamp(cosine / 0.5, 0, 1))
            }
            let pulse = 1 + 0.07 * sin(amount * .pi)
            var driftX = 1.4 * sin(0.00042 * now + Double(index)) + 0.5 * sin(0.001 * now + 2 * Double(index))
            var driftY = 0.9 * sin(0.00058 * now + Double(index))
            // **Somebody pointing at this ring outranks everything else the
            // mark would rather be looking at.** Upstream already damps the
            // state's own glance to a fifth while the pointer is on the
            // panel; the two habits Pulse added have to give way in the same
            // measure, or they win by sheer size. The standing lean is 7 and
            // the expression's built-in glance reaches 76, against a pointer
            // worth 22 — a rail on the right-hand edge kept staring left with
            // the cursor sitting on its right, which is not watching anything.
            let watching = config.pointer && pointer != nil
            let autonomousGazeWeight = watching ? 0.2 : 1.0

            // **Only the gaze turns round, not the mark.** Mirroring the
            // whole drawing aimed the eyes correctly and looked absurd: the
            // body flipped over like a card, which is not what a character
            // does when it looks the other way. So `facing` scales the
            // horizontal gaze terms instead — the wander, the state's own
            // glance, the expression's, and the standing lean — and because
            // it is sprung, the eyes travel across rather than jumping.
            //
            // Two terms are deliberately left out. The pointer is a real
            // place on screen, so it is added after the turn rather than
            // through it. And the glance a `notifying` mark gives its badge
            // is below, because the badge sits at a fixed point on the body:
            // turning the look without turning the badge would have it
            // staring past the thing.
            driftX = (driftX + aimX.value * autonomousGazeWeight + directGazeX
                      + config.gazeBias * autonomousGazeWeight) * facingValue

            // The expression's own glance is in the artwork rather than in a
            // number, so the only way to let it give way is to take it back
            // out. Most of it, not all: a `sad` mark being pointed at should
            // still look sad, and straightening the pair completely would
            // make every expression's eyes sit in the same place.
            driftX -= pairOffset * (1 - autonomousGazeWeight)
            driftX += pointerX

            // **The gaze rides inside the face; it does not push past it.**
            // The expression is already looking somewhere — up to `eyeReach`
            // off the head's centre — and the lean, the state's glance and
            // the pointer are all added on top. Stacked the same way they put
            // an eye outside the silhouette, where it is simply clipped: on a
            // 25pt ring that reads as a mark with one eye missing, which is
            // what it looked like. So the boldest thing the artwork itself
            // does is the ceiling for the total, and anything Pulse adds has
            // to fit under it. Moving back toward the middle is never
            // restricted — only leaving the face is.
            let reach = library.eyeReach
            driftX = BotMath.clamp(pairOffset + driftX, -reach, reach) - pairOffset
            driftY += pointerY + aimY.value * autonomousGazeWeight + directGazeY
            let notification = BotMath.clamp(notify.value, 0, 1)
            driftX -= 10 * notification
            driftY += 7 * notification

            let scaledEye = min(BotMath.clamp(eyeScale.value, 0.2, 2) * face.eye, fit / pulse)
            let scaleX = BotMath.clamp(perspectiveX * scaledEye * pulse, 0.02, 2.4)
            var winkScale = 1.0
            if index == winkEye, now < winkAt + 320 {
                let phase = (now - winkAt) / 320
                winkScale = max(phase < 0.42 ? 1 - phase / 0.42 : (phase - 0.42) / 0.58, 0.04)
            }
            let scaleYValue = BotMath.clamp(max(eyeOpen.value * winkScale, 0.04) * scaledEye * pulse, 0.02, 2.4)
            let halfHeight = library.eyeHalf * scaleYValue + 2
            let y = BotMath.clamp(headCentre + face.y + (centre.y + driftY - headCentre) * face.sy,
                          scanTop + halfHeight, scanBottom - halfHeight)

            // Keep the eye visibly inside the silhouette: sample the body's
            // width at every other point of the eye outline and clamp to the
            // tightest. The inset is about half a point at ring size, enough
            // that antialiasing does not turn an edge-clamped eye into half an
            // eye without pulling ordinary glances toward the middle.
            var maxLeft = -Double.infinity
            var minRight = Double.infinity
            for pointIndex in stride(from: 0, to: ring.count, by: 2) {
                let scaledX = (ring[pointIndex].x - centre.x) * scaleX
                let sampleY = y + (ring[pointIndex].y - centre.y) * scaleYValue
                let span = abs(turnAngle) > 0.001
                    ? BotMarkGeometry.spanAt(shapeRing, sampleY, headCentre: headCentre)
                    : BotMarkGeometry.shapeSpanAt(shape, spanSamples: spanSamples, sampleY, headCentre: headCentre)
                maxLeft = max(maxLeft, span.0 + edgeClearance - scaledX)
                minRight = min(minRight, span.1 - edgeClearance - scaledX)
            }
            let desired = localCentre + offsetX + driftX * face.sx
            let bounded = maxLeft <= minRight
                ? BotMath.clamp(desired, maxLeft, minRight)
                : (maxLeft + minRight) / 2
            var finalX = bounded + (desired - bounded) * (1 - perspectiveFade)
            var finalY = y

            if notification > 0.01 {
                let anchor = shapeRing[Int((7 * Double(shapeRing.count) / 8).rounded()) % shapeRing.count]
                let dx = finalX - anchor.x
                let dy = finalY - anchor.y
                let length = max(sqrt(dx * dx + dy * dy), 1)
                let directionX = dx / length
                let directionY = dy / length
                let eyeHalf = index == 0 ? leftHalf : rightHalf
                let needed = 20 * BotMath.clamp(notify.value, 0, 1.4)
                    + sqrt(pow(eyeHalf * scaleX * directionX, 2)
                           + pow(library.eyeHalf * scaleYValue * directionY, 2)) + 5
                if length < needed {
                    finalX += directionX * (needed - length)
                    finalY += directionY * (needed - length)
                }
            }

            var transform = CGAffineTransform(translationX: finalX, y: finalY)
            transform = transform.scaledBy(x: scaleX, y: scaleYValue)
            transform = transform.translatedBy(x: -centre.x, y: -centre.y)
            output.append(BotMarkFrame.Eye(path: BotMarkGeometry.ringPath(ring),
                                       transform: transform,
                                       visible: visible && morphAmount < 0.5))
        }
        return output
    }
}

/// Everything one frame needs, in the upstream's 0…228.54 unit space.
struct BotMarkFrame {
    struct Eye {
        var path: CGPath
        var transform: CGAffineTransform
        var visible: Bool
    }

    struct Badge {
        var centre: CGPoint
        var radius: Double
    }

    /// A morph part or a humming marker: already positioned, filled unless it
    /// carries a stroke width.
    struct Shape {
        var path: CGPath
        var opacity: Double
        var strokeWidth: Double?
    }

    /// A particle, which carries its own colour rather than the body's.
    struct Painted {
        enum Paint {
            case solid(Color)
            /// Five stops from the ribbon's tail to its head.
            case gradient([Color], CGPoint, CGPoint)
        }

        var path: CGPath
        var opacity: Double
        var paint: Paint
    }

    var headPath: CGPath
    var transform: CGAffineTransform
    var opacity: Double
    var eyes: [Eye]
    var badge: Badge?
    /// Drawn under the character, as the upstream layers them.
    var shapes: [Shape]
    /// Particles behind the character, and the ones passing in front of it.
    var backParticles: [Painted] = []
    var frontParticles: [Painted] = []
    /// Half the viewBox: 129.5 at rest, larger while a morph needs the room.
    var viewBoxRadius: Double
    /// How far into a morph this frame is, 0…1.
    ///
    /// Not used by the drawing — it is already baked into everything else —
    /// but a measurement of the body's size has to know, because a morph
    /// shrinks the character to a fifth on purpose and that is not a squash.
    var morphAmount: Double
    /// -1…+1: which way the gaze is aimed, and how far through a change of
    /// edge it is. ±1 at rest.
    ///
    /// Not used by the drawing — it is already baked into where the eyes
    /// were put — but a test measuring the turn has to be able to see it.
    var facing: Double

    /// The centre of the upstream viewBox, `-15 -15 259 259`.
    static let viewBoxCentre = 114.5
}
