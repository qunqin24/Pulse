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
        /// Prepaid credit, which is **not a limit**. DeepSeek sells money
        /// rather than an allowance: there is no ceiling to reach, no window
        /// to turn over, and calling it a spend limit put the word "limit"
        /// on a row where none exists.
        case balance
        /// OpenCode Go's billing period. The others' longest window is a
        /// week, so this one had nowhere to map.
        case monthly
        case other(seconds: Int)

        /// Ribbons are for a week or a month coming back, not a five-hour
        /// session rolling over. Codex's session clock moves several times a
        /// day; celebrating that is how the overlay played when nothing the
        /// user would call a reset had happened.
        var celebratesReset: Bool {
            switch self {
            case .weekly, .monthly: true
            case .fiveHour, .spend, .balance, .other: false
            }
        }
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

    /// Where this limit's denominator came from, when it did not come from the
    /// provider.
    ///
    /// Set only where a provider states how much of an allowance is **left**
    /// and never how large the allowance is. The row says which on screen and
    /// in `--json`, because the rule everywhere else is that a percentage comes
    /// from the provider.
    ///
    /// **This is why it is not `scope`.** Scope is a product name and
    /// `Docs/json-output.md` promises it reads the same in every language — a
    /// translated qualifier there breaks any script matching on it, which is
    /// exactly what putting "since top-up" in it did. A case here has a stable
    /// token for the contract and a localized title for the card.
    enum Estimate: String, Equatable, Codable, Sendable {
        /// Command Code: the monthly grant, from its published plan price.
        case planPrice
        /// DeepSeek: the highest balance Pulse has watched.
        case sinceTopUp
        /// DeepSeek: a figure the reader typed.
        case yourBudget

        var title: String {
            switch self {
            case .planPrice: .localized("estimated")
            case .sinceTopUp: .localized("since top-up")
            case .yourBudget: .localized("of your budget")
            }
        }
    }

    var estimate: Estimate?

    /// Spelled out because the hand-written `init(from:)` below suppresses the
    /// synthesised one. Same order and same defaults as before.
    init(
        id: String,
        kind: Kind,
        scope: String?,
        usedFraction: Double,
        windowSeconds: Int,
        resetsAt: Date?,
        reportsLength: Bool = true,
        estimate: Estimate? = nil,
        isExhausted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.usedFraction = usedFraction
        self.windowSeconds = windowSeconds
        self.resetsAt = resetsAt
        self.reportsLength = reportsLength
        self.estimate = estimate
        self.isExhausted = isExhausted
    }

    /// Decoded by hand for one reason: `estimate` replaced a stored
    /// `isEstimated: Bool`, and a cache written by 1.0.9 carries the old key.
    /// The synthesised decoder ignores it and leaves `estimate` nil, so the
    /// first launch after upgrading drew Command Code's inferred monthly
    /// percentage with nothing marking it as inferred — until that provider
    /// happened to refresh, which on the ceiling is half an hour, and never at
    /// all for `--json` if the app is not running.
    ///
    /// `.planPrice` because it was the only estimate that existed when that
    /// key was being written.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        usedFraction = try container.decode(Double.self, forKey: .usedFraction)
        windowSeconds = try container.decode(Int.self, forKey: .windowSeconds)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        reportsLength = try container.decodeIfPresent(Bool.self, forKey: .reportsLength) ?? true
        isExhausted = try container.decodeIfPresent(Bool.self, forKey: .isExhausted) ?? false

        if let estimate = try container.decodeIfPresent(Estimate.self, forKey: .estimate) {
            self.estimate = estimate
        } else {
            let legacy = try container.decodeIfPresent(Bool.self, forKey: .isEstimated) ?? false
            self.estimate = legacy ? .planPrice : nil
        }
    }

    /// Written by hand alongside the decoder, because `CodingKeys` carries a
    /// legacy case with no property behind it. **`isEstimated` is read and
    /// never written**: nothing new should be putting the old shape back on
    /// disk.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encode(usedFraction, forKey: .usedFraction)
        try container.encode(windowSeconds, forKey: .windowSeconds)
        try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
        try container.encode(reportsLength, forKey: .reportsLength)
        try container.encodeIfPresent(estimate, forKey: .estimate)
        try container.encode(isExhausted, forKey: .isExhausted)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, scope, usedFraction, windowSeconds, resetsAt
        case reportsLength, isExhausted, estimate
        /// Written by 1.0.9 and earlier. Read, never written.
        case isEstimated
    }

    /// Whether the denominator was inferred at all, which is what `--json`
    /// reports and what anything holding Pulse to "figures the provider
    /// reported" filters on.
    var isEstimated: Bool { estimate != nil }

    /// Whether the provider says this limit is spent.
    ///
    /// Taken from the provider rather than inferred, because they are the ones
    /// who decide: Claude Code reports a `severity` and a `locked_reason` per
    /// limit, Codex a `limit_reached` per group. A percentage can also sail
    /// past 100 on a spend limit, at which point the ring is already full and
    /// only this can say so.
    var isExhausted: Bool = false

    /// Same figures with a different reset. Used when a sibling limit stated
    /// the date and this one did not.
    func with(resetsAt: Date) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: scope,
            usedFraction: usedFraction,
            windowSeconds: windowSeconds,
            resetsAt: resetsAt,
            reportsLength: reportsLength,
            isExhausted: isExhausted
        )
    }

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
        case .balance: .localized("Balance")
        case .monthly: .localized("Monthly limit")
        case .other(let seconds):
            seconds >= 86_400
                ? .localized("\("\(Int((Double(seconds) / 86_400).rounded()))")-day limit")
                : .localized("\("\(Int((Double(seconds) / 3_600).rounded()))")-hour limit")
        }
        let scoped = scope.map { "\(base) · \($0)" } ?? base
        return estimate.map { "\(scoped) · \($0.title)" } ?? scoped
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

    /// The same figure as `percentText`, as a number.
    ///
    /// One rule, two renderings: `--json` prints an integer and the panel
    /// prints a string, and a status line built from the first must agree with
    /// the ring built from the second. Two copies of "never round away the
    /// fact that there is *some*" would eventually disagree by a point, at the
    /// one end where a point is the whole message.
    func percentValue(remaining: Bool = false) -> Int {
        Self.figure(remaining ? remainingFraction : usedFraction)
    }

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
        "\(percentValue(remaining: remaining))%"
    }

    /// A fraction as a whole percentage that never rounds away the fact that
    /// there is *some*, or that there is *not all*.
    private static func figure(_ fraction: Double) -> Int {
        // **NaN first, because `min`/`max` propagate it rather than clamping**
        // and `Int(NaN)` traps. A budget of "inf" typed into Settings reached
        // here as (inf − balance)/inf, and the panel then crashed on every
        // launch until the field was cleared, because the figure is persisted.
        // Guarded at the source too; this is the one that cannot be bypassed.
        guard fraction.isFinite else { return 0 }
        let percent = min(max(fraction, 0), 1) * 100
        if percent <= 0 { return 0 }
        if percent >= 100 { return 100 }
        return Int(min(max(percent.rounded(), 1), 99))
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
    enum Unavailability: String, Equatable, Sendable {
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
        /// It **is** open, and every helper it runs refused this RPC — a
        /// version bump, or the app still starting. Its own case because
        /// "Open Antigravity" is false advice when it is already open, and
        /// because a fault the user can only wait out is not one to be told
        /// about on a timer.
        case antigravityNotAnswering
        /// Cursor has never been signed in on this Mac, so there is no login
        /// to borrow.
        case cursorSignInRequired
        /// There is a login, and the account refused it.
        case cursorLoginExpired
        /// Grok Build's CLI has never signed in on this Mac, so there is no
        /// login to borrow. Its own case rather than `.signInRequired`, which
        /// names Codex — the trap the rest of this enum was fixed for once
        /// already.
        case grokSignInRequired
        /// There is a login and it has aged out. The CLI renews its own token
        /// while it is used and nothing renews it for Pulse, so the remedy is
        /// to use Grok, exactly as with Cursor.
        case grokLoginExpired
        /// Kimi Code's subscription login has never been driven from Pulse,
        /// and no API key has been pasted either. Its own case rather than
        /// `.apiKeyMissing`, which tells a subscriber to go looking for a
        /// key they do not need.
        case kimiSignInRequired
        /// Pulse held a Kimi Code login and it will no longer refresh. The
        /// remedy is to sign in again in Settings — not to paste a key, and
        /// not to run the CLI. Pulse does not borrow the CLI's refresh token.
        case kimiLoginExpired
        /// A plan that simply does not include Grok Bot. Not a failure to
        /// report anything — a complete answer, and "no limits reported"
        /// would send someone looking for a fault that is not there.
        case grokBotNotIncluded
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
        /// Qoder's Credits are read with a browser session, same as Ollama,
        /// so a missing or refused session is a setup step rather than a key.
        case qoderSessionMissing
        case qoderSessionExpired
        /// The page was fetched and did not contain the two figures. Reported
        /// rather than shown as zero: reading a page is reading someone's
        /// layout, and a layout can change.
        case ollamaPageChanged
        /// Volcengine's CLI isn't on this Mac. Named rather than shared,
        /// because the remedy is a specific command and the alternative — an
        /// access key pair — is a different thing to be told about.
        case volcengineCLIMissing
        /// It is installed and has never been signed in, or the session went.
        case volcengineSignInRequired
        /// The key works and the account has no Coding Plan running on it.
        ///
        /// Measured with a live Coding Plan key whose subscription had lapsed:
        /// `500 当前用户不存在coding plan`, over an HTTP 200, on all three
        /// hosts, from a key that answers a `glm-4-flash` completion perfectly
        /// well. The plan is a **subscription on the account**, not a property
        /// of the key, so authentication succeeding says nothing about whether
        /// there is a quota to report. A complete answer, not a fault — and it
        /// used to be reported as "the service returned an error", which sends
        /// somebody to look for an outage instead of at their subscription.
        case zaiNoCodingPlan
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
            case .antigravityNotAnswering: .localized("Antigravity is open but didn't answer. Restarting it usually helps.")
            case .cursorSignInRequired: .localized("Sign in to Cursor to see usage.")
            case .cursorLoginExpired: .localized("Cursor's saved login was refused. Open Cursor to renew it.")
            case .grokSignInRequired: .localized("Sign in to Grok to see usage.")
            case .grokLoginExpired: .localized("Grok's saved login expired. Use Grok to renew it.")
            case .kimiSignInRequired: .localized("Sign in to Kimi Code in Settings, or paste an API key.")
            case .kimiLoginExpired: .localized("Kimi Code's saved login expired. Sign in again in Settings.")
            case .grokBotNotIncluded: .localized("This Cursor plan doesn't include Grok Bot.")
            case .signedOut: .localized("Sign in to this account again in Settings.")
            case .notSignedIn: .localized("Sign in from Settings to see usage.")
            case .ollamaSessionMissing: .localized("Add an Ollama session in Settings.")
            case .ollamaSessionExpired: .localized("The Ollama session expired. Sign in again and add it.")
            case .qoderSessionMissing: .localized("Add a Qoder session in Settings.")
            case .qoderSessionExpired: .localized("The Qoder session expired. Sign in again and add it.")
            case .ollamaPageChanged: .localized("Ollama's page has changed and can no longer be read.")
            case .volcengineCLIMissing: .localized("Install arkcli and run `arkcli auth login`, or add access keys in Settings.")
            case .volcengineSignInRequired: .localized("arkcli isn't signed in. Run `arkcli auth login`.")
            case .zaiNoCodingPlan: .localized("That key works. The account has no Coding Plan running on it.")
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
    /// Remaining credit, when the provider reports it. Formatted for display,
    /// which is all most of the app wants.
    let creditBalance: String?
    /// The same figure as a number, where there is one to compare.
    ///
    /// **Separate from `creditBalance` on purpose.** That is a display string
    /// and is sometimes prose — Codex says "Unlimited" — so nothing may be
    /// decided from it. A low-balance warning has to compare money against
    /// money, and it must not compare ¥ against $, so the currency travels
    /// with the amount.
    var creditRemaining: CreditAmount?

    var origin: UsageRoute?
    /// A stale status-line capture is not necessarily a cache replacement.
    var isCached = false
    /// Only the latest fetch carries attempts; the cache stores the origin alone.
    var attempts: [ConnectionDiagnostic.Attempt] = []

    /// Money the provider says is left, and what it is denominated in.
    struct CreditAmount: Equatable, Sendable {
        let amount: Double
        /// An ISO code, as the provider gave it.
        let currency: String

        /// Short enough to read inside a ring.
        ///
        /// The rail's label is budgeted for "100%" — 38pt — and money is not
        /// bounded by anything: a ¥5,000 balance formats as "¥5,000.00" at
        /// 64pt and a US reader looking at a CNY account gets "CN¥5,000.00" at
        /// 83pt. Both were being truncated, because `minimumScaleFactor` stops
        /// at 0.6 and those need 0.56 and 0.43.
        ///
        /// So the ring gets a glance and the card keeps the figure. Rounding
        /// for display is what `percentText` already does; the exact balance is
        /// a hover away and is also in Settings.
        ///
        /// `.narrow` is what turns "CN¥" back into "¥": the wide form
        /// disambiguates currencies that share a symbol, which is worth 45pt
        /// somewhere the currency is not already fixed by the account.
        func railText(locale: Locale = LocalizationSource.locale) -> String {
            let magnitude = abs(amount)
            let (value, suffix): (Double, String) = if magnitude >= 1_000_000 {
                (amount / 1_000_000, "M")
            } else if magnitude >= 1_000 {
                (amount / 1_000, "k")
            } else {
                (amount, "")
            }

            // Three digits and a decimal point is as wide as this may get, so
            // anything into the hundreds loses its fraction rather than its
            // legibility. Cents survive only below a hundred, where they are
            // the part somebody might actually be watching.
            let places = abs(value) >= 100 ? 0 : (suffix.isEmpty ? 2 : 1)

            // **Truncated, never rounded.** A balance shown as more than it is
            // is the wrong way to be wrong — and it also settles the rollover
            // for free: 999,999 becomes "¥999k" rather than the "¥1,000k" that
            // rounding to one place produced.
            let scale = pow(10, Double(places))
            let shown = (value * scale).rounded(.towardZero) / scale

            return symbol(locale) + shown.formatted(
                .number.precision(.fractionLength(0...places)).grouping(.never)
                    .locale(locale)
            ) + suffix
        }

        /// The currency's narrow symbol, taken from a formatted zero so the
        /// locale's own choice is used rather than a table of symbols here.
        private func symbol(_ locale: Locale) -> String {
            0.formatted(
                .currency(code: currency).presentation(.narrow)
                    .precision(.fractionLength(0)).locale(locale)
            )
            .filter { !$0.isNumber && !$0.isWhitespace }
        }
    }

    var provider: Provider { account.provider }
    var id: String { account.id }

    /// The window the rail's ring shows.
    ///
    /// By default the one closest to being used up, so the ring reflects
    /// whichever limit will actually bite first — unless the provider names
    /// an included pool that should lead (Cursor's own models, not the small
    /// overflow lane). A provider can be pinned to a particular window in
    /// settings; a pin that no longer matches anything — a model that stopped
    /// being reported, say — quietly reverts to the default rather than
    /// leaving the ring blank.
    /// Whether this reading actually says anything.
    ///
    /// **Not `!windows.isEmpty`.** That was the test everywhere, on the fair
    /// assumption that a reading with no limits in it is a fetch that went
    /// wrong — every service that has nothing to report says
    /// `.noLimitsReported` rather than returning an empty `.live`. DeepSeek
    /// broke the assumption: it sells prepaid credit and reports no allowance,
    /// so on "balance only" a **complete** answer is deliberately a balance and
    /// no windows at all. Read as a failure, the cache kept handing back the
    /// previous reading and the setting appeared to do nothing.
    var reportsSomething: Bool { !windows.isEmpty || creditBalance != nil }

    func headlineWindow(preferring id: String? = nil) -> UsageWindow? {
        if let id, let pinned = windows.first(where: { $0.id == id }) { return pinned }
        if let preferred = account.provider.preferredHeadlineWindowID,
           let match = windows.first(where: { $0.id == preferred }) {
            return match
        }
        return windows.max { $0.usedFraction < $1.usedFraction }
    }

    /// The limit the second ring shows: **the fullest of the ring's own model
    /// group**, or of everything else where the group has nothing more.
    ///
    /// The group comes first because a provider can report two independent
    /// budgets. Antigravity reports four windows — a five-hour and a weekly
    /// for "Gemini", and the same pair for "Claude and GPT" — and they are
    /// separate pools. Pairing the ring's weekly Gemini figure with a
    /// five-hour Claude one puts two unrelated budgets on one mark: neither
    /// number says anything about the other, and the reader has no way to
    /// tell they are being mixed. Same group, and the two rings answer one
    /// question — how much of *this* pool is gone, over five hours and over
    /// the week.
    ///
    /// Claude Code falls out of the same rule for free: its five-hour and
    /// weekly limits are unscoped, so they are each other's group, and the
    /// model-scoped weekly is left to the card.
    ///
    /// The fallback matters for the provider whose ring is the only window in
    /// its group — better a second limit from elsewhere than an empty ring.
    /// Stated as "fullest" rather than "the weekly one" so it needs no table
    /// of which window each provider considers its long one, and so it keeps
    /// working when the ring is pinned.
    ///
    /// Nil when the provider reports one limit. An empty second ring reads as
    /// a limit at zero, or as a fault.
    func secondWindow(preferring id: String? = nil) -> UsageWindow? {
        guard let headline = headlineWindow(preferring: id), windows.count > 1 else { return nil }

        let rest = windows.filter { $0.id != headline.id }
        let sameGroup = rest.filter { $0.scope == headline.scope }
        // `max(by:)` keeps the first of equals, so a rail of untouched windows
        // stays in the provider's own order rather than shuffling between
        // passes.
        return (sameGroup.isEmpty ? rest : sameGroup).max { $0.usedFraction < $1.usedFraction }
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
