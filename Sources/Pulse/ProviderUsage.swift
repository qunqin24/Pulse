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

    /// Whether the provider says this limit is spent.
    ///
    /// Taken from the provider rather than inferred, because they are the ones
    /// who decide: Claude Code reports a `severity` and a `locked_reason` per
    /// limit, Codex a `limit_reached` per group. A percentage can also sail
    /// past 100 on a spend limit, at which point the ring is already full and
    /// only this can say so.
    var isExhausted: Bool = false

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

    var percentText: String { "\(Int((usedFraction * 100).rounded()))%" }

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
            case .codexNotInstalled: .localized("Codex isn't installed.")
            case .codexServerFailed: .localized("Couldn't start the Codex helper.")
            case .antigravityNotRunning: .localized("Open Antigravity to see its usage.")
            case .cursorSignInRequired: .localized("Sign in to Cursor to see usage.")
            case .cursorLoginExpired: .localized("Cursor's saved login was refused. Open Cursor to renew it.")
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
