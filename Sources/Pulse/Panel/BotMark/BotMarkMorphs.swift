// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation

/// The 14 one-shot morph effects, ported from the upstream `morph-system.js`
/// and the morph half of `svg-renderer.js`.
///
/// A morph is not a swap: the head's own outline blends into a circle (or,
/// for `pencil`, into an upside-down teardrop), the whole character scales
/// down to the effect's size, and the effect's own dots, rings and glyphs are
/// drawn underneath it. `RESET → ENTER → HOLD → EXIT → DONE` is driven by one
/// spring, so interrupting a morph half-way is well defined.
extension BotMarkEngine {
    /// How small the character gets while each effect is on screen.
    static let morphSizes: [String: Double] = [
        "dots": 22, "orbit": 19, "radar": 19, "progress": 19, "gather": 19,
        "wave": 16, "send": 20, "receive": 20, "dock": 20, "ball": 18,
        "whirl": 15, "pencil": 17, "bang": 13, "standby": 13,
    ]

    /// How much the viewBox opens up for each effect, so the parts that fly
    /// outside the head still fit. Only applied on small canvases.
    static let morphViewBoxes: [String: Double] = [
        "dots": 1.5, "orbit": 1.14, "radar": 1.14, "progress": 1.32, "gather": 1.15,
        "wave": 1.42, "send": 1.12, "receive": 1.12, "dock": 1.3, "ball": 1.22,
        "whirl": 1.45, "pencil": 1.18, "bang": 1.28, "standby": 1.75,
    ]

    static let morphOrder = ["dots", "orbit", "radar", "progress", "gather", "wave",
                             "send", "receive", "dock", "ball", "whirl", "pencil",
                             "bang", "standby"]

    struct EffectPose {
        var x = 0.0
        var y = 0.0
        var rotation = 0.0
        var scale = 1.0
        var opacity = 1.0
    }

    // MARK: - Lifecycle

    func updateMorph(now: Double, config: BotMarkConfig) {
        let requested = config.morph
        if requested != requestedMorphEffect {
            requestedMorphEffect = requested
            morphShotStartedAt = now
            oneShotResting = false
        }
        var visible = requested != nil
        // `progress` and `spawning` are shots, not loops: they play, rest,
        // and play again.
        if requested != nil, state == "progress" || state == "spawning" {
            let shot: Double = state == "progress" ? 2500 : 2000
            if !oneShotResting, now - morphShotStartedAt > shot {
                oneShotResting = true
                morphRestStartedAt = now
            } else if oneShotResting, now - morphRestStartedAt > 1500 {
                oneShotResting = false
                morphShotStartedAt = now
            }
            visible = !oneShotResting
        }
        morph.target = visible ? 1 : 0

        if let requested, requested != morphEffect {
            if morphEffect != nil, morph.value > 0.02 {
                previousMorphEffect = morphEffect
                morphBlend.value = 0
                morphBlend.velocity = 0
                morphBlend.target = 1
            } else {
                previousMorphEffect = nil
                morphBlend.value = 1
                morphBlend.velocity = 0
                morphBlend.target = 1
            }
            morphEffect = requested
            morphStartedAt = now
        }
        // The outgoing geometry is kept until its spring is all the way back.
        if requested == nil, morph.value < 0.004 {
            morphEffect = nil
            previousMorphEffect = nil
            morphBlend.value = 1
            morphBlend.velocity = 0
            morphBlend.target = 1
        }
        if previousMorphEffect != nil, morphBlend.value > 0.996 { previousMorphEffect = nil }

        if visible != morphVisible {
            if visible { turnDirection = Double.random(in: 0...1) < 0.5 ? 1 : -1 }
            turn.target += .pi * turnDirection
            morphVisible = visible
        }
    }

    // MARK: - Effects

    /// Draws every live effect and returns how the character itself should be
    /// posed while they play.
    func renderMorphEffects(morphAmount: Double, morphBlend blend: Double,
                            previous: String?, morphSize: Double, now: Double,
                            into shapes: inout [BotMarkFrame.Shape]) -> EffectPose {
        var pose = EffectPose()
        guard let active = morphEffect, morphAmount > 0.004 else { return pose }
        let elapsed = now - stateStartedAt

        for effect in Self.morphOrder {
            let amount: Double
            if effect == active {
                amount = morphAmount * blend
            } else if effect == previous {
                amount = morphAmount * (1 - blend)
            } else {
                continue
            }
            guard amount > 0.004 else { continue }

            switch effect {
            case "dots":
                renderDots(amount: amount, now: now, into: &shapes)
                let raw = BotMath.unitRemainder((now - morphStartedAt) / 1400 + 0.119)
                let distance = abs(raw - 1.0 / 3)
                let pulseDistance = min(distance, 1 - distance)
                let pulse = exp(-(pulseDistance * pulseDistance) / 0.045)
                let pop = 0.84 + 0.22 * pulse
                pose.scale *= 1 + (pop - 1) * (amount / max(morphAmount, 0.001))
                pose.y -= 9 * pulse * amount * morphAmount
                pose.opacity *= 1 - 0.5 * (1 - pulse) * amount
            case "orbit":
                renderOrbit(amount: amount, now: now, into: &shapes)
            case "radar":
                renderRadar(amount: amount, now: now, baseRadius: morphSize, into: &shapes)
            case "progress":
                renderProgress(amount: amount, now: now, into: &shapes)
            case "gather":
                renderGather(amount: amount, now: now, into: &shapes)
            case "wave":
                renderWave(amount: amount, now: now, into: &shapes)
            case "send":
                renderSend(amount: amount, now: now, into: &shapes)
                let phase = BotMath.unitRemainder(elapsed / 1500)
                let bump = phase < 0.18
                    ? -0.06 * sin(phase / 0.18 * .pi)
                    : phase < 0.42 ? 0.05 * sin((phase - 0.18) / 0.24 * .pi) : 0
                pose.scale *= 1 + bump * amount
            case "receive":
                renderReceive(amount: amount, now: now, into: &shapes)
                let phase = BotMath.clamp((BotMath.unitRemainder(elapsed / 1700) - 0.58) / 0.34, 0, 1)
                pose.scale *= 1 + 0.11 * sin(phase * .pi) * amount
            case "dock":
                renderDock(amount: amount, now: now, into: &shapes)
            case "pencil":
                let pencil = renderPencil(amount: amount, now: now, into: &shapes)
                pose.x += pencil.x * amount * morphAmount
                pose.y += pencil.y * amount * morphAmount
                pose.rotation += pencil.rotation * amount * morphAmount
            case "bang":
                renderBang(amount: amount, now: now, into: &shapes)
                pose.y += 58 * amount * morphAmount
                pose.scale *= 1 + 0.04 * exp(-((elapsed / 1000).truncatingRemainder(dividingBy: 2.2) * 5.5)) * amount
            case "standby":
                renderStandby(amount: amount, now: now, into: &shapes)
                pose.opacity *= 1 - (0.28 + 0.2 * sin(0.0016 * now)) * amount
            case "whirl":
                // The whirl is the belt of particles; the head only drifts.
                pose.x += (2 * sin(0.0009 * now) + 0.8 * sin(0.0017 * now)) * amount * morphAmount
                pose.y += (2.4 * sin(0.0013 * now) + 1.2 * sin(0.0006 * now)) * amount * morphAmount
            case "ball":
                let seconds = elapsed / 1000
                let gravity = 416 / 0.3844
                let fall = (80 / gravity).squareRoot()
                let cycle = BotMath.unitRemainder((seconds - fall) / 0.62)
                let height = seconds < fall
                    ? 40 - 0.5 * gravity * seconds * seconds
                    : 208 * cycle * (1 - cycle)
                pose.y += (40 - height) * amount * morphAmount
            default:
                break
            }
        }
        return pose
    }

    private func renderDots(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let anchors = [centre - 62, centre + 62]
        for index in 0..<2 {
            let phase = BotMath.clamp((amount - 0.12 * Double(index)) / (1 - 0.12 * Double(index)), 0, 1)
            guard phase > 0.004 else { continue }
            let grow = BotMath.cubicOut(phase)
            let enter = BotMath.backOut(phase)
            let raw = BotMath.unitRemainder((now - morphStartedAt) / 1400 + 0.119)
            let pulseDistance = abs(raw - Double(index) * 2 / 3)
            let distance = min(pulseDistance, 1 - pulseDistance)
            let pulse = exp(-(distance * distance) / 0.045)
            let lift = 9 * pulse * amount
            let pop = 0.84 + 0.22 * pulse
            let scale = 22 * grow * pop / centre * 1.02
            var transform = CGAffineTransform(
                translationX: centre + (anchors[index] - centre) * enter, y: centre - lift)
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: -centre, y: -centre)
            shapes.append(BotMarkFrame.Shape(path: circlePath.copy(using: &transform) ?? circlePath,
                                         opacity: grow * (1 - 0.5 * (1 - pulse))))
        }
    }

    private func renderOrbit(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let radius = 52 * BotMath.backOut(amount)
        for index in 0..<5 {
            let phase = 0.0017 * now + Double(index) * 2 * .pi / 5
            let cosine = cos(phase)
            let depth = 0.5 + 0.5 * BotMath.clamp(cosine, 0, 1)
            shapes.append(circle(
                x: centre + radius * sin(phase),
                y: centre - 0.42 * radius * cos(phase),
                radius: max(12 * depth * BotMath.cubicOut(amount), 0.3),
                opacity: BotMath.clamp((cosine + 0.4) / 0.6, 0.18, 1) * BotMath.cubicOut(amount)))
        }
    }

    private func renderRadar(amount: Double, now: Double, baseRadius: Double,
                             into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        for index in 0..<3 {
            let phase = BotMath.unitRemainder(now / 1300 + Double(index) / 3)
            shapes.append(circle(
                x: centre, y: centre,
                radius: baseRadius + (104 - baseRadius) * phase,
                opacity: BotMath.cubicOut(amount) * (1 - phase) * 0.9,
                strokeWidth: 3.4 * (1 - 0.55 * phase)))
        }
    }

    private func renderProgress(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let radius = 62 * BotMath.backOut(amount)
        shapes.append(circle(x: centre, y: centre, radius: radius,
                             opacity: 0.16 * BotMath.cubicOut(amount), strokeWidth: 5))
        let progress = BotMath.clamp((now - morphShotStartedAt) / 2500 / 0.85, 0, 1)
        guard progress > 0 else { return }
        // Upstream strokes the full circle and dashes it; the same result is
        // an arc from twelve o'clock.
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: centre, y: centre), radius: radius,
                   startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * progress,
                   clockwise: false)
        shapes.append(BotMarkFrame.Shape(path: arc, opacity: BotMath.cubicOut(amount), strokeWidth: 5))
    }

    private func renderGather(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        for index in 0..<5 {
            let phase = BotMath.clamp(((now - morphShotStartedAt) / 2000 - 0.09 * Double(index)) / 0.62, 0, 1)
            guard phase < 1 else { continue }
            let settle = 1 - pow(1 - phase, 3)
            let angle = 2.4 * Double(index) + 2.2 * phase
            let radius = 96 * (1 - settle)
            shapes.append(circle(
                x: centre + radius * cos(angle),
                y: centre + radius * sin(angle) * 0.8,
                radius: 9 * (0.5 + 0.5 * settle) * BotMath.cubicOut(amount),
                opacity: BotMath.cubicOut(amount) * BotMath.clamp(5 * phase, 0, 1) * (1 - 0.25 * settle)))
        }
    }

    private func renderWave(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let offsets = [-2.0, -1.0, 1.0, 2.0]
        for offset in offsets {
            let phase = BotMath.clamp((amount - 0.1 * abs(offset)) / (1 - 0.1 * abs(offset)), 0, 1)
            guard phase > 0.004 else { continue }
            let energy = (0.42 + 0.29 * sin(0.0021 * now) * sin(0.0034 * now)
                          + 0.29 * sin(0.0013 * now + 1.7))
                * (0.55 + 0.45 * sin(0.012 * now - 1.05 * abs(offset)))
            let size = (7 + 9 * BotMath.clamp(energy, 0.08, 1)) * BotMath.cubicOut(phase)
            let lift = 6 * BotMath.clamp(energy, 0, 1) * phase
            shapes.append(circle(x: centre + 44 * offset * BotMath.backOut(phase),
                                 y: centre - lift, radius: size, opacity: phase))
        }
    }

    private func renderSend(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let phase = BotMath.unitRemainder((now - stateStartedAt) / 1500)
        let travel = BotMath.clamp((phase - 0.18) / 0.55, 0, 1)
        let eased = travel * travel * (0.4 + 0.6 * travel)
        let distance = 108 * eased
        if travel > 0, travel < 1 {
            shapes.append(circle(x: centre + 0.74 * distance, y: centre - 0.62 * distance,
                                 radius: 10 * (1 - 0.55 * eased) * BotMath.cubicOut(amount),
                                 opacity: BotMath.cubicOut(amount) * (1 - eased * eased)))
        }
        let secondTravel = BotMath.clamp((phase - 0.26) / 0.55, 0, 1)
        let secondEase = secondTravel * secondTravel * (0.4 + 0.6 * secondTravel)
        if travel > 0, secondTravel > 0, secondTravel < 1 {
            let secondDistance = 108 * secondEase
            shapes.append(circle(x: centre + 0.74 * secondDistance,
                                 y: centre - 0.62 * secondDistance,
                                 radius: 5 * (1 - 0.6 * secondEase) * BotMath.cubicOut(amount),
                                 opacity: 0.3 * BotMath.cubicOut(amount) * (1 - secondEase)))
        }
        let ringPhase = BotMath.clamp((phase - 0.18) / 0.3, 0, 1)
        if ringPhase > 0, ringPhase < 1 {
            shapes.append(circle(x: centre, y: centre, radius: 20 + 34 * BotMath.cubicOut(ringPhase),
                                 opacity: BotMath.cubicOut(amount) * (1 - ringPhase) * 0.8,
                                 strokeWidth: 2.8 * (1 - ringPhase)))
        }
    }

    private func renderReceive(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let elapsed = now - stateStartedAt
        let cycle = Int(elapsed / 1700)
        if cycle != receiveCycle {
            receiveCycle = cycle
            receiveAngle = BotMath.random(-1.25 * .pi, 0.25 * .pi)
        }
        let phase = BotMath.unitRemainder(elapsed / 1700)
        let travel = BotMath.clamp(phase / 0.6, 0, 1)
        let eased = 1 - pow(1 - travel, 3)
        let radius = 108 * (1 - eased)
        let orbit = 18 * sin(travel * .pi) * (1 - 0.7 * eased)
        let cosine = cos(receiveAngle)
        let sine = sin(receiveAngle)
        if travel < 1 {
            shapes.append(circle(x: centre + cosine * radius - sine * orbit,
                                 y: centre + sine * radius + cosine * orbit,
                                 radius: 3.5 + 6.5 * eased,
                                 opacity: BotMath.cubicOut(amount) * BotMath.clamp(3.5 * travel, 0, 1)
                                     * (0.3 + 0.7 * eased)))
        }
        let ringPhase = BotMath.clamp((phase - 0.58) / 0.32, 0, 1)
        if ringPhase > 0, ringPhase < 1 {
            shapes.append(circle(x: centre, y: centre, radius: 20 + 26 * BotMath.cubicOut(ringPhase),
                                 opacity: BotMath.cubicOut(amount) * (1 - ringPhase) * 0.8,
                                 strokeWidth: 2.8 * (1 - ringPhase)))
        }
    }

    private func renderDock(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let elapsed = (now - stateStartedAt) / 1000
        for index in 0..<2 {
            let phase = BotMath.clamp((elapsed - (0.2 + 1.3 * Double(index))) / 0.9, 0, 1)
            guard phase > 0 else { continue }
            let eased = 1 - pow(1 - phase, 3)
            let angle = 0.0011 * now + Double(index) * .pi
            let targetX = centre + 42 * sin(angle)
            let targetY = centre + 21 * cos(angle) + 2 * sin(0.003 * now + Double(index))
            let startX = centre - 120 + 30 * Double(index)
            let startY = centre + 95
            shapes.append(circle(x: startX + (targetX - startX) * eased,
                                 y: startY + (targetY - startY) * eased,
                                 radius: (7 + 3 * eased) * BotMath.cubicOut(amount),
                                 opacity: BotMath.cubicOut(amount) * BotMath.clamp(4 * phase, 0, 1)))
        }
    }

    private struct PencilPose {
        var x: Double
        var y: Double
        var wiggle: Double
        var rotation: Double
        var lift: Bool
    }

    private func pencilPose(now: Double) -> PencilPose {
        let elapsed = now - stateStartedAt
        let cycle = BotMath.unitRemainder(elapsed / 2500)
        if cycle < 0.68 {
            let phase = cycle / 0.68
            let envelope = BotMath.clamp(phase / 0.08, 0, 1) * BotMath.clamp((1 - phase) / 0.08, 0, 1)
            return PencilPose(x: -54 + BotMath.smoothstep(phase) * 118, y: 26,
                              wiggle: 3.2 * sin(24 * phase) * envelope,
                              rotation: 17 + sin(0.0006 * elapsed), lift: false)
        }
        let phase = BotMath.cubicInOut((cycle - 0.68) / 0.32)
        return PencilPose(x: 64 - 118 * phase, y: 26 - 20 * sin(phase * .pi), wiggle: 0,
                          rotation: 17 - 2 * sin(phase * .pi) + sin(0.0006 * elapsed), lift: true)
    }

    private func renderPencil(amount: Double, now: Double,
                              into shapes: inout [BotMarkFrame.Shape]) -> EffectPose {
        let centre = BotMarkLibrary.shared.headCentre
        let pose = pencilPose(now: now)
        let angle = (pose.rotation - 90) * .pi / 180
        let offsetX = 68 * cos(angle)
        let offsetY = 68 * sin(angle)
        var transform = CGAffineTransform(
            translationX: centre + (pose.x + offsetX) * amount,
            y: centre + (pose.y + 0.15 * pose.wiggle + offsetY) * amount)
        transform = transform.rotated(by: pose.rotation * amount * .pi / 180)
        let scale = BotMath.cubicOut(amount)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -centre, y: -centre)
        shapes.append(BotMarkFrame.Shape(path: pencilGlyph.copy(using: &transform) ?? pencilGlyph,
                                     opacity: BotMath.clamp(1.6 * amount - 0.3, 0, 1)))

        // The written line: a trail of points laid down while the nib is
        // down, and eaten from the front once it lifts.
        if amount > 0.6, !pose.lift {
            let point = CGPoint(x: centre + pose.x, y: centre + pose.y + pose.wiggle + 19)
            if let last = writingTrail.last,
               hypot(point.x - last.x, point.y - last.y) <= 2.4 {
                writingTrail[writingTrail.count - 1] = point
            } else {
                writingTrail.append(point)
                if writingTrail.count > 64 { writingTrail.removeFirst() }
            }
        } else if !writingTrail.isEmpty {
            writingTrail.removeFirst(min(2, writingTrail.count))
        }
        if writingTrail.count >= 2 {
            let points = writingTrail
            let trail = CGMutablePath()
            trail.move(to: points[0])
            if points.count == 2 {
                trail.addLine(to: points[1])
            } else {
                for index in 0..<(points.count - 1) {
                    let previous = points[max(index - 1, 0)]
                    let point = points[index]
                    let next = points[index + 1]
                    let after = points[min(index + 2, points.count - 1)]
                    trail.addCurve(
                        to: next,
                        control1: CGPoint(x: point.x + (next.x - previous.x) / 6,
                                          y: point.y + (next.y - previous.y) / 6),
                        control2: CGPoint(x: next.x - (after.x - point.x) / 6,
                                          y: next.y - (after.y - point.y) / 6))
                }
            }
            shapes.append(BotMarkFrame.Shape(path: trail, opacity: BotMath.clamp(1.2 * amount, 0, 1),
                                         strokeWidth: 6))
        }
        return EffectPose(x: pose.x, y: pose.y + 0.5 * pose.wiggle, rotation: pose.rotation)
    }

    private func renderBang(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let elapsed = (now - stateStartedAt) / 1000
        let enter = BotMath.cubicOut(BotMath.clamp(1.1 * amount, 0, 1))
        let shake = 2.2 * sin(42 * elapsed) * exp(-(elapsed.truncatingRemainder(dividingBy: 2.2) * 5.5))
        var transform = CGAffineTransform(translationX: 0, y: -26 - (1 - enter) * 70)
        // rotate(shake, HEAD_C, HEAD_C - 74)
        transform = transform.translatedBy(x: centre, y: centre - 74)
        transform = transform.rotated(by: shake * .pi / 180)
        transform = transform.translatedBy(x: -centre, y: -(centre - 74))
        transform = transform.translatedBy(x: centre, y: centre)
        let scale = BotMath.clamp(1.2 * amount, 0, 1)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -centre, y: -centre)
        shapes.append(BotMarkFrame.Shape(path: alertGlyph.copy(using: &transform) ?? alertGlyph,
                                     opacity: BotMath.clamp(1.5 * amount - 0.2, 0, 1)))
    }

    private func renderStandby(amount: Double, now: Double, into shapes: inout [BotMarkFrame.Shape]) {
        let centre = BotMarkLibrary.shared.headCentre
        let pulse = 0.5 + 0.5 * sin(0.0016 * now)
        shapes.append(circle(x: centre, y: centre, radius: 26 + 7 * pulse,
                             opacity: BotMath.cubicOut(amount) * (0.06 + 0.1 * pulse)))
        if amount < 0.995 {
            shapes.append(circle(x: centre, y: centre, radius: 104 - 88 * BotMath.cubicOut(amount),
                                 opacity: (1 - BotMath.cubicOut(amount)) * 0.5, strokeWidth: 2.4))
        }
    }

    private func circle(x: Double, y: Double, radius: Double, opacity: Double,
                        strokeWidth: Double? = nil) -> BotMarkFrame.Shape {
        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        return BotMarkFrame.Shape(path: CGPath(ellipseIn: rect, transform: nil),
                              opacity: opacity, strokeWidth: strokeWidth)
    }
}
