import Foundation

/// Which route a provider's figures are read by.
///
/// Both providers can be reached two ways, and the two differ in more than
/// plumbing: the endpoint is live but undocumented and needs a stored login,
/// while the other route goes through the provider's own tooling — no
/// credentials for Pulse to hold, but it can only report what that tooling
/// last saw.
///
/// `.automatic` is the default and is what should stay the default: it takes
/// the endpoint when it can and the other route when it can't, which is the
/// behaviour that survives an expired token without anyone noticing. The
/// explicit choices exist for when you want to know which one you're looking
/// at, or to pin one because the other is misbehaving.
enum UsageSource: String, CaseIterable, Identifiable, Sendable {
    /// Endpoint first, the provider's own tooling as a fallback.
    case automatic
    /// Only the provider's usage endpoint.
    case endpoint
    /// Only the route through the provider's own tooling.
    case tooling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: .localized("Automatic")
        case .endpoint: .localized("Usage endpoint")
        case .tooling: .localized("Provider tooling")
        }
    }

    /// What the tooling route actually is, which differs per provider.
    func detail(for provider: Provider) -> String {
        switch (self, provider) {
        case (.automatic, _):
            .localized("Use the endpoint when possible, the other route when not.")
        case (.endpoint, .claudeCode):
            .localized("Reads your account's limits with the login Claude Code saved.")
        case (.endpoint, .codex):
            .localized("Reads your account's limits with the login Codex saved.")
        case (.tooling, .claudeCode):
            .localized("Uses whatever Claude Code last reported to its status line.")
        case (.tooling, .codex):
            .localized("Asks the Codex app server, which signs in on its own.")
        case (_, .openCodeGo), (_, .kimiCode), (_, .zai), (_, .glmCoding):
            // Never shown either — one route, and it needs a key.
            .localized("Uses the key you entered.")
        case (_, .ollamaCloud):
            // Never shown: one route, and it reads a page rather than an API.
            .localized("Reads your quota from Ollama's own settings page.")
        case (_, .antigravity):
            // Never shown — Antigravity has one route, so settings states it
            // rather than offering a choice. See `Provider.hasSourceChoice`.
            .localized("Asks the language server Antigravity runs while it is open.")
        case (_, .cursor):
            // Never shown, for the same reason: one route.
            .localized("Reads your account's limits with the login Cursor saved.")
        }
    }
}

/// How often Pulse asks the providers for fresh figures.
///
/// The default is `.automatic`, and it should stay that way. These are someone
/// else's servers doing us a favour, and a fixed minute spends the same number
/// of requests at three in the morning as it does mid-session — for figures
/// that, when nothing is running, haven't moved in hours. The fixed choices
/// are kept for when you want to know exactly what Pulse is doing.
enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    /// Paces itself. See `AdaptiveRefresh` for what it reacts to.
    case automatic = 0
    case halfMinute = 30
    case minute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800

    static let `default` = RefreshInterval.automatic

    var id: Int { rawValue }

    /// Nil when the wait is worked out afresh at each tick.
    var seconds: TimeInterval? { self == .automatic ? nil : TimeInterval(rawValue) }

    var title: String {
        // Same word as the connection setting's automatic, and the same idea:
        // let Pulse decide unless you have a reason not to.
        if self == .automatic { return .localized("Automatic") }

        // Interpolate a string, never the integer directly: an `Int` in a
        // localization key produces `%lld`, which won't match a `%@` entry in
        // the strings file and silently falls through to English.
        if rawValue < 60 { return .localized("\("\(rawValue)") seconds") }


        let minutes = rawValue / 60
        return minutes == 1
            ? .localized("1 minute")
            : .localized("\("\(minutes)") minutes")
    }
}

/// How big the floating panel is drawn.
///
/// One multiplier applied to every measurement in `DockLayout` and
/// `DetailCardLayout`, so the AppKit window frame and the SwiftUI content
/// scale together — they are computed from the same constants, which is what
/// keeps them from drifting apart.
enum PanelSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case standard
    case large

    static let `default` = PanelSize.standard

    var id: String { rawValue }

    /// Deliberately modest steps. The panel sits over the user's work all day;
    /// "large" is meant to be readable from further away, not to take over the
    /// side of the display.
    var scale: CGFloat {
        switch self {
        case .small: 0.82
        case .standard: 1
        case .large: 1.22
        }
    }

    var title: String {
        switch self {
        case .small: .localized("Small")
        case .standard: .localized("Standard")
        case .large: .localized("Large")
        }
    }
}

/// How much air there is between the rings.
///
/// Separate from `PanelSize`, which scales everything at once — this moves only
/// the gap, so the rings stay the size they were and the rail gets shorter or
/// longer around them. Someone watching seven accounts wants it tighter than
/// someone watching two, and that is not the same wish as wanting bigger rings.
enum RailSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case roomy

    static let `default` = RailSpacing.standard

    var id: String { rawValue }

    /// Applied to `DockLayout.itemSpacing`, so the standard one is what the
    /// rail has always been.
    var scale: CGFloat {
        switch self {
        case .compact: 0.6
        case .standard: 1
        case .roomy: 1.4
        }
    }

    var title: String {
        switch self {
        case .compact: .localized("Tight")
        case .standard: .localized("Standard")
        case .roomy: .localized("Loose")
        }
    }
}

/// The scale every panel measurement is multiplied by.
///
/// A stored value rather than something threaded through every call site,
/// because the measurements are read from both sides of the AppKit/SwiftUI
/// boundary — the panel's frame is computed from them before SwiftUI has laid
/// anything out. Written on the main thread when the setting changes and read
/// from layout; the lock covers the crossing, the same way `LocalizationSource`
/// handles its bundle.
enum PanelMetrics {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: CGFloat = PanelSize.default.scale

    /// Whether the rail keeps its percent labels when it is lying along the
    /// top of the screen. Off by default: a horizontal rail is under the menu
    /// bar, where a second line of type turns a compact pill into a banner.
    ///
    /// Kept here beside the scale rather than passed down because it changes
    /// the rail's *thickness*, which the AppKit window frame is worked out
    /// from before SwiftUI has laid anything out — the same reason `scale`
    /// lives here. `AppSettings` writes both.
    /// The gap between rings, as a multiplier. Here rather than passed down
    /// for the same reason as the scale: it changes the rail's length, and the
    /// AppKit frame is worked out from that before SwiftUI lays anything out.
    nonisolated(unsafe) private static var storedSpacing = RailSpacing.default.scale

    nonisolated(unsafe) private static var storedTopPercentages = false
    /// The same for a rail down a side, where the default is the other way
    /// round: the label sits under its ring and costs nothing there.
    nonisolated(unsafe) private static var storedSidePercentages = true

    /// Whether the percent label is drawn *above* its ring rather than below.
    ///
    /// Here beside the others because it moves where a ring's centre sits
    /// inside its item, and the hit testing has to agree with the drawing to
    /// within a point or a click lands beside the ring it appears to be on.
    nonisolated(unsafe) private static var storedLabelAboveRing = false

    /// How many rings the panel has to leave room for.
    ///
    /// Not `Provider.allCases.count` any more: one provider can be signed in
    /// to more than once, so the rail can be longer than there are providers.
    /// It lives here beside the scale for the same reason — the AppKit frame
    /// is worked out from it before SwiftUI lays anything out — and getting it
    /// wrong slices the end off the rail, which is exactly what happened the
    /// first time a seventh account existed.
    nonisolated(unsafe) private static var storedCapacity = Provider.allCases.count

    static var scale: CGFloat { lock.withLock { stored } }
    static var spacing: CGFloat { lock.withLock { storedSpacing } }
    static var topRailShowsPercentages: Bool { lock.withLock { storedTopPercentages } }
    static var sideRailShowsPercentages: Bool { lock.withLock { storedSidePercentages } }
    static var labelAboveRing: Bool { lock.withLock { storedLabelAboveRing } }
    static var railCapacity: Int { lock.withLock { storedCapacity } }

    static func use(_ size: PanelSize) {
        lock.withLock { stored = size.scale }
    }

    static func use(_ spacing: RailSpacing) {
        lock.withLock { storedSpacing = spacing.scale }
    }

    static func showTopPercentages(_ shows: Bool) {
        lock.withLock { storedTopPercentages = shows }
    }

    static func showSidePercentages(_ shows: Bool) {
        lock.withLock { storedSidePercentages = shows }
    }

    static func putLabelAboveRing(_ above: Bool) {
        lock.withLock { storedLabelAboveRing = above }
    }

    static func makeRoom(for accounts: Int) {
        lock.withLock { storedCapacity = max(accounts, 1) }
    }
}
