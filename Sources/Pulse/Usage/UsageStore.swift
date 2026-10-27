// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Observation

/// Holds the current usage for every provider and keeps it refreshed.
///
/// Providers are fetched in as many different ways as there are providers —
/// most are asked over the network, Claude Code can be read from whatever its
/// status line last handed us, and others go through a CLI, a local app's
/// cache or a browser session — so each is refreshed on its own terms rather
/// than on one shared clock.
///
/// The loop itself reschedules after every pass rather than repeating on a
/// fixed timer, because on `.automatic` the wait is worked out afresh each
/// time from what `AdaptiveRefresh` can see.
@MainActor
@Observable
final class UsageStore {
    /// Keyed by account id rather than by provider: one of them can be signed
    /// in to more than once, and a reading belongs to the account it came from.
    private(set) var usage: [String: ProviderUsage] = [:]
    private(set) var diagnostics: [String: ConnectionDiagnostic] = [:]
    private(set) var isRefreshing = false
    /// Nil while an automatic refresh is fetching every provider; otherwise
    /// the one provider the user explicitly asked to refresh from its ring.
    private var refreshingAccount: AccountKey?

    /// What the automatic interval currently works out to, so settings can
    /// show it rather than leaving it a black box.
    private(set) var currentInterval: TimeInterval = AdaptiveRefresh.floor

    private let settings: AppSettings
    private var networkProxy: NetworkProxySettings
    /// Each site-setting provider's site as last seen (`AppSettings.site(of:)`).
    private var sites: [Provider: String]
    /// Posts notifications about the readings that land here. Nil in previews,
    /// which have no bundle to post from and nothing to say anyway.
    private let alerts: UsageAlerts?
    private let appServer = CodexAppServer()
    /// The one way a provider is asked, for the full pass and the per-account
    /// refresh alike. Production talks to the real providers; a test hands in
    /// a fake and drives the scheduling without any network.
    private let services: any UsageServiceFactory
    /// Where fetched readings are reconciled and banked. Injectable so a test
    /// writes a scratch file rather than the one the running app depends on.
    private let cache: UsageCache
    /// The store's clock, for the pass watchdog and the per-provider pacing.
    private let clock: () -> Date
    /// The loop's one timer. Readable so a test can see that it is a one-shot.
    private(set) var timer: Timer?
    /// Kept with the centre each was registered on: workspace notifications
    /// don't come from the default centre, and removing them there does
    /// nothing at all.
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// Keys read once per launch rather than once per refresh pass.
    private var apiKeys: [Provider: String] = [:]
    /// A provider asked for while another pass was in flight.
    ///
    /// The guard that stops two passes overlapping used to drop these on the
    /// floor: saving a key during the launch pass, or pressing Refresh while
    /// anything else was running, did nothing at all — and the pass already
    /// running had read the old key before it started, so it published the
    /// missing-key answer and slept for up to half an hour.
    private var queued: Set<AccountKey> = []
    /// A whole pass asked for while one was running.
    private var queuedFullPass = false
    /// When the pass in flight began, so one that never returns can be
    /// noticed rather than blocking every later attempt for ever.
    private var refreshStartedAt: Date?
    /// Which pass is the current one.
    ///
    /// **Releasing the guard is not the same as ending the pass.** A pass given
    /// up on is never told so: it is still awaiting its requests, and when they
    /// finally answer it writes its readings into `usage` and clears the flags
    /// — which by then belong to a *different* pass. Measured: a ring clicked
    /// during a stall showed 90%, and six seconds later the abandoned pass put
    /// 5% back, undoing the one refresh the user asked for by hand. Every write
    /// checks this first, so a ghost finishes silently.
    private var generation = 0
    private var currentPass = 0
    /// When hovering last forced a refresh, and how long before it may again.
    private var lastLookRefresh: Date?
    private static let lookCooldown: TimeInterval = 30

    private var signals = AdaptiveRefresh.Signals()
    /// When each account was last **asked**, not when it last answered.
    ///
    /// Asked, because this paces requests: one that failed still spent the
    /// request, and one that never commits — a provider refusing every time —
    /// would otherwise read as permanently due and spin the loop.
    private var askedAt: [String: Date] = [:]
    private var screensAsleep = false

    /// Whether either CLI is working right now. Its own clock — see
    /// `AgentActivityMonitor`.
    let activity: AgentActivityMonitor
    /// Watches live readings for a limit turning over, so the rail's mark can
    /// celebrate one. Independent of the alert rules; see `ResetWatch`.
    private let resetWatch = ResetWatch()
    /// Whether a limit is being spent where this Mac's logs cannot see, which
    /// takes the value estimate off it. The app's own; previews and tests
    /// pass none, so they neither read the real transcripts nor write the file.
    let elsewhere: ElsewhereWatch?

    /// - Parameters:
    ///   - services: how an account is asked. Nil is the real providers.
    ///   - cache: where readings are reconciled and banked.
    ///   - clock: the time the pass watchdog and the pacing are measured by.
    init(settings: AppSettings, alerts: UsageAlerts? = nil, activity: AgentActivityMonitor = AgentActivityMonitor(),
         elsewhere: ElsewhereWatch? = nil, services: (any UsageServiceFactory)? = nil,
         cache: UsageCache = .shared, clock: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.activity = activity
        self.elsewhere = elsewhere
        networkProxy = settings.networkProxy
        sites = Self.sites(in: settings)
        self.alerts = alerts
        self.services = services ?? LiveUsageServices(settings: settings, appServer: appServer)
        self.cache = cache
        self.clock = clock

        for account in settings.allAccounts {
            usage[account.id] = Self.initialState(for: account)
        }
    }

    /// What an account shows before anything has been fetched for it.
    ///
    /// **Not always "loading".** A provider that needs a credential Pulse
    /// hasn't got is not loading and never will be: nothing is queued for it,
    /// and if it is switched off nothing ever will be. Seeded as `.loading` it
    /// sat in its own settings pane reading "Reading…" for ever, which is both
    /// untrue and the opposite of the one instruction that would help.
    private static func initialState(for account: AccountKey) -> ProviderUsage {
        // `keepsOwnCredential`, not `usesAPIKey`: the question is whether Pulse
        // holds something for this provider, not whether the user pastes it.
        // Asked the other way, Copilot's own pane read "Reading…" for ever —
        // which is the exact behaviour this function exists to prevent.
        // A placeholder must not probe keys. This store also exists while the
        // chooser is open, and holds slots for providers that were not chosen.
        guard account.isPrimary, account.provider.keepsOwnCredential
        else { return .unavailable(account, reason: .loading) }

        // And the remedy differs: a sign-in is not a key to paste.
        let reason: ProviderUsage.Unavailability = if account.provider == .copilot {
            .notSignedIn
        } else if account.provider.profile?.credential == .apiKey(optional: true) {
            // The field is a second way in; the first is a login this Mac may
            // already have, which only a fetch can find.
            .loading
        } else if account.provider.profile != nil, account.provider.readsBrowserStorage {
            .sessionMissing
        } else if account.provider.usesSessionCookie {
            .ollamaSessionMissing
        } else {
            .apiKeyMissing
        }
        return .unavailable(account, reason: reason)
    }

    /// How many limit reset credits Codex's first account has, for its card —
    /// nil while the switch is off or before the first answer. Asked beside
    /// every Codex refresh rather than inside it: it is a second call to a
    /// different route, and a slow app server must not hold the ring up.
    private(set) var codexResetCredits: CodexResetCredits?
    /// Which ask is the latest. Two can be in flight — a ring click right
    /// after a pass — and the one that answers last is not always the one
    /// asked last: an app server timing out after twenty seconds must not
    /// put "Not available" over the count a later ask already brought back.
    private var codexResetCreditsAsk = 0

    /// Internal so Settings can ask directly when the switch moves, rather
    /// than through `onChange`, which refetches every provider for what is
    /// one row on one card.
    func refreshCodexResetCredits() {
        codexResetCreditsAsk += 1
        let ask = codexResetCreditsAsk
        guard settings.showsCodexResetCredits, settings.isEnabled(AccountKey(.codex)) else {
            codexResetCredits = nil
            return
        }
        Task { [weak self, appServer] in
            let credits = await CodexAccountUsageService(server: appServer).resetCredits()
            guard let self, ask == self.codexResetCreditsAsk, self.settings.showsCodexResetCredits else { return }
            self.codexResetCredits = credits
        }
    }

    /// Codex's reset credits and account totals, which only its app server
    /// reports. Fetched when the settings pane asks rather than on the refresh
    /// loop: nothing on the rail shows them, and the call starts a process.
    func codexAccountUsage() async -> CodexAccountUsage? {
        guard settings.isEnabled(AccountKey(.codex)) else { return nil }
        return await CodexAccountUsageService(server: appServer).fetch()
    }

    /// Picks up a key that was just entered, or one that changed.
    func loadAPIKeys() {
        OpenCodeConsole.refreshSession()
        DeepSeekConsole.refreshSession()
        // Read the console's log ahead of being asked, so the first card is
        // not the one that waits half a minute for the month. Incremental and
        // shared with the card, so a warm-up that finds it fresh costs a page.
        if settings.isEnabled(AccountKey(.openCodeGo)),
           let cookie = APIKeyStore.key(for: .openCodeGo, slot: OpenCodeConsole.slot) {
            Task.detached(priority: .utility) { _ = await OpenCodeConsoleHistory.shared.ledger(cookie: cookie) }
        }
        if settings.isEnabled(AccountKey(.deepSeek)), let token = DeepSeekConsole.keptToken {
            let currency = settings.deepSeekCurrency
            Task.detached(priority: .utility) {
                _ = await DeepSeekConsoleHistory.shared.ledger(token: token, currency: currency)
            }
        }
        apiKeys = Dictionary(
            uniqueKeysWithValues: Provider.builtIn
                .filter { $0.keepsOwnCredential && settings.isEnabled(AccountKey($0)) }
                .compactMap { provider in
                    APIKeyStore.key(for: provider, slot: settings.keySlot(for: provider)).map { (provider, $0) }
                }
        )

        // Entering or clearing a key changes what a provider *can* report, and
        // one that still has nothing to show should say which of the two it is
        // rather than going on claiming to be loading. Only a placeholder is
        // rewritten — a reading that has actually been taken is left alone.
        for provider in Provider.builtIn where provider.keepsOwnCredential {
            let account = AccountKey(provider)
            guard case .unavailable(let reason) = usage[account.id]?.state,
                  [.loading, .apiKeyMissing, .ollamaSessionMissing, .sessionMissing, .apiKeyRefused,
                   .signedOut, .notSignedIn]
                    .contains(reason)
            else { continue }
            usage[account.id] = Self.initialState(for: account)
        }
    }

    /// Whether a provider's CLI is working at this moment.
    func isRunning(_ provider: Provider) -> Bool { activity.running.contains(provider) }

    /// Whether this provider's CLI finished a turn just now.
    ///
    /// The rail's mark celebrates a finished turn. Six seconds is long enough
    /// for the celebration to start on the next frame and short enough that
    /// reopening the panel a minute later does not replay it.
    func justFinishedWorking(_ provider: Provider, within span: TimeInterval = 6,
                             now: Date = Date()) -> Bool {
        guard let at = activity.finishedAt[provider] else { return false }
        return now.timeIntervalSince(at) >= 0 && now.timeIntervalSince(at) <= span
    }

    /// Whether this account's limit turned over just now. See `ResetWatch`.
    func justReset(_ account: AccountKey, now: Date = Date()) -> Bool {
        resetWatch.justReset(account, now: now)
    }

    /// Whether this provider is being refreshed explicitly from its ring.
    /// Automatic background passes stay silent on the rail.
    func isRefreshing(_ account: AccountKey) -> Bool {
        isRefreshing && refreshingAccount == account
    }

    func start() {
        guard !settings.needsProviderSelection, observers.isEmpty else { return }
        observe()
        loadAPIKeys()
        updateActivityMonitor()

        // Last time's numbers, on screen before the first request has even
        // gone out. They arrive marked stale, so the card says when they were
        // taken and a window that has since reset is dropped rather than aged
        // — nothing here is passed off as current. Without this every ring is
        // blank for as long as the slowest provider takes to answer, which on
        // a cold start is most of a second and looks like an app that has not
        // finished loading.
        // **Restored before the first request goes out, not alongside it.**
        // The guard below only knows whether a slot is still unavailable, and
        // an unavailable slot is not always an empty one: a pass that has
        // already landed `.apiKeyMissing` or `.signedOut` is a real answer —
        // the one answer the user has to be told — and a cache entry arriving
        // a moment later put yesterday's percentages over it. Racing was never
        // worth anything here: this is a disk read, and the requests it was
        // running beside take a round trip.
        Task { [accounts = settings.shownAccounts] in
            for account in accounts {
                guard let cached = await self.cache.lastReading(for: account) else { continue }
                // Nothing has been fetched yet, so anything but the seeded
                // placeholder would be a reading — and there cannot be one.
                guard case .unavailable = self.usage(for: account).state else { continue }
                self.usage[account.id] = cached
            }

            self.refresh()
        }

        // Only relevant when the app server is being used as a fallback; it
        // pushes when limits change, which saves waiting for the next tick.
        Task { [appServer, self] in
            await appServer.setRateLimitsChangedHandler { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// The user hovered the rail to read a card, which is the clearest sign
    /// they want these numbers to be current.
    func noteLooked() {
        signals.lastLooked = clock()

        // A rail is crossed ring by ring, so this is called several times a
        // second. Asking once is the point; asking once per ring is a storm.
        let asked = lastLookRefresh.map { clock().timeIntervalSince($0) < Self.lookCooldown } ?? false

        // Reading a stale card is the moment a slow cadence is most obviously
        // wrong, so this asks straight away rather than tightening the loop
        // and waiting for it.
        //
        // **Or when the loop has plainly stopped.** The timer is the only
        // thing that keeps it going, and a background app's timer is not a
        // promise — the system can nap it, and a pass that never returned
        // takes the schedule with it. Whatever the cause, a reading far older
        // than the cadence that was chosen for it is the evidence, and the
        // pointer arriving is the cheapest place to act on it.
        if !asked, currentInterval > AdaptiveRefresh.floor || isOverdue {
            lastLookRefresh = clock()
            refresh()
        } else {
            scheduleNext()
        }
    }

    /// How long this provider may be left between asks.
    ///
    /// A fixed interval chosen in Settings applies to everything equally —
    /// somebody who picked five minutes meant five minutes. Only `.automatic`
    /// paces providers differently, and only ever to ask sooner.
    private func interval(for provider: Provider) -> TimeInterval {
        settings.refreshInterval.seconds
            ?? AdaptiveRefresh.interval(for: signals, isWatched: provider.spendingIsWatchedLocally)
    }

    /// Whether the newest reading is older than the loop's own cadence allows.
    ///
    /// Twice the interval plus a minute: one missed tick is a slow network,
    /// two is a loop that has stopped.
    private var isOverdue: Bool {
        // **Never read is not overdue.** An unavailable reading carries no
        // `observedAt`, so a Mac where nothing is configured — or where every
        // enabled provider is refusing, which includes one refusing *because*
        // it is rate limiting — answered yes for ever. `noteLooked` runs on
        // every ring the pointer crosses, so sweeping the rail sent one request
        // per ring: measured, thirteen calls for twelve rings. Every signal in
        // this loop may only make it wait *longer*.
        guard let newest = usage.values.compactMap(\.observedAt).max() else { return false }
        return clock().timeIntervalSince(newest) > currentInterval * 2 + 60
    }

    /// Re-reads settings that affect the loop itself, then refreshes.
    func settingsChanged() {
        guard !settings.needsProviderSelection else { return }
        let proxyChanged = networkProxy != settings.networkProxy
        networkProxy = settings.networkProxy
        // A provider whose site changed is reading another account now: what
        // is shown and kept for it is the other site's, and goes — from the
        // table and from disk, so neither the panel nor `--json` shows it.
        let now = Self.sites(in: settings)
        let moved = Set(now.keys.filter { now[$0] != sites[$0] })
        sites = now
        let stale = settings.shownAccounts.filter { moved.contains($0.provider) }
        for account in stale { usage[account.id] = .unavailable(account, reason: .loading) }
        loadAPIKeys()
        updateActivityMonitor()
        guard proxyChanged || !stale.isEmpty else {
            refresh()
            return
        }

        // The process inherits its environment only when it starts. Tear down
        // one already running before the full pass is queued, so its next call
        // is made by a child carrying the new proxy. A moved site's kept
        // reading goes first, so the pass cannot fall back to it.
        Task { [weak self, appServer, cache] in
            for account in stale { await cache.forget(account) }
            if proxyChanged { await appServer.shutDown() }
            self?.refresh()
        }
    }

    /// The site each provider with a site setting is on.
    private static func sites(in settings: AppSettings) -> [Provider: String] {
        [
            .minimax: settings.minimaxSite.rawValue,
            .qoder: settings.qoderSite.rawValue,
            .stepFun: settings.stepFunSite.rawValue,
        ]
    }

    /// Nothing shows the spinner while the panel is off screen or the display
    /// is asleep, so nothing needs watching either.
    /// Internal so tests can check selection without starting provider requests.
    func updateActivityMonitor() {
        if !settings.needsProviderSelection && settings.isPanelVisible && !screensAsleep {
            activity.start(providers: Set(settings.shownAccounts.map(\.provider)))
        } else {
            activity.stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activity.stop()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        Task { [appServer] in await appServer.shutDown() }
    }

    /// - Parameter dueOnly: leave every provider alone whose own cadence has
    ///   not come round yet. True only from the timer; see `providersToAsk`.
    func refresh(dueOnly: Bool = false) {
        guard !settings.needsProviderSelection else { return }
        if isRefreshing, let started = refreshStartedAt,
           clock().timeIntervalSince(started) > Self.passCeiling {
            // Whatever it was waiting for is not coming. Letting the next pass
            // through is the only thing that can restart the loop — and the
            // abandoned one is disowned here rather than merely unblocked, or
            // it comes back later and overwrites whatever has happened since.
            isRefreshing = false
            generation += 1
        }

        guard !isRefreshing else {
            // Dropped, this used to be — and `settingsChanged()` is its main
            // caller, so switching a provider on mid-pass left it on `.loading`
            // until the next tick, which can be half an hour away.
            queuedFullPass = true
            return
        }
        isRefreshing = true
        refreshStartedAt = clock()
        refreshingAccount = nil
        generation += 1
        currentPass = generation
        let pass = generation

        let previous = usage

        // Nothing is fetched for a provider that isn't on the rail: it would
        // spend someone else's request, and read a credential, for a figure
        // nobody is going to see.
        // **And only the ones that are due.** One timer still drives the loop,
        // but each provider has its own cadence under `.automatic`, so a pass
        // woken for DeepSeek must not drag sixteen other services along with
        // it. Everything not asked keeps the reading it already has: the
        // commit loop below is gated on this same set.
        let now = clock()
        let wanted = Self.providersToAsk(
            from: settings.shownAccounts,
            dueOnly: dueOnly,
            askedAt: askedAt,
            interval: { self.interval(for: $0) },
            now: now
        )
        for provider in wanted { askedAt[AccountKey(provider).id] = now }
        // Primary accounts are asked side by side in one group rather than
        // one after another: there are dozens of them, and nothing about one
        // depends on another. Built here, on the main actor, so what each
        // reads from settings and the key store is read at the start of the
        // pass.
        let asked = settings.shownAccounts.filter { $0.isPrimary && wanted.contains($0.provider) }
        let primaries = asked.map { fetch(for: $0, liveKey: false) }
        // Added accounts stay on the loop's own cadence: every one of them is
        // an agent whose transcripts this Mac can see, so the signals are not
        // blind to any of them.
        let extras = settings.shownAccounts
            .filter { !$0.isPrimary && $0.provider != .pulseExtension }
            .map { ($0, fetch(for: $0, liveKey: false)) }
        // Extensions are read side by side rather than in that queue: each is
        // a program with its own time limit, and one taking all of it must not
        // make every other extension wait behind it.
        let extensionAccounts = settings.shownAccounts.filter { settings.pulseExtension(for: $0) != nil }
        let extensions = extensionAccounts.map { fetch(for: $0, liveKey: false) }

        Task {
            let rawPrimaries = await Self.fetchTogether(primaries)

            // **The disowning is checked before anything is written, not just
            // before the readings are handed to the panel.** `reconciled`
            // banks what it is given, so a pass that had been given up on used
            // to put its stale readings on disk on the way past — where the
            // next launch reads them — even though the guard below then threw
            // them away. Nothing this pass learned is worth keeping once
            // another pass has run.
            guard pass == self.currentPass else { return }

            // **One collection for the rest of the pass.** A refusal — rate
            // limited, expired token, a VPN dropping the connection — falls
            // back to the last good reading rather than blanking the card, and
            // it comes back marked stale so it says how old it is. The rows are
            // built once, from the one list of providers: the commit loop and
            // the change test below are asked of the same collection, so a
            // provider can no longer be committed and yet be missing from the
            // comparison — which is what left Devin's moves unable to shorten
            // the interval.
            var results: [BatchResult] = []
            for (account, raw) in zip(asked, rawPrimaries) {
                let answer = await self.settle(raw)
                results.append(BatchResult(provider: account.provider, raw: answer.raw, fetched: answer.fetched))
            }

            // Accounts Pulse signed in to itself, read one at a time: each
            // may have to renew its token first, and they are few.
            //
            // Held rather than written as they arrive: this loop is the
            // longest part of a pass — a token renewal is its own round trip —
            // so it is where a pass is most likely to be disowned, and it was
            // the one place that wrote straight into `usage` with no check at
            // all. Every one of these went over a newer reading.
            var fetchedExtras: [(String, ProviderUsage, ProviderUsage)] = []
            for (account, fetch) in extras {
                let raw = await fetch()
                guard pass == self.currentPass else { return }
                let answer = await self.settle(raw)
                fetchedExtras.append((account.id, answer.fetched, answer.raw))
            }
            let extensionReadings = await Self.fetchTogether(extensions)
            guard pass == self.currentPass else { return }
            for (account, reading) in zip(extensionAccounts, extensionReadings) {
                let answer = await self.settle(reading)
                fetchedExtras.append((account.id, answer.fetched, answer.raw))
            }

            // **A disowned pass writes nothing.** It was given up on, another
            // has run since, and everything below would put its stale readings
            // over newer ones and clear flags that now belong elsewhere.
            guard pass == self.currentPass else { return }

            for (id, usage, raw) in fetchedExtras { self.commit(usage, raw: raw, for: id) }

            // Only what was actually fetched is written back. A provider that
            // is off the rail was never asked, so its slot here would be
            // overwritten with a stale cache entry every automatic pass —
            // quietly undoing the deliberate refresh its own settings pane
            // offers, a minute or two after the user pressed it.
            for result in results {
                self.commit(result.fetched, raw: result.raw, for: AccountKey(result.provider).id)
            }
            self.isRefreshing = false
            self.refreshStartedAt = nil
            self.refreshingAccount = nil
            self.runQueued()

            // Compare the windows only. `observedAt` moves on every successful
            // fetch, so including it would report a change every single time
            // and the loop would never slow down. `results` holds only the
            // providers that were actually asked, so a switched-off one — whose
            // slot was never written — cannot compare as "moved" on every pass
            // and pin the adaptive interval at its floor.
            if Self.didAnythingMove(results, previous: previous) {
                self.signals.lastChange = self.clock()
            }

            if wanted.contains(.codex) { self.refreshCodexResetCredits() }
            self.scheduleNext()
        }
    }

    /// Re-fetches only the provider whose ring the user clicked.
    ///
    /// The automatic pass intentionally remains all-or-nothing so its two
    /// independent requests stay aligned on one clock. A manual refresh is
    /// narrower: it should not start the other provider's helper or spend a
    /// second endpoint request when the user asked about one ring.
    func refresh(_ account: AccountKey) {
        // Provider panes stay reachable while their rail slot is switched
        // off. Their controls must not turn that into an unadvertised fetch.
        guard !settings.needsProviderSelection, settings.isEnabled(account) else { return }
        // Asked for by hand: the keychain may be asked again for Cursor's
        // sealed login, which an automatic pass does not do after a refusal.
        if account.provider == .cursor || account.provider == .grokBot { CursorKeychain.allowAsking() }
        // The same ceiling as the full pass, and for the same reason: this
        // path sets the flag too, so a ring click that never came back would
        // block every refresh after it.
        if isRefreshing, let started = refreshStartedAt,
           clock().timeIntervalSince(started) > Self.passCeiling {
            isRefreshing = false
        }

        guard !isRefreshing else {
            queued.insert(account)
            return
        }
        isRefreshing = true
        refreshStartedAt = clock()
        refreshingAccount = account
        generation += 1
        currentPass = generation
        let pass = generation

        let previous = usage[account.id]
        let startedAt = ContinuousClock.now
        let fetch = fetch(for: account, liveKey: true)

        Task {
            let raw = await fetch()

            guard pass == self.currentPass else { return }

            let answer = await self.settle(raw)
            guard pass == self.currentPass else { return }
            self.commit(answer.fetched, raw: answer.raw, for: account.id)

            if previous?.windows != answer.fetched.windows {
                self.signals.lastChange = self.clock()
            }

            // A local/status-line read can finish within one frame. Keep the
            // explicit feedback around long enough to be perceived; network
            // requests naturally exceed this and pay no extra delay.
            let minimumFeedback = Duration.milliseconds(650)
            let elapsed = startedAt.duration(to: .now)
            if elapsed < minimumFeedback {
                try? await Task.sleep(for: minimumFeedback - elapsed)
            }

            guard pass == self.currentPass else { return }
            self.isRefreshing = false
            self.refreshStartedAt = nil
            self.refreshingAccount = nil
            if account == AccountKey(.codex) { self.refreshCodexResetCredits() }
            self.scheduleNext()
            self.runQueued()
        }
    }

    /// **The one path from an account to its request.** Both passes build
    /// theirs here, so which service answers for which account, and with what
    /// credential, is decided once — by `services`.
    ///
    /// - Parameter liveKey: read the credential from the key store when the
    ///   launch-time cache has none. For a ring click: a provider's own pane
    ///   in Settings is reachable while it is switched off, so its key will
    ///   not be in the cache. A full pass only ever asks enabled accounts,
    ///   whose keys are.
    private func fetch(for account: AccountKey, liveKey: Bool) -> UsageFetch {
        let provider = account.provider
        let key: String?
        if !account.isPrimary {
            key = nil
        } else if liveKey {
            key = provider.keepsOwnCredential ? (apiKeys[provider] ?? services.storedKey(for: provider)) : nil
        } else {
            key = apiKeys[provider]
        }
        // Every request the check makes is recorded for the diagnostics.
        let fetch = services.fetch(for: account, key: key)
        return { await ResponseLog.capture(fetch) }
    }

    /// Asks every account at once and returns the answers in the order given.
    private nonisolated static func fetchTogether(_ fetches: [UsageFetch]) async -> [ProviderUsage] {
        await withTaskGroup(of: (Int, ProviderUsage).self) { group in
            for (index, fetch) in fetches.enumerated() {
                group.addTask { (index, await fetch()) }
            }
            var readings = [ProviderUsage?](repeating: nil, count: fetches.count)
            for await (index, reading) in group { readings[index] = reading }
            return readings.compactMap { $0 }
        }
    }

    /// What an answer becomes before it is shown: its balance ring, then the
    /// cache's say. Returns both, because the alert rules and the diagnostics
    /// want the raw answer as well as the reconciled one.
    private func settle(_ raw: ProviderUsage) async -> (raw: ProviderUsage, fetched: ProviderUsage) {
        let answered = ringed(Self.namingHeldBack(raw, isHoldingBack: NetworkSession.isHoldingBack))
        return (answered, await cache.reconciled(answered))
    }

    /// A request "System Proxy Only" refused fails like a dropped connection,
    /// and a service reports that as unreachable. While the guard is refusing,
    /// that is what happened, so the reading says so — a route that did not
    /// need the network (a helper, a local file) answers as it would anyway.
    nonisolated static func namingHeldBack(_ raw: ProviderUsage, isHoldingBack: Bool) -> ProviderUsage {
        guard isHoldingBack, raw.state == .unavailable(.unreachable) else { return raw }
        var named = ProviderUsage.unavailable(raw.account, reason: .systemProxyOff)
        named.attempts = raw.attempts
        named.responses = raw.responses
        named.origin = raw.origin
        named.sourceScope = raw.sourceScope
        return named
    }

    /// An API account's balance with the ring its basis gives it. DeepSeek
    /// makes its own, from before the rule was everyone's; see `BalanceRing`.
    private func ringed(_ raw: ProviderUsage) -> ProviderUsage {
        let account = raw.account
        // Extensions too: one that reports a balance and no limit is a relay's
        // prepaid credit, and `applying` leaves every other reading as it is.
        let takesRing = account.provider == .pulseExtension
            || (account.provider.billing == .api && account.provider != .deepSeek)
        guard takesRing else { return raw }
        return BalanceRing.applying(
            basis: settings.balanceBasis(for: account),
            budget: settings.balanceBudget(for: account),
            to: raw
        )
    }

    private func runQueued() {
        // A whole pass supersedes the individual ones it would have covered.
        if queuedFullPass {
            queuedFullPass = false
            queued.removeAll()
            refresh()
            return
        }

        guard let account = queued.first else { return }
        queued.remove(account)
        refresh(account)
    }

    /// Writes a fetched reading into the table, and lets the alerts see it.
    ///
    /// **Every fetched reading goes through here, and only fetched ones.** The
    /// seeded placeholders and the cache restored at launch are written
    /// directly: neither is something Pulse has just observed, and running the
    /// restored cache through the alert rules would announce a fortnight of
    /// crossings the moment the app opened.
    private func commit(_ fetched: ProviderUsage, raw: ProviderUsage, for id: String) {
        // The replies belong to the diagnostics, not to the table every view
        // of the panel reads.
        var fetched = fetched
        fetched.responses = []
        usage[id] = fetched
        diagnostics[id] = ConnectionDiagnostic(
            raw: raw.recordingSoleRoute(), displayed: fetched,
            previous: diagnostics[id], now: clock()
        )
        guard let account = AccountKey(id: id) else { return }
        // Before the alert rules, and regardless of whether they are on: the
        // mark's celebration is not a notification.
        resetWatch.observe(fetched, as: account)
        elsewhere?.observe(fetched, as: account)
        guard let alerts else { return }
        // Both: the panel shows the reconciled reading, and the alert rules
        // need the answer the service actually gave — `reconciled` swaps a
        // failure for cached figures, which loses the reason with it.
        alerts.observe(fetched, raw: raw, as: account)
    }

    /// Runs the alert rules over the readings already in hand.
    ///
    /// Turning the threshold on — or lowering it — is a moment where a limit
    /// can already be over the line, and the documented behaviour is that such
    /// a limit is announced *once, immediately*. Without this it waited for the
    /// next pass, which on the adaptive interval is up to half an hour: the
    /// setting looked broken to anyone who switched it on to check.
    ///
    /// Only `.live` readings, and each is its own raw fetch — a cached or
    /// unavailable one has nothing to witness and must not be dressed up as a
    /// successful pass.
    func reconsiderAlerts() {
        guard let alerts else { return }
        let now = clock()
        var needsRefresh = false
        for account in settings.shownAccounts {
            let reading = usage(for: account)
            guard case .live = reading.state,
                  let observedAt = reading.observedAt,
                  now.timeIntervalSince(observedAt) <= UsageCache.maximumAge else {
                needsRefresh = true
                continue
            }
            if reading.current(at: now)?.windows.count != reading.windows.count {
                needsRefresh = true
            }
            alerts.observe(reading, raw: reading, as: account)
        }
        if needsRefresh { refresh() }
    }

    /// Whether this window's current cycle has been seen spent off this Mac.
    func usedElsewhere(_ window: UsageWindow, account: AccountKey) -> Bool {
        elsewhere?.usedElsewhere(window, account: account) ?? false
    }

    func usage(for account: AccountKey) -> ProviderUsage {
        usage[account.id] ?? .unavailable(account, reason: .loading)
    }

    // MARK: - The loop

    private func scheduleNext() {
        timer?.invalidate()
        guard !settings.needsProviderSelection else { return }

        signals.isPanelVisible = settings.isPanelVisible
        signals.isConstrained = screensAsleep
            || ProcessInfo.processInfo.isLowPowerModeEnabled
            || [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        // The monitor is already watching the transcripts on its own clock, so
        // the refresh loop reads its answer rather than scanning again.
        signals.lastAgentActivity = activity.lastWrite

        // The soonest anything is due, so the provider on the shortest cadence
        // sets the alarm and the rest are simply not asked when it goes off.
        let now = clock()
        let waits = settings.shownAccounts.filter(\.isPrimary).map { account -> TimeInterval in
            let due = interval(for: account.provider)
            guard let asked = askedAt[account.id] else { return 0 }
            return max(due - now.timeIntervalSince(asked), 0)
        }
        // A floor on the *timer* rather than on any provider's cadence: with
        // nothing enabled, or with something perpetually due, this is what
        // stops the loop spinning.
        let wait = Self.timerWait(
            primaryWaits: waits, fixed: settings.refreshInterval.seconds,
            adaptive: AdaptiveRefresh.interval(for: signals)
        )

        // **`currentInterval` is the cadence, not the countdown.** Settings
        // renders it as "Now: X minutes" and `isOverdue` multiplies it, and
        // both broke when it briefly became the wait until the next tick: a
        // timer set for the remaining 15 seconds of somebody's cycle read as
        // "Now: 0 minutes", and the overdue threshold for the half-hour
        // providers collapsed to about eleven minutes because DeepSeek was on
        // the rail. The wait is a scheduling detail; this is the answer to
        // "how often is Pulse asking", which is still the ordinary cadence.
        currentInterval = settings.refreshInterval.seconds
            ?? AdaptiveRefresh.interval(for: signals)

        let timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            // **The one caller that honours each provider's own cadence.**
            MainActor.assumeIsolated { self?.refresh(dueOnly: true) }
        }
        // `.common` so the loop keeps running while a menu or a drag has the
        // run loop in another mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The things that change how often it is worth asking, none of which
    /// arrive on their own schedule.
    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter

        observers = [
            observe(NSWorkspace.screensDidSleepNotification, on: workspace) { store in
                store.screensAsleep = true
                store.updateActivityMonitor()
            },
            observe(NSWorkspace.screensDidWakeNotification, on: workspace) { store in
                store.screensAsleep = false
                store.updateActivityMonitor()
                // Whatever happened while the display was off, the numbers on
                // screen are now the oldest they will ever be.
                store.refresh()
            },
            // The *system* waking, which is a different notification from the
            // screen waking and does not always come with it — a Mac woken
            // with its lid shut, on an external display, gets one and not the
            // other. A timer's fire date passed while asleep is exactly the
            // case that needs asking again.
            observe(NSWorkspace.didWakeNotification, on: workspace) { store in
                store.refresh()
            },
            observe(ProcessInfo.thermalStateDidChangeNotification) { $0.scheduleNext() },
            observe(.NSProcessInfoPowerStateDidChange) { $0.scheduleNext() }
        ]
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter = .default,
        handler: @escaping @MainActor (UsageStore) -> Void
    ) -> (center: NotificationCenter, token: any NSObjectProtocol) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        return (center, token)
    }
}
