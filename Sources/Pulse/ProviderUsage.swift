import Foundation

/// One rate-limit window exactly as a provider reports it.
///
/// Everything here comes from the provider — Pulse never derives a percentage
/// of its own, because the token budgets behind these limits aren't published
/// and any guess would be presented as fact.
struct UsageWindow: Identifiable, Equatable, Codable, Sendable {
    /// What kind of window this is, kept as meaning rather than as text.
    ///
    /// Names are built on demand in `name` instead of being stored: a window
    /// is read once when the provider reports it but may be displayed long
    /// after, and storing the translation would freeze it in whichever
    /// language was current at the moment it was fetched.
    enum Kind: Equatable, Codable, Sendable {
        case fiveHour
        case weekly
        case spend
        /// OpenCode Go's billing period. The others' longest window is a
        /// week, so this one had nowhere to map.
        case monthly
        case other(seconds: Int)
    }

    /// Stable across refreshes, so SwiftUI keeps a row's identity while its
    /// numbers change.
    let id: String
    let kind: Kind
    /// The model this limit is scoped to, when the provider scopes it to one.
    /// A product name, so it is never translated.
    let scope: String?
    /// 0...1 under normal conditions, but a provider may report over 100%
    /// once a limit is exceeded.
    let usedFraction: Double
    let windowSeconds: Int
    let resetsAt: Date?

    /// Whether `windowSeconds` is a length the provider actually **stated**,
    /// or one chosen so the row sorts.
    ///
    /// They are not the same thing and only one of them can be divided by.
    /// Kimi's weekly allowance reports a reset and no length — the window
    /// rolls, so the reset lands anywhere inside the week — and its seconds
    /// exist to put it after the shorter windows; Cursor's pools reset with a
    /// billing cycle that is 28 to 31 days and are stored as a flat 30. Both
    /// are fine to sort by and fine to leave undisplayed, and both would make
    /// `elapsedFraction` draw an arc nobody reported.
    var reportsLength: Bool = true

    /// Whether the provider says this limit is spent.
    ///
    /// Taken from the provider rather than inferred, because they are the ones
    /// who decide: Claude Code reports a `severity` and a `locked_reason` per
    /// limit, Codex a `limit_reached` per group. A percentage can also sail
    /// past 100 on a spend limit, at which point the ring is already full and
    /// only this can say so.
    var isExhausted: Bool = false

    /// How much of this window has gone by, 0...1 — the other half of the
    /// reading the rail can show.
    ///
    /// "80% used" says nothing on its own about whether that is a problem: 80%
    /// spent a fifth of the way into the window means running out, and 80%
    /// spent with minutes left on the clock means it was budgeted about right.
    /// The two are only comparable when both are on screen.
    ///
    /// **Nil rather than a guess.** It needs a reset time *and* a length, and
    /// a provider that reports one without the other cannot have this worked
    /// out for it — the same rule that drops a window whose length can't be
    /// read rather than inventing one.
    func elapsedFraction(at now: Date = Date()) -> Double? {
        // `windowSeconds > 0` is not evidence that a length was reported — a
        // sort key is also a positive number. Dividing by one draws a fraction
        // the provider never gave, which is the one thing this app does not do
        // outside the labelled money estimate.
        guard reportsLength, let resetsAt, windowSeconds > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / Double(windowSeconds), 0), 1)
    }

    var name: String {
        let base: String = switch kind {
        case .fiveHour: .localized("5-hour limit")
        case .weekly: .localized("Weekly limit")
        case .spend: .localized("Spend limit")
        case .monthly: .localized("Monthly limit")
        case .other(let seconds):
            seconds >= 86_400
                ? .localized("\("\(Int((Double(seconds) / 86_400).rounded()))")-day limit")
                : .localized("\("\(Int((Double(seconds) / 3_600).rounded()))")-hour limit")
        }
        return scope.map { "\(base) · \($0)" } ?? base
    }

    /// Rounded to the nearest whole number, **except that anything used at
    /// all never reads as 0%**.
    ///
    /// The mark says so whether the figure does or not: the ring's arc is
    /// drawn with a round cap and the progress bar with a capsule, so the
    /// smallest non-zero reading still puts a dot of colour on screen. A
    /// figure of 0% beside it is the same number disagreeing with itself, and
    /// the colour is the half that is right — you have started. It is also
    /// what the providers do: Cursor reports 0.03% and its own page says 1%.
    var percentText: String { percentText(remaining: false) }

    /// The same reading counted from the other end, when the user has asked to
    /// see what is **left**.
    ///
    /// **Both ends get the rule, not just one.** Subtracting the figure above
    /// from 100 looks tidier and is wrong at the extremes: a window 99.6%
    /// spent would read "0% left" while there is still something there, which
    /// is the same lie the rule above exists to prevent, told backwards. And a
    /// window 0.4% spent would read "100% left" when it isn't.
    ///
    /// So the figure shown is the one being displayed, held off both ends:
    /// nothing left reads 0%, anything left reads at least 1%, and nothing
    /// used reads 100% while anything used reads at most 99%. The two views
    /// need not sum to 100 — only one of them is ever on screen.
    func percentText(remaining: Bool) -> String {
        guard remaining else { return Self.figure(usedFraction) }
        return Self.figure(remainingFraction)
    }

    /// A fraction as a whole percentage that never rounds away the fact that
    /// there is *some*, or that there is *not all*.
    private static func figure(_ fraction: Double) -> String {
        let percent = min(max(fraction, 0), 1) * 100
        if percent <= 0 { return "0%" }
        if percent >= 100 { return "100%" }
        return "\(Int(min(max(percent.rounded(), 1), 99)))%"
    }

    /// What is left of the window, 0...1 — the arc when the figure is flipped.
    var remainingFraction: Double { min(max(1 - usedFraction, 0), 1) }

    /// "5h" / "7d" style description of the window's length.
    ///
    /// The counts are interpolated as strings: an `Int` in a localization key
    /// produces `%lld`, which won't match a `%@` entry in the strings file and
    /// falls through to English without complaining.
    var lengthText: String {
        let hours = Double(windowSeconds) / 3600
        if hours >= 24 {
            return String.localized("\("\(Int((hours / 24).rounded()))") days")
        }
        return String.localized("\("\(Int(hours.rounded()))") hours")
    }
}

/// Everything Pulse currently knows about one provider.
struct ProviderUsage: Identifiable, Equatable, Sendable {
    /// Why there is nothing to show.
    ///
    /// Kept as a case rather than a finished sentence for the same reason
    /// `UsageWindow.Kind` is: the text is produced when it's displayed, so it
    /// follows the language setting instead of freezing at whichever language
    /// was current when the reading was taken.
    enum Unavailability: Equatable, Sendable {
        case loading
        /// Claude Code's status line hook hasn't been registered.
        case notConnected
        /// Registered, but Claude Code hasn't reported anything yet.
        case awaitingResponse
        case noLimitsReported
        case signInRequired
        /// No usable Claude Code login, and nothing captured either.
        case claudeSignInRequired
        /// Signed in, but the login Claude Code saved has gone stale and
        /// nothing here can renew it.
        case claudeLoginExpired
        /// The desktop route, and its three separate ways of coming up empty.
        /// No desktop app on this Mac, or one that has never been signed in.
        case claudeDesktopNotSignedIn
        /// Its cookie store is there and its keychain key was not handed over
        /// — the prompt was denied, or dismissed. The remedy is to ask again,
        /// which is what the pane's own refresh does.
        case claudeDesktopKeyRefused
        /// The session was read and the service refused it.
        case claudeDesktopSessionExpired
        /// The `codex` command isn't installed, or isn't where we looked.
        case codexNotInstalled
        /// Found `codex`, but `codex app-server` wouldn't start.
        case codexServerFailed
        /// Antigravity's limits live in a server it only runs while it is open.
        case antigravityNotRunning
        /// Cursor has never been signed in on this Mac, so there is no login
        /// to borrow.
        case cursorSignInRequired
        /// There is a login, and the account refused it.
        case cursorLoginExpired
        /// An account Pulse signed in to itself, whose login has gone and
        /// cannot be renewed. Names no provider: every added account can
        /// reach this, and a message naming one is the trap the rest of this
        /// enum was fixed for once already.
        case signedOut
        /// Never signed in here, as against a login that has since gone bad.
        /// The difference is one word, and it is the difference between an
        /// instruction and a puzzle.
        case notSignedIn
        /// Ollama has no quota API: the figures come from its signed-in
        /// settings page, so what it needs is a browser session rather than a
        /// key, and the three ways that can fail are worth telling apart.
        case ollamaSessionMissing
        case ollamaSessionExpired
        /// The page was fetched and did not contain the two figures. Reported
        /// rather than shown as zero: reading a page is reading someone's
        /// layout, and a layout can change.
        case ollamaPageChanged
        /// No key has been entered for a provider that needs one.
        case apiKeyMissing
        /// There is a key, and the service refused it.
        case apiKeyRefused
        case unreachable
        case unreadableReply
        case rateLimited
        case serverError

        var message: String {
            switch self {
            case .loading: .localized("Loading…")
            case .notConnected: .localized("Connect Claude Code in Settings to see usage.")
            case .awaitingResponse: .localized("Waiting for the next Claude Code response.")
            case .noLimitsReported: .localized("No limits reported.")
            case .signInRequired: .localized("Sign in to Codex to see usage.")
            case .claudeSignInRequired: .localized("Sign in to Claude Code to see usage.")
            case .claudeLoginExpired: .localized("Claude Code's saved login expired. Use Claude Code, or connect the status line.")
            case .claudeDesktopNotSignedIn: .localized("Sign in to the Claude desktop app to see usage.")
            case .claudeDesktopKeyRefused: .localized("Pulse needs your keychain to read the Claude desktop app's session. Refresh to be asked again.")
            case .claudeDesktopSessionExpired: .localized("The Claude desktop app's session was refused. Open it and sign in again.")
            case .codexNotInstalled: .localized("Codex isn't installed.")
            case .codexServerFailed: .localized("Couldn't start the Codex helper.")
            case .antigravityNotRunning: .localized("Open Antigravity to see its usage.")
            case .cursorSignInRequired: .localized("Sign in to Cursor to see usage.")
            case .cursorLoginExpired: .localized("Cursor's saved login was refused. Open Cursor to renew it.")
            case .signedOut: .localized("Sign in to this account again in Settings.")
            case .notSignedIn: .localized("Sign in from Settings to see usage.")
            case .ollamaSessionMissing: .localized("Add an Ollama session in Settings.")
            case .ollamaSessionExpired: .localized("The Ollama session expired. Sign in again and add it.")
            case .ollamaPageChanged: .localized("Ollama's page has changed and can no longer be read.")
            case .apiKeyMissing: .localized("Add an API key in Settings.")
            case .apiKeyRefused: .localized("That key was refused. Check it in Settings.")
            case .unreachable: .localized("The service didn't respond.")
            case .unreadableReply: .localized("Couldn't read the reply.")
            case .rateLimited: .localized("Checking too often — easing off.")
            case .serverError: .localized("The service returned an error.")
            }
        }
    }

    enum State: Equatable, Sendable {
        /// Fetched from the provider, and current.
        case live
        /// The last known reading, from when the provider last reported one.
        case stale
        /// Nothing to show, and why.
        case unavailable(Unavailability)
    }

    /// Which account this reading belongs to. The provider alone stopped
    /// being enough once one of them could be signed in to twice.
    let account: AccountKey
    /// Ordered as the provider reports them; the first one drives the ring.
    let windows: [UsageWindow]
    let observedAt: Date?
    let state: State
    /// Plan name, when the provider names one.
    let plan: String?
    /// Remaining credit, when the provider reports it.
    let creditBalance: String?

    var provider: Provider { account.provider }
    var id: String { account.id }

    /// The window the rail's ring shows.
    ///
    /// By default the one closest to being used up, so the ring reflects
    /// whichever limit will actually bite first. A provider can be pinned to a
    /// particular window in settings; a pin that no longer matches anything —
    /// a model that stopped being reported, say — quietly reverts to the
    /// default rather than leaving the ring blank.
    func headlineWindow(preferring id: String? = nil) -> UsageWindow? {
        if let id, let pinned = windows.first(where: { $0.id == id }) { return pinned }
        return windows.max { $0.usedFraction < $1.usedFraction }
    }

    static func unavailable(_ provider: Provider, reason: Unavailability) -> ProviderUsage {
        unavailable(AccountKey(provider), reason: reason)
    }

    static func unavailable(_ account: AccountKey, reason: Unavailability) -> ProviderUsage {
        ProviderUsage(
            account: account,
            windows: [],
            observedAt: nil,
            state: .unavailable(reason),
            plan: nil,
            creditBalance: nil
        )
    }
}
