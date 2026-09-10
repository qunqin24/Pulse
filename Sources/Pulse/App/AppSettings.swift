import Foundation
import Observation
import SwiftUI

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

    /// Whether the panel moves itself onto whichever display the pointer is on.
    ///
    /// Off by default: with one display it can do nothing, and with two it
    /// overrides a position the user chose by dragging the panel there. There
    /// is still exactly **one** panel — this carries it across, it does not put
    /// a copy on every screen.
    ///
    /// "Active" means the display holding the pointer, and only that. Reading
    /// the focused window's display instead would follow other apps around,
    /// which is the opposite of what this is for.
    var followsActiveDisplay: Bool {
        didSet {
            guard followsActiveDisplay != oldValue else { return }
            UserDefaults.standard.set(followsActiveDisplay, forKey: Key.followsActiveDisplay)
            onChange?()
        }
    }

    /// Where DeepSeek's ring gets its denominator.
    ///
    /// DeepSeek reports a prepaid balance and no allowance at all, so unlike
    /// every other provider there is no percentage to show until something
    /// supplies one. Three modes, one setting, and the card always names which
    /// is in force — see `DeepSeekBasis`. Scalars rather than the per-account
    /// dictionaries beside them because DeepSeek has no second account.
    var deepSeekBasis: DeepSeekBasis {
        didSet {
            guard deepSeekBasis != oldValue else { return }
            UserDefaults.standard.set(deepSeekBasis.rawValue, forKey: Key.deepSeekBasis)
            onChange?()
        }
    }

    /// What the reader calls a full tank, for `DeepSeekBasis.budget`. Nil until
    /// they say, which leaves that mode showing the balance and no fraction.
    var deepSeekBudget: Double? {
        didSet {
            guard deepSeekBudget != oldValue else { return }
            UserDefaults.standard.set(deepSeekBudget, forKey: Key.deepSeekBudget)
            onChange?()
        }
    }

    /// Which currency the ring follows when the account holds more than one.
    /// Nil takes the first the reply lists with money in it.
    var deepSeekCurrency: String? {
        didSet {
            guard deepSeekCurrency != oldValue else { return }
            UserDefaults.standard.set(deepSeekCurrency, forKey: Key.deepSeekCurrency)
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
            PanelMetrics.makeRoom(for: railSlotCount)
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

    /// Whether the rail is in an order somebody chose, rather than the one it
    /// ships with.
    ///
    /// Compared against the accounts themselves, not against whether anything
    /// is stored: dragging a row down and back up again leaves a full stored
    /// list that happens to match the default exactly, and offering to reset
    /// an order that is already the default is a button that does nothing.
    var hasCustomOrder: Bool { orderedAccounts != allAccounts }

    /// Back to declaration order.
    ///
    /// By clearing the stored list rather than writing the default into it, so
    /// a provider added in a later version keeps arriving at the bottom of the
    /// rail instead of being pinned by a list written before it existed —
    /// which is the whole reason `orderedAccounts` appends what it doesn't
    /// recognise.
    func resetOrder() { providerOrder = [] }

    /// Drops an account into the place another one currently holds.
    ///
    /// The standard "take its place" behaviour, and it reads in both
    /// directions because the indices shift underneath it: dragging *down*
    /// onto a row lands after it (the target moved up when the dragged row was
    /// lifted out), dragging *up* onto a row lands before it. Both are what
    /// the pointer was pointing at.
    func move(_ account: AccountKey, onto target: AccountKey) {
        guard account != target else { return }

        var order = orderedAccounts
        guard
            let from = order.firstIndex(of: account),
            let to = order.firstIndex(of: target)
        else { return }

        order.remove(at: from)
        order.insert(account, at: min(to, order.count))
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

    /// A colour chosen for an account's ring, keyed by account. A missing
    /// entry means the ring is coloured by how much of its limit is gone,
    /// which is the default and the one that means something.
    var ringTints: [String: String] {
        didSet {
            guard ringTints != oldValue else { return }
            UserDefaults.standard.set(ringTints, forKey: Key.ringTints)
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

    /// How much air there is between the rings.
    var railSpacing: RailSpacing {
        didSet {
            guard railSpacing != oldValue else { return }
            // Before the change is announced, like `panelSize`: whoever reacts
            // is about to measure the rail.
            PanelMetrics.use(railSpacing)
            UserDefaults.standard.set(railSpacing.rawValue, forKey: Key.railSpacing)
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

    /// Whether the percent label sits above its ring rather than below it.
    ///
    /// Below by default: the ring is what the rail is for and reads first,
    /// with the figure confirming it underneath. Above suits anyone who reads
    /// the number first — and against the top of the screen it puts the ring
    /// nearer the desktop rather than the number.
    ///
    /// This moves where a ring's centre sits inside its item, so like the
    /// other rail metrics it is set on `PanelMetrics` before the change is
    /// announced: whoever reacts is about to measure the panel, and the hit
    /// testing has to agree with the drawing.
    var labelAboveRing: Bool {
        didSet {
            guard labelAboveRing != oldValue else { return }
            PanelMetrics.putLabelAboveRing(labelAboveRing)
            UserDefaults.standard.set(labelAboveRing, forKey: Key.labelAboveRing)
            onChange?()
        }
    }

    /// Whether each ring also shows how far through its window the clock is.
    ///
    /// Off by default. It is a genuinely useful second reading — 80% spent a
    /// fifth of the way in means running out, 80% spent with minutes left
    /// means it was budgeted about right — but it is a second thing to read
    /// on a mark that is 36pt across, and the rail's whole case is that one
    /// glance is enough. Asked for, so it is offered; not assumed.
    ///
    /// Unlike the other panel settings this changes nothing about the layout —
    /// the arc is drawn in the margin the rail already has around a ring — so
    /// it needs no `PanelMetrics` entry and nothing has to be re-measured.
    var showsWindowClock: Bool {
        didSet {
            guard showsWindowClock != oldValue else { return }
            UserDefaults.standard.set(showsWindowClock, forKey: Key.showsWindowClock)
        }
    }

    /// Show what is **left** rather than what is gone.
    ///
    /// The same reading either way — 12% used and 88% left are one fact — but
    /// which of the two a person wants at a glance is genuinely a matter of
    /// how they think about a budget, so it is offered rather than argued
    /// about. Spent is the default because that is what the providers
    /// themselves report and what every limit is expressed in.
    ///
    /// **The ring turns over with the figure, and its colour does not.** A
    /// number reading 88% beside an arc drawn at 12% is the same reading
    /// disagreeing with itself, so the arc shows what is left too — but colour
    /// on these rings means how close the limit is, and that does not change
    /// because the number was flipped. So a nearly empty ring is still red.
    ///
    /// Like `showsWindowClock` this changes nothing about the layout: "100%"
    /// is the widest either way round, so no `PanelMetrics` entry and nothing
    /// to re-measure.
    var showsRemaining: Bool {
        didSet {
            guard showsRemaining != oldValue else { return }
            UserDefaults.standard.set(showsRemaining, forKey: Key.showsRemaining)
        }
    }

    /// Say on the card whether each limit will last its window.
    ///
    /// Off by default, and that is the same judgement the window clock gets:
    /// it is the one line on that card the provider did not report, and a
    /// projection nobody asked for sitting under a reported figure invites
    /// being read as one. Someone who wants it turns it on knowing what it is.
    /// **A `PanelMetrics` entry, unlike the other two card settings**: this one
    /// adds a fourth line under every limit, and the panel's frame is worked
    /// out from `DetailCardLayout` before SwiftUI lays anything out. The
    /// metric is set before the change is announced, so whoever re-places the
    /// panel measures the size it is about to be.
    var showsForecast: Bool {
        didSet {
            guard showsForecast != oldValue else { return }
            PanelMetrics.showForecast(showsForecast)
            UserDefaults.standard.set(showsForecast, forKey: Key.showsForecast)
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

    /// How full a limit gets before Pulse posts a notification about it.
    ///
    /// Off by default, like every other setting that makes Pulse do something
    /// unprompted. Whatever step is chosen, a limit the provider reports as
    /// **spent** is always the second one — the two are one setting because
    /// wanting the warning and not wanting to hear that it happened is not a
    /// combination anybody has.
    var alertThreshold: AlertThreshold {
        didSet {
            guard alertThreshold != oldValue else { return }
            UserDefaults.standard.set(alertThreshold.rawValue, forKey: Key.alertThreshold)
        }
    }

    /// Say when a limit that was warned about has come back.
    ///
    /// Depends on `alertThreshold`, and the settings pane greys it out to say
    /// so: a reset is only announced for a window Pulse had already mentioned
    /// on the way up, so with the threshold off there is nothing this can fire
    /// about. See `AlertMemory` for why it is tied that way.
    var alertsOnReset: Bool {
        didSet {
            guard alertsOnReset != oldValue else { return }
            UserDefaults.standard.set(alertsOnReset, forKey: Key.alertsOnReset)
        }
    }

    /// Say when several passes in a row have failed to read an account.
    ///
    /// The one alert that is about Pulse rather than about usage. A failed
    /// fetch falls back to the last good reading, which is the right thing to
    /// show and also the reason the fault is invisible: the panel goes on
    /// displaying perfectly plausible figures with only a "last read" time to
    /// give it away.
    var alertsOnFailure: Bool {
        didSet {
            guard alertsOnFailure != oldValue else { return }
            UserDefaults.standard.set(alertsOnFailure, forKey: Key.alertsOnFailure)
        }
    }

    /// Whether anything at all would be posted. What decides if permission is
    /// worth asking for.
    var wantsAlerts: Bool {
        alertThreshold != .off || alertsOnReset || alertsOnFailure
    }

    /// A second, smaller ring inside the first, for the next-fullest limit.
    ///
    /// Off by default. The ring is the one thing on this panel somebody reads
    /// without stopping, and two arcs is twice as much to take in — the card
    /// is a hover away and already lists every limit. Someone who wants both
    /// at a glance turns it on knowing what it costs.
    ///
    /// **Not a `PanelMetrics` entry**, unlike the other ring settings. What
    /// moves inside the ring is decided from the reading itself — the view
    /// only rearranges when there is a second limit to draw — so a copy of
    /// this flag in the metrics was written on every change and read by
    /// nothing.
    var showsSecondRing: Bool {
        didSet {
            guard showsSecondRing != oldValue else { return }
            UserDefaults.standard.set(showsSecondRing, forKey: Key.showsSecondRing)
            onChange?()
        }
    }

    /// Accounts whose limits are drawn as one ring per model group, as ids.
    ///
    /// Off for everyone by default. Only a provider that actually reports more
    /// than one group can be split — `Provider.splitsByModelGroup` — and today
    /// that is Antigravity alone: its plan carries a Gemini allowance and a
    /// separate one for Claude and GPT, and a single ring can only ever show
    /// the worse of the two.
    var splitAccounts: Set<String> {
        didSet {
            guard splitAccounts != oldValue else { return }
            // The rail is about to get longer. Before the change is announced,
            // so whoever re-measures the panel sees the size it will be.
            PanelMetrics.makeRoom(for: railSlotCount)
            UserDefaults.standard.set(Array(splitAccounts), forKey: Key.splitAccounts)
            onChange?()
        }
    }

    func isSplit(_ account: AccountKey) -> Bool {
        account.provider.splitsByModelGroup && splitAccounts.contains(account.id)
    }

    func setSplit(_ split: Bool, for account: AccountKey) {
        var updated = splitAccounts
        if split { updated.insert(account.id) } else { updated.remove(account.id) }
        splitAccounts = updated
    }

    /// How many rings the rail has to have room for.
    ///
    /// **Every account, not only the shown ones** — the same rule the count
    /// this replaces followed, because the panel keeps its maximum frame while
    /// the rail shrinks inside it. A split account is counted for the groups it
    /// can produce rather than the groups a reading happens to carry, so the
    /// budget does not move when a provider answers with one group short.
    var railSlotCount: Int {
        allAccounts.reduce(0) { total, account in
            total + (isSplit(account) ? account.provider.modelGroupCount : 1)
        }
    }

    /// Called after any change that the AppKit side has to react to — showing
    /// or hiding the panel, or resizing it because the rail got shorter.
    var onChange: (() -> Void)?

    init(
        isPanelVisible: Bool = true,
        hidesInFullScreen: Bool = true,
        followsActiveDisplay: Bool = false,
        deepSeekBasis: DeepSeekBasis = .default,
        deepSeekBudget: Double? = nil,
        deepSeekCurrency: String? = nil,
        enabledAccounts: Set<String> = Set(Provider.allCases.map(\.rawValue)),
        extraAccounts: [ExtraAccount] = [],
        providerOrder: [String] = [],
        language: AppLanguage = .system,
        pinnedWindows: [String: String] = [:],
        sources: [String: String] = [:],
        sessionBrowsers: [String: String] = [:],
        ringTints: [String: String] = [:],
        refreshInterval: RefreshInterval = .default,
        autoCollapse: Bool = true,
        panelSize: PanelSize = .default,
        railSpacing: RailSpacing = .default,
        usesGlass: Bool = false,
        topRailShowsPercentages: Bool = false,
        sideRailShowsPercentages: Bool = true,
        labelAboveRing: Bool = false,
        showsWindowClock: Bool = false,
        showsRemaining: Bool = false,
        showsForecast: Bool = false,
        showsSecondRing: Bool = false,
        splitAccounts: Set<String> = [],
        alertThreshold: AlertThreshold = .default,
        alertsOnReset: Bool = false,
        alertsOnFailure: Bool = false
    ) {
        self.isPanelVisible = isPanelVisible
        self.hidesInFullScreen = hidesInFullScreen
        self.followsActiveDisplay = followsActiveDisplay
        self.deepSeekBasis = deepSeekBasis
        self.deepSeekBudget = deepSeekBudget
        self.deepSeekCurrency = deepSeekCurrency
        self.enabledAccounts = enabledAccounts
        self.extraAccounts = extraAccounts
        self.providerOrder = providerOrder
        self.language = language
        self.pinnedWindows = pinnedWindows
        self.sources = sources
        self.sessionBrowsers = sessionBrowsers
        self.ringTints = ringTints
        self.refreshInterval = refreshInterval
        self.autoCollapse = autoCollapse
        self.panelSize = panelSize
        self.railSpacing = railSpacing
        self.usesGlass = usesGlass
        self.topRailShowsPercentages = topRailShowsPercentages
        self.sideRailShowsPercentages = sideRailShowsPercentages
        self.labelAboveRing = labelAboveRing
        self.showsWindowClock = showsWindowClock
        self.showsRemaining = showsRemaining
        self.showsForecast = showsForecast
        self.showsSecondRing = showsSecondRing
        self.splitAccounts = splitAccounts
        self.alertThreshold = alertThreshold
        self.alertsOnReset = alertsOnReset
        self.alertsOnFailure = alertsOnFailure
    }

    /// A stored route the provider doesn't offer resolves to `.automatic`
    /// rather than being handed on. Routes are keyed by account and providers
    /// gain and lose them between versions, so a list saved while one existed
    /// would otherwise pin a provider to a route that can only fail.
    func source(for account: AccountKey) -> UsageSource {
        let stored = sources[account.id].flatMap(UsageSource.init(rawValue:)) ?? .automatic
        return UsageSource.options(for: account).contains(stored) ? stored : .automatic
    }

    func setSource(_ source: UsageSource, for account: AccountKey) {
        var updated = sources
        updated[account.id] = source == .automatic ? nil : source.rawValue
        sources = updated
    }

    /// The colour chosen for an account's ring, or nil to colour it by usage.
    func ringTint(for account: AccountKey) -> Color? {
        RingTint.color(from: ringTints[account.id])
    }

    func setRingTint(_ colour: Color?, for account: AccountKey) {
        // A colour that will not convert to sRGB has no hex, and storing that
        // nil would *remove* the key — silently putting the account back on
        // Automatic and taking the colour row off the pane, which reads as the
        // picker having refused to work. Keep whatever was chosen last
        // instead; only an explicit nil clears it.
        guard let colour else {
            var updated = ringTints
            updated[account.id] = nil
            ringTints = updated
            return
        }
        guard let hex = colour.hexString else { return }

        var updated = ringTints
        updated[account.id] = hex
        ringTints = updated
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

    /// What is on the rail, for a command that must not disturb anything.
    ///
    /// **Reads and never writes**, which is the whole reason it is not
    /// `restored()`. That one stamps `hasRun`, the offered list and the
    /// resolved enabled set on its way through — correct once at launch, and
    /// wrong for something a status line runs every few seconds. It also puts
    /// the language into effect and re-measures `PanelMetrics`, neither of
    /// which a command printing JSON has any business doing.
    ///
    /// Nothing is resolved or defaulted either: an installation that has never
    /// run the app has nothing stored, and the honest answer for it is an
    /// empty rail rather than a guess at what would be switched on.
    struct StoredRail: Sendable {
        /// Enabled accounts, in the order the rail draws them.
        let accounts: [AccountKey]
        /// What the user calls an added account.
        let labels: [String: String]
        /// The window each account's ring is pinned to, if any.
        let pinnedWindows: [String: String]
    }

    static func storedRail() -> StoredRail {
        let defaults = UserDefaults.standard

        let extras = defaults.data(forKey: Key.extraAccounts)
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) } ?? []
        let known = Provider.allCases.flatMap { provider in
            [AccountKey(provider)] + extras.filter { $0.provider == provider }.map(\.key)
        }

        let enabled = Set(defaults.stringArray(forKey: Key.enabledProviders) ?? [])
        // Same resolution as `orderedAccounts`: stored order first, then
        // anything it doesn't mention, so a provider added since a stored list
        // was written comes last rather than vanishing.
        let stored = (defaults.stringArray(forKey: Key.providerOrder) ?? [])
            .compactMap(AccountKey.init(id:))
            .filter(known.contains)
        let ordered = stored + known.filter { !stored.contains($0) }

        return StoredRail(
            accounts: ordered.filter { enabled.contains($0.id) },
            // `uniqueKeysWithValues` **traps** on a duplicate, and this
            // dictionary is built from a file anyone can edit — in the one
            // command a status line runs every couple of seconds. Everywhere
            // else in the app tolerates duplicates (`label(for:)` takes the
            // first), so crashing here would be the only place that doesn't.
            labels: Dictionary(extras.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first }),
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:]
        )
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
            //
            // **Only if it can actually report something.** One that needs a
            // key Pulse hasn't got would take a place on the rail to say
            // "enter an API key in Settings" about a service the person may
            // not even have an account with. It is still marked offered, so
            // this stays a decision taken once: it appears when it is switched
            // on in Settings, not the next time the app happens to launch.
            let offered = Set(previouslyOffered ?? [])
            providers.formUnion(Provider.allCases.filter {
                !offered.contains($0.rawValue) && $0.canReportWithoutSetup
            })
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
        //
        // What must not be empty is the **rail**, not this set: an added
        // account is switched on through `enabledExtras` and is not a provider
        // here, so someone monitoring a second Codex login and nothing else
        // has an empty `providers` and a perfectly full rail. Rebuilding from
        // `allCases` there switched all seven back on *and wrote it to disk*,
        // destroying the choice rather than merely misdrawing it.
        if providers.isEmpty && enabledExtras.isEmpty { providers = Set(Provider.allCases) }

        let accounts = Set(providers.map { AccountKey($0).id }).union(enabledExtras)
        defaults.set(Array(accounts), forKey: Key.enabledProviders)

        let language = defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        let settings = AppSettings(
            isPanelVisible: visible,
            hidesInFullScreen: defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? true,
            followsActiveDisplay: defaults.object(forKey: Key.followsActiveDisplay) as? Bool ?? false,
            deepSeekBasis: defaults.string(forKey: Key.deepSeekBasis)
                .flatMap(DeepSeekBasis.init(rawValue:)) ?? .default,
            deepSeekBudget: defaults.object(forKey: Key.deepSeekBudget) as? Double,
            deepSeekCurrency: defaults.string(forKey: Key.deepSeekCurrency),
            enabledAccounts: accounts,
            extraAccounts: extras,
            providerOrder: defaults.stringArray(forKey: Key.providerOrder) ?? [],
            language: language,
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:],
            sources: defaults.dictionary(forKey: Key.sources) as? [String: String] ?? [:],
            sessionBrowsers: defaults.dictionary(forKey: Key.sessionBrowsers) as? [String: String] ?? [:],
            ringTints: defaults.dictionary(forKey: Key.ringTints) as? [String: String] ?? [:],
            refreshInterval: (defaults.object(forKey: Key.refreshInterval) as? Int)
                .flatMap(RefreshInterval.init(rawValue:)) ?? .default,
            autoCollapse: defaults.object(forKey: Key.autoCollapse) as? Bool ?? true,
            panelSize: defaults.string(forKey: Key.panelSize)
                .flatMap(PanelSize.init(rawValue:)) ?? .default,
            railSpacing: defaults.string(forKey: Key.railSpacing)
                .flatMap(RailSpacing.init(rawValue:)) ?? .default,
            usesGlass: defaults.object(forKey: Key.usesGlass) as? Bool ?? false,
            topRailShowsPercentages: defaults.object(forKey: Key.topRailShowsPercentages) as? Bool ?? false,
            sideRailShowsPercentages: defaults.object(forKey: Key.sideRailShowsPercentages) as? Bool ?? true,
            labelAboveRing: defaults.object(forKey: Key.labelAboveRing) as? Bool ?? false,
            showsWindowClock: defaults.object(forKey: Key.showsWindowClock) as? Bool ?? false,
            showsRemaining: defaults.object(forKey: Key.showsRemaining) as? Bool ?? false,
            showsForecast: defaults.object(forKey: Key.showsForecast) as? Bool ?? false,
            showsSecondRing: defaults.object(forKey: Key.showsSecondRing) as? Bool ?? false,
            splitAccounts: Set(defaults.stringArray(forKey: Key.splitAccounts) ?? []),
            alertThreshold: (defaults.object(forKey: Key.alertThreshold) as? Int)
                .flatMap(AlertThreshold.init(rawValue:)) ?? .default,
            alertsOnReset: defaults.object(forKey: Key.alertsOnReset) as? Bool ?? false,
            alertsOnFailure: defaults.object(forKey: Key.alertsOnFailure) as? Bool ?? false
        )
        settings.applyLanguage()
        PanelMetrics.use(settings.panelSize)
        PanelMetrics.use(settings.railSpacing)
        PanelMetrics.showTopPercentages(settings.topRailShowsPercentages)
        PanelMetrics.showSidePercentages(settings.sideRailShowsPercentages)
        PanelMetrics.putLabelAboveRing(settings.labelAboveRing)
        PanelMetrics.showForecast(settings.showsForecast)
        PanelMetrics.makeRoom(for: settings.railSlotCount)
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
        // **The set refuses to go empty, and that refusal put the removed
        // account straight back.** `enabledAccounts` restores its old value
        // rather than accept nothing — so deleting the only enabled account
        // left its id behind, naming an account that no longer exists, and the
        // rail drew nothing at all because `shownAccounts` filters the real
        // ones. The provider this account belonged to takes its place: there
        // is always one, and it is the nearest thing to what was being watched.
        if enabledAccounts == [account.id] {
            enabledAccounts = [AccountKey(account.provider).id]
        } else {
            enabledAccounts.remove(account.id)
        }
        providerOrder.removeAll { $0 == account.id }
        pinnedWindows[account.id] = nil
        sources[account.id] = nil
        ringTints[account.id] = nil
        sessionBrowsers[account.id] = nil
    }

    func rename(_ account: AccountKey, to label: String) {
        guard let index = extraAccounts.firstIndex(where: { $0.key == account }) else { return }
        extraAccounts[index].label = label
    }

    private enum Key {
        static let panelVisible = "settings.panelVisible"
        static let extraAccounts = "settings.extraAccounts"
        static let hidesInFullScreen = "settings.hidesInFullScreen"
        static let followsActiveDisplay = "settings.followsActiveDisplay"
        static let deepSeekBasis = "settings.deepSeekBasis"
        static let deepSeekBudget = "settings.deepSeekBudget"
        static let deepSeekCurrency = "settings.deepSeekCurrency"
        static let enabledProviders = "settings.enabledProviders"
        static let language = "settings.language"
        static let pinnedWindows = "settings.pinnedWindows"
        static let sources = "settings.sources"
        static let sessionBrowsers = "settings.sessionBrowsers"
        static let ringTints = "settings.ringTints"
        // Bumped when `.automatic` arrived and became the default: the old
        // key holds a fixed number of seconds for anyone who ran an earlier
        // build, which would quietly keep them on the cadence the new default
        // exists to replace.
        static let refreshInterval = "settings.refreshInterval.v2"
        static let autoCollapse = "settings.autoCollapse"
        static let panelSize = "settings.panelSize"
        static let railSpacing = "settings.railSpacing"
        static let usesGlass = "settings.usesGlass"
        static let topRailShowsPercentages = "settings.topRailShowsPercentages"
        static let sideRailShowsPercentages = "settings.sideRailShowsPercentages"
        static let labelAboveRing = "settings.labelAboveRing"
        static let showsWindowClock = "settings.showsWindowClock"
        static let showsRemaining = "settings.showsRemaining"
        static let showsForecast = "settings.showsForecast"
        static let showsSecondRing = "settings.showsSecondRing"
        static let splitAccounts = "settings.splitAccounts"
        static let alertThreshold = "settings.alertThreshold"
        static let alertsOnReset = "settings.alertsOnReset"
        static let alertsOnFailure = "settings.alertsOnFailure"
        static let offeredProviders = "settings.offeredProviders"
        static let providerOrder = "settings.providerOrder"
        /// Set the first time Pulse runs on this Mac, and never cleared.
        static let hasRun = "settings.hasRun"
    }
}
