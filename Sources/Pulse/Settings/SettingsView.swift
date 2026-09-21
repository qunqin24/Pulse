import AppKit
import SwiftUI

/// The settings window: a source list on the left, one pane at a time on the
/// right, each pane a stack of grouped cards.
struct SettingsView: View {
    let store: UsageStore
    let settings: AppSettings
    let placement: PanelPlacement
    let update: AppUpdate
    let alerts: UsageAlerts
    /// Not for reading settings — those are in `settings` — but for the one
    /// thing only the monitor knows: whether the window server would take the
    /// combination.
    let shortcuts: GlobalShortcutMonitor

    @Bindable var navigation: SettingsNavigation
    private var pane: SettingsPane {
        get { navigation.pane }
        nonmutating set { navigation.pane = newValue }
    }
    @State private var hookGeneration = 0
    /// Login-item state lives with the system, not in `AppSettings`, so it is
    /// read back rather than stored — and nudged when it changes.
    @State private var loginGeneration = 0

    /// Read from the CLIs' own transcripts, which takes long enough on a cold
    /// start to be worth holding on to while the window is open.
    @State private var ledgers: [Provider: UsageLedger] = [:]
    /// How each provider's last history read went — kept beside the ledger
    /// rather than folded into it.
    ///
    /// An empty chart has several causes and they must not be said the same way:
    /// telling somebody their account has no usage, because the Wi-Fi dropped,
    /// beside a ring showing 80%, is the app inventing a reading — and so is
    /// telling them the service failed when no key was ever pasted. Written on
    /// **every** path that touches `ledgers`, so it cannot describe a read
    /// other than the most recent one.
    @State private var historyReads: [Provider: ZaiUsageService.HistoryRead] = [:]
    @State private var codexAccount: CodexAccountUsage?
    @State private var loadingHistory: Provider?
    /// The key field's contents. Seeded from the store when the pane opens;
    /// the store is a file, not something SwiftUI can observe.
    @State private var apiKey = ""
    /// The budget being typed, kept as text so a half-entered number is not
    /// read as a denominator on every keystroke.
    @State private var deepSeekBudget = ""
    /// Manual proxy fields are committed as one valid endpoint rather than on
    /// every keystroke.
    @State private var proxyHost = ""
    @State private var proxyPort = ""
    @State private var proxyHostInvalid = false
    @State private var proxyPortInvalid = false
    private enum ProxyField: Hashable { case host, port }
    @FocusState private var proxyField: ProxyField?
    /// The low-balance figure being typed, kept as text for the same reason.
    @State private var lowBalance = ""
    @State private var savedKey = ""
    /// The provider a browser sign-in is currently open for, and what went
    /// wrong with the last one.
    @State private var signingIn: Provider?
    @State private var signInError: (provider: Provider, message: String)?
    /// Shown while a device-code sign-in is waiting: the code the provider
    /// gave, and where to type it.
    @State private var devicePrompt: OAuthLogin.DevicePrompt?
    /// Copilot's own sign-in, which is GitHub's device flow rather than the
    /// one the added-account button drives.
    @State private var githubPrompt: GitHubDeviceLogin.Prompt?
    @State private var githubTask: Task<Void, Never>?
    @State private var githubError: String?
    /// What the last look through the browsers found.
    @State private var sessionMessage: String?
    /// Held so it can be called off. A device-code sign-in polls for fifteen
    /// minutes, and a sign-in that failed in the browser gives this side no
    /// sign at all — without a way out the button stays disabled for the whole
    /// quarter of an hour.
    @State private var signInTask: Task<Void, Never>?
    /// Narrows the sidebar. Sixteen providers plus every added account is a
    /// list that scrolls on any window worth opening.
    @State private var search = ""
    /// The row a reorder drag is currently over, so it can say so.
    @State private var dropTarget: AccountKey?
    @FocusState private var credentialFocused: Bool
    @State private var repairMessages: [String: String] = [:]
    @State private var connectionFocusRequest = 0
    /// Every agent's spending, for the pane that is not about one provider.
    /// Its own state rather than something derived from `ledgers`, which is
    /// filled one account at a time as their panes are opened.
    @State private var spend = SpendSummary()
    @State private var isScanningSpend = false
    @State private var spendRead = SpendReadState()
    @State private var spendProgress: AgentLedgers.Progress?
    @State private var spendRescan = 0
    /// The agent the spend pane is looking at on its own, and that agent's own
    /// figures. Kept beside the combined ones rather than derived on the fly:
    /// both come out of the same ledgers and the same span, so they cannot
    /// disagree about what a month is.
    @State private var spendFocus: SpendAgent?
    @State private var focusedSpend = SpendSummary()
    private var spendLedgers: [SpendAgent: UsageLedger] { spendRead.snapshot?.ledgers ?? [:] }
    /// Present sources — installed, or captured/exported somewhere Pulse reads
    /// — that produced no records at all. Named together at the foot of the
    /// pane so a silent source is not mistaken for a zero reading. Not
    /// span-dependent: "nothing was read" is the same answer over any span.
    private var spendNoRecords: [SpendAgent] {
        SpendAgent.allCases.filter { spendLedgers[$0]?.allTime.tokens == 0 }
    }
    /// Whether any present source held history a reader could not decode —
    /// a compressed transcript, say. The pane shows a short generic status
    /// rather than dropping those records silently; the readers' own English
    /// diagnostics never reach the view.
    private var spendHasReadLimitations: Bool { spendRead.snapshot?.notes.isEmpty == false }
    /// The model the spend pane has drilled into, and that model's own figures
    /// over the same span — crossed with `spendFocus` when an agent is open, so
    /// a model opened from an agent's list counts only that agent's work in it.
    ///
    /// **Not a setting.** Drilling in is a way of reading the page in front of
    /// you, not a preference about the app, so it lives here and is dropped
    /// when the agent changes rather than being written to `AppSettings`.
    @State private var selectedModel: String?
    @State private var modelSpend = ModelSpendSummary()

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                if matches(.general) || matches(.spend) {
                    Section(String.localized("Panel")) {
                        if matches(.general) { row(.general) }
                        // Above the accounts, not below them. Eighteen
                        // provider rows is more than a sidebar shows at once,
                        // and a pane whose whole subject is "all of them
                        // together" was landing under the fold — reachable
                        // only by scrolling past the thing it summarises.
                        if matches(.spend) { row(.spend) }
                    }
                }

                if !matchingAccounts.isEmpty {
                    Section(String.localized("Accounts")) {
                        // Same order as the rail: a sidebar that disagreed with
                        // the thing it configures is its own small confusion.
                        ForEach(matchingAccounts) { account in
                            row(.account(account))
                        }
                    }
                }

                if matches(.about) || matches(.integrations) {
                    Section(String.localized("Application")) {
                        if matches(.integrations) { row(.integrations) }
                        if matches(.about) { row(.about) }
                    }
                }
            }
            .listStyle(.sidebar)
            // **The floor is this frame, not `navigationSplitViewColumnWidth`.**
            //
            // `ideal:` is read once, when a column is first laid out. The whole
            // split view carries `.id(settings.language)`, so picking a
            // language — or launching into one, since `LocalizationSource.use`
            // runs after the first render — throws the column away and builds a
            // new one, and the new one does not get its `ideal` back. Measured
            // on the committed screenshots: 213pt in English, about 150pt in
            // Chinese, from the same code. `min:` does not rescue it either;
            // it bounds what a drag may do, it does not widen a column that was
            // already laid out narrow.
            //
            // A `minWidth` on the content is a layout constraint, so it is
            // re-applied on every rebuild, which is the property this needs.
            //
            // 200 is measured, not guessed. Scanning the committed English
            // screenshot for the rightmost ink in the list puts the longest
            // label — `GitHub Copilot` — at **150.5pt**, so this leaves about
            // 50pt of trailing air. 240 was tried first and read as baggy:
            // 90pt of empty column beside every row.
            //
            // **The brand names are the constraint, not the translated rows.**
            // That is worth writing down because it is the opposite of what it
            // looks like: "Token 消耗" reaches about 112pt and "开发者集成"
            // less, both short of the latin names, and CJK being twice the
            // width per glyph does not make up the difference over so few
            // characters. So this number does not move with the language — it
            // moves when a provider with a longer name is added, which is how
            // `GLM Coding Plan` quietly became the longest.
            .frame(minWidth: 200)
            // Still worth setting: these bound what dragging the divider may
            // do. `ideal` matches the frame so first layout and every rebuild
            // land on the same width; `max` keeps a stretched sidebar from
            // eating the pane.
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
            // `.sidebar`, not `.automatic`: this window has no `NSToolbar` —
            // see `SettingsWindowController` on why the title bar is left to
            // AppKit — and automatic placement has nowhere to put the field.
            .searchable(
                text: $search,
                placement: .sidebar,
                prompt: Text(localized: "Search")
            )
            .overlay {
                if isSearching, matchingAccounts.isEmpty, !matches(.general), !matches(.spend),
                   !matches(.about), !matches(.integrations) {
                    Text(localized: "No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                            .id("heading")

                        switch pane {
                        case .general: general
                        case .account(let account): accountPane(account)
                        case .spend:
                            SettingsGroup(String.localized("Token spend")) {
                                SettingsRow(
                                    String.localized("Read local usage records"),
                                    subtitle: String.localized("When enabled, scans local records and exports.")
                                ) {
                                    Toggle(String.localized("Read local usage records"), isOn: Binding(
                                        get: { settings.readsTokenSpend },
                                        set: { settings.readsTokenSpend = $0 }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                }
                                if settings.readsTokenSpend, isScanningSpend, let progress = spendProgress {
                                    SettingsRowDivider()
                                    SettingsRow(String.localized("Reading \(progress.agent.displayName)…")) {
                                        Text(verbatim: "\(progress.index + 1)/\(progress.total)")
                                            .monospacedDigit()
                                    }
                                }
                            }
                            if settings.readsTokenSpend {
                                TokenSpendView(
                                    summary: spend,
                                    focus: $spendFocus,
                                    focused: focusedSpend,
                                    modelFocus: $selectedModel,
                                    modelSummary: modelSpend,
                                    noRecords: spendNoRecords,
                                    hasReadLimitations: spendHasReadLimitations,
                                    span: Binding(
                                        get: { settings.spendSpan },
                                        set: { settings.spendSpan = $0 }
                                    ),
                                    isLoading: isScanningSpend,
                                    refresh: { spendRescan += 1 }
                                )
                            }
                        case .about: about
                        case .integrations: DeveloperIntegrationsView(settings: settings)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .background(.windowBackground)
                // Keyed on the pane and enabled state, so enabling an account
                // also reconsiders its history's empty-state explanation.
                .task(id: historyKey) { await loadHistory() }
                // A completed read survives sidebar changes in this window.
                // Only an initial visit or Rescan reads; changing the span
                // re-adds up what is already in memory.
                // **Two tasks, because they cost different things.** Reading
                // every agent's store is seconds on a cold launch; adding the
                // numbers up again for a different span is microseconds. Keyed
                // together, changing the span put the spinner back on screen
                // and made a cached read look like a rescan.
                .task(id: spendLoadKey) { await loadSpend() }
                .onChange(of: spendKey) { _, _ in recomputeSpend() }
                // A model opened under one agent means nothing under another,
                // so changing the agent drops back out of the model.
                .onChange(of: spendFocus) { _, _ in selectedModel = nil }
                .onChange(of: selectedModel) { old, new in
                    // Entering the detail drops the reader to the top, or they
                    // land in the middle of it when the model row was well down
                    // the page. Returning puts them back at the model list.
                    if new != nil {
                        proxy.scrollTo("heading", anchor: .top)
                    } else if old != nil {
                        proxy.scrollTo("models", anchor: .top)
                    }
                }
                .onChange(of: connectionFocusRequest) {
                    proxy.scrollTo("connection", anchor: .top)
                    credentialFocused = true
                }
                .onChange(of: navigation.requestID) { proxy.scrollTo("heading", anchor: .top) }
            }
        }
        // No `navigationTitle`: each pane already prints its own heading, and
        // the toolbar would repeat it right above.
        .frame(minWidth: 720, minHeight: 460)
        .onChange(of: navigation.requestID) { search = "" }
        // Rebuild everything when the language changes — the strings are read
        // through a plain function, so SwiftUI has nothing else to observe.
        .id(settings.language)
    }

    private var heading: some View {
        HStack(spacing: 9) {
            if case .account(let account) = pane {
                LobeIconView(provider: account.provider, size: 19)
            }

            Text(title(pane))
                .font(.system(size: 17, weight: .semibold))
        }
    }

    /// The pane's name. An account's is the user's own label, which the pane
    /// itself cannot reach — two subscriptions to the same plan are told apart
    /// by nothing else.
    private func title(_ pane: SettingsPane) -> String {
        if case .account(let account) = pane { return settings.label(for: account) }
        return pane.title
    }

    /// What the sidebar is being narrowed to, or nothing.
    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !query.isEmpty }

    /// Accounts whose name the search matches, in rail order.
    ///
    /// Matched against the provider's name **as well as** the user's label, not
    /// instead of it. A second Claude subscription called "工作" is still a
    /// Claude Code account, and typing the product name is the obvious way to
    /// look for it — `title(_:)` alone would only know the label.
    private var matchingAccounts: [AccountKey] {
        guard isSearching else { return settings.orderedAccounts }
        return settings.orderedAccounts.filter {
            matches(title(.account($0))) || matches($0.provider.displayName)
        }
    }

    private func matches(_ pane: SettingsPane) -> Bool {
        guard isSearching else { return true }
        return matches(title(pane))
    }

    /// Case- and accent-insensitive, and localized: `localizedStandardContains`
    /// is what Finder searches with, so "z.ai" finds Z.ai and a stray accent
    /// doesn't lose a row.
    private func matches(_ text: String) -> Bool {
        text.localizedStandardContains(query)
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(title(pane))
        } icon: {
            switch pane {
            case .account(let account):
                LobeIconView(provider: account.provider, size: 14)
            case .general, .spend, .about, .integrations:
                Image(systemName: pane.symbol)
            }
        }
        .tag(pane)
    }

    // MARK: - Panes

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
            if settings.needsProviderSelection {
                Text(localized: "Enable a service in its settings to start monitoring.")
                    .foregroundStyle(.secondary)
            }
            SettingsGroup(String.localized("Floating panel")) {
                SettingsRow(
                    String.localized("Show floating panel"),
                    subtitle: String.localized("The usage rail at the edge of the screen.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.isPanelVisible },
                        set: { settings.isPanelVisible = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide in full screen"),
                    subtitle: String.localized("Keep the floating panel out of full-screen apps.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.hidesInFullScreen },
                        set: { settings.hidesInFullScreen = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Size"),
                    subtitle: String.localized("Size of the rail on screen.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.panelSize },
                        set: { settings.panelSize = $0 }
                    )) {
                        ForEach(PanelSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Spacing"),
                    subtitle: String.localized("How much air there is between the rings.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.railSpacing },
                        set: { settings.railSpacing = $0 }
                    )) {
                        ForEach(RailSpacing.allCases) { spacing in
                            Text(spacing.title).tag(spacing)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Round ends"),
                    subtitle: String.localized("The rail's ends and the card's tail follow the ring's own curve.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.usesRoundEnds },
                        set: { settings.usesRoundEnds = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Liquid Glass"),
                    subtitle: glassSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.usesGlass },
                        set: { settings.usesGlass = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Hide until pointed at"),
                    subtitle: String.localized("Against a screen edge, the rail shrinks to a sliver until you point at it.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoCollapse },
                        set: { settings.autoCollapse = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Position"),
                    subtitle: String.localized("Drag it anywhere; near an edge it snaps on.")
                ) {
                    Picker("", selection: Binding(
                        get: { placement.dock },
                        set: { placement.update(dock: $0) }
                    )) {
                        Text(localized: "Left").tag(PanelDock.edge(.left))
                        Text(localized: "Top").tag(PanelDock.edge(.top))
                        Text(localized: "Free").tag(PanelDock.floating)
                        Text(localized: "Right").tag(PanelDock.edge(.right))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Follow the active display"),
                    subtitle: String.localized("With more than one display, the rail moves to the one the pointer is on.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.followsActiveDisplay },
                        set: { settings.followsActiveDisplay = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Percentages at the side"),
                    subtitle: String.localized("The figure under each ring, docked left or right.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.sideRailShowsPercentages },
                        set: { settings.sideRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Time until reset"),
                    subtitle: String.localized("A second arc outside each ring, for how much of the window has passed.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsWindowClock },
                        set: { settings.showsWindowClock = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Forecast"),
                    subtitle: String.localized("Whether each limit lasts its window, on the card.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsForecast },
                        set: { settings.showsForecast = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Second limit inside the ring"),
                    subtitle: String.localized("A thinner ring for the next-fullest limit, where a provider has one.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsSecondRing },
                        set: { settings.showsSecondRing = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show what's left"),
                    subtitle: String.localized("Counts down instead of up, figure and ring together.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsRemaining },
                        set: { settings.showsRemaining = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Figure above the ring"),
                    subtitle: String.localized("Swaps the two, wherever the panel is.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.labelAboveRing },
                        set: { settings.labelAboveRing = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        !settings.isPanelVisible
                            // Nothing to swap when neither rail shows a figure.
                            || (!settings.sideRailShowsPercentages && !settings.topRailShowsPercentages)
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Percentages on top"),
                    subtitle: String.localized("Only when the panel is docked to the top.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.topRailShowsPercentages },
                        set: { settings.topRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Turn red at"),
                    subtitle: String.localized("Where a ring stops being amber. A spent limit is red whatever this says.")
                ) {
                    Picker(String.localized("Turn red at"), selection: Binding(
                        get: { settings.warningThreshold },
                        set: { settings.warningThreshold = $0 }
                    )) {
                        ForEach(WarningThreshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Alert colour when docked"),
                    subtitle: String.localized("Off keeps the collapsed rail neutral even when a limit needs attention.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.dockShowsAlertColor },
                        set: { settings.dockShowsAlertColor = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Ring activity animation"),
                    subtitle: String.localized("The turning mark for a working CLI or a reading being fetched. Off leaves the ring still.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.animatesRingActivity },
                        set: { settings.animatesRingActivity = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.isPanelVisible)
                }
            }

            SettingsGroup(String.localized("Notifications")) {
                SettingsRow(
                    String.localized("Warn at"),
                    subtitle: alertsSubtitle
                ) {
                    Picker("", selection: Binding(
                        get: { settings.alertThreshold },
                        set: {
                            settings.alertThreshold = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    )) {
                        ForEach(AlertThreshold.allCases) { threshold in
                            Text(threshold.title).tag(threshold)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    .disabled(!UsageAlerts.isSupported)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a limit comes back"),
                    subtitle: String.localized("Only for one you were warned about.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnReset },
                        set: {
                            settings.alertsOnReset = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // Nothing to fire about: a reset is only announced for a
                    // window that was mentioned on the way up.
                    .disabled(!UsageAlerts.isSupported || settings.alertThreshold == .off)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("When a reading stops arriving"),
                    subtitle: String.localized("After several failed checks in a row, once per outage.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.alertsOnFailure },
                        set: {
                            settings.alertsOnFailure = $0
                            Task {
                                if await alerts.requestAuthorizationIfNeeded() {
                                    store.reconsiderAlerts()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!UsageAlerts.isSupported)
                }
            }

            SettingsGroup(String.localized("Refresh")) {
                SettingsRow(
                    String.localized("Check every"),
                    subtitle: refreshSubtitle
                ) {
                    Picker("", selection: Binding(
                        get: { settings.refreshInterval },
                        set: { settings.refreshInterval = $0 }
                    )) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }

            SettingsGroup(String.localized("Network")) {
                SettingsRow(
                    String.localized("Proxy"),
                    subtitle: String.localized("Use macOS settings or a proxy only for Pulse.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.networkProxy.mode },
                        set: { mode in
                            var proxy = settings.networkProxy
                            proxy.mode = mode
                            settings.networkProxy = proxy
                            if mode == .system {
                                proxyHostInvalid = false
                                proxyPortInvalid = false
                            }
                        }
                    )) {
                        ForEach(NetworkProxyMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }

                if settings.networkProxy.mode == .manual {
                    SettingsRowDivider()

                    SettingsRow(String.localized("Type")) {
                        Picker("", selection: Binding(
                            get: { settings.networkProxy.kind },
                            set: { kind in
                                var proxy = settings.networkProxy
                                proxy.kind = kind
                                settings.networkProxy = proxy
                            }
                        )) {
                            ForEach(NetworkProxyKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Host"),
                        subtitle: proxyHostInvalid
                            ? String.localized("Enter a host.")
                            : String.localized("The proxy server's name or address.")
                    ) {
                        TextField("", text: $proxyHost, prompt: Text(verbatim: "127.0.0.1"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .focused($proxyField, equals: .host)
                            .onSubmit { saveManualProxy() }
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Port"),
                        subtitle: proxyPortInvalid
                            ? String.localized("Enter a whole number from 1 to 65535.")
                            : String.localized("A number from 1 to 65535.")
                    ) {
                        TextField("", text: $proxyPort, prompt: Text(verbatim: "7897"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .focused($proxyField, equals: .port)
                            .onSubmit { saveManualProxy() }
                    }
                }
            }

            SettingsGroup(String.localized("Order")) {
                // **Drag, and the arrows as well.** This was arrows only, on
                // the reasoning that four rows is not enough to make a drag
                // worth learning and that an arrow which misses does nothing
                // while a drag which misses does something. The first half of
                // that stopped being true: there are seventeen providers now,
                // plus every added account, and moving the bottom one to the
                // top is sixteen clicks.
                //
                // The arrows stay rather than being replaced. They are the
                // precise way to move one place, they are the only way that
                // works from the keyboard, and they carry the accessibility
                // labels — drag and drop has none to give.
                ForEach(Array(settings.orderedAccounts.enumerated()), id: \.element) { index, account in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        settings.label(for: account),
                        // Moving something the rail isn't drawing looks like
                        // the arrow did nothing; saying so is kinder than
                        // hiding the row and renumbering everything.
                        subtitle: settings.isEnabled(account) ? nil : String.localized("Not shown"),
                        icon: account.provider.iconResource
                    ) {
                        HStack(spacing: 4) {
                            Button {
                                settings.move(account, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel(String.localized("Move \(settings.label(for: account)) up"))

                            Button {
                                settings.move(account, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == settings.orderedAccounts.count - 1)
                            .accessibilityLabel(String.localized("Move \(settings.label(for: account)) down"))
                        }
                        .buttonStyle(.borderless)
                    }
                    // The whole row, not just the text: a drag that only
                    // starts on the label is a drag most people conclude
                    // isn't there.
                    .contentShape(.rect)
                    .background(dropTarget == account ? Color.accentColor.opacity(0.12) : .clear)
                    .draggable(account.id) {
                        // The system's own drag image is the row at full
                        // width, which at 900pt is a slab. This is the two
                        // things being moved: the mark and the name.
                        HStack(spacing: 8) {
                            LobeIconView(provider: account.provider, size: 15)
                            Text(settings.label(for: account))
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        dropTarget = nil
                        guard let dragged = ids.first.flatMap(AccountKey.init(id:)),
                              settings.orderedAccounts.contains(dragged)
                        else { return false }

                        settings.move(dragged, onto: account)
                        return true
                    } isTargeted: { isTargeted in
                        // Cleared by identity, not unconditionally: the row
                        // being left and the row being entered report in an
                        // order nobody promises, so a bare `nil` on exit can
                        // wipe the highlight the next row has just set.
                        if isTargeted {
                            dropTarget = account
                        } else if dropTarget == account {
                            dropTarget = nil
                        }
                    }
                }

                // Last, and disabled while there is nothing to undo. A drag
                // that went somewhere unintended is easy to make and, at
                // seventeen rows, tedious to walk back by hand.
                SettingsRowDivider()

                SettingsRow(
                    String.localized("Reset order"),
                    subtitle: String.localized("Back to the order Pulse ships with.")
                ) {
                    Button(String.localized("Reset")) { settings.resetOrder() }
                        .disabled(!settings.hasCustomOrder)
                }
            }

            SettingsGroup(String.localized("Application")) {
                SettingsRow(
                    String.localized("Open at login"),
                    subtitle: loginSubtitle
                ) {
                    Toggle("", isOn: Binding(
                        get: {
                            _ = loginGeneration
                            return LoginItem.isEnabled
                        },
                        set: {
                            LoginItem.setEnabled($0)
                            loginGeneration += 1
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsGroup(String.localized("Shortcuts")) {
                SettingsRow(
                    String.localized("Open settings"),
                    subtitle: shortcutSubtitle(
                        for: .openSettings,
                        when: String.localized("Reaches this window with the menu bar icon out of sight.")
                    )
                ) {
                    ShortcutField(shortcut: settings.openSettingsShortcut) { shortcut in
                        settings.openSettingsShortcut = shortcut
                        shortcuts.apply(settings)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Show or hide the panel"),
                    subtitle: shortcutSubtitle(
                        for: .togglePanel,
                        when: String.localized("Draws the usage rail, or takes it away.")
                    )
                ) {
                    ShortcutField(shortcut: settings.togglePanelShortcut) { shortcut in
                        settings.togglePanelShortcut = shortcut
                        shortcuts.apply(settings)
                    }
                }
            }

            SettingsGroup(String.localized("Language")) {
                SettingsRow(
                    String.localized("Interface language"),
                    subtitle: String.localized("Takes effect right away.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }
        }
        .onAppear {
            proxyHost = settings.networkProxy.host
            proxyPort = settings.networkProxy.port.map(String.init) ?? ""
            proxyHostInvalid = false
            proxyPortInvalid = false
        }
        .onChange(of: proxyField) { previous, current in
            guard previous != nil, previous != current else { return }
            saveManualProxy()
        }
    }

    /// Host and port become one setting only after both fields are valid. The
    /// text remains as typed on refusal so the row can explain what to fix.
    private func saveManualProxy() {
        let host = NetworkProxySettings.validHost(proxyHost)
        let port = NetworkProxySettings.validPort(proxyPort)
        proxyHostInvalid = host == nil
        proxyPortInvalid = port == nil
        guard let host, let port else { return }

        var proxy = settings.networkProxy
        proxy.host = host
        proxy.port = port
        settings.networkProxy = proxy
        proxyHost = host
        proxyPort = String(port)
    }

    /// What a shortcut row says under its title.
    ///
    /// A combination the window server refused is one that will never fire, and
    /// saying nothing would leave the reader to work that out by pressing it —
    /// so the clash takes the line over while it lasts.
    private func shortcutSubtitle(
        for action: GlobalShortcutMonitor.Action,
        when available: String
    ) -> String {
        shortcuts.unavailable.contains(action)
            ? .localized("Another app is already using this combination.")
            : available
    }

    /// The login item's state is the system's to hold, so this says what the
    /// system actually reports rather than what was asked for.
    private var loginSubtitle: String {
        _ = loginGeneration

        return switch LoginItem.state {
        case .needsApproval:
            .localized("Waiting for approval in System Settings › General › Login Items.")
        case .on, .off:
            .localized("Start Pulse automatically when you log in.")
        }
    }

    /// Says what the *system* thinks, which is the half the switches cannot
    /// know. A switch left on while macOS is dropping everything Pulse posts is
    /// a setting that lies, and permission can be withdrawn in System Settings
    /// long after it was given.
    private var alertsSubtitle: String {
        guard UsageAlerts.isSupported else {
            // The `swift run` case: a bare executable has no bundle, and the
            // notification centre raises rather than refusing politely.
            return .localized("Notifications need the bundled app.")
        }

        if settings.wantsAlerts, alerts.authorization == .denied {
            return .localized("Turned off for Pulse in System Settings › Notifications.")
        }
        return .localized("Notify when a limit passes this, and again when it is spent.")
    }

    /// The catch only applies while it is on, so it is only said then.
    private var glassSubtitle: String {
        let base = String.localized("Frosted glass instead of solid black.")
        guard settings.usesGlass else { return base }
        // A full stop in Chinese is full-width and carries its own trailing
        // space; adding another leaves a visible gap mid-sentence.
        let gap = base.hasSuffix("。") ? "" : " "
        return base + gap + .localized("Drag it by a ring while this is on.")
    }

    /// On automatic the cadence is decided at each tick, so the setting says
    /// what it has settled on — otherwise the choice is a black box that seems
    /// to do nothing.
    private var refreshSubtitle: String {
        guard settings.refreshInterval == .automatic else {
            return .localized("How often to fetch new figures.")
        }

        let minutes = Int((store.currentInterval / 60).rounded())
        return .localized("2 to 30 minutes as needed. Now: \("\(minutes)") minutes.")
    }

    /// Finds this provider's session in whichever browser signed in.
    ///
    /// The default browser leads, because that is where the session actually
    /// is — another browser may hold one months out of date, and finding that
    /// is worse than the keychain asking. Whatever turns up goes through the
    /// provider's own filter before it is kept, so only the cookies that
    /// actually authenticate ever reach the store; everything else read along
    /// the way is discarded unseen.
    /// Names the browser about to be opened, and warns when opening it will
    /// ask for the keychain.
    private static func browserHint(_ chosen: BrowserCookies.Browser?, for provider: Provider) -> String {
        // A `localStorage` entry is not encrypted, so nothing is ever asked
        // for and the hint must not say it might be.
        guard provider.usesSessionCookie else {
            if let chosen { return String.localized("Only \(chosen.name).") }
            guard let first = ChromiumLocalStorage.present().first else {
                return String.localized("Finds it in the browser you signed in with.")
            }
            return String.localized("Starts with \(first.name).")
        }

        // Named, it is the only one opened — the rest are not tried, so a
        // failure is reported rather than answered from a browser the user
        // never signed in to. That is the same bargain `UsageSource` makes.
        if let chosen {
            return chosen.promptsForKeychain
                ? String.localized("Only \(chosen.name). It will ask for the keychain.")
                : String.localized("Only \(chosen.name).")
        }

        guard let first = BrowserCookies.present().first else {
            return String.localized("Finds it in the browser you signed in with.")
        }

        // "Starts with", not "looks in": if the session isn't there the rest
        // are tried too, and a hint that promised one browser and then reported
        // another reads as the app having ignored it.
        return first.promptsForKeychain
            ? String.localized("Starts with \(first.name). It will ask for the keychain.")
            : String.localized("Starts with \(first.name).")
    }

    private func readSession(for account: AccountKey) {
        // Devin's credential is not a cookie and is not saved: the service
        // reads it from the browser on every pass, so this button's job is to
        // say whether there is one to read and where it was found.
        guard account.provider.usesSessionCookie else {
            readBrowserStorage(for: account)
            return
        }

        // Named, that one and no other. Left automatic, the default browser
        // leads and the rest follow.
        let browsers = settings.sessionBrowser(for: account).map { [$0] } ?? BrowserCookies.present()

        guard !browsers.isEmpty else {
            sessionMessage = String.localized("No browser cookie store was found.")
            return
        }

        Task {
            // Off the main thread: this opens a database or two and may ask
            // the keychain, and the settings window should not freeze while it
            // does.
            // **Which site, and which cookies of it are worth keeping.** Two
            // providers read a session now, and the normalizer is the thing
            // that decides what leaves the browser — a shared one that kept
            // everything it found would forward whichever cookie either site
            // adds next.
            //
            // **Exhaustive, no `default`.** A fall-through would hand the next
            // provider added Ollama's host and Ollama's filter, and it would
            // find nothing and say so in that provider's own pane — the
            // failure `Provider.soleRoute` was made exhaustive to prevent,
            // where Grok's pane described Antigravity's language server.
            let host: String
            let keep: @Sendable (String) -> String?
            switch account.provider {
            case .ollamaCloud:
                host = "ollama.com"
                keep = { try? OllamaSessionCookie.normalize($0) }
            case .xiaomiMiMo:
                host = XiaomiMiMoClient.host
                keep = { try? XiaomiMiMoCookie.normalize($0) }
            case .claudeCode, .codex, .kiro, .antigravity, .cursor, .openCodeGo,
                 .kimiCode, .zai, .glmCoding, .minimax, .minimaxCN, .copilot,
                 .grok, .grokBot, .volcengine, .commandCode, .deepSeek, .devin:
                // Not session-based: `readSession` sends those to
                // `readBrowserStorage` before it gets here.
                return
            }

            let found = await Task.detached(priority: .userInitiated) {
                BrowserCookies.session(forHost: host, allowing: browsers, keep: keep)
            }.value

            if let found {
                guard APIKeyStore.setKey(found.header, for: account.provider) else { return }
                store.loadAPIKeys()
                store.refresh(account)
                // The keychain dialog may outlive the pane that opened it.
                if pane == .account(account) {
                    apiKey = found.header
                    savedKey = found.header
                    sessionMessage = String.localized("Read from \(found.browser.name).")
                }
                return
            }

            if pane == .account(account) {
                // Named per provider for the same reason the switch above is
                // exhaustive: a shared sentence would send somebody to the
                // wrong site.
                sessionMessage = switch account.provider {
                case .xiaomiMiMo:
                    String.localized("No Xiaomi session found. Sign in at platform.xiaomimimo.com first.")
                default:
                    String.localized("No Ollama session found. Sign in at ollama.com first.")
                }
            }
        }
    }

    /// Devin: look now, say what was found, and ask for a refresh.
    ///
    /// **Nothing is stored.** A saved copy would be a second place for the
    /// session to go stale and the one that cannot renew itself; reading it
    /// each pass costs about forty milliseconds and is always current.
    private func readBrowserStorage(for account: AccountKey) {
        let chosen = settings.sessionBrowser(for: account)
        guard !(chosen.map { [$0] } ?? ChromiumLocalStorage.present()).isEmpty else {
            sessionMessage = String.localized("No Chromium browser was found.")
            return
        }

        Task {
            // Off the main thread: it opens every table in a browser profile's
            // storage, and the settings window should not freeze while it does.
            let found = await Task.detached(priority: .userInitiated) {
                DevinUsageService.fromBrowser(chosen)
            }.value

            guard pane == .account(account) else { return }
            guard let found else {
                sessionMessage = String.localized("No Devin session found. Sign in at app.devin.ai first.")
                return
            }

            sessionMessage = String.localized("Read from \(found.browser.name).")
            store.refresh(account)
        }
    }

    private func saveKey(for account: AccountKey) {
        // Only call it saved if it was. Otherwise the Save button greys out
        // over a key that never reached disk.
        guard APIKeyStore.setKey(apiKey, for: account.provider) else { return }
        savedKey = apiKey
        // The store keeps keys for the life of the launch, so it has to be
        // told; otherwise the key is saved and nothing uses it until restart.
        store.loadAPIKeys()
        // And a key is only worth entering if something tries it now.
        store.refresh(account)
        // Including the history, which otherwise keeps saying there is no key
        // until the pane is left and come back to.
        Task { await loadHistory() }
    }

    private func accountPane(_ account: AccountKey) -> some View {
        let provider = account.provider
        return accountPaneBody(account, provider)
    }

    private func accountPaneBody(_ account: AccountKey, _ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if !settings.isEnabled(account), account.isPrimary {
                Text(provider.monitoringAccessDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup(String.localized("Panel")) {
                SettingsRow(String.localized("Show in panel")) {
                    Toggle("", isOn: Binding(
                        get: { settings.isEnabled(account) },
                        set: { settings.setEnabled($0, for: account) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // The last one standing can't be switched off: an empty
                    // rail has nothing to hover and nothing to drag.
                    .disabled(settings.isEnabled(account) && settings.enabledAccounts.count == 1)
                }

                SettingsRowDivider()

                ringWindowRow(for: account)

                // Only where there is more than one budget to split. Every
                // other provider reports one pool, and a switch that promises
                // a second ring it can never draw is worse than no switch.
                if provider.splitsByModelGroup {
                    SettingsRowDivider()

                    splitRow(for: account)
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Animated mark"),
                    subtitle: String.localized("Draw a bot that reacts to this account instead of the provider's logo.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showsBotMark(for: account) },
                        set: { settings.setShowsBotMark($0, for: account) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                // Only when there is a mark to give a character to. Shown
                // otherwise it is a control over something invisible.
                if settings.showsBotMark(for: account) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Bot personality"),
                        subtitle: settings.botPersona(for: account) == nil
                            ? String.localized("The character it plays: which motions it uses and how fast. Automatic keeps it different from the rings beside it.")
                            : String.localized("The character you picked for this bot, wherever this ring sits.")
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.botPersona(for: account) },
                            set: { settings.setBotPersona($0, for: account) }
                        )) {
                            Text(localized: "Automatic").tag(BotMarkPersona?.none)
                            ForEach(BotMarkPersona.allCases) { persona in
                                Text(persona.title).tag(BotMarkPersona?.some(persona))
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Bot colour"),
                        subtitle: settings.botColour(for: account) == nil
                            ? String.localized("Its brand colour, or one dealt to stand apart from its neighbours.")
                            : String.localized("A colour of your own for this bot.")
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.botColour(for: account) != nil },
                            set: { custom in
                                // Landing on the colour it already draws, so
                                // switching to Custom changes nothing until
                                // something is picked.
                                settings.setBotColour(
                                    custom ? BotMarkTint.body(for: account.provider) : nil,
                                    for: account)
                            }
                        )) {
                            Text(localized: "Automatic").tag(false)
                            Text(localized: "Custom").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    }

                    if let chosen = settings.botColour(for: account) {
                        SettingsRowDivider()

                        SettingsRow(
                            String.localized("Colour"),
                            subtitle: chosen.hexString
                        ) {
                            ColorPicker(
                                "",
                                selection: Binding(
                                    get: { chosen },
                                    set: { settings.setBotColour($0, for: account) }
                                ),
                                // A translucent body reads as a dim one, and
                                // dim is what "no reading" looks like.
                                supportsOpacity: false
                            )
                            .labelsHidden()
                        }
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Bot shape"),
                        subtitle: String.localized("Which body this bot wears. Round unless you change it.")
                    ) {
                        Picker("", selection: Binding(
                            get: { settings.botBody(for: account) },
                            set: { settings.setBotBody($0, for: account) }
                        )) {
                            ForEach(BotMarkBody.allCases) { body in
                                Text(body.title).tag(body)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Ring colour"),
                    // Which state it is in, said outright. A colour well always
                    // shows *a* colour, so on its own it cannot tell "automatic"
                    // from "they picked green" — and a greyed-out button next to
                    // it reads as unavailable, not as the state you are in.
                    subtitle: settings.ringTint(for: account) == nil
                        ? String.localized("Coloured by how much is left.")
                        : String.localized("A colour of your own, whatever the usage.")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.ringTint(for: account) != nil },
                        set: { custom in
                            // Switching on lands on something visibly chosen
                            // rather than on the colour the automatic mode
                            // happened to be showing.
                            settings.setRingTint(custom ? RingTint.suggestions.first : nil, for: account)
                        }
                    )) {
                        Text(localized: "Automatic").tag(false)
                        Text(localized: "Custom").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }

                // Only when there is a colour to change. Shown otherwise it is
                // a control that contradicts the row above it.
                if let chosen = settings.ringTint(for: account) {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Colour"),
                        subtitle: chosen.hexString
                    ) {
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { chosen },
                                set: { settings.setRingTint($0, for: account) }
                            ),
                            // A translucent ring reads as a dim one, and dim
                            // already means "no reading".
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }
            }

            if !settings.needsProviderSelection {
                connection(for: account)
                    .id("connection")

                ConnectionDiagnosticsView(
                    account: account, store: store, settings: settings,
                    isSigningIn: signingIn != nil || githubTask != nil,
                    repairMessage: repairMessages[account.id],
                    repair: { repair($0, for: account) }
                )
                .id(account)

                accounts(for: account)

                liveUsage(for: account)
            }

            // Both are built from the transcripts the CLI leaves behind, so
            // for a provider that keeps none they would be a column of zeroes
            // claiming nothing had been spent — and for an account Pulse
            // signed in to itself they would be worse than that. Those
            // transcripts belong to whichever account the CLI is signed in to,
            // which is not this one, so showing them here would report one
            // Its own group rather than a row under Connection, which is
            // about credentials and routes. This is a notification, and the
            // general pane's group of them is the wrong home too: the figure
            // is per account, because the providers that report a balance do
            // not price in the same currency.
            if provider.reportsSpendableBalance {
                SettingsGroup(String.localized("Notifications")) {
                    lowBalanceRow(for: account)
                }
            }

            // account's spending under another's name.
            if provider.providesHistory, account.isPrimary {
                // The estimate is money, and money needs the token split only
                // a transcript carries. A provider whose history comes from
                // its own statistics has tokens and nothing to price them
                // with, so the estimate is left off rather than shown at zero.
                if provider.keepsLocalTranscripts {
                    estimatedValue(for: account)
                }

                history(for: account)
            }
        }
        .onChange(of: "\(account.id)|\(settings.isEnabled(account))", initial: true) { _, _ in
            let shown = provider
            // The stored figure, shown in the field rather than left blank
            // beside a ring that is measuring against it.
            if shown == .deepSeek {
                deepSeekBudget = settings.deepSeekBudget.map { String($0) } ?? ""
            }
            if shown.reportsSpendableBalance {
                lowBalance = settings.lowBalanceAlert(for: AccountKey(shown)).map { String($0) } ?? ""
            }
            // Copilot has no key field, but its token lives in the same store
            // and the pane needs to know whether there is one.
            guard settings.isEnabled(account), account.isPrimary,
                  shown.usesAPIKey || shown == .copilot else {
                apiKey = ""
                savedKey = ""
                return
            }
            apiKey = APIKeyStore.key(for: shown) ?? ""
            savedKey = apiKey
        }
    }

    /// What each limit is worth in money.
    ///
    /// The only inferred figure in the app, so it gets its own group and says
    /// plainly where it came from — rather than sitting beside the reported
    /// percentages as though it were one of them.
    @ViewBuilder
    private func estimatedValue(for account: AccountKey) -> some View {
        let ledger = ledgers[account.provider] ?? .empty
        let estimates = store.usage(for: account).windows.compactMap { window in
            BudgetEstimator.estimate(for: window, ledger: ledger).map { (window, $0) }
        }

        if !estimates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SettingsGroup(String.localized("Estimated value")) {
                    ForEach(Array(estimates.enumerated()), id: \.element.0.id) { index, entry in
                        if index > 0 { SettingsRowDivider() }

                        SettingsRow(
                            entry.0.name,
                            subtitle: String.localized("\(Self.approximateMoney(entry.1.spent)) used so far")
                        ) {
                            // Just what the whole window is worth. The
                            // remainder used to sit here too, but it is only
                            // the other two numbers subtracted — and the
                            // percentage it comes from is already on screen,
                            // in "Current usage" directly above.
                            Text(Self.approximateMoney(entry.1.full))
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                    }
                }

                Text(localized: "An estimate, not a reported figure: what this Mac spent since each window opened, divided by the percentage the provider says is used. Work done on other machines isn't counted, which would put these low. Windows with too little use to extrapolate from are left out.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private static func approximateMoney(_ amount: Double) -> String {
        let text = amount.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(amount >= 100 ? 0 : 2))
                .locale(LocalizationSource.locale)
        )
        return "≈\(text)"
    }

    /// What has actually been spent over time, as opposed to how much of the
    /// current limit is left.
    @ViewBuilder
    private func history(for account: AccountKey) -> some View {
        if let ledger = ledgers[account.provider], !ledger.days.isEmpty {
            AccountUsageCard(
                provider: account.provider,
                ledger: ledger,
                credits: account.provider == .codex ? codexAccount : nil
            )
        } else {
            SettingsGroup(String.localized("Usage history")) {
                SettingsRow(
                    loadingHistory == account.provider
                        ? Self.loadingHistoryTitle(for: account.provider)
                        : String.localized("No history yet"),
                    subtitle: loadingHistory == account.provider
                        ? nil
                        : Self.emptyHistoryReason(
                            for: account.provider,
                            read: historyReads[account.provider]
                        )
                ) {
                    if loadingHistory == account.provider {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    /// What a history read depends on. A change to any of it means the
    /// sentence on screen is about to describe a read that no longer applies.
    private var historyKey: String {
        guard case .account(let account) = pane else { return "\(pane)" }
        return "\(account.id)|\(settings.isEnabled(account))"
    }

    /// One task owns opening, enabling and manual rescans. Leaving, disabling
    /// or closing the settings window cancels that same task, even mid-rescan.
    private var spendLoadKey: SpendReadState.Request {
        // Keep these separate even away from the pane: closing the window
        // there must still run the release path rather than keep the same "-".
        SpendReadState.Request(
            isEnabled: settings.readsTokenSpend,
            isWindowVisible: navigation.isWindowVisible,
            isPaneSelected: pane == .spend,
            rescan: spendRescan
        )
    }

    /// What the *figures* depend on, which is read back out of what was loaded.
    private var spendKey: String {
        guard case .spend = pane, settings.readsTokenSpend else { return "-" }
        return "\(settings.spendSpan.rawValue)|\(spendFocus?.rawValue ?? "")|\(selectedModel ?? "")"
    }

    /// Every agent's ledger, added up.
    ///
    /// Sidebar visits reuse the last completed snapshot. Turning reading off
    /// or closing the window releases it; a later visit revalidates disk caches.
    private func loadSpend() async {
        guard !Task.isCancelled else { return }
        spendProgress = nil
        isScanningSpend = false

        let id: UUID
        let refresh: Bool
        switch spendRead.prepare(spendLoadKey) {
        case .retain:
            return
        case .release:
            clearSpendSummaries()
            return
        case .scan(let nextID, let force):
            id = nextID
            refresh = force
            clearSpendSummaries()
        }

        isScanningSpend = true
        defer {
            if spendRead.finish(id) {
                isScanningSpend = false
                spendProgress = nil
            }
        }

        let result: AgentLedgers.Snapshot
        do {
            result = try await AgentLedgers.shared.scan(refresh: refresh) { progress in
                guard spendRead.isCurrent(id), !Task.isCancelled else { return }
                spendProgress = progress
            }
        } catch {
            return
        }
        guard !Task.isCancelled, settings.readsTokenSpend, navigation.isWindowVisible,
              pane == .spend, spendRead.complete(result, for: id) else { return }
        recomputeSpend()
    }

    private func clearSpendSummaries() {
        spend = SpendSummary()
        focusedSpend = SpendSummary()
        modelSpend = ModelSpendSummary()
    }

    /// The same function over the same ledgers, twice: once for everything and
    /// once for the agent being looked at. Deriving the second from the first
    /// would mean a second way of counting a span, and two ways of counting
    /// one thing eventually disagree.
    ///
    /// A model is counted from the same ledgers too, **narrowed to the agent on
    /// screen first where there is one** — so a model opened from an agent's
    /// list reports that agent's work in it and never the other agents' same
    /// model. Nothing here reads a store: it is arithmetic over what was
    /// already loaded, which is why opening a model costs no spinner.
    ///
    /// **One `now` and one calendar for all three.** Asked separately, a recompute
    /// that happens to straddle midnight can put the combined total on one day
    /// and the model on the next, so the drill-down no longer adds up to the row
    /// it was opened from.
    private func recomputeSpend() {
        guard settings.readsTokenSpend else { return }
        let span = settings.spendSpan.days
        let now = Date()
        let calendar = Calendar.current
        // The agent's ledgers, or all of them when no agent is open. Counted
        // once and shared, so the agent summary and the model summary below
        // cannot end up filtered differently.
        let scoped = spendFocus.map { agent in
            spendLedgers.filter { $0.key == agent }
        } ?? spendLedgers

        spend = SpendSummary.of(spendLedgers, overLast: span, now: now, calendar: calendar)
        focusedSpend = spendFocus == nil
            ? SpendSummary()
            : SpendSummary.of(scoped, overLast: span, now: now, calendar: calendar)
        modelSpend = selectedModel.map { name in
            ModelSpendSummary.of(scoped, named: name, overLast: span, now: now, calendar: calendar)
        } ?? ModelSpendSummary()
    }

    private func loadHistory() async {
        // History is per provider — it is read from that CLI's transcripts,
        // which do not say which account was signed in at the time.
        guard case .account(let account) = pane else { return }
        let provider = account.provider
        guard settings.isEnabled(account), account.isPrimary else {
            ledgers[provider] = .empty
            historyReads[provider] = .notAsked
            codexAccount = nil
            return
        }

        loadingHistory = provider
        // Only if it is still ours. `saveKey` starts an unstructured reload
        // that no pane switch cancels, so a returning older read would
        // otherwise drop the spinner the *current* pane is showing and let it
        // fall through to a sentence about an account nothing has read yet.
        defer { if loadingHistory == provider { loadingHistory = nil } }

        // Asked of the provider rather than scanned off disk. Their own
        // statistics cover the whole account, so there is nothing local to
        // read and nothing to cache between panes.
        if provider == .zai || provider == .glmCoding {
            let key = APIKeyStore.key(for: provider)
            let read = await ZaiUsageService(provider: provider, enteredKey: key).history()

            // A pane switch cancels this task, and a cancelled request comes
            // back looking exactly like a failed one. Recording it would leave
            // "didn't answer" on a provider that was never given the chance to.
            guard !Task.isCancelled else { return }

            historyReads[provider] = read
            ledgers[provider] = if case .answered(let ledger) = read { ledger } else { .empty }
            return
        }

        // Refreshed rather than reused: the session running right now is
        // appending to a log as this is read, and only that file is re-parsed.
        let scanned = await UsageLedgerReader.shared.ledger(for: provider, refresh: true)
        guard !Task.isCancelled else { return }
        ledgers[provider] = scanned
        // Reading this Mac's own files always answers, even when the answer is
        // that there is nothing there.
        historyReads[provider] = .answered(scanned)

        if provider == .codex {
            codexAccount = await store.codexAccountUsage()
        }
    }

    /// Which of the provider's limits the rail's ring shows.
    ///
    /// The options are whatever that provider is reporting right now, so the
    /// list changes as limits come and go — a per-model window appears only
    /// once that model has one. A pin that stops matching falls back to the
    /// automatic choice rather than leaving the ring blank.
    private func ringWindowRow(for account: AccountKey) -> some View {
        let usage = store.usage(for: account)

        return SettingsRow(
            String.localized("Ring shows"),
            subtitle: String.localized("Which limit the rail's ring tracks.")
        ) {
            Picker("", selection: Binding(
                get: {
                    let pinned = settings.pinnedWindow(for: account)
                    // Show "automatic" when the pin no longer matches anything.
                    return usage.windows.contains { $0.id == pinned } ? pinned : nil
                },
                set: { settings.setPinnedWindow($0, for: account) }
            )) {
                Text(localized: "Highest usage").tag(String?.none)

                ForEach(usage.windows) { window in
                    Text(window.name).tag(String?.some(window.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
            .disabled(usage.windows.isEmpty)
        }
    }

    /// One ring per model group, for the one provider that has more than one.
    ///
    /// Off by default. It costs a slot on the rail, and the rail is the whole
    /// of the panel when it is docked — a user who has not asked for a second
    /// ring should not find the first one narrower for it.
    private func splitRow(for account: AccountKey) -> some View {
        SettingsRow(
            String.localized("A ring for each model group"),
            subtitle: String.localized("Gemini and the third-party models draw on separate allowances. One ring can only follow the busier of the two.")
        ) {
            Toggle("", isOn: Binding(
                get: { settings.isSplit(account) },
                set: { settings.setSplit($0, for: account) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    /// What to say under the key field.
    ///
    /// Usually just where it is kept — but z.ai and GLM are one company's two
    /// storefronts, and a key from the wrong console is refused with no hint
    /// as to why, so those two name the site instead of leaving the user to
    /// guess which of the two they signed up for.
    /// Both halves of the empty state have to name the **right** source.
    ///
    /// A history read from the provider's own statistics has nothing to do
    /// with this Mac, and saying "nothing has been logged on this Mac" about
    /// it sends somebody looking for a log directory that was never going to
    /// exist. `Provider.keepsLocalTranscripts` is the question, not
    /// `providesHistory`: the latter is true for both sources.
    ///
    /// The two original sentences are claims about the account, and neither is
    /// one Pulse can make until a read has actually answered. A read that
    /// failed, or that Pulse chose not to make, says that instead; one that
    /// has not happened *yet* says nothing at all.
    private static func emptyHistoryReason(for provider: Provider, read: ZaiUsageService.HistoryRead?) -> String? {
        // Nothing read yet, so nothing may be said about the account. This is
        // the first frame of a pane, before `.task` has even set the spinner.
        guard let read else { return nil }

        switch read {
        case .failed:
            return .localized("\(provider.displayName) didn't answer, so there is nothing to chart yet. Try again in a moment.")
        case .notConfigured:
            return .localized("Add a key above and Pulse can read this account's history.")
        case .notAsked:
            return .localized("This account is switched off, so Pulse hasn't asked for its history.")
        case .answered:
            break
        }

        return provider.keepsLocalTranscripts
            ? .localized("Nothing has been logged on this Mac yet, so there is no history to add up.")
            : .localized("This account hasn't used anything yet, so there is nothing to chart.")
    }

    private static func loadingHistoryTitle(for provider: Provider) -> String {
        provider.keepsLocalTranscripts
            ? .localized("Reading logs")
            : .localized("Asking \(provider.displayName)")
    }

    /// DeepSeek reports money and no allowance, so the ring has no denominator
    /// until one is chosen. Three modes because there are exactly three places
    /// one can come from — see `DeepSeekBasis`.
    private var deepSeekBasisRow: some View {
        SettingsRow(
            String.localized("Ring shows"),
            subtitle: Self.deepSeekBasisSubtitle(settings.deepSeekBasis)
        ) {
            Picker("", selection: Binding(
                get: { settings.deepSeekBasis },
                set: { settings.deepSeekBasis = $0 }
            )) {
                ForEach(DeepSeekBasis.allCases) { basis in
                    Text(basis.title).tag(basis)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
    }

    private var deepSeekBudgetRow: some View {
        SettingsRow(
            String.localized("Full tank"),
            subtitle: String.localized("What you call a full balance. The ring measures against it.")
        ) {
            HStack(spacing: 8) {
                TextField("", text: $deepSeekBudget)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth - 70)
                    .onSubmit { saveDeepSeekBudget() }

                Button(String.localized("Save")) { saveDeepSeekBudget() }
            }
        }
    }

    /// Blank clears it, which puts the ring back to showing the balance alone
    /// rather than a fraction of nothing.
    private func saveDeepSeekBudget() {
        settings.deepSeekBudget = Self.money(deepSeekBudget)
        deepSeekBudget = Self.text(settings.deepSeekBudget)
    }

    /// A figure typed into a settings field, or nil for anything that is not
    /// one.
    ///
    /// **`Double(_:)` alone is not this.** It accepts `"inf"`, `"infinity"`
    /// and `"1e999"`, all of which are `> 0`, and an infinite denominator makes
    /// `usedFraction` NaN — which `min`/`max` propagate rather than clamp, and
    /// which `Int(_:)` traps on. Persisted, that crashed the panel on every
    /// launch until the field was cleared.
    ///
    /// Parsed through a formatter rather than `Double(_:)` so a comma decimal
    /// separator is read rather than silently clearing the setting, and the
    /// currency symbol somebody types out of habit is ignored.
    private static func money(_ typed: String) -> Double? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
            .filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.numberStyle = .decimal
        let value = formatter.number(from: trimmed)?.doubleValue
            ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))

        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// The stored figure back in the field — without the `.0` that
    /// `String(_:)` puts on every whole number.
    private static func text(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)
            .locale(LocalizationSource.locale))
    }

    private static func deepSeekBasisSubtitle(_ basis: DeepSeekBasis) -> String {
        switch basis {
        case .sinceTopUp:
            .localized("How much of the balance Pulse last saw you top up to is gone.")
        case .balanceOnly:
            .localized("The money left, with no ring. DeepSeek reports no allowance.")
        case .budget:
            .localized("How much of the figure you set is gone.")
        }
    }

    /// A prepaid balance has no percentage to warn at, so it gets a line of
    /// its own: the money, not a fraction of an allowance nobody reports.
    private func lowBalanceRow(for account: AccountKey) -> some View {
        SettingsRow(
            String.localized("Warn below"),
            subtitle: String.localized("Notify once when the balance falls under this. Blank for never.")
        ) {
            HStack(spacing: 8) {
                TextField("", text: $lowBalance)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsLayout.controlWidth - 70)
                    .onSubmit { saveLowBalance(for: account) }

                Button(String.localized("Save")) { saveLowBalance(for: account) }
            }
            // Greyed out in a build with no bundle, like every other alert
            // control: `UNUserNotificationCenter` raises without one.
            .disabled(!UsageAlerts.isSupported)
        }
    }

    private func saveLowBalance(for account: AccountKey) {
        settings.setLowBalanceAlert(Self.money(lowBalance), for: account)
        lowBalance = Self.text(settings.lowBalanceAlert(for: account))
        // **The only alert control that was not asking.** Its three siblings in
        // the general pane all do, and without it a fresh install types a
        // figure into a group headed "Notifications" and is never told
        // anything: `observe` bails while authorization is `.notDetermined`,
        // and nothing else was ever going to ask.
        guard settings.lowBalanceAlert(for: account) != nil else { return }
        Task {
            // And reconsider straight away, like its siblings: a balance
            // already under the line when the figure is entered is announced
            // once, rather than waiting for a pass.
            if await alerts.requestAuthorizationIfNeeded() { store.reconsiderAlerts() }
        }
    }

    private static func keySubtitle(for provider: Provider) -> String {
        switch provider {
        case _ where provider.usesSessionCookie:
            .localized("Copied from your browser. Stored encrypted on this Mac.")
        case .zai:
            .localized("From z.ai. Stored encrypted on this Mac.")
        case .glmCoding:
            .localized("From bigmodel.cn. Stored encrypted on this Mac.")
        case .minimax:
            .localized("From platform.minimax.io. Stored encrypted on this Mac.")
        case .minimaxCN:
            .localized("From platform.minimaxi.com. Stored encrypted on this Mac.")
        // The one field holding two secrets. Says the format, because a pair
        // pasted the wrong way round fails as a signature mismatch — a 403
        // with nothing in it to suggest what went wrong.
        case .volcengine:
            .localized("AccessKeyID:SecretAccessKey, from Volcengine. Optional — arkcli needs none. Stored encrypted on this Mac.")
        // Optional, like Volcengine's: `cmd auth login` already leaves a key
        // Pulse can read, and this field is for anyone whose account is signed
        // in somewhere other than this Mac.
        case .commandCode:
            .localized("From commandcode.ai. Optional — Pulse can use the login Command Code saved. Stored encrypted on this Mac.")
        case .deepSeek:
            .localized("From platform.deepseek.com. Stored encrypted on this Mac.")
        // Two values in one field, because the quota path is scoped by an
        // organisation and nothing on this Mac carries one. Optional, like
        // Volcengine's: without it Pulse reads the plan Devin's own app saved.
        case .devin:
            .localized("A Bearer token from app.devin.ai, then a space, then your organization. Optional — Pulse can read what Devin's app saved. Stored encrypted on this Mac.")
        default:
            .localized("Stored encrypted on this Mac.")
        }
    }

    /// Where a provider's figures come from, plus anything that route needs
    /// setting up.
    ///
    /// **Not drawn when it would be empty.** An added account of a provider
    /// with one route has nothing here: no picker, no key field, and the
    /// route row below is the primary account's. Drawn anyway it is a
    /// "Connection" heading over an empty box, which reads as a control that
    /// failed to load rather than as a section with nothing to say.
    @ViewBuilder
    private func connection(for account: AccountKey) -> some View {
        let source = settings.source(for: account)

        if hasConnectionControls(for: account) {
        SettingsGroup(String.localized("Connection")) {
            // A account.provider with a single route gets told, not asked. A picker
            // with one entry is a control that cannot do anything.
            if account.isPrimary, account.provider.hasSourceChoice {
                SettingsRow(
                    String.localized("Read usage from"),
                    subtitle: source.detail(for: account.provider)
                ) {
                    Picker("", selection: Binding(
                        get: { settings.source(for: account) },
                        set: { settings.setSource($0, for: account) }
                    )) {
                        // A route this Mac cannot take is a choice whose only
                        // outcome is an error — the same rule the browser list
                        // follows. A route already *pinned* is still offered,
                        // so deleting the desktop app says so on the card
                        // rather than silently switching to another route.
                        ForEach(UsageSource.options(for: account).filter {
                            $0 != .desktopApp || ClaudeDesktopSession.isAvailable || source == .desktopApp
                        }) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            } else if account.provider == .copilot {
                // A sign-in, not a pasted token. The endpoint would accept the
                // one `gh` holds, but that carries `repo` and `workflow` — the
                // run of someone's source code, handed over to draw a
                // percentage. This asks for `read:user`.
                SettingsRow(
                    String.localized("GitHub account"),
                    subtitle: githubError
                        ?? (savedKey.isEmpty
                            ? String.localized("Opens GitHub's own page. Pulse asks to read your profile, nothing else.")
                            : String.localized("Signed in. Pulse holds a read-only token for this Mac."))
                ) {
                    if githubTask != nil {
                        Button(String.localized("Cancel")) { endGitHubSignIn() }
                    } else if savedKey.isEmpty {
                        Button(String.localized("Sign in…")) { startGitHubSignIn() }
                    } else {
                        Button(String.localized("Sign out")) {
                            _ = APIKeyStore.setKey(nil, for: .copilot)
                            apiKey = ""
                            savedKey = ""
                            githubError = nil
                            store.loadAPIKeys()
                            store.refresh(account)
                        }
                    }
                }

                // While it waits, the code is the whole interaction: it is
                // typed on GitHub's page, not here.
                if let githubPrompt {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Code"),
                        subtitle: String.localized("Copied — paste it on the page that opened.")
                    ) {
                        HStack(spacing: 10) {
                            Text(githubPrompt.userCode)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)

                            Button(String.localized("Copy")) { copy(githubPrompt.userCode) }

                            Button(String.localized("Open page")) {
                                NSWorkspace.shared.open(githubPrompt.verificationURL)
                            }
                        }
                    }
                }
            }

            // **Its own `if`, not the tail of that chain.** A provider can want
            // both a route picker *and* a credential — Volcengine does: the
            // `arkcli` route needs nothing pasted and the signed-endpoint route
            // needs an access key pair. Chained behind `hasSourceChoice` the
            // field was never drawn at all, so the endpoint route it belongs to
            // could not be configured from Settings by any means. A divider
            // where both are shown, and none where the picker was not.
            if account.provider.hasSourceChoice, account.provider.usesAPIKey {
                SettingsRowDivider()
            }

            if account.provider.usesAPIKey {
                // Takes precedence over the key OpenCode saved for itself —
                // see OpenCodeGoUsageService for why that way round.
                // What this provider wants is not always a key. Ollama has no
                // quota API, so the figures come from its signed-in settings
                // page and a browser session is the only credential there is —
                // calling it an API key would send people looking for one that
                // does not exist.
                SettingsRow(
                    account.provider.usesSessionCookie
                        ? String.localized("Session cookie")
                        : account.provider.usesKeyPair
                            ? String.localized("Access keys")
                            // Devin's is a token *and* an organization, and
                            // calling it an API key sends people looking for a
                            // page that issues one. There isn't one.
                            : account.provider == .devin
                                ? String.localized("Token and organization")
                                : String.localized("API key"),
                    subtitle: Self.keySubtitle(for: account.provider)
                ) {
                    HStack(spacing: 8) {
                        SecureField("", text: $apiKey)
                            .focused($credentialFocused)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .onSubmit { saveKey(for: account) }

                        Button(String.localized("Save")) { saveKey(for: account) }
                            .disabled(apiKey == savedKey)
                    }
                }

                // Only where a browser session *is* the credential. Every
                // other provider borrows a login its own tool stored, and none
                // of them should be going through anybody's cookies to do it.
                if account.provider.readsBrowserStorage {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Read from browser"),
                        // Says which one it will open, and that it may ask —
                        // Chromium keeps its cookies under a key in the login
                        // keychain, and being told a second before the dialog
                        // appears is the difference between a step and a scare.
                        subtitle: sessionMessage
                            ?? Self.browserHint(settings.sessionBrowser(for: account), for: account.provider)
                    ) {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { settings.sessionBrowser(for: account) },
                                set: {
                                    settings.setSessionBrowser($0, for: account)
                                    sessionMessage = nil
                                }
                            )) {
                                Text(localized: "Automatic").tag(BrowserCookies.Browser?.none)

                                // Only what is actually installed. A browser
                                // that isn't there is a choice that can only
                                // fail.
                                // Devin's is in a LevelDB, which only the
                                // Chromium browsers keep — offering Safari or
                                // Firefox there is a choice that cannot work.
                                ForEach(account.provider.usesSessionCookie
                                    ? BrowserCookies.present()
                                    : ChromiumLocalStorage.present()) { browser in
                                    Text(browser.name).tag(BrowserCookies.Browser?.some(browser))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)

                            Button(String.localized("Read")) { readSession(for: account) }
                        }
                    }
                }
            } else {
                // One route, so it is stated rather than offered — but what
                // that route is differs: a server one of them runs while it is
                // open, a login the others already saved. The wording belongs
                // to the provider (`Provider.soleRoute`), where the switch is
                // exhaustive: this was a ternary that gave every provider but
                // Cursor Antigravity's sentence.
                // Primary only. What this row names is the login the
                // provider's own tool stored, and an account Pulse signed in
                // to itself does not use it — `fetchAdded` goes straight over
                // HTTP with the token Pulse holds. Stating the CLI's route
                // there would name a credential this account never touches.
                if account.isPrimary, let route = account.provider.soleRoute {
                    SettingsRow(String.localized("Read usage from"), subtitle: route.note) {
                        Text(route.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                    }
                }
            }

            if account.provider == .deepSeek {
                SettingsRowDivider()
                deepSeekBasisRow
                if settings.deepSeekBasis == .budget {
                    SettingsRowDivider()
                    deepSeekBudgetRow
                }
            }

            // The status line has to be registered before it can report
            // anything, so the control for that follows the choice that needs
            // it.
            if account.isPrimary, account.provider == .claudeCode, source != .endpoint {
                SettingsRowDivider()
                claudeCodeStatusLine
            }
        }
        }
    }

    /// Whether `connection(for:)` has anything to put in its card — the same
    /// four questions it asks, answered before the heading is drawn.
    private func hasConnectionControls(for account: AccountKey) -> Bool {
        guard account.isPrimary else { return false }
        if account.provider.hasSourceChoice { return true }
        if account.provider == .copilot { return true }
        if account.provider.usesAPIKey { return true }
        return account.isPrimary && account.provider.soleRoute != nil
    }

    /// Signing in to another subscription of the same provider, and getting
    /// rid of one.
    ///
    /// Only shown where it can work. The other providers are read from a login
    /// their own tool stored, and that store holds exactly one — a second
    /// account of theirs is not something Pulse can be shown, so offering it
    /// would be a control that cannot do anything.
    @ViewBuilder
    private func accounts(for account: AccountKey) -> some View {
        if account.provider.supportsMultipleAccounts {
            SettingsGroup(String.localized("Accounts")) {
                Group {
                    SettingsRow(
                        account.isPrimary ? String.localized("Add another account") : String.localized("Sign in again…"),
                        // The one thing someone should know before they start:
                        // whose name is on the page that opens.
                        subtitle: String.localized("Opens the provider's own sign-in page.")
                    ) {
                        // One sign-in at a time, and its Cancel, code and
                        // error belong to the provider it was started for:
                        // a Codex device code shown on the Claude Code pane
                        // reads as Claude Code asking for it.
                        if signingIn == account.provider {
                            Button(String.localized("Cancel")) {
                                signInTask?.cancel()
                                signInTask = nil
                                signingIn = nil
                                devicePrompt = nil
                            }
                        } else {
                            Button(String.localized("Sign in…")) {
                                signIn(to: account.provider, replacing: account.isPrimary ? nil : account)
                            }
                            .disabled(signingIn != nil)
                        }
                    }

                    // While a device-code sign-in is waiting, the code is the
                    // whole interaction: it is typed on the provider's page,
                    // not here, and nothing comes back to this Mac.
                    if let devicePrompt, signingIn == account.provider {
                        SettingsRowDivider()
                        SettingsRow(
                            String.localized("Code"),
                            // The sign-in half is not decoration: OpenAI's own
                            // hand-off to a Google account fails with
                            // `token_exchange_failed` when the browser has no
                            // session, and this row is the only place that
                            // says so. Which half is said depends on whether
                            // the provider's own link already carries the
                            // code — telling someone to paste on a page that
                            // filled itself in is an instruction to undo.
                            subtitle: devicePrompt.prefilled
                                ? String.localized("Already on the page. Sign in there first if asked, then approve it.")
                                : String.localized("Copied. Sign in there first if asked, then paste it.")
                        ) {
                            HStack(spacing: 10) {
                                Text(devicePrompt.userCode)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(String.localized("Copy")) { copy(devicePrompt.userCode) }

                                Button(String.localized("Open page")) {
                                    NSWorkspace.shared.open(devicePrompt.verificationURL)
                                }
                            }
                        }
                    }

                    if let signInError, signInError.provider == account.provider {
                        SettingsRowDivider()
                        SettingsRow(String.localized("Sign-in"), subtitle: signInError.message) { EmptyView() }
                    }
                }
                if !account.isPrimary {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Name")) {
                        TextField("", text: Binding(
                            get: { settings.label(for: account) },
                            set: { settings.rename(account, to: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsLayout.controlWidth)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Remove account"),
                        subtitle: String.localized("Forgets its login and takes it off the rail.")
                    ) {
                        Button(String.localized("Remove"), role: .destructive) {
                            AccountCredentialStore.set(nil, for: account)
                            settings.removeAccount(account)
                            pane = .general
                        }
                    }
                }
            }
        }
    }

    /// GitHub's device flow, for Copilot's quota.
    private func startGitHubSignIn() {
        githubError = nil
        githubTask = Task {
            defer {
                // Only the attempt still on screen clears the pane; a cancelled
                // one has already had its state cleared by the button.
                if !Task.isCancelled {
                    githubTask = nil
                    githubPrompt = nil
                }
            }
            do {
                let prompt = try await GitHubDeviceLogin.start()
                githubPrompt = prompt
                // The clipboard is the whole convenience here: GitHub will not
                // pre-fill its field from a link, deliberately, because that is
                // the device-code phishing attack. A paste still leaves the
                // consent where it belongs.
                copy(prompt.userCode)
                NSWorkspace.shared.open(prompt.verificationURL)

                let token = try await GitHubDeviceLogin.awaitToken(prompt)
                try Task.checkCancellation()
                guard APIKeyStore.setKey(token, for: .copilot) else {
                    githubError = String.localized("Couldn't save the login on this Mac.")
                    return
                }
                if pane == .account(AccountKey(.copilot)) {
                    apiKey = token
                    savedKey = token
                }
                store.loadAPIKeys()
                store.refresh(AccountKey(.copilot))
            } catch let failure as GitHubDeviceLogin.Failure {
                if !Task.isCancelled { githubError = failure.message }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { githubError = String.localized("Sign-in was cancelled.") }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func repair(_ remedy: ConnectionRemedy, for account: AccountKey) {
        repairMessages[account.id] = nil
        switch remedy {
        case .signIn:
            if account.provider == .copilot { startGitHubSignIn() }
            else if !account.isPrimary { signIn(to: account.provider, replacing: account) }
        case .editCredential:
            connectionFocusRequest += 1
        case .readBrowser:
            readSession(for: account)
        case .connectStatusLine:
            let installed = StatusLineHook.install()
            hookGeneration += 1
            repairMessages[account.id] = installed
                ? String.localized("Connected. Use Claude Code to send a new reading.")
                : String.localized("Couldn't connect the status line. Open setup help.")
            if installed { store.refresh(account) }
        case .copyCommand(let command):
            copy(command)
            repairMessages[account.id] = String.localized("Copied — run \(command) in your terminal, then retry.")
        case .openApp(let name):
            let candidates = [
                URL.applicationDirectory.appending(path: "\(name).app"),
                URL.homeDirectory.appending(path: "Applications/\(name).app")
            ]
            guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                repairMessages[account.id] = String.localized("Couldn't find \(name). Open setup help.")
                return
            }
            Task {
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    store.refresh(account)
                } catch {
                    repairMessages[account.id] = String.localized("Couldn't open \(name). Open setup help.")
                }
            }
        case .retry: store.refresh(account)
        case .help: NSWorkspace.shared.open(ConnectionRemedy.helpURL(for: account.provider))
        }
    }

    private func endGitHubSignIn() {
        githubTask?.cancel()
        githubTask = nil
        githubPrompt = nil
        githubError = nil
    }

    /// Runs the browser sign-in, then keeps whatever came back.
    private func signIn(to provider: Provider, replacing existing: AccountKey? = nil) {
        signingIn = provider
        signInError = nil

        signInTask = Task {
            defer {
                // Only an attempt that is still the one on screen clears the
                // pane. A cancelled one has already had its state cleared by
                // the button that cancelled it, and by the time it unwinds the
                // user may well have started another — which would otherwise
                // lose its Cancel button and its code to a sign-in nobody is
                // waiting for any more.
                if !Task.isCancelled {
                    signingIn = nil
                    devicePrompt = nil
                    signInTask = nil
                }
            }
            do {
                let credentials: AccountCredentials
                if provider == .grokBot {
                    // Cursor has no OAuth for a third party to drive: its page
                    // takes a challenge and a nonce and the tokens are polled
                    // for afterwards. Nothing comes back to this Mac and there
                    // is no code to type, so this branch shows neither.
                    credentials = try await CursorWebLogin.signIn()
                } else if OAuthLogin.usesDeviceCode(provider) {
                    // A code shown on the provider's own page. No local
                    // port to collide with the CLI's sign-in, and nothing
                    // redirected back to this Mac. Whether the page fills the
                    // code in itself is the provider's decision — GitHub and
                    // OpenAI send no pre-filled link, xAI does — so the code
                    // goes on the clipboard either way and the row's subtitle
                    // follows `DevicePrompt.prefilled`.
                    let prompt = try await OAuthLogin.startDevice(provider)
                    devicePrompt = prompt
                    // On the clipboard the moment it exists, like GitHub's. The
                    // same reason applies here: neither page will pre-fill from
                    // a link, so a paste is the shortest honest route.
                    copy(prompt.userCode)
                    NSWorkspace.shared.open(prompt.verificationURL)
                    credentials = try await OAuthLogin.awaitDevice(prompt, for: provider)
                } else {
                    credentials = try await OAuthLogin.signIn(to: provider)
                }
                // Seeded from whatever the provider said about the account, so
                // two subscriptions are not both offered as "Codex".
                try Task.checkCancellation()
                if let existing, !settings.allAccounts.contains(existing) { return }
                let added = existing ?? settings.addAccount(provider, label: Self.label(for: credentials, provider: provider, in: settings))
                guard AccountCredentialStore.set(credentials, for: added) else {
                    if existing == nil { settings.removeAccount(added) }
                    signInError = (provider, String.localized("Couldn't save the login on this Mac."))
                    return
                }
                store.refresh(added)
                pane = .account(added)
            } catch let failure as OAuthLogin.Failure {
                if !Task.isCancelled { signInError = (provider, failure.message) }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { signInError = (provider, String.localized("Sign-in was cancelled.")) }
            }
        }
    }

    /// What to call a newly added account.
    ///
    /// The part of the address before the "@", because the card's header is
    /// one line at a fixed width and a whole email address spends all of it.
    /// A provider that names nothing gets a number, which at least counts.
    /// Either way it is the user's to change.
    private static func label(for credentials: AccountCredentials, provider: Provider, in settings: AppSettings) -> String {
        if let name = credentials.accountName?.split(separator: "@").first, !name.isEmpty {
            return String(name)
        }

        let existing = settings.extraAccounts.filter { $0.provider == provider }.count
        return "\(provider.displayName) \(existing + 2)"
    }

    /// Registering Pulse as Claude Code's status line is the backup route for
    /// its figures — the main one is the account's usage endpoint. It earns
    /// its place because the stored login expires after a few hours and
    /// nothing here renews it, so the status line covers the gap until Claude
    /// Code is next used. Kept visible and reversible rather than being wired
    /// up behind the user's back.
    private var claudeCodeStatusLine: some View {
        Group {
            SettingsRow(
                String.localized("Claude Code status line"),
                subtitle: String.localized("A backup for when the saved login expires. Your own status line keeps working.")
            ) {
                Button(
                    isHookInstalled
                        ? String.localized("Disconnect")
                        : String.localized("Connect")
                ) {
                    _ = isHookInstalled ? StatusLineHook.uninstall() : StatusLineHook.install()
                    hookGeneration += 1
                    store.refresh()
                }
            }
        }
    }

    private func liveUsage(for account: AccountKey) -> some View {
        let usage = store.usage(for: account)

        return SettingsGroup(String.localized("Current usage")) {
            // Says how current these figures are, and offers to make them
            // current. The rail has the same on a ring click, but nobody
            // reading a settings pane should have to go and find it there.
            SettingsRow(String.localized("Last read")) {
                HStack(spacing: 10) {
                    // `Text`'s relative style keeps counting on its own. A
                    // string worked out once said "just now" for the whole
                    // half hour until something else redrew the view.
                    if let observed = usage.observedAt {
                        Text(observed, style: .relative)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            // Every other date in the app is pinned to the
                            // language chosen in Settings; this one formats
                            // with the environment's locale, which follows the
                            // system. Without this, an English Pulse on a
                            // Chinese Mac prints "4分钟" beside "Refresh".
                            .environment(\.locale, LocalizationSource.locale)
                    } else {
                        Text(localized: "Not yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Button(String.localized("Refresh")) { store.refresh(account) }
                        // Any pass, not just this account.provider's: during a
                        // background one the press would only queue, with
                        // nothing on screen to say so.
                        .disabled(store.isRefreshing)
                }
            }

            SettingsRowDivider()

            if usage.windows.isEmpty {
                SettingsRow(
                    String.localized("No reading"),
                    subtitle: {
                        if case .unavailable(let reason) = usage.state { return reason.message }
                        return nil
                    }()
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(usage.windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(window.name, subtitle: resetText(window)) {
                        Text(window.percentText(remaining: settings.showsRemaining))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                }
            }

            if let plan = usage.plan {
                SettingsRowDivider()
                SettingsRow(String.localized("Plan")) {
                    Text(plan)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            if let credit = usage.creditBalance {
                SettingsRowDivider()
                SettingsRow(String.localized("Credit balance")) {
                    Text(credit)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resetText(_ window: UsageWindow) -> String? {
        // **The same rule as `UsageDetailCard.resetText`, and it has to be
        // stated in both places.** `windowSeconds` is sometimes a sort key
        // rather than a measurement, and printing one here put a figure nobody
        // reported under a heading that reads like a reported one — with the
        // panel's own card, an inch away, deliberately saying nothing.
        guard let resets = window.resetsAt else {
            return window.reportsLength ? window.lengthText : nil
        }
        let formatter = DateFormatter()
        formatter.locale = LocalizationSource.locale
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(resets) ? "jmm" : "MMMdjmm"
        )
        return String.localized("Resets \(formatter.string(from: resets))")
    }

    /// Reading the settings file is cheap but not observable, so a counter
    /// nudges SwiftUI to look again after connecting or disconnecting.
    private var isHookInstalled: Bool {
        _ = hookGeneration
        return StatusLineHook.isInstalled
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(String.localized("Version"), subtitle: updateSubtitle) {
                    if update.canCheck {
                        // Sparkle puts up its own window with whatever it
                        // finds, so this is the same button either way — there
                        // is nothing for Pulse to draw on top of it.
                        Button(
                            update.newer.map { String.localized("Update to \($0.version)") }
                                ?? String.localized("Check now")
                        ) {
                            update.check()
                        }
                        .disabled(update.isChecking)
                    } else {
                        Text(Self.version)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if update.canCheck {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Check automatically"),
                        subtitle: String.localized("Every two hours. Updates are offered, never installed on their own.")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { update.checksAutomatically },
                            set: { update.checksAutomatically = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    String.localized("Usage data"),
                    subtitle: String.localized("Read from each provider's own account. Pulse shows the figures they report; where it has to infer one, the figure itself says so.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // The address itself as the subtitle, not a sentence about it:
                // somebody reading this pane wants to know where the source is,
                // and half of them will want to type it rather than click.
                SettingsRow(
                    String.localized("Source code"),
                    subtitle: "github.com/qunqin24/Pulse"
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(URL(string: "https://github.com/qunqin24/Pulse")!)
                    }
                }
            }

            SettingsGroup(String.localized("Credits")) {
                SettingsRow(
                    "Vinz (@hivinz_)",
                    subtitle: String.localized("Pulse is built from a design he posted on X.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://x.com/hivinz_/status/2092996055248126353")!
                        )
                    }
                }

                SettingsRowDivider()

                SettingsRow(
                    "Lobe Icons",
                    subtitle: String.localized("Provider marks from github.com/lobehub/lobe-icons.")
                ) {
                    EmptyView()
                }

                SettingsRowDivider()

                // Credited for the same reason the icons above are: it is
                // somebody else's work, shipped here. What that data is and
                // where it came from: Docs/decisions/bot-mark-geometry.md.
                SettingsRow(
                    "Morph Bot",
                    subtitle: String.localized("The animated marks are a port of github.com/iduu/grokbot-animation, itself a study of the bot on x.ai.")
                ) {
                    Button(String.localized("Open")) {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/iduu/grokbot-animation")!
                        )
                    }
                }
            }
        }
    }

    /// The version, and what is known about a newer one. All four states are
    /// distinguishable on purpose: "no update" and "couldn't ask" look
    /// identical otherwise, and a check that silently failed is worse than one
    /// that says so.
    private var updateSubtitle: String {
        if let newer = update.newer {
            return .localized("\(Self.version) installed · \(newer.version) available")
        }
        if update.isChecking { return .localized("Checking…") }
        if update.didFail { return .localized("Couldn't reach the update feed.") }
        if !update.canCheck { return .localized("Built from source — no update check.") }
        return .localized("\(Self.version) · up to date")
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1 (prototype)"
    }
}

enum SettingsPane: Hashable {
    case general
    case account(AccountKey)
    /// Every agent's spending added up — a pane whose subject is not a
    /// provider, which is why it sits outside the accounts rather than inside
    /// one of them.
    case spend
    case about
    case integrations

    var title: String {
        switch self {
        case .general: .localized("General")
        // Not "Usage history", which is what a provider's own card is called.
        // Two panes with one name is two places to look for one thing.
        case .spend: .localized("Token spend")
        // Brand names, left as they are in every language.
        // A fallback: the view titles these from the account's own label.
        case .account(let account): account.provider.displayName
        case .about: .localized("About")
        case .integrations: .localized("Developer integrations")
        }
    }

    /// Only meaningful for the panes drawn with an SF Symbol; provider panes
    /// use the provider's own mark instead.
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .spend: "chart.bar"
        case .account: "square.stack.3d.up"
        case .about: "info.circle"
        case .integrations: "terminal"
        }
    }
}

#Preview("Settings") {
    SettingsView(
        store: UsageStore(settings: AppSettings()),
        settings: AppSettings(),
        placement: PanelPlacement(),
        update: AppUpdate(),
        alerts: UsageAlerts(settings: AppSettings()),
        shortcuts: GlobalShortcutMonitor(),
        navigation: SettingsNavigation()
    )
}
