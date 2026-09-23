import CoreGraphics
import Testing
@testable import Pulse

@Suite("Bot mark transition bounds")
struct BotMarkTransitionBoundsTests {
    // All samples end at 2.25s, before ambientNext can first fire at 2.5s.
    // Only the scheduled bounce and the chosen state change move the body.
    @Test("An interrupted bounce keeps the body inside its canvas")
    func interruptedBounce() {
        let centre = BotMarkLibrary.shared.headCentre
        var worst = 0.0
        var scenario = ""
        for transitionFrame in 1...60 {
            let engine = BotMarkEngine()
            var programme = BotMarkProgramme(states: ["proud"])
            programme.hold = 100_000...100_000
            programme.particlesEnabled = false
            for index in 0...15 {
                _ = engine.advance(to: Double(index) / 60, programme: programme)
            }
            engine.startBounce(250)
            for index in 1...120 {
                if index == transitionFrame { programme.states = ["happy"] }
                let frame = engine.advance(to: Double(index + 15) / 60, programme: programme)
                let point = CGPoint(x: centre, y: centre).applying(frame.transform)
                let slide = max(abs(Double(point.x) - centre), abs(Double(point.y) - centre))
                if slide > worst { worst = slide; scenario = "transition=\(transitionFrame) frame=\(index)" }
            }
        }
        print("TRANSITION_BOUNDS maximum=\(worst) scenario=\(scenario)")
        #expect(worst < 13)
    }

    @Test("Morphs keep their wider travel and hand off without a jump",
          arguments: [("writing", "bouncing"), ("bouncing", "writing"),
                      ("writing", "idle"), ("bouncing", "idle")])
    func morphHandoffs(source: String, target: String) {
        let centre = BotMarkLibrary.shared.headCentre
        let engine = BotMarkEngine()
        var programme = BotMarkProgramme(states: [source])
        programme.hold = 100_000...100_000
        programme.particlesEnabled = false
        var previous: CGPoint?
        var morphTravel = 0.0
        var largestStep = 0.0
        var final: BotMarkFrame?
        for index in 0...120 {
            if index == 60 { programme.states = [target] }
            let frame = engine.advance(to: Double(index) / 30, programme: programme)
            let point = CGPoint(x: centre, y: centre).applying(frame.transform)
            if frame.morphAmount > 0.95 {
                morphTravel = max(morphTravel, max(abs(Double(point.x) - centre), abs(Double(point.y) - centre)))
            }
            if let previous {
                largestStep = max(largestStep, Double(hypot(point.x - previous.x, point.y - previous.y)))
            }
            previous = point
            final = frame
        }
        #expect(morphTravel > 13, "Effects retain their own room to move")
        #expect(largestStep < 30, "The body must not snap as the constraint returns")
        if target == "idle", let final {
            #expect(final.morphAmount < 0.01)
            let point = CGPoint(x: centre, y: centre).applying(final.transform)
            #expect(max(abs(Double(point.x) - centre), abs(Double(point.y) - centre)) < 13)
        }
    }
}
