import SwiftUI
import Testing
@testable import Pulse

/// The animated mark: what it says, and whether it can be seen saying it.
///
/// The animation itself is not testable from here — it is a per-frame spring
/// solve drawn into a `Canvas`, and what it looks like is a screenshot
/// question. What *is* checkable is the part that would fail silently: the
/// rule that turns a Pulse fact into a mood, and the rule that keeps a brand
/// colour visible on the disc it sits on. Both of those go wrong by drawing
/// something plausible rather than by crashing.
@Suite("Bot mark")
@MainActor
struct BotMarkTests {
    @Test("Busy outranks every other reading")
    func busyWins() {
        #expect(BotMarkMood.resolve(isBusy: true, isRefreshing: true,
                                    isSpent: true, hasReading: false) == .working)
        #expect(BotMarkMood.resolve(isBusy: true, isRefreshing: false,
                                    isSpent: false, hasReading: true) == .working)
    }

    @Test("A spent limit is only read once nothing is happening")
    func spentBelowActivity() {
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: true,
                                    isSpent: true, hasReading: true) == .fetching)
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: true, hasReading: true) == .spent)
    }

    /// No reading is its own mood, rather than an instruction to fall asleep.
    @Test("No reading is unavailable, and a plain reading is idle")
    func quietStates() {
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: false, hasReading: false) == .unavailable)
        #expect(BotMarkMood.resolve(isBusy: false, isRefreshing: false,
                                    isSpent: false, hasReading: true) == .idle)
    }

    /// Every mood has to name a state the library actually carries, or the
    /// mark silently falls back to the first state in the table and the rail
    /// says "idle" about a provider that is signed out.
    @Test("Every mood names a state the data has")
    func moodsResolveToRealStates() {
        for mood in BotMarkMood.allCases {
            #expect(BotMarkLibrary.shared.state(mood.upstreamState).id == mood.upstreamState)
        }
    }

    /// The geometry is a bundled resource, and a resource that stops being
    /// copied is a blank rail rather than a build failure.
    @Test("The bundled geometry is the whole table")
    func libraryLoads() {
        let library = BotMarkLibrary.shared
        #expect(library.shapes.count == 18)
        #expect(library.shapeOrder.count == 18)
        #expect(library.expressions.count == 25)
        #expect(library.states.count == 39)
        // Two eyes, and the rings have to be the same length end to end or
        // the expression blend has nothing to interpolate between.
        for expression in library.expressions {
            #expect(expression.count == 2)
            #expect(expression[0].count == expression[1].count)
        }
        // Shape blending is point-by-point, so every body shares one count.
        let counts = Set(library.shapes.values.map(\.ring.count))
        #expect(counts == [96])
    }

    /// Every provider draws a body, and a dark brand is lifted rather than
    /// left as a hole in the disc.
    @Test("No provider's mark disappears into the disc")
    func bodiesStayVisible() {
        for provider in Provider.allCases {
            let body = BotMarkTint.body(for: provider)
            let luminance = Self.luminance(of: body)
            #expect(luminance >= 0.41, "\(provider.rawValue) draws too dark to see")
            // And the eyes have to read against whatever the body became.
            let eyes = BotMarkTint.eyes(on: body)
            #expect(abs(Self.luminance(of: eyes) - luminance) > 0.3,
                    "\(provider.rawValue) has no contrast between body and eyes")
        }
    }

    /// The whole point of dealing colours is that the rail is not a row of
    /// identical bots. A hash over the ids was tried first and collided: six
    /// of the original set shared two colours.
    @Test("A rail of colourless providers gives every provider a distinct colour")
    func dealtColoursAreDistinct() {
        let colourless = Provider.allCases.filter { BotMarkTint.brand(for: $0) == nil }
        let colours = BotMarkTint.deal(over: colourless).map(\.hexString)
        #expect(colours.allSatisfy { $0 != nil })
        #expect(Set(colours).count == colourless.count)
    }

    /// Distinct is not enough — two greens 20° apart are distinct and still
    /// read as one colour on a rail. What matters is the pair a reader
    /// actually sees together, which is the pair drawn next to each other.
    @Test("Neighbours on a rail are never near each other in hue")
    func neighboursAreFarApart() {
        // Every rail worth worrying about: the whole list, and the awkward
        // ones where a brand colour sits between two dealt colours.
        let rails: [[Provider]] = [
            Provider.allCases,
            [.claudeCode, .codex, .cursor, .openCodeGo, .kimiCode, .glmCoding, .devin],
            [.claudeCode, .codex],
            [.deepSeek, .grok, .volcengine, .grokBot, .antigravity, .copilot],
            [.minimax, .cursor, .minimaxCN, .devin],
        ]
        for rail in rails {
            let hues = BotMarkTint.deal(over: rail).map(Self.hue(of:))
            for index in hues.indices.dropLast() {
                // Two brand colours side by side are what those brands are —
                // MiniMax's two rows really are one red. Only a pair with a
                // dealt colour in it is this code's to get right.
                guard BotMarkTint.isDealt(rail[index]) || BotMarkTint.isDealt(rail[index + 1]) else {
                    continue
                }
                let gap = Self.separation(hues[index], hues[index + 1])
                #expect(gap >= 30,
                        "\(rail[index].rawValue) and \(rail[index + 1].rawValue) sit \(Int(gap))° apart")
            }
        }
    }

    /// Two accounts of one provider draw one brand, and a rail is dealt the
    /// same way every time it is built — a mark that changed colour between
    /// two frames would be worse than a white one.
    @Test("Dealing is stable for a given rail")
    func dealIsStable() {
        let rail: [Provider] = [.claudeCode, .codex, .cursor, .grok, .devin]
        let first = BotMarkTint.deal(over: rail).map(\.hexString)
        let second = BotMarkTint.deal(over: rail).map(\.hexString)
        #expect(first == second)
    }

    /// A colour somebody picked is used as picked — and the rings beside it
    /// are dealt away from it, exactly as they are from a brand colour.
    @Test("A chosen colour is kept, and neighbours still avoid it")
    func chosenColoursAreHonoured() {
        let rail: [Provider] = [.cursor, .grok, .devin]
        let pink = BotMarkPalette.rgb(0xFF66CC)
        let dealt = BotMarkTint.deal(over: rail, chosen: [nil, pink, nil])
        #expect(dealt[1].hexString == pink.hexString, "the chosen colour was overwritten")
        for index in [0, 2] {
            let gap = Self.separation(Self.hue(of: dealt[index]), Self.hue(of: pink))
            #expect(gap >= 30, "a neighbour was dealt \(Int(gap))° from the chosen colour")
        }
        // And with nothing chosen the rail deals as it always did.
        #expect(BotMarkTint.deal(over: rail).count == rail.count)
    }

    /// A provider that carries a brand colour keeps it — the dealt palette is
    /// only for the ones that do not.
    @Test("A brand colour is never overwritten")
    func brandWins() {
        #expect(BotMarkTint.brand(for: .claudeCode) != nil)
        #expect(BotMarkTint.body(for: .claudeCode).hexString
                == BotMarkTint.brand(for: .claudeCode)?.hexString)
    }

    /// A black brand keeps its hue when it is lifted — the point is to make it
    /// visible, not to turn every dark mark into the same grey.
    @Test("Lifting a dark colour keeps its hue")
    func liftKeepsHue() {
        let body = BotMarkTint.body(for: .deepSeek)
        let colour = NSColor(body).usingColorSpace(.sRGB)!
        #expect(colour.blueComponent > colour.redComponent)
    }

    /// A persona may change how a mood is said, never what it says. This is
    /// the rule that keeps the rail honest: no character may claim work is
    /// happening when it is not, or look idle about a spent limit.
    @Test("No persona contradicts the reading")
    func personasStayHonest() {
        // The states each mood is allowed to be played as, by meaning.
        let allowed: [BotMarkMood: Set<String>] = [
            // Only the sleepy persona can add a drowsy night-time accent.
            // `listening` is idle with the pointer on this ring.
            .idle: ["idle", "listening", "humming", "drowsy", "proud", "curious", "playful",
                    "happy", "shy", "suspicious", "surprised", "laughing", "bouncing"],
            .working: ["working", "excited", "searching", "thinking", "writing", "spawning",
                       "orbit", "radar", "loading", "receiving"],
            .fetching: ["searching", "listening", "receiving", "spawning", "radar", "loading", "orbit", "thinking"],
            .spent: ["sad", "drowsy", "shy", "scared", "angry", "surprised", "suspicious", "alerting"],
            .unavailable: ["confused", "drowsy", "listening", "surprised", "suspicious", "shy"],
        ]
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                for state in persona.routine(for: mood).states {
                    #expect(allowed[mood]?.contains(state) == true,
                            "\(persona.rawValue) plays \(state) for \(mood.rawValue)")
                    #expect(BotMarkLibrary.shared.state(state).id == state)
                }
            }
        }
    }

    /// The shape list is offered to the reader, so every entry has to draw
    /// something — a picker row that renders nothing is worse than no row.
    @Test("Every shape in the picker exists in the data")
    func bodyShapesAreReal() {
        #expect(BotMarkBody.allCases.count == BotMarkLibrary.shared.shapes.count)
        for body in BotMarkBody.allCases {
            #expect(BotMarkLibrary.shared.shapes[body.shape] != nil,
                    "no shape named \(body.shape)")
        }
        // Round by default, and stored as an absence, so nothing has to be
        // written for the common case.
        #expect(BotMarkBody.default == .blob)
        #expect(BotMarkBody(rawValue: "a shape that was removed") == nil)
    }

    /// Automatic dealing exists so neighbours are different characters.
    @Test("Neighbouring rings are dealt different personas")
    func automaticPersonasDiffer() {
        for index in 0..<40 {
            #expect(BotMarkPersona.automatic(at: index)
                    != BotMarkPersona.automatic(at: index + 1))
        }
        // And a rail no longer than the cast has no repeats at all.
        let rail = (0..<BotMarkPersona.allCases.count).map(BotMarkPersona.automatic(at:))
        #expect(Set(rail).count == BotMarkPersona.allCases.count)
    }

    /// A rail on the right edge has to look left, and the only way to see
    /// that without a screenshot is to read where the eyes were actually put.
    ///
    /// The autonomous gaze is switched off for the comparison (`gazeScale` 0),
    /// so the two runs differ by the lean and nothing else — otherwise the
    /// random glances would make this flake.
    @Test("The gaze lean moves the eyes, and the right way")
    func gazeLeanMovesTheEyes() {
        func eyeCentre(_ gaze: BotMarkGaze) -> Double {
            var programme = BotMarkProgramme(states: ["idle"])
            programme.gazeScale = 0
            programme.gazeBias = gaze.bias
            programme.flipX = gaze.mirrored
            let engine = BotMarkEngine()
            var time = 0.0
            var frame = engine.advance(to: time, programme: programme)
            while time < 2 {
                time += 1.0 / 60
                frame = engine.advance(to: time, programme: programme)
            }
            // Both eyes, so a wink or a blink cannot tilt the reading. No
            // correction for the turn: it is applied to where the eyes were
            // put, so what is read here is already what is drawn.
            return frame.eyes.map { Double($0.transform.tx) }.reduce(0, +) / 2
        }

        let ahead = eyeCentre(.ahead)
        #expect(eyeCentre(.left) < ahead - 3, "looking left did not move the eyes left")
        #expect(eyeCentre(.right) > ahead + 3, "looking right did not move the eyes right")
    }

    /// The lean alone is not enough, which is the whole reason the mirror
    /// exists — and the reason the test above is not the test that matters.
    ///
    /// Several upstream states rest with the eyes well off to one side, and a
    /// standing lean of 7 units cannot pull a pose that is 27 units out back
    /// across the middle. Measured on the worst of them: `sleepy` at rest,
    /// which sat right of centre on all but a handful of frames until the mark
    /// was mirrored. Ten minutes at 30fps, so a glance every few seconds is
    /// sampled hundreds of times and the average is not a coin toss.
    @Test("A right-hand rail does not spend its time facing the screen edge")
    func lopsidedStatesStillFaceInward() {
        func meanGaze(_ persona: BotMarkPersona, _ mood: BotMarkMood,
                      _ gaze: BotMarkGaze) -> Double {
            var programme = Self.programme(persona, mood)
            programme.gazeBias = gaze.bias
            programme.flipX = gaze.mirrored
            let engine = BotMarkEngine()
            var time = 0.0
            var samples: [Double] = []
            while time < 600 {
                time += 1.0 / 30
                let frame = engine.advance(to: time, programme: programme)
                // Morphs move the character deliberately, and a hidden eye is
                // a body mid-spin rather than a mark looking anywhere.
                guard frame.morphAmount < 0.01, frame.eyes.count == 2,
                      frame.eyes.allSatisfy({ $0.visible }) else { continue }
                let centre = CGPoint(x: BotMarkFrame.viewBoxCentre,
                                     y: BotMarkFrame.viewBoxCentre)
                    .applying(frame.transform).x
                var sum = 0.0
                for eye in frame.eyes {
                    var transform = eye.transform.concatenating(frame.transform)
                    guard let path = eye.path.copy(using: &transform) else { return 0 }
                    sum += Double(path.boundingBoxOfPath.midX)
                }
                samples.append(sum / 2 - Double(centre))
            }
            return samples.reduce(0, +) / Double(samples.count)
        }

        // Every character, at rest and at work, on a rail against the right
        // edge. None of them may average out looking at the edge.
        for persona in BotMarkPersona.allCases {
            for mood in [BotMarkMood.working, .idle] {
                let aimed = meanGaze(persona, mood, .left)
                #expect(aimed < 0,
                        "\(persona) \(mood) averages \(aimed) — right of centre on a right-hand rail")
            }
        }
    }

    /// Dragging the rail to the other edge turns the mark round; opening the
    /// panel does not.
    ///
    /// The mirror is a scale of -1, and a scale that changes between one frame
    /// and the next swaps the character for its own reflection with nothing in
    /// between. Sprung, it passes edge-on and comes round. But a mark appearing
    /// already mirrored has not turned anywhere, so the first frame snaps —
    /// otherwise every mark on a right-hand rail would spin on launch.
    @Test("Changing edge turns the mark; appearing on one does not")
    func facingTurnsRatherThanSwaps() {
        func frames(flipped: Bool, from engine: BotMarkEngine,
                    start: Double, seconds: Double) -> [Double] {
            var programme = BotMarkProgramme(states: ["idle"])
            programme.flipX = flipped
            var time = start
            var facings: [Double] = []
            while time < start + seconds {
                facings.append(engine.advance(to: time, programme: programme).facing)
                time += 1.0 / 60
            }
            return facings
        }

        // Appearing mirrored: settled from the very first frame.
        let fresh = BotMarkEngine()
        let onAppear = frames(flipped: true, from: fresh, start: 0, seconds: 0.5)
        #expect(onAppear.allSatisfy { $0 < -0.99 }, "a mark that appeared mirrored animated its flip")

        // Settled facing one way, then the rail moves to the other edge.
        let moved = BotMarkEngine()
        _ = frames(flipped: false, from: moved, start: 0, seconds: 1)
        let turn = frames(flipped: true, from: moved, start: 1, seconds: 1)
        #expect(turn.first! > 0.9, "the turn did not start from where the mark was")
        #expect(turn.last! < -0.9, "the mark never finished turning")
        // Straight ahead somewhere in the middle, which is what makes it a
        // look across rather than a jump.
        #expect(turn.contains { abs($0) < 0.3 }, "the mark swapped sides without passing through")
        // And it takes a moment: an instant flip would clear 0.3 in one frame.
        let crossing = turn.filter { abs($0) < 0.9 }.count
        #expect(crossing >= 6, "the turn took \(crossing) frames — too fast to read as motion")
    }

    /// The eyes look across; the body stays where it is.
    ///
    /// This is the shape of the first attempt's mistake, written down. Turning
    /// the mark round was done by mirroring the whole drawing, which aimed the
    /// eyes correctly and flipped the body over like a card — the right answer
    /// to the wrong question. A rail being dragged from one edge to the other
    /// should look like a character glancing over, so the eyes have to move
    /// and the body has to not.
    @Test("Turning moves the eyes and leaves the body alone")
    func turningMovesOnlyTheEyes() {
        func sample(flipped: Bool, from engine: BotMarkEngine,
                    start: Double, seconds: Double) -> [(eyes: Double, body: CGAffineTransform)] {
            var programme = BotMarkProgramme(states: ["bored"])
            programme.flipX = flipped
            var time = start
            var out: [(Double, CGAffineTransform)] = []
            while time < start + seconds {
                let frame = engine.advance(to: time, programme: programme)
                if frame.eyes.count == 2 {
                    // Where the eyes are actually drawn, not their transform's
                    // translation: the reflection moves each ring's own centroid,
                    // which that translation cancels against.
                    var sum = 0.0
                    for eye in frame.eyes {
                        var transform = eye.transform.concatenating(frame.transform)
                        guard let path = eye.path.copy(using: &transform) else { continue }
                        sum += Double(path.boundingBoxOfPath.midX)
                    }
                    let centre = CGPoint(x: BotMarkFrame.viewBoxCentre,
                                         y: BotMarkFrame.viewBoxCentre)
                        .applying(frame.transform).x
                    out.append((sum / 2 - Double(centre), frame.transform))
                }
                time += 1.0 / 60
            }
            return out
        }

        let engine = BotMarkEngine()
        let before = sample(flipped: false, from: engine, start: 0, seconds: 60)
        let after = sample(flipped: true, from: engine, start: 60, seconds: 60)

        // **Averaged over a minute, not over the last half-second.** `bored`
        // takes a fresh glance every three to six seconds, so a short tail
        // lands on whichever one happened to be running and the average is a
        // coin toss — which is what made the first version of this flake.
        func settled(_ frames: [(eyes: Double, body: CGAffineTransform)]) -> Double {
            // Past the first second, so the turn itself is not in the average.
            let tail = frames.dropFirst(60)
            return tail.map(\.eyes).reduce(0, +) / Double(tail.count)
        }
        // `bored` is one of the expressions drawn well off to one side, which
        // is exactly the case the mirror exists for.
        let settledBefore = settled(before)
        let settledAfter = settled(after)
        #expect(settledBefore > 0, "the sideways expression was not looking right to begin with")
        #expect(settledAfter < 0, "the eyes never came across")

        // The body is never mirrored and never jumps. Its horizontal scale
        // stays positive throughout — a mirror would send it through zero to
        // -1 — and it moves no further across the turn than it does at rest.
        #expect(after.allSatisfy { $0.body.a > 0 }, "the body was mirrored")
        func travel(_ frames: [(eyes: Double, body: CGAffineTransform)]) -> Double {
            let xs = frames.map { Double($0.body.tx) }
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        // Half again as much, not a hair more: both runs are a minute of the
        // body's own random bob, so their extents agree to within noise and a
        // tolerance of ±1 made this flake. What it has to catch is a body that
        // *turns over*, which sweeps it through its whole width — several
        // times this — and which `body.a > 0` above already rules out.
        #expect(travel(after) <= travel(before) * 1.5 + 2,
                "the body moved \(travel(after)) across the turn against \(travel(before)) at rest")
    }

    /// Which way each edge looks. A rail on the right edge of the screen has
    /// the screen to its left.
    @Test("The rail's edge decides the lean")
    func edgesLeanInward() {
        #expect(BotMarkGaze(edge: .right) == .left)
        #expect(BotMarkGaze(edge: .left) == .right)
        // A top rail has screen on both sides of it.
        #expect(BotMarkGaze(edge: .top) == .ahead)
        #expect(BotMarkGaze.ahead.bias == 0)
        // The engine leans the same way whichever edge it is; the mirror is
        // what turns a right-hand rail around.
        #expect(BotMarkGaze.left.bias == BotMarkGaze.right.bias)
        #expect(BotMarkGaze.left.mirrored)
        #expect(!BotMarkGaze.right.mirrored)
        #expect(!BotMarkGaze.ahead.mirrored)
    }

    /// Working has to be visible *as* working at ring size, which is the one
    /// thing the removal of the white activity arc put on this code. Measured
    /// as the peak-to-peak rotation of the body over three seconds, read off
    /// the frame transform — a still cannot show it and a screenshot cannot
    /// measure it.
    @Test("Working moves visibly more than idle")
    func workingIsVisiblyBusy() {
        /// Peak-to-peak rotation, and how much the drawn body's height
        /// changes as a fraction of itself.
        func swing(_ mood: BotMarkMood) -> (degrees: Double, pump: Double) {
            // One state, so the measurement is of the motion and not of the
            // playlist moving on.
            var programme = BotMarkProgramme(states: [BotMarkPersona.calm.state(for: mood)])
            programme.mood = mood
            programme.rotationScale = mood.rotationEmphasis
            programme.squashScale = mood.squashEmphasis
            programme.tempo = mood.tempoEmphasis
            let engine = BotMarkEngine()
            var time = 0.0
            var lowest = Double.infinity
            var highest = -Double.infinity
            var shortest = Double.infinity
            var tallest = -Double.infinity
            // Past the state's own settle, then sampled for three seconds.
            while time < 5 {
                time += 1.0 / 60
                let frame = engine.advance(to: time, programme: programme)
                guard time > 2 else { continue }
                let degrees = atan2(Double(frame.transform.b), Double(frame.transform.a))
                    * 180 / .pi
                lowest = min(lowest, degrees)
                highest = max(highest, degrees)
                shortest = min(shortest, Self.drawnHeight(frame))
                tallest = max(tallest, Self.drawnHeight(frame))
            }
            let pump = (tallest - shortest) / tallest
            print("\(mood.rawValue): \(String(format: "%.1f", highest - lowest))° swing, "
                  + "\(String(format: "%.1f", pump * 100))% pump")
            return (highest - lowest, pump)
        }

        let idle = swing(.idle)
        let working = swing(.working)
        #expect(working.pump > idle.pump * 1.5, "working does not breathe harder than idle")
        #expect(working.degrees > idle.degrees * 2, "working does not rock more than idle")
        // **And it has to stay a pulse.** An emphasis that resizes the mark
        // reads as a glitch, not as work: ten was tried, came out at 20% of
        // the body's height, and was reported as the bot growing and
        // shrinking. Every persona, every mood, inside a hand's breadth of
        // its resting height.
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let engine = BotMarkEngine()
                var time = 0.0
                var resting: Double?
                while time < 6 {
                    time += 1.0 / 60
                    let frame = engine.advance(to: time,
                                               programme: Self.programme(persona, mood))
                    let height = Self.drawnHeight(frame)
                    // A second in, so the state's own arrival is not the
                    // baseline — and never mid-morph: `spawning` and `writing`
                    // shrink the character to a fifth *on purpose*, because
                    // the effect is what is being shown, and that is not the
                    // squash this is guarding.
                    guard time > 1, frame.morphAmount < 0.01 else { continue }
                    let base = resting ?? height
                    resting = base
                    let ratio = String(format: "%.2f", height / base)
                    #expect(height / base > 0.82 && height / base < 1.2,
                            "\(persona.rawValue)/\(mood.rawValue) drew at \(ratio) of its height")
                }
            }
        }
    }

    /// The ribbons are the one cue that unmistakably reads as "this is doing
    /// something" at ring size, and they only appear when the body spins. If
    /// a refactor ever stops the working state spinning, or leaves particles
    /// gated off at this size, nothing crashes — the rail just goes quiet
    /// again, which is the bug this is here to catch.
    @Test("A working mark throws ribbons")
    func workingDrawsRibbons() {
        var programme = Self.programme(.calm, .working)
        programme.viewWidth = 25
        let engine = BotMarkEngine()
        var time = 0.0
        var framesWithRibbons = 0
        // Long enough for calm's complete authored scene and another pass at
        // its moving face. Historically a twelve-second random playlist could
        // omit `working` entirely; the ordered scene now visits every beat,
        // but a sample still has to include its morphs and settling time.
        var states: Set<String> = []
        while time < 30 {
            time += 1.0 / 60
            let frame = engine.advance(to: time, programme: programme)
            states.insert(engine.state)
            if !frame.backParticles.isEmpty || !frame.frontParticles.isEmpty {
                framesWithRibbons += 1
            }
        }
        print("ribbons over 30s, states seen: \(states.sorted().joined(separator: ", "))")
        print("ribbons on \(framesWithRibbons) of \(Int(30 * 60)) frames")
        #expect(framesWithRibbons > 60, "no ribbons in thirty seconds of working")
    }

    /// The head may not leave the canvas: the viewBox has about 15 units of
    /// margin around the body, and `drowsy` nods 25.
    @Test("No state pushes the head off its canvas")
    func headStaysInsideTheCanvas() {
        for persona in BotMarkPersona.allCases {
            for mood in BotMarkMood.allCases {
                let engine = BotMarkEngine()
                var time = 0.0
                while time < 8 {
                    time += 1.0 / 60
                    let frame = engine.advance(to: time,
                                               programme: Self.programme(persona, mood))
                    // A morph moves the character on purpose — the pencil
                    // walks it across the canvas as it writes — and brings its
                    // own viewBox. Only the plain body is bounded.
                    guard frame.morphAmount < 0.01 else { continue }
                    // Where the body's own centre actually lands, by running
                    // it through the frame's transform — reading `tx` off the
                    // matrix instead mixes in the rotation about that centre.
                    let centre = BotMarkLibrary.shared.headCentre
                    let drawn = CGPoint(x: centre, y: centre).applying(frame.transform)
                    let slid = max(abs(Double(drawn.x) - centre), abs(Double(drawn.y) - centre))
                    #expect(slid < 13,
                            "\(persona.rawValue)/\(mood.rawValue) slid \(Int(slid)) units")
                }
            }
        }
    }

    /// A one-shot has to interrupt the playlist, play once, and hand it back
    /// — and it must not replay for as long as the fact stays true, which for
    /// a reset is twenty seconds of frames.
    @Test("An event plays once and gives the playlist back")
    func eventsPlayOnce() {
        var programme = Self.programme(.calm, .working)
        programme.event = .limitReset
        let engine = BotMarkEngine()
        var time = 0.0
        var celebrating = 0
        var afterwards: Set<String> = []
        while time < 14 {
            time += 1.0 / 60
            _ = engine.advance(to: time, programme: programme)
            if engine.state == "celebrate" { celebrating += 1 }
            if time > 8 { afterwards.insert(engine.state) }
        }
        // The celebrate cycle is 6.2s upstream and gets the whole of it.
        #expect(celebrating > 300, "the celebration did not hold")
        #expect(!afterwards.contains("celebrate"),
                "the event replayed while its fact was still true")
        #expect(!afterwards.isEmpty)
    }

    /// Silence and night only add a doze to the sleepy character's playlist.
    @Test("Only the sleepy persona adds a night-time doze")
    func quietIdleStates() {
        for persona in BotMarkPersona.allCases {
            let busy = persona.idleStates(quiet: false, night: false)
            let quiet = persona.idleStates(quiet: true, night: false)
            let night = persona.idleStates(quiet: true, night: true)
            #expect(busy.first == persona.state(for: .idle))
            #expect(busy.count >= 3)
            #expect(quiet == busy)
            #expect(night.first == persona.state(for: .idle))
            #expect(night.contains("drowsy") == (persona == .sleepy))
            // Repeating a state would make the engine choose an identical pose.
            #expect(Set(quiet).count == quiet.count)
            #expect(Set(night).count == night.count)
        }
    }

    /// Work out of hours is still work: `angry` joins the playlist and the
    /// states that mean work stay in it.
    @Test("Out of hours adds anger without dropping the work")
    func overtimeAddsAnger() {
        for persona in BotMarkPersona.allCases {
            let day = persona.workingStates(overtime: false)
            let night = persona.workingStates(overtime: true)
            #expect(!day.contains("angry"))
            #expect(night.contains("angry"))
            #expect(night.count == day.count + 1)
            #expect(Set(night).count == night.count)
            for state in day { #expect(night.contains(state)) }
            // Three at least, or it is a loop again.
            #expect(day.count >= 3)
            for state in day {
                #expect(BotMarkLibrary.shared.state(state).id == state)
            }
        }
    }

    /// The hours themselves are a guess, but the rule has to be the rule.
    @Test("Overtime is nights and weekends")
    func overtimeHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int) -> Date {
            // 2026-09-14 is a Monday, so day 14…20 walks a whole week.
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        #expect(!BotMarkHours.isOvertime(at: at(14, 10), calendar: calendar))
        #expect(!BotMarkHours.isOvertime(at: at(18, 20), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 8), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 21), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(14, 2), calendar: calendar))
        // Saturday and Sunday, in the middle of the working day.
        #expect(BotMarkHours.isOvertime(at: at(19, 14), calendar: calendar))
        #expect(BotMarkHours.isOvertime(at: at(20, 14), calendar: calendar))
    }

    /// The three shapes whose turn profile is solved from spheres in 3D are
    /// the only ones that touch `turnedShapeRing`'s solid branch — where a
    /// cached baseline and a per-point `profile[index]` live. Nothing else
    /// exercises them, so a body chosen from the picker could crash on a spin
    /// that no test had ever run.
    @Test("A solid body survives being spun")
    func solidBodiesTurn() {
        let solids: [BotMarkBody] = [.bean, .tablet, .cloud]
        for body in solids {
            #expect(BotMarkLibrary.shared.shape(body.shape).solid != nil,
                    "\(body.shape) is not one of the solid shapes any more")
            var programme = Self.programme(.playful, .working)   // playful spins
            programme.shape = body.shape
            let engine = BotMarkEngine()
            var time = 0.0
            // Long enough for the ambient gestures to spin it at least once.
            while time < 20 {
                time += 1.0 / 60
                let frame = engine.advance(to: time, programme: programme)
                let drawn = frame.headPath.boundingBoxOfPath
                #expect(drawn.width.isFinite && drawn.height.isFinite,
                        "\(body.shape) drew a non-finite outline")
                #expect(drawn.width > 0, "\(body.shape) collapsed to nothing")
            }
        }
    }

    /// Aiming a mark does not push its eyes out of its face.
    ///
    /// An expression is drawn already looking somewhere — `eyeReach`, up to 76
    /// units off the head's centre — and the lean, the state's own glance and
    /// the pointer are added on top of that. Stacked the same way they put an
    /// eye outside the silhouette, where it is clipped: at ring size that is a
    /// mark with one eye missing, which is exactly what it looked like on a
    /// real rail. The fix is a ceiling plus a small final silhouette inset —
    /// what Pulse adds fits under what the artwork already does, and an eye at
    /// the bound still has enough room to render whole at ring size. This is
    /// the measurement that caught it.
    ///
    /// Measured as the share of frames where an eye overhangs the body rather
    /// than as a worst case, because a worst case here is legitimate: a mark
    /// mid-spin has an eye travelling round to the limb, and that one is meant
    /// to slide off the edge. What is not legitimate is it happening all the
    /// time. Before the ceiling, `proud` at rest overhung on 13% of its frames
    /// and `sleepy` at work on 7%; the whole rail now sits under 3%.
    @Test("Turning a mark does not push its eyes out of its face")
    func aimingKeepsTheEyesInTheFace() {
        func overhang(_ persona: BotMarkPersona, _ mood: BotMarkMood) -> Double {
            var programme = Self.programme(persona, mood)
            // Turned to face the screen, which is the case that stacks: the
            // reflected artwork, the lean and the glance all pull one way.
            // Deliberately *without* a pointer — a pointer on the panel damps
            // the autonomous glance to a fifth, so parking one here would hide
            // the very thing being measured.
            programme.gazeBias = BotMarkGaze.left.bias
            programme.flipX = BotMarkGaze.left.mirrored
            let engine = BotMarkEngine()
            var time = 0.0
            var outside = 0
            var total = 0
            // Ten minutes, not four. The share is a frame count over random
            // glances, and at four minutes the spread put a fixed rail at 4.0%
            // against a threshold of 4 — the bound was fine and the sample was
            // not. A longer run separates ~3% fixed from ~5-13% broken with
            // room to spare.
            while time < 600 {
                time += 1.0 / 30
                let frame = engine.advance(to: time, programme: programme)
                guard frame.morphAmount < 0.01, frame.eyes.count == 2,
                      frame.eyes.allSatisfy({ $0.visible }) else { continue }
                var bodyTransform = frame.transform
                guard let headPath = frame.headPath.copy(using: &bodyTransform) else { continue }
                let body = headPath.boundingBoxOfPath
                for eye in frame.eyes {
                    var transform = eye.transform.concatenating(frame.transform)
                    guard let path = eye.path.copy(using: &transform) else { continue }
                    let drawn = path.boundingBoxOfPath
                    total += 1
                    // Clearance to the nearer side of the body, as a share of
                    // its width. An eye hard against the edge is the symptom:
                    // it is clipped to the silhouette, so what is left of it
                    // reads as half an eye or none.
                    let clearance = min(drawn.minX - body.minX, body.maxX - drawn.maxX)
                    if clearance / body.width < 0.02 { outside += 1 }
                }
            }
            return Double(outside) / Double(total) * 100
        }

        for persona in BotMarkPersona.allCases {
            for mood in [BotMarkMood.working, .idle] {
                let share = overhang(persona, mood)
                #expect(share < 4,
                        "\(persona) \(mood) has an eye off the body on \(share)% of frames")
            }
        }
    }

    /// Somebody pointing at a ring outranks everything the mark would rather
    /// be looking at.
    ///
    /// Two of the three things aiming a mark are much larger than the pointer:
    /// the expression's built-in glance reaches 76 units and the standing lean
    /// is 7, against a pointer worth 22. On a rail against the right-hand edge
    /// they pull the same way, so the mark went on staring left with the
    /// cursor sitting on its right — which is the opposite of the behaviour
    /// the pointer exists for. Upstream already damps the state's own glance
    /// to a fifth while the pointer is on the panel; the lean and the artwork
    /// now give way in the same measure.
    ///
    /// Checked on the hard case: every persona, turned to face the screen, so
    /// the habits and the pointer disagree.
    @Test("The pointer outranks the lean and the expression")
    func pointerWinsOverHabit() {
        func eyes(_ persona: BotMarkPersona, pointerX: Double) -> Double {
            var programme = Self.programme(persona, .idle)
            programme.gazeBias = BotMarkGaze.left.bias
            programme.flipX = BotMarkGaze.left.mirrored
            programme.pointer = CGPoint(x: pointerX, y: 0)
            let engine = BotMarkEngine()
            var time = 0.0
            var settled: [Double] = []
            while time < 30 {
                time += 1.0 / 30
                let frame = engine.advance(to: time, programme: programme)
                guard frame.eyes.count == 2, frame.eyes.allSatisfy({ $0.visible }) else { continue }
                let centre = CGPoint(x: BotMarkFrame.viewBoxCentre,
                                     y: BotMarkFrame.viewBoxCentre)
                    .applying(frame.transform).x
                var sum = 0.0
                for eye in frame.eyes {
                    var transform = eye.transform.concatenating(frame.transform)
                    guard let path = eye.path.copy(using: &transform) else { return .nan }
                    sum += Double(path.boundingBoxOfPath.midX)
                }
                // Past the first few seconds, so the springs have arrived.
                if time > 5 { settled.append(sum / 2 - Double(centre)) }
            }
            return settled.reduce(0, +) / Double(settled.count)
        }

        for persona in BotMarkPersona.allCases {
            let looksLeft = eyes(persona, pointerX: -1)
            let looksRight = eyes(persona, pointerX: 1)
            #expect(looksRight > looksLeft + 8,
                    "\(persona) barely moved: \(looksLeft) with the pointer left, \(looksRight) with it right")
            // And it is not merely a shift — the eyes end up on the side the
            // pointer is actually on.
            #expect(looksLeft < 0, "\(persona) did not look left at a pointer on its left")
            #expect(looksRight > 0, "\(persona) did not look right at a pointer on its right")
        }
    }

    /// The programme a ring would hand the engine for this pair, so a test
    /// measures what the rail actually plays.
    private static func programme(_ persona: BotMarkPersona,
                                  _ mood: BotMarkMood) -> BotMarkProgramme {
        BotMarkProgramme.forMood(mood, persona: persona, at: weekday, calendar: calendar)
    }

    private static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()
    private static let weekday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!

    /// The height of the body as it is actually drawn.
    ///
    /// **The path is transformed, not its bounding box.** Transforming the
    /// box rotates a rectangle, and the axis-aligned box of a rotated
    /// rectangle is taller than the shape inside it — which reads as the body
    /// growing every time it leans. That artefact is what made the first
    /// version of this measurement fail on a persona that merely tilts.
    private static func drawnHeight(_ frame: BotMarkFrame) -> Double {
        var transform = frame.transform
        guard let path = frame.headPath.copy(using: &transform) else { return 0 }
        return Double(path.boundingBoxOfPath.height)
    }

    private static func hue(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 0 }
        return Double(base.hueComponent) * 360
    }

    /// The shorter way round the colour wheel.
    private static func separation(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func luminance(of colour: Color) -> Double {
        guard let base = NSColor(colour).usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * base.redComponent
            + 0.7152 * base.greenComponent
            + 0.0722 * base.blueComponent
    }
}
