// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import Observation
import SwiftUI

/// User-facing preferences, persisted in `UserDefaults`.
///
/// **Where things live.** Swift keeps stored properties in the class body, and
/// `@Observable` tracks only those, so this file is the one list of everything
/// that is stored: each setting's declaration and its documentation, grouped by
/// topic. What a change *does* — the key it is written under, the callback it
/// fires, the global it keeps in step — is in that topic's file:
///
/// | File | Topic |
/// |---|---|
/// | `AppSettings+Application` | menu bar item, Dock icon, shortcuts, language |
/// | `AppSettings+Panel` | the floating panel: visibility, size, rail metrics, glass |
/// | `AppSettings+Rings` | how a ring looks: tint, mark, clock, warning colour, pinned window |
/// | `AppSettings+Accounts` | which accounts exist, which are shown, in what order |
/// | `AppSettings+Providers` | per-provider choices: routes, sites, balance basis, proxy, cadence |
/// | `AppSettings+TokenSpend` | the Token spend pane |
/// | `AppSettings+Notifications` | alert rules |
/// | `AppSettings+Recap` | the monthly recap |
/// | `AppSettings+WindowStarter` | the window starter |
///
/// **Two callbacks, and the difference is a network request.** `onChange`
/// is the usage loop's hook: `AppDelegate` answers it by re-placing the panel
/// *and* asking every provider again. `onLayoutChange` re-places the panel and
/// nothing else. A setting that changes only how Pulse draws or places itself
/// goes through the second; reaching for `onChange` there costs every
/// provider a request for a figure that did not change.
@Observable
final class AppSettings {
    /// Where every setting is written. The app's own settings use
    /// `UserDefaults.standard`; a test passes a throwaway suite.
    @ObservationIgnored let defaults: UserDefaults

    // MARK: - Callbacks

    /// Called after any change the usage loop has to react to — a provider
    /// switched on or off, a route or a site chosen, the panel shown or hidden.
    /// `AppDelegate` re-places the panel and refreshes every provider.
    var onChange: (() -> Void)?
    /// Called after a change to how the panel is drawn or placed — its size,
    /// its rail's metrics, its glass. Re-places the panel; does **not**
    /// refresh anything. See the table above.
    var onLayoutChange: (() -> Void)?
    /// Called only when the menu bar status item should be inserted or removed.
    /// Kept separate from `onChange` so a presentation preference cannot start
    /// a provider refresh.
    var onMenuBarIconChange: (() -> Void)?
    /// Called when the Dock icon the settings window brings should appear or go.
    var onDockIconChange: (() -> Void)?
    /// Called when the recap notification is switched, so a month already
    /// announceable is announced now.
    var onRecapAlertChange: (() -> Void)?

    // MARK: - Application (AppSettings+Application)

    /// Whether Pulse removes its menu bar icon.
    ///
    /// Off by default so existing installs keep the current entry point. This
    /// setting deliberately does not call `onChange`: the status item reacts
    /// through its dedicated callback, and changing it must not trigger a
    /// provider refresh.
    var hidesMenuBarIcon: Bool {
        didSet { hidesMenuBarIconChanged(from: oldValue) }
    }

    /// Whether Pulse shows a Dock icon for as long as the settings window is
    /// open.
    ///
    /// On by default: an `.accessory` app has no Dock icon and no ⌘-Tab entry,
    /// so a settings window that something else has covered cannot be found
    /// again. The icon is there only while the window is, and goes with it.
    /// Goes through its own callback, not `onChange`, which refetches.
    var showsDockIconInSettings: Bool {
        didSet { showsDockIconInSettingsChanged(from: oldValue) }
    }

    /// Whether the menu bar item also shows the tightest limit: the mark of
    /// the account whose ring is fullest, and its percentage.
    ///
    /// The menu bar is the one place that is never out of sight — the panel
    /// steps aside for full-screen apps, and some people hide it. Off by
    /// default, like every other addition to what Pulse puts on screen. Goes
    /// through the menu bar's own callback, not `onChange`, which refetches.
    var showsUsageInMenuBar = false {
        didSet { showsUsageInMenuBarChanged(from: oldValue) }
    }

    /// Whether the menu bar item's menu opens on the usage dashboard — an
    /// overview of every account, and a tab per account.
    ///
    /// Off by default, like every other addition to what Pulse puts on screen:
    /// the menu is a few plain items until somebody asks for more. Read when
    /// the menu opens, so it needs no callback.
    var showsMenuDashboard = false {
        didSet { showsMenuDashboardChanged(from: oldValue) }
    }

    /// The account the menu bar speaks for, by id. Nil — the default — is
    /// whichever ring is fullest. An account taken off the rail falls back to
    /// that too (`MenuBarReading.choose`) rather than leaving the bar blank.
    var menuBarAccount: String? {
        didSet { menuBarAccountChanged(from: oldValue) }
    }

    /// How the menu bar draws the account: its figure, a small ring, or its
    /// five-hour and weekly limits side by side. See `MenuBarStyle`.
    var menuBarStyle: MenuBarStyle = .figure {
        didSet { menuBarStyleChanged(from: oldValue) }
    }

    /// The key combination that opens settings from anywhere, or nil.
    ///
    /// Deliberately no `onChange`: that is the usage loop's hook and it
    /// refetches every provider when it fires. A shortcut is not a reading.
    /// Whoever sets one tells `GlobalShortcutMonitor` directly, which is the
    /// only thing that has to hear about it.
    var openSettingsShortcut: GlobalShortcut? {
        didSet { openSettingsShortcutChanged(from: oldValue) }
    }

    /// The key combination that draws the floating panel or takes it away, or
    /// nil. Same rule about `onChange` as the one above.
    var togglePanelShortcut: GlobalShortcut? {
        didSet { togglePanelShortcutChanged(from: oldValue) }
    }

    /// Interface language. Applied to `LocalizationSource` as soon as it
    /// changes so the UI re-reads its strings without a relaunch.
    var language: AppLanguage {
        didSet { languageChanged(from: oldValue) }
    }

    // MARK: - Panel (AppSettings+Panel)

    /// Whether the floating panel is on screen.
    var isPanelVisible: Bool {
        didSet { isPanelVisibleChanged(from: oldValue) }
    }

    /// Whether the floating panel stays out of other apps' full-screen Spaces.
    ///
    /// On by default: a usage glance is useful on the desktop, but sitting over
    /// a presentation, video, game, or focused full-screen workspace is noise.
    /// This is implemented with the panel's public AppKit collection behavior,
    /// so it needs no Accessibility permission and cannot confuse a maximized
    /// window with a real full-screen Space.
    var hidesInFullScreen: Bool {
        didSet { hidesInFullScreenChanged(from: oldValue) }
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
        didSet { followsActiveDisplayChanged(from: oldValue) }
    }

    /// How big the floating panel is drawn.
    var panelSize: PanelSize {
        didSet { panelSizeChanged(from: oldValue) }
    }

    /// Whether the rail keeps its percent labels while it lies along the top
    /// of the screen.
    ///
    /// Off by default. Against a side of the screen the label sits under its
    /// ring and costs nothing; along the top it is a second line of type
    /// directly under the menu bar, which turns a compact pill into a banner.
    /// The number is a hover away on the card either way.
    var topRailShowsPercentages: Bool {
        didSet { topRailShowsPercentagesChanged(from: oldValue) }
    }

    /// How much air there is between the rings.
    var railSpacing: RailSpacing {
        didSet { railSpacingChanged(from: oldValue) }
    }

    /// Whether the rail keeps its percent labels down a side of the screen.
    ///
    /// On by default, which is the opposite of the top rail's. Against a side
    /// the label sits under its ring and costs only the rail's length; across
    /// the top it is a second line of type directly under the menu bar. Same
    /// control, opposite defaults, for that reason.
    var sideRailShowsPercentages: Bool {
        didSet { sideRailShowsPercentagesChanged(from: oldValue) }
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
        didSet { labelAboveRingChanged(from: oldValue) }
    }

    /// Whether a rail lying free across puts each figure beside its ring
    /// rather than under it.
    ///
    /// Off by default: under, with the rings drawn closer together than down
    /// a side, is the free rail's own proportion. Beside makes the rail the
    /// upright one's thickness and a good deal longer. Docked to the top the
    /// figures stay under their rings either way. Moves where a ring sits, so
    /// it goes to `PanelMetrics` before the change is announced, like
    /// `labelAboveRing`.
    var freeAcrossFiguresBeside: Bool {
        didSet { freeAcrossFiguresBesideChanged(from: oldValue) }
    }

    /// Whether the rail's ends are half circles taken from the ring, rather
    /// than softened corners of their own.
    ///
    /// Off by default, which is the rail as it has always been drawn: 26pt
    /// superellipse corners and a flatter 24 x 38 flare into the screen edge.
    /// On, one circle sets every curve on the panel — each end becomes a half
    /// circle of half the rail, the flare is that same circle turned inside
    /// out so the two meet as a single S-curve, and the card's tail leaves
    /// the card along its edge instead of at an angle.
    ///
    /// One switch rather than three, because the three are one idea. Split up
    /// they would let a round end sit on the old end padding, which puts the
    /// first ring hard against the curve it is supposed to be centred in.
    ///
    /// Set on `PanelMetrics` before the change is announced, like the other
    /// rail metrics: the two styles sit the end ring differently, so the rail
    /// is 16pt longer with round ends and whoever reacts is about to measure
    /// it.
    var usesRoundEnds: Bool {
        didSet { usesRoundEndsChanged(from: oldValue) }
    }

    /// Whether each ring also shows how far through its window the clock is.
    ///
    /// Off by default. It is a genuinely useful second reading — 80% spent a
    /// fifth of the way in means running out, 80% spent with minutes left
    /// means it was budgeted about right — but it is a second thing to read
    /// on a mark that is 36pt across, and the rail's whole case is that one
    /// glance is enough. Asked for, so it is offered; not assumed.
    ///
    /// The arc is drawn in the margin the rail already has around a ring, so
    /// it moves nothing by itself — but **it moves the figures.** The arc is
    /// drawn 5pt outside the ring's own edge, so a figure at the usual
    /// distance sat on it (issue #73); with the arc on, figures stand that
    /// much further off and the rail is longer. So it goes to `PanelMetrics`
    /// before the change is announced, like `labelAboveRing`.
    var showsWindowClock: Bool {
        didSet { showsWindowClockChanged(from: oldValue) }
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
        didSet { showsForecastChanged(from: oldValue) }
    }

    /// The accounts whose card is the detailed one, by account id: the plan,
    /// how far through each window the clock is and, with Token spend on,
    /// what this Mac has put through the account lately.
    ///
    /// **Per account, not one switch for the panel.** The detailed card is
    /// worth its height for the one or two accounts somebody watches closely,
    /// and noise on the rest.
    ///
    /// A `PanelMetrics` entry like the forecast, and for the same reason: the
    /// detailed card is taller, and the frame is worked out before SwiftUI lays
    /// anything out. Set before the change is announced, so whoever re-places
    /// the panel measures the new size.
    var detailedCards: Set<String> = [] {
        didSet { detailedCardsChanged(from: oldValue) }
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
        didSet { usesGlassChanged(from: oldValue) }
    }

    /// A light solid surface with dark content, instead of black (#74).
    ///
    /// Only the solid surface: glass is pinned dark for the reason
    /// `PanelGlass` gives, so this is ignored while `usesGlass` is on, and
    /// kept rather than cleared so turning glass off again brings it back.
    /// At a physical notch too: the reader chose light, so the notch berth
    /// is light like everywhere else, not a special case they have to learn.
    /// `FloatingUsagePanelContent.panelScheme` is where the two settings meet.
    var usesLightPanel: Bool {
        didSet { usesLightPanelChanged(from: oldValue) }
    }

    /// How clear the glass is, 0 to 1: how little of `PanelGlass`'s dimming
    /// sits under the panel's white content. The reader's to choose because
    /// the right amount depends on what is usually behind the panel — a
    /// white page wants more, a dark editor none.
    ///
    /// Deliberately no `onChange`: that refetches every provider, and a
    /// slider sets this dozens of times a second. The panel is `@Observable`
    /// and redraws on its own.
    ///
    /// **Observer body kept here, not in `AppSettings+Panel`.** Assigning
    /// the clamped value inside its own `didSet` does not run the observer
    /// again; from a method it would, and would write the value out twice.
    var glassTransparency: Double {
        didSet {
            let clamped = min(max(glassTransparency, 0), 1)
            guard clamped == glassTransparency else { glassTransparency = clamped; return }
            guard glassTransparency != oldValue else { return }
            defaults.set(glassTransparency, forKey: Key.glassTransparency)
        }
    }

    /// Whether the rail hides down to a sliver when the pointer is elsewhere.
    ///
    /// On by default. The panel sits over whatever else is on screen all day,
    /// and most of that time nobody is reading it — but it stays reachable at
    /// the edge, and the sliver still changes colour when a limit is nearly
    /// gone, so hiding it never hides bad news.
    var autoCollapse: Bool {
        didSet { autoCollapseChanged(from: oldValue) }
    }

    /// Accounts whose limits are drawn as one ring per model group, as ids.
    ///
    /// Off for everyone by default. Only a provider that actually reports more
    /// than one group can be split — `Provider.splitsByModelGroup` — and today
    /// that is Antigravity alone: its plan carries a Gemini allowance and a
    /// separate one for Claude and GPT, and a single ring can only ever show
    /// the worse of the two.
    var splitAccounts: Set<String> {
        didSet { splitAccountsChanged(from: oldValue) }
    }

    /// Whether this is the settings the running app is drawn from, and so the
    /// one allowed to move `PanelMetrics`.
    ///
    /// **Global state, owned by one instance.** The rail's budget is a static
    /// the AppKit frame reads, and every other `AppSettings` — a preview's, a
    /// test's — switching an account on would resize a panel it has nothing to
    /// do with. Under parallel tests that was a race: one suite's toggle
    /// shrank the window another suite was measuring. Set by `restored()`
    /// once the metrics have been brought in line with what is stored.
    @ObservationIgnored var drivesPanelMetrics = false

    // MARK: - Rings (AppSettings+Rings)

    /// Which window each provider's ring shows, keyed by provider. A missing
    /// entry means "whichever is closest to its limit".
    var pinnedWindows: [String: String] {
        didSet { pinnedWindowsChanged(from: oldValue) }
    }

    /// A colour chosen for an account's ring, keyed by account. A missing
    /// entry means the ring is coloured by how much of its limit is gone,
    /// which is the default and the one that means something.
    var ringTints: [String: String] {
        didSet { ringTintsChanged(from: oldValue) }
    }

    /// Which rings draw an animated mark instead of the provider's logo,
    /// keyed by account. A missing entry means the logo, which is the default.
    ///
    /// **Per account, not one switch for the rail.** A logo says which of
    /// twenty products a ring belongs to, and a mark gives that up for
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
        didSet { botMarksChanged(from: oldValue) }
    }

    /// The persona chosen for an account's mark, keyed by account. A missing
    /// entry means automatic, which is what almost everyone will leave it on.
    ///
    /// Automatic is dealt by position on the rail, so the ring beside this one
    /// is a different character. Choosing one is for when somebody wants a
    /// particular provider to be the sleepy one.
    var botPersonas: [String: String] {
        didSet { botPersonasChanged(from: oldValue) }
    }

    /// A colour chosen for an account's **mark**, keyed by account. A missing
    /// entry means the brand colour, or one dealt across the rail.
    ///
    /// Separate from `ringTints` on purpose: the ring means how close the
    /// limit is, the mark means which provider this is, and somebody who
    /// wants a green bot in a red ring is asking for two different things.
    var botColours: [String: String] {
        didSet { botColoursChanged(from: oldValue) }
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
        didSet { botShapesChanged(from: oldValue) }
    }

    /// Whether the outer clock arc fills with elapsed time or empties with the
    /// time remaining. Elapsed is the persisted fallback so existing installs
    /// keep the display they chose before this direction setting existed.
    var windowClockDirection: WindowClockDirection {
        didSet { windowClockDirectionChanged(from: oldValue) }
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
    /// This changes nothing about the layout: "100%" is the widest either
    /// way round, so no `PanelMetrics` entry and nothing to re-measure.
    var showsRemaining: Bool {
        didSet { showsRemainingChanged(from: oldValue) }
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
        didSet { warningThresholdChanged(from: oldValue) }
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
        didSet { dockShowsAlertColorChanged(from: oldValue) }
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
        didSet { showsSecondRingChanged(from: oldValue) }
    }

    /// Whether a ring turns while its CLI is working or Pulse is fetching it a
    /// fresh reading.
    ///
    /// On by default — it is how those two facts are shown at all, see
    /// `UsageRingView.isBusy`/`isRefreshing`. Off draws the ring exactly as it
    /// would sit between events: the usage arc at full opacity, no travelling
    /// mark, no refresh sweep. The facts themselves are unaffected — a busy
    /// CLI is still busy — only the moving cue for them is withheld, for
    /// anyone who finds a rail of turning rings more distracting than useful.
    var animatesRingActivity: Bool {
        didSet { animatesRingActivityChanged(from: oldValue) }
    }

    // MARK: - Accounts (AppSettings+Accounts)

    /// Which accounts appear in the rail. Empty only until the initial choice
    /// is made; once monitoring starts, the last ring cannot be switched off.
    ///
    /// Ids rather than providers, and stored under the same key with the same
    /// values as when it was providers: a first account's id *is* its
    /// provider's raw value, so nothing written by an older version stops
    /// matching.
    ///
    /// **Observer body kept here, not in `AppSettings+Accounts`**, for the
    /// reason `glassTransparency` gives: it puts the old value back from inside
    /// its own `didSet`, which does not run the observer a second time.
    var enabledAccounts: Set<String> {
        didSet {
            guard enabledAccounts != oldValue else { return }
            if enabledAccounts.isEmpty {
                enabledAccounts = oldValue
                return
            }
            // The rail is sized from what is shown, so the budget moves
            // before the change is announced — see `railSlotCount`.
            resizeRail()
            defaults.set(Array(enabledAccounts), forKey: ProviderSelection.enabledKey)
            onChange?()
        }
    }

    /// Accounts Pulse knows about beyond each provider's first, which exist
    /// only because Pulse was signed in to them.
    var extraAccounts: [ExtraAccount] {
        didSet { extraAccountsChanged(from: oldValue) }
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
        didSet { providerOrderChanged(from: oldValue) }
    }

    /// The extensions the last scan of the extensions folder found usable, and
    /// the folders it turned away. Nothing here is fetched until its account
    /// is switched on, which is `enabledAccounts`' job as for any provider.
    ///
    /// **Scanned at launch and when asked, not watched.** A program being
    /// copied in is a half-written folder for a moment, and a watcher would
    /// list it broken and then fixed. Settings has a button for "look again".
    ///
    /// Written only by `AppSettings+Accounts` (`apply(_:)`, `restoreAccounts`).
    var extensions: [PulseExtension] = [] {
        didSet { extensionsChanged(from: oldValue) }
    }
    /// Written only by `AppSettings+Accounts`, like `extensions`.
    var extensionProblems: [ExtensionCatalog.Problem] = []

    /// Discovery is metadata only. Neither list enables anything on its own.
    var detectedProviders: Set<Provider> = []
    var suggestedProviders: Set<Provider> = []

    /// What `orderedAccounts` worked out, kept until one of the three things it
    /// depends on changes. Not observed: reading `orderedAccounts` reads those
    /// three, which is what tells an observer.
    @ObservationIgnored var orderedCache: [AccountKey]?

    // MARK: - Providers (AppSettings+Providers)

    /// Where DeepSeek's ring gets its denominator.
    ///
    /// DeepSeek reports a prepaid balance and no allowance at all, so unlike
    /// every other provider there is no percentage to show until something
    /// supplies one. Three modes, one setting, and the card always names which
    /// is in force — see `BalanceBasis`. Scalars rather than the per-account
    /// dictionaries beside them because DeepSeek has no second account.
    var deepSeekBasis: BalanceBasis {
        didSet { deepSeekBasisChanged(from: oldValue) }
    }

    /// What the reader calls a full tank, for `BalanceBasis.budget`. Nil until
    /// they say, which leaves that mode showing the balance and no fraction.
    var deepSeekBudget: Double? {
        didSet { deepSeekBudgetChanged(from: oldValue) }
    }

    /// Which currency the ring follows when the account holds more than one.
    /// Nil takes the first the reply lists with money in it.
    var deepSeekCurrency: String? {
        didSet { deepSeekCurrencyChanged(from: oldValue) }
    }

    /// Which Qoder site the saved session belongs to.
    ///
    /// `qoder.com` and `qoder.com.cn` are two sign-ins on two hosts, and a
    /// session for one is refused by — and must never be sent to — the other.
    /// So the site decides both where the browser is asked for cookies and
    /// where the request goes, and changing it discards the session saved for
    /// the old one (Settings does that). A scalar, like DeepSeek's settings
    /// beside it, because Qoder has no second account.
    var qoderSite: QoderSite {
        didSet { qoderSiteChanged(from: oldValue) }
    }

    /// Whether Qoder's credits are drawn part by part as well as in total.
    ///
    /// `total_quota` adds up the plan's credits, a resource pack bought on
    /// top and the credits tied to one model family, and each of those is
    /// spent and lapses on its own: a total at 57% can hold a pack at 95%.
    /// Off by default, so an account with one part reads as it always has; on,
    /// each part with an allowance gets its own row after the total, and the
    /// ring's automatic choice follows whichever is fullest. Changes what the
    /// service returns, so it goes through `onChange`.
    var qoderShowsParts = false {
        didSet { qoderShowsPartsChanged(from: oldValue) }
    }

    /// Which StepFun site the saved session belongs to: `platform.stepfun.com`
    /// or `platform.stepfun.ai`, two sign-ins on two hosts. The same rules as
    /// `qoderSite`: it decides where cookies are read from and where the
    /// request goes, and changing it discards the saved session.
    var stepFunSite: StepFunSite {
        didSet { stepFunSiteChanged(from: oldValue) }
    }

    /// Where Pulse sends a self-hosted gateway's request, per account.
    ///
    /// sub2api and New API are somebody's own deployments, so unlike every
    /// other provider here there is no address to ship: these are typed.
    /// Stored as the reader wrote it and checked on the way out
    /// (`GatewayAddress`), so a half-typed address never becomes a request and
    /// is never quietly rewritten into one. Empty until they say.
    ///
    /// **Keyed by account id, like `sources` and `sessionBrowsers`**, rather
    /// than a scalar per provider. It was a scalar while sub2api was the only
    /// one; a second gateway turned "the address" into "*whose* address", and
    /// a shape that cannot hold two is the shape that quietly gives one
    /// provider the other's host.
    var serverAddresses: [String: String] {
        didSet { serverAddressesChanged(from: oldValue) }
    }

    /// Whether Codex's card shows how many limit reset credits are left.
    ///
    /// **Off by default**, because it is not free: the count is only in
    /// Codex's app server, so while this is on every Codex refresh starts or
    /// asks that process — which somebody reading Codex from its usage
    /// endpoint alone would otherwise never run.
    ///
    /// No `onChange`: that refetches every provider, and this is one row on
    /// one card. Settings asks the store for the count itself.
    var showsCodexResetCredits = false {
        didSet { showsCodexResetCreditsChanged(from: oldValue) }
    }

    /// Where each API account's ring gets its denominator, keyed by account.
    /// DeepSeek's own lives in `deepSeekBasis`, from before there were others;
    /// `balanceBasis(for:)` reads either. A missing entry is the default.
    var balanceBases: [String: String] = [:] {
        didSet { balanceBasesChanged(from: oldValue) }
    }

    /// What the reader calls a full tank for each API account, for
    /// `BalanceBasis.budget`. DeepSeek's lives in `deepSeekBudget`.
    var balanceBudgets: [String: Double] = [:] {
        didSet { balanceBudgetsChanged(from: oldValue) }
    }

    /// Which browser an account's session cookie is read from, keyed by
    /// account. A missing entry means "whichever, starting with the default
    /// one" — the same shape as `sources`, and for the same reason: naming one
    /// means a failure is *reported* rather than quietly answered from
    /// somewhere the user never signed in.
    var sessionBrowsers: [String: String] {
        didSet { sessionBrowsersChanged(from: oldValue) }
    }

    /// Which route each provider's figures are read by, keyed by provider. A
    /// missing entry means `.automatic`.
    var sources: [String: String] {
        didSet { sourcesChanged(from: oldValue) }
    }

    /// How often the figures are re-read.
    var refreshInterval: RefreshInterval {
        didSet { refreshIntervalChanged(from: oldValue) }
    }

    /// How Pulse's own requests and supported helper processes reach the
    /// network. System is the default so an upgrade changes nothing.
    var networkProxy: NetworkProxySettings {
        didSet { networkProxyChanged(from: oldValue) }
    }

    // MARK: - Token spend (AppSettings+TokenSpend)

    /// How far back the Token spend pane counts.
    ///
    /// The last **week** until the reader picks another span, and their pick is
    /// kept: the pane answers a sit-down question, and making someone re-choose
    /// the window on every visit is work nobody asked for. No `onChange?()` —
    /// nothing about the panel's frame depends on it, and `@Observable` already
    /// redraws whoever read it, the same as `warningThreshold`.
    var spendSpan: SpendSpan {
        didSet { spendSpanChanged(from: oldValue) }
    }

    /// Which view of the Token spend pane's year-long "Token activity" chart is
    /// open: the daily grid until the reader picks another, and their pick is
    /// kept like the span's. No `onChange?()` for the same reason.
    var spendActivityView: ActivityView {
        didSet { spendActivityViewChanged(from: oldValue) }
    }

    /// Local records are read only after this pane is explicitly enabled.
    /// No onChange: that hook refreshes the quota providers.
    var readsTokenSpend: Bool {
        didSet { readsTokenSpendChanged(from: oldValue) }
    }

    // MARK: - Notifications (AppSettings+Notifications)

    /// Warn when a prepaid balance falls below this much, per account.
    ///
    /// Empty is off, which is how it ships — the same rule every other alert
    /// follows. Keyed by account id and stored per account rather than as one
    /// figure because the providers that report a balance do not price in the
    /// same currency: ¥20 and $20 are not the same line.
    var lowBalanceAlerts: [String: Double] {
        didSet { lowBalanceAlertsChanged(from: oldValue) }
    }

    /// How full a limit gets before Pulse posts a notification about it.
    ///
    /// Off by default, like every other setting that makes Pulse do something
    /// unprompted. Whatever step is chosen, a limit the provider reports as
    /// **spent** is always the second one — the two are one setting because
    /// wanting the warning and not wanting to hear that it happened is not a
    /// combination anybody has.
    var alertThreshold: AlertThreshold {
        didSet { alertThresholdChanged(from: oldValue) }
    }

    /// Say when a limit that was warned about has come back.
    ///
    /// Depends on `alertThreshold`, and the settings pane greys it out to say
    /// so: a reset is only announced for a window Pulse had already mentioned
    /// on the way up, so with the threshold off there is nothing this can fire
    /// about. See `AlertMemory` for why it is tied that way.
    var alertsOnReset: Bool {
        didSet { alertsOnResetChanged(from: oldValue) }
    }

    /// Say when several passes in a row have failed to read an account.
    ///
    /// The one alert that is about Pulse rather than about usage. A failed
    /// fetch falls back to the last good reading, which is the right thing to
    /// show and also the reason the fault is invisible: the panel goes on
    /// displaying perfectly plausible figures with only a "last read" time to
    /// give it away.
    var alertsOnFailure: Bool {
        didSet { alertsOnFailureChanged(from: oldValue) }
    }

    /// Say when a provider's own status page — Codex's, Claude Code's,
    /// DeepSeek's — reports an outage: for whichever is switched on, and only
    /// about what it runs on (`StatusPage.notifiesAbout`). Rules: `OutageMemory`.
    var alertsOnOutage = false {
        didSet { alertsOnOutageChanged(from: oldValue) }
    }

    /// Say, in the first days of a month, that last month's recap is ready —
    /// only when that month had records Pulse has read (`RecapNoticeRule`).
    /// Off by default. Goes through its own callback, which checks at once:
    /// switching it on in the first days of a month announces then.
    var alertsOnRecap = false {
        didSet { alertsOnRecapChanged(from: oldValue) }
    }

    // MARK: - Recap (AppSettings+Recap)

    /// The month whose recap was last announced, as `Recap.Period.key`
    /// ("2026-09"), so each month is announced once however often Pulse
    /// restarts or the switch is flipped.
    var recapAnnouncedMonth: String? {
        didSet { recapAnnouncedMonthChanged(from: oldValue) }
    }

    /// What the reader pays a month, in US dollars — typed into the recap
    /// window, used only for its payback card. **Nil is nothing typed**, never a
    /// guess and never zero: no payback card is drawn for it. Only a positive
    /// amount within `RecapPrice.maximum` is kept.
    ///
    /// **Observer body kept here, not in `AppSettings+Recap`**, for the reason
    /// `glassTransparency` gives.
    var recapMonthlyPrice: Double? {
        didSet {
            // Assigning inside `didSet` does not run it again.
            let kept = RecapPrice.normalized(recapMonthlyPrice)
            if kept != recapMonthlyPrice { recapMonthlyPrice = kept }
            guard kept != oldValue else { return }
            if let kept {
                defaults.set(kept, forKey: Key.recapMonthlyPrice)
            } else {
                defaults.removeObject(forKey: Key.recapMonthlyPrice)
            }
        }
    }

    /// Whether the recap cards say "Project 1", "Project 2" instead of the
    /// directories' names. Off: names are shown.
    var recapHidesProjects = false {
        didSet { recapHidesProjectsChanged(from: oldValue) }
    }

    // MARK: - Window starter (AppSettings+WindowStarter)

    /// Providers whose usage windows Pulse starts as soon as they reset, by
    /// raw value — see `WindowPrimer`. Empty by default, and switched on only
    /// through Settings' confirmation, which says what it does and what it
    /// risks. Not through `onChange`, which refetches every provider:
    /// `WindowPrimer` observes this itself.
    var primedProviders: Set<String> = [] {
        didSet { primedProvidersChanged(from: oldValue) }
    }

    /// When the window starter may act. See `PrimerHours`.
    var primerHours: PrimerHours = .default {
        didSet { primerHoursChanged(from: oldValue) }
    }

    /// When each provider's window was last started, and how that went —
    /// what its pane shows, so the reader can see it is doing something.
    /// Written only by `AppSettings+WindowStarter`.
    var primerRunTimes: [String: Double] = [:]
    var primerRunOutcomes: [String: String] = [:]

    // MARK: - Init

    /// Source-compatible with every caller that names only the settings it
    /// cares about: `AppSettings(readsTokenSpend: true)`. Every default here is
    /// the shipped one, and is the same constant `restored()` falls back to
    /// (`Default`), so the two cannot drift.
    ///
    /// The list stays flat. Every stored property has to be assigned in a
    /// designated initializer's own body, so grouping the arguments into
    /// per-topic values would leave this body as long as it is and put a second
    /// list of the same names in front of it.
    init(
        isPanelVisible: Bool = Default.isPanelVisible,
        hidesMenuBarIcon: Bool = Default.hidesMenuBarIcon,
        showsDockIconInSettings: Bool = Default.showsDockIconInSettings,
        hidesInFullScreen: Bool = Default.hidesInFullScreen,
        followsActiveDisplay: Bool = Default.followsActiveDisplay,
        openSettingsShortcut: GlobalShortcut? = nil,
        togglePanelShortcut: GlobalShortcut? = nil,
        deepSeekBasis: BalanceBasis = .default,
        deepSeekBudget: Double? = nil,
        deepSeekCurrency: String? = nil,
        qoderSite: QoderSite = Default.qoderSite,
        stepFunSite: StepFunSite = Default.stepFunSite,
        serverAddresses: [String: String] = [:],
        lowBalanceAlerts: [String: Double] = [:],
        enabledAccounts: Set<String> = Set(Provider.builtIn.map(\.rawValue)),
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
        autoCollapse: Bool = Default.autoCollapse,
        panelSize: PanelSize = .default,
        railSpacing: RailSpacing = .default,
        usesGlass: Bool = Default.usesGlass,
        glassTransparency: Double = Default.glassTransparency,
        usesLightPanel: Bool = Default.usesLightPanel,
        topRailShowsPercentages: Bool = Default.topRailShowsPercentages,
        sideRailShowsPercentages: Bool = Default.sideRailShowsPercentages,
        labelAboveRing: Bool = Default.labelAboveRing,
        freeAcrossFiguresBeside: Bool = Default.freeAcrossFiguresBeside,
        usesRoundEnds: Bool = Default.usesRoundEnds,
        showsWindowClock: Bool = Default.showsWindowClock,
        windowClockDirection: WindowClockDirection = .default,
        showsRemaining: Bool = Default.showsRemaining,
        warningThreshold: WarningThreshold = .default,
        dockShowsAlertColor: Bool = Default.dockShowsAlertColor,
        showsForecast: Bool = Default.showsForecast,
        showsSecondRing: Bool = Default.showsSecondRing,
        animatesRingActivity: Bool = Default.animatesRingActivity,
        splitAccounts: Set<String> = [],
        spendSpan: SpendSpan = .default,
        spendActivityView: ActivityView = .default,
        readsTokenSpend: Bool = Default.readsTokenSpend,
        alertThreshold: AlertThreshold = .default,
        alertsOnReset: Bool = Default.alertsOnReset,
        alertsOnFailure: Bool = Default.alertsOnFailure,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.isPanelVisible = isPanelVisible
        self.hidesMenuBarIcon = hidesMenuBarIcon
        self.showsDockIconInSettings = showsDockIconInSettings
        self.hidesInFullScreen = hidesInFullScreen
        self.followsActiveDisplay = followsActiveDisplay
        self.openSettingsShortcut = openSettingsShortcut
        self.togglePanelShortcut = togglePanelShortcut
        self.deepSeekBasis = deepSeekBasis
        self.deepSeekBudget = deepSeekBudget
        self.deepSeekCurrency = deepSeekCurrency
        self.qoderSite = qoderSite
        self.stepFunSite = stepFunSite
        self.serverAddresses = serverAddresses
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
        self.glassTransparency = min(max(glassTransparency, 0), 1)
        self.usesLightPanel = usesLightPanel
        self.topRailShowsPercentages = topRailShowsPercentages
        self.sideRailShowsPercentages = sideRailShowsPercentages
        self.labelAboveRing = labelAboveRing
        self.freeAcrossFiguresBeside = freeAcrossFiguresBeside
        self.usesRoundEnds = usesRoundEnds
        self.showsWindowClock = showsWindowClock
        self.windowClockDirection = windowClockDirection
        self.showsRemaining = showsRemaining
        self.warningThreshold = warningThreshold
        self.dockShowsAlertColor = dockShowsAlertColor
        self.showsForecast = showsForecast
        self.showsSecondRing = showsSecondRing
        self.animatesRingActivity = animatesRingActivity
        self.splitAccounts = splitAccounts
        self.spendSpan = spendSpan
        self.spendActivityView = spendActivityView
        self.readsTokenSpend = readsTokenSpend
        self.alertThreshold = alertThreshold
        self.alertsOnReset = alertsOnReset
        self.alertsOnFailure = alertsOnFailure
    }

    // MARK: - Restoring

    /// The settings the running app is drawn from: what is stored, with
    /// everything that has to follow it put into effect — the language, the
    /// proxy session, `PanelMetrics`.
    static func restored() -> AppSettings {
        let settings = restoredSettings(from: .standard)
        settings.applyRestored()
        return settings
    }

    /// What is stored, read into a new `AppSettings`, with no global touched.
    /// Split from `restored()` so a test can read an isolated suite back.
    ///
    /// The memberwise call is flat for the reason `init` is. Settings that are
    /// not parameters of it are read by their topic's own `restore…` function,
    /// called at the end.
    ///
    /// What this Mac has installed and what its extensions folder holds are
    /// parameters, defaulting to looking, so a test does not read the Mac.
    static func restoredSettings(
        from defaults: UserDefaults,
        detected: Set<Provider> = Provider.installedOnThisMac(),
        scan: ExtensionCatalog.Scan = ExtensionCatalog.scan()
    ) -> AppSettings {
        let extras = (defaults.data(forKey: Key.extraAccounts))
            .flatMap { try? JSONDecoder().decode([ExtraAccount].self, from: $0) } ?? []
        // The scan comes before the stored choice is restored, which keeps only
        // accounts it knows: an extension missing from this list would lose its
        // switch on every launch.
        let selection = ProviderSelection.restore(
            in: defaults,
            knownAccounts: Set(Provider.builtIn.map(\.rawValue))
                .union(extras.map(\.id))
                .union(scan.extensions.map(\.account.id)),
            detected: detected
        )

        let settings = AppSettings(
            isPanelVisible: defaults.settingsFlag(Key.panelVisible, default: Default.isPanelVisible),
            hidesMenuBarIcon: defaults.settingsFlag(Key.hidesMenuBarIcon, default: Default.hidesMenuBarIcon),
            showsDockIconInSettings: defaults.settingsFlag(
                Key.showsDockIconInSettings, default: Default.showsDockIconInSettings
            ),
            hidesInFullScreen: defaults.settingsFlag(Key.hidesInFullScreen, default: Default.hidesInFullScreen),
            followsActiveDisplay: defaults.settingsFlag(
                Key.followsActiveDisplay, default: Default.followsActiveDisplay
            ),
            openSettingsShortcut: defaults.string(forKey: Key.openSettingsShortcut)
                .flatMap(GlobalShortcut.init(storage:)),
            togglePanelShortcut: defaults.string(forKey: Key.togglePanelShortcut)
                .flatMap(GlobalShortcut.init(storage:)),
            deepSeekBasis: defaults.settingsChoice(Key.deepSeekBasis) ?? .default,
            deepSeekBudget: defaults.object(forKey: Key.deepSeekBudget) as? Double,
            deepSeekCurrency: defaults.string(forKey: Key.deepSeekCurrency),
            qoderSite: defaults.settingsChoice(Key.qoderSite) ?? Default.qoderSite,
            stepFunSite: defaults.settingsChoice(Key.stepFunSite) ?? Default.stepFunSite,
            serverAddresses: defaults.dictionary(forKey: Key.serverAddresses) as? [String: String] ?? [:],
            lowBalanceAlerts: defaults.dictionary(forKey: Key.lowBalanceAlerts) as? [String: Double] ?? [:],
            enabledAccounts: selection.enabledAccounts,
            extraAccounts: extras,
            providerOrder: defaults.stringArray(forKey: Key.providerOrder) ?? [],
            language: defaults.settingsChoice(Key.language) ?? .system,
            pinnedWindows: defaults.dictionary(forKey: Key.pinnedWindows) as? [String: String] ?? [:],
            sources: defaults.dictionary(forKey: Key.sources) as? [String: String] ?? [:],
            sessionBrowsers: defaults.dictionary(forKey: Key.sessionBrowsers) as? [String: String] ?? [:],
            ringTints: defaults.dictionary(forKey: Key.ringTints) as? [String: String] ?? [:],
            botMarks: defaults.dictionary(forKey: Key.botMarks) as? [String: Bool] ?? [:],
            botPersonas: defaults.dictionary(forKey: Key.botPersonas) as? [String: String] ?? [:],
            botShapes: defaults.dictionary(forKey: Key.botShapes) as? [String: String] ?? [:],
            botColours: defaults.dictionary(forKey: Key.botColours) as? [String: String] ?? [:],
            refreshInterval: defaults.settingsIntChoice(Key.refreshInterval) ?? .default,
            networkProxy: Self.storedNetworkProxy(in: defaults),
            autoCollapse: defaults.settingsFlag(Key.autoCollapse, default: Default.autoCollapse),
            panelSize: defaults.settingsChoice(Key.panelSize) ?? .default,
            railSpacing: defaults.settingsChoice(Key.railSpacing) ?? .default,
            usesGlass: defaults.settingsFlag(Key.usesGlass, default: Default.usesGlass),
            glassTransparency: defaults.object(forKey: Key.glassTransparency) as? Double ?? Default.glassTransparency,
            usesLightPanel: defaults.settingsFlag(Key.usesLightPanel, default: Default.usesLightPanel),
            topRailShowsPercentages: defaults.settingsFlag(
                Key.topRailShowsPercentages, default: Default.topRailShowsPercentages
            ),
            sideRailShowsPercentages: defaults.settingsFlag(
                Key.sideRailShowsPercentages, default: Default.sideRailShowsPercentages
            ),
            labelAboveRing: defaults.settingsFlag(Key.labelAboveRing, default: Default.labelAboveRing),
            freeAcrossFiguresBeside: defaults.settingsFlag(
                Key.freeAcrossFiguresBeside, default: Default.freeAcrossFiguresBeside
            ),
            usesRoundEnds: defaults.settingsFlag(Key.usesRoundEnds, default: Default.usesRoundEnds),
            showsWindowClock: defaults.settingsFlag(Key.showsWindowClock, default: Default.showsWindowClock),
            windowClockDirection: Self.storedWindowClockDirection(in: defaults),
            showsRemaining: defaults.settingsFlag(Key.showsRemaining, default: Default.showsRemaining),
            warningThreshold: defaults.settingsIntChoice(Key.warningThreshold) ?? .default,
            dockShowsAlertColor: defaults.settingsFlag(Key.dockShowsAlertColor, default: Default.dockShowsAlertColor),
            showsForecast: defaults.settingsFlag(Key.showsForecast, default: Default.showsForecast),
            showsSecondRing: defaults.settingsFlag(Key.showsSecondRing, default: Default.showsSecondRing),
            animatesRingActivity: defaults.settingsFlag(
                Key.animatesRingActivity, default: Default.animatesRingActivity
            ),
            splitAccounts: Set(defaults.stringArray(forKey: Key.splitAccounts) ?? []),
            spendSpan: Self.storedSpendSpan(in: defaults),
            spendActivityView: Self.storedSpendActivityView(in: defaults),
            readsTokenSpend: Self.storedReadsTokenSpend(in: defaults),
            alertThreshold: defaults.settingsIntChoice(Key.alertThreshold) ?? .default,
            alertsOnReset: defaults.settingsFlag(Key.alertsOnReset, default: Default.alertsOnReset),
            alertsOnFailure: defaults.settingsFlag(Key.alertsOnFailure, default: Default.alertsOnFailure),
            defaults: defaults
        )
        settings.restoreProviders(from: defaults)
        settings.restoreNotifications(from: defaults)
        settings.restoreRecap(from: defaults)
        settings.restoreApplication(from: defaults)
        settings.restoreWindowStarter(from: defaults)
        settings.restorePanel(from: defaults)
        settings.restoreAccounts(detected: detected, suggested: selection.suggestedProviders, scan: scan)
        return settings
    }

    /// Everything outside this object that has to agree with what was just
    /// restored, and only then the right to move `PanelMetrics` afterwards.
    private func applyRestored() {
        applyLanguage()
        NetworkSession.apply(networkProxy)
        applyPanelMetrics()
        drivesPanelMetrics = true
        resizeRail()
    }

    // MARK: - Keys and defaults

    /// The `UserDefaults` keys, which are the stored format: renaming one
    /// resets everybody's choice. Each topic file extends this with its own
    /// (`AppSettings+Panel` adds `panelSize`, and so on), and
    /// `AppSettingsPersistenceTests` spells them out so a rename fails.
    enum Key {}

    /// The shipped default of every setting whose default is a literal, which
    /// both `init` and `restored()` need. Topic files extend this too.
    enum Default {}
}

extension UserDefaults {
    /// A stored boolean, or `value` when none is stored — or when what is
    /// stored is not a boolean, which `bool(forKey:)` would read as false.
    func settingsFlag(_ key: String, default value: Bool) -> Bool {
        object(forKey: key) as? Bool ?? value
    }

    /// A stored string naming a case, or nil when none is stored or it names
    /// a case a later version removed.
    func settingsChoice<Choice: RawRepresentable>(_ key: String) -> Choice? where Choice.RawValue == String {
        string(forKey: key).flatMap(Choice.init(rawValue:))
    }

    /// The same for a case stored as a number.
    func settingsIntChoice<Choice: RawRepresentable>(_ key: String) -> Choice? where Choice.RawValue == Int {
        (object(forKey: key) as? Int).flatMap(Choice.init(rawValue:))
    }
}
