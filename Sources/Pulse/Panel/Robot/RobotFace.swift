// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Shapes, poses and timing ported from Agent Robot Avatar
// (https://github.com/CX-ArtLab/agent-robot-avatar, v0.7.1),
// Copyright (c) 2026 CX ART Lab, MIT License — see THIRD_PARTY_NOTICES.md.
// The character is CX ArtLab's design, not Pulse's.
import SwiftUI

/// The avatar's geometry, in its own 240 × 240 drawing space.
///
/// Everything here is a number from the original component so the robot in a
/// ring is the same robot: the head outline, where the eyes sit, the lids that
/// shape each expression, the antenna. `RobotMarkView` scales it to the ring.
enum RobotFace {
    /// The original's view box.
    static let canvas: CGFloat = 240
    /// Where each eye is centred before it looks anywhere.
    static let leftEyeX: Double = 86
    static let rightEyeX: Double = 154
    static let eyeY: Double = 126
    /// The antenna's resting centre and radius, outside the head.
    static let antennaHome = CGPoint(x: 120, y: 12)
    static let antennaRadius: CGFloat = 15
    /// How far the eyes may look, sideways and up or down. Not both at once:
    /// a diagonal look would push them past the head's rounded corners.
    static let lookReach = CGSize(width: 48, height: 34)
    /// The rectangle each eye's lids are clipped to, around the eye's centre.
    static let lidMask = CGRect(x: -40, y: -54, width: 80, height: 108)

    /// The part of the canvas the robot actually covers — head, antenna, and
    /// the room a lowered head moves into — which is what is fitted to a ring.
    static let drawnBounds = CGRect(x: 26, y: -3, width: 188, height: 214)

    /// One quarter of the head, from the top centre to the right centre, as
    /// offsets from the head's centre. The rest is the same quarter mirrored.
    private static let quarter: [(Double, Double)] = [
        (0, -100), (12.8, -99.95), (19.87, -99.8), (25.68, -99.56), (30.79, -99.22), (35.43, -98.78),
        (39.71, -98.24), (43.69, -97.6), (47.44, -96.86), (50.99, -96.03), (54.34, -95.1), (57.53, -94.07),
        (60.57, -92.93), (63.46, -91.7), (66.22, -90.37), (68.85, -88.94), (71.36, -87.41), (73.75, -85.78),
        (76.03, -84.04), (78.19, -82.2), (80.25, -80.25), (82.2, -78.19), (84.04, -76.03), (85.78, -73.75),
        (87.41, -71.36), (88.94, -68.85), (90.37, -66.22), (91.7, -63.46), (92.93, -60.57), (94.07, -57.53),
        (95.1, -54.34), (96.03, -50.99), (96.86, -47.44), (97.6, -43.69), (98.24, -39.71), (98.78, -35.43),
        (99.22, -30.79), (99.56, -25.68), (99.8, -19.87), (99.95, -12.8), (100, 0),
    ]

    /// The head's outline before it is placed: clockwise from the top
    /// centre, flattened to nine tenths of its height as the original does
    /// once its antenna is attached.
    private static let baseOutline: [CGPoint] = {
        let q = quarter
        var points = q.map { CGPoint(x: $0.0, y: $0.1) }
        points += q.dropLast().reversed().map { CGPoint(x: $0.0, y: -$0.1) }
        points += q.dropFirst().map { CGPoint(x: -$0.0, y: -$0.1) }
        points += q.dropFirst().dropLast().reversed().map { CGPoint(x: -$0.0, y: $0.1) }
        return flattened(points.map { CGPoint(x: 120 + $0.x, y: 120 + $0.y) })
    }()

    /// The head's outline as drawn for a shape, inset to 94% of the canvas.
    static func headOutline(_ shape: RobotShape = .standard) -> [CGPoint] {
        outlines[shape] ?? []
    }

    static func headPath(_ shape: RobotShape = .standard) -> Path {
        paths[shape] ?? Path()
    }

    private static let outlines: [RobotShape: [CGPoint]] = Dictionary(
        uniqueKeysWithValues: RobotShape.allCases.map { shape in
            (shape, rounded(baseOutline, to: shape.roundness)
                .map { CGPoint(x: 7.2 + $0.x * 0.94, y: 7.2 + $0.y * 0.94) })
        }
    )

    private static let paths: [RobotShape: Path] = outlines.mapValues { outline in
        var path = Path()
        path.addLines(outline)
        path.closeSubpath()
        return path
    }

    /// The original's `setHeadRoundness`: below 50 the outline eases towards
    /// a superellipse of exponent 10 (squarer), above it towards one of 2.2
    /// (rounder), each fitted to the same box.
    static func rounded(_ points: [CGPoint], to roundness: Double) -> [CGPoint] {
        let roundness = min(max(roundness, 0), 100)
        guard roundness != 50 else { return points }
        let exponent = roundness < 50 ? 10.0 : 2.2
        let amount = roundness < 50 ? (50 - roundness) / 50 : (roundness - 50) / 50

        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return points
        }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let halfW = max((maxX - minX) / 2, 0.001), halfH = max((maxY - minY) / 2, 0.001)

        return points.map { point in
            let angle = atan2(point.y - cy, point.x - cx)
            let xTerm = pow(abs(cos(angle)) / halfW, exponent)
            let yTerm = pow(abs(sin(angle)) / halfH, exponent)
            let denominator = pow(xTerm + yTerm, 1 / exponent)
            let radius = denominator > 0 ? 1 / denominator : 0
            let target = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
            return CGPoint(x: point.x + (target.x - point.x) * amount,
                           y: point.y + (target.y - point.y) * amount)
        }
    }

    /// The original's `flattenHeadPoints`: the top and bottom bands move in by
    /// the whole inset, the middle eases between them, so the sides stay
    /// straight and only the head's height changes.
    static func flattened(_ points: [CGPoint], heightScale: Double = 0.9) -> [CGPoint] {
        guard let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxY > minY else {
            return points
        }
        let height = maxY - minY
        let centre = (minY + maxY) / 2
        let inset = height * (1 - heightScale) / 2
        let upperLock = minY + height * 0.4
        let lowerLock = maxY - height * 0.4

        return points.map { point in
            var shift: CGFloat = 0
            if point.y <= upperLock {
                shift = inset
            } else if point.y < centre {
                shift = inset * RobotEase.smoothstep((centre - point.y) / max(0.001, centre - upperLock))
            } else if point.y >= lowerLock {
                shift = -inset
            } else if point.y > centre {
                shift = -inset * RobotEase.smoothstep((point.y - centre) / max(0.001, lowerLock - centre))
            }
            return CGPoint(x: point.x, y: point.y + shift)
        }
    }
}

/// The shape of both eyes: the eye's size, and where the upper and lower lids
/// cut across it. A tilted upper lid is what makes an eye sad.
struct RobotPose: Equatable {
    var width: Double
    var height: Double
    var topLid: Double
    var bottomLid: Double
    /// Degrees; the right eye's is the mirror of the left's.
    var leftTilt: Double = 0
    var rightTilt: Double = 0

    static let idle = RobotPose(width: 54, height: 58, topLid: -36, bottomLid: 36)
    static let happy = RobotPose(width: 58, height: 58, topLid: -36, bottomLid: 0)
    static let sad = RobotPose(width: 58, height: 58, topLid: -5, bottomLid: 36, leftTilt: -16, rightTilt: 16)
    static let sleepy = RobotPose(width: 58, height: 56, topLid: 0, bottomLid: 36)
    /// Sleepy's eye with the lids met in a thin slit.
    static let asleep = RobotPose(width: 58, height: 56, topLid: 7, bottomLid: 14)
    static let surprise = RobotPose(width: 68, height: 68, topLid: -40, bottomLid: 40)
    /// The brief reopening while falling asleep.
    static let peek = RobotPose(width: 54, height: 58, topLid: -22, bottomLid: 36)
}

extension RobotPose: RobotMixable {
    func mixed(with other: RobotPose, by t: Double) -> RobotPose {
        RobotPose(
            width: width.mixed(with: other.width, by: t),
            height: height.mixed(with: other.height, by: t),
            topLid: topLid.mixed(with: other.topLid, by: t),
            bottomLid: bottomLid.mixed(with: other.bottomLid, by: t),
            leftTilt: leftTilt.mixed(with: other.leftTilt, by: t),
            rightTilt: rightTilt.mixed(with: other.rightTilt, by: t)
        )
    }
}

/// Something a tween can move between.
protocol RobotMixable {
    func mixed(with other: Self, by t: Double) -> Self
}

extension Double: RobotMixable {
    func mixed(with other: Double, by t: Double) -> Double { self + (other - self) * t }
}

/// The original's easing curves.
enum RobotEase: Equatable {
    case linear
    case outQuint
    case inOutCubic
    /// Smoothstep.
    case smooth
    /// A CSS `cubic-bezier`, which is how the original moves the head.
    case bezier(Double, Double, Double, Double)

    /// The head's bob and nod.
    static let head = RobotEase.bezier(0.16, 1, 0.3, 1)
    /// The slower drop of a failing head.
    static let droop = RobotEase.bezier(0.32, 0, 0.24, 1)

    static func smoothstep(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    func callAsFunction(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .outQuint: return 1 - pow(1 - t, 5)
        case .inOutCubic: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .smooth: return Self.smoothstep(t)
        case let .bezier(x1, y1, x2, y2): return Self.bezier(t, x1, y1, x2, y2)
        }
    }

    /// y for a given x on a unit cubic Bézier, solved for x by bisection —
    /// a few dozen steps at thirty frames a second is nothing.
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func curve(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0, s = x
        for _ in 0..<24 {
            s = (low + high) / 2
            if curve(s, x1, x2) < x { low = s } else { high = s }
        }
        return curve(s, y1, y2)
    }
}

/// A value moving from one place to another over a stretch of time.
struct RobotTween<Value: RobotMixable> {
    var from: Value
    var to: Value
    var start: TimeInterval = 0
    var duration: TimeInterval = 0
    var ease: RobotEase = .outQuint

    init(_ value: Value) {
        from = value
        to = value
    }

    func value(at now: TimeInterval) -> Value {
        guard duration > 0 else { return to }
        return from.mixed(with: to, by: ease((now - start) / duration))
    }

    func isSettled(at now: TimeInterval) -> Bool { duration <= 0 || now - start >= duration }

    /// Heads for `target` from wherever it is now, so a change of mind
    /// mid-move does not jump.
    mutating func move(to target: Value, at now: TimeInterval, over duration: TimeInterval,
                       ease: RobotEase = .outQuint) {
        from = value(at: now)
        to = target
        start = now
        self.duration = duration
        self.ease = ease
    }
}

/// One drawn frame, in the avatar's 240-unit space.
struct RobotFrame: Equatable {
    struct Eye: Equatable {
        /// The eye's centre.
        var centre: CGPoint
        /// The white of the eye: half its width and half its height, centred
        /// `lift` below `centre`.
        var radii: CGSize
        var lift: CGFloat = 0
        /// Squashes the whole eye, lids and all — the waiting orbit's
        /// perspective.
        var scale = CGSize(width: 1, height: 1)
        var topLid: CGFloat
        var bottomLid: CGFloat
        /// Degrees.
        var tilt: CGFloat
    }

    var left: Eye
    var right: Eye
    /// How far the head has moved down (positive) or up.
    var headDrop: CGFloat
    /// About the head's centre: surprise swells it a little.
    var headScale: CGFloat = 1
    /// Degrees, about the head's centre.
    var headTilt: CGFloat
    var antenna: CGPoint
}
