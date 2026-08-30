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

    /// Which providers appear in the rail. Never empty — the last one left
    /// can't be switched off, since an empty rail would leave nothing to
    /// hover, and nothing to grab to drag the panel.
    var enabledProviders: Set<Provider> {
        didSet {
            guard enabledProviders != oldValue else { return }
            if enabledProviders.isEmpty {
                enabledProviders = oldValue
                return
            }
            UserDefaults.standard.set(
                enabledProviders.map(\.rawValue),
                forKey: Key.enabledProviders
            )
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
        enabledProviders: Set<Provider> = Set(Provider.allCases),
        language: AppLanguage = .system,
        pinnedWindows: [String: String] = [:],
        sources: [String: String] = [:],
        refreshInterval: RefreshInterval = .default,
        autoCollapse: Bool = true,
        panelSize: PanelSize = .default,
        usesGlass: Bool = false
    ) {
        self.isPanelVisible = isPanelVisible
        self.hidesInFullScreen = hidesInFullScreen
        self.enabledProviders = enabledProviders
        self.language = language
        self.pinnedWindows = pinnedWindows
        self.sources = sources
        self.refreshInterval = refreshInterval
        self.autoCollapse = autoCollapse
        self.panelSize = panelSize
        self.usesGlass = usesGlass
    }

    func source(for provider: Provider) -> UsageSource {
        sources[provider.rawValue].flatMap(UsageSource.init(rawValue:)) ?? .automatic
    }

    func setSource(_ source: UsageSource, for provider: Provider) {
        var updated = sources
        updated[provider.rawValue] = source == .automatic ? nil : source.rawValue
        sources = updated
    }

    /// The window pinned for a provider, if any.
    func pinnedWindow(for provider: Provider) -> String? {
        pinnedWindows[provider.rawValue]
    }

    func setPinnedWindow(_ id: String?, for provider: Provider) {
        var updated = pinnedWindows
        updated[provider.rawValue] = id
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
        var providers = Set(stored.compactMap(Provider.init(rawValue:)))

        // A provider added in a later version is switched on the first time it
        // is seen, and only then. Without this it would be missing from every
        // stored list and would never appear at all; switching it back on for
        // everyone at each launch would override the user turning it off. So
        // what is remembered is which providers have been *offered*, the same
        // decided-once shape `LoginItem` uses for opening at login.
        let offered = Set(defaults.stringArray(forKey: Key.offeredProviders) ?? [])
        let fresh = Provider.allCases.filter { !offered.contains($0.rawValue) }
        if !stored.isEmpty { providers.formUnion(fresh) }
        defaults.set(Provider.allCases.map(\.rawValue), forKey: Key.offeredProviders)

        let language = defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        let settings = AppSettings(
            isPanelVisible: visible,
            hidesInFullScreen: defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? true,
            enabledProviders: providers.isEmpty ? Set(Provider.allCases) : providers,
            language: language,
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:],
            sources: defaults.dictionary(forKey: Key.sources) as? [String: String] ?? [:],
            refreshInterval: (defaults.object(forKey: Key.refreshInterval) as? Int)
                .flatMap(RefreshInterval.init(rawValue:)) ?? .default,
            autoCollapse: defaults.object(forKey: Key.autoCollapse) as? Bool ?? true,
            panelSize: defaults.string(forKey: Key.panelSize)
                .flatMap(PanelSize.init(rawValue:)) ?? .default,
            usesGlass: defaults.object(forKey: Key.usesGlass) as? Bool ?? false
        )
        settings.applyLanguage()
        PanelMetrics.use(settings.panelSize)
        return settings
    }

    func isEnabled(_ provider: Provider) -> Bool {
        enabledProviders.contains(provider)
    }

    func setEnabled(_ isEnabled: Bool, for provider: Provider) {
        if isEnabled {
            enabledProviders.insert(provider)
        } else {
            enabledProviders.remove(provider)
        }
    }

    private enum Key {
        static let panelVisible = "settings.panelVisible"
        static let hidesInFullScreen = "settings.hidesInFullScreen"
        static let enabledProviders = "settings.enabledProviders"
        static let language = "settings.language"
        static let pinnedWindows = "settings.pinnedWindows"
        static let sources = "settings.sources"
        // Bumped when `.automatic` arrived and became the default: the old
        // key holds a fixed number of seconds for anyone who ran an earlier
        // build, which would quietly keep them on the cadence the new default
        // exists to replace.
        static let refreshInterval = "settings.refreshInterval.v2"
        static let autoCollapse = "settings.autoCollapse"
        static let panelSize = "settings.panelSize"
        static let usesGlass = "settings.usesGlass"
        static let offeredProviders = "settings.offeredProviders"
    }
}
