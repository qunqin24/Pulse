import AppKit
import SwiftUI

/// Reports when the pointer enters the view it is attached to.
///
/// SwiftUI's own `.onHover` installs a tracking area scoped to the active
/// application. Pulse runs as an `.accessory` app behind a non-activating
/// panel that can never become key (see `FloatingPanelController`), so it is
/// essentially never the active app and `.onHover` would stay silent. This
/// uses an `.activeAlways` tracking area instead, which reports regardless of
/// which app is frontmost.
///
/// Only entering is reported, deliberately. Exit events are not trustworthy
/// here: the panel resizes itself whenever the details card opens, and the
/// resulting layout passes can fire exits while the pointer has not moved at
/// all. Whether the pointer has really left is answered by
/// `PanelPointerWatcher` instead.
///
/// Attach it as a background so it takes the frame of whatever it is tracking:
///
///     someView.background(PointerEntryReporter { ... })
struct PointerEntryReporter: NSViewRepresentable {
    let onEnter: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onEnter = onEnter
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onEnter = onEnter
    }

    final class TrackingView: NSView {
        var onEnter: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            // `.inVisibleRect` keeps the area sized to the view on its own, so
            // it is installed once and left alone. Tearing it down and adding
            // it back on every layout pass is itself a source of phantom
            // enter/exit events.
            guard trackingAreas.isEmpty else { return }

            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) {
            onEnter?()
        }
    }
}

/// Pointing-hand cursor and a hover flag for a control on the floating panel.
///
/// `.onHover` is silent here (the panel never becomes key). Clicks on the
/// details card belong to SwiftUI, so `hitTest` returns nil and the button
/// underneath still receives them. Tracking still fires: it is the area, not
/// the hit test, that decides enter and leave.
struct PointerHand: NSViewRepresentable {
    var onHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> HandView {
        let view = HandView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: HandView, context: Context) {
        view.onHover = onHover
    }

    final class HandView: NSView {
        var onHover: (Bool) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            guard trackingAreas.isEmpty else { return }
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
            onHover(false)
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }
    }
}
