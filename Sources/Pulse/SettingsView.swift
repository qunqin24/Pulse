import SwiftUI

/// The settings window: a source list on the left, one pane at a time on the
/// right, each pane a stack of grouped cards.
struct SettingsView: View {
    let store: UsageStore
    let settings: AppSettings
    let placement: PanelPlacement
    let update: AppUpdate

    @State private var pane: SettingsPane = .general
    @State private var hookGeneration = 0
    /// Login-item state lives with the system, not in `AppSettings`, so it is
    /// read back rather than stored — and nudged when it changes.
    @State private var loginGeneration = 0

    /// Read from the CLIs' own transcripts, which takes long enough on a cold
    /// start to be worth holding on to while the window is open.
    @State private var ledgers: [Provider: UsageLedger] = [:]
    @State private var codexAccount: CodexAccountUsage?
    @State private var loadingHistory: Provider?
    /// The key field's contents. Seeded from the store when the pane opens;
    /// the store is a file, not something SwiftUI can observe.
    @State private var apiKey = ""
    @State private var savedKey = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section(String.localized("Panel")) {
                    row(.general)
                }

                Section(String.localized("Providers")) {
                    // Same order as the rail: a sidebar that disagreed with
                    // the thing it configures is its own small confusion.
                    ForEach(settings.orderedProviders) { provider in
                        row(.provider(provider))
                    }
                }

                Section(String.localized("Application")) {
                    row(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading

                    switch pane {
                    case .general: general
                    case .provider(let provider): providerPane(provider)
                    case .about: about
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(.windowBackground)
            .task(id: pane) { await loadHistory() }
        }
        // No `navigationTitle`: each pane already prints its own heading, and
        // the toolbar would repeat it right above.
        .frame(minWidth: 720, minHeight: 460)
        // Rebuild everything when the language changes — the strings are read
        // through a plain function, so SwiftUI has nothing else to observe.
        .id(settings.language)
    }

    private var heading: some View {
        HStack(spacing: 9) {
            if case .provider(let provider) = pane {
                LobeIconView(provider: provider, size: 19)
            }

            Text(pane.title)
                .font(.system(size: 17, weight: .semibold))
        }
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            switch pane {
            case .provider(let provider):
                LobeIconView(provider: provider, size: 14)
            case .general, .about:
                Image(systemName: pane.symbol)
            }
        }
        .tag(pane)
    }

    // MARK: - Panes

    private var general: some View {
        VStack(alignment: .leading, spacing: 22) {
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
                    String.localized("Percentages on top"),
                    subtitle: String.localized("Only when the panel is docked to the top.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.topRailShowsPercentages },
                        set: { settings.topRailShowsPercentages = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsGroup(String.localized("Order")) {
                // Arrows rather than dragging. Four rows is not enough to make
                // a drag worth learning, and a drag that misses does something
                // — an arrow that misses does nothing.
                ForEach(Array(settings.orderedProviders.enumerated()), id: \.element) { index, provider in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        provider.displayName,
                        // Moving something the rail isn't drawing looks like
                        // the arrow did nothing; saying so is kinder than
                        // hiding the row and renumbering everything.
                        subtitle: settings.isEnabled(provider) ? nil : String.localized("Not shown"),
                        icon: provider
                    ) {
                        HStack(spacing: 4) {
                            Button {
                                settings.move(provider, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel(String.localized("Move \(provider.displayName) up"))

                            Button {
                                settings.move(provider, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == settings.orderedProviders.count - 1)
                            .accessibilityLabel(String.localized("Move \(provider.displayName) down"))
                        }
                        .buttonStyle(.borderless)
                    }
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

    private func saveKey(for provider: Provider) {
        // Only call it saved if it was. Otherwise the Save button greys out
        // over a key that never reached disk.
        guard APIKeyStore.setKey(apiKey, for: provider) else { return }
        savedKey = apiKey
        // The store keeps keys for the life of the launch, so it has to be
        // told; otherwise the key is saved and nothing uses it until restart.
        store.loadAPIKeys()
        // And a key is only worth entering if something tries it now.
        store.refresh(provider)
    }

    private func providerPane(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(String.localized("Panel")) {
                SettingsRow(String.localized("Show in panel")) {
                    Toggle("", isOn: Binding(
                        get: { settings.isEnabled(provider) },
                        set: { settings.setEnabled($0, for: provider) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    // The last one standing can't be switched off: an empty
                    // rail has nothing to hover and nothing to drag.
                    .disabled(settings.isEnabled(provider) && settings.enabledProviders.count == 1)
                }

                SettingsRowDivider()

                ringWindowRow(for: provider)
            }

            connection(for: provider)

            liveUsage(for: provider)

            // Both are built from the transcripts the CLIs leave behind, so
            // for a provider that keeps none they would be a column of zeroes
            // claiming nothing had been spent.
            if provider.keepsLocalTranscripts {
                estimatedValue(for: provider)

                history(for: provider)
            }
        }
        .onChange(of: provider, initial: true) { _, shown in
            guard shown.usesAPIKey else { return }
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
    private func estimatedValue(for provider: Provider) -> some View {
        let ledger = ledgers[provider] ?? .empty
        let estimates = store.usage(for: provider).windows.compactMap { window in
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
    private func history(for provider: Provider) -> some View {
        if let ledger = ledgers[provider], !ledger.days.isEmpty {
            AccountUsageCard(
                provider: provider,
                ledger: ledger,
                credits: provider == .codex ? codexAccount : nil
            )
        } else {
            SettingsGroup(String.localized("Usage history")) {
                SettingsRow(
                    loadingHistory == provider
                        ? String.localized("Reading logs")
                        : String.localized("No history yet"),
                    subtitle: loadingHistory == provider
                        ? nil
                        : String.localized("Nothing has been logged on this Mac yet, so there is no history to add up.")
                ) {
                    if loadingHistory == provider {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    private func loadHistory() async {
        guard case .provider(let provider) = pane else { return }

        loadingHistory = provider
        defer { loadingHistory = nil }

        // Refreshed rather than reused: the session running right now is
        // appending to a log as this is read, and only that file is re-parsed.
        ledgers[provider] = await UsageLedgerReader.shared.ledger(for: provider, refresh: true)

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
    private func ringWindowRow(for provider: Provider) -> some View {
        let usage = store.usage(for: provider)

        return SettingsRow(
            String.localized("Ring shows"),
            subtitle: String.localized("Which limit the rail's ring tracks.")
        ) {
            Picker("", selection: Binding(
                get: {
                    let pinned = settings.pinnedWindow(for: provider)
                    // Show "automatic" when the pin no longer matches anything.
                    return usage.windows.contains { $0.id == pinned } ? pinned : nil
                },
                set: { settings.setPinnedWindow($0, for: provider) }
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

    /// Where a provider's figures come from, plus anything that route needs
    /// setting up.
    private func connection(for provider: Provider) -> some View {
        let source = settings.source(for: provider)

        return SettingsGroup(String.localized("Connection")) {
            // A provider with a single route gets told, not asked. A picker
            // with one entry is a control that cannot do anything.
            if provider.hasSourceChoice {
                SettingsRow(
                    String.localized("Read usage from"),
                    subtitle: source.detail(for: provider)
                ) {
                    Picker("", selection: Binding(
                        get: { settings.source(for: provider) },
                        set: { settings.setSource($0, for: provider) }
                    )) {
                        ForEach(UsageSource.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            } else if provider.usesAPIKey {
                // Takes precedence over the key OpenCode saved for itself —
                // see OpenCodeGoUsageService for why that way round.
                SettingsRow(
                    String.localized("API key"),
                    subtitle: String.localized("Stored encrypted on this Mac.")
                ) {
                    HStack(spacing: 8) {
                        SecureField("", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: SettingsLayout.controlWidth)
                            .onSubmit { saveKey(for: provider) }

                        Button(String.localized("Save")) { saveKey(for: provider) }
                            .disabled(apiKey == savedKey)
                    }
                }
            } else {
                // One route, so it is stated rather than offered — but what
                // that route is differs: a server one of them runs while it is
                // open, a login the other one already saved.
                let route = provider == .cursor
                    ? (name: String.localized("Cursor's own login"),
                       note: String.localized("Uses the login Cursor already saved."))
                    : (name: String.localized("Antigravity's language server"),
                       note: String.localized("Only while Antigravity is open."))

                SettingsRow(String.localized("Read usage from"), subtitle: route.note) {
                    Text(route.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            }

            // The status line has to be registered before it can report
            // anything, so the control for that follows the choice that needs
            // it.
            if provider == .claudeCode, source != .endpoint {
                SettingsRowDivider()
                claudeCodeStatusLine
            }
        }
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

    private func liveUsage(for provider: Provider) -> some View {
        let usage = store.usage(for: provider)

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

                    Button(String.localized("Refresh")) { store.refresh(provider) }
                        // Any pass, not just this provider's: during a
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
                        Text(window.percentText)
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
        guard let resets = window.resetsAt else { return window.lengthText }
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
                        subtitle: String.localized("Once a day. Updates are offered, never installed on their own.")
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
                    subtitle: String.localized("Read from each provider's own account. Pulse shows the figures they report and never estimates one of its own.")
                ) {
                    EmptyView()
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
    case provider(Provider)
    case about

    var title: String {
        switch self {
        case .general: .localized("General")
        // Brand names, left as they are in every language.
        case .provider(let provider): provider.displayName
        case .about: .localized("About")
        }
    }

    /// Only meaningful for the panes drawn with an SF Symbol; provider panes
    /// use the provider's own mark instead.
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .provider: "square.stack.3d.up"
        case .about: "info.circle"
        }
    }
}

#Preview("Settings") {
    SettingsView(
        store: UsageStore(settings: AppSettings()),
        settings: AppSettings(),
        placement: PanelPlacement(),
        update: AppUpdate()
    )
}
