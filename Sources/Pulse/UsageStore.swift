import AppKit
import Foundation
import Observation

/// Holds the current usage for every provider and keeps it refreshed.
///
/// The two providers are fetched very differently — Codex is asked over the
/// network, Claude Code is read from whatever its status line last handed us —
/// so each is refreshed on its own terms rather than on one shared clock.
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
    private(set) var isRefreshing = false
    /// Nil while an automatic refresh is fetching every provider; otherwise
    /// the one provider the user explicitly asked to refresh from its ring.
    private var refreshingAccount: AccountKey?

    /// What the automatic interval currently works out to, so settings can
    /// show it rather than leaving it a black box.
    private(set) var currentInterval: TimeInterval = AdaptiveRefresh.floor

    private let settings: AppSettings
    private let appServer = CodexAppServer()
    private let codex: CodexUsageService
    private let claudeCode = ClaudeCodeUsageService()
    private let antigravity = AntigravityUsageService()
    private let cursor = CursorUsageService()
    private var timer: Timer?
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
    private var screensAsleep = false

    /// Whether either CLI is working right now. Its own clock — see
    /// `AgentActivityMonitor`.
    let activity = AgentActivityMonitor()

    init(settings: AppSettings) {
        self.settings = settings
        codex = CodexUsageService(server: appServer)

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
        guard account.isPrimary, account.provider.keepsOwnCredential,
              !account.provider.canReportWithoutSetup
        else { return .unavailable(account, reason: .loading) }

        // And the remedy differs: a sign-in is not a key to paste.
        let reason: ProviderUsage.Unavailability = if account.provider == .copilot {
            .notSignedIn
        } else if account.provider.usesSessionCookie {
            .ollamaSessionMissing
        } else {
            .apiKeyMissing
        }
        return .unavailable(account, reason: reason)
    }

    /// Codex's reset credits and account totals, which only its app server
    /// reports. Fetched when the settings pane asks rather than on the refresh
    /// loop: nothing on the rail shows them, and the call starts a process.
    func codexAccountUsage() async -> CodexAccountUsage? {
        await CodexAccountUsageService(server: appServer).fetch()
    }

    /// Picks up a key that was just entered, or one that changed.
    func loadAPIKeys() {
        apiKeys = Dictionary(
            uniqueKeysWithValues: Provider.allCases
                .filter { $0.keepsOwnCredential && settings.isEnabled(AccountKey($0)) }
                .compactMap { provider in APIKeyStore.key(for: provider).map { (provider, $0) } }
        )

        // Entering or clearing a key changes what a provider *can* report, and
        // one that still has nothing to show should say which of the two it is
        // rather than going on claiming to be loading. Only a placeholder is
        // rewritten — a reading that has actually been taken is left alone.
        for provider in Provider.allCases where provider.keepsOwnCredential {
            let account = AccountKey(provider)
            guard case .unavailable(let reason) = usage[account.id]?.state,
                  [.loading, .apiKeyMissing, .ollamaSessionMissing, .apiKeyRefused,
                   .signedOut, .notSignedIn]
                    .contains(reason)
            else { continue }
            usage[account.id] = Self.initialState(for: account)
        }
    }

    /// Whether a provider's CLI is working at this moment.
    func isRunning(_ provider: Provider) -> Bool { activity.running.contains(provider) }

    /// Whether this provider is being refreshed explicitly from its ring.
    /// Automatic background passes stay silent on the rail.
    func isRefreshing(_ account: AccountKey) -> Bool {
        isRefreshing && refreshingAccount == account
    }

    func start() {
        guard observers.isEmpty else { return }
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
        Task { [accounts = settings.allAccounts] in
            for account in accounts {
                guard let cached = await UsageCache.shared.lastReading(for: account) else { continue }
                // Nothing has been fetched yet, so anything but the seeded
                // placeholder would be a reading — and there cannot be one.
                guard case .unavailable = self.usage(for: account).state else { continue }
                self.usage[account.id] = cached
            }

            self.refresh()
        }

        // Only relevant when the app server is being used as a fallback; it
        // pushes when limits change, which saves waiting for the next tick.
        Task { [appServer] in
            await appServer.setRateLimitsChangedHandler { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// The user hovered the rail to read a card, which is the clearest sign
    /// they want these numbers to be current.
    func noteLooked() {
        signals.lastLooked = Date()

        // A rail is crossed ring by ring, so this is called several times a
        // second. Asking once is the point; asking once per ring is a storm.
        let asked = lastLookRefresh.map { Date().timeIntervalSince($0) < Self.lookCooldown } ?? false

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
            lastLookRefresh = Date()
            refresh()
        } else {
            scheduleNext()
        }
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
        return Date().timeIntervalSince(newest) > currentInterval * 2 + 60
    }

    /// Re-reads settings that affect the loop itself, then refreshes.
    func settingsChanged() {
        loadAPIKeys()
        updateActivityMonitor()
        refresh()
    }

    /// Nothing shows the spinner while the panel is off screen or the display
    /// is asleep, so nothing needs watching either.
    private func updateActivityMonitor() {
        if settings.isPanelVisible && !screensAsleep {
            activity.start()
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

    /// Longer than any pass can honestly take: every request in one carries a
    /// timeout of its own, and the whole set runs side by side. Past this the
    /// pass is not slow, it is gone — and since `scheduleNext` only runs when a
    /// pass *finishes*, a lost one takes the whole loop with it and nothing
    /// ever asks again.
    private static let passCeiling: TimeInterval = 180

    func refresh() {
        if isRefreshing, let started = refreshStartedAt,
           Date().timeIntervalSince(started) > Self.passCeiling {
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
        refreshStartedAt = Date()
        refreshingAccount = nil
        generation += 1
        currentPass = generation
        let pass = generation

        let codexSource = settings.source(for: AccountKey(.codex))
        let claudeSource = settings.source(for: AccountKey(.claudeCode))
        let previous = usage

        // Read here rather than inside the services, which stay free of
        // storage concerns.
        let openCode = OpenCodeGoUsageService(enteredKey: apiKeys[.openCodeGo])
        let kimi = KimiCodeUsageService(enteredKey: apiKeys[.kimiCode])
        let ollama = OllamaCloudUsageService(cookie: apiKeys[.ollamaCloud])
        let zai = ZaiUsageService(provider: .zai, enteredKey: apiKeys[.zai])
        let glm = ZaiUsageService(provider: .glmCoding, enteredKey: apiKeys[.glmCoding])
        let minimax = MiniMaxUsageService(provider: .minimax, enteredKey: apiKeys[.minimax])
        let minimaxCN = MiniMaxUsageService(provider: .minimaxCN, enteredKey: apiKeys[.minimaxCN])
        let copilot = CopilotUsageService(token: apiKeys[.copilot])
        // Nothing is fetched for a provider that isn't on the rail: it would
        // spend someone else's request, and read a credential, for a figure
        // nobody is going to see.
        let wanted = Set(settings.shownAccounts.filter(\.isPrimary).map(\.provider))
        let extras = settings.shownAccounts.filter { !$0.isPrimary }

        Task { [codex, claudeCode, antigravity, cursor] in
            // Independent, so they run side by side rather than one waiting on
            // another's round trip.
            async let codexUsage = wanted.contains(.codex)
                ? await codex.fetch(source: codexSource)
                : ProviderUsage.unavailable(.codex, reason: .loading)
            async let claudeUsage = wanted.contains(.claudeCode)
                ? await claudeCode.fetch(source: claudeSource)
                : ProviderUsage.unavailable(.claudeCode, reason: .loading)
            async let antigravityUsage = wanted.contains(.antigravity)
                ? await antigravity.fetch()
                : ProviderUsage.unavailable(.antigravity, reason: .loading)
            async let cursorUsage = wanted.contains(.cursor)
                ? await cursor.fetch()
                : ProviderUsage.unavailable(.cursor, reason: .loading)
            async let openCodeUsage = wanted.contains(.openCodeGo)
                ? await openCode.fetch()
                : ProviderUsage.unavailable(.openCodeGo, reason: .loading)
            async let ollamaUsage = wanted.contains(.ollamaCloud)
                ? await ollama.fetch()
                : ProviderUsage.unavailable(.ollamaCloud, reason: .loading)
            async let kimiUsage = wanted.contains(.kimiCode)
                ? await kimi.fetch()
                : ProviderUsage.unavailable(.kimiCode, reason: .loading)
            async let zaiUsage = wanted.contains(.zai)
                ? await zai.fetch()
                : ProviderUsage.unavailable(.zai, reason: .loading)
            async let glmUsage = wanted.contains(.glmCoding)
                ? await glm.fetch()
                : ProviderUsage.unavailable(.glmCoding, reason: .loading)
            async let minimaxUsage = wanted.contains(.minimax)
                ? await minimax.fetch()
                : ProviderUsage.unavailable(.minimax, reason: .loading)
            async let minimaxCNUsage = wanted.contains(.minimaxCN)
                ? await minimaxCN.fetch()
                : ProviderUsage.unavailable(.minimaxCN, reason: .loading)
            async let copilotUsage = wanted.contains(.copilot)
                ? await copilot.fetch()
                : ProviderUsage.unavailable(.copilot, reason: .loading)

            let (rawCodex, rawClaude, rawAntigravity, rawOpenCode) =
                await (codexUsage, claudeUsage, antigravityUsage, openCodeUsage)
            let (rawKimi, rawCursor, rawOllama) = await (kimiUsage, cursorUsage, ollamaUsage)
            let (rawZai, rawGLM) = await (zaiUsage, glmUsage)
            let (rawMiniMax, rawMiniMaxCN) = await (minimaxUsage, minimaxCNUsage)
            let rawCopilot = await copilotUsage

            // **The disowning is checked before anything is written, not just
            // before the readings are handed to the panel.** `reconciled`
            // banks what it is given, so a pass that had been given up on used
            // to put its stale readings on disk on the way past — where the
            // next launch reads them — even though the guard below then threw
            // them away. Nothing this pass learned is worth keeping once
            // another pass has run.
            guard pass == self.currentPass else { return }

            // A refusal — rate limited, expired token, a VPN dropping the
            // connection — falls back to the last good reading rather than
            // blanking the card. It comes back marked stale, so it says how
            // old it is.
            let fetchedCodex = await UsageCache.shared.reconciled(rawCodex)
            let fetchedClaude = await UsageCache.shared.reconciled(rawClaude)
            let fetchedAntigravity = await UsageCache.shared.reconciled(rawAntigravity)
            let fetchedOpenCode = await UsageCache.shared.reconciled(rawOpenCode)
            let fetchedKimi = await UsageCache.shared.reconciled(rawKimi)
            let fetchedCursor = await UsageCache.shared.reconciled(rawCursor)
            let fetchedOllama = await UsageCache.shared.reconciled(rawOllama)
            let fetchedZai = await UsageCache.shared.reconciled(rawZai)
            let fetchedGLM = await UsageCache.shared.reconciled(rawGLM)
            let fetchedMiniMax = await UsageCache.shared.reconciled(rawMiniMax)
            let fetchedMiniMaxCN = await UsageCache.shared.reconciled(rawMiniMaxCN)
            let fetchedCopilot = await UsageCache.shared.reconciled(rawCopilot)

            // Accounts Pulse signed in to itself, read one at a time: each
            // may have to renew its token first, and they are few.
            //
            // Held rather than written as they arrive: this loop is the
            // longest part of a pass — a token renewal is its own round trip —
            // so it is where a pass is most likely to be disowned, and it was
            // the one place that wrote straight into `usage` with no check at
            // all. Every one of these went over a newer reading.
            var fetchedExtras: [(String, ProviderUsage)] = []
            for account in extras {
                let raw = await Self.fetchAdded(account, claudeCode: claudeCode, codex: codex)
                guard pass == self.currentPass else { return }
                fetchedExtras.append((account.id, await UsageCache.shared.reconciled(raw)))
            }


            // **A disowned pass writes nothing.** It was given up on, another
            // has run since, and everything below would put its stale readings
            // over newer ones and clear flags that now belong elsewhere.
            guard pass == self.currentPass else { return }

            for (id, usage) in fetchedExtras { self.usage[id] = usage }

            // Only what was actually fetched is written back. A provider that
            // is off the rail was never asked, so its slot here would be
            // overwritten with a stale cache entry every automatic pass —
            // quietly undoing the deliberate refresh its own settings pane
            // offers, a minute or two after the user pressed it.
            for (provider, fetched) in [
                (Provider.codex, fetchedCodex),
                (.claudeCode, fetchedClaude),
                (.antigravity, fetchedAntigravity),
                (.openCodeGo, fetchedOpenCode),
                (.kimiCode, fetchedKimi),
                (.cursor, fetchedCursor),
                (.ollamaCloud, fetchedOllama),
                (.zai, fetchedZai),
                (.glmCoding, fetchedGLM),
                (.minimax, fetchedMiniMax),
                (.minimaxCN, fetchedMiniMaxCN),
                (.copilot, fetchedCopilot),
            ] where wanted.contains(provider) {
                self.usage[AccountKey(provider).id] = fetched
            }
            self.isRefreshing = false
            self.refreshStartedAt = nil
            self.refreshingAccount = nil
            self.runQueued()

            // Compare the windows only. `observedAt` moves on every successful
            // fetch, so including it would report a change every single time
            // and the loop would never slow down.
            // Only what was actually fetched. A provider that is switched off
            // is still reconciled — which hands back its cached windows — while
            // its slot here was never written, so it compared as "moved" on
            // every single pass and pinned the adaptive interval at its floor.
            let moved = [
                (Provider.codex, fetchedCodex),
                (.claudeCode, fetchedClaude),
                (.antigravity, fetchedAntigravity),
                (.openCodeGo, fetchedOpenCode),
                (.kimiCode, fetchedKimi),
                (.cursor, fetchedCursor),
                (.ollamaCloud, fetchedOllama),
                (.zai, fetchedZai),
                (.glmCoding, fetchedGLM),
                (.minimax, fetchedMiniMax),
                (.minimaxCN, fetchedMiniMaxCN),
                (.copilot, fetchedCopilot),
            ].contains { provider, fetched in
                wanted.contains(provider)
                    && previous[AccountKey(provider).id]?.windows != fetched.windows
            }
            if moved { self.signals.lastChange = Date() }

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
        // The same ceiling as the full pass, and for the same reason: this
        // path sets the flag too, so a ring click that never came back would
        // block every refresh after it.
        if isRefreshing, let started = refreshStartedAt,
           Date().timeIntervalSince(started) > Self.passCeiling {
            isRefreshing = false
        }

        guard !isRefreshing else {
            queued.insert(account)
            return
        }
        isRefreshing = true
        refreshStartedAt = Date()
        refreshingAccount = account
        generation += 1
        currentPass = generation
        let pass = generation

        let provider = account.provider
        let source = settings.source(for: account)
        let previous = usage[account.id]
        let startedAt = ContinuousClock.now
        // A provider's own pane in Settings is reachable while it is switched
        // off, so its key will not be in the launch-time cache.
        let key = provider.keepsOwnCredential ? (apiKeys[provider] ?? APIKeyStore.key(for: provider)) : nil
        let openCode = OpenCodeGoUsageService(enteredKey: key)
        let kimi = KimiCodeUsageService(enteredKey: key)
        let ollama = OllamaCloudUsageService(cookie: key)
        let zai = ZaiUsageService(provider: provider, enteredKey: key)
        let minimax = MiniMaxUsageService(provider: provider, enteredKey: key)

        Task { [codex, claudeCode, antigravity, cursor] in
            let raw: ProviderUsage
            if !account.isPrimary {
                raw = await Self.fetchAdded(account, claudeCode: claudeCode, codex: codex)
            } else {
            switch provider {
            case .codex:
                raw = await codex.fetch(source: source)
            case .claudeCode:
                raw = await claudeCode.fetch(source: source)
            case .antigravity:
                raw = await antigravity.fetch()
            case .cursor:
                raw = await cursor.fetch()
            case .openCodeGo:
                raw = await openCode.fetch()
            case .kimiCode:
                raw = await kimi.fetch()
            case .ollamaCloud:
                raw = await ollama.fetch()
            case .zai, .glmCoding:
                raw = await zai.fetch()
            case .minimax, .minimaxCN:
                raw = await minimax.fetch()
            case .copilot:
                raw = await CopilotUsageService(token: key).fetch()
            }
            }

            guard pass == self.currentPass else { return }

            let fetched = await UsageCache.shared.reconciled(raw)
            self.usage[account.id] = fetched

            if previous?.windows != fetched.windows {
                self.signals.lastChange = Date()
            }

            // A local/status-line read can finish within one frame. Keep the
            // explicit feedback around long enough to be perceived; network
            // requests naturally exceed this and pay no extra delay.
            let minimumFeedback = Duration.milliseconds(650)
            let elapsed = startedAt.duration(to: .now)
            if elapsed < minimumFeedback {
                try? await Task.sleep(for: minimumFeedback - elapsed)
            }

            self.isRefreshing = false
            self.refreshStartedAt = nil
            self.refreshingAccount = nil
            self.scheduleNext()
            self.runQueued()
        }
    }

    /// An account Pulse signed in to itself.
    ///
    /// Its token is renewed here when it is close to expiring, because nothing
    /// else will: the CLI keeps its own login fresh, and this one is not that.
    /// A renewal that fails leaves the account signed out rather than
    /// reporting a network error — the remedy is the same either way, and it
    /// is one the user can act on.
    private static func fetchAdded(
        _ account: AccountKey,
        claudeCode: ClaudeCodeUsageService,
        codex: CodexUsageService
    ) async -> ProviderUsage {
        guard var credentials = AccountCredentialStore.credentials(for: account) else {
            return .unavailable(account, reason: .signedOut)
        }

        if !credentials.isFresh {
            guard let renewed = try? await OAuthLogin.refresh(credentials, for: account.provider) else {
                return .unavailable(account, reason: .signedOut)
            }
            credentials = renewed
            // Compare-and-set: a pass that was given up on can still be in
            // here, and its answer must not replace a newer login.
            AccountCredentialStore.renewed(credentials, for: account)
        }

        return switch account.provider {
        case .claudeCode: await claudeCode.fetch(account: account, token: credentials.accessToken)
        case .codex: await codex.fetch(account: account, credentials: credentials)
        // Nothing else can be signed in to, so nothing else gets here.
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot:
            .unavailable(account, reason: .loading)
        }
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

    func usage(for account: AccountKey) -> ProviderUsage {
        usage[account.id] ?? .unavailable(account, reason: .loading)
    }

    // MARK: - The loop

    private func scheduleNext() {
        timer?.invalidate()

        signals.isPanelVisible = settings.isPanelVisible
        signals.isConstrained = screensAsleep
            || ProcessInfo.processInfo.isLowPowerModeEnabled
            || [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        // The monitor is already watching the transcripts on its own clock, so
        // the refresh loop reads its answer rather than scanning again.
        signals.lastAgentActivity = activity.lastWrite

        let wait = settings.refreshInterval.seconds ?? AdaptiveRefresh.interval(for: signals)
        currentInterval = wait

        let timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
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
