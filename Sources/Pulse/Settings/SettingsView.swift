// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// The settings window: a source list on the left, one pane at a time on the
/// right, each pane a stack of grouped cards.
///
/// This is the shell and nothing else: the sidebar, the heading and the switch
/// that picks a pane. Each pane is its own view in this folder (see
/// `Docs/ui/settings.md`). What has to outlive a pane — the reading behind the
/// Token spend pane, an account's history, a sign-in under way — is held here
/// as a model, because switching panes would otherwise throw it away.
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
    /// Opens the recap window on a period — the one the Token spend pane's button names.
    var openRecap: @MainActor (Recap.Period) -> Void
    private var pane: SettingsPane {
        get { navigation.pane }
        nonmutating set { navigation.pane = newValue }
    }

    /// Narrows the sidebar. Sixteen providers plus every added account is a
    /// list that scrolls on any window worth opening.
    @State private var search = ""
    @State private var spend: SpendPaneModel
    @State private var history: AccountHistoryModel
    @State private var flows: AccountFlows

    init(
        store: UsageStore,
        settings: AppSettings,
        placement: PanelPlacement,
        update: AppUpdate,
        alerts: UsageAlerts,
        shortcuts: GlobalShortcutMonitor,
        navigation: SettingsNavigation,
        openRecap: @escaping @MainActor (Recap.Period) -> Void = { _ in }
    ) {
        self.store = store
        self.settings = settings
        self.placement = placement
        self.update = update
        self.alerts = alerts
        self.shortcuts = shortcuts
        self.navigation = navigation
        self.openRecap = openRecap

        let history = AccountHistoryModel(store: store, settings: settings, navigation: navigation)
        _history = State(initialValue: history)
        _spend = State(initialValue: SpendPaneModel(settings: settings, navigation: navigation))
        _flows = State(initialValue: AccountFlows(
            store: store, settings: settings, navigation: navigation, alerts: alerts, history: history))
    }

    var body: some View {
        // **The sidebar stays.** With the toggle SwiftUI adds, collapsing it and
        // drawing it back at a width that cannot hold the sidebar beside the
        // pane overflowed both ways: the list slid out past the left edge, the
        // pane past the right, and the title bar put up an overflow "»" for
        // items it no longer had room for. A settings window's sidebar is how
        // it is navigated, as System Settings' is; there is nothing to gain by
        // hiding it.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(settings: settings, navigation: navigation, search: search)
                .toolbar(removing: .sidebarToggle)
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
                // 200 was measured, not guessed. Scanning the committed English
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
                //
                // And moved to 220 when `Alibaba Coding Plan` did: 121.4pt of text
                // at the sidebar's 13pt against `Xiaomi Coding Plan`'s 117.3, and
                // with the scroller showing — which it always is now, with
                // seventy-odd rows — 200 cut it to "Alibaba Coding Pl…".
                .frame(minWidth: 220)
                // Still worth setting: these bound what dragging the divider may
                // do. `ideal` matches the frame so first layout and every rebuild
                // land on the same width; `max` keeps a stretched sidebar from
                // eating the pane.
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
                // `.sidebar`, not `.automatic`: at the top of the list, under the
                // traffic lights, as System Settings has it. Automatic would put
                // the field in the window's toolbar, which carries only the title.
                .searchable(
                    text: $search,
                    placement: .sidebar,
                    prompt: Text(localized: "Search")
                )
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Where a new pane scrolls to. The pane's name is the
                        // window's title now, in the toolbar, as System
                        // Settings has it; it used to be drawn here too.
                        Color.clear.frame(height: 0)
                            .id("heading")

                        // Above every pane, for as long as this window stays
                        // open (`StarRequest`).
                        if navigation.showsStarRequest {
                            StarRequestBanner { navigation.showsStarRequest = false }
                        }

                        switch pane {
                        case .appearance: AppearancePane(settings: settings)
                        case .rings: RingsPane(settings: settings)
                        case .placement: PlacementPane(settings: settings, placement: placement)
                        case .general: GeneralPane(settings: settings, shortcuts: shortcuts)
                        case .notifications: NotificationsPane(store: store, settings: settings, alerts: alerts)
                        case .network: NetworkPane(store: store, settings: settings)
                        case .experimental: ExperimentalPane(settings: settings)
                        case .account(let account):
                            AccountPane(
                                account: account, store: store, settings: settings,
                                navigation: navigation, history: history, flows: flows, scroll: proxy
                            )
                        case .spend:
                            TokenSpendPane(settings: settings, model: spend, openRecap: openRecap, scroll: proxy)
                        case .about: AboutPane(update: update)
                        case .integrations: DeveloperIntegrationsView(settings: settings)
                        case .extensions:
                            ExtensionsSettingsView(settings: settings) { navigation.pane = .account($0) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .background(.windowBackground)
                // Keyed on the pane and enabled state, so enabling an account
                // also reconsiders its history's empty-state explanation.
                .task(id: history.key) { await history.load() }
                // A completed read survives sidebar changes in this window.
                // Only an initial visit or Rescan reads; changing the span
                // re-adds up what is already in memory.
                // **Two tasks, because they cost different things.** Reading
                // stores and summarizing their cached ledgers have independent
                // lifetimes. Changing the span must not start another scan.
                //
                // They live here, not in the Token spend pane: leaving the pane
                // or closing the window changes the key, and the release path
                // only runs if a task is still alive to see it.
                .task(id: spend.loadKey) { await spend.load() }
                .task(id: spend.summaryRequest) { await spend.recompute() }
                .onChange(of: navigation.requestID) { proxy.scrollTo("heading", anchor: .top) }
            }
            .navigationTitle(pane.title(in: settings))
            .toolbar {
                // **The toolbar needs an item of its own.** A toolbar with
                // nothing in it is not drawn, and without one the sidebar
                // stops under the title bar instead of running up behind the
                // traffic lights (`SettingsWindowController`). Back and
                // forward are what System Settings puts there.
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        navigation.goBack(where: exists)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .help(String.localized("Back"))
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(navigation.back.isEmpty)

                    Button {
                        navigation.goForward(where: exists)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .help(String.localized("Forward"))
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(navigation.forward.isEmpty)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onChange(of: navigation.requestID) { search = "" }
        // Rebuild everything when the language changes — the strings are read
        // through a plain function, so SwiftUI has nothing else to observe.
        .id(settings.language)
    }

    /// Whether a pane in the history can still be shown: an account's only
    /// while the account exists.
    private func exists(_ pane: SettingsPane) -> Bool {
        if case .account(let account) = pane { return settings.allAccounts.contains(account) }
        return true
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
