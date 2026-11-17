import AppKit
import SwiftUI
import Testing
@testable import Pulse

/// The settings window for `Docs/images/settings.webp`, drawn from the current
/// code with throwaway settings rather than captured from a running app:
///
///     PULSE_SETTINGS_SHOT=/tmp/settings-shot swift test --filter SettingsScreenshotRenderTests
///
/// writes `settings-<pane>.png` for a few panes, in English, light, at the
/// display's scale. `settings-appearance.png` is the one in the docs:
/// `cwebp -q 90 settings-appearance.png -o Docs/images/settings.webp`. The
/// window is real, so its title bar and sidebar are drawn (`WindowCapture`).
/// Nothing here checks a pixel; without the variable it is skipped.
@MainActor
@Suite("Settings screenshot", .serialized)
struct SettingsScreenshotRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PULSE_SETTINGS_SHOT"] != nil))
    func render() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PULSE_SETTINGS_SHOT"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        LocalizationSource.use(.english)
        defer { LocalizationSource.use(.system) }

        let (defaults, cleanup) = TestDefaults.make("settings-shot")
        defer { cleanup() }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("settings-shot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // English symbols too: `textformat.size` and its kind draw the
        // system language's own letters otherwise.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(arguments.merging(["AppleLanguages": ["en"], "AppleLocale": "en_US"]) { $1 },
                                                forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let settings = AppSettings(
            enabledAccounts: Set([Provider.claudeCode, .codex, .cursor, .antigravity, .copilot, .grok,
                                  .kimiCode, .deepSeek].map(\.rawValue)),
            defaults: defaults
        )
        let alerts = UsageAlerts(settings: settings, file: scratch.appendingPathComponent("alerts.json"),
                                 outageFile: scratch.appendingPathComponent("outages.json"))
        let store = UsageStore(settings: settings)
        let navigation = SettingsNavigation()

        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)

        let window = WindowCapture.ActiveWindow(
            contentRect: NSRect(origin: WindowCapture.offscreen, size: CGSize(width: 920, height: 660)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let content = NSHostingView(
            rootView: SettingsView(
                store: store, settings: settings, placement: PanelPlacement(), update: AppUpdate(), alerts: alerts,
                shortcuts: GlobalShortcutMonitor(), navigation: navigation, openRecap: { _ in }
            )
            .environment(\.extensionIcons, settings.extensionIcons)
            .environment(\.controlActiveState, .key)
        )
        content.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = content
        window.setFrameOrigin(WindowCapture.offscreen)
        // A switch that is on still comes out grey: AppKit draws it in the
        // accent colour only for a window the window server holds active,
        // which no override here reaches and a test runner cannot become
        // (activation is cooperative since macOS 14).
        window.orderFrontRegardless()
        defer { window.close() }

        for (pane, name) in [(SettingsPane.appearance, "appearance"), (.rings, "rings"), (.placement, "placement")] {
            navigation.open(pane)
            try await Task.sleep(for: .seconds(1.5))
            let image = try #require(WindowCapture.image(of: window), "the window could not be read back")
            let rep = NSBitmapImageRep(cgImage: image)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("settings-\(name).png"))
        }
    }
}
