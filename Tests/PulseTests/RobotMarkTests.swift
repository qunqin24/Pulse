import Foundation
import SwiftUI
import Testing
@testable import Pulse

/// The robot shows only what Pulse has seen, one fact at a time, and each
/// mood ends up in the original avatar's pose for it.
@Suite("Robot in the ring")
struct RobotMarkTests {
    // MARK: - Facts to mood

    @Test("Nothing happening is idle")
    func idle() {
        #expect(RobotMood.resolve(hasReading: true, isSpent: false, isWorking: false, isRefreshing: false) == .idle)
    }

    @Test("A refresh outranks everything, then the CLI working")
    func order() {
        #expect(RobotMood.resolve(hasReading: false, isSpent: true, isWorking: true, isRefreshing: true) == .refreshing)
        #expect(RobotMood.resolve(hasReading: false, isSpent: true, isWorking: true, isRefreshing: false) == .working)
        #expect(RobotMood.resolve(hasReading: true, isSpent: true, isWorking: true, isRefreshing: false) == .working)
    }

    @Test("No reading is asleep, even with a remembered spent limit")
    func noReading() {
        #expect(RobotMood.resolve(hasReading: false, isSpent: false, isWorking: false, isRefreshing: false) == .asleep)
        #expect(RobotMood.resolve(hasReading: false, isSpent: true, isWorking: false, isRefreshing: false) == .asleep)
    }

    @Test("Spent only when the provider says so")
    func spent() {
        #expect(RobotMood.resolve(hasReading: true, isSpent: true, isWorking: false, isRefreshing: false) == .spent)
    }

    @Test("With ring activity off, working and refreshing are not shown")
    func activityOff() {
        #expect(RobotMood.resolve(hasReading: true, isSpent: false, isWorking: true, isRefreshing: true,
                                  activity: false) == .idle)
        #expect(RobotMood.resolve(hasReading: true, isSpent: true, isWorking: true, isRefreshing: false,
                                  activity: false) == .spent)
    }

    @Test("A reset cheers, a finished turn nods, and a reset wins")
    func gestures() {
        #expect(RobotCue().gesture == nil)
        #expect(RobotCue(justReset: true).gesture == .cheer)
        #expect(RobotCue(justFinished: true).gesture == .nod)
        #expect(RobotCue(justReset: true, justFinished: true).gesture == .cheer)
    }

    // MARK: - Mood to face

    /// A motion with fixed randomness, so blinks and glances land the same
    /// way every run.
    private func motion() -> RobotMotion {
        let motion = RobotMotion()
        motion.random = { 0.5 }
        return motion
    }

    /// Steps a motion at thirty frames a second from `start` for `seconds`.
    private func run(_ motion: RobotMotion, mood: RobotMood, from start: TimeInterval,
                     for seconds: TimeInterval) -> RobotFrame {
        var frame = motion.frame(at: start, mood: mood)
        var now = start
        while now < start + seconds {
            now += 1 / 30
            frame = motion.frame(at: now, mood: mood)
        }
        return frame
    }

    @Test("A panel opening on a sleeping robot shows it asleep, not falling asleep")
    func firstFrameIsSettled() {
        let frame = motion().frame(at: 100, mood: .asleep)
        #expect(Double(frame.left.topLid) == RobotPose.asleep.topLid)
        #expect(Double(frame.left.bottomLid) == RobotPose.asleep.bottomLid)
        #expect(frame.headDrop == 4)
    }

    @Test("Falling asleep ends with the lids in a slit and the timeline free to stop")
    func fallsAsleep() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        let frame = run(motion, mood: .asleep, from: 1, for: 4)
        #expect(Double(frame.left.topLid) == RobotPose.asleep.topLid)
        #expect(Double(frame.left.bottomLid) == RobotPose.asleep.bottomLid)
        #expect(abs(frame.headDrop - 4) < 0.01)
        #expect(motion.isAtRest(at: 5))
    }

    @Test("Spent holds the failure pose: sad lids, head and eyes lowered")
    func spentHolds() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        let frame = run(motion, mood: .spent, from: 1, for: 10)
        #expect(Double(frame.left.tilt) == RobotPose.sad.leftTilt)
        #expect(Double(frame.right.tilt) == RobotPose.sad.rightTilt)
        #expect(abs(frame.headDrop - 5.5) < 0.01)
        #expect(abs(frame.left.centre.y - (RobotFace.eyeY + 4.8)) < 0.5)
        #expect(!motion.isAtRest(at: 11))
    }

    @Test("Working circles the eyes round each other")
    func workingOrbits() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        let a = run(motion, mood: .working, from: 1, for: 1)
        let b = run(motion, mood: .working, from: 2, for: 0.8)
        #expect(abs(a.left.centre.x - b.left.centre.x) > 10)
        // The orbit is a round trip through the middle: both eyes stay
        // within the head's width.
        #expect((86...154).contains(Double(a.left.centre.x)))
    }

    @Test("Reduced motion holds still poses, with the waiting eyes drawn together")
    func reducedMotion() {
        let motion = motion()
        let first = motion.frame(at: 0, mood: .working, reduceMotion: true)
        let later = motion.frame(at: 2, mood: .working, reduceMotion: true)
        #expect(first == later)
        #expect(first.left.centre.x == 100)
        #expect(first.right.centre.x == 140)
    }

    @Test("A nod plays once and returns to the mood")
    func nodReturns() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        motion.play(.nod, at: 1)
        #expect(motion.gesture == .nod)
        let mid = run(motion, mood: .idle, from: 1, for: 0.65)
        // The eyes dip in the middle of the nod.
        #expect(mid.left.centre.y > RobotFace.eyeY + 10)
        _ = run(motion, mood: .idle, from: 1.65, for: 1)
        #expect(motion.gesture == nil)
    }

    // MARK: - Personality, colour, shape

    @Test("Automatic picks differ from the robot before, and a choice is kept")
    func spread() {
        let options = ["a", "b", "c"]
        let all = RobotAutomatic.spread([String?](repeating: nil, count: 7), over: options)
        for (left, right) in zip(all, all.dropFirst()) { #expect(left != right) }
        #expect(Set(all) == Set(options))

        // A chosen value stays, and the automatic one after it steers round it.
        let mixed = RobotAutomatic.spread([nil, "a", nil], over: options)
        #expect(mixed[1] == "a")
        #expect(mixed[0] != "a" && mixed[2] != "a")

        // Two robots set to Automatic never share a personality.
        let personalities = RobotAutomatic.spread([RobotPersonality?](repeating: nil, count: 2),
                                                  over: RobotAutomatic.personalities)
        #expect(personalities[0] != personalities[1])
    }

    @Test("Brand colours come from the provider, written or profiled; black-and-white marks have none")
    func brandColours() {
        #expect(Provider.claudeCode.brandColour == 0xD97757)
        #expect(Provider.deepSeek.brandColour == 0x4D6BFE)
        #expect(Provider.xiaomiMiMo.brandColour == 0xFF6900)
        #expect(Provider.perplexity.brandColour == 0x20808D)
        #expect(Provider.alibabaCodingPlan.brandColour == 0xFF6A00)
        #expect(Provider.alibabaTokenPlan.brandColour == 0xFF6A00)
        #expect(Provider.huggingFace.brandColour == 0xFFD21E)
        #expect(Provider.zoomMate.brandColour == 0x0B5CFF)
        for provider in [Provider.codex, .cursor, .openCodeGo, .grok, .newAPI, .pulseExtension] {
            #expect(provider.brandColour == nil)
        }
    }

    private func hueGap(_ a: RobotInk, _ b: RobotInk) -> Double {
        let d = abs(a.hue - b.hue)
        return min(d, 1 - d)
    }

    @Test("A brand colour is used as it is; robots without one get distinct wheel colours away from their neighbours")
    func automaticInks() {
        let providers: [Provider] = [.claudeCode, .codex, .cursor, .openCodeGo, .grok, .deepSeek]
        let inks = RobotAutomatic.inks(for: providers, custom: Array(repeating: nil, count: providers.count))
        #expect(inks[0].ink == RobotInk(rgb: 0xD97757))
        #expect(inks[5].ink == RobotInk(rgb: 0x4D6BFE))
        #expect(inks.allSatisfy { !$0.chosen })
        // No two neighbours alike, and no wheel colour used twice.
        for (left, right) in zip(inks, inks.dropFirst()) {
            #expect(hueGap(left.ink, right.ink) > 0.05)
        }
        let wheel = inks[1...4].map(\.ink)
        for (i, a) in wheel.enumerated() {
            for b in wheel[(i + 1)...] { #expect(a != b) }
        }
        // Codex sits next to Claude Code's orange: well away from it.
        #expect(hueGap(inks[1].ink, inks[0].ink) >= 0.2)
    }

    @Test("Pulse's wheel keeps away from the usage colours, and a far robot avoids every colour on the panel")
    func wheelAvoidsUsage() {
        #expect(RobotAutomatic.wheel.count >= 6)
        for ink in RobotAutomatic.wheel {
            for (usage, clearance) in zip(RobotAutomatic.usageHues, RobotAutomatic.usageClearances) {
                #expect(RobotAutomatic.hueDistance(ink.hue, usage) >= clearance - 0.001)
            }
        }
        // The rail the maintainer runs: OpenCode Go's colour is not taken
        // near Claude Code's orange two rings away.
        let inks = RobotAutomatic.inks(for: [.claudeCode, .codex, .kimiCode, .openCodeGo],
                                       custom: [nil, nil, nil, nil])
        #expect(hueGap(inks[3].ink, inks[0].ink) >= 0.12)
        #expect(hueGap(inks[3].ink, inks[2].ink) >= 0.08)
    }

    @Test("A chosen colour comes first, is kept exactly, and its neighbours steer round it")
    func customInkFirst() {
        let red = RobotInk(rgb: 0xFF0000)
        let inks = RobotAutomatic.inks(for: [.claudeCode, .codex], custom: [red, nil])
        #expect(inks[0].ink == red)
        #expect(inks[0].chosen)
        #expect(!inks[1].chosen)
        #expect(hueGap(inks[1].ink, red) >= 0.2)
    }

    @Test("An automatic colour too dark for the panel is lifted to 3:1, a legible one left alone")
    func legibleInk() {
        let dark = RobotInk(rgb: 0x101040)
        let lifted = dark.legible(onDark: true)
        #expect((lifted.luminance + 0.05) / 0.05 >= 2.99)
        #expect(lifted != dark)
        let fine = RobotInk(rgb: 0xD97757)
        #expect(fine.legible(onDark: true) == fine)
        // Hugging Face's yellow is pale on the light panel and is darkened there.
        let yellow = RobotInk(rgb: 0xFFD21E)
        #expect(yellow.legible(onDark: false).luminance < yellow.luminance)
    }

    @Test("Each personality's pastime claims nothing")
    func pastimes() {
        for personality in RobotPersonality.allCases {
            #expect(![.cheer, .nod].contains(personality.pastime))
        }
        #expect(Set(RobotPersonality.allCases.map(\.pastime)).count == RobotPersonality.allCases.count)
    }

    @Test("A pastime plays only in idle time, after its gap")
    func pastimeOnlyWhenIdle() {
        for personality in RobotPersonality.allCases {
            let late = personality.pastimeGap.upperBound + 1

            let idle = motion()
            _ = idle.frame(at: 0, mood: .idle, personality: personality)
            _ = idle.frame(at: personality.pastimeGap.lowerBound - 1, mood: .idle, personality: personality)
            #expect(idle.gesture == nil)
            _ = idle.frame(at: late, mood: .idle, personality: personality)
            #expect(idle.gesture == personality.pastime)

            for mood in [RobotMood.working, .refreshing, .spent, .asleep] {
                let busy = motion()
                _ = busy.frame(at: 0, mood: mood, personality: personality)
                _ = busy.frame(at: late, mood: mood, personality: personality)
                #expect(busy.gesture == nil)
            }

            let still = motion()
            _ = still.frame(at: 0, mood: .idle, personality: personality, reduceMotion: true)
            _ = still.frame(at: late, mood: .idle, personality: personality, reduceMotion: true)
            #expect(still.gesture == nil)
        }
    }

    @Test("Inspect narrows the lids to the original's aperture")
    func inspectNarrows() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        motion.play(.inspect, at: 1)
        let frame = run(motion, mood: .idle, from: 1, for: 0.28 + 0.6)
        #expect(abs(Double(frame.left.topLid) + 8) < 0.01)
        #expect(abs(Double(frame.left.bottomLid) - 8) < 0.01)
    }

    @Test("Surprise swells the head and returns it")
    func surpriseSwells() {
        let motion = motion()
        _ = run(motion, mood: .idle, from: 0, for: 1)
        motion.play(.surprise, at: 1)
        let wide = run(motion, mood: .idle, from: 1, for: 0.5 + 0.41)
        #expect(wide.headScale > 1.03)
        let after = run(motion, mood: .idle, from: 1.91, for: 1)
        #expect(after.headScale == 1)
        #expect(motion.gesture == nil)
    }

    @Test("The shapes are the original's roundness 0, 50 and 100, in the same box")
    func shapes() {
        func box(_ shape: RobotShape) -> CGRect {
            let points = RobotFace.headOutline(shape)
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        for shape in RobotShape.allCases {
            #expect(RobotFace.headOutline(shape).count == 160)
            #expect(abs(box(shape).width - box(.standard).width) < 0.5)
            #expect(abs(box(shape).height - box(.standard).height) < 0.5)
        }
        // A point on the diagonal: further out when squarer, further in when rounder.
        func corner(_ shape: RobotShape) -> CGFloat { RobotFace.headOutline(shape)[20].x }
        #expect(corner(.square) > corner(.standard))
        #expect(corner(.round) < corner(.standard))
    }

    @Test("The head outline is the original's: closed, symmetric, flattened")
    func headOutline() {
        let points = RobotFace.headOutline()
        #expect(points.count == 160)
        let xs = points.map(\.x), ys = points.map(\.y)
        // 94% of a 200-unit head, inset 7.2: 26...214 across.
        #expect(abs(xs.min()! - 26) < 0.01)
        #expect(abs(xs.max()! - 214) < 0.01)
        // Nine tenths of that tall.
        #expect(abs((ys.max()! - ys.min()!) - 188 * 0.9) < 0.01)
        #expect(RobotFace.drawnBounds.insetBy(dx: -0.01, dy: -0.01).contains(CGRect(x: xs.min()!, y: ys.min()!,
                                                       width: xs.max()! - xs.min()!,
                                                       height: ys.max()! - ys.min()! + 5.5)))
    }
}
