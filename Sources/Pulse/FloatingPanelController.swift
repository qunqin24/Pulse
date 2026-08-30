import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    /// The panel's frame, derived from the SwiftUI layer's own layout
    /// constants (`DockLayout` in UsageDockView.swift, `DetailCardLayout` in
    /// UsageDetailCard.swift) so it can never drift out of sync with what
    /// SwiftUI actually draws. Not `private` because
    /// `FloatingUsagePanelView`'s `#Preview` sizes itself from these too.
    ///
    /// **The panel is this size always — it does not grow when the details
    /// card opens.** It used to, and that was the source of a stubborn
    /// glitch: widening the panel moves its left edge, which moves the
    /// coordinate space the SwiftUI content is laid out in. The dock rail's
    /// position *within that space* therefore jumps by the width of the card,
    /// even though its position on screen never changes — and since this all
    /// happens inside the animation that opens the card, SwiftUI dutifully
    /// animates the jump, flinging the rail sideways and sliding it back.
    /// A panel that never resizes cannot do that. The extra width costs
    /// nothing: it is transparent, and macOS routes clicks through the
    /// transparent parts of a non-opaque window.
    enum Layout {
        /// Detail card + its pointer + the gap after it + the dock rail.
        static var width: CGFloat {
            DetailCardLayout.width
                + DetailCardLayout.pointerWidth
                + DetailCardLayout.horizontalGap
                + DockLayout.width
        }
        /// Tall enough for whichever is bigger: the rail with every provider
        /// switched on, or the tallest card that might be shown beside it.
        ///
        /// Both matter. The rail obviously has to fit, but so does the card —
        /// the panel's frame never changes, so a card taller than the window
        /// gets sliced off flat against its edge, which reads as a drawing
        /// bug rather than as a card that didn't fit. Spare height costs
        /// nothing: it is transparent, and macOS routes clicks through the
        /// transparent parts of a non-opaque window.
        static var height: CGFloat { max(DockLayout.maximumHeight, DetailCardLayout.maximumHeight) }
    }

    private let panel: FloatingPanel
    private var hostingView: NSHostingView<FloatingUsagePanelView>?
    private let store: UsageStore
    private let settings: AppSettings
    /// Where the panel is parked. The drag handle writes to this and moves the
    /// window itself; this class reads it when first placing the panel.
    private let placement: PanelPlacement

    init(store: UsageStore, settings: AppSettings, placement: PanelPlacement) {
        self.store = store
        self.settings = settings
        self.placement = placement

        panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()

        let hostingView = NSHostingView(
            rootView: FloatingUsagePanelView(store: store, settings: settings, placement: placement)
        )
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.height
        )
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        self.hostingView = hostingView

        // Choosing an edge in settings only changes the placement; without
        // this the content would mirror while the window stayed where it was,
        // leaving the rail stranded mid-screen.
        placement.onChange = { [weak self] in
            self?.placePanel()
        }

        // What the panel can be picked up by. Collapsed there is no rail on
        // screen to grab, only the sliver — a press in the sixty points of
        // empty air where the rail *would* be must go to whatever is behind
        // the panel, not move it.
        panel.placement = placement
        // Both capture the two objects they need rather than the controller,
        // which owns the panel they are stored on.
        panel.railFrame = { [settings, placement] in
            PanelHitArea.rail(
                edge: placement.edge,
                railHeight: DockLayout.height(for: settings.enabledProviders.count),
                railTop: placement.railTop
            )
        }
        panel.grabArea = { [settings, placement] in
            let railHeight = DockLayout.height(for: settings.enabledProviders.count)
            return placement.isRailExpanded
                ? PanelHitArea.rail(edge: placement.edge, railHeight: railHeight, railTop: placement.railTop)
                : PanelHitArea.strip(edge: placement.edge, railHeight: railHeight, railTop: placement.railTop)
        }
        panel.onClick = { [settings, placement, store] point in
            guard placement.isRailExpanded else { return }
            let providers = Provider.allCases.filter(settings.isEnabled)
            guard let provider = PanelHitArea.provider(
                at: point,
                edge: placement.edge,
                providers: providers,
                railTop: placement.railTop
            ) else { return }
            store.refresh(provider)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        placePanel()
        panel.orderFrontRegardless()
    }

    func toggle() {
        panel.isVisible ? panel.orderOut(nil) : show()
    }

    /// Brings the panel in line with settings that were just changed.
    func settingsChanged() {
        applyCollectionBehavior()

        if settings.isPanelVisible {
            if !panel.isVisible { show() }
            // Switching a provider off shortens the rail, and where the rail
            // sits inside the panel is worked out from its height — so this
            // has to be redone or the rail drifts from where it was left.
            placePanel()
        } else {
            panel.orderOut(nil)
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        applyCollectionBehavior()
    }

    /// Keeps the rail on every ordinary desktop Space while deciding separately
    /// whether it may accompany another app into a full-screen Space.
    ///
    /// `.fullScreenAuxiliary` is the explicit opt-in that made the panel appear
    /// over full-screen apps before this setting existed. `.fullScreenNone` is
    /// the matching public opt-out, so no app inspection, Space polling, or
    /// Accessibility permission is needed.
    private func applyCollectionBehavior() {
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            settings.hidesInFullScreen ? .fullScreenNone : .fullScreenAuxiliary,
            .stationary
        ]
    }

    /// Parks the panel where it was last left.
    ///
    /// The rail's size is passed in because it shortens when a provider is
    /// switched off, and the placement works in terms of the rail rather than
    /// the window — the window is mostly the empty space the card unfolds
    /// into, and the user has never positioned that.
    private func placePanel() {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let layout = placement.layout(
            in: screen.visibleFrame,
            panel: CGSize(width: Layout.width, height: Layout.height),
            rail: CGSize(
                width: DockLayout.width,
                height: DockLayout.height(for: settings.enabledProviders.count)
            )
        )

        panel.setFrame(layout.frame, display: true)
        placement.setRailTop(layout.railTop)

    }
}

/// The panel, which also owns dragging itself around.
///
/// The drag used to be an `NSViewRepresentable` inside the SwiftUI tree, and
/// that turned out to be a bad place for it. A press only reaches a view inside
/// `NSHostingView` if SwiftUI claims the point first, and once the berth became
/// a `PanelSurface` — added for the Liquid Glass option, and marked as not
/// hit-testable so it could never take a press away from the handle — nothing
/// claimed the empty black between the rings. The panel could be dragged by its
/// rings, which carry a `contentShape` for their tracking areas, and nowhere
/// else. Putting a shape over the handle to claim those points was worse: it
/// swallowed the press rather than passing it down, and then nothing worked at
/// all.
///
/// `sendEvent` sees every event the window server hands this window, before any
/// of SwiftUI's hit testing and before whatever Liquid Glass installs for its
/// own interactivity. Neither can take the drag away from here.
///
/// What is dragged is the **rail**, not the window. The window is far wider than
/// the rail (it carries the space the card unfolds into) and which side of it
/// the rail sits on flips at the middle of the screen; moving the window with
/// the pointer would throw the rail sideways at that moment.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// What can be taken hold of, in the panel's own top-left coordinates:
    /// the rail when it is drawn out, its sliver when it is not. Supplied by
    /// the controller, which is what knows how many providers are switched on.
    var grabArea: (() -> CGRect)?
    /// The rail's own rect, whatever is currently on screen.
    ///
    /// Separate from `grabArea` on purpose: collapsed, what is grabbed is the
    /// sliver, but what is *placed* is still the rail — the stored position is
    /// the rail's, and handing the placement a 20pt sliver where it expects a
    /// 64pt rail would throw the panel across the screen on the first drag.
    var railFrame: (() -> CGRect)?
    /// A short press that ended without moving the panel. The controller maps
    /// it to a provider ring; empty rail space remains drag-only.
    var onClick: ((CGPoint) -> Void)?
    var placement: PanelPlacement?

    /// Where on the rail the pointer took hold, so the panel doesn't jump to
    /// centre itself under the pointer when the drag starts. Nil when no drag
    /// is in progress.
    private var grab: CGSize?
    private var pressedAt: CGPoint?
    private var didDrag = false

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where begin(event): return
        case .leftMouseDragged where carry(): return
        case .leftMouseUp where finish(): return
        default: super.sendEvent(event)
        }
    }

    private func begin(_ event: NSEvent) -> Bool {
        let location = local(event)
        guard
            let area = grabArea?(),
            let rail = railFrame?(),
            area.contains(location)
        else { return false }

        // Measured against the rail even when the sliver is what was grabbed,
        // so the pointer keeps its hold on the rail rather than on whichever
        // stand-in was on screen at the time.
        //
        // Screen coordinates run bottom-up, so the rail's bottom edge is its
        // distance from the window's top subtracted from the window's top.
        let origin = CGPoint(x: frame.minX + rail.minX, y: frame.maxY - rail.maxY)
        let pointer = NSEvent.mouseLocation
        grab = CGSize(width: pointer.x - origin.x, height: pointer.y - origin.y)
        pressedAt = location
        didDrag = false
        return true
    }

    private func carry() -> Bool {
        guard
            let grab,
            let placement,
            let screen = screen ?? NSScreen.main,
            let railFrame = railFrame?()
        else { return false }

        let visible = screen.visibleFrame
        let pointer = NSEvent.mouseLocation
        let rail = railFrame.size

        if !didDrag {
            didDrag = true
            placement.isDragging = true
        }

        // Where the rail would like to be, kept wholly on screen.
        let wanted = CGPoint(
            x: min(max(pointer.x - grab.width, visible.minX), visible.maxX - rail.width),
            y: min(max(pointer.y - grab.height, visible.minY), visible.maxY - rail.height)
        )

        // Docking is decided *during* the drag, not on release: a snap that
        // waited for mouse-up would jump the panel out from under the pointer.
        let dock: PanelDock = if wanted.x - visible.minX <= PanelPlacement.dockDistance {
            .edge(.left)
        } else if visible.maxX - (wanted.x + rail.width) <= PanelPlacement.dockDistance {
            .edge(.right)
        } else {
            .floating
        }

        let ratios = PanelPlacement.ratios(forRailAt: wanted, in: visible, rail: rail)
        placement.record(dock: dock, horizontalRatio: ratios.h, verticalRatio: ratios.v)

        // One source of truth for the geometry: ask the placement where that
        // puts things rather than working it out a second way here.
        let layout = placement.layout(in: visible, panel: frame.size, rail: rail)
        setFrame(layout.frame, display: true)
        placement.setRailTop(layout.railTop)
        return true
    }

    private func finish() -> Bool {
        guard grab != nil else { return false }
        let click = didDrag ? nil : pressedAt
        grab = nil
        pressedAt = nil
        didDrag = false
        placement?.isDragging = false
        if let click { onClick?(click) }
        return true
    }

    /// The event's location in the panel's own coordinates, with the origin at
    /// the top-left corner to match SwiftUI — which is the space the grab area
    /// is given in.
    private func local(_ event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
    }
}
