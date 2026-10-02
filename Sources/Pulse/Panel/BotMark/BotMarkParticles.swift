// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import SwiftUI

/// The particle layer, ported from the upstream `particle-system.js`.
///
/// Two kinds live here. A **burst** is ordinary confetti: spawned on a ring
/// around the head, thrown outward, dragged and pulled down, drawn as a dot,
/// a streak or a star. An **orbit** particle only exists while the character
/// is spinning: it rides a tilted, rolled circle around the head and drags a
/// tapered ribbon behind it, coloured by a hue that travels along the ribbon.
/// The ribbon is split front/back by the particle's depth, so it passes
/// behind the head and comes back out.
final class BotMarkParticles {
    private static let colors = [
        BotMarkPalette.rgb(0xf9705c), BotMarkPalette.rgb(0x5b95f0), BotMarkPalette.rgb(0x3fbe86),
        BotMarkPalette.rgb(0xf5b13f), BotMarkPalette.rgb(0x9a72ee), BotMarkPalette.rgb(0x35c3bd),
    ]

    private struct Orbit {
        var angle: Double
        var angularVelocity: Double
        var tilt: Double
        var roll: Double
        var radius: Double
        var radiusVelocity: Double
        var follow: Double
        var carry: Double
        var arc: Double
    }

    private struct TrailPoint {
        var x: Double
        var y: Double
        var angle: Double
        var z: Double
    }

    private final class Particle {
        var x = 0.0
        var y = 0.0
        var vx = 0.0
        var vy = 0.0
        var returnAmount = 0.0
        var life = 0.0
        var maximum = 1.0
        var radius = 4.0
        var rotation = 0.0
        var rotationSpeed = 0.0
        var curl = 0.0
        var color = Color.white
        var round = true
        var isStar = false
        var hue = 0.0
        var hueSpan = 0.0
        var hueVelocity = 0.0
        var orbit: Orbit?
        var history: [TrailPoint] = []
    }

    private struct Layout {
        var tilt: Double
        var roll: Double
    }

    private let headCentre = BotMarkLibrary.shared.headCentre
    private var particles: [Particle] = []
    private var spinAngle = 0.0
    private var lastSpinAngle = 0.0
    private var angularVelocity = 0.0
    private var trailActive = false
    private var emissionQueue: [(at: Double, index: Int)] = []
    private var orbitLayouts: [Layout] = []
    private var hue = 0.0
    private var orbitCount = 4
    private var sizeScale = 1.0
    private var wideStyle = false
    private var beltRadius = BotMarkLibrary.shared.headCentre

    private(set) var back: [BotMarkFrame.Painted] = []
    private(set) var front: [BotMarkFrame.Painted] = []

    init() {
        spinAngle = BotMath.random(0, 2 * .pi)
    }

    private func clear() {
        particles = []
    }

    /// A new spin picks a new set of orbit planes, so two spins never look
    /// like the same animation.
    private func resetOrbitStyle(layoutCount: Int = 1) {
        let roll = BotMath.random(-0.85, 0.85)
        orbitLayouts = (0..<layoutCount).map { index in
            Layout(tilt: BotMath.random(0.16, 0.5),
                   roll: roll + Double(index) * .pi / Double(layoutCount) + BotMath.random(-0.12, 0.12))
        }
        orbitCount = layoutCount > 1 ? 3 * layoutCount : Int(BotMath.random(3, 5).rounded())
        hue = BotMath.random(0, 360)
    }

    private func spawnOrbitParticle(angle: Double, direction: Double, index: Int) {
        guard particles.count <= 110 else { return }
        if orbitLayouts.isEmpty { resetOrbitStyle() }
        let layout = orbitLayouts[index % orbitLayouts.count]
        let countPerLayout = max(Int((Double(orbitCount) / Double(orbitLayouts.count)).rounded(.up)) - 1, 1)
        let baseRadius = 116 * (beltRadius / headCentre)
        let particle = Particle()
        particle.x = headCentre
        particle.y = headCentre
        particle.maximum = 9
        particle.radius = orbitCount <= 3 ? BotMath.random(8, 10.5)
            : orbitCount == 4 ? BotMath.random(6.6, 8.6) : BotMath.random(5.6, 7.4)
        particle.rotation = BotMath.random(0, 360)
        particle.rotationSpeed = BotMath.random(-240, 240)
        particle.color = Self.colors.randomElement() ?? .white
        particle.hue = hue + 360 * Double(index) / Double(max(orbitCount, 1)) + BotMath.random(-14, 14)
        particle.hueSpan = BotMath.random(45, 95) * (Double.random(in: 0...1) < 0.5 ? 1 : -1)
        particle.hueVelocity = BotMath.random(18, 42) * (Double.random(in: 0...1) < 0.5 ? 1 : -1)
        particle.orbit = Orbit(
            angle: angle,
            angularVelocity: direction * BotMath.random(0.5, 1.1),
            tilt: layout.tilt + BotMath.random(-0.04, 0.04),
            roll: layout.roll + BotMath.random(-0.05, 0.05),
            radius: baseRadius + Double(index / orbitLayouts.count) * (38 / Double(countPerLayout))
                + BotMath.random(-1.5, 1.5),
            radiusVelocity: BotMath.random(0, 2.5),
            follow: BotMath.random(0.74, 0.94),
            carry: 0,
            arc: BotMath.random(2.2, 3.4))
        particles.append(particle)
    }

    /// Confetti. Used when the bot wakes and when the body shape changes.
    func burst(count: Int = 20, force: Double = 1, curl: Double = 0) {
        guard particles.count <= 120 else { return }
        for index in 0..<count {
            let angle = Double(index) / Double(count) * 2 * .pi + BotMath.random(-0.35, 0.35)
            let distance = BotMath.random(96, 116) * (beltRadius / headCentre)
            let speed = BotMath.random(170, 360) * force
            let tangentX = -sin(angle)
            let tangentY = cos(angle)
            let curlVelocity = curl * speed * 0.2
            let isStar = Double.random(in: 0...1) < 0.18
            let particle = Particle()
            particle.x = headCentre + cos(angle) * distance
            particle.y = headCentre + sin(angle) * distance
            particle.vx = cos(angle) * speed + tangentX * curlVelocity
            particle.vy = sin(angle) * speed + tangentY * curlVelocity - BotMath.random(20, 75)
            particle.maximum = BotMath.random(0.45, 0.85)
            particle.radius = isStar ? BotMath.random(4, 7) : BotMath.random(3.5, 8)
            particle.rotation = BotMath.random(0, 360)
            particle.rotationSpeed = BotMath.random(-260, 260)
            particle.isStar = isStar
            particle.round = !isStar && Double.random(in: 0...1) < 0.3
            particle.color = isStar ? BotMarkLibrary.shared.starGold : (Self.colors.randomElement() ?? .white)
            particles.append(particle)
        }
    }

    private func projectOrbit(_ orbit: Orbit, _ angle: Double) -> CGPoint {
        let horizontal = orbit.radius * sin(angle)
        let vertical = -orbit.radius * cos(angle) * sin(orbit.tilt)
        let cosine = cos(orbit.roll)
        let sine = sin(orbit.roll)
        return CGPoint(x: headCentre + horizontal * cosine - vertical * sine,
                       y: headCentre + horizontal * sine + vertical * cosine)
    }

    private func orbitDepth(_ orbit: Orbit, _ angle: Double) -> Double {
        cos(angle) * cos(orbit.tilt)
    }

    /// The tapered ribbon, split into the part in front of the head and the
    /// part behind it.
    private func trailPaths(_ points: [TrailPoint], width: Double) -> (front: CGPath?, back: CGPath?) {
        guard points.count >= 2 else { return (nil, nil) }
        var length = 0.0
        for index in 1..<points.count {
            length += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        guard length >= 2 else { return (nil, nil) }
        let actualWidth = min(width, 0.34 * length)
        var normals: [CGPoint] = []
        for index in points.indices {
            let previous = points[index > 0 ? index - 1 : 0]
            let next = points[index < points.count - 1 ? index + 1 : points.count - 1]
            var dx = next.x - previous.x
            var dy = next.y - previous.y
            let magnitude = hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)
            dx /= magnitude
            dy /= magnitude
            // The ribbon is half as wide at the tail as at the head.
            let halfWidth = actualWidth * (0.5 + Double(index) / Double(points.count - 1) * 0.5) / 2
            normals.append(CGPoint(x: -dy * halfWidth, y: dx * halfWidth))
        }

        func segment(_ start: Int, _ end: Int) -> CGPath {
            let path = CGMutablePath()
            for index in start...end {
                let point = CGPoint(x: points[index].x + normals[index].x,
                                    y: points[index].y + normals[index].y)
                if index == start { path.move(to: point) } else { path.addLine(to: point) }
            }
            if end == points.count - 1 { addCap(path, at: end) }
            for index in stride(from: end, through: start, by: -1) {
                path.addLine(to: CGPoint(x: points[index].x - normals[index].x,
                                         y: points[index].y - normals[index].y))
            }
            if start == 0 { addCap(path, at: 0) }
            path.closeSubpath()
            return path
        }

        func addCap(_ path: CGMutablePath, at index: Int) {
            let normal = normals[index]
            let radius = max(hypot(normal.x, normal.y), 0.2)
            let start = atan2(normal.y, normal.x)
            // The upstream cap is an SVG arc with sweep 0: the short way
            // round, in the negative direction.
            path.addArc(center: CGPoint(x: points[index].x, y: points[index].y),
                        radius: radius, startAngle: start, endAngle: start - .pi, clockwise: true)
        }

        let frontPath = CGMutablePath()
        let backPath = CGMutablePath()
        var cursor = 0
        while cursor < points.count {
            let isFront = points[cursor].z >= 0
            var end = cursor
            while end + 1 < points.count && (points[end + 1].z >= 0) == isFront { end += 1 }
            let segmentStart = max(cursor - 1, 0)
            let segmentEnd = min(end + 1, points.count - 1)
            if segmentEnd > segmentStart {
                let piece = segment(segmentStart, segmentEnd)
                if isFront { frontPath.addPath(piece) } else { backPath.addPath(piece) }
            }
            cursor = end + 1
        }
        return (frontPath.isEmpty ? nil : frontPath, backPath.isEmpty ? nil : backPath)
    }

    func update(now: Double, delta: Double, spinAngle newSpinAngle: Double,
                sizeScale: Double, wideStyle: Bool, enabled: Bool, beltRadius: Double) {
        self.sizeScale = sizeScale
        self.spinAngle = newSpinAngle
        self.wideStyle = wideStyle
        self.beltRadius = beltRadius
        back = []
        front = []
        if !enabled {
            if !particles.isEmpty { clear() }
            emissionQueue = []
            trailActive = false
            angularVelocity = 0
            lastSpinAngle = spinAngle
            return
        }

        var difference = spinAngle - lastSpinAngle
        if !difference.isFinite || abs(difference) > 1.2 { difference = 0 }
        lastSpinAngle = spinAngle
        let wasSpinning = abs(angularVelocity) >= 0.9
        angularVelocity = delta > 0 ? difference / delta : 0
        let isSpinning = abs(angularVelocity) >= 0.9
        if !wasSpinning && isSpinning {
            resetOrbitStyle(layoutCount: wideStyle ? 3 : 1)
            trailActive = false
        }
        if wasSpinning && !isSpinning { emissionQueue = [] }
        if !trailActive && abs(angularVelocity) >= 5 {
            trailActive = true
            emissionQueue = (0..<orbitCount).map { index in
                (at: now + Double(index) * BotMath.random(55, 105), index: index)
            }
        }
        while let first = emissionQueue.first, now >= first.at {
            emissionQueue.removeFirst()
            spawnOrbitParticle(angle: spinAngle - BotMath.random(0, 0.18),
                               direction: angularVelocity < 0 ? -1 : 1,
                               index: first.index)
        }

        var alive: [Particle] = []
        for particle in particles {
            particle.life += delta
            let progress = BotMath.clamp(particle.life / particle.maximum, 0, 1)
            if particle.orbit != nil {
                let shouldReturn = !isSpinning || progress > 0.55
                particle.returnAmount = BotMath.clamp(
                    particle.returnAmount + (shouldReturn ? delta / 0.5 : -delta / 0.35), 0, 1)
                if particle.returnAmount >= 1 { continue }
            } else if particle.life >= particle.maximum {
                continue
            }

            let opacity = particle.orbit != nil
                ? min(1, particle.life / 0.26)
                : (progress < 0.1 ? progress / 0.1 : pow(1 - (progress - 0.1) / 0.9, 1.7))

            if var orbit = particle.orbit {
                if isSpinning {
                    orbit.carry = angularVelocity * orbit.follow
                    orbit.angle += angularVelocity * delta * orbit.follow + orbit.angularVelocity * delta
                } else {
                    orbit.angle += (orbit.carry + orbit.angularVelocity) * delta
                    orbit.carry *= exp(-2.6 * delta)
                    orbit.angularVelocity *= exp(-2.6 * delta)
                }
                orbit.radius += orbit.radiusVelocity * delta
                let position = projectOrbit(orbit, orbit.angle)
                particle.x = position.x
                particle.y = position.y
                let depth = orbitDepth(orbit, orbit.angle)
                let depthScale = 0.72 + 0.28 * BotMath.clamp(depth, 0, 1)
                let enter = min(particle.life / 0.34, 1)
                let smoothEnter = enter * enter * (3 - 2 * enter)
                let width = max(particle.radius * depthScale * 1.7 * sizeScale * smoothEnter
                                * (1 - 0.72 * particle.returnAmount * particle.returnAmount), 0.5)

                // Subdivide the step so a fast spin still draws a curve.
                let previousAngle = particle.history.last?.angle ?? orbit.angle
                let angleChange = orbit.angle - previousAngle
                let subdivisions = min(Int((abs(angleChange) / 0.09).rounded(.up)), 24)
                if subdivisions > 0 {
                    for index in 1...subdivisions {
                        let angle = previousAngle + angleChange * Double(index) / Double(subdivisions)
                        let point = projectOrbit(orbit, angle)
                        particle.history.append(TrailPoint(x: point.x, y: point.y, angle: angle,
                                                           z: orbitDepth(orbit, angle)))
                    }
                }
                if particle.history.isEmpty {
                    particle.history.append(TrailPoint(x: particle.x, y: particle.y,
                                                       angle: orbit.angle, z: depth))
                }
                let arc = orbit.arc * (1 - particle.returnAmount * particle.returnAmount
                                       * (3 - 2 * particle.returnAmount))
                while particle.history.count > 2,
                      abs(orbit.angle - particle.history[0].angle) > arc {
                    particle.history.removeFirst()
                }
                let excess = abs(orbit.angle - particle.history[0].angle) - arc
                if particle.history.count >= 2, excess > 0 {
                    let direction: Double = orbit.angle - particle.history[0].angle < 0 ? -1 : 1
                    let angle = particle.history[0].angle + direction * excess
                    let point = projectOrbit(orbit, angle)
                    particle.history[0] = TrailPoint(x: point.x, y: point.y, angle: angle,
                                                     z: orbitDepth(orbit, angle))
                }
                if particle.history.count > 48 {
                    particle.history.removeFirst(particle.history.count - 48)
                }
                if particle.history.count >= 2 {
                    let paths = trailPaths(particle.history, width: width)
                    let travelling = particle.hue + particle.hueVelocity * particle.life
                    let stops = (0..<5).map { index -> Color in
                        let position = Double(index) / 4
                        let value = travelling + position * particle.hueSpan
                        return BotMarkPalette.hsl(degrees: value, saturation: 0.56,
                                                  lightness: 0.56 + 0.11 * position)
                    }
                    let from = CGPoint(x: particle.history[0].x, y: particle.history[0].y)
                    let to = CGPoint(x: particle.history[particle.history.count - 1].x,
                                     y: particle.history[particle.history.count - 1].y)
                    if let path = paths.back {
                        back.append(BotMarkFrame.Painted(path: path, opacity: opacity,
                                                     paint: .gradient(stops, from, to)))
                    }
                    if let path = paths.front {
                        front.append(BotMarkFrame.Painted(path: path, opacity: opacity,
                                                      paint: .gradient(stops, from, to)))
                    }
                }
                particle.orbit = orbit
                alive.append(particle)
                continue
            }

            if particle.curl != 0 {
                let cosine = cos(particle.curl * delta)
                let sine = sin(particle.curl * delta)
                let vx = particle.vx * cosine - particle.vy * sine
                let vy = particle.vx * sine + particle.vy * cosine
                particle.vx = vx
                particle.vy = vy
            }
            particle.x += particle.vx * delta
            particle.y += particle.vy * delta
            let drag = pow(0.94, 60 * delta)
            particle.vx *= drag
            particle.vy = particle.vy * drag + 40 * delta
            let size = max(particle.radius * (1 - 0.4 * progress), 0.5)

            if particle.isStar {
                particle.rotation += particle.rotationSpeed * delta
                var transform = CGAffineTransform(translationX: particle.x, y: particle.y)
                transform = transform.rotated(by: particle.rotation * .pi / 180)
                transform = transform.scaledBy(x: size, y: size)
                if let path = BotMarkLibrary.shared.starPath.copy(using: &transform) {
                    back.append(BotMarkFrame.Painted(path: path, opacity: opacity,
                                                 paint: .solid(particle.color)))
                }
            } else if particle.round {
                let rect = CGRect(x: particle.x - size, y: particle.y - size,
                                  width: size * 2, height: size * 2)
                back.append(BotMarkFrame.Painted(path: CGPath(ellipseIn: rect, transform: nil),
                                             opacity: opacity, paint: .solid(particle.color)))
            } else {
                // A streak: the faster it goes, the longer it draws.
                let width = max(2 * size, min(0.05 * hypot(particle.vx, particle.vy), 30))
                let height = 1.5 * size
                let rect = CGRect(x: particle.x - width / 2, y: particle.y - height / 2,
                                  width: width, height: height)
                let rounded = CGPath(roundedRect: rect, cornerWidth: height / 2,
                                     cornerHeight: height / 2, transform: nil)
                var transform = CGAffineTransform(translationX: particle.x, y: particle.y)
                    .rotated(by: atan2(particle.vy, particle.vx))
                    .translatedBy(x: -particle.x, y: -particle.y)
                if let path = rounded.copy(using: &transform) {
                    back.append(BotMarkFrame.Painted(path: path, opacity: opacity,
                                                 paint: .solid(particle.color)))
                }
            }
            alive.append(particle)
        }
        particles = alive
    }
}

/// The particle palette's two colour conversions.
///
/// **Not an `extension Color`.** `Color(hex:)` is the single most likely
/// name for a later helper in this app to claim, and a second one would be a
/// redeclaration rather than a shadow.
enum BotMarkPalette {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255,
              green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255)
    }

    /// CSS `hsl()`, which is not SwiftUI's HSB.
    static func hsl(degrees: Double, saturation: Double, lightness: Double) -> Color {
        let hue = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 60
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let second = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch Int(hue) {
        case 0: (red, green, blue) = (chroma, second, 0)
        case 1: (red, green, blue) = (second, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, second)
        case 3: (red, green, blue) = (0, second, chroma)
        case 4: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        return Color(red: red + match, green: green + match, blue: blue + match)
    }
}
