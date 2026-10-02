// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A mark's personality: which of the upstream's states it plays for each
/// mood, and how quickly it moves.
///
/// Eight authored choreographies give each character its own default pose,
/// idle scene, task effects, attention response and finish acknowledgement.
/// Motion scales are an accent on those scenes, not their only difference.
///
/// **A persona does not touch the body.** Which shape a mark wears is the
/// reader's choice — `BotMarkBody`, round by default — and tying it to
/// temperament would mean picking "sleepy" to get a bean.
///
/// **A persona may change how a mood is said, never what it says.** Task
/// effects need work or a fetch, celebration needs a witnessed reset, and a
/// spent/unavailable account does not play a carefree idle scene. Only sleepy
/// can use drowsy. These meanings are pinned across complete routines.
enum BotMarkPersona: String, CaseIterable, Identifiable, Sendable {
    case calm
    case eager
    case steady
    case curious
    case sleepy
    case playful
    case stoic
    case proud

    var id: String { rawValue }

    /// The first pose, also used by Reduce Motion. The full routine is kept
    /// beside its timings, so this cannot drift from what the view plays.
    func state(for mood: BotMarkMood) -> String {
        routine(for: mood).states.first ?? "idle"
    }

    private var choreography: BotMarkChoreography {
        switch self {
        case .calm: .calm
        case .eager: .eager
        case .steady: .steady
        case .curious: .curious
        case .sleepy: .sleepy
        case .playful: .playful
        case .stoic: .stoic
        case .proud: .proud
        }
    }

    func routine(for mood: BotMarkMood) -> BotMarkRoutine {
        switch mood {
        case .idle: choreography.idle
        case .working: choreography.working
        case .fetching: choreography.fetching
        case .spent: choreography.spent
        case .unavailable: choreography.unavailable
        }
    }

    func workingRoutine(overtime: Bool) -> BotMarkRoutine {
        overtime ? choreography.overtime : choreography.working
    }

    func idleRoutine(quiet: Bool, night: Bool) -> BotMarkRoutine {
        self == .sleepy && quiet && night ? BotMarkChoreography.sleepyNight : choreography.idle
    }

    var attentionRoutine: BotMarkRoutine { choreography.attention }
    var completionState: String { choreography.completion }

    func workingStates(overtime: Bool) -> [String] { workingRoutine(overtime: overtime).states }
    func idleStates(quiet: Bool, night: Bool) -> [String] { idleRoutine(quiet: quiet, night: night).states }

    /// How long it waits between things.
    ///
    /// **Larger is slower.** Upstream multiplies every gap by this — the wait
    /// until the next blink, the next glance, the next change of expression —
    /// so 1.5 is a mark that blinks half as often, not one that moves fast.
    var tempo: Double {
        switch self {
        case .playful, .eager: 0.85   // shorter waits between blinks and glances
        case .sleepy: 1.5
        case .stoic: 1.25
        case .calm, .steady, .curious, .proud: 1
        }
    }

    var motionScale: Double {
        switch self {
        case .playful: 1.15
        case .eager: 1.1
        case .sleepy: 0.8
        case .stoic: 0.6
        case .calm, .steady, .curious, .proud: 1
        }
    }

    var gazeScale: Double {
        switch self {
        case .curious, .eager: 1.2
        case .stoic: 0.5
        case .sleepy: 0.7
        case .calm, .steady, .playful, .proud: 1
        }
    }

    var eyeScale: Double {
        switch self {
        case .eager, .curious: 1.06
        case .stoic: 0.94
        case .calm, .steady, .sleepy, .playful, .proud: 1
        }
    }

    /// The name in the settings picker, in the shape the other settings
    /// enums use: a localized `title`, rendered with `Text(persona.title)`.
    var title: String {
        switch self {
        case .calm: .localized("Calm")
        case .eager: .localized("Eager")
        case .steady: .localized("Steady")
        case .curious: .localized("Curious")
        case .sleepy: .localized("Sleepy")
        case .playful: .localized("Playful")
        case .stoic: .localized("Stoic")
        case .proud: .localized("Proud")
        }
    }

    /// The persona for the nth ring on the rail, when nobody has chosen one.
    ///
    /// Walked in rail order rather than fixed per provider, for the same
    /// reason the colours are dealt that way: what matters is that the ring
    /// beside this one is a different character, and the rail only shows
    /// enabled accounts. Eight personas cover eight rings before anything
    /// repeats, and a repeat is four rings away.
    static func automatic(at index: Int) -> BotMarkPersona {
        let all = BotMarkPersona.allCases
        return all[((index % all.count) + all.count) % all.count]
    }
}
