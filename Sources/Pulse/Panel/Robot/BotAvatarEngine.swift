// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Runs Open Bot Avatar (https://github.com/DominikScholz/open-bot-avatar,
// v0.4.0), Copyright (c) 2026 Dominik Scholz, MIT License — see
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
/// **Fluffy** is the one exception: the original draws fur with WebGL2, which
/// JavaScriptCore has not got. The fur's mesh is still the original's own
/// (`buildMesh`, run here), and so are its level of detail, its eye sockets'
/// regions and its dye ramp; the WebGL2 renderer and shaders are ported to
/// Metal (`FluffyRenderer`), and the coat comes back with the frame as an
/// image to paint in place of the flat body.
///
/// **Off the main thread, on one queue of its own.** The first frame of a
/// figure builds its volume, 45–115 ms per figure with v0.4.0 measured on an
/// M-series Mac; after that a frame is 0.1–2 ms. On the main thread eight robots would
/// hold the panel still for half a second, so the context lives on a serial queue —
/// JavaScriptCore is not to be entered from two threads at once — and a ring
/// shows the provider's mark for that first moment rather than stopping
/// everything else (`RobotMarkView.placeholder`). A fluffy figure's mesh is
/// built on the same queue as a job of its own, so other rings keep drawing
/// meanwhile, and kept on the GPU while its rings draw.
final class BotAvatarEngine: @unchecked Sendable {
    static let shared = BotAvatarEngine()

    private let queue = DispatchQueue(label: "Pulse.BotAvatarEngine", qos: .userInitiated)
    private let bundle: Bundle
    // Touched only on `queue`.
    private var loaded = false
    private var context: JSContext?
    private var frameFunction: JSValue?
    private var forgetFunction: JSValue?
    private var meshFunction: JSValue?
    private var markMeshFunction: JSValue?
    private var rampFunction: JSValue?
    private var figureIDs: [String] = []
    /// Cross-section outlines by the engine's id, which is the same for the
    /// same geometry, so each is parsed once rather than every frame.
    private var outlines: [String: Path] = [:]
    /// Fluffy meshes on the GPU, by figure or mark, and the ones on their way.
    private var geometries: [String: FluffyGeometry] = [:]
    private var building: Set<String> = []
    private var unbuildable: Set<String> = []
    /// The pompoms of `thinking` and `blocked`, by shape, colour and density.
    private var sprites: [String: FluffyImage] = [:]
    private var spriteOrder: [String] = []
    /// Drawings whose last frame was fluffy. When none is left, the meshes go.
    private var fluffyKeys: Set<String> = []

    /// This many meshes always stay on the GPU; any more only while drawn
    /// within `idleSeconds` (the original's `KEPT_MESHES` and `IDLE_MS`).
    static let keptMeshes = 8
    static let idleSeconds: TimeInterval = 2

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
    /// animation clock; `now` the wall clock the easing runs on. `colour` is
    /// the body's and `eyes` the eyes' (`#rrggbb`); `pixelScale` is device
    /// pixels per point, which decides how much fur is drawn.
    func frame(key: String, figure: String, state: State, happy: Bool, time: TimeInterval,
               now: TimeInterval, reducedMotion: Bool, size: CGFloat, colour: String,
               material: RobotMaterial = .flat, eyes: String = "#151515",
               pixelScale: CGFloat = 2) async -> BotAvatarFrame? {
        await run { engine in
            engine.frameOnQueue(key: key, figure: figure, state: state, happy: happy, time: time, now: now,
                                reducedMotion: reducedMotion, size: size, colour: colour, material: material,
                                eyes: eyes, pixelScale: pixelScale)
        }
    }

    /// Lets go of a drawing's animator once it is gone.
    func forget(key: String) {
        queue.async {
            _ = self.forgetFunction?.call(withArguments: [key])
            self.stopFluffy(key: key)
        }
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
        self.context = context
        frameFunction = host?.objectForKeyedSubscript("frame")
        forgetFunction = host?.objectForKeyedSubscript("forget")
        meshFunction = host?.objectForKeyedSubscript("mesh")
        markMeshFunction = host?.objectForKeyedSubscript("markMesh")
        rampFunction = host?.objectForKeyedSubscript("ramp")
    }

    private func frameOnQueue(key: String, figure: String, state: State, happy: Bool, time: TimeInterval,
                              now: TimeInterval, reducedMotion: Bool, size: CGFloat, colour: String,
                              material: RobotMaterial, eyes: String, pixelScale: CGFloat) -> BotAvatarFrame? {
        let fluffy = material == .fluffy && FluffyRenderer.shared != nil
        guard
            let frameFunction,
            let json = frameFunction.call(withArguments: [
                key, figure, now * 1000, time, state.rawValue, happy ? "happy" : "neutral",
                reducedMotion, Double(size), colour, fluffy,
            ]), json.isString,
            let object = try? JSONSerialization.jsonObject(with: Data(json.toString().utf8)) as? [String: Any],
            var frame = BotAvatarFrame(object, outline: outline(id:data:))
        else { return nil }
        if fluffy {
            fluffyKeys.insert(key)
            dress(&frame, key: key, figure: figure, colour: colour, eyes: eyes,
                  scale: Double(size) / 100 * Double(pixelScale))
        } else {
            stopFluffy(key: key)
        }
        return frame
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

    // MARK: - Fluffy

    /// Adds the coat and the pompoms to a frame, as the original's `paint.js`
    /// would paint them. Where one is not ready yet, the frame says so; where
    /// one cannot be drawn, that part stays flat.
    private func dress(_ frame: inout BotAvatarFrame, key: String, figure: String, colour: String, eyes: String,
                       scale: Double) {
        guard
            let renderer = FluffyRenderer.shared,
            let body = FluffyLook.bytes(hex: colour),
            let ink = FluffyLook.bytes(hex: eyes)
        else { return }
        let ramp: (SIMD3<UInt8>) -> [UInt8]? = { self.ramp($0) }
        // The whole body and its eyes as one image, unless it has shrunk away into a mark.
        if let surface = frame.surface, surface.scale > 0.001, frame.hasBody {
            switch geometry("figure:\(figure)", detail: FluffyDetail(scale: scale), mesh: { $0.figureMesh(figure) }) {
            case let .ready(geometry):
                frame.coat = renderer.render(geometry, view: surface.view,
                                             look: FluffyLook(color: body, ink: ink, eyes: surface.eyes),
                                             scale: scale, key: key, ramp: ramp)
            case .pending:
                frame.isFluffyPending = true
            case .failed:
                break
            }
        }
        frame.shapes = frame.shapes.map { shape in
            guard case let .mark(path, evenOdd, box, matrix, _) = shape else { return shape }
            return .mark(path, evenOdd: evenOdd, box: box, matrix,
                         sprite: sprite(box: box, colour: body, hex: colour, scale: scale, renderer: renderer, ramp: ramp))
        }
    }

    /// `paintFluffyMark`: a mark face-on as a fluffy ball or capsule, rendered
    /// once per shape, colour and density and kept, since the dots and the
    /// exclamation mark only ever move, squash and fade.
    private func sprite(box: CGRect, colour: SIMD3<UInt8>, hex: String, scale: Double, renderer: FluffyRenderer,
                        ramp: (SIMD3<UInt8>) -> [UInt8]?) -> FluffyImage? {
        guard box.width > 0, box.height > 0 else { return nil }
        /// Radius of a mark's model, and the headroom for the top of a hop.
        let radius = 12.0, headroom = 1.12
        let aspect = (1000 * box.height / box.width).rounded() / 1000
        let unit = box.width / (2 * radius)
        // Whole powers of two, so a mark that grows or shrinks keeps the same fibers.
        let density = min(8, max(0.5, pow(2, (log2(headroom * scale * unit)).rounded(.up))))
        let name = "\(aspect)|\(hex)|\(density)"
        if let sprite = sprites[name] { return sprite }
        guard
            case let .ready(geometry) = geometry("mark:\(aspect)", detail: FluffyDetail(scale: density),
                                                 mesh: { $0.markMesh(aspect: aspect) }),
            let sprite = renderer.render(geometry, view: .front, look: FluffyLook(color: colour, ink: colour, eyes: []),
                                         scale: density, key: nil, ramp: ramp)
        else { return nil }
        if spriteOrder.count >= 12 { sprites[spriteOrder.removeFirst()] = nil }
        sprites[name] = sprite
        spriteOrder.append(name)
        return sprite
    }

    private enum Built {
        case ready(FluffyGeometry)
        case pending
        case failed
    }

    /// A mesh on the GPU good for `detail`, or the job that builds it set
    /// going. A coarser one already there draws while a finer one builds.
    private func geometry(_ name: String, detail: FluffyDetail,
                          mesh: @escaping @Sendable (BotAvatarEngine) -> FluffyMeshArrays?) -> Built {
        if let geometry = geometries[name], geometry.covers(detail) { return .ready(geometry) }
        if unbuildable.contains(name) { return .failed }
        if !building.contains(name) {
            building.insert(name)
            queue.async {
                self.building.remove(name)
                guard
                    let arrays = mesh(self),
                    let geometry = FluffyRenderer.shared?.upload(arrays, detail: detail)
                else {
                    self.unbuildable.insert(name)
                    return
                }
                self.geometries[name] = geometry
                self.sweep()
            }
        }
        if let geometry = geometries[name] { return .ready(geometry) }
        return .pending
    }

    /// Frees the meshes not drawn for a while, beyond the few most recent.
    /// One not drawn yet stays: its ring's next frame may be queued behind
    /// other rings' builds for longer than `idleSeconds`, and sweeping it
    /// then would only build it again.
    private func sweep() {
        guard geometries.count > Self.keptMeshes else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for (name, geometry) in geometries.sorted(by: { $0.value.usedAt < $1.value.usedAt })
        where geometries.count > Self.keptMeshes && geometry.usedAt > 0 && now - geometry.usedAt >= Self.idleSeconds {
            geometries[name] = nil
        }
    }

    private func stopFluffy(key: String) {
        guard fluffyKeys.remove(key) != nil else { return }
        FluffyRenderer.shared?.forget(key: key)
        // Nothing fluffy is drawn any more: nothing on the GPU is needed.
        if fluffyKeys.isEmpty {
            geometries.removeAll()
            sprites.removeAll()
            spriteOrder.removeAll()
            FluffyRenderer.shared?.releaseAll()
        }
    }

    /// The original's `buildMesh` for a figure's volume, copied out.
    func figureMesh(_ figure: String) -> FluffyMeshArrays? {
        meshFunction.flatMap { Self.meshArrays($0.call(withArguments: [figure])) }
    }

    /// The original's `buildMesh` for a mark's capsule.
    func markMesh(aspect: Double) -> FluffyMeshArrays? {
        markMeshFunction.flatMap { Self.meshArrays($0.call(withArguments: [aspect])) }
    }

    /// The original's `dyeRamp` for a colour.
    private func ramp(_ colour: SIMD3<UInt8>) -> [UInt8]? {
        guard let value = rampFunction?.call(withArguments: [colour.x, colour.y, colour.z]) else { return nil }
        return Self.typedArray(value, of: UInt8.self, type: kJSTypedArrayTypeUint8Array)
    }

    /// Builds a figure's mesh now, on the engine's queue, and says how long it
    /// took and how big it is. For tests.
    func measureMesh(figure: String) async -> (seconds: TimeInterval, mesh: FluffyMeshArrays?) {
        await run { engine in
            let start = ProcessInfo.processInfo.systemUptime
            let mesh = engine.figureMesh(figure)
            return (ProcessInfo.processInfo.systemUptime - start, mesh)
        }
    }

    /// Runs `body` with the context on its queue. For tests that compare a
    /// port with the bundled original.
    func evaluate<T: Sendable>(_ body: @escaping @Sendable (JSContext) -> T?) async -> T? {
        await run { engine in engine.context.flatMap(body) }
    }

    private static func meshArrays(_ value: JSValue?) -> FluffyMeshArrays? {
        guard
            let value, value.isObject,
            let vertices = typedArray(value.forProperty("vertices"), of: Float.self, type: kJSTypedArrayTypeFloat32Array),
            let indices = typedArray(value.forProperty("indices"), of: UInt32.self, type: kJSTypedArrayTypeUint32Array),
            let roots = typedArray(value.forProperty("roots"), of: Float.self, type: kJSTypedArrayTypeFloat32Array)
        else { return nil }
        let number = { (name: String) in value.forProperty(name)?.toDouble() ?? .nan }
        let mesh = FluffyMeshArrays(
            vertices: vertices, indices: indices, roots: roots,
            coarse: (Int(number("coarseStart")), Int(number("coarseCount"))),
            fine: (Int(number("fineStart")), Int(number("fineCount"))),
            bounds: (number("minX"), number("minY"), number("maxX"), number("maxY")),
            halfDepth: number("halfDepth"), eyeZ: (number("eyeZ0"), number("eyeZ1"))
        )
        guard [mesh.bounds.minX, mesh.bounds.maxX, mesh.halfDepth].allSatisfy(\.isFinite) else { return nil }
        return mesh
    }

    /// A typed array's contents, copied straight from its backing store.
    private static func typedArray<T>(_ value: JSValue?, of _: T.Type, type: JSTypedArrayType) -> [T]? {
        guard let value, let ref = value.jsValueRef, let context = value.context?.jsGlobalContextRef else { return nil }
        var exception: JSValueRef?
        guard
            JSValueGetTypedArrayType(context, ref, &exception) == type,
            let object = JSValueToObject(context, ref, &exception),
            // The original's arrays are made fresh, so they start their buffer.
            JSObjectGetTypedArrayByteOffset(context, object, &exception) == 0
        else { return nil }
        let length = JSObjectGetTypedArrayByteLength(context, object, &exception)
        guard length > 0 else { return [] }
        guard let bytes = JSObjectGetTypedArrayBytesPtr(context, object, &exception), exception == nil else { return nil }
        let count = length / MemoryLayout<T>.stride
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: T.self), count: count))
    }

    /// The only script Pulse writes: it keeps the validated definitions and
    /// one animator per drawing, returns each frame as JSON, and hands the
    /// fluffy renderer the original's meshes, sockets and dye.
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
      function frame(key, id, nowMs, time, state, mood, reduced, size, color, fluffy) {
        var def = defs[id];
        if (!def) return null;
        var animator = animators[key] || (animators[key] = OBA.createAnimator());
        var step = animator.step({ now: nowMs, state: state, mood: mood, target: null, reducedMotion: reduced });
        var out = OBA.liveFrame(def, {
          time: time, state: state, mood: mood, stateAge: step.stateAge, motionBlend: step.motionBlend,
          gaze: step.gaze, reducedMotion: reduced, size: size, color: color
        });
        if (fluffy) {
          out.sockets = out.surface.eyes.map(function (e) {
            var r = OBA.socketRegion(e.mark);
            return { cx: r.cx, cy: r.cy, w: r.w, h: r.h, span: r.span,
                     exposed: OBA.exposedHeight(r.w, r.h), key: OBA.socketKey(e.mark) };
          });
        } else {
          delete out.surface;
        }
        return JSON.stringify(out);
      }
      function forget(key) { delete animators[key]; }
      function describe(shape, m, eyeZ) {
        var b = shape.bounds;
        return { vertices: m.vertices, indices: m.indices, roots: m.roots,
                 coarseStart: m.coarse.start, coarseCount: m.coarse.count,
                 fineStart: m.fine.start, fineCount: m.fine.count,
                 minX: b.minX, minY: b.minY, maxX: b.maxX, maxY: b.maxY,
                 halfDepth: OBA.halfDepth(shape), eyeZ0: eyeZ[0], eyeZ1: eyeZ[1] };
      }
      function mesh(id) {
        var def = defs[id];
        if (!def) return null;
        var vol = OBA.preparedVolume(def).vol;
        return describe(vol, OBA.buildMesh(vol), vol.eyeZ);
      }
      // The model marks.js gives a dot or a bar: a capsule 12 units in radius.
      function markMesh(aspect) {
        var radius = 12, half = radius * aspect;
        var model = { radius: radius, bounds: { minX: -radius, maxX: radius, minY: -half, maxY: half } };
        return describe(model, OBA.buildMesh(model), [0, 0]);
      }
      function ramp(r, g, b) { return OBA.dyeRamp([r, g, b]); }
      return { load: load, frame: frame, forget: forget, mesh: mesh, markMesh: markMesh, ramp: ramp };
    })();
    """
}
