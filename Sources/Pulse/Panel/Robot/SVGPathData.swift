// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CoreGraphics
import Foundation
import SwiftUI

/// SVG path data (`d`) to a `Path`: the whole command set, absolute and
/// relative, with the compact number forms an optimiser writes — `-.23.05` is
/// two numbers, and an arc's flags may run together as `11`.
///
/// Written for Open Bot Avatar's frames (`BotAvatarEngine`), which hand over
/// every outline as path data. Malformed data ends the path where it stops
/// making sense rather than throwing: a frame is redrawn a moment later, and a
/// half-drawn shape is better than none.
enum SVGPathData {
    static func path(_ data: String) -> Path {
        Path(cgPath(data))
    }

    static func cgPath(_ data: String) -> CGPath {
        var scanner = Scanner(data)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        // The previous segment's second control point, for S and T.
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard let byte = scanner.peek else { break }
            if Scanner.isCommand(byte) {
                command = byte
                scanner.advance()
            } else if command == 0 {
                break
            }
            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x, y: origin.y + y) }

            switch command | 0x20 {
            case UInt8(ascii: "m"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                start = current
                path.move(to: current)
                // Further pairs after a move are lines.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "l"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "c"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = point(x1, y1), c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil
            case UInt8(ascii: "s"):
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil
            case UInt8(ascii: "q"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let control = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuad = control; lastCubic = nil
            case UInt8(ascii: "t"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let control = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuad = control; lastCubic = nil
            case UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let end = point(x, y)
                addArc(to: path, from: current, to: end, radii: CGSize(width: rx, height: ry),
                       rotation: rotation, largeArc: large, sweep: sweep)
                current = end
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = start
                lastCubic = nil; lastQuad = nil
                // A close takes no numbers; a number after it is malformed.
                scanner.skipSeparators()
                if let next = scanner.peek, !Scanner.isCommand(next) { return path }
            default:
                return path
            }
        }
        return path
    }

    /// An elliptical arc as cubic Béziers, by the conversion in the SVG
    /// specification's implementation notes (F.6.5 and F.6.6).
    private static func addArc(to path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, radii: CGSize,
                               rotation degrees: CGFloat, largeArc: Bool, sweep: Bool) {
        var rx = abs(radii.width), ry = abs(radii.height)
        guard rx > 0, ry > 0, p1 != p2 else {
            if p1 != p2 { path.addLine(to: p2) }
            return
        }
        let phi = degrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Radii too small for the endpoints are scaled up until they reach.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var factor = (max(numerator, 0) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cxp = factor * rx * y1p / ry
        let cyp = -factor * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            return sign * acos(min(max(dot / length, -1), 1))
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // At most a quarter turn per curve keeps each one close to the arc.
        let segments = max(Int((abs(delta) / (.pi / 2)).rounded(.up)), 1)
        let step = delta / CGFloat(segments)
        let kappa = 4 / 3 * tan(step / 4)
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta1
        for index in 0..<segments {
            let next = t + step
            let from = onEllipse(t), to = index == segments - 1 ? p2 : onEllipse(next)
            let d1 = derivative(t), d2 = derivative(next)
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x + kappa * d1.x, y: from.y + kappa * d1.y),
                          control2: CGPoint(x: to.x - kappa * d2.x, y: to.y - kappa * d2.y))
            t = next
        }
    }

    /// Reads numbers and flags off the path data's bytes, which end in a
    /// zero so `strtod` can read straight out of them.
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(_ data: String) {
            var bytes = Array(data.utf8)
            bytes.append(0)
            self.bytes = bytes
        }

        var peek: UInt8? { index < bytes.count - 1 ? bytes[index] : nil }
        mutating func advance() { index += 1 }

        static func isCommand(_ byte: UInt8) -> Bool {
            switch byte | 0x20 {
            case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"),
                 UInt8(ascii: "c"), UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"),
                 UInt8(ascii: "a"), UInt8(ascii: "z"):
                // `e` and `E` belong to numbers and are not in this set.
                return true
            default:
                return false
            }
        }

        mutating func skipSeparators() {
            while let byte = peek, byte == 0x20 || byte == 0x2C || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                advance()
            }
        }

        /// A number: sign, digits, one point, an exponent. A second point or a
        /// sign starts the next number, which is where `strtod` stops too.
        /// The process stays in the C locale (nothing here calls `setlocale`), so
        /// the point is a point whatever the user's decimal separator.
        mutating func number() -> CGFloat? {
            skipSeparators()
            // Only what a path number can start with: `strtod` would also
            // take `inf`, `nan` and hexadecimal.
            guard let first = peek,
                  (first >= 0x30 && first <= 0x39) || first == UInt8(ascii: "-")
                    || first == UInt8(ascii: "+") || first == UInt8(ascii: ".") else { return nil }
            let start = index
            let (value, read): (Double, Int) = bytes.withUnsafeBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { base in
                    var end: UnsafeMutablePointer<CChar>?
                    let value = strtod(base + start, &end)
                    return (value, end.map { UnsafePointer($0) - (base + start) } ?? 0)
                }
            }
            guard read > 0 else { return nil }
            index += read
            return CGFloat(value)
        }

        /// An arc flag: a single 0 or 1, which may touch what follows it.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let byte = peek, byte == UInt8(ascii: "0") || byte == UInt8(ascii: "1") else { return nil }
            advance()
            return byte == UInt8(ascii: "1")
        }
    }
}
