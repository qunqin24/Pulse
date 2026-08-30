import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Not private: the menu bar scene reads the language from it so the menu
    /// rebuilds when the language changes.
    let settings = AppSettings.restored()
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

        // On by default, decided once — and repaired rather than re-added, so
        // switching it off stays off.
        LoginItem.applyDefaultOnFirstRun()
        LoginItem.repairPathIfNeeded()

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
        let window = settingsWindow ?? SettingsWindowController(store: store, settings: settings, placement: placement)
        settingsWindow = window
        window.show()
    }
}
