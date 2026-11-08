// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import SwiftUI

/// Which side the rail's back faces — so, which side the details card opens
/// away from.
///
/// Docked, this is the screen edge the rail is fused to. Floating, it is
/// whichever half of the screen the rail is sitting in, so the card always
/// unfolds towards the roomier side rather than off the edge of the display.
///
/// `bottom` is both kinds: a rail fused to the screen's bottom edge — the
/// physical one, level with the Dock, so it can sit in the empty stretch
/// either side of it — and a horizontal rail standing free in the lower half
/// of the screen. Either way its card opens upwards.
enum PanelEdge: String, Sendable {
    case left
    case right
    case top
    case bottom

    /// Which way the rail runs.
    ///
    /// Everything that used to read the edge directly — the stack the rings
    /// sit in, which way the card unfolds, which end the flare fuses into,
    /// which of the two ratios is pinned — actually only cares about this. Two
    /// vertical edges and one horizontal one is a coincidence of what is built
    /// today; the axis is the thing.
    enum Axis: String, Sendable {
        case vertical
        case horizontal
    }

    var axis: Axis {
        switch self {
        case .left, .right: .vertical
        case .top, .bottom: .horizontal
        }
    }
    var isVertical: Bool { axis == .vertical }
    var isLeft: Bool { self == .left }

    /// Where the rail's container is pinned inside the panel. The offset along
    /// the panel is applied separately (`PanelPlacement.railTop` and
    /// `railLeading`), so this pins the container to the corner those offsets
    /// are measured from.
    var railAlignment: Alignment {
        switch self {
        case .left, .top, .bottom: .topLeading
        case .right: .topTrailing
        }
    }

    /// How the rail and its collapsed sliver sit *within* that container,
    /// which is exactly the rail's size — so this centres the sliver along the
    /// rail and holds it against the screen edge across it.
    var stackAlignment: Alignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// Where the card hangs off the rail: away from the rail's back.
    var cardAlignment: Alignment {
        switch self {
        case .left: .topTrailing
        case .right: .topLeading
        case .top: .topLeading
        case .bottom: .bottomLeading
        }
    }

    /// Which way, along the axis the card unfolds across, it moves clear of
    /// the rail. Positive is right for a side dock and down for the top one,
    /// which is SwiftUI's direction in both cases.
    var cardDirection: CGFloat {
        switch self {
        case .left, .top: 1
        case .right, .bottom: -1
        }
    }

    /// The corner of the card the reveal animation grows out of, along the
    /// axis the card unfolds across.
    var cardRevealOrigin: CGFloat {
        switch self {
        case .left, .top: 0
        case .right, .bottom: 1
        }
    }
}

/// Whether the panel is fused to a screen edge or standing free — and,
/// standing free, which way the rail runs: upright like a side dock, or lying
/// across like the top one.
enum PanelDock: Equatable, Hashable, Sendable {
    case edge(PanelEdge)
    case floating(PanelEdge.Axis)

    var edge: PanelEdge? {
        if case .edge(let edge) = self { return edge }
        return nil
    }

    var isDocked: Bool { edge != nil }
}

/// Where the panel is parked, and the memory of it between launches.
///
/// The position is the **rail's**, not the window's. The window is much wider
/// than the rail — it carries the space the card unfolds into — and which side
/// of the window the rail sits on flips as the panel crosses the middle of the
/// screen. Storing the window's position instead would make the rail jump the
/// width of a card at that moment, which is precisely what the user is holding
/// on to while dragging.
///
/// Both coordinates are fractions of the room the rail has to move in rather
/// than absolute points, so the panel lands somewhere sensible when the
/// display, the menu bar or the Dock changes between runs.
@Observable
final class PanelPlacement {
    private(set) var dock: PanelDock
    /// 0 puts the rail against the left of the usable area, 1 against the
    /// right. Only meaningful while floating.
    private(set) var horizontalRatio: Double
    /// 0 puts the rail's top at the top of the usable area, 1 its bottom at
    /// the bottom.
    private(set) var verticalRatio: Double

    /// Where the rail's top edge sits inside the panel, measured downwards
    /// from the panel's own top — SwiftUI's direction.
    ///
    /// Written by whoever last placed the window, because it can only be
    /// worked out from the screen: the window is kept inside the visible area
    /// so the card always has room, and when the rail is parked near the top
    /// or bottom of the screen the window can go no further — so the rail has
    /// to travel *within* the window for that last stretch. Without this the
    /// rail would stop dead a couple of hundred points short of either end of
    /// the screen.
    private(set) var railTop: CGFloat = 0

    /// The same, along the panel's other axis. Only a rail lying across the
    /// top of the screen ever moves in it; down a side the rail is pinned to
    /// one edge of the panel and this stays zero.
    private(set) var railLeading: CGFloat = 0

    /// Present only while attached to a physical notch; never persisted.
    var notch: CGRect?

    /// How far a docked rail is drawn off its edge while it is being pulled
    /// away or drawn on (`DropletTether`); zero at rest. Never persisted.
    var pull: CGFloat = 0
    /// Extra thinning of the neck while a rail is being drawn onto an edge.
    var thinning: CGFloat = 0
    /// How hard the hand is pulling a docked rail off its edge, 0 to 1: the
    /// pointer's pull, not where the rail has been drawn, which trails it.
    var tension: CGFloat = 0
    /// How far a parted neck's two pieces have drawn back, 0 to 1, while the
    /// rail is letting go of an edge (`DropletTether.partingDuration`).
    var parted: CGFloat = 0
    /// How much a rail that has just let go of an edge still has its docked
    /// corners, easing to 0 (`DockBerthShape.fusion`).
    var fusion: CGFloat = 0
    /// How fast the rail is being carried, in points a second, screen
    /// coordinates; zero at rest.
    var motion: CGVector = .zero

    /// `AppSettings.snapsToEdges`, copied here by the panel controller
    /// whenever settings change; never persisted by this class. It decides
    /// what a drag lands on (`dragDock`) and how close to a side a free
    /// upright rail may stand (`sideMargin`).
    var snapsToEdges = true

    /// `AppSettings.liquidDocking`, copied here like `snapsToEdges`: whether a
    /// drag pulls the rail off an edge like a drop and carries it on a
    /// spring (`DropletTether`).
    var liquidDocking = false

    /// How far a free rail is kept from the left and right of the screen.
    ///
    /// An upright rail flush against a side looks docked there without
    /// being docked, so while snapping is on it keeps the docking distance —
    /// it would have docked on the way in anyway. A rail lying across has no
    /// side dock to be mistaken for, and with snapping on it docks to a side
    /// only once the pointer gets there: held back 32pt, it stopped short
    /// while the hand kept moving. With snapping off nothing is held back,
    /// so the rail goes flush into any corner (issue #85).
    func sideMargin(for axis: PanelEdge.Axis) -> CGFloat {
        snapsToEdges && axis == .vertical ? Self.dockDistance : 0
    }

    /// The room the rail is placed in on a screen, which its two ratios are
    /// fractions of.
    ///
    /// The usable area, except for a free rail with snapping off: that one
    /// goes wherever it is put, over the menu bar and beside or over the
    /// Dock as well (issue #85), and is raised above them there
    /// (`isBeyond`). With snapping on the menu bar and the Dock are where
    /// the top and bottom docks are, so a free rail stays clear of them.
    static func room(snaps: Bool, dock: PanelDock, visible: CGRect, screen: CGRect) -> CGRect {
        snaps || dock.isDocked ? visible : screen
    }

    func room(visible: CGRect, screen: CGRect) -> CGRect {
        Self.room(snaps: snapsToEdges, dock: dock, visible: visible, screen: screen)
    }

    /// Whether a rail whose top-left is `railOrigin` reaches past the usable
    /// area — over the menu bar or the Dock — where it has to be drawn above
    /// them or it is hidden under them.
    static func isBeyond(_ visible: CGRect, railOrigin: CGPoint, rail: CGSize) -> Bool {
        let rect = CGRect(x: railOrigin.x, y: railOrigin.y - rail.height, width: rail.width, height: rail.height)
        return !visible.insetBy(dx: -0.5, dy: -0.5).contains(rect)
    }

    /// The card's height limit, including a vertical pointer. Computed for
    /// every edge at placement and while dragging, never persisted.
    var cardRoom: CGFloat?
    /// Granted panel geometry, shared by card placement and pointer hit bands.
    /// These are transient measurements, never persisted or driven by a card.
    private(set) var panelSize: CGSize?
    private(set) var cardPlacementBounds: CGRect?

    /// Converts the owning screen's usable area to the actual panel's flipped
    /// coordinates. Preserve the origin: an oversized window can extend above it.
    static func cardBounds(visible: CGRect, panelFrame: CGRect) -> CGRect {
        let local = CGRect(x: visible.minX - panelFrame.minX,
                           y: panelFrame.maxY - visible.maxY,
                           width: visible.width, height: visible.height)
        let bounds = local.intersection(CGRect(origin: .zero, size: panelFrame.size))
        return bounds.isNull || bounds.isEmpty ? .zero : bounds
    }

    func setPanelFrame(_ frame: CGRect, visible: CGRect) {
        panelSize = frame.size
        cardPlacementBounds = Self.cardBounds(visible: visible, panelFrame: frame)
    }

    /// A horizontal rail opens toward the usable edge; beside a vertical rail
    /// the card can slide along the whole usable height. Both leave breathing
    /// room on the display. Placement reserves the screen budget in the window.
    static func cardRoom(edge: PanelEdge, railOrigin: CGPoint, rail: CGSize, in visible: CGRect) -> CGFloat? {
        let room: CGFloat
        switch edge {
        case .top: room = (railOrigin.y - rail.height) - visible.minY
        case .bottom: room = visible.maxY - railOrigin.y
        case .left, .right: room = visible.height
        }
        return max(min(room - DetailCardLayout.horizontalGap,
                       DetailCardLayout.screenHeightLimit(in: visible)), 0)
    }

    /// Which display the rail was left on, as `PanelScreen` names them.
    ///
    /// The two ratios are fractions of one screen's usable area, so they say
    /// *where* on a display the rail sits and nothing about *which*. Without
    /// this the panel came home to whichever screen was main at every launch,
    /// every settings change and every re-place — so it could be dragged onto
    /// a second monitor and would not stay there.
    ///
    /// Nil means "wherever is main", which is what a first run wants and what
    /// a stored display that is no longer attached falls back to.
    private(set) var display: String?

    /// True while the panel is being carried across the screen.
    ///
    /// The drag belongs to the window now, not to a view inside it, so this is
    /// how the content hears about it: cards are kept shut while the pointer
    /// sweeps across the rings, and the rail is not allowed to hide itself out
    /// from under the hand holding it.
    var isDragging = false
    /// The panel is under a held mouse button, whether or not it has moved yet.
    ///
    /// `isDragging` is set on the first *movement*, so it leaves a window
    /// between mouse-down and that first frame. Moving the panel in that
    /// window is worse than moving it during a drag: the grab offset was
    /// measured at mouse-down, so the panel jumps by however far it was moved
    /// the instant the pointer travels.
    var isPressed = false

    /// The panel's own context menu is open.
    ///
    /// The pointer is over the menu while it is up, which is off the panel by
    /// every test the watcher makes — so without this the rail winds down to
    /// its sliver the moment the menu appears next to it, and the menu is left
    /// pointing at nothing.
    var isMenuOpen = false

    /// Whether the rail is drawn out in full or wound down to its sliver.
    ///
    /// Decided by the content — it depends on where the pointer is — and
    /// mirrored here because the window has to know how much of itself can be
    /// taken hold of, and cannot see that state from the outside.
    var isRailExpanded = true

    /// When the rail last came out, for `PanelIntent.ringClickGuard`. Nil
    /// while it is wound down. Set by the content alongside `isRailExpanded`;
    /// nothing draws from it, so it is not observed.
    @ObservationIgnored var railOpenedAt: Date?

    init(
        dock: PanelDock = .edge(.right),
        horizontalRatio: Double = 1,
        verticalRatio: Double = 0.5,
        display: String? = nil
    ) {
        self.dock = dock
        self.horizontalRatio = horizontalRatio.clampedToUnitRange
        self.verticalRatio = verticalRatio.clampedToUnitRange
        self.display = display
    }

    /// Which way the card opens. Docked, the edge it is fused to; floating,
    /// the half of the screen it is standing in — left or right for an
    /// upright rail, top or bottom for one lying across.
    var edge: PanelEdge {
        switch dock {
        case .edge(let edge): edge
        case .floating(.vertical): horizontalRatio < 0.5 ? .left : .right
        case .floating(.horizontal): verticalRatio < 0.5 ? .top : .bottom
        }
    }

    var isDocked: Bool { dock.isDocked }

    /// `defaults` is only ever not `.standard` in a test.
    static func restored(from defaults: UserDefaults = .standard) -> PanelPlacement {

        let dock: PanelDock = if defaults.object(forKey: Key.floating) as? Bool == true {
            // Absent for anyone who floated the panel before there was a
            // second axis, which was always upright.
            .floating(defaults.string(forKey: Key.floatingAxis).flatMap(PanelEdge.Axis.init(rawValue:)) ?? .vertical)
        } else {
            .edge(defaults.string(forKey: Key.edge).flatMap(PanelEdge.init(rawValue:)) ?? .right)
        }

        return PanelPlacement(
            dock: dock,
            horizontalRatio: defaults.object(forKey: Key.horizontalRatio) as? Double ?? 1,
            verticalRatio: defaults.object(forKey: Key.verticalRatio) as? Double ?? 0.5,
            display: defaults.string(forKey: Key.display)
        )
    }

    /// Called when the placement changes by a route that hasn't already moved
    /// the window — picking a position in settings, say. `FloatingPanelController`
    /// uses it to reposition the panel.
    var onChange: (() -> Void)?

    /// The rail got longer or shorter without any setting changing.
    ///
    /// It can now: a split provider draws a ring per model group, so the first
    /// reading after launch turns one ring into two. Where the rail sits inside
    /// the panel is worked out from its length, and that sum was last done when
    /// the rail was a ring shorter — leaving the last ring hanging below the
    /// window's edge, drawn where no click can reach it.
    ///
    /// **Not while the panel is held**, which is moving the window itself and
    /// would be fought over the same frame — and not merely "not while
    /// dragging": between mouse-down and the first movement the grab offset is
    /// already measured, so a re-place there makes the panel jump the moment
    /// the pointer travels.
    func railLengthChanged() {
        guard !isDragging, !isPressed else { return }
        onChange?()
    }

    /// Carries the panel onto another display, keeping where on a display it
    /// sits.
    ///
    /// The two ratios are fractions of one screen's usable area, so they need
    /// no adjusting: the rail lands in the same place on the new display as it
    /// held on the old one, whatever the two displays' sizes. Only the name of
    /// the display changes.
    ///
    /// Stored like any other move, so switching "follow the active display"
    /// back off leaves the panel on the display it was last carried to rather
    /// than throwing it back across the desk.
    ///
    /// **Not while the panel is held.** The same rule as `railLengthChanged`,
    /// for the same reason: between mouse-down and the first movement the grab
    /// offset is already measured, and moving the panel there makes it jump
    /// the moment the pointer travels.
    func move(toDisplay identifier: String) -> Bool {
        guard !isDragging, !isPressed else { return false }
        guard display != identifier else { return true }

        record(
            dock: dock,
            horizontalRatio: horizontalRatio,
            verticalRatio: verticalRatio,
            display: identifier
        )
        onChange?()
        return true
    }

    /// Changes where the panel should sit, and asks for it to be moved there.
    func update(dock: PanelDock, horizontalRatio: Double? = nil, verticalRatio: Double? = nil) {
        record(
            dock: dock,
            horizontalRatio: horizontalRatio ?? self.horizontalRatio,
            verticalRatio: verticalRatio ?? self.verticalRatio,
            display: display
        )
        onChange?()
    }

    /// Stores a placement the panel is already at.
    ///
    /// Used by the drag handle, which moves the window itself as the pointer
    /// goes: asking for it to be moved again would fight the drag over the
    /// same frame.
    /// `persist: false` keeps it in memory only: the liquid follow records a
    /// place on every display frame and writes it once, when it stops.
    func record(dock: PanelDock, horizontalRatio: Double, verticalRatio: Double, display: String?, persist: Bool = true) {
        self.dock = dock
        self.horizontalRatio = horizontalRatio.clampedToUnitRange
        self.verticalRatio = verticalRatio.clampedToUnitRange
        self.display = display
        guard persist else { return }

        let defaults = UserDefaults.standard
        defaults.set(!dock.isDocked, forKey: Key.floating)
        switch dock {
        case .edge(let edge): defaults.set(edge.rawValue, forKey: Key.edge)
        case .floating(let axis): defaults.set(axis.rawValue, forKey: Key.floatingAxis)
        }
        defaults.set(self.horizontalRatio, forKey: Key.horizontalRatio)
        defaults.set(self.verticalRatio, forKey: Key.verticalRatio)
        defaults.set(display, forKey: Key.display)
    }

    func setRailOffset(top: CGFloat, leading: CGFloat) {
        if abs(railTop - top) > 0.5 { railTop = top }
        if abs(railLeading - leading) > 0.5 { railLeading = leading }
    }

    // MARK: - Geometry

    /// Everything the AppKit side needs to put the window somewhere: the
    /// window's frame, and where the rail sits inside it.
    ///
    /// The two are worked out together because they trade off against each
    /// other. The rail's place on screen is what the user chose; the window is
    /// then centred on it and pushed back inside the visible area if that put
    /// it half off the screen, and whatever that push cost is handed back as
    /// the rail's offset inside the window so the rail itself doesn't move.
    /// Where the panel goes, and where the rail goes — the second **in screen
    /// coordinates**, deliberately.
    ///
    /// It used to carry the rail's offsets inside the panel instead, which was
    /// a trap: `frame` is a *request*. The panel is as tall as a rail with
    /// every account switched on — 1133pt — which is taller than the usable
    /// area of a laptop display, and AppKit's `constrainFrameRect` pulls such
    /// a window down so its top stays under the menu bar. Offsets measured
    /// from the panel's own edges are then relative to a position the window
    /// never had; everything else measures against the real one, and the drag
    /// round-tripped the difference through `ratios(forRailAt:)`. 72pt, on the
    /// first frame the pointer moved.
    ///
    /// A screen position cannot be wrong that way. Ask `offsets(forRailTopLeft:
    /// in:rail:)` for the offsets, **after** setting the frame and with the
    /// frame the window actually got.
    struct Layout {
        let frame: CGRect
        /// The rail's top-left corner in screen coordinates.
        let railOrigin: CGPoint
    }

    /// Where the rail sits inside a panel that has **this** frame.
    ///
    /// Both offsets are clamped so the rail cannot be asked to sit outside the
    /// window it is drawn in, however far the frame ended up from the one that
    /// was asked for.
    static func offsets(
        forRailTopLeft origin: CGPoint,
        in frame: CGRect,
        rail: CGSize
    ) -> (top: CGFloat, leading: CGFloat) {
        (
            top: min(max(frame.maxY - origin.y, 0), max(frame.height - rail.height, 0)),
            leading: min(max(origin.x - frame.minX, 0), max(frame.width - rail.width, 0))
        )
    }

    /// `topEdge` is where a top-docked rail's own top edge belongs, which is
    /// **not** the top of `visible`: the panel is drawn above the menu bar, so
    /// it goes to the display's physical edge. On a Mac with a notch that is
    /// as far as the notch allows and no further. When `notch` is available,
    /// the surface starts at the physical top and the rings sit below it.
    /// - Parameter bottomEdge: the screen's own bottom, below the Dock — where
    ///   a bottom-docked rail stands. `visible` stops above the Dock across
    ///   the whole width, though the Dock fills only the middle of it.
    func layout(in visible: CGRect, topEdge: CGFloat, bottomEdge: CGFloat? = nil, panel: CGSize, rail: CGSize) -> Layout {
        // Along the top the free coordinate is the horizontal one, and the
        // panel hangs *down* from the rail instead of being centred on it,
        // because that is the only direction the card can unfold into.
        if case .edge(.top) = dock {
            let railX = min(
                max(notch.map { $0.midX - rail.width / 2 }
                    ?? (visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0)), visible.minX),
                max(visible.maxX - rail.width, visible.minX)
            )
            let railTopY = notch?.minY ?? topEdge

            let windowX = min(
                max(railX + rail.width / 2 - panel.width / 2, visible.minX),
                max(visible.maxX - panel.width, visible.minX)
            )
            let windowY = max((notch?.maxY ?? railTopY) - panel.height, visible.minY)

            return Layout(
                frame: CGRect(x: windowX, y: windowY, width: panel.width, height: panel.height),
                railOrigin: CGPoint(x: railX, y: railTopY)
            )
        }

        // Along the bottom the rail stands on the screen's own edge, beside
        // the Dock rather than above it, and the window stands up from it:
        // the card can only unfold upwards.
        if case .edge(.bottom) = dock {
            let floor = bottomEdge ?? visible.minY
            let railX = min(
                max(visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0), visible.minX),
                max(visible.maxX - rail.width, visible.minX)
            )
            let windowX = min(
                max(railX + rail.width / 2 - panel.width / 2, visible.minX),
                max(visible.maxX - panel.width, visible.minX)
            )
            return Layout(
                frame: CGRect(x: windowX, y: floor, width: panel.width, height: panel.height),
                railOrigin: CGPoint(x: railX, y: floor + rail.height)
            )
        }

        if case .floating(.horizontal) = dock {
            return layoutLyingFree(in: visible, panel: panel, rail: rail)
        }

        let railX: CGFloat = switch dock {
        case .edge(.left): visible.minX
        case .edge(.right): visible.maxX - rail.width
        // Handled above; never reached.
        case .edge(.top), .edge(.bottom), .floating(.horizontal): visible.minX
        case .floating(.vertical):
            // Floating means *not touching* while snapping is on. Without
            // this, switching to free placement while the stored position is
            // still the docked one leaves the rail flush against the side of
            // the screen wearing the silhouette of something that isn't.
            min(
                max(
                    visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0),
                    visible.minX + sideMargin(for: .vertical)
                ),
                max(
                    visible.maxX - rail.width - sideMargin(for: .vertical),
                    visible.minX + sideMargin(for: .vertical)
                )
            )
        }

        // Screen coordinates run bottom-up, so ratio 0 — the rail at the top —
        // is the *highest* y.
        let railY = visible.minY
            + CGFloat(1 - verticalRatio) * max(visible.height - rail.height, 0)

        let windowX = edge.isLeft ? railX : railX + rail.width - panel.width
        let windowY = min(
            max(railY + rail.height / 2 - panel.height / 2, visible.minY),
            max(visible.maxY - panel.height, visible.minY)
        )

        return Layout(
            frame: CGRect(x: windowX, y: windowY, width: panel.width, height: panel.height),
            // The rail's *top*, which is its bottom-left origin plus its run.
            railOrigin: CGPoint(x: railX, y: railY + rail.height)
        )
    }

    /// A rail lying across the screen and standing free: the top dock's
    /// shape, placed by both ratios the way the upright floating rail is.
    ///
    /// Not kept clear of the sides: see `sideMargin`. The window hangs *down* from the rail in the top half of
    /// the screen and stands *up* from it in the bottom half (`edge`), so the
    /// card always has the roomier half to open into — hanging down
    /// everywhere would slice it off against the Dock the moment the rail was
    /// parked low.
    private func layoutLyingFree(in visible: CGRect, panel: CGSize, rail: CGSize) -> Layout {
        let margin = sideMargin(for: .horizontal)
        let railX = min(
            max(
                visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0),
                visible.minX + margin
            ),
            max(visible.maxX - rail.width - margin, visible.minX + margin)
        )
        // Screen coordinates run bottom-up: this is the rail's bottom edge.
        let railY = visible.minY
            + CGFloat(1 - verticalRatio) * max(visible.height - rail.height, 0)

        let windowX = min(
            max(railX + rail.width / 2 - panel.width / 2, visible.minX),
            max(visible.maxX - panel.width, visible.minX)
        )
        let wantedY = edge == .bottom ? railY : railY + rail.height - panel.height
        let windowY = min(
            max(wantedY, visible.minY),
            max(visible.maxY - panel.height, visible.minY)
        )

        return Layout(
            frame: CGRect(x: windowX, y: windowY, width: panel.width, height: panel.height),
            railOrigin: CGPoint(x: railX, y: railY + rail.height)
        )
    }

    /// The two ratios that would put the rail at a given spot on screen.
    static func ratios(forRailAt origin: CGPoint, in visible: CGRect, rail: CGSize) -> (h: Double, v: Double) {
        let across = max(visible.width - rail.width, 0)
        let down = max(visible.height - rail.height, 0)
        return (
            across > 0 ? Double((origin.x - visible.minX) / across) : 0.5,
            down > 0 ? 1 - Double((origin.y - visible.minY) / down) : 0.5
        )
    }

    /// How far a rail whose bottom-left corner is at `railOrigin` stands off
    /// `edge`, where the docked rail would be flush: positive into the
    /// screen. What a pull is measured by, and where a rail being drawn on
    /// starts from.
    static func distance(
        from edge: PanelEdge,
        railOrigin origin: CGPoint,
        rail: CGSize,
        screen: CGRect,
        visible: CGRect,
        topEdge: CGFloat,
        notch: CGRect?
    ) -> CGFloat {
        switch edge {
        case .top: (notch?.minY ?? topEdge) - (origin.y + rail.height)
        case .bottom: origin.y - screen.minY
        case .left: origin.x - visible.minX
        case .right: visible.maxX - (origin.x + rail.width)
        }
    }

    /// How close the rail has to get to a side of the screen before it fuses
    /// to it. Generous enough to be easy to hit on purpose, tight enough that
    /// parking the panel *near* an edge on purpose still works.
    static let dockDistance: CGFloat = 32

    /// Where a rail being carried lands on this frame of the drag.
    ///
    /// Docking is decided *during* the drag, not on release: a snap that
    /// waited for mouse-up would jump the panel out from under the pointer.
    ///
    /// The top is tested against the **pointer**, not the rail. A rail
    /// standing on its end is most of the screen tall, so its top edge
    /// reaches the top of the display almost as soon as it is lifted at all
    /// — testing that would flip it on its side the moment it was picked
    /// up. Throwing the pointer at the top of the screen is the deliberate
    /// gesture, and it is the same one that reaches the menu bar.
    ///
    /// **The sides are the same for a rail lying across** (issue #85). It is
    /// most of the screen wide, so its end reached a side long before the
    /// pointer was anywhere near the bottom, and a rail carried into a
    /// bottom corner stood up against the side instead of staying across.
    /// An upright rail is as narrow as the hand holding it, so for it the
    /// rail's own edge is the gesture and stays the test.
    ///
    /// Off every edge the rail stands free **the way it already runs**:
    /// lifted off the top it stays lying across, lifted off a side it stays
    /// upright. Turning it on the way out would undo the free placement
    /// somebody chose in settings the first time they moved the panel.
    ///
    /// The bottom is the top's mirror: the pointer thrown at the screen's
    /// **own** bottom — level with the Dock, beside it — docks the rail
    /// there. Just above the Dock, short of that, it lies across and
    /// stands free with its card opening up; with the Dock hidden the two
    /// lines meet and docking wins.
    ///
    /// **Staying docked there is the rail's, not the pointer's.** A ring is
    /// held 32pt or more above the screen's bottom — more with figures — so
    /// the pointer rule would lift a bottom rail off on the first sideways
    /// frame. The top has the menu bar's height in hand for the same slack;
    /// the bottom has nothing, so a docked rail stays while its own bottom
    /// is within reach of the edge.
    ///
    /// With `snaps` off (Settings → *Snap to screen edges*, `snapsToEdges`)
    /// none of that applies: the rail stands free and keeps running the way it did when
    /// it was picked up, wherever it is carried.
    static func dragDock(
        pointer: CGPoint,
        rail: CGRect,
        screen: CGRect,
        visible: CGRect,
        current: PanelDock,
        axis: PanelEdge.Axis,
        snaps: Bool
    ) -> PanelDock {
        guard snaps else { return .floating(axis) }

        let staysOnBottom = current == .edge(.bottom)
            && rail.minY - screen.minY <= dockDistance
        let (left, right) = axis == .horizontal
            ? (pointer.x, pointer.x)
            : (rail.minX, rail.maxX)

        return if visible.maxY - pointer.y <= dockDistance {
            .edge(.top)
        } else if staysOnBottom || pointer.y - screen.minY <= dockDistance {
            .edge(.bottom)
        } else if pointer.y - visible.minY <= dockDistance {
            .floating(.horizontal)
        } else if left - visible.minX <= dockDistance {
            .edge(.left)
        } else if visible.maxX - right <= dockDistance {
            .edge(.right)
        } else {
            .floating(axis)
        }
    }

    private enum Key {
        static let edge = "panel.edge"
        static let floating = "panel.floating"
        static let floatingAxis = "panel.floatingAxis"
        static let horizontalRatio = "panel.horizontalRatio"
        static let verticalRatio = "panel.verticalRatio"
        static let display = "panel.display"
    }
}

private extension Double {
    var clampedToUnitRange: Double { min(max(self, 0), 1) }
}
