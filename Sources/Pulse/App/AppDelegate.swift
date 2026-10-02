// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Not private: the status-item menu reads the language from it so the
    /// menu rebuilds when the language changes.
    let settings = AppSettings.restored()
    /// Not private for the same reason: the status-item menu shows a newer
    /// version when there is one.
    let update = AppUpdate()
    private let placement = PanelPlacement.restored()
    /// Not private: the settings pane shows what the system says about
    /// permission, which is not the same as what the switches say.
    private(set) lazy var alerts = UsageAlerts(settings: settings)
    /// Not private for the same reason: the settings pane is the only place
    /// that can report a combination the window server refused.
    let shortcuts = GlobalShortcutMonitor()
    private lazy var store = UsageStore(settings: settings, alerts: alerts)
    /// Which tab the menu bar's menu last had open, kept between openings.
    private let dashboard = MenuDashboardModel()
    /// Starts usage windows after they reset, for the providers switched on.
    private lazy var primer = WindowPrimer(store: store, settings: settings)
    /// Bumped on every redraw of the status item. A tracking closure re-arms
    /// only while it still holds the latest, so the chain started by each
    /// settings change replaces the one before instead of running beside it.
    private var menuBarGeneration = 0

    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var providerSetupWindow: ProviderSetupWindowController?
    private var preparedClaude = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        settings.onMenuBarIconChange = { [weak self] in
            self?.updateMenuBarItem()
        }

        // **Writing to a pipe whose far end has closed raises SIGPIPE, whose
        // default is to kill the process.** Pulse writes to one: the Codex
        // helper's standard input. So that helper exiting — crashing, being
        // killed with the terminal it was started from, the user quitting
        // Codex — took Pulse down with it, with nothing in the log but
        // "Terminated due to signal 13". Ignored here rather than in
        // `CodexAppServer` because it is a property of the whole process, and
        // because the failure it prevents is not local to the caller that
        // happened to trigger it. The write then returns an error, which
        // `CodexAppServer.write(_:to:)` reads as the helper being gone.
        signal(SIGPIPE, SIG_IGN)

        // Caches whose format changed are invalidated by renaming the file;
        // this takes the orphans away rather than leaving them on disk.
        PulseStorage.removeSupersededFiles()

        // A launch agent left over from a loose build has to be handed over
        // before anything reads the state, or both builds start at login.
        LoginItem.adoptBundleIfNeeded()

        // On by default, decided once — and repaired rather than re-added, so
        // switching it off stays off.
        LoginItem.applyDefaultOnFirstRun()
        LoginItem.repairPathIfNeeded()

        // Daily at most, and only from a bundle — see `AppUpdate`.
        update.checkIfDue()

        settings.onChange = { [weak self] in
            self?.settingsChanged()
        }

        // Same issue, from the other side: a combination that works with no
        // pointer involved. Both unset until somebody sets one.
        shortcuts.on(.openSettings) { [weak self] in self?.showSettings() }
        shortcuts.on(.togglePanel) { [weak self] in
            // Through the setting rather than `controller.toggle()`, so the
            // panel is in the state the switch in settings claims it is, and
            // stays that way across a launch.
            self?.settings.isPanelVisible.toggle()
        }
        shortcuts.apply(settings)
        shortcuts.onRegistrationChange = { [weak self] in
            self?.restoreMenuBarEntryPointIfNeeded()
        }

        // A stored shortcut is only an entry point after Carbon accepts it.
        // Repair an impossible combination before removing the status item,
        // including settings written by a previous build.
        restoreMenuBarEntryPointIfNeeded()
        updateMenuBarItem()

        if settings.needsProviderSelection {
            showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
        } else {
            startMonitoring()
            if !settings.suggestedProviders.isEmpty {
                showProviderSelection(providers: settings.suggestedProviders, isInitial: false)
            }
        }
    }

    private func showProviderSelection(providers: Set<Provider>, isInitial: Bool) {
        let window = ProviderSetupWindowController(settings: settings, providers: providers, isInitial: isInitial)
        providerSetupWindow = window
        window.show()
    }

    private func settingsChanged() {
        restoreMenuBarEntryPointIfNeeded()
        settingsWindow?.refreshTitle()
        providerSetupWindow?.refreshTitle()
        guard !settings.needsProviderSelection else { return }
        if panelController == nil {
            // Enabling a service in Settings is also an initial choice.
            providerSetupWindow?.close()
            startMonitoring()
        } else {
            panelController?.settingsChanged()
            store.settingsChanged()
            prepareClaudeIfSelected()
        }
    }

    private func startMonitoring() {
        guard !settings.needsProviderSelection, panelController == nil else { return }
        alerts.start { [weak self] in self?.showSettings() }
        let controller = FloatingPanelController(store: store, settings: settings, placement: placement)
        panelController = controller
        controller.contextMenu = { [weak self] in self?.panelMenu() ?? NSMenu() }
        if settings.isPanelVisible { controller.show() }
        store.start()
        primer.start()
        prepareClaudeIfSelected()
    }

    private func prepareClaudeIfSelected() {
        let claude = AccountKey(.claudeCode)
        guard settings.isEnabled(claude), !preparedClaude else { return }
        preparedClaude = true
        // Let the selection window close before either system prompt appears.
        Task { [weak self] in
            guard let self else { return }
            guard self.settings.isEnabled(claude) else {
                self.preparedClaude = false
                return
            }
            StatusLineHook.repairPathIfNeeded()
            ClaudeDesktopSession.requestPermissionAtLaunch(
                willBeUsed: [.automatic, .desktopApp].contains(self.settings.source(for: claude))
            ) { [weak self] in
                guard let self, self.settings.isEnabled(claude) else { return }
                self.store.refresh(claude)
            }
            StatusLineHook.offerOnFirstRun(willBeUsed: self.settings.isEnabled(claude))
        }
    }

    func showSettings() {
        showSettings(link: nil)
    }

    /// The rail's own menu: the same three things the menu bar offers, because
    /// this exists for the Mac where that menu cannot be reached.
    ///
    /// Built on each click rather than kept, so an update found since the last
    /// one is on it — an `NSMenu` held as a property would still be showing
    /// whatever was true when it was made.
    private func panelMenu() -> NSMenu {
        makeMenu()
    }

    private func updateMenuBarItem() {
        restoreMenuBarEntryPointIfNeeded()
        if settings.hidesMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = makeMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        showMenuBarReading()
    }

    /// The menu bar item's face: Pulse's mark alone, or — with
    /// `showsUsageInMenuBar` on — the mark of the account whose ring is
    /// fullest and that ring's percentage, red past the warning line.
    ///
    /// Re-read whenever anything it reads changes: the tracking is armed
    /// again on every change, because `withObservationTracking` fires once.
    private func showMenuBarReading() {
        guard let button = statusItem?.button else { return }
        menuBarGeneration += 1
        let generation = menuBarGeneration
        let (reading, remaining, style, label) = withObservationTracking {
            let reading = settings.showsUsageInMenuBar
                ? MenuBarReading.choose(
                    among: settings.shownAccounts,
                    chosen: settings.menuBarAccount.flatMap(AccountKey.init(id:)),
                    usage: store.usage(for:),
                    pinned: settings.pinnedWindow(for:),
                    warningAt: settings.warningThreshold.fraction
                )
                : nil
            // The label inside too: renaming the account is a change to show.
            return (reading, settings.showsRemaining, settings.menuBarStyle,
                    reading.map { settings.label(for: $0.account) })
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.menuBarGeneration == generation else { return }
                self.showMenuBarReading()
            }
        }

        MenuBarReading.draw(reading, remaining: remaining, style: style, label: label, on: button)
    }

    /// An accessory app has no Dock icon. When the panel is also hidden, a
    /// successfully registered global shortcut is the only replacement for
    /// the status item; a stored shortcut that Carbon refused does not count.
    /// Internal and pure so the launch-safety rule can be pinned by a test.
    nonisolated static func menuBarIconMustRemainVisible(
        panelVisible: Bool,
        hasRegisteredShortcut: Bool
    ) -> Bool {
        !panelVisible && !hasRegisteredShortcut
    }

    private func restoreMenuBarEntryPointIfNeeded() {
        guard settings.hidesMenuBarIcon,
              Self.menuBarIconMustRemainVisible(
                  // Before a provider is selected there is no panel controller,
                  // whatever the persisted visibility preference says.
                  panelVisible: !settings.needsProviderSelection && settings.isPanelVisible,
                  hasRegisteredShortcut: shortcuts.hasRegisteredEntryPoint
              )
        else { return }
        settings.hidesMenuBarIcon = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Only the menu bar's menu: the rail's own menu opens beside the rings
        // it would be repeating.
        if menu === statusItem?.menu { addDashboard(to: menu) }
        populateMenu(menu)
    }

    /// The tabbed view at the top of the menu bar's menu, and the items that
    /// go with whichever tab is open. See `MenuDashboard`.
    private func addDashboard(to menu: NSMenu) {
        guard !settings.needsProviderSelection, !settings.shownAccounts.isEmpty else { return }

        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.rootView = AnyView(MenuDashboard(
            store: store,
            settings: settings,
            model: dashboard,
            onResize: { [weak hosting] size in
                // The menu lays itself out from its items' frames, so a tab
                // of a different height has to say so here.
                guard let hosting, hosting.frame.size != size else { return }
                hosting.setFrameSize(size)
            }
        ))
        hosting.setFrameSize(hosting.fittingSize)
        item.view = hosting
        menu.addItem(item)
        menu.addItem(.separator())

        let page = NSMenuItem(title: "", action: #selector(openUsagePage(_:)), keyEquivalent: "")
        page.target = self
        page.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        menu.addItem(page)

        let refresh = NSMenuItem(title: .localized("Refresh"), action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refresh)
        menu.addItem(.separator())

        // The page item names the open tab's provider, and is there only when
        // that provider has a page Pulse knows.
        let showPage = { [weak self, weak page] in
            guard let self, let page else { return }
            let account = self.dashboard.selected.flatMap(AccountKey.init(id:))
                .flatMap { self.settings.shownAccounts.contains($0) ? $0 : nil }
            if let account, let url = account.provider.usagePage {
                page.title = .localized("Open \(account.provider.displayName) usage page")
                page.representedObject = url
                page.isHidden = false
            } else {
                page.isHidden = true
            }
        }
        dashboard.onSelect = showPage
        showPage()
    }

    @objc private func openUsagePage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func togglePanelFromMenu() {
        settings.isPanelVisible.toggle()
    }

    @objc private func refreshAll() {
        store.refresh()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
        // With no service chosen there is no rail, and nothing else on screen
        // says why. Rebuilt on every open, so it goes once a choice is made.
        if settings.needsProviderSelection {
            let item = NSMenuItem(
                title: .localized("Choose services to start monitoring…"),
                action: #selector(chooseServices),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let newer = update.newer {
            let item = NSMenuItem(
                title: .localized("Pulse \(newer.version) is available"),
                action: #selector(checkForUpdate),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Some people want the menu bar and nothing at the screen's edge. The
        // switch lives in Settings → Position too; here it is one click from
        // where such a person already is. Through the setting, like the
        // shortcut, so a hidden panel stays hidden across a launch and hiding
        // the last way back brings the menu bar icon back (`settingsChanged`).
        if !settings.needsProviderSelection {
            let panelItem = NSMenuItem(
                title: .localized("Show floating panel"),
                action: #selector(togglePanelFromMenu),
                keyEquivalent: ""
            )
            panelItem.target = self
            panelItem.state = settings.isPanelVisible ? .on : .off
            menu.addItem(panelItem)
        }

        let settingsItem = NSMenuItem(
            title: .localized("Settings…"),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: .localized("Quit Pulse"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    @objc private func chooseServices() {
        providerSetupWindow?.close()
        showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdate() {
        update.check()
    }

    /// Opening Pulse while it is already running — a double-click in
    /// Applications, Spotlight, Launchpad — opens Settings.
    ///
    /// An accessory app has no Dock icon, and with the panel and the menu bar
    /// icon both hidden (allowed once a global shortcut is registered) nothing
    /// of it is on screen. A forgotten shortcut then left no way back short
    /// of Activity Monitor; opening the app again is the way everybody tries
    /// first, and it did nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Before a service is chosen the chooser is the way in, not Settings —
        // the one already open brought forward rather than a second made.
        if settings.needsProviderSelection {
            if let chooser = providerSetupWindow {
                chooser.show()
            } else {
                showProviderSelection(providers: Set(Provider.builtIn), isInitial: true)
            }
        } else {
            showSettings()
        }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = PulseLink(url: url) { showSettings(link: link) }
        }
    }

    private func showSettings(link: PulseLink?) {
        let window = settingsWindow ?? SettingsWindowController(store: store, settings: settings, placement: placement, update: update, alerts: alerts, shortcuts: shortcuts)
        settingsWindow = window
        window.show(link: link)
    }
}
