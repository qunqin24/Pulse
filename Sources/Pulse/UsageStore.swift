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

    private var signals = AdaptiveRefresh.Signals()
    private var screensAsleep = false

    /// Whether either CLI is working right now. Its own clock — see
    /// `AgentActivityMonitor`.
    let activity = AgentActivityMonitor()

    init(settings: AppSettings) {
        self.settings = settings
        codex = CodexUsageService(server: appServer)

        for account in settings.allAccounts {
            usage[account.id] = .unavailable(account, reason: .loading)
        }
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
                .filter { $0.usesAPIKey && settings.isEnabled(AccountKey($0)) }
                .compactMap { provider in APIKeyStore.key(for: provider).map { (provider, $0) } }
        )
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
        Task { [accounts = settings.allAccounts] in
            for account in accounts {
                guard let cached = await UsageCache.shared.lastReading(for: account) else { continue }
                // A fetch that has already landed is newer than anything on
                // disk and must not be undone by it.
                guard case .unavailable = self.usage(for: account).state else { continue }
                self.usage[account.id] = cached
            }
        }

        // Only relevant when the app server is being used as a fallback; it
        // pushes when limits change, which saves waiting for the next tick.
        Task { [appServer] in
            await appServer.setRateLimitsChangedHandler { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }

        refresh()
    }

    /// The user hovered the rail to read a card, which is the clearest sign
    /// they want these numbers to be current.
    func noteLooked() {
        signals.lastLooked = Date()

        // Reading a stale card is the moment a slow cadence is most obviously
        // wrong, so this asks straight away rather than tightening the loop
        // and waiting for it.
        if currentInterval > AdaptiveRefresh.floor { refresh() } else { scheduleNext() }
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

    func refresh() {
        guard !isRefreshing else {
            // Dropped, this used to be — and `settingsChanged()` is its main
            // caller, so switching a provider on mid-pass left it on `.loading`
            // until the next tick, which can be half an hour away.
            queuedFullPass = true
            return
        }
        isRefreshing = true
        refreshingAccount = nil

        let codexSource = settings.source(for: AccountKey(.codex))
        let claudeSource = settings.source(for: AccountKey(.claudeCode))
        let previous = usage

        // Read here rather than inside the services, which stay free of
        // storage concerns.
        let openCode = OpenCodeGoUsageService(enteredKey: apiKeys[.openCodeGo])
        let kimi = KimiCodeUsageService(enteredKey: apiKeys[.kimiCode])
        let ollama = OllamaCloudUsageService(cookie: apiKeys[.ollamaCloud])
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

            let (rawCodex, rawClaude, rawAntigravity, rawOpenCode) =
                await (codexUsage, claudeUsage, antigravityUsage, openCodeUsage)
            let (rawKimi, rawCursor, rawOllama) = await (kimiUsage, cursorUsage, ollamaUsage)

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

            // Accounts Pulse signed in to itself, read one at a time: each
            // may have to renew its token first, and they are few.
            for account in extras {
                let raw = await Self.fetchAdded(account, claudeCode: claudeCode, codex: codex)
                self.usage[account.id] = await UsageCache.shared.reconciled(raw)
            }

            self.usage[AccountKey(.codex).id] = fetchedCodex
            self.usage[AccountKey(.claudeCode).id] = fetchedClaude
            self.usage[AccountKey(.antigravity).id] = fetchedAntigravity
            self.usage[AccountKey(.openCodeGo).id] = fetchedOpenCode
            self.usage[AccountKey(.kimiCode).id] = fetchedKimi
            self.usage[AccountKey(.cursor).id] = fetchedCursor
            self.usage[AccountKey(.ollamaCloud).id] = fetchedOllama
            self.isRefreshing = false
            self.refreshingAccount = nil
            self.runQueued()

            // Compare the windows only. `observedAt` moves on every successful
            // fetch, so including it would report a change every single time
            // and the loop would never slow down.
            let moved = previous[AccountKey(.codex).id]?.windows != fetchedCodex.windows
                || previous[AccountKey(.claudeCode).id]?.windows != fetchedClaude.windows
                || previous[AccountKey(.antigravity).id]?.windows != fetchedAntigravity.windows
                || previous[AccountKey(.openCodeGo).id]?.windows != fetchedOpenCode.windows
                || previous[AccountKey(.kimiCode).id]?.windows != fetchedKimi.windows
                || previous[AccountKey(.cursor).id]?.windows != fetchedCursor.windows
                || previous[AccountKey(.ollamaCloud).id]?.windows != fetchedOllama.windows
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
        guard !isRefreshing else {
            queued.insert(account)
            return
        }
        isRefreshing = true
        refreshingAccount = account

        let provider = account.provider
        let source = settings.source(for: account)
        let previous = usage[account.id]
        let startedAt = ContinuousClock.now
        // A provider's own pane in Settings is reachable while it is switched
        // off, so its key will not be in the launch-time cache.
        let key = provider.usesAPIKey ? (apiKeys[provider] ?? APIKeyStore.key(for: provider)) : nil
        let openCode = OpenCodeGoUsageService(enteredKey: key)
        let kimi = KimiCodeUsageService(enteredKey: key)
        let ollama = OllamaCloudUsageService(cookie: key)

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
            }
            }

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
            AccountCredentialStore.set(credentials, for: account)
        }

        return switch account.provider {
        case .claudeCode: await claudeCode.fetch(account: account, token: credentials.accessToken)
        case .codex: await codex.fetch(account: account, credentials: credentials)
        // Nothing else can be signed in to, so nothing else gets here.
        case .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud: .unavailable(account, reason: .loading)
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
