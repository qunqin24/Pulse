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

        // Before `LegacyDefaults.migrateIfNeeded()` deliberately: this command
        // reads settings and must not be the thing that migrates them. A
        // status line running it every couple of seconds is not the moment to
        // decide an installation's defaults — the app does that at launch.
        if CommandLine.arguments.contains(UsageReport.modeArgument) {
            exit(UsageReport.run())
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
        // The AppKit delegate owns the status item so it can remove it at
        // runtime. This scene supplies SwiftUI's required app scene without
        // opening a second settings window; AppDelegate owns the real one.
        Settings {
            EmptyView()
        }
    }
}
