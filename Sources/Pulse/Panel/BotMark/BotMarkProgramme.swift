// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What a mark should be playing, and how.
///
/// Authored scenes come from `BotMarkChoreography`: a signature pose, a
/// contrasting gesture/effect, and a return to the character. Each beat has
/// its own hold time, and every beat gets played rather than randomly skipped.
///
/// The engine owns which one is playing, because it owns the clock — and
/// because the per-state table (`expressionPool`, cadences, the morph it
/// carries) has to be rebuilt every time the state changes, which the view
/// cannot do without knowing when that happens.
struct BotMarkProgramme {
    enum Order { case random, sequence }

    /// The states to take in turn. One entry is held; more are rotated.
    var states: [String]
    var order: Order = .random
    /// Milliseconds a state is held before another is taken.
    var hold: ClosedRange<Double> = 2500...4500
    /// Brief accents need not have the same screen time as the resting pose.
    var stateHolds: [String: ClosedRange<Double>] = [:]
    /// A one-shot that interrupts the playlist, for something that just
    /// happened rather than something that is going on.
    var event: BotMarkEvent?
    /// The same witnessed finish, expressed by this character. Reset keeps
    /// the complete celebration rather than being cut into a short pose.
    var completionState = "excited"
    /// The mood behind the playlist, so the engine can tell a change of state
    /// from a change of fact.
    var mood: BotMarkMood = .idle

    var shape: String = BotMarkBody.default.shape
    var tempo = 1.0
    var motionScale = 1.0
    var gazeScale = 1.0
    var eyeScale = 1.0
    var gazeBias = 0.0
    /// Whether the mark is drawn mirrored, so a rail on the right-hand edge
    /// faces into the screen. See `BotMarkGaze`.
    var flipX = false
    var rotationScale = 1.0
    var squashScale = 1.0
    /// Master switch; the configuration additionally requires a busy mood or
    /// an event currently playing. Idle spins must not wear work's ribbons.
    var particlesEnabled = true
    /// Where the pointer is, as a fraction of the mark's own radius from its
    /// centre, or nil when it is nowhere near. The eyes follow it.
    var pointer: CGPoint?
    var viewWidth = 96.0
    var color = Color.white
    var eyeColor = Color(white: 0.06)

    /// One production mapping for the view and frame-level regression tests.
    /// The supplied date makes day/night behaviour reproducible without
    /// changing the clock or the reader's settings.
    static func forMood(
        _ mood: BotMarkMood,
        persona: BotMarkPersona,
        isQuiet: Bool = false,
        isPointedAt: Bool = false,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> BotMarkProgramme {
        let overtime = BotMarkHours.isOvertime(at: date, calendar: calendar)
        let night = BotMarkHours.isNight(at: date, calendar: calendar)
        let routine: BotMarkRoutine = switch mood {
        case .working: persona.workingRoutine(overtime: overtime)
        case .idle: isPointedAt ? persona.attentionRoutine : persona.idleRoutine(quiet: isQuiet, night: night)
        case .fetching, .spent, .unavailable: persona.routine(for: mood)
        }
        var programme = BotMarkProgramme(states: routine.states)
        // Finish the whole authored scene. Randomly choosing any different
        // state could omit a character's signature indefinitely.
        programme.order = .sequence
        programme.stateHolds = routine.holds
        programme.completionState = persona.completionState
        programme.mood = mood
        programme.tempo = persona.tempo * mood.tempoEmphasis
        programme.motionScale = persona.motionScale
        programme.gazeScale = persona.gazeScale
        programme.eyeScale = persona.eyeScale
        programme.rotationScale = mood.rotationEmphasis
        programme.squashScale = mood.squashEmphasis
        return programme
    }

    func state(for event: BotMarkEvent) -> String {
        event == .workFinished ? completionState : event.state
    }

    func holdDuration(for state: String) -> ClosedRange<Double> {
        stateHolds[state] ?? hold
    }

    /// The config for one state of the playlist: the upstream's own table for
    /// that state, with this programme's scales on top.
    func configuration(for state: String, isEvent: Bool = false) -> BotMarkConfig {
        var config = BotMarkConfig.forState(BotMarkLibrary.shared.state(state), shape: shape)
        config.tempo = tempo
        config.motionScale = motionScale
        config.gazeScale = gazeScale
        config.eyeScale = eyeScale
        config.gazeBias = gazeBias
        config.flipX = flipX
        config.rotationScale = rotationScale
        config.squashScale = squashScale
        config.particlesEnabled = particlesEnabled && (mood == .working || mood == .fetching || isEvent)
        config.pointer = pointer != nil
        config.viewWidth = viewWidth
        config.color = color
        config.eyeColor = eyeColor
        return config
    }
}

/// Something that just happened, played once and then dropped.
///
/// **Both of these are facts Pulse witnessed**, not a view noticing its own
/// history: a window that turned over by the same unambiguous test the
/// notifications use, and a CLI whose turn ended, from the activity monitor
/// that already drives the running mark. A mark that celebrated because a
/// SwiftUI body happened to be rebuilt would be the rail inventing news.
enum BotMarkEvent: Equatable, Sendable {
    /// A limit reset: the big one, nine turns and a shower of ribbons.
    case limitReset
    /// A turn just finished. Shorter and quieter — this happens many times an
    /// hour, and a full celebration every time would be exhausting.
    case workFinished

    var state: String {
        switch self {
        case .limitReset: "celebrate"
        case .workFinished: "excited"
        }
    }

    /// How long the one-shot holds the mark before the playlist comes back.
    ///
    /// The celebrate cycle is 6.2s upstream and looks unfinished if it is cut
    /// mid-spin, so a reset gets the whole of it. A finish is a beat.
    var duration: Double {
        switch self {
        case .limitReset: 6400
        case .workFinished: 2600
        }
    }
}
