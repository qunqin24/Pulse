import AppKit
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
    /// The provider a browser sign-in is currently open for, and what went
    /// wrong with the last one.
    @State private var signingIn: Provider?
    @State private var signInError: String?
    /// Shown while a device-code sign-in is waiting: the code the provider
    /// gave, and where to type it.
    @State private var devicePrompt: OAuthLogin.DevicePrompt?
    /// What the last look through the browsers found.
    @State private var sessionMessage: String?
    /// Held so it can be called off. A device-code sign-in polls for fifteen
    /// minutes, and a sign-in that failed in the browser gives this side no
    /// sign at all — without a way out the button stays disabled for the whole
    /// quarter of an hour.
    @State private var signInTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section(String.localized("Panel")) {
                    row(.general)
                }

                Section(String.localized("Accounts")) {
                    // Same order as the rail: a sidebar that disagreed with
                    // the thing it configures is its own small confusion.
                    ForEach(settings.orderedAccounts) { account in
                        row(.account(account))
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
                    case .account(let account): accountPane(account)
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

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(title(pane))
        } icon: {
            switch pane {
            case .account(let account):
                LobeIconView(provider: account.provider, size: 14)
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
                ForEach(Array(settings.orderedAccounts.enumerated()), id: \.element) { index, account in
                    if index > 0 { SettingsRowDivider() }

                    SettingsRow(
                        settings.label(for: account),
                        // Moving something the rail isn't drawing looks like
                        // the arrow did nothing; saying so is kinder than
                        // hiding the row and renumbering everything.
                        subtitle: settings.isEnabled(account) ? nil : String.localized("Not shown"),
                        icon: account.provider
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
    private static func browserHint(_ chosen: BrowserCookies.Browser?) -> String {
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
            let found = await Task.detached(priority: .userInitiated) {
                BrowserCookies.session(forHost: "ollama.com", allowing: browsers) {
                    try? OllamaSessionCookie.normalize($0)
                }
            }.value

            if let found {
                apiKey = found.header
                saveKey(for: account)
                sessionMessage = String.localized("Read from \(found.browser.name).")
                return
            }

            sessionMessage = String.localized("No Ollama session found. Sign in at ollama.com first.")
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
    }

    private func accountPane(_ account: AccountKey) -> some View {
        let provider = account.provider
        return accountPaneBody(account, provider)
    }

    private func accountPaneBody(_ account: AccountKey, _ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 22) {
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
            }

            connection(for: account)

            accounts(for: account)

            liveUsage(for: account)

            // Both are built from the transcripts the CLI leaves behind, so
            // for a provider that keeps none they would be a column of zeroes
            // claiming nothing had been spent — and for an account Pulse
            // signed in to itself they would be worse than that. Those
            // transcripts belong to whichever account the CLI is signed in to,
            // which is not this one, so showing them here would report one
            // account's spending under another's name.
            if provider.keepsLocalTranscripts, account.isPrimary {
                estimatedValue(for: account)

                history(for: account)
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
                        ? String.localized("Reading logs")
                        : String.localized("No history yet"),
                    subtitle: loadingHistory == account.provider
                        ? nil
                        : String.localized("Nothing has been logged on this Mac yet, so there is no history to add up.")
                ) {
                    if loadingHistory == account.provider {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }

    private func loadHistory() async {
        // History is per provider — it is read from that CLI's transcripts,
        // which do not say which account was signed in at the time.
        guard case .account(let account) = pane else { return }
        let provider = account.provider

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

    /// Where a provider's figures come from, plus anything that route needs
    /// setting up.
    private func connection(for account: AccountKey) -> some View {
        let source = settings.source(for: account)

        return SettingsGroup(String.localized("Connection")) {
            // A account.provider with a single route gets told, not asked. A picker
            // with one entry is a control that cannot do anything.
            if account.provider.hasSourceChoice {
                SettingsRow(
                    String.localized("Read usage from"),
                    subtitle: source.detail(for: account.provider)
                ) {
                    Picker("", selection: Binding(
                        get: { settings.source(for: account) },
                        set: { settings.setSource($0, for: account) }
                    )) {
                        ForEach(UsageSource.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.controlWidth, alignment: .trailing)
                }
            } else if account.provider.usesAPIKey {
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
                        : String.localized("API key"),
                    subtitle: account.provider.usesSessionCookie
                        ? String.localized("Copied from your browser. Stored encrypted on this Mac.")
                        : String.localized("Stored encrypted on this Mac.")
                ) {
                    HStack(spacing: 8) {
                        SecureField("", text: $apiKey)
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
                if account.provider.usesSessionCookie {
                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Read from browser"),
                        // Says which one it will open, and that it may ask —
                        // Chromium keeps its cookies under a key in the login
                        // keychain, and being told a second before the dialog
                        // appears is the difference between a step and a scare.
                        subtitle: sessionMessage ?? Self.browserHint(settings.sessionBrowser(for: account))
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
                                ForEach(BrowserCookies.present()) { browser in
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
                // open, a login the other one already saved.
                let route = account.provider == .cursor
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
            if account.provider == .claudeCode, source != .endpoint {
                SettingsRowDivider()
                claudeCodeStatusLine
            }
        }
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
                if account.isPrimary {
                    SettingsRow(
                        String.localized("Add another account"),
                        // The one thing someone should know before they start:
                        // whose name is on the page that opens.
                        subtitle: String.localized("Opens the provider's own sign-in page.")
                    ) {
                        if signingIn == nil {
                            Button(String.localized("Sign in…")) { signIn(to: account.provider) }
                        } else {
                            Button(String.localized("Cancel")) {
                                signInTask?.cancel()
                                signInTask = nil
                                signingIn = nil
                                devicePrompt = nil
                            }
                        }
                    }

                    // While a device-code sign-in is waiting, the code is the
                    // whole interaction: it is typed on the provider's page,
                    // not here, and nothing comes back to this Mac.
                    if let devicePrompt {
                        SettingsRowDivider()
                        SettingsRow(
                            String.localized("Code"),
                            subtitle: String.localized("Enter it on the page that opened.")
                        ) {
                            HStack(spacing: 10) {
                                Text(devicePrompt.userCode)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(String.localized("Open page")) {
                                    NSWorkspace.shared.open(devicePrompt.verificationURL)
                                }
                            }
                        }
                    }

                    if let signInError {
                        SettingsRowDivider()
                        SettingsRow(String.localized("Sign-in"), subtitle: signInError) { EmptyView() }
                    }
                } else {
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

    /// Runs the browser sign-in, then keeps whatever came back.
    private func signIn(to provider: Provider) {
        signingIn = provider
        signInError = nil

        signInTask = Task {
            defer {
                signingIn = nil
                devicePrompt = nil
                signInTask = nil
            }
            do {
                let credentials: AccountCredentials
                if OAuthLogin.usesDeviceCode(provider) {
                    // A code the user types on the provider's own page. No
                    // local port to collide with the CLI's sign-in, and
                    // nothing redirected back to this Mac.
                    let prompt = try await OAuthLogin.startDevice(provider)
                    devicePrompt = prompt
                    NSWorkspace.shared.open(prompt.verificationURL)
                    credentials = try await OAuthLogin.awaitDevice(prompt, for: provider)
                } else {
                    credentials = try await OAuthLogin.signIn(to: provider)
                }
                // Seeded from whatever the provider said about the account, so
                // two subscriptions are not both offered as "Codex".
                let added = settings.addAccount(provider, label: Self.label(for: credentials, provider: provider, in: settings))
                guard AccountCredentialStore.set(credentials, for: added) else {
                    settings.removeAccount(added)
                    signInError = String.localized("Couldn't save the login on this Mac.")
                    return
                }
                store.refresh(added)
                pane = .account(added)
            } catch let failure as OAuthLogin.Failure {
                signInError = failure.message
            } catch is CancellationError {
                signInError = nil
            } catch {
                signInError = String.localized("Sign-in was cancelled.")
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
    case account(AccountKey)
    case about

    var title: String {
        switch self {
        case .general: .localized("General")
        // Brand names, left as they are in every language.
        // A fallback: the view titles these from the account's own label.
        case .account(let account): account.provider.displayName
        case .about: .localized("About")
        }
    }

    /// Only meaningful for the panes drawn with an SF Symbol; provider panes
    /// use the provider's own mark instead.
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .account: "square.stack.3d.up"
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
