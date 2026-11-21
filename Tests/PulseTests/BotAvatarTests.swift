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
                let slices = frame.shapes.filter { if case .slice = $0 { true } else { false } }
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
