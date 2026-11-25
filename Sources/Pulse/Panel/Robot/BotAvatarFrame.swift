// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Frames of Open Bot Avatar (https://github.com/DominikScholz/open-bot-avatar,
// v0.4.0), Copyright (c) 2026 Dominik Scholz, MIT License — see
// THIRD_PARTY_NOTICES.md. The fluffy compositing follows its `dom/paint.js`.
import SwiftUI

/// One frame of a figure, as `liveFrame` lists it: shapes back to front in a
/// 0 0 100 100 box, each with its own matrix, all under `root`.
struct BotAvatarFrame: Sendable {
    enum Shape: Sendable {
        /// A cross-section of the body: filled in the body's colour.
        case slice(Path, evenOdd: Bool, CGAffineTransform)
        /// A piece of `thinking`'s dots or `blocked`'s exclamation mark, in
        /// place of the body: filled in the body's colour, or in fluffy drawn
        /// as a pompom (`sprite`) once one is rendered.
        case mark(Path, evenOdd: Bool, box: CGRect, CGAffineTransform, sprite: FluffyImage?)
        /// An eye at rest: a pill in the eye colour.
        case pill(CGRect, radius: CGFloat, CGAffineTransform)
        /// A happy eye: an arc stroked with round ends.
        case arc(Path, width: CGFloat, CGAffineTransform)
        /// Any other eye, and every eye on its way between two looks.
        case eye(Path, CGAffineTransform)
        /// A piece of a ribbon, filled with its ribbon's gradient.
        case ribbon(Path, CGAffineTransform, Gradient, start: CGPoint, end: CGPoint)
    }

    /// The body as one surface, for the fluffy renderer: the view's rotation,
    /// how much of its size the body keeps as it gives way to a mark, and both
    /// eyes, including one `shapes` leaves out because its spot faces away.
    struct Surface: Sendable {
        var view: FluffyView
        var scale: Double
        var eyes: [FluffyEye]
    }

    let root: CGAffineTransform
    var shapes: [Shape]
    /// Only when the frame was asked for in fluffy.
    let surface: Surface?
    /// The fluffy coat, drawn in place of the body's slices and eyes.
    var coat: FluffyImage?
    /// Fluffy, but the figure's mesh is still being built: the coat is not
    /// in this frame yet.
    var isFluffyPending = false

    var hasBody: Bool {
        shapes.contains { if case .slice = $0 { true } else { false } }
    }

    init?(_ object: [String: Any], outline: (String, String) -> Path) {
        guard let root = Self.matrix(object["root"]), let list = object["shapes"] as? [[String: Any]] else { return nil }
        var outlines: [String: (data: String, evenOdd: Bool, box: CGRect)] = [:]
        for entry in object["paths"] as? [[String: Any]] ?? [] {
            if let id = entry["id"] as? String, let data = entry["d"] as? String {
                let box = entry["box"] as? [String: Any] ?? [:]
                let value = { (key: String) in CGFloat((box[key] as? NSNumber)?.doubleValue ?? 0) }
                outlines[id] = (data, entry["evenOdd"] as? Bool ?? false,
                                CGRect(x: value("x"), y: value("y"), width: value("w"), height: value("h")))
            }
        }
        self.root = root
        shapes = list.compactMap { shape in
            guard let matrix = Self.matrix(shape["matrix"]) else { return nil }
            switch shape["kind"] as? String {
            case "slice":
                guard let id = shape["path"] as? String, let entry = outlines[id] else { return nil }
                if (shape["key"] as? String)?.hasPrefix("mark-") == true {
                    return .mark(outline(id, entry.data), evenOdd: entry.evenOdd, box: entry.box, matrix, sprite: nil)
                }
                return .slice(outline(id, entry.data), evenOdd: entry.evenOdd, matrix)
            case "eye":
                guard let mark = shape["mark"] as? [String: Any] else { return nil }
                switch Self.eyeMark(mark) {
                case let .pill(rect, radius): return .pill(rect, radius: radius, matrix)
                case let .arc(data, width): return .arc(SVGPathData.path(data), width: width, matrix)
                case let .path(data): return .eye(SVGPathData.path(data), matrix)
                case nil: return nil
                }
            case "ribbon":
                guard
                    let data = shape["d"] as? String,
                    let gradient = shape["gradient"] as? [String: Any],
                    let stops = gradient["stops"] as? [String]
                else { return nil }
                let point = { (x: String, y: String) in
                    CGPoint(x: (gradient[x] as? NSNumber)?.doubleValue ?? 0, y: (gradient[y] as? NSNumber)?.doubleValue ?? 0)
                }
                let colours = stops.compactMap { RobotInk(hex: $0)?.color }
                guard !colours.isEmpty else { return nil }
                return .ribbon(SVGPathData.path(data), matrix, Gradient(colors: colours),
                               start: point("x1", "y1"), end: point("x2", "y2"))
            default:
                return nil
            }
        }
        surface = Self.surface(object["surface"], sockets: object["sockets"])
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func eyeMark(_ mark: [String: Any]) -> FluffyTextures.EyeMark? {
        switch mark["shape"] as? String {
        case "pill":
            let value = { (key: String) in CGFloat(number(mark[key]) ?? 0) }
            return .pill(CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")),
                         radius: value("radius"))
        case "arc":
            guard let data = mark["d"] as? String else { return nil }
            return .arc(data, width: CGFloat(number(mark["strokeWidth"]) ?? 1))
        case "path":
            guard let data = mark["d"] as? String else { return nil }
            return .path(data)
        default:
            return nil
        }
    }

    /// `surface`, with the sockets the glue measured with the original's own
    /// `socketRegion`, `exposedHeight` and `socketKey`.
    private static func surface(_ value: Any?, sockets: Any?) -> Surface? {
        guard
            let surface = value as? [String: Any],
            let view = surface["view"] as? [String: Any],
            let sockets = sockets as? [[String: Any]],
            let scale = number(surface["scale"])
        else { return nil }
        let basis = { (key: String) in number(view[key]) ?? 0 }
        let eyes = zip(surface["eyes"] as? [[String: Any]] ?? [], sockets).compactMap { eye, socket -> FluffyEye? in
            guard
                let markObject = eye["mark"] as? [String: Any], let mark = eyeMark(markObject),
                let key = socket["key"] as? String
            else { return nil }
            let value = { (key: String) in number(socket[key]) ?? 0 }
            return FluffyEye(
                mark: mark,
                region: .init(cx: value("cx"), cy: value("cy"), w: value("w"), h: value("h"), span: value("span"),
                              exposed: value("exposed")),
                key: key, dx: number(eye["dx"]) ?? 0, dy: number(eye["dy"]) ?? 0
            )
        }
        return Surface(view: FluffyView(cY: basis("cY"), sY: basis("sY"), cP: basis("cP"), sP: basis("sP"),
                                        facing: basis("facing")),
                       scale: scale, eyes: eyes)
    }

    /// SVG's `a b c d e f`, which is `CGAffineTransform`'s order too.
    private static func matrix(_ value: Any?) -> CGAffineTransform? {
        guard let numbers = value as? [NSNumber], numbers.count == 6 else { return nil }
        let v = numbers.map { CGFloat($0.doubleValue) }
        return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    /// Paints the frame with the figure's 0 0 100 100 box laid over `box`.
    ///
    /// With a coat, as the original's `paintCanvas` does: the coat takes the
    /// place of the first of the body's slices, under the root's motion and
    /// shrunk with the body, and the other slices and the eyes are not drawn;
    /// ribbons and marks go where they always go.
    func draw(in context: inout GraphicsContext, box: CGRect, body: Color, eyes: Color) {
        context.translateBy(x: box.minX, y: box.minY)
        context.scaleBy(x: box.width / 100, y: box.height / 100)
        context.concatenate(root)
        var coatPainted = false
        for shape in shapes {
            var layer = context
            switch shape {
            case let .slice(path, evenOdd, matrix):
                if let coat {
                    guard !coatPainted else { continue }
                    coatPainted = true
                    let radius = coat.radius * (surface?.scale ?? 1)
                    layer.draw(Image(decorative: coat.image, scale: 1).interpolation(.high),
                               in: CGRect(x: coat.cx - radius, y: coat.cy - radius, width: 2 * radius, height: 2 * radius))
                    continue
                }
                layer.concatenate(matrix)
                layer.fill(path, with: .color(body), style: FillStyle(eoFill: evenOdd))
            case let .mark(path, evenOdd, box, matrix, sprite):
                layer.concatenate(matrix)
                if let sprite {
                    let radius = sprite.radius * box.width / 24
                    layer.draw(Image(decorative: sprite.image, scale: 1).interpolation(.high),
                               in: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
                } else {
                    layer.fill(path, with: .color(body), style: FillStyle(eoFill: evenOdd))
                }
            case let .pill(rect, radius, matrix):
                if coat != nil { continue }
                layer.concatenate(matrix)
                layer.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(eyes))
            case let .arc(path, width, matrix):
                if coat != nil { continue }
                layer.concatenate(matrix)
                layer.stroke(path, with: .color(eyes), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            case let .eye(path, matrix):
                if coat != nil { continue }
                layer.concatenate(matrix)
                layer.fill(path, with: .color(eyes))
            case let .ribbon(path, matrix, gradient, start, end):
                layer.concatenate(matrix)
                layer.fill(path, with: .linearGradient(gradient, startPoint: start, endPoint: end))
            }
        }
    }
}
