import AppKit
import SwiftUI

/// Owns the settings window.
///
/// Pulse runs as an `.accessory` app, so it has no Dock icon and is normally
/// not the active application. A settings window therefore has to activate the
/// app explicitly, or it opens behind whatever the user was looking at. That
/// is also why this is a plain `NSWindowController` rather than SwiftUI's
/// `Settings` scene: the window's activation and lifetime need to be handled
/// directly.
@MainActor
final class SettingsWindowController {
    private let store: UsageStore
    private let settings: AppSettings
    private let placement: PanelPlacement
    private let update: AppUpdate
    private var window: NSWindow?

    init(store: UsageStore, settings: AppSettings, placement: PanelPlacement, update: AppUpdate) {
        self.store = store
        self.settings = settings
        self.placement = placement
        self.update = update
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.title = String.localized("Pulse Settings")

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    /// Re-reads the title, which is set once at creation but has to follow a
    /// language change while the window is open.
    func refreshTitle() {
        window?.title = String.localized("Pulse Settings")
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // These two go together, and the pairing is the whole point.
        //
        // `.fullSizeContentView` lets the scrolling content run under the
        // title bar, so it is *blurred away* as you scroll rather than being
        // chopped off at a hard edge. Nothing is hidden at rest: AppKit
        // reports the bar as a 52pt top safe area and the scroll view already
        // insets by it.
        //
        // But that only works if something actually draws up there. A
        // transparent title bar draws nothing, so the scrolled content came
        // straight through and printed over "Pulse Settings" — which is the
        // bug this pairing fixes. Opaque means AppKit's own material does the
        // blurring.
        //
        // Measured, in case it comes up: the sidebar does *not* run behind the
        // traffic lights either way. AppKit gives that treatment to an
        // `NSSplitViewController` with a sidebar item, and SwiftUI's
        // `NavigationSplitView` inside an `NSHostingView` doesn't get it —
        // neither `.fullSizeContentView` nor a unified `NSToolbar` changes it.
        window.titlebarAppearsTransparent = false
        // The documented "hairline once content is scrolled under it" setting.
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(store: store, settings: settings, placement: placement, update: update)
        )
        return window
    }
}
