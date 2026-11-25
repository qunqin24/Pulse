import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// Open Bot Avatar in the rings: the bundled engine runs, every figure Pulse
/// offers draws in every state, path data parses as SVG means it, and the
/// facts Pulse has map to the original's states in order. Serialized: the
/// engine has one queue, and a test measuring a frame must not wait behind
/// another building twenty-three figures.
@Suite("Bot avatar", .serialized)
struct BotAvatarTests {
    private let engine = BotAvatarEngine.shared

    @Test("The bundled engine runs and offers exactly the figures Pulse lists")
    func figures() async {
        #expect(Set(await engine.figures()) == Set(RobotFigures.automatic))
        #expect(RobotFigures.automatic.count == Set(RobotFigures.automatic).count)
        // Every figure has a name of its own in the interface.
        for figure in RobotFigures.automatic {
            #expect(RobotFigures.title(figure) != figure)
        }
    }

    @Test("Every figure draws in every state")
    func everyState() async throws {
        for figure in RobotFigures.automatic {
            for state in [BotAvatarEngine.State.idle, .thinking, .working, .waiting, .blocked, .done] {
                let frame = try #require(await engine.frame(
                    key: "test-\(figure)-\(state)", figure: figure, state: state, happy: false, time: 2.5,
                    now: 1_000, reducedMotion: false, size: 27, colour: "#4285f4"
                ), "\(figure) \(state)")
                defer { engine.forget(key: "test-\(figure)-\(state)") }
                let slices = frame.shapes.filter {
                    switch $0 {
                    case .slice, .mark: true
                    default: false
                    }
                }
                #expect(!slices.isEmpty, "\(figure) \(state) draws nothing")
                let eyes = frame.shapes.filter {
                    switch $0 {
                    case .pill, .arc, .eye: true
                    default: false
                    }
                }
                // The marks of thinking and blocked replace the body, eyes and all.
                if state == .thinking || state == .blocked {
                    #expect(eyes.isEmpty, "\(figure) \(state)")
                } else {
                    #expect(eyes.count == 2, "\(figure) \(state)")
                }
            }
        }
    }

    @Test("A figure Pulse does not know draws nothing rather than something else")
    func unknownFigure() async {
        #expect(await engine.frame(key: "test-unknown", figure: "no-such-figure", state: .idle, happy: false, time: 0,
                             now: 0, reducedMotion: false, size: 27, colour: "#ffffff") == nil)
    }

    @Test("Once a figure is built, a frame costs a few milliseconds at most")
    func cost() async {
        let figures = Array(RobotFigures.automatic.prefix(6))
        // The first frame of each builds its volume (hundreds of milliseconds,
        // off the main thread); that is not what is measured.
        // One drawing per figure, each with its own animator, as on a rail.
        for figure in figures {
            for state in [BotAvatarEngine.State.idle, .working] {
                _ = await engine.frame(key: "test-cost-\(figure)", figure: figure, state: state, happy: false,
                                       time: 0, now: 0, reducedMotion: false, size: 27, colour: "#4285f4")
            }
        }
        let start = Date()
        let count = 180
        for index in 0..<count {
            let figure = figures[index % figures.count]
            _ = await engine.frame(key: "test-cost-\(figure)", figure: figure, state: .working,
                                   happy: false, time: Double(index) / 30, now: Double(index) / 30,
                                   reducedMotion: false, size: 27, colour: "#4285f4")
        }
        for figure in figures { engine.forget(key: "test-cost-\(figure)") }
        let each = Date().timeIntervalSince(start) / Double(count)
        // A debug build on a busy test machine: generous, but it catches a
        // frame that went from milliseconds to tens of them.
        #expect(each < 0.015, "\(each * 1000) ms a frame")
    }

    // MARK: - Fluffy

    @Test("The bundled shaders are the ones the Metal port follows")
    func shadersUnchanged() async throws {
        let source = try #require(await engine.evaluate { context in
            context.evaluateScript("OpenBotAvatar.vertexShader + OpenBotAvatar.fragmentShader")?.toString()
        })
        // A new version whose shaders changed: port the change to
        // FluffyShaders.source, then update the digest.
        #expect(FluffyShaders.digest(of: source) == FluffyShaders.upstreamDigest)
    }

    @Test("The ported level of detail and constants agree with the original's")
    func detailAgrees() async throws {
        let scales = [0.1, 0.3, 0.48, 0.54, 0.75, 1, 1.4, 1.92, 2, 2.56, 4]
        let script = """
        JSON.stringify({
          details: \(scales).map(function (s) { return OpenBotAvatar.fluffyDetail(s); }),
          roots: [[42090, 4], [42090, 8], [10, 3], [7, 8], [0, 2]].map(function (p) { return OpenBotAvatar.rootsIn(p[0], p[1]); }),
          passes: OpenBotAvatar.ROOT_PASSES, pad: OpenBotAvatar.SOCKET_PAD, tile: OpenBotAvatar.SOCKET_TILE,
          ramp: OpenBotAvatar.DYE_RAMP_SIZE, range: OpenBotAvatar.DYE_RAMP_RANGE, body: OpenBotAvatar.PASS.body,
          shell: OpenBotAvatar.PASS.shell, strand: OpenBotAvatar.PASS.strand
        })
        """
        let json = try #require(await engine.evaluate { context in context.evaluateScript(script)?.toString() })
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let details = try #require(object["details"] as? [[String: Any]])
        #expect(details.count == scales.count)
        for (scale, detail) in zip(scales, details) {
            let original = FluffyDetail(shells: detail["shells"] as? Int ?? -1,
                                        strandPasses: detail["strandPasses"] as? Int ?? -1,
                                        fineSockets: detail["fineSockets"] as? Bool ?? false)
            #expect(FluffyDetail(scale: scale) == original, "\(scale)")
        }
        let roots = [(42090, 4), (42090, 8), (10, 3), (7, 8), (0, 2)].map { FluffyDetail.roots(in: $0.0, passes: $0.1) }
        #expect(roots == object["roots"] as? [Int])
        #expect(object["passes"] as? Int == FluffyDetail.rootPasses)
        #expect(object["pad"] as? Double == FluffyTextures.socketPad)
        #expect(object["tile"] as? Int == FluffyTextures.socketTile)
        #expect(object["ramp"] as? Int == FluffyRenderer.rampSize)
        // Inlined in the shader source, with the passes' numbers.
        #expect(object["range"] as? Double == 2.4)
        #expect([object["body"], object["shell"], object["strand"]].compactMap { $0 as? Int } == [0, 1, 2])
    }

    @Test("A figure's mesh comes out of the script whole")
    func mesh() async throws {
        for figure in ["mug", "ghost", "barbell"] {
            let (seconds, built) = await engine.measureMesh(figure: figure)
            let mesh = try #require(built, "\(figure)")
            let vertices = mesh.vertices.count / 6
            #expect(mesh.vertices.count % 6 == 0 && mesh.indices.count % 3 == 0 && mesh.roots.count % 8 == 0)
            #expect(vertices > 5_000 && vertices < 200_000, "\(figure): \(vertices) vertices")
            #expect(mesh.roots.count / 8 > 10_000, "\(figure): \(mesh.roots.count / 8) roots")
            #expect(mesh.coarse.start == 0 && mesh.fine.start == mesh.coarse.count)
            #expect(mesh.fine.start + mesh.fine.count == mesh.indices.count)
            #expect(Int(mesh.indices.max() ?? .max) < vertices)
            #expect(mesh.bounds.minX >= 0 && mesh.bounds.maxX <= 100 && mesh.bounds.minX < mesh.bounds.maxX)
            #expect(mesh.halfDepth > 0 && mesh.eyeZ.0 > 0)
            // Positions inside the grid's padded box; normals of unit length.
            #expect(mesh.vertices[0] > -10 && mesh.vertices[0] < 110)
            let normal = (mesh.vertices[3] * mesh.vertices[3] + mesh.vertices[4] * mesh.vertices[4]
                + mesh.vertices[5] * mesh.vertices[5]).squareRoot()
            #expect(abs(normal - 1) < 0.01)
            #expect(seconds < 2, "\(figure): \(seconds) s")
        }
        #expect(await engine.measureMesh(figure: "no-such-figure").mesh == nil)
    }

    @Test("An eye's socket tile is low inside the eye and high outside it")
    func socketTile() {
        let region = FluffyTextures.SocketRegion(cx: 40, cy: 50, w: 6, h: 14, span: 14 + 7.6, exposed: 0.8 - 0.175)
        let tile = FluffyTextures.socketTile(.pill(CGRect(x: 37, y: 43, width: 6, height: 14), radius: 3), region: region)
        let size = FluffyTextures.socketTile
        #expect(tile.count == size * size)
        #expect(tile[size / 2 * size + size / 2] < 100)
        #expect(tile[0] > 200 && tile[size * size - 1] > 200)
    }

    /// A frame in fluffy, once the figure's mesh is built.
    private func fluffyFrame(_ key: String, figure: String = "cat", state: BotAvatarEngine.State,
                             time: Double = 3) async throws -> BotAvatarFrame {
        for _ in 0..<200 {
            let frame = try #require(await engine.frame(
                key: key, figure: figure, state: state, happy: false, time: time, now: 1_000,
                reducedMotion: false, size: 27, colour: "#4285f4", material: .fluffy
            ))
            if !frame.isFluffyPending { return frame }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CancellationError()
    }

    @Test("Fluffy draws a coat for the body and pompoms for the marks", .enabled(if: FluffyRenderer.shared != nil))
    func fluffy() async throws {
        let idle = try await fluffyFrame("test-fluffy-idle", state: .idle)
        let coat = try #require(idle.coat)
        // 27pt at 2x is 0.54 pixels a unit: a small image, never below 32.
        #expect(coat.image.width >= 32 && coat.image.width == coat.image.height && coat.image.width < 120)
        #expect(coat.radius > 30 && coat.cx > 30 && coat.cx < 70)
        let pixels = try #require(coat.image.dataProvider?.data as Data?)
        let middle = (coat.image.height / 2 * coat.image.width + coat.image.width / 2) * 4
        #expect(pixels[middle + 3] == 255, "the body is opaque")
        #expect(pixels[3] == 0, "around it is clear")

        // Seen again at the same moment, the image is reused.
        let again = try await fluffyFrame("test-fluffy-idle", state: .idle)
        engine.forget(key: "test-fluffy-idle")
        #expect(again.coat?.image === coat.image)

        // The marks of thinking become pompoms once their own small mesh is in.
        var sprites = 0
        for _ in 0..<100 where sprites == 0 {
            let thinking = try await fluffyFrame("test-fluffy-thinking", state: .thinking)
            sprites = thinking.shapes.filter { if case .mark(_, _, _, _, .some) = $0 { true } else { false } }.count
            if sprites == 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        engine.forget(key: "test-fluffy-thinking")
        #expect(sprites == 3)

        // Flat asks for no coat.
        let flat = try #require(await engine.frame(key: "test-fluffy-flat", figure: "cat", state: .idle, happy: false,
                                                   time: 3, now: 1_000, reducedMotion: false, size: 27,
                                                   colour: "#4285f4"))
        engine.forget(key: "test-fluffy-flat")
        #expect(flat.coat == nil && flat.surface == nil && !flat.isFluffyPending)
    }

    /// Eight fluffy rings at rail size, as a rail of eight robots draws them.
    /// Prints what it measures; the limits only catch a cost that went from
    /// milliseconds to tens of them.
    @Test("Eight fluffy rings cost a few milliseconds a frame", .enabled(if: FluffyRenderer.shared != nil))
    func fluffyCost() async throws {
        let figures = Array(RobotFigures.automatic.prefix(8))
        var firsts: [Double] = []
        for figure in figures {
            let start = ProcessInfo.processInfo.systemUptime
            _ = try await fluffyFrame("test-fcost-\(figure)", figure: figure, state: .idle, time: 0)
            firsts.append(ProcessInfo.processInfo.systemUptime - start)
        }
        var each: [String: Double] = [:]
        // The same frames flat, in drawings of their own, for comparison.
        for material in RobotMaterial.allCases {
            for state in [BotAvatarEngine.State.idle, .working] {
                let start = ProcessInfo.processInfo.systemUptime, startCPU = Self.cpuTime()
                let count = 240
                for index in 0..<count {
                    let figure = figures[index % figures.count]
                    _ = await engine.frame(key: "test-fcost-\(material)-\(figure)", figure: figure, state: state,
                                           happy: false, time: Double(index) / 30, now: Double(index) / 30,
                                           reducedMotion: false, size: 27, colour: "#4285f4", material: material)
                }
                each["\(material) \(state)"] = (ProcessInfo.processInfo.systemUptime - start) / Double(count)
                each["\(material) \(state) cpu"] = (Self.cpuTime() - startCPU) / Double(count)
            }
        }
        for figure in figures {
            engine.forget(key: "test-fcost-\(figure)")
            for material in RobotMaterial.allCases { engine.forget(key: "test-fcost-\(material)-\(figure)") }
        }
        let ms = { (key: String) in (each[key] ?? 0) * 1000 }
        let report = String(format: "first fluffy frame per figure %.0f–%.0f ms (all eight %.2f s); "
                                + "per frame idle %.2f ms, working %.2f ms (flat %.2f ms, %.2f ms); "
                                + "CPU per frame idle %.2f ms, working %.2f ms (flat %.2f ms, %.2f ms)",
                            (firsts.min() ?? 0) * 1000, (firsts.max() ?? 0) * 1000, firsts.reduce(0, +),
                            ms("fluffy idle"), ms("fluffy working"), ms("flat idle"), ms("flat working"),
                            ms("fluffy idle cpu"), ms("fluffy working cpu"), ms("flat idle cpu"), ms("flat working cpu"))
        print("Fluffy cost: \(report)")
        #expect((each["fluffy working"] ?? 1) < 0.03, "\(report)")
        #expect(firsts.allSatisfy { $0 < 3 }, "\(report)")
    }

    /// CPU seconds this process has used, on every thread.
    private static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let seconds = { (time: timeval) in Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    // MARK: - Path data

    @Test("Compact numbers, relative commands and implicit lines")
    func pathNumbers() {
        // `-.5.5` is two numbers; pairs after a move are lines.
        let box = SVGPathData.cgPath("M10 10l-.5.5 20 0h5v5z").boundingBox
        #expect(abs(box.minX - 9.5) < 0.001)
        #expect(abs(box.maxX - 34.5) < 0.001)
        #expect(abs(box.maxY - 15.5) < 0.001)
        let exponent = SVGPathData.cgPath("M1e1 0L2e+1 1.5E1").boundingBox
        #expect(abs(exponent.maxX - 20) < 0.001 && abs(exponent.maxY - 15) < 0.001)
    }

    @Test("Arcs, as the marks use them, and with flags run together")
    func pathArcs() {
        let circle = SVGPathData.cgPath("M6.6 0A6.6 6.6 0 1 1 -6.6 0A6.6 6.6 0 1 1 6.6 0Z").boundingBox
        #expect(abs(circle.width - 13.2) < 0.05 && abs(circle.height - 13.2) < 0.05)
        let compact = SVGPathData.cgPath("M0 0a5 5 0 1110 0").boundingBox
        #expect(abs(compact.width - 10) < 0.05 && abs(compact.minY + 5) < 0.05)
    }

    @Test("Curves and their smooth continuations")
    func pathCurves() {
        let path = SVGPathData.cgPath("M0 0C0 10 10 10 10 0S20-10 20 0Q25 5 30 0T40 0")
        #expect(abs(path.currentPoint.x - 40) < 0.001 && abs(path.currentPoint.y) < 0.001)
        #expect(SVGPathData.cgPath("M0 0L5 5 garbage").currentPoint == CGPoint(x: 5, y: 5))
    }

    // MARK: - Facts to states

    @Test("Facts become the original's states, in Pulse's order")
    func states() {
        #expect(RobotMood.resolve(hasReading: true, isSpent: true, isWorking: true, isRefreshing: true) == .refreshing)
        #expect(RobotMood.resolve(hasReading: false, isSpent: true, isWorking: true, isRefreshing: false) == .working)
        #expect(RobotMood.resolve(hasReading: false, isSpent: true, isWorking: false, isRefreshing: false) == .asleep)
        #expect(RobotMood.resolve(hasReading: true, isSpent: true, isWorking: false, isRefreshing: false) == .spent)
        #expect(RobotMood.resolve(hasReading: true, isSpent: false, isWorking: false, isRefreshing: false) == .idle)
        // Activity off withholds the two moods it stands for.
        #expect(RobotMood.resolve(hasReading: true, isSpent: false, isWorking: true, isRefreshing: true,
                                  activity: false) == .idle)

        #expect(RobotMood.idle.state == .idle)
        #expect(RobotMood.working.state == .working)
        #expect(RobotMood.refreshing.state == .thinking)
        #expect(RobotMood.spent.state == .blocked)
        #expect(RobotMood.asleep.state == .waiting)

        #expect(RobotGesture.triggered(justReset: true, justFinished: true) == .cheer)
        #expect(RobotGesture.triggered(justReset: false, justFinished: true) == .nod)
        #expect(RobotGesture.triggered(justReset: false, justFinished: false) == nil)
    }

    @Test("Automatic figures differ from their neighbours and keep a chosen one")
    func spread() {
        let figures = RobotAutomatic.spread([nil, nil, "mug", nil], over: RobotFigures.automatic)
        #expect(figures[2] == "mug")
        for index in 1..<figures.count {
            #expect(figures[index] != figures[index - 1])
        }
        // Each account keeps its own phase, the same every time.
        #expect(RobotCue.phase(for: AccountKey(.codex)) == RobotCue.phase(for: AccountKey(.codex)))
        #expect(RobotCue.phase(for: AccountKey(.codex)) != RobotCue.phase(for: AccountKey(.claudeCode)))
    }

    @Test("A colour goes to the engine as lowercase hex")
    func hex() {
        #expect(RobotInk(rgb: 0x4285F4).hexString == "#4285f4")
        #expect(RobotInk(red: 2, green: -1, blue: 0.5).hexString == "#ff0080")
    }
}
