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
        /// The panel's size for a given dock, which is the only thing about it
        /// that ever changes — and it changes only when the rail is re-docked
        /// onto the other axis, never while a card opens. That distinction is
        /// the whole point: growing the window mid-animation moves the
        /// coordinate space the rail is laid out in, so the rail lurches
        /// sideways and slides back every time a card appears. Re-docking
        /// happens under the pointer, with no card open, and has to resize.
        static func size(for edge: PanelEdge) -> CGSize {
            // Card + its pointer + the gap after it, which is the room the
            // card unfolds into whichever way it unfolds.
            let reach = DetailCardLayout.width
                + DetailCardLayout.pointerWidth
                + DetailCardLayout.horizontalGap

            switch edge.axis {
            case .vertical:
                return CGSize(
                    width: reach + DockLayout.thickness(on: .vertical),
                    // Tall enough for whichever is bigger: the rail with every
                    // provider on, or the tallest card that might be shown
                    // beside it. A card taller than the window gets sliced off
                    // flat against its edge, which reads as a drawing bug
                    // rather than as a card that didn't fit.
                    height: max(DockLayout.maximumLength(on: .vertical), DetailCardLayout.maximumHeight)
                )
            case .horizontal:
                return CGSize(
                    // Wide enough for whichever is wider, for the same reason.
                    width: max(DockLayout.maximumLength(on: .horizontal), DetailCardLayout.width),
                    height: DockLayout.thickness(on: .horizontal)
                        + DetailCardLayout.horizontalGap
                        + DetailCardLayout.pointerWidth
                        + DetailCardLayout.maximumHeight
                )
            }
        }

        /// The vertical dock's size, which is what the previews and anything
        /// written before there was a second axis mean.
        static var width: CGFloat { size(for: .right).width }
        static var height: CGFloat { size(for: .right).height }
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

        let initialSize = Layout.size(for: placement.edge)
        panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialSize.width,
                height: initialSize.height
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
        hostingView.frame = NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height)
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
                railSize: DockLayout.size(for: settings.shownAccounts.count, on: placement.edge.axis, docked: placement.isDocked),
                railTop: placement.railTop,
                railLeading: placement.railLeading
            )
        }
        // The rail's size for a dock it is not on yet, which the drag needs:
        // crossing onto the other axis turns the rail as it goes.
        // Takes the dock it is *landing* on, not the one it is leaving: the
        // rail's ends lose the flare's worth of padding the moment it comes off
        // an edge, and measuring the old state throws the placement off by that
        // much on the frame it changes.
        panel.railSize = { [settings] edge, docked in
            DockLayout.size(for: settings.shownAccounts.count, on: edge.axis, docked: docked)
        }
        panel.grabArea = { [settings, placement] in
            let size = DockLayout.size(for: settings.shownAccounts.count, on: placement.edge.axis, docked: placement.isDocked)
            return placement.isRailExpanded
                ? PanelHitArea.rail(edge: placement.edge, railSize: size, railTop: placement.railTop, railLeading: placement.railLeading)
                : PanelHitArea.strip(edge: placement.edge, railSize: size, railTop: placement.railTop, railLeading: placement.railLeading)
        }
        panel.onClick = { [settings, placement, store] point in
            guard placement.isRailExpanded else { return }
            // The rail draws them in the user's order, so a click has to be
            // matched against that order — `PanelHitArea.provider` maps a
            // position to an index, and the enum's order is not what is on
            // screen once anything has been moved.
            let accounts = settings.shownAccounts
            guard let account = PanelHitArea.account(
                at: point,
                edge: placement.edge,
                accounts: accounts,
                railTop: placement.railTop,
                railLeading: placement.railLeading,
                docked: placement.isDocked
            ) else { return }
            store.refresh(account)
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
        panel.applyLevel(for: placement.dock)
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

        let edge = placement.edge
        let layout = placement.layout(
            in: screen.visibleFrame,
            topEdge: FloatingPanel.topEdge(of: screen),
            panel: Layout.size(for: edge),
            rail: DockLayout.size(for: settings.shownAccounts.count, on: edge.axis, docked: placement.isDocked)
        )

        panel.applyLevel(for: placement.dock)
        panel.setFrame(layout.frame, display: true)
        placement.setRailOffset(top: layout.railTop, leading: layout.railLeading)
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
    /// The rail's size on a given edge, which the drag needs for an edge the
    /// panel has not reached yet.
    var railSize: ((PanelEdge, Bool) -> CGSize)?

    /// Where a top-docked rail's top edge belongs: the display's physical top,
    /// less whatever a notch takes out of it.
    ///
    /// Not `visibleFrame.maxY`, which is under the menu bar — a rail parked a
    /// menu bar's height below the edge of the screen is not against the edge
    /// of the screen, and looks it.
    static func topEdge(of screen: NSScreen) -> CGFloat {
        let notch = screen.safeAreaInsets.top
        guard notch > 0 else { return screen.frame.maxY }

        // With a notch there is a row of screen either side of it, but the
        // rail is wider than either — centred, most of it would be behind the
        // notch, where nothing is drawn at all. So it stops at the notch's own
        // line, which is also where the menu bar ends. Taking the lower of the
        // two rather than trusting them to be equal: the rail must never be
        // asked to draw itself into a row it cannot be seen in, and only one
        // of these two numbers is the notch's.
        return min(screen.frame.maxY - notch, screen.visibleFrame.maxY)
    }

    /// Above the menu bar while docked to the top, and only then.
    ///
    /// `.floating` sits *below* the menu bar's own level, so a panel placed at
    /// the display's edge would simply be drawn over by it. `.statusBar` is
    /// one step above the menu bar and the same level the menu bar's own extras
    /// use — high enough to reach the edge, not so high that it covers system
    /// alerts. Nothing else about the panel changes, and off the top edge it
    /// goes back to floating so it never sits over the menu bar for nothing.
    func applyLevel(for dock: PanelDock) {
        level = dock.edge == .top ? .statusBar : .floating
    }
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
        //
        // The top is tested against the **pointer**, not the rail. A rail
        // standing on its end is most of the screen tall, so its top edge
        // reaches the top of the display almost as soon as it is lifted at all
        // — testing that would flip it on its side the moment it was picked
        // up. Throwing the pointer at the top of the screen is the deliberate
        // gesture, and it is the same one that reaches the menu bar.
        let dock: PanelDock = if visible.maxY - pointer.y <= PanelPlacement.dockDistance {
            .edge(.top)
        } else if wanted.x - visible.minX <= PanelPlacement.dockDistance {
            .edge(.left)
        } else if visible.maxX - (wanted.x + rail.width) <= PanelPlacement.dockDistance {
            .edge(.right)
        } else {
            .floating
        }

        // The rail turns as it crosses onto the other axis, so everything from
        // here is measured in the orientation it is about to be in — not the
        // one it is leaving. Measuring in the old one throws the panel across
        // the screen on the frame the axis changes.
        let landing = dock.edge ?? placement.edge
        let landingRail = railSize?(landing, dock.isDocked) ?? rail
        let landingPanel = FloatingPanelController.Layout.size(for: landing)

        // Under the pointer, in the new orientation. Carrying the old grab
        // offset across a quarter turn would put the rail somewhere the hand
        // holding it never asked for.
        let turned = landingRail != rail
        let origin = turned
            ? CGPoint(x: pointer.x - landingRail.width / 2, y: pointer.y - landingRail.height / 2)
            : wanted

        let ratios = PanelPlacement.ratios(forRailAt: origin, in: visible, rail: landingRail)
        placement.record(dock: dock, horizontalRatio: ratios.h, verticalRatio: ratios.v)

        // One source of truth for the geometry: ask the placement where that
        // puts things rather than working it out a second way here.
        let layout = placement.layout(
            in: visible,
            topEdge: Self.topEdge(of: screen),
            panel: landingPanel,
            rail: landingRail
        )
        applyLevel(for: dock)
        setFrame(layout.frame, display: true)
        placement.setRailOffset(top: layout.railTop, leading: layout.railLeading)
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
