// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Ported from Open Bot Avatar's fluffy renderer (`dist/dom/fluffy/renderer.js`
// and `socket.js`, https://github.com/DominikScholz/open-bot-avatar, v0.4.0),
// Copyright (c) 2026 Dominik Scholz, MIT License — see THIRD_PARTY_NOTICES.md.
import CoreGraphics
import Foundation

/// The fluffy shaders' textures, made as the original makes them. The
/// original draws two of them on a 2D canvas, which JavaScriptCore has not
/// got, so these are ports to Core Graphics: the same seeded strokes, the same
/// warp and the same distance sweep.
enum FluffyTextures {
    /// Pixels a side of an eye's distance tile (`SOCKET_TILE`).
    static let socketTile = 96
    /// How far around an eye the coat is pressed down, viewBox units, and
    /// the range of the distance field (`SOCKET_PAD`).
    static let socketPad = 3.8

    /// The original's seeded generator, so a coat is the same every launch.
    struct Random {
        var seed: UInt32
        mutating func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
    }

    /// `fiberTile`: a tileable 128-pixel square of short curved fibers, for
    /// the compressed pile around the eye sockets. One grey byte a pixel.
    static func fiberTile() -> [UInt8] {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            // A canvas counts down from the top.
            context.translateBy(x: 0, y: CGFloat(size))
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(gray: 0x25 / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.setLineCap(.round)
            var random = Random(seed: 9213)
            let side = Double(size)
            for _ in 0..<1400 {
                let x = random.next() * side, y = random.next() * side
                let angle = 2.4 * sin(y * .pi / 32) + 1.4 * cos(x * .pi / 32) + (random.next() - 0.5) * 3.3
                let dx = cos(angle), dy = sin(angle), length = 3 + random.next() * 8
                let curl = (random.next() - 0.5) * length
                let grey = (55 + 200 * random.next()).rounded()
                context.setStrokeColor(gray: grey / 255, alpha: 1)
                context.setLineWidth(0.8 + random.next() * 1.5)
                // Each fiber on every neighbouring tile it reaches into, so the edges wrap.
                for ox in [-side, 0, side] {
                    for oy in [-side, 0, side] {
                        if x + ox < -12 || x + ox > side + 12 || y + oy < -12 || y + oy > side + 12 { continue }
                        context.beginPath()
                        context.move(to: CGPoint(x: x + ox, y: y + oy))
                        context.addQuadCurve(
                            to: CGPoint(x: x + ox + dx * length, y: y + oy + dy * length),
                            control: CGPoint(x: x + ox + dx * length * 0.5 - dy * curl,
                                             y: y + oy + dy * length * 0.5 + dx * curl)
                        )
                        context.strokePath()
                    }
                }
            }
        }
        return pixels
    }

    /// `rootVolume`: random root density in a repeating cube, one byte a cell.
    static func rootVolume(side: Int) -> [UInt8] {
        var seed: UInt32 = 73021
        return (0..<(side * side * side)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(seed >> 24)
        }
    }

    /// An eye's mark as the original's `EyeMark` gives it, in face coordinates.
    enum EyeMark: Sendable, Equatable {
        case pill(CGRect, radius: CGFloat)
        case arc(String, width: CGFloat)
        case path(String)
    }

    /// Where an eye's tile sits, as the original's `socketRegion` measures it.
    struct SocketRegion: Sendable, Equatable {
        var cx, cy, w, h, span: Double
        /// `exposedHeight(w, h)`.
        var exposed: Double
    }

    /// `socketTile`: signed distance to the eye's seated contour, in units of
    /// 2 × `socketPad` around 0.5 (inside is below), one byte a pixel.
    static func socketTile(_ mark: EyeMark, region: SocketRegion) -> [UInt8] {
        let size = socketTile
        let (cx, cy, w, h, span) = (region.cx, region.cy, region.w, region.h, region.span)
        let scale = Double(size) / span
        let exposure = region.exposed
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(size))
            context.scaleBy(x: 1, y: -1)
            context.concatenate(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                                  tx: Double(size) / 2 - cx * scale, ty: Double(size) / 2 - cy * scale))
            context.setLineCap(.round)
            context.setFillColor(gray: 1, alpha: 1)
            context.setStrokeColor(gray: 1, alpha: 1)
            // The surrounding nap hides a little of the top and bottom of the bead.
            context.translateBy(x: cx, y: cy)
            context.scaleBy(x: 1, y: exposure)
            context.translateBy(x: -cx, y: -cy)
            switch mark {
            case let .path(data):
                context.addPath(SVGPathData.cgPath(data))
                context.fillPath()
            case let .arc(data, width):
                context.setLineWidth(width)
                context.addPath(SVGPathData.cgPath(data))
                context.strokePath()
            case let .pill(rect, radius):
                let r = max(0, min(radius, rect.width / 2, rect.height / 2))
                context.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
                context.fillPath()
            }
        }
        // Round out the straight sides of the stadium into a soft bead profile.
        var coverage = [UInt8](repeating: 0, count: size * size)
        let cap = min(1, w / h)
        let half = Double(size) / 2
        // Unchecked buffers: this runs on every frame an eye changes shape.
        rgba.withUnsafeBufferPointer { rgba in
            coverage.withUnsafeMutableBufferPointer { coverage in
                for y in 0..<size {
                    let v = min(0.9999, abs((Double(y) + 0.5 - half) / ((scale * h * exposure) / 2)))
                    let capY = max(0, (v - 1 + cap) / cap)
                    let stadium = (1 - capY * capY).squareRoot()
                    let oval = pow(1 - pow(v, 2.2), 1 / 2.2)
                    let taper = h > w ? min(1, oval / stadium) : 1
                    // A slight cant in the seated oval is most visible on an open eye.
                    let cant = 0.04 * max(0, 1 - cap) * (Double(y) + 0.5 - half)
                    for x in 0..<size {
                        let source = (Double(x) + 0.5 - half - cant) / taper + half - 0.5
                        let i = Int(source.rounded(.down))
                        if i < 0 || i + 1 >= size { continue }
                        let offset = 4 * (y * size + i) + 3
                        let a = Double(rgba[offset]), b = Double(rgba[offset + 4])
                        coverage[y * size + x] = UInt8(max(0, min(255, (a + (b - a) * (source - Double(i))).rounded())))
                    }
                }
            }
        }
        // Start on each side of the antialiased boundary, then sweep the
        // distance out both ways. Single precision, as the original's
        // Float32Array.
        var distance = [Float](repeating: Float(size), count: size * size)
        let diagonal = Float(2.0.squareRoot())
        coverage.withUnsafeBufferPointer { coverage in
            distance.withUnsafeMutableBufferPointer { distance in
                for i in (size + 1)..<(distance.count - size - 1) {
                    let a = Float(coverage[i]) / 255
                    let inside = a >= 0.5
                    if (a > 0 && a < 1)
                        || (coverage[i - 1] >= 128) != inside || (coverage[i + 1] >= 128) != inside
                        || (coverage[i - size] >= 128) != inside || (coverage[i + size] >= 128) != inside {
                        distance[i] = abs(a - 0.5)
                    }
                }
                for step in [1, -1] {
                    for j in 1..<(size - 1) {
                        for k in 1..<(size - 1) {
                            let i = step == 1 ? j * size + k : (size - 1 - j) * size + size - 1 - k
                            let previous = i - size * step
                            // Two at a time: the variadic `min` builds an array per call.
                            let straight = min(distance[i - step], distance[previous]) + 1
                            let slanted = min(distance[previous - 1], distance[previous + 1]) + diagonal
                            distance[i] = min(distance[i], min(straight, slanted))
                        }
                    }
                }
            }
        }
        var tile = [UInt8](repeating: 0, count: size * size)
        for i in 0..<tile.count {
            let signed = Double(coverage[i] >= 128 ? -distance[i] : distance[i]) / scale
            tile[i] = UInt8((255 * max(0, min(1, 0.5 + signed / (2 * socketPad)))).rounded())
        }
        return tile
    }
}
