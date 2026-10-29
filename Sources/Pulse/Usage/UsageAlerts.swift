// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
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
        var cycleID: String?
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
    /// the reading, the memory, and the three settings; nothing here reads the
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
        guard case .live = rawState, case .live = reading.state, threshold != .off,
              let observedAt = reading.observedAt,
              now.timeIntervalSince(observedAt) <= UsageCache.maximumAge else {
            accounts[account.id] = record
            return produced
        }

        for window in reading.current(at: now)?.windows ?? [] {
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

            if let cycle = window.cycleID, let previous = seen?.cycleID, cycle != previous {
                memory.announced = 0
            } else if let seen {
                // Said only when the evidence is unambiguous — the rule, and
                // why it is that rule, live on `UsageWindow.hasTurnedOver`.
                // The rail's mark asks the same question of the same code.
                let unambiguous = window.hasTurnedOver(since: seen.fraction,
                                                       resetsAt: seen.resetsAt)
                // **The step is cleared by the same evidence that would
                // announce, not by the drop alone.** Clearing on any 5-point
                // dip re-armed a window that had not reset: a rolling weekly
                // allowance oscillating across the line — 95%, 89%, 93% — was
                // announced at 95, said nothing at 89, and then announced
                // again at 93, for as long as it wobbled. "At most one
                // notification per limit" was written on the tin and was not
                // what it did.
                if unambiguous {
                    // And only for a limit that was worth mentioning on the way
                    // up. "Your 5-hour window reset" about a window that never
                    // got past 12% is a notification about nothing.
                    if announcesReset, seen.announced > 0 {
                        produced.append(UsageAlert(account: account, kind: .reset, window: window))
                    }
                    memory.announced = 0
                }
            }

            if let step = Self.step(for: window, threshold: threshold), step > memory.announced {
                memory.announced = step
                produced.append(
                    UsageAlert(
                        account: account,
                        kind: step >= 100 ? .spent : .approaching(percent: step),
                        window: window
                    )
                )
            }

            memory.fraction = window.usedFraction
            memory.resetsAt = window.resetsAt
            if let cycle = window.cycleID { memory.cycleID = cycle }
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
        // A top-up pack joins the balance here for the same reason: it is
        // prepaid rather than granted, its fraction moves when a pack is
        // bought, and nothing but the provider's own word may call it spent.
        let reached = window.isExhausted
            ? 100
            : (window.kind == .balance || window.kind == .topUp
                ? min(99, Int((window.usedFraction * 100).rounded(.down)))
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
             .cursorLoginExpired, .cursorKeyRefused, .grokLoginExpired, .signedOut, .apiKeyRefused,
             .ollamaSessionExpired, .ollamaPageChanged, .xiaomiSessionExpired,
             .qoderSessionExpired, .stepFunSessionExpired,
             .unreachable, .unreadableReply, .rateLimited, .serverError,
             .codexServerFailed,
             // An extension that answered before and has stopped: the same
             // news as any route going down.
             .extensionTimedOut, .extensionFailed, .extensionSignedOut,
             // A credential that worked and has stopped.
             .sessionExpired, .localLoginExpired:
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
             .zaiNoCodingPlan,
             // And the same again for Xiaomi: the session worked and the
             // account simply has no plan on it.
             .xiaomiNoCodingPlan,
             // And for Qoder: the session worked and the account holds no
             // credits. An answer, not an outage. StepFun's no-plan likewise.
             .qoderNoCredits, .stepFunNoPlan,
             .noPlan:
            .answered

        // Never set up, never signed in, or an app that simply is not
        // running. All of them true until somebody does something, and none
        // of them worth a banner on a timer.
        case .loading, .notConnected, .awaitingResponse,
             .signInRequired, .claudeSignInRequired, .claudeDesktopNotSignedIn,
             .codexNotInstalled, .kiroNotInstalled, .kiroVersionUnsupported,
             .kiroSignInRequired, .antigravityNotRunning, .antigravityNotAnswering,
             .cursorSignInRequired, .grokSignInRequired, .notSignedIn,
             .ollamaSessionMissing, .xiaomiSessionMissing, .qoderSessionMissing, .stepFunSessionMissing,
             .apiKeyMissing, .volcengineCLIMissing, .antigravityCLIMissing, .antigravityCLIOutdated,
             .volcengineSignInRequired,
             // A program taken out of its folder is a setup change somebody
             // made, not an outage.
             .extensionMissing,
             // "System Proxy Only" holding back because the proxy app was
             // quit: Pulse chose not to ask, so nothing about the provider is
             // known, and every account announcing an outage at once would
             // be a notification about a switch.
             .systemProxyOff,
             // Nothing set up yet, for a profiled provider.
             .sessionMissing, .localLoginMissing, .localAppMissing,
             // An app that was never installed or never signed in, which is
             // the same standing as a CLI that is not there: true until
             // somebody does something, and not an outage to announce.
             .devinAppMissing, .devinPlanUnread, .devinOrganizationMissing,
             // A self-hosted service with no address yet, or one whose address
             // Pulse will not send a key to. Both are setup steps nobody has
             // finished, and neither is evidence about whether anything can be
             // reached — nothing was ever asked.
             .serverAddressMissing, .serverAddressRefused:
            .neutral
        }
    }
}

/// Turns readings into notifications, and remembers what it has already said.
///
/// **Nothing is posted unless the user asked for it**, and the three switches
/// are separate because the three things are: a limit filling up is a plan for
/// the afternoon, a limit coming back is permission to start again, and a
/// reading that stopped arriving is a fault. Someone can want any one of them
/// without the others.
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
/// One rule for all of them rather than sound for the consequential ones: macOS
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
    private(set) var outages: OutageMemory
    private var tapHandler: NotificationTapHandler?
    private var authorizationRequest: Task<Bool, Never>?
    private var outageCheck: Task<Void, Never>?
    private var outageTimer: Task<Void, Never>?
    private let memoryFile: URL
    private let outageFile: URL

    private static var file: URL {
        PulseStorage.directory.appending(path: "alerts.json")
    }

    private static var outagesFile: URL {
        PulseStorage.directory.appending(path: "status-alerts.json")
    }

    init(settings: AppSettings, file: URL = UsageAlerts.file, outageFile: URL = UsageAlerts.outagesFile) {
        self.settings = settings
        memoryFile = file
        self.outageFile = outageFile
        memory = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode(AlertMemory.self, from: $0) } ?? AlertMemory()
        outages = (try? Data(contentsOf: outageFile))
            .flatMap { try? JSONDecoder().decode(OutageMemory.self, from: $0) } ?? OutageMemory()
    }

    /// Wires up what happens when one is clicked, and reads the current grant.
    /// Called once at launch — asking for permission is not done here, because
    /// a permission dialog at launch for a feature nobody has switched on is
    /// how an app gets denied for good.
    func start(
        openSettings: @escaping @MainActor () -> Void,
        openRecap: @escaping @MainActor (Recap.Period) -> Void = { _ in }
    ) {
        guard Self.isSupported else { return }

        let handler = NotificationTapHandler(open: openSettings, openRecap: openRecap)
        tapHandler = handler
        UNUserNotificationCenter.current().delegate = handler

        // The grant first: `checkServices` does nothing while it is unknown, so
        // a first tick ahead of it was a wasted one, and an outage already
        // under way at launch waited five minutes to be said.
        //
        // Then its own clock rather than the refresh pass's, which stretches to
        // half an hour while the Mac sits idle — the moment someone comes back
        // to work is when an outage matters most. Each tick returns at once
        // unless the switch is on and a provider with a page is in use. The
        // sleep is on the continuous clock, so a tick due while the Mac slept
        // comes right after it wakes.
        outageTimer = Task { [weak self] in
            await self?.readAuthorization()
            while !Task.isCancelled {
                self?.checkServices()
                try? await Task.sleep(for: ServiceStatus.checkInterval)
            }
        }
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

    /// What sending a test notification came to.
    enum TestOutcome: Equatable {
        case sent
        /// macOS will not show Pulse's notifications: refused at the prompt,
        /// or turned off in System Settings since.
        case denied
        /// The permission prompt was closed without an answer; pressing
        /// again asks again.
        case undecided
        /// No app bundle (`isSupported`).
        case unsupported
    }

    /// Posts one notification now, on request, so the reader can see that
    /// notifications reach them and how they look.
    ///
    /// **Asks for permission whatever is switched on**, unlike
    /// `requestAuthorizationIfNeeded`: pressing the button is the request.
    /// Not a usage alert and remembered nowhere — the one notification that
    /// is about nothing Pulse saw, because the reader asked for exactly that,
    /// and it says so.
    func sendTest() async -> TestOutcome {
        guard Self.isSupported else { return .unsupported }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        await readAuthorization()
        if authorization == .notDetermined { return .undecided }
        guard authorization == .authorized || authorization == .provisional else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = "Pulse"
        content.body = .localized("This is a test notification. Pulse's notifications look like this.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pulse.test", content: content, trigger: nil)
        do {
            try await center.add(request)
            return .sent
        } catch {
            return .denied
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

    /// Whether a `.stale` reading should count against this account.
    ///
    /// False for a **push route** — Claude Code's status line only writes while
    /// a session runs — and false for a reading out of an app's own saved state
    /// (`UsageRoute.appCache`). Devin's figures are written when its app
    /// launches and not again while it runs, so an old reading means nobody has
    /// relaunched it, not that a check failed. Counting that would post "the
    /// last few checks didn't get through" over a route where every check got
    /// through — the one thing these rules exist to prevent.
    ///
    /// `nonisolated static` and pure, so a test can pin the rule directly.
    nonisolated static func staleMeansFailure(
        route: UsageSource,
        raw: ProviderUsage,
        for account: AccountKey
    ) -> Bool {
        !route.reportsOnlyWhenUsed(for: account) && raw.origin != .appCache
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
        // feature nobody had turned on.
        guard settings.wantsUsageAlerts, authorizationRequest == nil,
              !Self.isSupported || authorization != .notDetermined else { return }

        let before = memory
        let alerts = memory.alerts(
            for: reading,
            raw: raw.state,
            as: account,
            threshold: settings.alertThreshold,
            announcesReset: settings.alertsOnReset,
            announcesFailure: settings.alertsOnFailure,
            lowBalance: settings.lowBalanceAlert(for: account),
            staleMeansFailure: Self.staleMeansFailure(
                route: settings.source(for: account), raw: raw, for: account
            ),
            // The one clock reading in here, taken at the edge and passed in,
            // so the rules themselves stay decidable from their arguments.
            now: Date()
        )

        if memory != before { save() }
        // The memory is kept up to date whether or not anything can be posted:
        // a build with no bundle, or a grant that was refused, must not come
        // back later and announce a fortnight of crossings it slept through.
        guard Self.isSupported, !alerts.isEmpty else { return }

        for alert in alerts { post(alert) }
    }

    /// Asks the status pages of the providers in use whether their service is
    /// down, and says so (`OutageMemory`). Called every `checkInterval` and
    /// when the setting is switched; one check at a time, its pages at once.
    ///
    /// **Only providers switched on**: a disabled one is not fetched, and a
    /// page that can't be read changes nothing. What is no longer watched —
    /// the switch off, a provider off — is forgotten here.
    func checkServices() {
        guard settings.alertsOnOutage else {
            forgetOutages(except: [])
            return
        }
        let pages = Array(Set(settings.shownAccounts.map(\.provider)))
            .compactMap(settings.statusPage(for:))
            .sorted { $0.id < $1.id }
        forgetOutages(except: Set(pages))
        guard outageCheck == nil, authorizationRequest == nil,
              !Self.isSupported || authorization != .notDetermined else { return }
        guard !pages.isEmpty else { return }
        // A company's page read once for every provider on it.
        let feeds = Set(pages.map(\.feed))

        outageCheck = Task {
            let read = await withTaskGroup(of: (StatusFeed, [ServiceStatus.Component]?).self) { group in
                for feed in feeds {
                    group.addTask { (feed, await ServiceStatus.current(feed)) }
                }
                var read: [StatusFeed: [ServiceStatus.Component]] = [:]
                for await (feed, components) in group { read[feed] = components }
                return read
            }
            for page in pages {
                guard let components = read[page.feed] else { continue }
                consider(components.filter(page.notifiesAbout), from: page)
            }
            outageCheck = nil
        }
    }

    private func forgetOutages(except pages: Set<StatusPage>) {
        var kept = outages
        kept.keepOnly(pages)
        guard kept != outages else { return }
        outages = kept
        Self.persist(outages, to: outageFile)
    }

    private func consider(_ components: [ServiceStatus.Component], from page: StatusPage) {
        // Switched off while the page was being read.
        guard settings.alertsOnOutage else { return }
        let before = outages
        let change = outages.changes(in: components, on: page)
        if outages != before { Self.persist(outages, to: outageFile) }
        // Kept up to date whether or not anything can be posted, for the same
        // reason the limits' memory is.
        guard Self.isSupported, !change.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = page.provider.displayName
        content.subtitle = .localized("Service status")
        // A status, not an event: true whenever it is read.
        let down = change.worse.isEmpty ? "" : String.localized("\(page.company) reports \(Self.list(change.worse, states: true)).")
        let back = change.recovered.isEmpty ? "" : String.localized("Back to normal: \(Self.list(change.recovered, states: false)).")
        content.body = Self.joined(down, back)
        content.sound = .default

        // One per provider: a newer word on the same service replaces the last.
        let request = UNNotificationRequest(
            identifier: "service-status-\(page.provider.rawValue)",
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// "CLI (Partial outage) and Codex API (Degraded performance)", in the
    /// interface language's own way of listing.
    private static func list(_ components: [ServiceStatus.Component], states: Bool) -> String {
        let items = components.map { component in
            states ? String.localized("\(component.name) (\(component.state.title))") : component.name
        }
        let formatter = ListFormatter()
        formatter.locale = LocalizationSource.locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
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

        case .reset:
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
    /// leaves a visible gap mid-line.
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
        Self.persist(memory, to: memoryFile)
    }

    /// Snapshot on the actor, write off it: both memories are value types, so
    /// the queue gets bytes nobody else can be changing underneath it. The
    /// path is passed in too — the files are main-actor isolated with the rest
    /// of this type, and reading one from the queue is the kind of
    /// actor-isolation slip that is a warning here and an error in Xcode.
    private static func persist<Value: Encodable & Sendable>(_ snapshot: Value, to destination: URL) {
        disk.async {
            PulseStorage.prepare()
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}

/// Opens Settings when a notification is clicked — and the recap window when
/// it is the recap's.
///
/// Every one of the others is about an account, and everything you can do about
/// any of them — change a route, sign in again, paste a key, switch the provider
/// off — is in that window. It opens on whichever pane was last shown rather
/// than the account's own: the pane is the view's own state, and reaching into
/// it from here would mean threading a selection through the window controller
/// for a feature that is one click away as it is.
///
/// The recap's identifier carries its month (`RecapNoticeRule`), so a click
/// opens the recap on that month.
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let open: @MainActor () -> Void
    private let openRecap: @MainActor (Recap.Period) -> Void

    init(
        open: @escaping @MainActor () -> Void,
        openRecap: @escaping @MainActor (Recap.Period) -> Void = { _ in }
    ) {
        self.open = open
        self.openRecap = openRecap
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
        let openRecap = openRecap
        let recap = RecapNoticeRule.period(fromIdentifier: response.notification.request.identifier)
        let finish = UncheckedBox(completionHandler)
        Task { @MainActor in
            if let recap { openRecap(recap) } else { open() }
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
