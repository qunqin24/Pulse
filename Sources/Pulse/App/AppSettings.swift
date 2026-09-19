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

    /// The key combination that opens settings from anywhere, or nil.
    ///
    /// Deliberately no `onChange`: that is the usage loop's hook and it
    /// refetches every provider when it fires. A shortcut is not a reading.
    /// Whoever sets one tells `GlobalShortcutMonitor` directly, which is the
    /// only thing that has to hear about it.
    var openSettingsShortcut: GlobalShortcut? {
        didSet {
            guard openSettingsShortcut != oldValue else { return }
            UserDefaults.standard.set(openSettingsShortcut?.storage, forKey: Key.openSettingsShortcut)
        }
    }

    /// The key combination that draws the floating panel or takes it away, or
    /// nil. Same rule about `onChange` as the one above.
    var togglePanelShortcut: GlobalShortcut? {
        didSet {
            guard togglePanelShortcut != oldValue else { return }
            UserDefaults.standard.set(togglePanelShortcut?.storage, forKey: Key.togglePanelShortcut)
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

    /// Warn when a prepaid balance falls below this much, per account.
    ///
    /// Empty is off, which is how it ships — the same rule every other alert
    /// follows. Keyed by account id and stored per account rather than as one
    /// figure because the providers that report a balance do not price in the
    /// same currency: ¥20 and $20 are not the same line.
    var lowBalanceAlerts: [String: Double] {
        didSet {
            guard lowBalanceAlerts != oldValue else { return }
            UserDefaults.standard.set(lowBalanceAlerts, forKey: Key.lowBalanceAlerts)
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

    /// Every account, in the user's order.
    ///
    /// Anything the stored order doesn't mention goes after it, **sorted by
    /// name**. Someone who has arranged the rail keeps their arrangement and a
    /// provider added later lands at the bottom of it; someone who never
    /// touched it — which is everybody until they do — gets the whole list in
    /// alphabetical order rather than in the order the enum happens to be
    /// written in.
    var orderedAccounts: [AccountKey] {
        let known = allAccounts
        let stored = providerOrder.compactMap(AccountKey.init(id:)).filter(known.contains)
        return stored + known.filter { !stored.contains($0) }.sorted(by: byName)
    }

    /// The order accounts fall into before anybody has arranged them: **by the
    /// name on the row**.
    ///
    /// It used to be declaration order, which is the order the providers were
    /// added to the enum over the months — an order with a meaning, but not one
    /// visible from the outside. Seventeen rows arranged by nothing a reader
    /// can see is a list you have to scan rather than one you can look in.
    ///
    /// An added account sorts by the label the user gave it, not by its
    /// provider, because the label is what is written on the row. Two Claude
    /// Code accounts called "Work" and "Personal" belong under W and P.
    ///
    /// `localizedStandardCompare` is Finder's comparison: case- and
    /// accent-insensitive, and it puts any digits in a name in numeric order.
    /// The same one the settings search matches with.
    private func byName(_ a: AccountKey, _ b: AccountKey) -> Bool {
        let left = label(for: a)
        let right = label(for: b)
        // Ids as the tie-break, so two rows that read the same never swap
        // places between launches.
        if left.localizedStandardCompare(right) == .orderedSame { return a.id < b.id }
        return left.localizedStandardCompare(right) == .orderedAscending
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
    /// Whether anybody has actually arranged the rail.
    ///
    /// **Not `orderedAccounts != allAccounts`.** That compared the order shown
    /// against *declaration* order, and since the default became name order the
    /// two differ on a fresh install — so "Reset order" was enabled out of the
    /// box and did nothing when pressed, which is the one thing a control must
    /// never do. The question is whether a stored arrangement exists that still
    /// names something real.
    var hasCustomOrder: Bool {
        !providerOrder.compactMap(AccountKey.init(id:)).filter(allAccounts.contains).isEmpty
    }

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

    /// Which accounts appear in the rail. Empty only until the initial choice
    /// is made; once monitoring starts, the last ring cannot be switched off.
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
            UserDefaults.standard.set(Array(enabledAccounts), forKey: ProviderSelection.enabledKey)
            onChange?()
        }
    }

    var needsProviderSelection: Bool { shownAccounts.isEmpty }

    /// Discovery is metadata only. Neither list enables anything on its own.
    var detectedProviders: Set<Provider> = []
    var suggestedProviders: Set<Provider> = []

    func selectProviders(_ providers: Set<Provider>) {
        guard !providers.isEmpty else { return }
        enabledAccounts.formUnion(providers.map(\.rawValue))
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

    /// Which rings draw an animated mark instead of the provider's logo,
    /// keyed by account. A missing entry means the logo, which is the default.
    ///
    /// **Per account, not one switch for the rail.** A logo says which of
    /// eighteen products a ring belongs to, and a mark gives that up for
    /// motion — which is a trade worth making for the two or three rings
    /// somebody actually watches work, and not for the rest. Per account
    /// rather than per provider for the same reason `ringTints` is: two
    /// accounts of one provider are two rings, and they are told apart by
    /// exactly this kind of choice.
    ///
    /// **The mark takes the CLI-activity arc with it, on that ring only.** A
    /// white travelling arc and a mark that visibly gets to work are one fact
    /// drawn twice.
    var botMarks: [String: Bool] {
        didSet {
            guard botMarks != oldValue else { return }
            UserDefaults.standard.set(botMarks, forKey: Key.botMarks)
        }
    }

    /// The persona chosen for an account's mark, keyed by account. A missing
    /// entry means automatic, which is what almost everyone will leave it on.
    ///
    /// Automatic is dealt by position on the rail, so the ring beside this one
    /// is a different character. Choosing one is for when somebody wants a
    /// particular provider to be the sleepy one.
    var botPersonas: [String: String] {
        didSet {
            guard botPersonas != oldValue else { return }
            UserDefaults.standard.set(botPersonas, forKey: Key.botPersonas)
        }
    }

    /// A colour chosen for an account's **mark**, keyed by account. A missing
    /// entry means the brand colour, or one dealt across the rail.
    ///
    /// Separate from `ringTints` on purpose: the ring means how close the
    /// limit is, the mark means which provider this is, and somebody who
    /// wants a green bot in a red ring is asking for two different things.
    var botColours: [String: String] {
        didSet {
            guard botColours != oldValue else { return }
            UserDefaults.standard.set(botColours, forKey: Key.botColours)
        }
    }

    /// The body shape chosen for an account's mark, keyed by account. A
    /// missing entry is round, which is what every mark is until somebody
    /// changes it.
    ///
    /// **Not dealt like the colours and the personas.** Those are dealt
    /// because two rings that look identical are unreadable, and a colour or a
    /// rhythm says nothing by itself. A shape somebody did not choose would be
    /// the app making a claim about that provider with a silhouette.
    var botShapes: [String: String] {
        didSet {
            guard botShapes != oldValue else { return }
            UserDefaults.standard.set(botShapes, forKey: Key.botShapes)
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

    /// How Pulse's own requests and supported helper processes reach the
    /// network. System is the default so an upgrade changes nothing.
    var networkProxy: NetworkProxySettings {
        didSet {
            guard networkProxy != oldValue else { return }
            Self.storeNetworkProxy(networkProxy, in: .standard)
            NetworkSession.apply(networkProxy)
            onChange?()
        }
    }

    static func storedNetworkProxy(in defaults: UserDefaults) -> NetworkProxySettings {
        guard let data = defaults.data(forKey: Key.networkProxy),
              let settings = try? JSONDecoder().decode(NetworkProxySettings.self, from: data)
        else { return .default }
        return settings
    }

    static func storeNetworkProxy(_ settings: NetworkProxySettings, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Key.networkProxy)
    }

    static var networkProxyDefaultsKey: String { Key.networkProxy }

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

    /// How full a limit has to be before the panel draws it red.
    ///
    /// A setting rather than a constant because "getting tight" is a judgement
    /// about how somebody works, not a fact about the limit: a weekly window
    /// three-quarters gone on a Monday and on a Friday are the same number and
    /// not the same news. It moves the **caution** step's upper edge, nothing
    /// else — green below 50%, yellow up to here, red above it. Spent stays
    /// what the provider reports, and is never a matter of taste.
    ///
    /// No `onChange?()`: nothing about the panel's frame depends on it, and
    /// `@Observable` already redraws whoever read it.
    var warningThreshold: WarningThreshold {
        didSet {
            guard warningThreshold != oldValue else { return }
            UserDefaults.standard.set(warningThreshold.rawValue, forKey: Key.warningThreshold)
        }
    }

    /// Whether the collapsed sliver takes on `warningThreshold`'s colour when
    /// a limit is close.
    ///
    /// On by default. A rail full of accounts that all cross the threshold at
    /// once turns the sliver into a permanent coloured line against the
    /// screen edge — off locks it to its normal, alert-free colour, the same
    /// one it would draw with nothing to report. The rings are unaffected:
    /// this only touches the sliver `FloatingUsagePanelView.alertTint` feeds
    /// `UsageDockView`.
    ///
    /// No `onChange?()`: nothing about the panel's frame depends on it, the
    /// same as `warningThreshold`.
    var dockShowsAlertColor: Bool {
        didSet {
            guard dockShowsAlertColor != oldValue else { return }
            UserDefaults.standard.set(dockShowsAlertColor, forKey: Key.dockShowsAlertColor)
        }
    }

    /// How far back the Token spend pane counts.
    ///
    /// The last **week** until the reader picks another span, and their pick is
    /// kept: the pane answers a sit-down question, and making someone re-choose
    /// the window on every visit is work nobody asked for. No `onChange?()` —
    /// nothing about the panel's frame depends on it, and `@Observable` already
    /// redraws whoever read it, the same as `warningThreshold`.
    var spendSpan: SpendSpan {
        didSet {
            guard spendSpan != oldValue else { return }
            Self.storeSpendSpan(spendSpan, in: .standard)
        }
    }

    /// Local records are read only after this pane is explicitly enabled.
    /// No onChange: that hook refreshes the quota providers.
    var readsTokenSpend: Bool {
        didSet {
            guard readsTokenSpend != oldValue else { return }
            Self.storeReadsTokenSpend(readsTokenSpend, in: .standard)
        }
    }

    static func storedReadsTokenSpend(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Key.readsTokenSpend) as? Bool ?? false
    }

    static func storeReadsTokenSpend(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.readsTokenSpend)
    }

    /// The span last chosen, or `.week` when nothing is stored or what is
    /// stored no longer names an offered range.
    ///
    /// Takes the store as an argument, rather than reaching for
    /// `UserDefaults.standard`, so the round trip can be pinned against an
    /// isolated suite. `restored()` and `spendSpan`'s `didSet` both go through
    /// this and `storeSpendSpan`, so what a test exercises is the one
    /// production uses.
    static func storedSpendSpan(in defaults: UserDefaults) -> SpendSpan {
        defaults.string(forKey: Key.spendSpan)
            .flatMap(SpendSpan.init(rawValue:)) ?? .default
    }

    static func storeSpendSpan(_ span: SpendSpan, in defaults: UserDefaults) {
        defaults.set(span.rawValue, forKey: Key.spendSpan)
    }

    /// The key the chosen span lives under. Internal so a test can store a
    /// value the picker no longer offers and prove the fallback; nothing
    /// outside the module can see it either way.
    static var spendSpanDefaultsKey: String { Key.spendSpan }

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
        alertThreshold != .off || alertsOnReset || alertsOnFailure || !lowBalanceAlerts.isEmpty
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
        openSettingsShortcut: GlobalShortcut? = nil,
        togglePanelShortcut: GlobalShortcut? = nil,
        deepSeekBasis: DeepSeekBasis = .default,
        deepSeekBudget: Double? = nil,
        deepSeekCurrency: String? = nil,
        lowBalanceAlerts: [String: Double] = [:],
        enabledAccounts: Set<String> = Set(Provider.allCases.map(\.rawValue)),
        extraAccounts: [ExtraAccount] = [],
        providerOrder: [String] = [],
        language: AppLanguage = .system,
        pinnedWindows: [String: String] = [:],
        sources: [String: String] = [:],
        sessionBrowsers: [String: String] = [:],
        ringTints: [String: String] = [:],
        botMarks: [String: Bool] = [:],
        botPersonas: [String: String] = [:],
        botShapes: [String: String] = [:],
        botColours: [String: String] = [:],
        refreshInterval: RefreshInterval = .default,
        networkProxy: NetworkProxySettings = .default,
        autoCollapse: Bool = true,
        panelSize: PanelSize = .default,
        railSpacing: RailSpacing = .default,
        usesGlass: Bool = false,
        topRailShowsPercentages: Bool = false,
        sideRailShowsPercentages: Bool = true,
        labelAboveRing: Bool = false,
        showsWindowClock: Bool = false,
        showsRemaining: Bool = false,
        warningThreshold: WarningThreshold = .default,
        dockShowsAlertColor: Bool = true,
        showsForecast: Bool = false,
        showsSecondRing: Bool = false,
        splitAccounts: Set<String> = [],
        spendSpan: SpendSpan = .default,
        readsTokenSpend: Bool = false,
        alertThreshold: AlertThreshold = .default,
        alertsOnReset: Bool = false,
        alertsOnFailure: Bool = false
    ) {
        self.isPanelVisible = isPanelVisible
        self.hidesInFullScreen = hidesInFullScreen
        self.followsActiveDisplay = followsActiveDisplay
        self.openSettingsShortcut = openSettingsShortcut
        self.togglePanelShortcut = togglePanelShortcut
        self.deepSeekBasis = deepSeekBasis
        self.deepSeekBudget = deepSeekBudget
        self.deepSeekCurrency = deepSeekCurrency
        self.lowBalanceAlerts = lowBalanceAlerts
        self.enabledAccounts = enabledAccounts
        self.extraAccounts = extraAccounts
        self.providerOrder = providerOrder
        self.language = language
        self.pinnedWindows = pinnedWindows
        self.sources = sources
        self.sessionBrowsers = sessionBrowsers
        self.ringTints = ringTints
        self.botMarks = botMarks
        self.botPersonas = botPersonas
        self.botShapes = botShapes
        self.botColours = botColours
        self.refreshInterval = refreshInterval
        self.networkProxy = networkProxy
        self.autoCollapse = autoCollapse
        self.panelSize = panelSize
        self.railSpacing = railSpacing
        self.usesGlass = usesGlass
        self.topRailShowsPercentages = topRailShowsPercentages
        self.sideRailShowsPercentages = sideRailShowsPercentages
        self.labelAboveRing = labelAboveRing
        self.showsWindowClock = showsWindowClock
        self.showsRemaining = showsRemaining
        self.warningThreshold = warningThreshold
        self.dockShowsAlertColor = dockShowsAlertColor
        self.showsForecast = showsForecast
        self.showsSecondRing = showsSecondRing
        self.splitAccounts = splitAccounts
        self.spendSpan = spendSpan
        self.readsTokenSpend = readsTokenSpend
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

    /// The balance this account should be warned below, or nil for no warning.
    func lowBalanceAlert(for account: AccountKey) -> Double? {
        lowBalanceAlerts[account.id]
    }

    /// Anything that is not a positive figure clears it: a warning below zero
    /// can never fire, and one at zero fires only once the account is already
    /// empty, which is the moment it is too late to be told.
    func setLowBalanceAlert(_ amount: Double?, for account: AccountKey) {
        var updated = lowBalanceAlerts
        updated[account.id] = amount.flatMap { $0 > 0 ? $0 : nil }
        lowBalanceAlerts = updated
    }

    func setSource(_ source: UsageSource, for account: AccountKey) {
        var updated = sources
        updated[account.id] = source == .automatic ? nil : source.rawValue
        sources = updated
    }

    /// Whether this account's ring draws the animated mark.
    func showsBotMark(for account: AccountKey) -> Bool {
        botMarks[account.id] ?? false
    }

    func setShowsBotMark(_ shows: Bool, for account: AccountKey) {
        var updated = botMarks
        // Off is the default, so it is stored as an absence rather than as a
        // false — the same shape as a cleared ring colour.
        updated[account.id] = shows ? true : nil
        botMarks = updated
    }

    /// The persona chosen for an account's mark, or nil for automatic.
    ///
    /// A stored value that stops parsing — a persona removed in a later
    /// version — reads as automatic rather than as a crash or a blank mark.
    func botPersona(for account: AccountKey) -> BotMarkPersona? {
        botPersonas[account.id].flatMap(BotMarkPersona.init(rawValue:))
    }

    func setBotPersona(_ persona: BotMarkPersona?, for account: AccountKey) {
        var updated = botPersonas
        updated[account.id] = persona?.rawValue
        botPersonas = updated
    }

    /// The colour chosen for an account's mark, or nil for its brand colour.
    func botColour(for account: AccountKey) -> Color? {
        RingTint.color(from: botColours[account.id])
    }

    func setBotColour(_ colour: Color?, for account: AccountKey) {
        // A colour with no hex would store nil and silently put the account
        // back on automatic, which reads as the picker refusing to work —
        // the same trap `setRingTint` documents.
        guard let colour else {
            var updated = botColours
            updated[account.id] = nil
            botColours = updated
            return
        }
        guard let hex = colour.hexString else { return }
        var updated = botColours
        updated[account.id] = hex
        botColours = updated
    }

    /// The shape an account's mark wears. A stored value that no longer
    /// names a shape reads as round rather than as a blank ring.
    func botBody(for account: AccountKey) -> BotMarkBody {
        botShapes[account.id].flatMap(BotMarkBody.init(rawValue:)) ?? .default
    }

    func setBotBody(_ body: BotMarkBody, for account: AccountKey) {
        var updated = botShapes
        // Round is the default, so it is stored as an absence.
        updated[account.id] = body == .default ? nil : body.rawValue
        botShapes = updated
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

        let enabled = Set(defaults.stringArray(forKey: ProviderSelection.enabledKey) ?? [])
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

        let extras = (defaults.data(forKey: Key.extraAccounts))
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) } ?? []
        let detected = Provider.installedOnThisMac()
        let selection = ProviderSelection.restore(
            in: defaults,
            knownAccounts: Set(Provider.allCases.map(\.rawValue)).union(extras.map(\.id)),
            detected: detected
        )

        let language = defaults.string(forKey: Key.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system

        let settings = AppSettings(
            isPanelVisible: visible,
            hidesInFullScreen: defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? true,
            followsActiveDisplay: defaults.object(forKey: Key.followsActiveDisplay) as? Bool ?? false,
            openSettingsShortcut: defaults.string(forKey: Key.openSettingsShortcut)
                .flatMap(GlobalShortcut.init(storage:)),
            togglePanelShortcut: defaults.string(forKey: Key.togglePanelShortcut)
                .flatMap(GlobalShortcut.init(storage:)),
            deepSeekBasis: defaults.string(forKey: Key.deepSeekBasis)
                .flatMap(DeepSeekBasis.init(rawValue:)) ?? .default,
            deepSeekBudget: defaults.object(forKey: Key.deepSeekBudget) as? Double,
            deepSeekCurrency: defaults.string(forKey: Key.deepSeekCurrency),
            lowBalanceAlerts: defaults.dictionary(forKey: Key.lowBalanceAlerts) as? [String: Double] ?? [:],
            enabledAccounts: selection.enabledAccounts,
            extraAccounts: extras,
            providerOrder: defaults.stringArray(forKey: Key.providerOrder) ?? [],
            language: language,
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:],
            sources: defaults.dictionary(forKey: Key.sources) as? [String: String] ?? [:],
            sessionBrowsers: defaults.dictionary(forKey: Key.sessionBrowsers) as? [String: String] ?? [:],
            ringTints: defaults.dictionary(forKey: Key.ringTints) as? [String: String] ?? [:],
            botMarks: defaults.dictionary(forKey: Key.botMarks) as? [String: Bool] ?? [:],
            botPersonas: defaults.dictionary(forKey: Key.botPersonas) as? [String: String] ?? [:],
            botShapes: defaults.dictionary(forKey: Key.botShapes) as? [String: String] ?? [:],
            botColours: defaults.dictionary(forKey: Key.botColours) as? [String: String] ?? [:],
            refreshInterval: (defaults.object(forKey: Key.refreshInterval) as? Int)
                .flatMap(RefreshInterval.init(rawValue:)) ?? .default,
            networkProxy: Self.storedNetworkProxy(in: defaults),
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
            warningThreshold: (defaults.object(forKey: Key.warningThreshold) as? Int)
                .flatMap(WarningThreshold.init(rawValue:)) ?? .default,
            dockShowsAlertColor: defaults.object(forKey: Key.dockShowsAlertColor) as? Bool ?? true,
            showsForecast: defaults.object(forKey: Key.showsForecast) as? Bool ?? false,
            showsSecondRing: defaults.object(forKey: Key.showsSecondRing) as? Bool ?? false,
            splitAccounts: Set(defaults.stringArray(forKey: Key.splitAccounts) ?? []),
            spendSpan: Self.storedSpendSpan(in: defaults),
            readsTokenSpend: Self.storedReadsTokenSpend(in: defaults),
            alertThreshold: (defaults.object(forKey: Key.alertThreshold) as? Int)
                .flatMap(AlertThreshold.init(rawValue:)) ?? .default,
            alertsOnReset: defaults.object(forKey: Key.alertsOnReset) as? Bool ?? false,
            alertsOnFailure: defaults.object(forKey: Key.alertsOnFailure) as? Bool ?? false
        )
        settings.detectedProviders = detected
        settings.suggestedProviders = selection.suggestedProviders
        settings.applyLanguage()
        NetworkSession.apply(settings.networkProxy)
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
        static let openSettingsShortcut = "settings.openSettingsShortcut"
        static let togglePanelShortcut = "settings.togglePanelShortcut"
        static let deepSeekBasis = "settings.deepSeekBasis"
        static let deepSeekBudget = "settings.deepSeekBudget"
        static let deepSeekCurrency = "settings.deepSeekCurrency"
        static let lowBalanceAlerts = "settings.lowBalanceAlerts"
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
        static let networkProxy = "settings.networkProxy"
        static let autoCollapse = "settings.autoCollapse"
        static let panelSize = "settings.panelSize"
        static let railSpacing = "settings.railSpacing"
        static let usesGlass = "settings.usesGlass"
        static let topRailShowsPercentages = "settings.topRailShowsPercentages"
        static let sideRailShowsPercentages = "settings.sideRailShowsPercentages"
        static let labelAboveRing = "settings.labelAboveRing"
        static let showsWindowClock = "settings.showsWindowClock"
        static let botMarks = "settings.botMarks"
        static let botPersonas = "settings.botPersonas"
        static let botShapes = "settings.botShapes"
        static let botColours = "settings.botColours"
        static let showsRemaining = "settings.showsRemaining"
        static let warningThreshold = "settings.warningThreshold"
        static let dockShowsAlertColor = "settings.dockShowsAlertColor"
        static let showsForecast = "settings.showsForecast"
        static let showsSecondRing = "settings.showsSecondRing"
        static let splitAccounts = "settings.splitAccounts"
        static let spendSpan = "settings.spendSpan"
        static let readsTokenSpend = "settings.readsTokenSpend"
        static let alertThreshold = "settings.alertThreshold"
        static let alertsOnReset = "settings.alertsOnReset"
        static let alertsOnFailure = "settings.alertsOnFailure"
        static let providerOrder = "settings.providerOrder"
    }
}
