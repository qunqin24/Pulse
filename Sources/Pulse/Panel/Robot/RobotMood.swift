// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What the robot in a ring is doing, decided only from what Pulse has seen.
///
/// The robot is CX ArtLab's Agent Robot Avatar (MIT; THIRD_PARTY_NOTICES.md).
/// Each case borrows one of that project's own actions rather than inventing a
/// face: Pulse supplies the facts, the avatar already has an expression for
/// each of them.
enum RobotMood: Equatable {
    /// Nothing happening. The avatar's `idle`: blinks and glances around.
    case idle
    /// The provider's CLI is working (`UsageStore.isRunning`). The avatar's
    /// `waiting-spin`, its default "waiting for a reply".
    case working
    /// A reading is being fetched from the ring (`UsageStore.isRefreshing`).
    /// The avatar's `waiting-wave`, so it is not mistaken for the CLI.
    case refreshing
    /// The provider says this limit is spent. The avatar's `failure`, held:
    /// head and eyes lowered, until the provider says otherwise.
    case spent
    /// No reading. The avatar's `sleep` — not `failure` or `refuse`, because
    /// nothing known is not the same as something broken.
    case asleep

    /// The one mood for a set of facts. The order is the rule:
    ///
    /// - **Refreshing first.** It is the answer to a click on this ring, and
    ///   a click that seems to do nothing is clicked again.
    /// - **Working before anything about the reading.** The CLI is running
    ///   whatever the last reading said; a spent limit is already on the
    ///   ring in its own colour, and the white activity arc this replaces
    ///   has nowhere else to go.
    /// - **No reading before spent.** Without a reading, "spent" is a memory.
    /// - `activity` false (`AppSettings.animatesRingActivity` off) withholds
    ///   working and refreshing, as it withholds the arcs they stand for.
    static func resolve(hasReading: Bool, isSpent: Bool, isWorking: Bool,
                        isRefreshing: Bool, activity: Bool = true) -> RobotMood {
        if activity && isRefreshing { return .refreshing }
        if activity && isWorking { return .working }
        if !hasReading { return .asleep }
        if isSpent { return .spent }
        return .idle
    }
}

/// An expression played once over the current mood.
///
/// The first two report something Pulse saw. The rest are a personality's
/// pastimes while idle, and are chosen from the original's actions that
/// **claim nothing** — a cheer or a nod in idle time would read as a reset or
/// a finished turn that never happened.
enum RobotGesture: Equatable {
    /// A limit turned over (`UsageStore.justReset`). The avatar's `success`.
    case cheer
    /// The CLI finished a turn (`UsageStore.justFinishedWorking`). The
    /// avatar's `affirm`: a nod.
    case nod
    /// The avatar's `bored`: a slow look to one side and the other.
    case bored
    /// The avatar's `inspect`: narrowed eyes scanning up and down.
    case inspect
    /// The avatar's `surprise`: eyes shrink, then open wide.
    case surprise

    /// A reset outranks a finished turn: it is rarer and it is the better news.
    static func triggered(justReset: Bool, justFinished: Bool) -> RobotGesture? {
        if justReset { return .cheer }
        if justFinished { return .nod }
        return nil
    }
}

/// What a ring needs to draw the robot instead of the provider's mark. Nil on
/// a ring that draws the mark.
///
/// The two one-off facts are carried as the store answers them; the view
/// plays a gesture when one *becomes* true, so a span that stays true for
/// twenty seconds plays once.
struct RobotCue: Equatable {
    var justReset: Bool = false
    var justFinished: Bool = false
    /// The head's colour, or nil for the panel's own foreground.
    var ink: RobotInk?
    /// Whether `ink` was picked by hand, in which case it is drawn exactly as
    /// picked; an automatic one is adjusted to stand out from the panel.
    var inkIsChosen = false
    var personality: RobotPersonality = .curious
    var shape: RobotShape = .standard

    var gesture: RobotGesture? {
        RobotGesture.triggered(justReset: justReset, justFinished: justFinished)
    }
}

/// How a robot passes idle time: which of the original's idle actions it
/// reaches for, and how quickly it glances and blinks.
///
/// Only idle time. Every mood that reports a fact — working, refreshing,
/// spent, asleep — and both fact gestures look the same whatever the
/// personality, so a personality can never be mistaken for a state.
enum RobotPersonality: String, CaseIterable, Identifiable {
    /// Slow glances and blinks; now and then the original's `bored`.
    case calm
    /// The original's own idle timing; now and then `inspect`.
    case curious
    /// Quick, frequent glances; now and then `surprise`.
    case lively

    var id: String { rawValue }

    /// Multiplies the time between glances.
    var glanceGap: Double {
        switch self {
        case .calm: 1.6
        case .curious: 1
        case .lively: 0.6
        }
    }

    /// How quickly the eyes reach where they are glancing, per sixtieth of a
    /// second. The original's idle glance is 0.16.
    var glanceSpeed: Double {
        switch self {
        case .calm: 0.1
        case .curious: 0.16
        case .lively: 0.26
        }
    }

    /// Multiplies the time between blinks.
    var blinkGap: Double {
        switch self {
        case .calm: 1.3
        case .curious: 1
        case .lively: 0.8
        }
    }

    var pastime: RobotGesture {
        switch self {
        case .calm: .bored
        case .curious: .inspect
        case .lively: .surprise
        }
    }

    /// Seconds of idle time between pastimes, at least and at most.
    var pastimeGap: ClosedRange<Double> {
        switch self {
        case .calm: 30...50
        case .curious: 25...40
        case .lively: 18...30
        }
    }

    var title: String {
        switch self {
        case .calm: .localized("Calm")
        case .curious: .localized("Curious")
        case .lively: .localized("Lively")
        }
    }
}

/// The head's outline, from the original's `setHeadRoundness`: the shape
/// eased towards a squarer or a rounder superellipse. The only appearance
/// variant the original has besides its colour and skins.
enum RobotShape: String, CaseIterable, Identifiable {
    /// The original's default, roundness 50. Called "Original" on screen:
    /// the head as CX ArtLab drew it.
    case standard
    /// Roundness 0.
    case square
    /// Roundness 100.
    case round

    var id: String { rawValue }

    var roundness: Double {
        switch self {
        case .standard: 50
        case .square: 0
        case .round: 100
        }
    }

    var title: String {
        switch self {
        case .standard: .localized("Original")
        case .square: .localized("Squarer")
        case .round: .localized("Rounder")
        }
    }
}

/// What a robot set to Automatic gets: its product's colour or a colour from
/// Pulse's wheel (`inks`, in RobotColour.swift), and a personality picked so
/// that neighbouring robots on the rail differ.
enum RobotAutomatic {
    static let personalities: [RobotPersonality] = [.curious, .calm, .lively]

    /// One value per robot, in rail order: the chosen one where there is one,
    /// otherwise the next option in turn that differs from both neighbours —
    /// the robot before as resolved, the robot after where it was chosen.
    ///
    /// Counting through the options by position rather than always taking
    /// the first that differs keeps a long rail varied, instead of
    /// alternating between two.
    static func spread<T: Equatable>(_ chosen: [T?], over options: [T]) -> [T] {
        guard !options.isEmpty else { return [] }
        var result: [T] = []
        for (index, pick) in chosen.enumerated() {
            if let pick {
                result.append(pick)
                continue
            }
            let previous = result.last
            let next = index + 1 < chosen.count ? chosen[index + 1] : nil
            let start = index % options.count
            let candidates = (0..<options.count).map { options[(start + $0) % options.count] }
            result.append(candidates.first { $0 != previous && $0 != next }
                ?? candidates.first { $0 != previous }
                ?? candidates[0])
        }
        return result
    }
}
