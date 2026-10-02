// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What a ring's mark is doing, and which of the upstream's 39 states says it.
///
/// **This is the only place a Pulse fact becomes a bot state.** The upstream
/// catalogue is a character sheet — 39 moods, most of which Pulse has nothing
/// to say about — and the temptation is to reach into it from the view for
/// whichever one looks nice. Five moods, each standing for something the rail
/// already knew, is the whole vocabulary: if the mark is doing something, a
/// reading somewhere says why.
enum BotMarkMood: String, CaseIterable, Identifiable, Sendable {
    /// Nothing is happening: the provider answered and the limit is fine.
    case idle
    /// This provider's CLI is working right now — the fact the white
    /// travelling mark used to carry on its own.
    case working
    /// Pulse is fetching a fresh reading.
    case fetching
    /// The provider says this limit is spent.
    case spent
    /// No reading at all: signed out, disabled, or nothing back yet.
    case unavailable

    var id: String { rawValue }

    /// The upstream state this plays.
    ///
    /// `working` rather than `thinking`: thinking is a morph that replaces the
    /// body with three dots, which at 16pt throws away both the face and the
    /// brand colour — the two things that say *which* provider is busy.
    var upstreamState: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .fetching: "searching"
        case .spent: "sad"
        case .unavailable: "confused"
        }
    }

    /// How much to exaggerate the rotation, so the mood can be seen at ring
    /// size at all.
    ///
    /// **Only the moods that are an event.** A ring that is idle should be
    /// quiet — that is the reading — and a mark rocking away at nothing would
    /// be a rail that always looks busy. Working is the one a reader asks the
    /// rail about ("is it doing something?"), so it is the one worth
    /// exaggerating most; fetching is a second or two long and only has to be
    /// noticed while it lasts.
    var rotationEmphasis: Double {
        switch self {
        case .working: 2.4
        case .fetching: 1.6
        case .idle, .spent, .unavailable: 1
        }
    }

    /// How hard the body breathes.
    ///
    /// **A pulse, not a pump.** Ten was tried and read as the mark resizing
    /// itself — 20% of the body's height at 25pt is five points of it moving,
    /// which is a different thing from a character breathing. Three is about
    /// 3% peak-to-peak against idle's 1.3%: visible when you look at it,
    /// invisible when you are not. What actually says "working" at ring size
    /// is the ribbons and the doubled tempo.
    var squashEmphasis: Double {
        switch self {
        case .working: 3
        case .fetching: 2
        case .idle, .spent, .unavailable: 1
        }
    }

    /// A multiplier on every wait the mark keeps — blinks, glances, changes of
    /// expression, and the gestures that make it spin. **Smaller is busier**,
    /// because upstream multiplies its gaps by this.
    ///
    /// Half for working: a mark that is working blinks and looks about twice
    /// as often, and takes its occasional spin every three or four seconds
    /// instead of every six to nine. Nothing about the *reading* changes; it
    /// is the difference between a character at rest and one at work.
    var tempoEmphasis: Double {
        switch self {
        case .working: 0.5
        case .fetching: 0.7
        case .idle, .spent, .unavailable: 1
        }
    }

    /// Reads the mood off the same facts the ring is already drawn from.
    ///
    /// **Busy outranks spent.** A spent limit is a state of the world that
    /// will still be true in a minute; a CLI turning is happening now, and it
    /// is the one thing on this rail that answers "is it doing something".
    /// Nothing here looks at the warning threshold: how close a limit is, is
    /// what the ring's colour means, and saying it twice in two languages on
    /// one 36pt mark is how a rail stops being readable at a glance.
    static func resolve(isBusy: Bool, isRefreshing: Bool,
                        isSpent: Bool, hasReading: Bool) -> BotMarkMood {
        if isBusy { return .working }
        if isRefreshing { return .fetching }
        if isSpent { return .spent }
        if !hasReading { return .unavailable }
        return .idle
    }
}
