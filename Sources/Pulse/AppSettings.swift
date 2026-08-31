import Foundation
import Observation

/// User-facing preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    /// Whether the floating panel is on screen.
    var isPanelVisible: Bool {
        didSet {
            guard isPanelVisible != oldValue else { return }
            UserDefaults.standard.set(isPanelVisible, forKey: Key.panelVisible)
            onChange?()
        }
    }

    /// Whether the floating panel stays out of other apps' full-screen Spaces.
    ///
    /// On by default: a usage glance is useful on the desktop, but sitting over
    /// a presentation, video, game, or focused full-screen workspace is noise.
    /// This is implemented with the panel's public AppKit collection behavior,
    /// so it needs no Accessibility permission and cannot confuse a maximized
    /// window with a real full-screen Space.
    var hidesInFullScreen: Bool {
        didSet {
            guard hidesInFullScreen != oldValue else { return }
            UserDefaults.standard.set(hidesInFullScreen, forKey: Key.hidesInFullScreen)
            onChange?()
        }
    }

    /// The order the rail draws them in, as account ids.
    ///
    /// Stored rather than derived so it survives a launch, and resolved through
    /// `orderedAccounts` rather than trusted as-is: an account added later is
    /// missing from every list stored before it existed, and one removed would
    /// still be named in lists stored while it did. The stored values are
    /// unchanged from when this was a list of providers — a provider's first
    /// account has the provider's own raw value as its id.
    var providerOrder: [String] {
        didSet {
            guard providerOrder != oldValue else { return }
            UserDefaults.standard.set(providerOrder, forKey: Key.providerOrder)
            // Deliberately no `onChange`: that is how the AppKit side hears
            // about settings the *usage loop* cares about, and it refetches
            // every provider when it fires. Rearranging the rail is a layout
            // change — the panel is `@Observable` and redraws on its own, and
            // nobody's rate limit should pay for a reorder.
        }
    }

    /// Accounts Pulse knows about beyond each provider's first, which exist
    /// only because Pulse was signed in to them.
    var extraAccounts: [ExtraAccount] {
        didSet {
            guard extraAccounts != oldValue else { return }
            // Before the change is announced: whoever reacts is about to
            // measure the panel, and the rail is now longer than it was.
            PanelMetrics.makeRoom(for: allAccounts.count)
            let data = try? JSONEncoder().encode(extraAccounts)
            UserDefaults.standard.set(data, forKey: Key.extraAccounts)
            onChange?()
        }
    }

    /// Every account there is: each provider's first, plus whatever has been
    /// added to the two that allow it. Declaration order, before the user's
    /// own order is applied.
    var allAccounts: [AccountKey] {
        Provider.allCases.flatMap { provider in
            [AccountKey(provider)] + extraAccounts.filter { $0.provider == provider }.map(\.key)
        }
    }

    /// Every account, in the user's order. Anything the stored order doesn't
    /// mention goes last, in declaration order — so a new one appears at the
    /// bottom of the rail rather than in the middle of it.
    var orderedAccounts: [AccountKey] {
        let known = allAccounts
        let stored = providerOrder.compactMap(AccountKey.init(id:)).filter(known.contains)
        return stored + known.filter { !stored.contains($0) }
    }

    /// Moves an account one place up or down. Silently does nothing at the
    /// ends, so the buttons can simply be disabled there.
    func move(_ account: AccountKey, by offset: Int) {
        var order = orderedAccounts
        guard
            let from = order.firstIndex(of: account),
            order.indices.contains(from + offset)
        else { return }

        order.swapAt(from, from + offset)
        providerOrder = order.map(\.id)
    }

    /// What to call an account. A provider's first one is just the provider;
    /// the rest carry a label so two subscriptions can be told apart.
    func label(for account: AccountKey) -> String {
        extraAccounts.first { $0.key == account }?.label ?? account.provider.displayName
    }

    /// Which accounts appear in the rail, as ids. Never empty — the last one
    /// left can't be switched off, since an empty rail would leave nothing to
    /// hover, and nothing to grab to drag the panel.
    ///
    /// Ids rather than providers, and stored under the same key with the same
    /// values as when it was providers: a first account's id *is* its
    /// provider's raw value, so nothing written by an older version stops
    /// matching.
    var enabledAccounts: Set<String> {
        didSet {
            guard enabledAccounts != oldValue else { return }
            if enabledAccounts.isEmpty {
                enabledAccounts = oldValue
                return
            }
            UserDefaults.standard.set(Array(enabledAccounts), forKey: Key.enabledProviders)
            onChange?()
        }
    }

    /// Interface language. Applied to `LocalizationSource` as soon as it
    /// changes so the UI re-reads its strings without a relaunch.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            LocalizationSource.use(language)
            UserDefaults.standard.set(language.rawValue, forKey: Key.language)
            onChange?()
        }
    }

    /// Which window each provider's ring shows, keyed by provider. A missing
    /// entry means "whichever is closest to its limit".
    var pinnedWindows: [String: String] {
        didSet {
            guard pinnedWindows != oldValue else { return }
            UserDefaults.standard.set(pinnedWindows, forKey: Key.pinnedWindows)
            onChange?()
        }
    }

    /// Which browser an account's session cookie is read from, keyed by
    /// account. A missing entry means "whichever, starting with the default
    /// one" — the same shape as `sources`, and for the same reason: naming one
    /// means a failure is *reported* rather than quietly answered from
    /// somewhere the user never signed in.
    var sessionBrowsers: [String: String] {
        didSet {
            guard sessionBrowsers != oldValue else { return }
            UserDefaults.standard.set(sessionBrowsers, forKey: Key.sessionBrowsers)
        }
    }

    /// Which route each provider's figures are read by, keyed by provider. A
    /// missing entry means `.automatic`.
    var sources: [String: String] {
        didSet {
            guard sources != oldValue else { return }
            UserDefaults.standard.set(sources, forKey: Key.sources)
            onChange?()
        }
    }

    /// How often the figures are re-read.
    var refreshInterval: RefreshInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Key.refreshInterval)
            onChange?()
        }
    }

    /// How big the floating panel is drawn.
    var panelSize: PanelSize {
        didSet {
            guard panelSize != oldValue else { return }
            // Applied before the change is announced: whoever reacts to it is
            // going to measure the panel, and it has to already be the new
            // size when they do.
            PanelMetrics.use(panelSize)
            UserDefaults.standard.set(panelSize.rawValue, forKey: Key.panelSize)
            onChange?()
        }
    }

    /// Whether the rail keeps its percent labels while it lies along the top
    /// of the screen.
    ///
    /// Off by default. Against a side of the screen the label sits under its
    /// ring and costs nothing; along the top it is a second line of type
    /// directly under the menu bar, which turns a compact pill into a banner.
    /// The number is a hover away on the card either way.
    var topRailShowsPercentages: Bool {
        didSet {
            guard topRailShowsPercentages != oldValue else { return }
            // Before the change is announced, for the same reason `panelSize`
            // does it: this changes the rail's thickness, and whoever reacts
            // is about to measure the panel.
            PanelMetrics.showTopPercentages(topRailShowsPercentages)
            UserDefaults.standard.set(topRailShowsPercentages, forKey: Key.topRailShowsPercentages)
            onChange?()
        }
    }

    /// Whether the rail keeps its percent labels down a side of the screen.
    ///
    /// On by default, which is the opposite of the top rail's. Against a side
    /// the label sits under its ring and costs only the rail's length; across
    /// the top it is a second line of type directly under the menu bar. Same
    /// control, opposite defaults, for that reason.
    var sideRailShowsPercentages: Bool {
        didSet {
            guard sideRailShowsPercentages != oldValue else { return }
            // Before the change is announced, like `panelSize`: whoever reacts
            // is about to measure the rail, and it just got shorter or longer.
            PanelMetrics.showSidePercentages(sideRailShowsPercentages)
            UserDefaults.standard.set(sideRailShowsPercentages, forKey: Key.sideRailShowsPercentages)
            onChange?()
        }
    }

    /// Liquid Glass instead of flat black for the panel's surfaces.
    ///
    /// Off by default because a solid surface is legible over anything, and
    /// glass takes on whatever is behind it — see `PanelSurface`.
    ///
    /// **The drag fault this used to carry a warning about was probably never
    /// the material's.** With glass on, the panel could be dragged by its rings
    /// and nowhere else; that was read as macOS 26's material swallowing input
    /// outside SwiftUI's hit-testing chain
    /// (developer.apple.com/forums/thread/816366), and `.allowsHitTesting(false)`,
    /// `.disabled(true)` and opaque ink above and below the material were all
    /// tried against it. The same symptom then turned up on the plain black
    /// panel, where no material is involved: the surface had been taken out of
    /// hit testing, so nothing claimed the gaps between the rings and the
    /// window was never handed the press. Both are fixed by claiming it again
    /// and taking the drag in `FloatingPanel.sendEvent`, which runs before any
    /// view — including anything the material installs — sees the event.
    ///
    /// Worth keeping from that hunt: `hitTest` and synthesised `NSEvent`s both
    /// reported the handle as perfectly reachable throughout. Neither can
    /// answer whether a real click arrives.
    var usesGlass: Bool {
        didSet {
            guard usesGlass != oldValue else { return }
            UserDefaults.standard.set(usesGlass, forKey: Key.usesGlass)
            onChange?()
        }
    }

    /// Whether the rail hides down to a sliver when the pointer is elsewhere.
    ///
    /// On by default. The panel sits over whatever else is on screen all day,
    /// and most of that time nobody is reading it — but it stays reachable at
    /// the edge, and the sliver still changes colour when a limit is nearly
    /// gone, so hiding it never hides bad news.
    var autoCollapse: Bool {
        didSet {
            guard autoCollapse != oldValue else { return }
            UserDefaults.standard.set(autoCollapse, forKey: Key.autoCollapse)
            onChange?()
        }
    }

    /// Called after any change that the AppKit side has to react to — showing
    /// or hiding the panel, or resizing it because the rail got shorter.
    var onChange: (() -> Void)?

    init(
        isPanelVisible: Bool = true,
        hidesInFullScreen: Bool = true,
        enabledAccounts: Set<String> = Set(Provider.allCases.map(\.rawValue)),
        extraAccounts: [ExtraAccount] = [],
        providerOrder: [String] = [],
        language: AppLanguage = .system,
        pinnedWindows: [String: String] = [:],
        sources: [String: String] = [:],
        sessionBrowsers: [String: String] = [:],
        refreshInterval: RefreshInterval = .default,
        autoCollapse: Bool = true,
        panelSize: PanelSize = .default,
        usesGlass: Bool = false,
        topRailShowsPercentages: Bool = false,
        sideRailShowsPercentages: Bool = true
    ) {
        self.isPanelVisible = isPanelVisible
        self.hidesInFullScreen = hidesInFullScreen
        self.enabledAccounts = enabledAccounts
        self.extraAccounts = extraAccounts
        self.providerOrder = providerOrder
        self.language = language
        self.pinnedWindows = pinnedWindows
        self.sources = sources
        self.sessionBrowsers = sessionBrowsers
        self.refreshInterval = refreshInterval
        self.autoCollapse = autoCollapse
        self.panelSize = panelSize
        self.usesGlass = usesGlass
        self.topRailShowsPercentages = topRailShowsPercentages
        self.sideRailShowsPercentages = sideRailShowsPercentages
    }

    func source(for account: AccountKey) -> UsageSource {
        sources[account.id].flatMap(UsageSource.init(rawValue:)) ?? .automatic
    }

    func setSource(_ source: UsageSource, for account: AccountKey) {
        var updated = sources
        updated[account.id] = source == .automatic ? nil : source.rawValue
        sources = updated
    }

    /// The browser an account's session is read from, or nil for "whichever".
    func sessionBrowser(for account: AccountKey) -> BrowserCookies.Browser? {
        sessionBrowsers[account.id].flatMap(BrowserCookies.Browser.init(rawValue:))
    }

    func setSessionBrowser(_ browser: BrowserCookies.Browser?, for account: AccountKey) {
        var updated = sessionBrowsers
        updated[account.id] = browser?.rawValue
        sessionBrowsers = updated
    }

    /// The window pinned for an account, if any.
    func pinnedWindow(for account: AccountKey) -> String? {
        pinnedWindows[account.id]
    }

    func setPinnedWindow(_ id: String?, for account: AccountKey) {
        var updated = pinnedWindows
        updated[account.id] = id
        pinnedWindows = updated
    }

    /// Puts the stored language into effect. Deliberately not done in `init`:
    /// that would let any throwaway instance — a SwiftUI preview, say — reset
    /// the language the app is actually running in.
    func applyLanguage() {
        LocalizationSource.use(language)
    }

    static func restored() -> AppSettings {
        let defaults = UserDefaults.standard

        let visible = defaults.object(forKey: Key.panelVisible) as? Bool ?? true

        let stored = defaults.stringArray(forKey: Key.enabledProviders) ?? []
        let previouslyOffered = defaults.stringArray(forKey: Key.offeredProviders)

        let extras = (defaults.data(forKey: Key.extraAccounts))
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) } ?? []
        // Whichever added accounts were switched on stays switched on. The
        // rules below decide only which providers' *first* accounts appear,
        // which is all they ever decided.
        let enabledExtras = Set(stored).intersection(Set(extras.map(\.id)))

        // A provider's first account has the provider's own raw value as its
        // id, so a list written before accounts existed parses here unchanged.
        var providers = Set(stored.compactMap(Provider.init(rawValue:)))

        // "Has Pulse ever run here" cannot be read off the enabled set: 1.0.0
        // computed that set and never wrote it, so it is absent for everyone
        // upgrading. `hasRun` is absent for them too, being new. What 1.0.0
        // *did* write is the offered list — so its presence is the evidence,
        // and this flag takes over from the next launch onwards.
        let hasRunBefore = defaults.bool(forKey: Key.hasRun) || previouslyOffered != nil
        defaults.set(true, forKey: Key.hasRun)

        if hasRunBefore {
            // An upgrade with nothing stored is 1.0.0's own default, which was
            // every provider it knew about — that is what those users have
            // been looking at, and it is what they keep.
            if stored.isEmpty, let previouslyOffered {
                providers = Set(previouslyOffered.compactMap(Provider.init(rawValue:)))
            }

            // Then a provider added since is switched on once. This has to run
            // *before* the offered list is stamped, or the very providers it
            // exists for are marked offered without ever appearing.
            let offered = Set(previouslyOffered ?? [])
            providers.formUnion(Provider.allCases.filter { !offered.contains($0.rawValue) })
        } else {
            // A genuinely new Mac starts with what is installed. Nothing found
            // at all falls back to everything: the user should still see what
            // Pulse supports.
            let installed = Provider.installedOnThisMac()
            providers = installed.isEmpty ? Set(Provider.allCases) : installed
        }

        defaults.set(Provider.allCases.map(\.rawValue), forKey: Key.offeredProviders)

        // Never empty. A stored list whose names no longer parse — a provider
        // renamed or removed — would otherwise leave a rail with nothing to
        // hover and nothing to grab.
        if providers.isEmpty { providers = Set(Provider.allCases) }

        let accounts = Set(providers.map { AccountKey($0).id }).union(enabledExtras)
        defaults.set(Array(accounts), forKey: Key.enabledProviders)

        let language = defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        let settings = AppSettings(
            isPanelVisible: visible,
            hidesInFullScreen: defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? true,
            enabledAccounts: accounts,
            extraAccounts: extras,
            providerOrder: defaults.stringArray(forKey: Key.providerOrder) ?? [],
            language: language,
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:],
            sources: defaults.dictionary(forKey: Key.sources) as? [String: String] ?? [:],
            sessionBrowsers: defaults.dictionary(forKey: Key.sessionBrowsers) as? [String: String] ?? [:],
            refreshInterval: (defaults.object(forKey: Key.refreshInterval) as? Int)
                .flatMap(RefreshInterval.init(rawValue:)) ?? .default,
            autoCollapse: defaults.object(forKey: Key.autoCollapse) as? Bool ?? true,
            panelSize: defaults.string(forKey: Key.panelSize)
                .flatMap(PanelSize.init(rawValue:)) ?? .default,
            usesGlass: defaults.object(forKey: Key.usesGlass) as? Bool ?? false,
            topRailShowsPercentages: defaults.object(forKey: Key.topRailShowsPercentages) as? Bool ?? false,
            sideRailShowsPercentages: defaults.object(forKey: Key.sideRailShowsPercentages) as? Bool ?? true
        )
        settings.applyLanguage()
        PanelMetrics.use(settings.panelSize)
        PanelMetrics.showTopPercentages(settings.topRailShowsPercentages)
        PanelMetrics.showSidePercentages(settings.sideRailShowsPercentages)
        PanelMetrics.makeRoom(for: settings.allAccounts.count)
        return settings
    }

    func isEnabled(_ account: AccountKey) -> Bool {
        enabledAccounts.contains(account.id)
    }

    func setEnabled(_ isEnabled: Bool, for account: AccountKey) {
        if isEnabled {
            enabledAccounts.insert(account.id)
        } else {
            enabledAccounts.remove(account.id)
        }
    }

    /// The accounts the rail is actually showing, in the user's order — which
    /// is what everything measuring or hit-testing the rail has to agree on.
    var shownAccounts: [AccountKey] { orderedAccounts.filter(isEnabled) }

    /// Adds an account Pulse has just signed in to, switched on and last in
    /// the rail. The slot is generated here so it can never collide with one
    /// that has been removed.
    @discardableResult
    func addAccount(_ provider: Provider, label: String, slot: String = UUID().uuidString) -> AccountKey {
        let account = ExtraAccount(provider: provider, slot: slot, label: label)
        extraAccounts.append(account)
        enabledAccounts.insert(account.id)
        return account.key
    }

    /// Forgets an account, and everything stored against it — a later account
    /// must never inherit a removed one's pinned window or route.
    func removeAccount(_ account: AccountKey) {
        guard !account.isPrimary else { return }

        extraAccounts.removeAll { $0.key == account }
        enabledAccounts.remove(account.id)
        providerOrder.removeAll { $0 == account.id }
        pinnedWindows[account.id] = nil
        sources[account.id] = nil
    }

    func rename(_ account: AccountKey, to label: String) {
        guard let index = extraAccounts.firstIndex(where: { $0.key == account }) else { return }
        extraAccounts[index].label = label
    }

    private enum Key {
        static let panelVisible = "settings.panelVisible"
        static let extraAccounts = "settings.extraAccounts"
        static let hidesInFullScreen = "settings.hidesInFullScreen"
        static let enabledProviders = "settings.enabledProviders"
        static let language = "settings.language"
        static let pinnedWindows = "settings.pinnedWindows"
        static let sources = "settings.sources"
        static let sessionBrowsers = "settings.sessionBrowsers"
        // Bumped when `.automatic` arrived and became the default: the old
        // key holds a fixed number of seconds for anyone who ran an earlier
        // build, which would quietly keep them on the cadence the new default
        // exists to replace.
        static let refreshInterval = "settings.refreshInterval.v2"
        static let autoCollapse = "settings.autoCollapse"
        static let panelSize = "settings.panelSize"
        static let usesGlass = "settings.usesGlass"
        static let topRailShowsPercentages = "settings.topRailShowsPercentages"
        static let sideRailShowsPercentages = "settings.sideRailShowsPercentages"
        static let offeredProviders = "settings.offeredProviders"
        static let providerOrder = "settings.providerOrder"
        /// Set the first time Pulse runs on this Mac, and never cleared.
        static let hasRun = "settings.hasRun"
    }
}
