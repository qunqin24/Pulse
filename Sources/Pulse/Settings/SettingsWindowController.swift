// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Owns the settings window.
///
/// Pulse runs as an `.accessory` app, so it has no Dock icon and is normally
/// not the active application. A settings window therefore has to activate the
/// app explicitly, or it opens behind whatever the user was looking at. The
/// visible window is AppKit-owned rather than the inert SwiftUI `Settings`
/// scene declared by `PulseApp`, so its activation and lifetime can be handled
/// directly.
@MainActor
final class SettingsWindowController {
    private let store: UsageStore
    private let settings: AppSettings
    private let placement: PanelPlacement
    private let update: AppUpdate
    private let alerts: UsageAlerts
    private let shortcuts: GlobalShortcutMonitor
    private let dock: DockPresence
    private let openRecap: @MainActor (Recap.Period) -> Void
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    init(
        store: UsageStore,
        settings: AppSettings,
        placement: PanelPlacement,
        update: AppUpdate,
        alerts: UsageAlerts,
        shortcuts: GlobalShortcutMonitor,
        dock: DockPresence,
        openRecap: @escaping @MainActor (Recap.Period) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.placement = placement
        self.update = update
        self.alerts = alerts
        self.shortcuts = shortcuts
        self.dock = dock
        self.openRecap = openRecap
    }

    /// Opens on a pane, or on the one last shown. The Dock icon follows the
    /// window (`DockPresence`).
    func show(link: PulseLink? = nil, pane: SettingsPane? = nil) {
        navigation.isWindowVisible = true
        if let link { navigation.open(link, accounts: settings.allAccounts) }
        if let pane { navigation.open(pane) }
        let window = window ?? makeWindow()
        self.window = window

        // The system may have taken the grant away since launch, and this
        // window is the only place Pulse reports it.
        alerts.refreshAuthorization()

        // Centred when it comes up, not when it is already on screen: the
        // recap's "Open Token spend" reaches an open window, which stays put.
        let wasVisible = window.isVisible
        // Only as the window opens, never on a window already in front.
        if !wasVisible, StarRequest.claimIfDue() { navigation.showsStarRequest = true }
        window.makeKeyAndOrderFront(nil)
        if !wasVisible { window.center() }
        dock.apply()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        // 920 × 660 rather than the 760 × 500 it opened at first.
        //
        // The old default was set when the sidebar held four rows. It now holds
        // seventy-seven providers plus every added account, and the general pane a
        // six-group stack — so the window opened already scrolling in both
        // columns, which reads as a window that is broken rather than one that
        // is small. This is the size at which the sidebar shows its accounts
        // without scrolling and a settings group fits whole; `minWidth` /
        // `minHeight` on the view are unchanged, so it can still be dragged
        // down to the old size. It fits a 13-inch display with room over.
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // **The window's title bar and toolbar are SwiftUI's**
        // (`sceneBridgingOptions = [.toolbars, .title]` below): the pane's
        // name as the title, back and forward as its items. That is what
        // gives the window System Settings' look on macOS 26 — the sidebar
        // running up behind the traffic lights, and content fading softly
        // out under the title as it scrolls. Measured in a harness, each of
        // the alternatives missed one half: an `NSToolbar` made here put the
        // sidebar up top but drew a hard band and line under the title,
        // because the soft fade is SwiftUI's and SwiftUI cannot see a toolbar
        // it did not make; no toolbar at all kept the soft fade but the
        // sidebar stopped under the title bar. A transparent title bar turns
        // the fade off altogether and prints scrolled content over the title.
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        dock.track(window)
        window.onClose = { [weak self, weak window] in
            self?.navigation.isWindowVisible = false
            self?.navigation.showsStarRequest = false
            // `close()` runs this before the window is off screen, so the
            // window is named rather than read from `isVisible`.
            self?.dock.apply(closing: window)
        }
        let content = NSHostingView(
            rootView: SettingsView(
                store: store, settings: settings, placement: placement, update: update, alerts: alerts,
                shortcuts: shortcuts, navigation: navigation, openRecap: openRecap
            )
        )
        // A hosting **view**: with a hosting controller, the window binds its
        // title to the controller's, which is nil.
        content.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = content
        return window
    }
}

/// Clicking away from the key field has to end its editing, and on macOS
/// nothing does that by itself: a text field holds first responder until some
/// other view asks for it, and nothing else in this window ever does. So the
/// field kept its focus ring wherever else you clicked, and only changing pane
/// — which tears the field down — let it go.
///
/// The window is the right place for it because it sees the press before
/// anything decides what it landed on, the same reason the floating panel
/// takes its drags here. The test is plain geometry against the field being
/// edited, not a hit test: a hit test asks a hosted SwiftUI tree a question it
/// answers unreliably, and this one only needs "was that inside the box".
///
/// An extension rather than the settings window's own, because the recap
/// window has a text field too.
extension NSWindow {
    func endFieldEditing(ifOutside event: NSEvent) {
        guard event.type == .leftMouseDown, let field = fieldBeingEdited() else { return }
        let box = field.convert(field.bounds, to: nil)
        if !box.contains(event.locationInWindow) { makeFirstResponder(nil) }
    }

    /// The text field the window's field editor is currently working for, or
    /// nil when nothing is being edited.
    func fieldBeingEdited() -> NSView? {
        guard let editor = firstResponder as? NSText, editor.isFieldEditor else { return nil }

        // The field editor is shared and installed into whichever field is
        // active, which it keeps as its delegate.
        if let field = (editor as? NSTextView)?.delegate as? NSView { return field }
        return editor.superview?.superview
    }
}

final class SettingsWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        onClose?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        endFieldEditing(ifOutside: event)
        super.sendEvent(event)
    }
}
