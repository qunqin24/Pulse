import Foundation
import SwiftUI

/// Which side the rail's back faces — so, which side the details card opens
/// away from.
///
/// Docked, this is the screen edge the rail is fused to. Floating, it is
/// whichever half of the screen the rail is sitting in, so the card always
/// unfolds towards the roomier side rather than off the edge of the display.
enum PanelEdge: String, Sendable {
    case left
    case right
    case top

    /// Which way the rail runs.
    ///
    /// Everything that used to read the edge directly — the stack the rings
    /// sit in, which way the card unfolds, which end the flare fuses into,
    /// which of the two ratios is pinned — actually only cares about this. Two
    /// vertical edges and one horizontal one is a coincidence of what is built
    /// today; the axis is the thing.
    enum Axis: Sendable {
        case vertical
        case horizontal
    }

    var axis: Axis { self == .top ? .horizontal : .vertical }
    var isVertical: Bool { axis == .vertical }
    var isLeft: Bool { self == .left }

    /// Where the rail's container is pinned inside the panel. The offset along
    /// the panel is applied separately (`PanelPlacement.railTop` and
    /// `railLeading`), so this pins the container to the corner those offsets
    /// are measured from.
    var railAlignment: Alignment {
        switch self {
        case .left, .top: .topLeading
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
        }
    }

    /// Where the card hangs off the rail: away from the rail's back.
    var cardAlignment: Alignment {
        switch self {
        case .left: .topTrailing
        case .right: .topLeading
        case .top: .topLeading
        }
    }

    /// Which way, along the axis the card unfolds across, it moves clear of
    /// the rail. Positive is right for a side dock and down for the top one,
    /// which is SwiftUI's direction in both cases.
    var cardDirection: CGFloat {
        switch self {
        case .left, .top: 1
        case .right: -1
        }
    }

    /// The corner of the card the reveal animation grows out of, along the
    /// axis the card unfolds across.
    var cardRevealOrigin: CGFloat {
        switch self {
        case .left, .top: 0
        case .right: 1
        }
    }
}

/// Whether the panel is fused to a screen edge or standing free.
enum PanelDock: Equatable, Hashable, Sendable {
    case edge(PanelEdge)
    case floating

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

    /// True while the panel is being carried across the screen.
    ///
    /// The drag belongs to the window now, not to a view inside it, so this is
    /// how the content hears about it: cards are kept shut while the pointer
    /// sweeps across the rings, and the rail is not allowed to hide itself out
    /// from under the hand holding it.
    var isDragging = false

    /// Whether the rail is drawn out in full or wound down to its sliver.
    ///
    /// Decided by the content — it depends on where the pointer is — and
    /// mirrored here because the window has to know how much of itself can be
    /// taken hold of, and cannot see that state from the outside.
    var isRailExpanded = true

    init(
        dock: PanelDock = .edge(.right),
        horizontalRatio: Double = 1,
        verticalRatio: Double = 0.5
    ) {
        self.dock = dock
        self.horizontalRatio = horizontalRatio.clampedToUnitRange
        self.verticalRatio = verticalRatio.clampedToUnitRange
    }

    /// Which way the card opens. Docked, the edge it is fused to; floating,
    /// the half of the screen it is standing in.
    var edge: PanelEdge {
        dock.edge ?? (horizontalRatio < 0.5 ? .left : .right)
    }

    var isDocked: Bool { dock.isDocked }

    static func restored() -> PanelPlacement {
        let defaults = UserDefaults.standard

        let dock: PanelDock = if defaults.object(forKey: Key.floating) as? Bool == true {
            .floating
        } else {
            .edge(defaults.string(forKey: Key.edge).flatMap(PanelEdge.init(rawValue:)) ?? .right)
        }

        return PanelPlacement(
            dock: dock,
            horizontalRatio: defaults.object(forKey: Key.horizontalRatio) as? Double ?? 1,
            verticalRatio: defaults.object(forKey: Key.verticalRatio) as? Double ?? 0.5
        )
    }

    /// Called when the placement changes by a route that hasn't already moved
    /// the window — picking a position in settings, say. `FloatingPanelController`
    /// uses it to reposition the panel.
    var onChange: (() -> Void)?

    /// Changes where the panel should sit, and asks for it to be moved there.
    func update(dock: PanelDock, horizontalRatio: Double? = nil, verticalRatio: Double? = nil) {
        record(
            dock: dock,
            horizontalRatio: horizontalRatio ?? self.horizontalRatio,
            verticalRatio: verticalRatio ?? self.verticalRatio
        )
        onChange?()
    }

    /// Stores a placement the panel is already at.
    ///
    /// Used by the drag handle, which moves the window itself as the pointer
    /// goes: asking for it to be moved again would fight the drag over the
    /// same frame.
    func record(dock: PanelDock, horizontalRatio: Double, verticalRatio: Double) {
        self.dock = dock
        self.horizontalRatio = horizontalRatio.clampedToUnitRange
        self.verticalRatio = verticalRatio.clampedToUnitRange

        let defaults = UserDefaults.standard
        defaults.set(!dock.isDocked, forKey: Key.floating)
        if let edge = dock.edge { defaults.set(edge.rawValue, forKey: Key.edge) }
        defaults.set(self.horizontalRatio, forKey: Key.horizontalRatio)
        defaults.set(self.verticalRatio, forKey: Key.verticalRatio)
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
    struct Layout {
        let frame: CGRect
        /// Where the rail's top edge sits inside the panel, measured down from
        /// the panel's own top.
        let railTop: CGFloat
        /// The same along the other axis, for a rail lying across the top.
        /// Zero for a rail down a side, which is pinned to one of them.
        let railLeading: CGFloat
    }

    /// `topEdge` is where a top-docked rail's own top edge belongs, which is
    /// **not** the top of `visible`: the panel is drawn above the menu bar, so
    /// it goes to the display's physical edge. On a Mac with a notch that is
    /// as far as the notch allows and no further — nothing can be drawn under
    /// it — which lands back on the menu bar's own line.
    func layout(in visible: CGRect, topEdge: CGFloat, panel: CGSize, rail: CGSize) -> Layout {
        // Along the top the free coordinate is the horizontal one, and the
        // panel hangs *down* from the rail instead of being centred on it,
        // because that is the only direction the card can unfold into.
        if case .edge(.top) = dock {
            let railX = min(
                max(visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0), visible.minX),
                max(visible.maxX - rail.width, visible.minX)
            )
            let railTopY = topEdge

            let windowX = min(
                max(railX + rail.width / 2 - panel.width / 2, visible.minX),
                max(visible.maxX - panel.width, visible.minX)
            )
            let windowY = max(railTopY - panel.height, visible.minY)

            return Layout(
                frame: CGRect(x: windowX, y: windowY, width: panel.width, height: panel.height),
                railTop: min(max(windowY + panel.height - railTopY, 0), max(panel.height - rail.height, 0)),
                railLeading: min(max(railX - windowX, 0), max(panel.width - rail.width, 0))
            )
        }

        let railX: CGFloat = switch dock {
        case .edge(.left): visible.minX
        case .edge(.right): visible.maxX - rail.width
        case .edge(.top): visible.minX  // handled above; never reached
        case .floating:
            // Floating means *not touching*. Without this, switching to free
            // placement while the stored position is still the docked one
            // leaves the rail flush against the side of the screen wearing the
            // silhouette of something that isn't.
            min(
                max(
                    visible.minX + CGFloat(horizontalRatio) * max(visible.width - rail.width, 0),
                    visible.minX + Self.dockDistance
                ),
                max(visible.maxX - rail.width - Self.dockDistance, visible.minX + Self.dockDistance)
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
            railTop: min(max(windowY + panel.height - railY - rail.height, 0), max(panel.height - rail.height, 0)),
            railLeading: 0
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

    /// How close the rail has to get to a side of the screen before it fuses
    /// to it. Generous enough to be easy to hit on purpose, tight enough that
    /// parking the panel *near* an edge on purpose still works.
    static let dockDistance: CGFloat = 32

    private enum Key {
        static let edge = "panel.edge"
        static let floating = "panel.floating"
        static let horizontalRatio = "panel.horizontalRatio"
        static let verticalRatio = "panel.verticalRatio"
    }
}

private extension Double {
    var clampedToUnitRange: Double { min(max(self, 0), 1) }
}
