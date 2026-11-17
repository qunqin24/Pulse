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
/// `cwebp -q 90 settings-appearance.png -o Docs/images/settings.webp`. The window is real — title bar, sidebar and glass are
/// drawn by the window server, which an offscreen `cacheDisplay` cannot do —
/// so it is put on screen far outside every display and read back by its
/// window number, which needs no screen-recording grant for the app's own
/// window. Nothing here checks a pixel; without the variable it is skipped.
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

        let window = ActiveWindow(
            contentRect: NSRect(x: -12_000, y: -12_000, width: 920, height: 660),
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
        window.setFrameOrigin(NSPoint(x: -12_000, y: -12_000))
        // A switch that is on still comes out grey: AppKit draws it in the
        // accent colour only for a window the window server holds active,
        // which no override here reaches and a test runner cannot become
        // (activation is cooperative since macOS 14).
        window.orderFrontRegardless()
        defer { window.close() }

        for (pane, name) in [(SettingsPane.appearance, "appearance"), (.rings, "rings"), (.placement, "placement")] {
            navigation.open(pane)
            try await Task.sleep(for: .seconds(1.5))
            let image = try #require(Self.capture(window.windowNumber), "the window could not be read back")
            let rep = NSBitmapImageRep(cgImage: image)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("settings-\(name).png"))
        }
    }

    /// A window drawn as the active one — coloured traffic lights, full-strength
    /// sidebar — without making the test runner the active app, which would
    /// take focus from whatever the person running it is doing.
    private final class ActiveWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
        @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    }

    /// `CGWindowListCreateImage`, looked up at run time: it is deprecated in
    /// the SDK, and a warning is a failure here, but it is still the one call
    /// that reads back the process's own window without a grant.
    private static func capture(_ windowNumber: Int) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        // Just this window, without its shadow, at the backing scale.
        let includingWindow: UInt32 = 1 << 3
        let ignoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        return create(.null, includingWindow, UInt32(windowNumber), ignoreFraming | bestResolution)?.takeRetainedValue()
    }
}
