import CoreGraphics
import Foundation

/// Ports of the upstream `geometry.js` helpers. Same formulas, same
/// constants; the only change is Swift types.
enum BotMarkGeometry {
    static func centroid(_ ring: [CGPoint]) -> CGPoint {
        var x = 0.0
        var y = 0.0
        for point in ring {
            x += point.x
            y += point.y
        }
        return CGPoint(x: x / Double(ring.count), y: y / Double(ring.count))
    }

    /// Point-by-point interpolation. Every ring in the data has the same
    /// count and the same angular order, which is what makes this work.
    static func lerpRing(_ from: [CGPoint], _ to: [CGPoint], _ amount: Double) -> [CGPoint] {
        guard from.count == to.count else { return to }
        var output = [CGPoint]()
        output.reserveCapacity(from.count)
        for index in from.indices {
            output.append(CGPoint(x: from[index].x + (to[index].x - from[index].x) * amount,
                                  y: from[index].y + (to[index].y - from[index].y) * amount))
        }
        return output
    }

    /// The straight-sided path, used for the eyes.
    static func ringPath(_ ring: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = ring.first else { return path }
        path.move(to: first)
        for point in ring.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// The smoothed path, used for a head that is blending or turning:
    /// Catmull-Rom tangents over the ring, emitted as cubic Béziers.
    static func ringOutline(_ ring: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard ring.count > 2 else { return ringPath(ring) }
        let count = ring.count
        path.move(to: ring[0])
        for index in 0..<count {
            let previous = ring[(index - 1 + count) % count]
            let point = ring[index]
            let next = ring[(index + 1) % count]
            let after = ring[(index + 2) % count]
            path.addCurve(
                to: next,
                control1: CGPoint(x: point.x + (next.x - previous.x) / 6,
                                  y: point.y + (next.y - previous.y) / 6),
                control2: CGPoint(x: next.x - (after.x - point.x) / 6,
                                  y: next.y - (after.y - point.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    /// How wide the silhouette is at height `y`, by scanning the ring's
    /// crossings. `headCentre` decides which side a crossing belongs to.
    static func spanAt(_ ring: [CGPoint], _ y: Double, headCentre: Double) -> (Double, Double) {
        var left = -Double.infinity
        var right = Double.infinity
        for index in ring.indices {
            let start = ring[index]
            let end = ring[(index + 1) % ring.count]
            if (start.y <= y) == (end.y <= y) { continue }
            let x = start.x + ((end.x - start.x) * (y - start.y)) / (end.y - start.y)
            if x <= headCentre { left = max(left, x) } else { right = min(right, x) }
        }
        return (left.isFinite ? left : headCentre, right.isFinite ? right : headCentre)
    }

    /// The same question answered from the shape's 160 pre-sampled spans,
    /// which is what the renderer uses whenever the shape is at rest.
    static func shapeSpanAt(_ shape: BotMarkShape, spanSamples: [(Double, Double)]?,
                            _ y: Double, headCentre: Double) -> (Double, Double) {
        guard let samples = spanSamples, !samples.isEmpty else {
            return spanAt(shape.ring, y, headCentre: headCentre)
        }
        let count = Double(samples.count)
        let position = BotMath.clamp(((y - shape.top) / (shape.bottom - shape.top)) * count - 0.5, 0, count - 1)
        let start = Int(position.rounded(.down))
        let end = min(start + 1, samples.count - 1)
        let amount = position - Double(start)
        return (samples[start].0 + (samples[end].0 - samples[start].0) * amount,
                samples[start].1 + (samples[end].1 - samples[start].1) * amount)
    }

    /// The radial profile of a solid at a given yaw, smoothed with the same
    /// five-tap binomial pass the upstream uses.
    private static func radialSolidProfile(_ solid: [[Double]], _ angle: Double) -> [Double] {
        let cosine = cos(angle)
        let sine = sin(angle)
        let count = 96
        var raw = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let theta = Double(index) / Double(count) * 2 * .pi
            let directionX = cos(theta)
            let directionY = sin(theta)
            var radius = 0.0
            for sphere in solid {
                let x = sphere[0], y = sphere[1], z = sphere[2], sphereRadius = sphere[3]
                let rotatedX = x * cosine + z * sine
                let projection = directionX * rotatedX + directionY * y
                let discriminant = projection * projection - (rotatedX * rotatedX + y * y) + sphereRadius * sphereRadius
                if discriminant > 0 { radius = max(radius, projection + discriminant.squareRoot()) }
            }
            raw[index] = radius
        }
        return smooth(raw)
    }

    private static func smooth(_ values: [Double]) -> [Double] {
        let count = values.count
        return (0..<count).map { index in
            // One named tap per line: written as a single sum, Swift 6.2.4
            // (Xcode 26.3) gives up type-checking it and the build fails.
            let twoBefore = values[(index - 2 + count) % count]
            let before = values[(index - 1 + count) % count]
            let centre = values[index]
            let after = values[(index + 1) % count]
            let twoAfter = values[(index + 2) % count]
            return (twoBefore + 4 * before + 6 * centre + 4 * after + twoAfter) / 16
        }
    }

    /// The un-yawed profile of each solid shape, solved once. Written only
    /// from the main-actor render path.
    private nonisolated(unsafe) static var solidBaselines: [String: [Double]] = [:]

    /// The ring as it looks yawed by `angle`. Flat-sided and solid shapes
    /// deform; the rest are unchanged, which is why turning a blob only
    /// moves its eyes.
    static func turnedShapeRing(_ shape: BotMarkShape, identifier: String, angle: Double,
                                headCentre: Double) -> [CGPoint] {
        if let solid = shape.solid {
            let baseline: [Double]
            if let cached = solidBaselines[identifier] {
                baseline = cached
            } else {
                baseline = radialSolidProfile(solid, 0)
                solidBaselines[identifier] = baseline
            }
            var profile = radialSolidProfile(solid, angle).enumerated().map { index, value in
                BotMath.clamp((value + 12) / (baseline[index] + 12), 0.32, 1.5)
            }
            for _ in 0..<3 { profile = smooth(profile) }
            return shape.ring.enumerated().map { index, point in
                CGPoint(x: headCentre + (point.x - headCentre) * profile[index],
                        y: headCentre + (point.y - headCentre) * profile[index])
            }
        }
        if shape.sides > 0 {
            let segment = 2 * Double.pi / Double(shape.sides)
            let wrapped = angle.truncatingRemainder(dividingBy: segment)
            let positive = (wrapped + segment).truncatingRemainder(dividingBy: segment)
            let factor = 1 + (cos(positive - segment / 2) / cos(segment / 2) - 1) * 0.45
            return shape.ring.map { CGPoint(x: headCentre + ($0.x - headCentre) * factor, y: $0.y) }
        }
        return shape.ring
    }
}
