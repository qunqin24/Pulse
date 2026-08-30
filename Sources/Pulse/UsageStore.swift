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
    private(set) var usage: [Provider: ProviderUsage] = [:]
    private(set) var isRefreshing = false
    /// Nil while an automatic refresh is fetching every provider; otherwise
    /// the one provider the user explicitly asked to refresh from its ring.
    private var refreshingProvider: Provider?

    /// What the automatic interval currently works out to, so settings can
    /// show it rather than leaving it a black box.
    private(set) var currentInterval: TimeInterval = AdaptiveRefresh.floor

    private let settings: AppSettings
    private let appServer = CodexAppServer()
    private let codex: CodexUsageService
    private let claudeCode = ClaudeCodeUsageService()
    private let antigravity = AntigravityUsageService()
    private var timer: Timer?
    /// Kept with the centre each was registered on: workspace notifications
    /// don't come from the default centre, and removing them there does
    /// nothing at all.
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    private var signals = AdaptiveRefresh.Signals()
    private var screensAsleep = false

    /// Whether either CLI is working right now. Its own clock — see
    /// `AgentActivityMonitor`.
    let activity = AgentActivityMonitor()

    init(settings: AppSettings) {
        self.settings = settings
        codex = CodexUsageService(server: appServer)

        for provider in Provider.allCases {
            usage[provider] = .unavailable(provider, reason: .loading)
        }
    }

    /// Codex's reset credits and account totals, which only its app server
    /// reports. Fetched when the settings pane asks rather than on the refresh
    /// loop: nothing on the rail shows them, and the call starts a process.
    func codexAccountUsage() async -> CodexAccountUsage? {
        await CodexAccountUsageService(server: appServer).fetch()
    }

    /// Whether a provider's CLI is working at this moment.
    func isRunning(_ provider: Provider) -> Bool { activity.running.contains(provider) }

    /// Whether this provider is being refreshed explicitly from its ring.
    /// Automatic background passes stay silent on the rail.
    func isRefreshing(_ provider: Provider) -> Bool {
        isRefreshing && refreshingProvider == provider
    }

    func start() {
        guard observers.isEmpty else { return }
        observe()
        updateActivityMonitor()

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
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshingProvider = nil

        let codexSource = settings.source(for: .codex)
        let claudeSource = settings.source(for: .claudeCode)
        let previous = usage

        Task { [codex, claudeCode, antigravity] in
            // Independent, so they run side by side rather than one waiting on
            // another's round trip.
            async let codexUsage = codex.fetch(source: codexSource)
            async let claudeUsage = claudeCode.fetch(source: claudeSource)
            async let antigravityUsage = antigravity.fetch()

            let (rawCodex, rawClaude, rawAntigravity) = await (codexUsage, claudeUsage, antigravityUsage)

            // A refusal — rate limited, expired token, a VPN dropping the
            // connection — falls back to the last good reading rather than
            // blanking the card. It comes back marked stale, so it says how
            // old it is.
            let fetchedCodex = await UsageCache.shared.reconciled(rawCodex)
            let fetchedClaude = await UsageCache.shared.reconciled(rawClaude)
            let fetchedAntigravity = await UsageCache.shared.reconciled(rawAntigravity)

            self.usage[.codex] = fetchedCodex
            self.usage[.claudeCode] = fetchedClaude
            self.usage[.antigravity] = fetchedAntigravity
            self.isRefreshing = false
            self.refreshingProvider = nil

            // Compare the windows only. `observedAt` moves on every successful
            // fetch, so including it would report a change every single time
            // and the loop would never slow down.
            let moved = previous[.codex]?.windows != fetchedCodex.windows
                || previous[.claudeCode]?.windows != fetchedClaude.windows
                || previous[.antigravity]?.windows != fetchedAntigravity.windows
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
    func refresh(_ provider: Provider) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshingProvider = provider

        let source = settings.source(for: provider)
        let previous = usage[provider]
        let startedAt = ContinuousClock.now

        Task { [codex, claudeCode, antigravity] in
            let raw: ProviderUsage
            switch provider {
            case .codex:
                raw = await codex.fetch(source: source)
            case .claudeCode:
                raw = await claudeCode.fetch(source: source)
            case .antigravity:
                raw = await antigravity.fetch()
            }

            let fetched = await UsageCache.shared.reconciled(raw)
            self.usage[provider] = fetched

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
            self.refreshingProvider = nil
            self.scheduleNext()
        }
    }

    func usage(for provider: Provider) -> ProviderUsage {
        usage[provider] ?? .unavailable(provider, reason: .loading)
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
