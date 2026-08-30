import AppKit
import SwiftUI

/// The executable's entry point.
///
/// Claude Code runs this same binary as its status line command (see
/// `StatusLineHook`), so that case has to be settled before any of the app
/// starts: it must read stdin, print one line and exit rather than open a
/// window. Hence a separate entry type — `PulseApp` keeps the plain `main()`
/// that `App` provides.
@main
enum PulseMain {
    static func main() {
        if CommandLine.arguments.contains(StatusLineHook.modeArgument) {
            StatusLineHook.runAsStatusLine()
            exit(0)
        }

        // Registering has to run from this executable, since what gets written
        // into Claude Code's settings is this binary's own path.
        if CommandLine.arguments.contains("--install-statusline") {
            print(StatusLineHook.install() ? "installed" : "failed")
            exit(0)
        }
        if CommandLine.arguments.contains("--uninstall-statusline") {
            print(StatusLineHook.uninstall() ? "uninstalled" : "failed")
            exit(0)
        }

        // Before anything reads a setting: running from a bundle changes
        // which `UserDefaults` domain that means.
        LegacyDefaults.migrateIfNeeded()

        PulseApp.main()
    }
}

struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A plain menu rather than a popover: everything Pulse has to say
        // about usage it says in the floating panel, so this is only a way in
        // to settings and out of the app.
        MenuBarExtra("Pulse", systemImage: "chart.pie.fill") {
            MenuBarContent(
                settings: appDelegate.settings,
                update: appDelegate.update,
                openSettings: appDelegate.showSettings
            )
        }
    }
}

private struct MenuBarContent: View {
    let settings: AppSettings
    let update: AppUpdate
    let openSettings: () -> Void

    var body: some View {
        Group {
            // Only when there is one. A permanent "check for updates" item
            // would be a chore offered to everyone so that the rare person who
            // needs it can find it; the check runs on its own daily, and the
            // manual one lives in Settings.
            if let newer = update.newer {
                Button(String.localized("Pulse \(newer.version) is available")) {
                    update.check()
                }

                Divider()
            }

            Button(String.localized("Settings…"), action: openSettings)
                .keyboardShortcut(",")

            Divider()

            Button(String.localized("Quit Pulse")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        // The menu is built once and kept; without a dependency on the
        // language it would still be showing whatever was current at launch.
        // Reading `settings.language` here is what makes SwiftUI rebuild it.
        .id("\(settings.language.rawValue)-\(update.newer?.version ?? "")")
    }
}
