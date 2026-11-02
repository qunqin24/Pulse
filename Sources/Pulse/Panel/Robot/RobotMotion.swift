// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Motion ported from Agent Robot Avatar
// (https://github.com/CX-ArtLab/agent-robot-avatar, v0.7.1),
// Copyright (c) 2026 CX ART Lab, MIT License — see THIRD_PARTY_NOTICES.md.
import CoreGraphics
import Foundation

/// Moves the avatar through time: the pose it is morphing into, its blinks,
/// where it is looking, its antenna, and the scripted steps of an expression.
///
/// The view keeps one of these per ring and asks it for a frame each tick; it
/// has no clock of its own, so a test can drive it with any times it likes.
/// Only the original's behaviour that a ring can use is here: no pointer
/// following, dragging or squeezing — the panel's input belongs to the window
/// (Docs/ui/input.md), and a ring is far too small to grab.
final class RobotMotion {
    /// Where randomness comes from: the blink and glance timings. A test
    /// replaces it to get the same frames every run.
    var random: () -> Double = { Double.random(in: 0..<1) }

    private(set) var mood: RobotMood?
    private(set) var gesture: RobotGesture?
    private var gestureStart: TimeInterval = 0
    private var gestureEnd: TimeInterval = 0

    private var pose = RobotTween(RobotPose.idle)
    /// Where the head rests for the mood: lowered when spent or asleep.
    private var headDrop = RobotTween(0.0)
    /// A head movement played over the resting place — a bob, a nod, waking.
    private var headKeys: HeadKeys?
    /// The failure expression's eyes, pressed down inside the head.
    private var eyeDrop = RobotTween(0.0)
    /// How far the eyes are into their waiting orbit (working) or wave
    /// (refreshing), 0...1, so they ease in and out of it rather than jump.
    private var orbit = RobotTween(0.0)
    private var wave = RobotTween(0.0)
    private var orbitStart: TimeInterval = 0
    private var waveStart: TimeInterval = 0
    private var script: [(at: TimeInterval, run: (RobotMotion, TimeInterval) -> Void)] = []

    private var blinkStart: TimeInterval?
    private var blinkLength: TimeInterval = 0.15
    private var nextBlinkAt: TimeInterval = 0
    private var look = CGPoint.zero
    private var wanderTarget = CGPoint.zero
    private var nextWanderAt: TimeInterval = 0
    private var tilt: Double = 0
    private var tiltSpeed: Double = 0
    private var antenna = RobotFace.antennaHome
    private var antennaSpeed = CGVector.zero
    private var antennaPlaced = false
    private var lastStep: TimeInterval?
    private var reduced = false
    private var personality = RobotPersonality.curious
    /// When idle time next reaches for the personality's pastime.
    private var nextPastimeAt: TimeInterval = .infinity
    /// When the current expression stops preparing and acts.
    private var actAt: TimeInterval = 0
    /// Where `bored` is looking.
    private var boredTarget = CGPoint.zero
    /// Surprise swells the head a little.
    private var headScale = RobotTween(1.0)
    private var shakeStart: TimeInterval?

    /// Plays a one-off expression over the current mood, then returns to it.
    func play(_ gesture: RobotGesture, at now: TimeInterval) {
        self.gesture = gesture
        gestureStart = now
        script.removeAll()
        settleBody(at: now, over: 0.3)
        orbit.move(to: 0, at: now, over: pace(0.2))
        wave.move(to: 0, at: now, over: pace(0.2))
        pose.move(to: .idle, at: now, over: pace(0.14))

        // The original's `_prepareExpression`: centre the eyes, pause, then act.
        // Each action has its own pause.
        let act = now + pace(gesture.preparation)
        actAt = act
        shakeStart = nil
        switch gesture {
        case .cheer:
            schedule(at: act) { motion, at in
                motion.pose.move(to: .happy, at: at, over: motion.pace(0.22))
                motion.headKeys = HeadKeys(start: at, duration: 0.76, keys: [(0, 0), (0.42, -2.4), (1, 0)])
            }
            schedule(at: act + pace(0.98)) { motion, at in
                motion.pose.move(to: .idle, at: at, over: motion.pace(0.52))
            }
            gestureEnd = act + pace(1.5)
        case .nod:
            schedule(at: act) { motion, at in
                motion.headKeys = HeadKeys(start: at, duration: 0.92, keys: [(0, 0), (0.52, 5), (1, 0)])
            }
            gestureEnd = act + pace(0.92)
        case .bored:
            // A slow look one way, the other, and back.
            for (offset, target) in [(0.0, CGPoint(x: -18, y: -11)), (1.4, CGPoint(x: 18, y: -11)),
                                     (2.8, CGPoint.zero)] {
                schedule(at: act + offset) { motion, _ in motion.boredTarget = target }
            }
            gestureEnd = act + 3.12
        case .inspect:
            // The lids and eyes are drawn from the timeline in `eye`; the head
            // dips and rises during the first pass.
            let head = act + Inspect.headStart
            schedule(at: head) { motion, at in
                motion.headKeys = Inspect.head(start: at)
            }
            gestureEnd = act + Inspect.duration + 0.03
        case .surprise:
            // Eyes shrink, open wide with a shiver and the head swells, then
            // everything settles back.
            schedule(at: act) { motion, at in
                motion.pose.move(to: RobotPose(width: 34, height: 36, topLid: -36, bottomLid: 36),
                                 at: at, over: 0.235, ease: .inOutCubic)
            }
            schedule(at: act + 0.235) { motion, at in
                motion.pose.move(to: .surprise, at: at, over: 0.175)
                motion.headScale.move(to: 1.035, at: at, over: 0.175, ease: .head)
            }
            schedule(at: act + 0.41) { motion, at in motion.shakeStart = at }
            schedule(at: act + 0.83) { motion, at in
                motion.shakeStart = nil
                motion.headScale.move(to: 1, at: at, over: 0.43, ease: .head)
                motion.pose.move(to: .idle, at: at, over: 0.43, ease: .inOutCubic)
            }
            gestureEnd = act + 1.26
        }
    }

    /// The frame for `now`, for a ring whose facts say `mood`.
    func frame(at now: TimeInterval, mood: RobotMood, personality: RobotPersonality = .curious,
               reduceMotion: Bool = false) -> RobotFrame {
        reduced = reduceMotion
        if self.personality != personality {
            self.personality = personality
            schedulePastime(after: now)
        }
        if self.mood != mood {
            enter(mood, at: now, from: self.mood)
        }
        if gesture != nil, now >= gestureEnd {
            gesture = nil
            shakeStart = nil
            headScale = RobotTween(1)
            // Back to the mood's resting state without its entrance: the
            // expression already centred the face.
            enter(mood, at: now, from: .idle)
        }
        // Idle time, long enough: the personality's pastime. Never over a
        // mood that reports something, and never with reduced motion.
        if mood == .idle, gesture == nil, !reduced, now >= nextPastimeAt {
            play(personality.pastime, at: now)
        }
        runScript(until: now)

        let dt = min(max(now - (lastStep ?? now), 0), 0.066)
        lastStep = now
        stepBlink(at: now)
        stepLook(at: now, dt: dt)
        stepTilt(dt: dt)

        let drop = headDrop.value(at: now) + (headKeys?.value(at: now) ?? 0)
        let scale = headScale.value(at: now)
        stepAntenna(drop: drop, scale: scale, dt: dt)

        return RobotFrame(
            left: eye(left: true, at: now),
            right: eye(left: false, at: now),
            headDrop: drop,
            headScale: scale,
            headTilt: tilt,
            antenna: antenna
        )
    }

    /// Whether nothing on the face can move until the facts change: asleep,
    /// with the falling-asleep sequence over. The view stops its timeline
    /// then, as the original stops its frame loop.
    func isAtRest(at now: TimeInterval) -> Bool {
        mood == .asleep && gesture == nil && script.isEmpty && headKeys == nil
            && pose.isSettled(at: now) && headDrop.isSettled(at: now)
            && orbit.isSettled(at: now) && wave.isSettled(at: now)
    }

    // MARK: - Moods

    private func enter(_ mood: RobotMood, at now: TimeInterval, from previous: RobotMood?) {
        self.mood = mood
        script.removeAll()
        schedulePastime(after: now)

        // The first frame shows the mood as it stands, not its entrance: a
        // panel opening on a sleeping robot should not watch it fall asleep.
        guard let previous else {
            settle(mood, at: now)
            return
        }

        orbit.move(to: mood == .working ? 1 : 0, at: now, over: pace(0.25))
        wave.move(to: mood == .refreshing ? 1 : 0, at: now, over: pace(0.25))
        if mood == .working && previous != .working { orbitStart = now }
        if mood == .refreshing && previous != .refreshing { waveStart = now }

        var at = now
        if previous == .asleep && mood != .asleep {
            at = wake(at: now)
        }

        switch mood {
        case .idle:
            schedule(at: at) { motion, at in
                motion.pose.move(to: .idle, at: at, over: motion.pace(0.32))
                motion.settleBody(at: at, over: 0.52)
            }
        case .working, .refreshing:
            schedule(at: at) { motion, at in
                motion.pose.move(to: .idle, at: at, over: motion.pace(0.14))
                motion.settleBody(at: at, over: 0.32)
            }
        case .spent:
            // The original's `failure`: centre, pause, sad eyes, and only once
            // they have settled, lower the head and press the eyes down. Held
            // here, where the original recovers — a spent limit stays spent.
            schedule(at: at) { motion, at in
                motion.pose.move(to: .idle, at: at, over: motion.pace(0.14))
            }
            schedule(at: at + pace(0.44)) { motion, at in
                motion.pose.move(to: .sad, at: at, over: motion.pace(0.32))
            }
            schedule(at: at + pace(0.76)) { motion, at in
                motion.headDrop.move(to: 5.5, at: at, over: motion.pace(0.72), ease: .droop)
                motion.eyeDrop.move(to: 4.8, at: at, over: motion.pace(0.72), ease: .smooth)
            }
        case .asleep:
            // The original's `sleep`: drowsy, a brief reopening, drowsy again,
            // then the lids meet as the head sinks.
            schedule(at: at) { motion, at in
                motion.pose.move(to: .idle, at: at, over: motion.pace(0.16))
                motion.settleBody(at: at, over: 0.32)
            }
            schedule(at: at + pace(0.16)) { motion, at in
                motion.pose.move(to: .sleepy, at: at, over: motion.pace(0.94), ease: .inOutCubic)
            }
            schedule(at: at + pace(1.14)) { motion, at in
                motion.pose.move(to: .peek, at: at, over: motion.pace(0.105))
            }
            schedule(at: at + pace(1.26)) { motion, at in
                motion.pose.move(to: .sleepy, at: at, over: motion.pace(0.82), ease: .inOutCubic)
            }
            schedule(at: at + pace(2.25)) { motion, at in
                motion.pose.move(to: .asleep, at: at, over: motion.pace(0.98), ease: .inOutCubic)
                motion.headDrop.move(to: 4, at: at, over: motion.pace(0.98), ease: .head)
            }
        }
    }

    /// The original's `wake`: a little jolt, drowsy, wide awake, and on.
    /// Returns when the mood being woken into takes over.
    private func wake(at now: TimeInterval) -> TimeInterval {
        let from = headDrop.value(at: now)
        headDrop = RobotTween(0)
        if !reduced {
            headKeys = HeadKeys(start: now, duration: 0.5, keys: [(0, from), (0.55, -2), (1, 0)])
        }
        pose.move(to: .sleepy, at: now, over: pace(0.24))
        schedule(at: now + pace(0.26)) { motion, at in
            motion.pose.move(to: .surprise, at: at, over: motion.pace(0.12))
        }
        return now + pace(0.45)
    }

    /// Puts everything where the mood holds still, with no movement.
    private func settle(_ mood: RobotMood, at now: TimeInterval) {
        let rest: RobotPose = switch mood {
        case .spent: .sad
        case .asleep: .asleep
        default: .idle
        }
        pose = RobotTween(rest)
        headDrop = RobotTween(mood == .spent ? 5.5 : mood == .asleep ? 4 : 0)
        eyeDrop = RobotTween(mood == .spent ? 4.8 : 0)
        orbit = RobotTween(mood == .working ? 1 : 0)
        wave = RobotTween(mood == .refreshing ? 1 : 0)
        orbitStart = now
        waveStart = now
        nextBlinkAt = now + (1.8 + random() * 1.8) * personality.blinkGap
        nextWanderAt = now + 0.5
    }

    /// The next pastime, a while into idle time. Counted from every change of
    /// mood and every expression, so it only ever interrupts stillness.
    private func schedulePastime(after now: TimeInterval) {
        let gap = personality.pastimeGap
        nextPastimeAt = now + gap.lowerBound + random() * (gap.upperBound - gap.lowerBound)
    }

    /// Head and eyes back to their ordinary height.
    private func settleBody(at now: TimeInterval, over duration: TimeInterval) {
        headDrop.move(to: 0, at: now, over: pace(duration), ease: .droop)
        eyeDrop.move(to: 0, at: now, over: pace(duration), ease: .smooth)
    }

    private func schedule(at time: TimeInterval, _ run: @escaping (RobotMotion, TimeInterval) -> Void) {
        script.append((time, run))
    }

    private func runScript(until now: TimeInterval) {
        while let index = script.indices.min(by: { script[$0].at < script[$1].at }),
              script[index].at <= now {
            let step = script.remove(at: index)
            step.run(self, step.at)
        }
        if let keys = headKeys, now >= keys.start + keys.duration { headKeys = nil }
    }

    /// A duration, or none at all with reduced motion: the original snaps
    /// between poses then rather than moving.
    private func pace(_ duration: TimeInterval) -> TimeInterval { reduced ? 0 : duration }

    // MARK: - Life

    /// Blinks, only while the face is free — never asleep, waiting or in
    /// the middle of an expression.
    private var blinks: Bool {
        !reduced && (gesture == nil || gesture == .bored) && (mood == .idle || mood == .spent)
    }

    private var blinkFactor: Double {
        guard let blinkStart, let now = lastStep else { return 1 }
        let t = min(max((now - blinkStart) / blinkLength, 0), 1)
        return t < 0.5 ? 1.0.mixed(with: 0.08, by: t * 2) : 0.08.mixed(with: 1, by: (t - 0.5) * 2)
    }

    private func stepBlink(at now: TimeInterval) {
        if let start = blinkStart {
            if now - start >= blinkLength || !blinks {
                blinkStart = nil
                nextBlinkAt = now + (1.9 + random() * 2.6) * personality.blinkGap
            }
        } else if blinks && now >= nextBlinkAt {
            blinkStart = now
            blinkLength = 0.15 + random() * 0.07
        }
    }

    private func stepLook(at now: TimeInterval, dt: TimeInterval) {
        let wanders = !reduced && gesture == nil && mood == .idle
        if wanders && now >= nextWanderAt {
            let reachX = 12 + random() * 13
            let reachY = 5 + random() * 9
            wanderTarget = CGPoint(x: (random() * 2 - 1) * reachX, y: (random() * 2 - 1) * reachY)
            nextWanderAt = now + (1.15 + random() * 1.9) * personality.glanceGap
        } else if gesture == .bored && !reduced {
            wanderTarget = boredTarget
        } else if !wanders {
            wanderTarget = .zero
        }
        if reduced {
            look = wanderTarget
            return
        }

        var target = wanderTarget
        let reach = hypot(target.x / RobotFace.lookReach.width, target.y / RobotFace.lookReach.height)
        if reach > 1 {
            target.x /= reach
            target.y /= reach
        }
        // `bored` looks at the original's fastest speed, clamped as it does.
        let speed = gesture == .bored ? 0.9 : wanders ? personality.glanceSpeed : 0.40
        let k = 1 - pow(1 - speed, dt / (1 / 60.0))
        look.x += (target.x - look.x) * k
        look.y += (target.y - look.y) * k
    }

    /// The head leans a little into a diagonal glance, on a spring.
    private func stepTilt(dt: TimeInterval) {
        guard !reduced else {
            tilt = 0
            tiltSpeed = 0
            return
        }
        let nx = min(max(look.x / RobotFace.lookReach.width, -1), 1)
        let ny = min(max(look.y / RobotFace.lookReach.height, -1), 1)
        let target = nx * ny * 8
        let step = min(dt, 0.034)
        tiltSpeed += ((target - tilt) * 56 - tiltSpeed * 13) * step
        tilt += tiltSpeed * step
    }

    /// The antenna floats above the head and follows it on a loose spring,
    /// so it bobs after the head moves.
    private func stepAntenna(drop: Double, scale: Double, dt: TimeInterval) {
        let home = RobotFace.antennaHome
        let angle = tilt * .pi / 180
        let dx = (home.x - 120) * scale, dy = (home.y - 120) * scale + drop
        let target = CGPoint(x: 120 + dx * cos(angle) - dy * sin(angle),
                             y: 120 + dx * sin(angle) + dy * cos(angle))
        guard !reduced, antennaPlaced else {
            antenna = target
            antennaSpeed = .zero
            antennaPlaced = true
            return
        }
        let step = min(dt, 0.05)
        antennaSpeed.dx += ((target.x - antenna.x) * 180 - antennaSpeed.dx * 5.6) * step
        antennaSpeed.dy += ((target.y - antenna.y) * 180 - antennaSpeed.dy * 5.6) * step
        antenna.x += antennaSpeed.dx * step
        antenna.y += antennaSpeed.dy * step
    }

    // MARK: - Eyes

    private func eye(left: Bool, at now: TimeInterval) -> RobotFrame.Eye {
        let p = pose.value(at: now)
        let restX = (left ? RobotFace.leftEyeX : RobotFace.rightEyeX)

        // The nod and the cheer's bob, counted from when the expression acts.
        var nodY = 0.0, nodScale = 1.0, bobY = 0.0
        let acted = (now - actAt) * 1000
        if !reduced, acted >= 0 {
            switch gesture {
            case .nod:
                let depth: Double = switch acted {
                case ..<150: acted / 150
                case ..<300: 1 - (acted - 150) / 150
                case ..<450: (acted - 300) / 150
                case ..<760: 1 - (acted - 450) / 310
                default: 0
                }
                nodY = 31 * depth
                nodScale = 1 - 0.3 * depth
            case .cheer:
                let t = min(acted / 620, 1)
                if t < 1 { bobY = sin(t * .pi * 4) * 8 * (1 - 0.38 * t) }
            case .bored, .inspect, .surprise, nil:
                break
            }
        }

        // Surprise: the eyes shiver while wide, and stand a little further apart.
        var shiver = 1.0, spread = 0.0
        if gesture == .surprise {
            if let shakeStart {
                let t = min(max((now - shakeStart) / 0.42, 0), 1)
                shiver = 1 + 0.022 * sin(t * .pi * 8) * (1 - 0.18 * t)
            }
            spread = 3.4 * RobotEase.outQuint(min(max((p.width - 34) / (RobotPose.surprise.width - 34), 0), 1))
        }

        let blinkHeight = max(2.6, p.height * blinkFactor * nodScale * shiver)
        let lift = (p.height - blinkHeight) * 0.02
        let projectedX = restX + spread * (left ? -1 : 1) + look.x
        let edge = left ? projectedX - 32 : 208 - projectedX
        let edgeFactor = min(max(1 - edge / 58, 0), 1)
        let width = p.width * shiver * (1 - 0.22 * edgeFactor * edgeFactor)
        let height = blinkHeight * (1 - 0.08 * edgeFactor * edgeFactor)
        let inward = (p.width * shiver - width) * 0.58 * (left ? 1 : -1)

        var centre = CGPoint(x: projectedX + inward,
                             y: RobotFace.eyeY + look.y + nodY + eyeDrop.value(at: now) + bobY)
        var radii = CGSize(width: width / 2, height: height / 2)
        var scale = CGSize(width: 1, height: 1)

        // Working: the eyes circle round each other, foreshortened as they
        // pass. With reduced motion the original holds them drawn together.
        let orbiting = orbit.value(at: now)
        if orbiting > 0 {
            let x: Double, sx: Double, sy: Double
            if reduced {
                x = left ? 100 : 140
                sx = 0.92
                sy = 1
            } else {
                let angle = (now - orbitStart).truncatingRemainder(dividingBy: 3.2) / 3.2 * .pi * 4
                let depth = 1 + 0.08 * sin(angle) * (left ? 1 : -1)
                x = 120 + 34 * cos(angle) * (left ? -1 : 1)
                sx = (0.72 + 0.28 * abs(cos(angle))) * depth
                sy = depth
            }
            centre.x = centre.x.mixed(with: x, by: orbiting)
            scale = CGSize(width: 1.0.mixed(with: sx, by: orbiting), height: 1.0.mixed(with: sy, by: orbiting))
        }

        // Refreshing: the eyes bob up and down in turn.
        let waving = wave.value(at: now)
        if waving > 0 {
            var y = RobotFace.eyeY, x = restX, sx = 1.0
            if reduced {
                x = left ? 100 : 140
                sx = 0.92
            } else {
                let elapsed = now - waveStart
                let amplitude = 10 * RobotEase.smoothstep(elapsed / 0.14)
                let angle = elapsed.truncatingRemainder(dividingBy: 1.1) / 1.1 * .pi * 2
                y += sin(angle + (left ? 0 : 0.7)) * amplitude
            }
            centre = CGPoint(x: centre.x.mixed(with: x, by: waving), y: centre.y.mixed(with: y, by: waving))
            radii = CGSize(width: radii.width.mixed(with: 27, by: waving),
                           height: radii.height.mixed(with: 29, by: waving))
            scale.width = scale.width.mixed(with: sx, by: waving)
        }

        var eye = RobotFrame.Eye(
            centre: centre,
            radii: radii,
            lift: lift,
            scale: scale,
            topLid: p.topLid,
            bottomLid: p.bottomLid,
            tilt: left ? p.leftTilt : p.rightTilt
        )

        // Inspect: the original keeps the eyes' own shape and makes the
        // squint with the lids alone, scanning the eyes up and down.
        if gesture == .inspect, !reduced, acted >= 0 {
            let (lids, shift) = Inspect.state(at: acted / 1000)
            eye.centre = CGPoint(x: restX, y: RobotFace.eyeY + shift)
            eye.topLid = CGFloat(Double(eye.topLid).mixed(with: -Inspect.aperture / 2, by: lids))
            eye.bottomLid = CGFloat(Double(eye.bottomLid).mixed(with: Inspect.aperture / 2, by: lids))
            eye.tilt = 0
        }
        return eye
    }
}

/// A head movement as keyframes, with one easing over the whole run — how the
/// original's Web Animations calls move the head.
private struct HeadKeys {
    var start: TimeInterval
    var duration: TimeInterval
    var keys: [(Double, Double)]
    /// The easing over the whole run.
    var ease: RobotEase = .head
    /// An easing for the segment that starts at each key, where the original
    /// gives one; linear otherwise.
    var segments: [RobotEase] = []

    func value(at now: TimeInterval) -> Double {
        let progress = ease((now - start) / duration)
        guard let next = keys.firstIndex(where: { $0.0 >= progress }), next > 0 else {
            return keys.first?.1 ?? 0
        }
        let (a, from) = keys[next - 1], (b, to) = keys[next]
        let segment = next - 1 < segments.count ? segments[next - 1] : .linear
        return from.mixed(with: to, by: segment((progress - a) / max(b - a, 0.0001)))
    }
}

/// The original's `inspect` timeline, in seconds from when it acts.
private enum Inspect {
    static let aperture = 16.0
    static let scanOffset = 16.0
    /// Close, hold; down, hold, up, hold, centre, hold; down, hold, up, hold,
    /// centre, hold; open — the original's tuned phase lengths.
    static let phases: [Double] = [0.22, 0.88, 0.4, 0.56, 0.16, 0.58, 0.14, 0.76,
                                   0.14, 0.62, 0.18, 0.62, 0.1, 0.94, 0.26]
    static let duration = phases.reduce(0, +)

    private static func end(_ index: Int) -> Double { phases[0...index].reduce(0, +) }

    /// The head moves from the first descent to the first return to centre.
    static let headStart = end(1)
    static func head(start: TimeInterval) -> HeadKeys {
        let span = end(6) - headStart
        func at(_ index: Int) -> Double { (end(index) - headStart) / span }
        return HeadKeys(
            start: start, duration: span,
            keys: [(0, 0), (at(2), 5), (at(3), 5), (at(4), -4), (at(5), -4), (1, 0)],
            ease: .linear,
            segments: [.bezier(0.38, 0, 0.25, 1), .linear, .bezier(0.35, 0, 0.22, 1), .linear,
                       .bezier(0.35, 0, 0.22, 1)]
        )
    }

    /// How closed the lids are, 0...1, and how far the eyes have moved down.
    static func state(at t: Double) -> (Double, Double) {
        let lids: Double
        if t < end(0) {
            lids = RobotEase.smoothstep(t / phases[0])
        } else if t >= end(13) {
            lids = 1 - RobotEase.smoothstep((t - end(13)) / phases[14])
        } else {
            lids = 1
        }

        func move(_ from: Double, _ to: Double, during index: Int) -> Double {
            let start = end(index) - phases[index]
            return from.mixed(with: to, by: RobotEase.smoothstep((t - start) / phases[index]))
        }
        let o = scanOffset
        let shift: Double = switch t {
        case ..<end(1): 0
        case ..<end(2): move(0, o, during: 2)
        case ..<end(3): o
        case ..<end(4): move(o, -o, during: 4)
        case ..<end(5): -o
        case ..<end(6): move(-o, 0, during: 6)
        case ..<end(7): 0
        case ..<end(8): move(0, o, during: 8)
        case ..<end(9): o
        case ..<end(10): move(o, 0, during: 10)
        default: 0
        }
        return (lids, shift)
    }
}

extension RobotGesture {
    /// The original's pause before each action: centre the eyes, wait, act.
    fileprivate var preparation: TimeInterval {
        switch self {
        case .cheer, .nod, .surprise: 0.5
        case .bored: 0.8
        case .inspect: 0.28
        }
    }
}

extension CGFloat {
    fileprivate func mixed(with other: Double, by t: Double) -> CGFloat {
        CGFloat(Double(self).mixed(with: other, by: t))
    }
}
