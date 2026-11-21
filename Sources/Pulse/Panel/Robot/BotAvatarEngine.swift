// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Runs Open Bot Avatar (https://github.com/DominikScholz/open-bot-avatar,
// v0.3.0), Copyright (c) 2026 Dominik Scholz, MIT License — see
// THIRD_PARTY_NOTICES.md.
import Foundation
import JavaScriptCore
import SwiftUI

/// Open Bot Avatar's own renderer, run in JavaScriptCore, handing back each
/// frame as shapes for `RobotMarkView` to paint.
///
/// **The original's code, not a port.** `open-bot-avatar.js` is the package's
/// DOM-free build bundled as it is (`Scripts/vendor-open-bot-avatar.sh`), so a
/// figure turns, breathes, sweeps its ribbons and morphs its eyes exactly as on
/// the project's own page, and following the project is a matter of replacing
/// that file. What Pulse adds is the painting: `liveFrame` returns plain path
/// data and matrices, back to front, and SwiftUI fills them.
///
/// **Off the main thread, on one queue of its own.** The first frame of a
/// figure builds its volume, 300–550 ms per figure measured on an M-series
/// Mac; after that a frame is 0.1–2 ms. On the main thread eight robots would
/// hold the panel still for seconds, so the context lives on a serial queue —
/// JavaScriptCore is not to be entered from two threads at once — and a ring
/// shows the provider's mark for that first moment rather than stopping
/// everything else (`RobotMarkView.placeholder`).
final class BotAvatarEngine: @unchecked Sendable {
    static let shared = BotAvatarEngine()

    private let queue = DispatchQueue(label: "Pulse.BotAvatarEngine", qos: .userInitiated)
    private let bundle: Bundle
    // Touched only on `queue`.
    private var loaded = false
    private var frameFunction: JSValue?
    private var forgetFunction: JSValue?
    private var figureIDs: [String] = []
    /// Cross-section outlines by the engine's id, which is the same for the
    /// same geometry, so each is parsed once rather than every frame.
    private var outlines: [String: Path] = [:]

    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }

    /// What the figure is doing, in the original's own words.
    enum State: String, Sendable {
        case idle, thinking, working, waiting, blocked, done
    }

    /// The ids of every figure that passed the original's own validation, the
    /// package's examples first and then its gallery. Empty if the script
    /// could not run.
    func figures() async -> [String] {
        await run { $0.figureIDs }
    }

    /// One frame for one drawn figure.
    ///
    /// `key` names the drawing, not the account: each keeps its own animator,
    /// which eases a change of state from what was on screen. `time` is the
    /// animation clock; `now` the wall clock the easing runs on.
    func frame(key: String, figure: String, state: State, happy: Bool, time: TimeInterval,
               now: TimeInterval, reducedMotion: Bool, size: CGFloat, colour: String) async -> BotAvatarFrame? {
        await run { engine in
            engine.frameOnQueue(key: key, figure: figure, state: state, happy: happy, time: time, now: now,
                                reducedMotion: reducedMotion, size: size, colour: colour)
        }
    }

    /// Lets go of a drawing's animator once it is gone.
    func forget(key: String) {
        queue.async { _ = self.forgetFunction?.call(withArguments: [key]) }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable (BotAvatarEngine) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                self.loadIfNeeded()
                continuation.resume(returning: work(self))
            }
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard
            let scriptURL = bundle.url(forResource: "open-bot-avatar", withExtension: "js"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8),
            let galleryURL = bundle.url(forResource: "open-bot-avatars", withExtension: "json"),
            let gallery = try? String(contentsOf: galleryURL, encoding: .utf8),
            let context = JSContext()
        else { return }
        // Once per message: a frame that throws throws again on every frame.
        var logged: Set<String> = []
        context.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "unknown"
            if logged.count < 50, logged.insert(message).inserted {
                NSLog("Pulse: Open Bot Avatar failed: %@", message)
            }
        }
        context.evaluateScript(script)
        context.evaluateScript(Self.glue)
        let host = context.objectForKeyedSubscript("PulseAvatars")
        let listed = host?.invokeMethod("load", withArguments: [gallery])?.toString() ?? "[]"
        figureIDs = (try? JSONSerialization.jsonObject(with: Data(listed.utf8))) as? [String] ?? []
        frameFunction = host?.objectForKeyedSubscript("frame")
        forgetFunction = host?.objectForKeyedSubscript("forget")
    }

    private func frameOnQueue(key: String, figure: String, state: State, happy: Bool, time: TimeInterval,
                              now: TimeInterval, reducedMotion: Bool, size: CGFloat, colour: String) -> BotAvatarFrame? {
        guard
            let frameFunction,
            let json = frameFunction.call(withArguments: [
                key, figure, now * 1000, time, state.rawValue, happy ? "happy" : "neutral",
                reducedMotion, Double(size), colour,
            ]), json.isString,
            let object = try? JSONSerialization.jsonObject(with: Data(json.toString().utf8)) as? [String: Any]
        else { return nil }
        return BotAvatarFrame(object, outline: outline(id:data:))
    }

    private func outline(id: String, data: String) -> Path {
        if let cached = outlines[id] { return cached }
        // A long session collects outlines for every depth and look; a full
        // cache is cheaper to drop than to manage.
        if outlines.count > 4_000 { outlines.removeAll(keepingCapacity: true) }
        let path = SVGPathData.path(data)
        outlines[id] = path
        return path
    }

    /// The only script Pulse writes: it keeps the validated definitions and
    /// one animator per drawing, and returns each frame as JSON.
    private static let glue = """
    var PulseAvatars = (function () {
      var OBA = OpenBotAvatar, defs = {}, order = [], animators = {};
      function load(galleryText) {
        var gallery = [];
        try { gallery = JSON.parse(galleryText); } catch (e) {}
        OBA.examples.concat(gallery).forEach(function (d) {
          var result = OBA.validateAvatar(d);
          if (result.ok && !defs[result.value.id]) {
            defs[result.value.id] = result.value;
            order.push(result.value.id);
          }
        });
        return JSON.stringify(order);
      }
      function frame(key, id, nowMs, time, state, mood, reduced, size, color) {
        var def = defs[id];
        if (!def) return null;
        var animator = animators[key] || (animators[key] = OBA.createAnimator());
        var step = animator.step({ now: nowMs, state: state, mood: mood, target: null, reducedMotion: reduced });
        return JSON.stringify(OBA.liveFrame(def, {
          time: time, state: state, mood: mood, stateAge: step.stateAge, motionBlend: step.motionBlend,
          gaze: step.gaze, reducedMotion: reduced, size: size, color: color
        }));
      }
      function forget(key) { delete animators[key]; }
      return { load: load, frame: frame, forget: forget };
    })();
    """
}

/// One frame of a figure, as `liveFrame` lists it: shapes back to front in a
/// 0 0 100 100 box, each with its own matrix, all under `root`.
struct BotAvatarFrame: Sendable {
    enum Shape: Sendable {
        /// A cross-section of the body, or a piece of `thinking`'s dots and
        /// `blocked`'s exclamation mark: filled in the body's colour.
        case slice(Path, evenOdd: Bool, CGAffineTransform)
        /// An eye at rest: a pill in the eye colour.
        case pill(CGRect, radius: CGFloat, CGAffineTransform)
        /// A happy eye: an arc stroked with round ends.
        case arc(Path, width: CGFloat, CGAffineTransform)
        /// Any other eye, and every eye on its way between two looks.
        case eye(Path, CGAffineTransform)
        /// A piece of a ribbon, filled with its ribbon's gradient.
        case ribbon(Path, CGAffineTransform, Gradient, start: CGPoint, end: CGPoint)
    }

    let root: CGAffineTransform
    let shapes: [Shape]

    init?(_ object: [String: Any], outline: (String, String) -> Path) {
        guard let root = Self.matrix(object["root"]), let list = object["shapes"] as? [[String: Any]] else { return nil }
        var outlines: [String: (data: String, evenOdd: Bool)] = [:]
        for entry in object["paths"] as? [[String: Any]] ?? [] {
            if let id = entry["id"] as? String, let data = entry["d"] as? String {
                outlines[id] = (data, entry["evenOdd"] as? Bool ?? false)
            }
        }
        self.root = root
        shapes = list.compactMap { shape in
            guard let matrix = Self.matrix(shape["matrix"]) else { return nil }
            switch shape["kind"] as? String {
            case "slice":
                guard let id = shape["path"] as? String, let entry = outlines[id] else { return nil }
                return .slice(outline(id, entry.data), evenOdd: entry.evenOdd, matrix)
            case "eye":
                guard let mark = shape["mark"] as? [String: Any] else { return nil }
                switch mark["shape"] as? String {
                case "pill":
                    let value = { (key: String) in CGFloat((mark[key] as? NSNumber)?.doubleValue ?? 0) }
                    return .pill(CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")),
                                 radius: value("radius"), matrix)
                case "arc":
                    guard let data = mark["d"] as? String else { return nil }
                    return .arc(SVGPathData.path(data),
                                width: CGFloat((mark["strokeWidth"] as? NSNumber)?.doubleValue ?? 1), matrix)
                case "path":
                    guard let data = mark["d"] as? String else { return nil }
                    return .eye(SVGPathData.path(data), matrix)
                default:
                    return nil
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
    }

    /// SVG's `a b c d e f`, which is `CGAffineTransform`'s order too.
    private static func matrix(_ value: Any?) -> CGAffineTransform? {
        guard let numbers = value as? [NSNumber], numbers.count == 6 else { return nil }
        let v = numbers.map { CGFloat($0.doubleValue) }
        return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    /// Paints the frame with the figure's 0 0 100 100 box laid over `box`.
    func draw(in context: inout GraphicsContext, box: CGRect, body: Color, eyes: Color) {
        context.translateBy(x: box.minX, y: box.minY)
        context.scaleBy(x: box.width / 100, y: box.height / 100)
        context.concatenate(root)
        for shape in shapes {
            var layer = context
            switch shape {
            case let .slice(path, evenOdd, matrix):
                layer.concatenate(matrix)
                layer.fill(path, with: .color(body), style: FillStyle(eoFill: evenOdd))
            case let .pill(rect, radius, matrix):
                layer.concatenate(matrix)
                layer.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(eyes))
            case let .arc(path, width, matrix):
                layer.concatenate(matrix)
                layer.stroke(path, with: .color(eyes), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            case let .eye(path, matrix):
                layer.concatenate(matrix)
                layer.fill(path, with: .color(eyes))
            case let .ribbon(path, matrix, gradient, start, end):
                layer.concatenate(matrix)
                layer.fill(path, with: .linearGradient(gradient, startPoint: start, endPoint: end))
            }
        }
    }
}
