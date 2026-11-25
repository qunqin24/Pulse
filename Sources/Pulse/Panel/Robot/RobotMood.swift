// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// What the figure in a ring is doing, decided only from what Pulse has seen.
///
/// The figures are Open Bot Avatar's (MIT; THIRD_PARTY_NOTICES.md), and each
/// case is one of that project's own states rather than an invented face:
/// Pulse supplies the facts, the avatar already has a way of showing each.
enum RobotMood: Equatable {
    /// Nothing happening. The avatar's `idle`: breathes, sways, blinks and
    /// looks around.
    case idle
    /// The provider's CLI is working (`UsageStore.isRunning`). The avatar's
    /// `working`: bent over the work, ribbons sweeping round now and then.
    case working
    /// A reading is being fetched from the ring (`UsageStore.isRefreshing`).
    /// The avatar's `thinking`, three hopping dots, so it is not mistaken for
    /// the CLI.
    case refreshing
    /// The provider says this limit is spent. The avatar's `blocked`: an
    /// exclamation mark in place of the body, until the provider says
    /// otherwise.
    case spent
    /// No reading. The avatar's `waiting` — slit eyes and a sigh, not
    /// `blocked`, because nothing known is not the same as something wrong.
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

    /// The avatar's state for this mood.
    var state: BotAvatarEngine.State {
        switch self {
        case .idle: .idle
        case .working: .working
        case .refreshing: .thinking
        case .spent: .blocked
        case .asleep: .waiting
        }
    }
}

/// Something that just happened, shown for a moment over the mood.
enum RobotGesture: Equatable {
    /// A limit turned over (`UsageStore.justReset`). The avatar's `done`: a
    /// few turns inside its ribbons.
    case cheer
    /// The CLI finished a turn (`UsageStore.justFinishedWorking`). The
    /// avatar's happy mood: its eyes turn to arcs.
    case nod

    /// A reset outranks a finished turn: it is rarer and it is the better news.
    static func triggered(justReset: Bool, justFinished: Bool) -> RobotGesture? {
        if justReset { return .cheer }
        if justFinished { return .nod }
        return nil
    }

    /// How long it shows before the mood is back. A cheer is one round of
    /// the original's celebration; a nod is a glance's worth of smile.
    var duration: TimeInterval {
        switch self {
        case .cheer: 4.5
        case .nod: 3
        }
    }
}

/// What a ring needs to draw a figure instead of the provider's mark. Nil on
/// a ring that draws the mark.
///
/// The two one-off facts are carried as the store answers them; the view
/// plays a gesture when one *becomes* true, so a span that stays true for
/// twenty seconds plays once.
struct RobotCue: Equatable {
    var justReset: Bool = false
    var justFinished: Bool = false
    /// The body's colour, or nil for the panel's own foreground.
    var ink: RobotInk?
    /// Whether `ink` was picked by hand, in which case it is drawn exactly as
    /// picked; an automatic one is adjusted to stand out from the panel.
    var inkIsChosen = false
    /// Which of Open Bot Avatar's figures, by its id.
    var figure: String = RobotFigures.automatic[0]
    /// Flat colour, or Open Bot Avatar's fur.
    var material: RobotMaterial = .flat
    /// Seconds added to the figure's clock, from the account, so figures on
    /// one rail do not breathe and blink in step.
    var phase: TimeInterval = 0

    /// The same account always gets the same phase, up to a minute.
    static func phase(for account: AccountKey) -> TimeInterval {
        let sum = account.id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return TimeInterval(sum % 600) / 10
    }

    var gesture: RobotGesture? {
        RobotGesture.triggered(justReset: justReset, justFinished: justFinished)
    }
}

/// What a figure is drawn in: flat colour, as the original draws by default,
/// or its fluffy material — a coat of fur with the eyes set in as beads, and
/// `thinking`'s dots and `blocked`'s mark as pompoms. Stored by its raw value.
enum RobotMaterial: String, CaseIterable, Sendable {
    case flat
    case fluffy

    var title: String {
        switch self {
        case .flat: String.localized("Flat")
        case .fluffy: String.localized("Fluffy")
        }
    }
}

/// The figures Pulse offers, and the order Automatic hands them out in.
enum RobotFigures {
    /// Automatic's order: figures whose outline and eyes read at the 20pt of a
    /// ring come first, so a short rail gets the clearest ones.
    static let automatic = [
        "mug", "ghost", "cat", "lightbulb", "chat", "cloud", "egg", "controller",
        "bunny", "star", "rocket", "book", "camera", "shield", "sprout", "brain",
        "bull", "palette", "magnifier", "witch-hat", "paint-brush", "barbell", "watering-can",
    ]

    /// The figure's name in the interface language. The English names are
    /// the original's own.
    static func title(_ id: String) -> String {
        switch id {
        case "controller": .localized("Controller")
        case "barbell": .localized("Barbell")
        case "mug": .localized("Mug")
        case "lightbulb": .localized("Lightbulb")
        case "chat": .localized("Speech bubble")
        case "sprout": .localized("Sprout")
        case "watering-can": .localized("Watering can")
        case "book": .localized("Book")
        case "brain": .localized("Brain")
        case "bull": .localized("Bull")
        case "bunny": .localized("Bunny")
        case "camera": .localized("Camera")
        case "cat": .localized("Cat")
        case "cloud": .localized("Cloud")
        case "egg": .localized("Egg")
        case "ghost": .localized("Ghost")
        case "magnifier": .localized("Magnifying glass")
        case "paint-brush": .localized("Paintbrush")
        case "palette": .localized("Palette")
        case "rocket": .localized("Rocket")
        case "shield": .localized("Shield")
        case "star": .localized("Star")
        case "witch-hat": .localized("Witch's hat")
        default: id
        }
    }
}

/// What a robot set to Automatic gets: its product's colour or a colour from
/// Pulse's wheel (`inks`, in RobotColour.swift), and a figure picked so that
/// neighbouring robots on the rail differ.
enum RobotAutomatic {
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
