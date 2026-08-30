import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Not private: the menu bar scene reads the language from it so the menu
    /// rebuilds when the language changes.
    let settings = AppSettings.restored()
    /// Not private for the same reason: the menu bar scene shows a newer
    /// version when there is one.
    let update = AppUpdate()
    private let placement = PanelPlacement.restored()
    private lazy var store = UsageStore(settings: settings)

    private var panelController: FloatingPanelController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Keep the registered status line path pointing at wherever this
        // build actually lives, since rebuilding can move it.
        StatusLineHook.repairPathIfNeeded()

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

        // Once ever, and only for someone who has Claude Code. Asked after the
        // panel is up so the app is visibly there before it asks for anything.
        StatusLineHook.offerOnFirstRun()

        store.start()

        let controller = FloatingPanelController(store: store, settings: settings, placement: placement)
        panelController = controller

        settings.onChange = { [weak self] in
            controller.settingsChanged()
            self?.settingsWindow?.refreshTitle()
            // Changing where the figures come from — or how often they're
            // read — should show up now, not at the next tick.
            self?.store.settingsChanged()
        }

        if settings.isPanelVisible {
            controller.show()
        }
    }

    func showSettings() {
        let window = settingsWindow ?? SettingsWindowController(store: store, settings: settings, placement: placement, update: update)
        settingsWindow = window
        window.show()
    }
}
