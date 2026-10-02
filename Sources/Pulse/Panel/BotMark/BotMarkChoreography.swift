// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// A short authored scene, in milliseconds. States keep the upstream artwork;
/// the sequence and its pacing give the character a recognisable routine.
struct BotMarkBeat: Equatable, Sendable {
    let state: String
    let hold: ClosedRange<Double>

    init(_ state: String, _ hold: ClosedRange<Double>) {
        self.state = state
        self.hold = hold
    }
}

struct BotMarkRoutine: Sendable {
    let beats: [BotMarkBeat]
    let states: [String]
    let holds: [String: ClosedRange<Double>]

    init(_ beats: BotMarkBeat...) { self.init(beats: beats) }

    private init(beats: [BotMarkBeat]) {
        self.beats = beats
        states = beats.map(\.state)
        holds = Dictionary(beats.map { ($0.state, $0.hold) }, uniquingKeysWith: { first, _ in first })
    }

    func appending(_ beat: BotMarkBeat) -> BotMarkRoutine {
        BotMarkRoutine(beats: beats + [beat])
    }
}

/// Immutable tables, not rebuilt by the view on every animation frame. Idle
/// uses playful/emotional gestures. No working state appears in any persona's
/// idle/attention routine, so one resting character cannot impersonate another
/// one's work. Alerts belong to exhaustion and celebration to a witnessed reset.
struct BotMarkChoreography: Sendable {
    let idle: BotMarkRoutine
    let working: BotMarkRoutine
    let fetching: BotMarkRoutine
    let spent: BotMarkRoutine
    let unavailable: BotMarkRoutine
    let attention: BotMarkRoutine
    let completion: String
    let overtime: BotMarkRoutine

    init(idle: BotMarkRoutine, working: BotMarkRoutine, fetching: BotMarkRoutine,
         spent: BotMarkRoutine, unavailable: BotMarkRoutine, attention: BotMarkRoutine,
         completion: String) {
        self.idle = idle
        self.working = working
        self.fetching = fetching
        self.spent = spent
        self.unavailable = unavailable
        self.attention = attention
        self.completion = completion
        overtime = working.appending(.init("angry", 1_800...2_500))
    }

    static let calm = BotMarkChoreography(
        idle: .init(.init("idle", 4_500...6_500), .init("listening", 2_200...3_200), .init("shy", 1_600...2_400)),
        working: .init(.init("working", 4_000...5_500), .init("thinking", 2_300...3_000),
                       .init("searching", 3_000...4_000), .init("writing", 2_700...3_500)),
        fetching: .init(.init("receiving", 1_700...2_400), .init("listening", 1_500...2_200)),
        spent: .init(.init("sad", 4_000...6_000), .init("shy", 2_000...3_000)),
        unavailable: .init(.init("confused", 3_000...4_500), .init("listening", 2_000...3_000)),
        attention: .init(.init("listening", 3_000...4_000), .init("idle", 2_000...3_000)),
        completion: "happy"
    )

    static let eager = BotMarkChoreography(
        idle: .init(.init("happy", 2_500...3_500), .init("curious", 1_800...2_600), .init("playful", 1_600...2_400)),
        working: .init(.init("excited", 3_200...4_200), .init("spawning", 2_200...3_000),
                       .init("working", 3_500...4_500), .init("radar", 2_000...2_800)),
        fetching: .init(.init("spawning", 2_000...2_600), .init("radar", 1_500...2_000), .init("receiving", 1_700...2_300)),
        spent: .init(.init("scared", 1_800...2_500), .init("angry", 2_000...3_000), .init("sad", 3_000...4_000)),
        unavailable: .init(.init("surprised", 1_200...1_600), .init("confused", 2_500...3_500), .init("listening", 1_800...2_500)),
        attention: .init(.init("happy", 2_000...3_000), .init("curious", 2_000...3_000)),
        completion: "excited"
    )

    static let steady = BotMarkChoreography(
        idle: .init(.init("humming", 4_000...5_500), .init("listening", 2_200...3_000), .init("idle", 2_500...3_500)),
        working: .init(.init("working", 4_500...6_000), .init("writing", 2_800...3_600),
                       .init("searching", 3_500...4_500), .init("orbit", 2_200...3_000)),
        fetching: .init(.init("loading", 2_000...3_000), .init("orbit", 2_000...2_800)),
        spent: .init(.init("sad", 4_000...5_000), .init("alerting", 1_500...2_000)),
        unavailable: .init(.init("confused", 3_500...4_500), .init("suspicious", 2_500...3_500)),
        attention: .init(.init("listening", 3_000...4_000), .init("humming", 2_500...3_500)),
        completion: "humming"
    )

    static let curious = BotMarkChoreography(
        idle: .init(.init("curious", 2_500...3_500), .init("suspicious", 1_800...2_600), .init("surprised", 1_200...1_600)),
        working: .init(.init("searching", 3_500...4_500), .init("radar", 2_500...3_300),
                       .init("working", 3_500...4_500), .init("thinking", 2_200...3_000)),
        fetching: .init(.init("radar", 1_800...2_500), .init("searching", 2_000...2_800), .init("thinking", 1_500...2_200)),
        spent: .init(.init("surprised", 1_200...1_600), .init("sad", 3_000...4_000), .init("suspicious", 2_000...3_000)),
        unavailable: .init(.init("suspicious", 2_000...3_000), .init("confused", 2_500...3_500), .init("surprised", 1_200...1_600)),
        attention: .init(.init("curious", 2_500...3_500), .init("listening", 2_000...3_000)),
        completion: "surprised"
    )

    static let sleepy = BotMarkChoreography(
        idle: .init(.init("shy", 6_000...8_000), .init("idle", 6_000...8_000), .init("happy", 2_000...3_000)),
        working: .init(.init("working", 4_000...5_500), .init("thinking", 2_800...3_600),
                       .init("searching", 3_500...4_500), .init("receiving", 2_500...3_300)),
        fetching: .init(.init("listening", 2_500...3_500), .init("loading", 2_000...3_000)),
        spent: .init(.init("drowsy", 3_000...4_000), .init("sad", 4_000...6_000)),
        unavailable: .init(.init("drowsy", 3_000...4_000), .init("confused", 4_000...5_000)),
        attention: .init(.init("shy", 2_000...3_000), .init("listening", 3_000...4_000)),
        completion: "shy"
    )
    static let sleepyNight = sleepy.idle.appending(.init("drowsy", 2_000...3_000))

    static let playful = BotMarkChoreography(
        idle: .init(.init("playful", 3_000...4_000), .init("bouncing", 1_800...2_400), .init("laughing", 1_600...2_200)),
        working: .init(.init("excited", 3_000...4_000), .init("orbit", 1_800...2_400),
                       .init("searching", 3_000...4_000), .init("writing", 2_500...3_300)),
        fetching: .init(.init("orbit", 1_800...2_500), .init("receiving", 1_700...2_300)),
        spent: .init(.init("scared", 1_800...2_500), .init("surprised", 1_200...1_600), .init("sad", 3_000...4_000)),
        unavailable: .init(.init("surprised", 1_200...1_600), .init("shy", 2_000...3_000), .init("confused", 2_500...3_500)),
        attention: .init(.init("playful", 2_500...3_500), .init("surprised", 1_200...1_600)),
        completion: "laughing"
    )

    static let stoic = BotMarkChoreography(
        idle: .init(.init("suspicious", 4_000...6_000), .init("listening", 2_000...3_000), .init("idle", 4_000...5_000)),
        working: .init(.init("searching", 3_000...4_000), .init("radar", 2_300...3_000),
                       .init("working", 4_500...6_000), .init("loading", 2_500...3_300)),
        fetching: .init(.init("searching", 2_500...3_500), .init("thinking", 2_000...2_800)),
        spent: .init(.init("angry", 2_500...3_500), .init("sad", 4_000...5_000)),
        unavailable: .init(.init("suspicious", 3_000...4_000), .init("confused", 3_000...4_000), .init("listening", 2_000...3_000)),
        attention: .init(.init("suspicious", 2_500...3_500), .init("listening", 2_500...3_500)),
        completion: "proud"
    )

    static let proud = BotMarkChoreography(
        idle: .init(.init("proud", 3_500...5_000), .init("happy", 2_200...3_200), .init("laughing", 1_500...2_100)),
        working: .init(.init("excited", 3_000...4_000), .init("orbit", 2_200...3_000),
                       .init("working", 4_000...5_500), .init("spawning", 2_500...3_300)),
        fetching: .init(.init("thinking", 1_800...2_500), .init("loading", 2_000...2_800), .init("radar", 1_800...2_500)),
        spent: .init(.init("angry", 2_500...3_500), .init("shy", 2_000...3_000), .init("sad", 3_000...4_000)),
        unavailable: .init(.init("confused", 3_000...4_000), .init("shy", 2_500...3_500)),
        attention: .init(.init("proud", 3_000...4_000), .init("happy", 2_000...3_000)),
        completion: "playful"
    )
}
