import Foundation
import Observation
import UserNotifications

/// How full a limit has to get before Pulse says something unprompted.
///
/// A list rather than a free number: the point of the setting is to pick the
/// moment you want to hear about, and four of them cover it. `off` is the
/// default, because a menu-bar app that starts posting notifications on its
/// own the day you install it has changed what you agreed to.
enum AlertThreshold: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case seventyFive = 75
    case eighty = 80
    case ninety = 90
    case ninetyFive = 95

    static let `default` = AlertThreshold.off

    var id: Int { rawValue }

    /// Nil when nothing is to be said about a limit at all.
    var percent: Int? { self == .off ? nil : rawValue }

    /// Not run through `localized`: a bare percentage is a numeral and a sign,
    /// not a sentence, and a key of `"%@%"` is a format string with a stray
    /// trailing `%` in it — which is exactly the sort of thing that formats
    /// into something else on somebody else's machine.
    var title: String {
        self == .off ? .localized("Off") : "\(rawValue)%"
    }
}

/// One thing worth interrupting somebody for.
///
/// Deliberately few, and every one of them is something you would want to know
/// **while looking at something else** — which is the whole test for whether
/// it belongs here rather than on the card. A limit you are about to run into,
/// one you have run into, one that has come back, and a reading that has
/// stopped arriving so the panel is quietly showing yesterday's figures.
struct UsageAlert: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// Went past the figure the user asked to be told about.
        case approaching(percent: Int)
        /// The provider says it is spent — its own word, not a rounding of
        /// ours. See `UsageWindow.isExhausted`.
        case spent
        /// A window Pulse had already warned about has turned over.
        case reset
        /// A window turned over and the user asked for ribbons. Not posted
        /// as a notification — see `ResetCelebration`.
        case celebration
        /// A prepaid balance fell below the figure the user asked to be told
        /// about. Money, not a percentage: these providers report no allowance
        /// to take a percentage of.
        case lowBalance(remaining: String)
        /// Several passes in a row failed to produce a current reading. The
        /// reason when there is one; nil when the fetch simply failed and the
        /// cache answered in its place.
        case unreadable(ProviderUsage.Unavailability?)
    }

    let account: AccountKey
    let kind: Kind
    /// The limit it is about, or nil when it is about the account as a whole.
    let window: UsageWindow?

    /// Stable per (account, limit, thing being said), so macOS replaces an
    /// earlier notice of the same kind instead of stacking a column of them.
    /// The reset time is part of a reset's identity — two different windows
    /// turning over are two different pieces of news.
    var identifier: String {
        let limit = window?.id ?? "-"
        let what: String = switch kind {
        case .approaching(let percent): "approaching-\(percent)"
        case .spent: "spent"
        case .reset: "reset-\(Int(window?.resetsAt?.timeIntervalSince1970 ?? 0))"
        case .celebration: "celebration-\(Int(window?.resetsAt?.timeIntervalSince1970 ?? 0))"
        case .lowBalance: "low-balance"
        case .unreadable: "unreadable"
        }
        return "\(account.id)|\(limit)|\(what)"
    }
}

/// What Pulse has already said, so that it does not say it again.
///
/// Persisted, and that is not a detail. Pulse starts at login and is running
/// while the Mac sleeps, so "have I already mentioned this" cannot live in
/// memory alone: every relaunch would re-announce whatever was already over
/// the line, which is precisely the behaviour that makes people switch
/// notifications off and never switch them back on.
struct AlertMemory: Codable, Sendable, Equatable {
    /// What was last seen of one limit.
    struct Window: Codable, Sendable, Equatable {
        /// The highest step already announced for the window that is currently
        /// open, or 0 for nothing said yet. Cleared when the window turns over.
        var announced = 0
        /// The reading the previous pass saw, so a turnover can be spotted.
        var fraction = 0.0
        var resetsAt: Date?
        /// A candidate turnover waiting for a second live reading.
        ///
        /// Codex can briefly report 0% used without the window having turned
        /// over. Firing on that one sample is how the ribbons played when
        /// nothing had reset. A drop while the stated reset time holds still
        /// has to show up twice; a clock that merely slides is not a refill.
        var pendingReset = false

        enum CodingKeys: String, CodingKey {
            case announced, fraction, resetsAt, pendingReset
        }

        init(announced: Int = 0, fraction: Double = 0, resetsAt: Date? = nil, pendingReset: Bool = false) {
            self.announced = announced
            self.fraction = fraction
            self.resetsAt = resetsAt
            self.pendingReset = pendingReset
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            announced = try container.decodeIfPresent(Int.self, forKey: .announced) ?? 0
            fraction = try container.decodeIfPresent(Double.self, forKey: .fraction) ?? 0
            resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
            pendingReset = try container.decodeIfPresent(Bool.self, forKey: .pendingReset) ?? false
        }
    }

    struct Account: Codable, Sendable, Equatable {
        var windows: [String: Window] = [:]
        /// Consecutive passes that could not produce a current reading.
        var failures = 0
        /// Whether this run of failures has already been reported. Cleared by
        /// the first reading that works, so a provider that comes and goes is
        /// mentioned once per outage rather than once per pass.
        var reportedFailure = false
        /// The low-balance figure already warned about, or nil for nothing
        /// said.
        ///
        /// **The threshold rather than a flag**, so that raising the line
        /// warns again about a balance that was already under the old one —
        /// somebody who moves it from ¥5 to ¥50 is asking a new question and
        /// deserves an answer. Cleared when the balance climbs back over,
        /// which is a top-up.
        var lowBalanceWarnedFor: Double?
    }

    /// Keyed by account id, like every other stored table — see `AccountKey`.
    var accounts: [String: Account] = [:]

    /// How many failed passes before saying so.
    ///
    /// Three, against an interval of 2 to 30 minutes, is between six minutes
    /// and an hour and a half of silence. One failed pass is not news: every
    /// one of these endpoints is undocumented, and a dropped connection or a
    /// rate limit answers for itself on the next tick. Three in a row is a
    /// thing that is not going to fix itself.
    static let failuresBeforeSaying = 3

    /// How old the figures on the panel have to be before a `.stale` reading
    /// counts against the account.
    ///
    /// **`.stale` on its own is not a failure**, which is the trap here.
    /// `UsageCache.reconciled` hands back a stale reading for a *successful*
    /// fetch too: the status-line route calls its capture live for ten minutes,
    /// so a perfectly good capture can be older than what the endpoint banked a
    /// minute ago, and the newer banked one is returned instead — marked stale,
    /// every pass, for an account that is working. Counting that would have put
    /// "Claude Code can't be read" on screen for the one provider most likely to
    /// hit it.
    ///
    /// So the question asked of a stale reading is not "did the fetch fail" —
    /// which it cannot answer, the reason having been swallowed by the fallback
    /// — but the one the user actually cares about: **are the figures on the
    /// panel getting old**. Half an hour is the top of the adaptive interval, so
    /// anything past it has missed at least one pass it was due.
    static let stalenessBeforeSaying: TimeInterval = 1800

    /// What to say about one reading, if anything — and the record of having
    /// said it.
    ///
    /// **Pure, apart from its own `self`.** Everything it decides comes from
    /// the reading, the memory, and the settings; nothing here reads the
    /// clock, the disk, or the notification centre. That is what makes the
    /// rules below arguable at all.
    /// `staleMeansFailure` is false for a route that only produces a reading
    /// while the tool is being *used*. Claude Code's status line is a push:
    /// its capture is marked stale ten minutes after the last response, which
    /// says the user stopped working, not that a check failed. Counted as an
    /// outage it posted "the last few checks didn't get through" over a route
    /// where every check got through — an alert about something Pulse did not
    /// witness, which is the one thing the rules here exist to prevent.
    mutating func alerts(
        for reading: ProviderUsage,
        raw rawState: ProviderUsage.State,
        as account: AccountKey,
        threshold: AlertThreshold,
        announcesReset: Bool,
        announcesFailure: Bool,
        celebratesReset: Bool = false,
        /// The balance to warn below, or nil for no warning on this account.
        lowBalance: Double?,
        staleMeansFailure: Bool,
        now: Date
    ) -> [UsageAlert] {
        var record = accounts[account.id] ?? Account()
        var produced: [UsageAlert] = []

        /// One more pass that produced nothing current, and the one sentence
        /// about it if this is the third.
        func countFailure(_ reason: ProviderUsage.Unavailability?) {
            record.failures += 1
            guard announcesFailure,
                  record.failures >= Self.failuresBeforeSaying,
                  !record.reportedFailure
            else { return }

            record.reportedFailure = true
            produced.append(UsageAlert(account: account, kind: .unreadable(reason), window: nil))
        }

        /// The provider answered. Whatever it said, it can be reached.
        func succeeded() {
            record.failures = 0
            record.reportedFailure = false
        }

        // **Classified on the *raw* fetch, not on what is being shown.**
        // `UsageCache.reconciled` replaces a failed fetch with the last good
        // figures marked `.stale`, which is right for the panel and destroys
        // the evidence here: quitting Antigravity produced
        // `.antigravityNotRunning` — a reason the rules deliberately spare —
        // and the cache handed on a `.stale` reading that aged into "the last
        // few checks didn't get through" about an app that had simply been
        // closed. The tests missed it because they fed the state machine
        // directly; the live path goes service → cache → here.
        switch rawState {
        case .live:
            succeeded()

        case .stale:
            // A service that reports its own staleness rather than a cache
            // standing in for it — Claude Code's status-line capture is the
            // only one. Judged on the age of the figures, and only where
            // staleness can mean failure at all.
            guard staleMeansFailure,
                  let observedAt = reading.observedAt,
                  now.timeIntervalSince(observedAt) > Self.stalenessBeforeSaying
            else { break }
            countFailure(nil)

        case .unavailable(let reason):
            switch Self.standing(of: reason) {
            case .failure:
                if case .stale = reading.state,
                   let observedAt = reading.observedAt,
                   now.timeIntervalSince(observedAt) <= Self.stalenessBeforeSaying {
                    break
                }
                countFailure(reason)
            case .answered: succeeded()
            case .neutral: break
            }
        }

        // **Money, and judged on live readings only** — the same rule as the
        // limits below and for the same reason: a stale reading carries
        // whatever the cache last banked, and warning from it would announce a
        // balance the account may have topped up since.
        //
        // Separate from `threshold` because it answers a different question.
        // These providers report no allowance to take a percentage of; what
        // there is to warn about is the money running out.
        if let lowBalance,
           case .live = rawState, case .live = reading.state,
           let remaining = reading.creditRemaining,
           let formatted = reading.creditBalance {
            if remaining.amount < lowBalance {
                if record.lowBalanceWarnedFor != lowBalance {
                    record.lowBalanceWarnedFor = lowBalance
                    produced.append(UsageAlert(
                        account: account,
                        kind: .lowBalance(remaining: formatted),
                        window: nil
                    ))
                }
            } else {
                // Back over the line — a top-up, or the line moved down.
                // Either way the next crossing is news again.
                record.lowBalanceWarnedFor = nil
            }
        }

        // **Limits are judged on live readings only.** A stale reading carries
        // whatever the cache last banked, which can be *lower* than the figure
        // already recorded here — and a figure that falls is how a reset is
        // detected. Running the cache through these rules would announce a
        // reset every time the network hiccuped.
        //
        // Ribbons still need this loop when the threshold is Off: they fire
        // on the same unambiguous evidence, without a prior warning.
        guard case .live = rawState, case .live = reading.state,
              threshold != .off || celebratesReset,
              let observedAt = reading.observedAt,
              now.timeIntervalSince(observedAt) <= UsageCache.maximumAge else {
            accounts[account.id] = record
            return produced
        }

        for window in reading.windows {
            // A previously live snapshot can outlast its window between polls.
            guard window.resetsAt.map({ $0 > now }) ?? true else { continue }
            let seen = record.windows[window.id]
            // First sighting starts at nothing announced, so a limit that is
            // *already* past the line is said once, now.
            //
            // The alternative — record where it stands and stay quiet until it
            // moves up a step — was tried and is wrong. Someone who switches
            // this on at 93% of their week gets silence and then a wall, which
            // is the feature failing at the only job it has. The burst it was
            // guarding against does not exist at the scale it imagined: this
            // is at most one notification per limit, ever, and only for limits
            // already over the chosen line.
            //
            // The copy is a status, not an event — "92% used", never "just
            // passed 90%" — so it is true whenever it is read, including for a
            // figure that has been true for days.
            var memory = seen ?? Window()

            if let seen {
                let jump: TimeInterval = {
                    guard let new = window.resetsAt, let old = seen.resetsAt else { return 0 }
                    return new.timeIntervalSince(old)
                }()
                // A real turnover jumps by a large share of the window.
                // Codex (and Spark) push `resetsAt` by a few minutes on every
                // poll — CodexBar treats that as the same window, not a new
                // one. A minute of slack was how the ribbons played twice.
                let significantJump = jump > max(
                    30 * 60,
                    TimeInterval(max(window.windowSeconds, 0)) * 0.25
                )
                let emptied = seen.fraction - window.usedFraction >= 0.4
                // Said only when the evidence is unambiguous. A few points of
                // drift is not a reset: a rolling window — Kimi's week, which
                // can reset anywhere inside it — slides down without anything
                // having turned over. A clock that inches forward *without*
                // the tank emptying is not one either. A forty-point drop
                // while the stated reset time holds still (or only slides a
                // little) is a glitch until it shows up twice — Codex has
                // read 0% used without refilling.
                // **Never for a balance.** `Kind.balance` is prepaid credit;
                // switching DeepSeek's denominator must not announce a reset.
                let confirmed = window.kind != .balance && (
                    emptied && significantJump
                    || emptied && seen.resetsAt == nil
                    || emptied && window.resetsAt == nil
                    || emptied && seen.pendingReset
                )

                // **The step is cleared by the same evidence that would
                // announce, not by the drop alone.** Clearing on any 5-point
                // dip re-armed a window that had not reset: a rolling weekly
                // allowance oscillating across the line — 95%, 89%, 93% — was
                // announced at 95, said nothing at 89, and then announced
                // again at 93, for as long as it wobbled. "At most one
                // notification per limit" was written on the tin and was not
                // what it did.
                if confirmed {
                    // And only for a limit that was worth mentioning on the way
                    // up. "Your 5-hour window reset" about a window that never
                    // got past 12% is a notification about nothing.
                    if announcesReset, seen.announced > 0 {
                        produced.append(UsageAlert(account: account, kind: .reset, window: window))
                    }
                    // Ribbons are the opposite: they name the provider so you
                    // can tell who came back, whether or not you were warned.
                    // Five-hour sessions are excluded: they roll several times
                    // a day, which is not the weekly/monthly event CodexBar
                    // plays the fanfare for.
                    if celebratesReset, window.kind.celebratesReset {
                        produced.append(UsageAlert(account: account, kind: .celebration, window: window))
                    }
                    memory.announced = 0
                    memory.pendingReset = false
                    memory.fraction = window.usedFraction
                    memory.resetsAt = window.resetsAt
                } else if emptied {
                    // Hold the *pre-drop* baseline so a rebound is compared
                    // against the high figure, not against the glitch.
                    memory.pendingReset = true
                } else {
                    memory.pendingReset = false
                    memory.fraction = window.usedFraction
                    memory.resetsAt = window.resetsAt
                }
            } else {
                memory.fraction = window.usedFraction
                memory.resetsAt = window.resetsAt
            }

            if threshold != .off,
               let step = Self.step(for: window, threshold: threshold),
               step > memory.announced {
                memory.announced = step
                produced.append(
                    UsageAlert(
                        account: account,
                        kind: step >= 100 ? .spent : .approaching(percent: step),
                        window: window
                    )
                )
            }

            record.windows[window.id] = memory
        }

        accounts[account.id] = record
        return produced
    }

    /// The highest step this window has reached: the chosen threshold, 100, or
    /// neither.
    ///
    /// **100 is the provider's word, not arithmetic.** `isExhausted` is what
    /// the provider reports; the fraction is only allowed to reach 100 by
    /// rounding *down*, so 99.6% stays 99. Pulse saying "spent" about a limit
    /// that still has something in it is the same invention as a made-up
    /// percentage, told at the worst possible moment.
    private static func step(for window: UsageWindow, threshold: AlertThreshold) -> Int? {
        // A balance reaching 100% is arithmetic against a denominator that is
        // Pulse's own observation or the reader's own typed figure — never
        // DeepSeek's. `is_available` is the only thing that may say an account
        // is spent, which is what the provider's own doc promises, and this is
        // where that promise is kept: a ¥100 full-tank with the balance at zero
        // announced "This limit is spent" while the account could still pay.
        let reached = window.isExhausted
            ? 100
            : (window.kind == .balance ? min(99, Int((window.usedFraction * 100).rounded(.down)))
                                       : Int((window.usedFraction * 100).rounded(.down)))
        if reached >= 100 { return 100 }
        if let percent = threshold.percent, reached >= percent { return percent }
        return nil
    }

    /// What a reading with no figures in it does to a run of failures.
    ///
    /// **Three outcomes, not two.** Splitting only into "counts" and "doesn't"
    /// left a *successful* answer — the provider replied and has no limits to
    /// report — neither counting nor clearing, so it could sit in the middle of
    /// a run of real failures without breaking it, and could leave
    /// `reportedFailure` stuck true so the next genuine outage said nothing.
    enum Standing {
        /// Something that was working has stopped.
        case failure
        /// The provider answered. Whatever else is true, it can be reached.
        case answered
        /// Neither: a setup step nobody has taken, or an app that is not open.
        /// True until somebody acts, so it is not news — and not evidence
        /// about whether the provider can be reached either.
        case neutral
    }

    /// The question is "did something that was working stop", not "is there
    /// anything to show".
    static func standing(of reason: ProviderUsage.Unavailability) -> Standing {
        switch reason {
        case .claudeLoginExpired, .claudeDesktopKeyRefused, .claudeDesktopSessionExpired,
             .cursorLoginExpired, .grokLoginExpired, .kimiLoginExpired, .signedOut, .apiKeyRefused,
             .ollamaSessionExpired, .ollamaPageChanged, .qoderSessionExpired,
             .unreachable, .unreadableReply, .rateLimited, .serverError,
             .codexServerFailed:
            .failure

        // The provider replied. "No limits on this plan" and "your Cursor plan
        // doesn't include Grok Bot" are complete answers, and an answer ends
        // an outage as surely as a figure does.
        case .noLimitsReported, .grokBotNotIncluded,
             // Same shape: a key that authenticated, an envelope that parsed,
             // and a complete answer in it. Classed neutral it cleared
             // nothing, so an earlier outage's `reportedFailure` stayed true
             // for the life of the record and the *next* real outage said
             // nothing — the exact failure the three-way split exists to
             // prevent.
             .zaiNoCodingPlan:
            .answered

        // Never set up, never signed in, or an app that simply is not
        // running. All of them true until somebody does something, and none
        // of them worth a banner on a timer.
        case .loading, .notConnected, .awaitingResponse,
             .signInRequired, .claudeSignInRequired, .claudeDesktopNotSignedIn,
             .codexNotInstalled, .antigravityNotRunning, .antigravityNotAnswering,
             .cursorSignInRequired, .grokSignInRequired, .kimiSignInRequired, .notSignedIn,
             .ollamaSessionMissing, .qoderSessionMissing, .apiKeyMissing, .volcengineCLIMissing,
             .volcengineSignInRequired:
            .neutral
        }
    }
}

/// Turns readings into notifications, and remembers what it has already said.
///
/// **Nothing is posted unless the user asked for it**, and the three
/// notification switches are separate because the three things are: a limit
/// filling up is a plan for the afternoon, a limit coming back is permission
/// to start again, and a reading that stopped arriving is a fault. Someone
/// can want any one of them without the others. Ribbons are a fourth switch
/// and not a notification.
///
/// Every one of them asks for the **default sound**, and the mute switch is
/// macOS's own per-app "Play sound for notifications".
///
/// This was silent first, on the reasoning that Pulse spends its whole day at
/// the edge of the screen not asking for attention — with a note in the
/// changelog saying to add a sound in System Settings if you wanted one. That
/// note was **wrong**, and wrong in the direction that matters: a notification
/// with no `sound` is delivered silently and the system switch cannot put one
/// back, it can only take away one the app asked for. So the choice was never
/// between quiet and loud; it was between a working off switch in the place
/// people look for it, and no switch at all.
///
/// A banner nobody hears is also the wrong default for these four in
/// particular. Every one of them is something you would want to know *while
/// looking at something else* — that is the test for being here rather than on
/// the card — and a silent banner on a second display, or behind a full-screen
/// window, is a message that was never delivered.
///
/// One rule for all four rather than sound for the consequential two: macOS
/// offers one switch per app, so a distinction Pulse drew here would be one
/// nobody could turn off, and one nobody could discover either.
@MainActor
@Observable
final class UsageAlerts {
    /// Whether notifications can be posted at all.
    ///
    /// `UNUserNotificationCenter.current()` does not fail politely without an
    /// app bundle — it raises, and takes the process with it. A `swift run`
    /// build is a bare executable, which is the normal way to work on this
    /// app, so every entry point here is fenced by this and the settings pane
    /// says why the switches do nothing.
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    /// What the system says, rather than what was asked for. A grant can be
    /// withdrawn in System Settings long after it was given, and a switch that
    /// is on while macOS is dropping everything Pulse posts is a lie.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let settings: AppSettings
    // Read-only outside this type so tests can verify no warning is consumed during authorization.
    private(set) var memory: AlertMemory
    private var tapHandler: NotificationTapHandler?
    private var authorizationRequest: Task<Bool, Never>?
    private let memoryFile: URL

    private static var file: URL {
        PulseStorage.directory.appending(path: "alerts.json")
    }

    init(settings: AppSettings, file: URL = UsageAlerts.file) {
        self.settings = settings
        memoryFile = file
        memory = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode(AlertMemory.self, from: $0) } ?? AlertMemory()
    }

    /// Wires up what happens when one is clicked, and reads the current grant.
    /// Called once at launch — asking for permission is not done here, because
    /// a permission dialog at launch for a feature nobody has switched on is
    /// how an app gets denied for good.
    func start(openSettings: @escaping @MainActor () -> Void) {
        guard Self.isSupported else { return }

        let handler = NotificationTapHandler(open: openSettings)
        tapHandler = handler
        UNUserNotificationCenter.current().delegate = handler

        Task { await readAuthorization() }
    }

    /// Re-reads the grant. Called when the settings window opens, because that
    /// is the only place `authorization` is shown and it can have been
    /// withdrawn in System Settings at any point since launch.
    ///
    /// Without this the subtitle was read once at launch and never again — so
    /// the row confidently said alerts were on while macOS dropped every one,
    /// which is verbatim the failure the property exists to report.
    func refreshAuthorization() {
        guard Self.isSupported else { return }
        Task { await readAuthorization() }
    }

    /// Asks, if anything is switched on and nobody has been asked yet. Called
    /// from the settings pane the moment a switch goes on, which is the one
    /// place the dialog is expected.
    func requestAuthorizationIfNeeded() async -> Bool {
        guard Self.isSupported else { return false }
        return await requestAuthorizationIfNeeded {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            await self.readAuthorization()
            return granted
        }
    }

    /// Injectable authorization operation: tests never contact the system centre.
    func requestAuthorizationIfNeeded(using request: @escaping @MainActor () async -> Bool) async -> Bool {
        guard settings.wantsAlerts else { return false }
        if let authorizationRequest {
            return await authorizationRequest.value && settings.wantsAlerts
        }
        let pending = Task { await request() }
        authorizationRequest = pending
        let granted = await pending.value
        authorizationRequest = nil
        return granted && settings.wantsAlerts
    }

    /// A reading has landed. Decide what it is worth saying, and say it.
    ///
    /// `raw` is what the provider's service actually returned, before
    /// `UsageCache.reconciled` swapped a failure for the last good figures.
    /// The panel needs the reconciled one; the rules need both.
    func observe(_ reading: ProviderUsage, raw: ProviderUsage, as account: AccountKey) {
        // Nothing switched on means no work and, more to the point, **no
        // file**: without this the memory was written on the first pass of
        // every launch — measured — and a run of failures was counted up for a
        // feature nobody had turned on. Ribbons keep the same file: they need
        // the previous fraction to know a reset happened.
        guard settings.wantsAlerts || settings.celebratesReset else { return }
        // Notices wait for a grant; ribbons do not. A permission dialog in
        // flight must still not consume a warning, so the notice half stays
        // out until that returns — and takes the ribbons with it for that
        // one pass, rather than mark a reset seen and then stay silent.
        if settings.wantsAlerts {
            guard authorizationRequest == nil,
                  !Self.isSupported || authorization != .notDetermined else { return }
        }

        let before = memory
        let alerts = memory.alerts(
            for: reading,
            raw: raw.state,
            as: account,
            threshold: settings.alertThreshold,
            announcesReset: settings.alertsOnReset,
            announcesFailure: settings.alertsOnFailure,
            celebratesReset: settings.celebratesReset,
            lowBalance: settings.lowBalanceAlert(for: account),
            staleMeansFailure: !settings.source(for: account).reportsOnlyWhenUsed(for: account),
            // The one clock reading in here, taken at the edge and passed in,
            // so the rules themselves stay decidable from their arguments.
            now: Date()
        )

        if memory != before { save() }
        playCelebrations(from: alerts)
        // The memory is kept up to date whether or not anything can be posted:
        // a build with no bundle, or a grant that was refused, must not come
        // back later and announce a fortnight of crossings it slept through.
        guard Self.isSupported else { return }
        for alert in alerts where alert.kind != .celebration {
            post(alert)
        }
    }

    /// One overlay per account per pass. Two of Qoder's bars turning over
    /// together is one piece of news, named Qoder, not two shows in a row.
    private func playCelebrations(from alerts: [UsageAlert]) {
        guard settings.celebratesReset else { return }
        var seen = Set<AccountKey>()
        for alert in alerts where alert.kind == .celebration {
            guard seen.insert(alert.account).inserted else { continue }
            ResetCelebration.shared.play(name: settings.label(for: alert.account))
        }
    }

    private func post(_ alert: UsageAlert) {
        let content = UNMutableNotificationContent()
        content.title = settings.label(for: alert.account)
        if let subtitle = subtitle(for: alert) { content.subtitle = subtitle }
        content.body = body(for: alert)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.identifier,
            content: content,
            // Now, not on a schedule.
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// The limit's own name, which is the second thing you need after knowing
    /// which account it is. An account-wide fault has no limit to name.
    private func subtitle(for alert: UsageAlert) -> String? {
        if case .unreadable = alert.kind { return .localized("Can't be read") }
        if case .lowBalance = alert.kind { return .localized("Balance") }
        return alert.window?.name
    }

    private func body(for alert: UsageAlert) -> String {
        switch alert.kind {
        case .unreadable(let reason):
            // The unavailable copy is already a localized sentence that says
            // what to do about it — which is exactly what this notification is
            // for. Nothing is gained by writing it a second time here.
            return reason?.message
                ?? .localized("The last few checks didn't get through, so the panel is showing older figures.")

        case .approaching:
            guard let window = alert.window else { return "" }
            let figure = window.percentText(remaining: settings.showsRemaining)
            let said: String = settings.showsRemaining
                ? .localized("\(figure) left.")
                : .localized("\(figure) used.")
            return Self.joined(said, Self.resetSentence(alert.window))

        case .lowBalance(let remaining):
            // The figure and nothing else. There is no window to say when it
            // comes back, because it does not come back on its own — this
            // provider's credit is bought, and the only thing that refills it
            // is the reader.
            return .localized("\(remaining) left.")

        case .spent:
            return Self.joined(.localized("This limit is spent."), Self.resetSentence(alert.window))

        case .reset, .celebration:
            return .localized("This limit has reset.")
        }
    }

    /// When it comes back, when the provider says.
    ///
    /// Nothing at all when it doesn't. A window's `windowSeconds` is sometimes
    /// only a sort key — see `UsageWindow.reportsLength` — so the fallback the
    /// card can use ("a 7-day limit") is not available here without printing a
    /// length nobody reported.
    private static func resetSentence(_ window: UsageWindow?) -> String {
        guard let resets = window?.resetsAt else { return "" }

        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }

    /// Two sentences, with a space only where one is wanted. A Chinese full
    /// stop is full-width and carries its own trailing space; adding another
    /// leaves a visible gap mid-line. Same rule as `glassSubtitle`.
    private static func joined(_ first: String, _ second: String) -> String {
        guard !second.isEmpty else { return first }
        guard !first.isEmpty else { return second }
        return first.hasSuffix("。") ? first + second : first + " " + second
    }

    private func readAuthorization() async {
        authorization = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    /// One serial queue, so two saves cannot land out of order and neither
    /// lands on the main thread.
    ///
    /// `observe` runs from `UsageStore.commit` for every account of every
    /// pass, and the memory changes whenever a figure moves — so this was an
    /// encode plus an atomic write (temp file, rename) on the UI thread
    /// several times a refresh. Small file, wrong thread.
    private static let disk = DispatchQueue(label: "Pulse.alerts", qos: .utility)

    private func save() {
        // Snapshot on the actor, write off it: `AlertMemory` is a value type,
        // so the queue gets bytes nobody else can be changing underneath it.
        // The path is snapshotted too — `file` is main-actor isolated with the
        // rest of this type, and reading it from the queue is the kind of
        // actor-isolation slip that is a warning here and an error in Xcode.
        let snapshot = memory
        let destination = memoryFile
        Self.disk.async {
            PulseStorage.prepare()
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}

/// Opens Settings when a notification is clicked.
///
/// Every one of these is about an account, and everything you can do about any
/// of them — change a route, sign in again, paste a key, switch the provider
/// off — is in that window. It opens on whichever pane was last shown rather
/// than the account's own: the pane is the view's own state, and reaching into
/// it from here would mean threading a selection through the window controller
/// for a feature that is one click away as it is.
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let open: @MainActor () -> Void

    init(open: @escaping @MainActor () -> Void) {
        self.open = open
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// The completion-handler form rather than the `async` one, deliberately.
    /// These are *optional* protocol requirements, so a signature that doesn't
    /// match the selector isn't an error — it is a method that is simply never
    /// called, and a click that does nothing looks exactly like a click that
    /// was never wired up. This spelling is the one the header declares.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let open = open
        let finish = UncheckedBox(completionHandler)
        Task { @MainActor in
            open()
            finish.value()
        }
    }
}


/// Carries a completion handler across to the main actor.
///
/// AppKit hands these out without a `@Sendable` on them, and the alternative —
/// calling it on whichever thread the notification centre used — is worse than
/// vouching for a closure whose whole job is to be called exactly once.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) { self.value = value }
}
