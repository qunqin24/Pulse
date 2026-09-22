import AppKit

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
        updateMenuBarItem()

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

        if settings.needsProviderSelection {
            showProviderSelection(providers: Set(Provider.allCases), isInitial: true)
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
        if settings.hidesMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }

        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "chart.pie.fill",
                accessibilityDescription: "Pulse"
            )
            button.image?.isTemplate = true
            button.toolTip = "Pulse"
        }
        let menu = makeMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populateMenu(menu)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populateMenu(menu)
        return menu
    }

    private func populateMenu(_ menu: NSMenu) {
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

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdate() {
        update.check()
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
