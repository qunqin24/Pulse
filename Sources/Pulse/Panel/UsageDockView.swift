// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Layout constants for the collapsed dock rail. Shared with
/// `FloatingPanelController.Layout` (which derives its panel sizes from
/// these plus `DetailCardLayout`) so the AppKit panel frame and the SwiftUI
/// content never drift apart.
enum DockLayout {
    /// Rail width. Flush against the screen's right edge.
    static var width: CGFloat { 64 * PanelMetrics.scale }
    /// Measured from the panel's top edge, NOT from the rail body's flat top
    /// — the concave flare occupies the first `flareHeight` of it. So the
    /// breathing room actually visible above the first ring is
    /// `verticalPadding - flareHeight`. It can never drop below `flareHeight`,
    /// which would clip the ring against the flare; both styles below clear
    /// it by 22pt.
    ///
    /// Softened ends carry a **written** 46pt, tuned against the flatter
    /// 24 × 38 flare beside them. Round ends **derive** it, so the first ring
    /// keeps its place in the end it is centred in: its centre `endRingOffset`
    /// further in than the centre of the end's circle, which is itself
    /// `flareHeight + cornerRadius` in. 54pt at standard size — the rail is
    /// 16pt longer that way, which is why this setting goes through
    /// `onLayoutChange?()` like the other rail metrics.
    static var verticalPadding: CGFloat {
        guard PanelMetrics.usesRoundEnds else { return 46 * PanelMetrics.scale }
        return flareHeight + cornerRadius - ringDiameter / 2 + endRingOffset
    }

    /// Room added at each end of the rail beyond what would sit the first
    /// ring exactly on the centre of the rounded end: 20pt of black over that
    /// ring instead of the 12pt beside it, at standard size.
    ///
    /// Zero is the concentric position, and it was built first. Set beside
    /// the design this rail follows, it read cramped — a ring with no more
    /// black over it than beside it looks pushed up against the end. Nothing,
    /// 8 and 12 were drawn side by side and 8 was picked. The bottom end gets
    /// the same, which is room under the last label.
    ///
    /// Zero with softened ends, whose 46pt padding was written rather than
    /// derived: there is no end circle for a ring to be concentric with.
    static var endRingOffset: CGFloat {
        PanelMetrics.usesRoundEnds ? 8 * PanelMetrics.scale : 0
    }
    static var horizontalPadding: CGFloat { 10 * PanelMetrics.scale }

    static var ringDiameter: CGFloat { 36 * PanelMetrics.scale }
    static var ringLineWidth: CGFloat { 4 * PanelMetrics.scale }
    /// Gap between a ring and the percent label beneath it.
    ///
    /// Further with the time-until-reset arc on: it is drawn 5pt outside the
    /// ring's edge (`UsageRingView.clockGap` + its stroke), and a figure at
    /// the usual 6pt sat on it — under the ring, beside it, across or down a
    /// side (issue #73). The extra keeps the same clear gap from the arc as
    /// from a ring without one.
    static var ringToTextSpacing: CGFloat { 6 * PanelMetrics.scale + clockReach }

    /// How much further the time-until-reset arc stands out than the ring it
    /// circles: 5pt at standard size while it is on, nothing while it is off.
    /// Measured from `UsageRingView.clockDiameter` and the clock's stroke.
    static var clockReach: CGFloat { PanelMetrics.showsWindowClock ? 5 * PanelMetrics.scale : 0 }
    static var percentFontSize: CGFloat { 13 * PanelMetrics.scale }
    /// Rendered line height of the percent label, and its width at "100%".
    ///
    /// The panel's AppKit frame is worked out from these before SwiftUI lays
    /// anything out, so they are budgets rather than measurements — and a
    /// budget that is **short** is not an approximation, it is a squeeze. The
    /// height was 15 and the line renders at 15.6–16.0 per unit of scale, so
    /// every item overflowed its own frame by a fraction; centred, that put
    /// ring *i* half an item's worth of error from where the hit testing
    /// looked for it, reaching 6pt down a full rail.
    ///
    /// Measured with the real font — `.system(size:weight:.medium,
    /// design:.rounded)`, `.monospacedDigit()` — at all three sizes, and
    /// rounded **up**: 15.6/16.0/15.6 for the height, 36.9/37.0/37.8 for the
    /// width. Anything drawn on the panel that needs a budget gets it this
    /// way, never by eye.
    static var percentTextHeight: CGFloat { 16 * PanelMetrics.scale }
    static var percentTextWidth: CGFloat { 38 * PanelMetrics.scale }
    /// Gap between the ring+label items, along the rail.
    ///
    /// The only measurement `RailSpacing` touches: the rings keep their size
    /// and the rail grows or shrinks around them, which is a different wish
    /// from wanting the whole panel bigger.
    static var itemSpacing: CGFloat { 30 * PanelMetrics.scale * PanelMetrics.spacing }

    /// The second ring's own geometry, all of it measured off the first so
    /// the two cannot drift apart.
    ///
    /// **Everything inside the ring has to move for this**, which is why it is
    /// here and not a constant in the view. At standard scale the band between
    /// the icon's disc and the ring's inner edge is six points wide, and the
    /// activity mark already rides the middle of it — the one place a second
    /// arc wants. So when this is on the mark moves inward and the disc gives
    /// up two points; the ring itself, the rail's width and the ring centres
    /// are all unchanged, so nothing outside this circle notices.
    static var secondRingDiameter: CGFloat { 26 * PanelMetrics.scale }
    static var secondRingLineWidth: CGFloat { 2.5 * PanelMetrics.scale }

    /// Reach of the two convex corners on the rail's inner side.
    ///
    /// **Round ends** (`AppSettings.usesRoundEnds`): half the rail, so each
    /// end is a full half-circle. Not a taste for round things. A ring is
    /// centred across the rail, so an end this round shares its centre line
    /// with the ring nearest it and follows that ring round — 12pt of black
    /// down both sides of it at standard size, a little more over it
    /// (`endRingOffset`) — instead of squaring off above it. The rail, its
    /// rings and the card's corners then read as one family of curves.
    /// Circular for the reason the floating capsule is: at this radius the
    /// corner meets the flare with no straight edge between them, and there
    /// is nothing for a superellipse to ease into.
    ///
    /// **Softened ends** (the default): 26pt, drawn as a fourth-order
    /// superellipse rather than a circular arc — see
    /// `DockBerthShape.appendCorner`. A superellipse eases into the edge
    /// beside it, so it reads tighter than its radius: about a 14pt circular
    /// corner, squarer than the 20pt ring it wraps. That is the look Pulse
    /// shipped with, and it is kept because it is the one people know.
    ///
    /// Either way, constrained by `cornerRadius + flareWidth <= width`, since
    /// the corner and the flare share the rail's top and bottom edges. Both
    /// styles land on exactly `width`.
    static var cornerRadius: CGFloat {
        PanelMetrics.usesRoundEnds ? width / 2 : 26 * PanelMetrics.scale
    }
    /// How far the concave flare rises above the rail body's flat top edge
    /// (and drops below its bottom edge) on its way to the screen edge.
    ///
    /// With round ends this is the end's own circle turned inside out: as
    /// tall as it is wide, and as wide as the half of the rail the corner
    /// leaves. The two meet on the rail's centre line with one tangent, so
    /// the end is a single S-curve into the screen edge rather than a corner
    /// followed by a shoulder. Softened ends keep the written 24, a flatter
    /// curve than the corner beside it.
    static var flareHeight: CGFloat {
        PanelMetrics.usesRoundEnds ? cornerRadius : 24 * PanelMetrics.scale
    }
    /// How far in from the screen edge the flare starts sweeping.
    ///
    /// With round ends, the whole of the rail the corner does not take, so
    /// `cornerRadius + flareWidth` is exactly `width` and the body's flat top
    /// edge has no length at all. A top rail carrying labels is thicker than
    /// `width`; there the difference is a short flat run between the corner
    /// and the flare. Softened ends keep the written 38, which also sums to
    /// `width` against their 26pt corner.
    static var flareWidth: CGFloat {
        PanelMetrics.usesRoundEnds ? width - cornerRadius : 38 * PanelMetrics.scale
    }

    /// Height of one ring + its percent label.
    static var itemHeight: CGFloat { ringDiameter + ringToTextSpacing + percentTextHeight }

    /// Whether the label is drawn above its ring rather than below it.
    static var labelLeads: Bool { PanelMetrics.labelAboveRing }

    /// How far into its item a ring starts, which is nothing at all unless the
    /// label is above it — then the ring is pushed down past the whole label
    /// block. **Everything that locates a ring has to add this**, the drawing
    /// and the hit testing alike, or a click lands on the number instead of on
    /// the ring it appears to be aimed at.
    static func ringOffsetInItem(on axis: PanelEdge.Axis) -> CGFloat {
        guard labelLeads, showsPercentages(on: axis) else { return 0 }
        return percentTextHeight + ringToTextSpacing
    }

    /// Whether an item carries its percent label. A setting on both axes, with
    /// opposite defaults: down a side the label sits under its ring and costs
    /// nothing, while across the top it is a second line of type directly under
    /// the menu bar.
    static func showsPercentages(on axis: PanelEdge.Axis) -> Bool {
        axis == .vertical
            ? PanelMetrics.sideRailShowsPercentages
            : PanelMetrics.topRailShowsPercentages
    }

    /// The room left at each end of the rail, before the first ring.
    ///
    /// Less when the rail is floating, and that is not a taste: docked, the
    /// concave flare carves `flareHeight` out of each end, so the black you
    /// actually see above the first ring is the difference. Off the edge there
    /// is no flare and the whole padding shows — 54pt against a 30pt gap
    /// between rings, which reads as the ends having been forgotten. Taking
    /// the flare off the number keeps the *visible* breathing room the same on
    /// both, which is what anyone is actually looking at — and because the
    /// flare is as tall as the rail is half wide, it also sits the end ring in
    /// the capsule's round end exactly where it sits in the docked rail's.
    static func endPadding(docked: Bool) -> CGFloat {
        docked ? verticalPadding : verticalPadding - flareHeight
    }

    /// One item's extent **along** the rail.
    ///
    /// Down a side that is the ring stacked over its label; across the top the
    /// two are stacked the same way but the run is the other axis, so an item
    /// is as wide as the **wider of the two**.
    ///
    /// It used to be the ring alone, on the stated premise that the label is
    /// narrower at every size. Measured, "100%" is *wider* — by 1.5 / 1.0 /
    /// 1.1pt at small / standard / large — so a top rail was built about a
    /// point short per ring, the stack was squeezed, and the only thing in an
    /// item that can compress is the text: every label rendered as "10…".
    static func itemLength(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        guard showsPercentages(on: axis) else { return ringDiameter }
        if labelsBeside(on: axis, docked: docked) { return ringDiameter + ringToTextSpacing + percentTextWidth }
        return axis == .vertical ? itemHeight : max(ringDiameter, percentTextWidth)
    }

    /// A rail lying across and standing free, with labels on — which is
    /// laid out in one of two proportions of its own, never the top dock's.
    ///
    /// The top dock's proportion on a free pill — labels stacked, 10pt above
    /// and below, the upright rail's 30pt between rings — read as cramped top
    /// to bottom and scattered side to side: a row of loose icons rather than
    /// one rail. Docked to the top it keeps that proportion; it hangs from the
    /// menu bar rather than floating as a pill.
    static func freeAcrossWithLabels(on axis: PanelEdge.Axis, docked: Bool) -> Bool {
        axis == .horizontal && !docked && showsPercentages(on: .horizontal)
    }

    /// The free lying rail's labels **beside** their rings
    /// (`AppSettings.freeAcrossFiguresBeside`): the rail is the upright one's
    /// thickness and reads as the same object turned over, but longer.
    static func labelsBeside(on axis: PanelEdge.Axis, docked: Bool) -> Bool {
        freeAcrossWithLabels(on: axis, docked: docked) && PanelMetrics.freeAcrossFiguresBeside
    }

    /// The free lying rail's labels **under** their rings, the default: the
    /// rings closer together and more room above and below than the top dock.
    static func labelsStackedFree(on axis: PanelEdge.Axis, docked: Bool) -> Bool {
        freeAcrossWithLabels(on: axis, docked: docked) && !PanelMetrics.freeAcrossFiguresBeside
    }

    /// The gap between items along the rail. Tighter on a free lying rail,
    /// whose items already sit apart by their labels' width.
    static func gap(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        if labelsBeside(on: axis, docked: docked) { return 18 * PanelMetrics.scale * PanelMetrics.spacing }
        if labelsStackedFree(on: axis, docked: docked) { return 20 * PanelMetrics.scale * PanelMetrics.spacing }
        return itemSpacing
    }

    /// The room either side of the items **across** the rail.
    static func crossPadding(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        labelsStackedFree(on: axis, docked: docked) ? 14 * PanelMetrics.scale : horizontalPadding
    }

    /// The rail's extent **across** its run: its width down a side, its height
    /// across the top.
    ///
    /// `width` is deliberately more than a ring and its padding — the rail has
    /// always been drawn wider than its contents — so a top rail without
    /// labels keeps exactly the same proportion by using the same number. With
    /// labels there is a second line to make room for.
    /// Down a side this is always `width`, labels or not: the berth's flare
    /// and its corners share that measurement (`cornerRadius + flareWidth <=
    /// width`), so narrowing the rail when the labels go would fold the shape
    /// in on itself. Only the rail's *length* changes there.
    static func thickness(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        guard axis == .horizontal, showsPercentages(on: .horizontal),
              !labelsBeside(on: axis, docked: docked) else { return width }
        let insets = crossInsets(on: axis, docked: docked)
        return itemHeight + insets.leading + insets.trailing
    }

    /// The padding either side of the items across the rail — top and bottom
    /// lying across, left and right down a side.
    ///
    /// **The ring's side gets 10pt more while the time-until-reset arc is
    /// on**, when the rail lies across with its figures stacked over or under
    /// the rings. The arc stands 5pt further out than the ring, and with
    /// figures above the rings at the top dock it sat 3pt off the rail's
    /// bottom edge, under a notch's whole housing of black (issue #78). Its
    /// own reach alone (5pt) was tried first and still read cramped; 10 was
    /// picked by eye on the bundled app, which leaves 5pt more past the arc
    /// than a ring without one has. The figures' side is left as it was: the
    /// gap between a ring and its figure already allows for the arc
    /// (`ringToTextSpacing`). Down a side, and with figures beside or off, the
    /// rail is far wider than a ring and its arc, so nothing is added.
    static func crossInsets(on axis: PanelEdge.Axis,
                            docked: Bool = true) -> (leading: CGFloat, trailing: CGFloat) {
        let padding = crossPadding(on: axis, docked: docked)
        guard axis == .horizontal, showsPercentages(on: .horizontal),
              !labelsBeside(on: axis, docked: docked) else { return (padding, padding) }
        let extra = PanelMetrics.showsWindowClock ? 10 * PanelMetrics.scale : 0
        return labelLeads ? (padding, padding + extra) : (padding + extra, padding)
    }

    /// Rail length for a given number of providers: the padding at each end +
    /// the items + the gaps between them. Providers can be switched off in
    /// settings, so this is not a constant.
    static func length(for itemCount: Int, on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        let count = CGFloat(max(itemCount, 1))
        return endPadding(docked: docked) * 2 + itemLength(on: axis, docked: docked) * count
            + gap(on: axis, docked: docked) * (count - 1)
    }

    /// The rail's full size, laid the way `edge` lays it.
    static func size(for itemCount: Int, on axis: PanelEdge.Axis, docked: Bool = true) -> CGSize {
        let along = length(for: itemCount, on: axis, docked: docked)
        let across = thickness(on: axis, docked: docked)
        return axis == .vertical
            ? CGSize(width: across, height: along)
            : CGSize(width: along, height: across)
    }

    /// Where a ring's centre sits **across** the rail.
    ///
    /// The items are centred in the rail's thickness, and how thick an item is
    /// depends on whether it carries a label — so this is not simply half the
    /// rail. Down a side only the ring is ever as wide as this, the label being
    /// narrower; across the top the label is stacked under the ring and counts.
    static func ringCentreAcross(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        if labelsBeside(on: axis, docked: docked) { return thickness(on: axis, docked: docked) / 2 }
        let item = axis == .vertical
            ? ringDiameter
            : (showsPercentages(on: axis) ? itemHeight : ringDiameter)
        guard axis == .horizontal, showsPercentages(on: axis) else {
            return (thickness(on: axis, docked: docked) - item) / 2 + ringDiameter / 2
        }
        return crossInsets(on: axis, docked: docked).leading + ringOffsetInItem(on: axis) + ringDiameter / 2
    }

    /// How far along the rail the first ring's centre sits, and the step from
    /// one to the next.
    static func firstRingAlong(docked: Bool = true, on axis: PanelEdge.Axis = .vertical) -> CGFloat {
        // How far into its item the ring's centre sits, **along the rail**.
        //
        // Down a side the item is the ring stacked over its label, so this is
        // the label's share when it leads plus half a ring. Across the top the
        // stack runs the other way and the ring is simply centred in the
        // item's width — which is *not* half a ring once the item is as wide
        // as the label, and the label is the wider of the two.
        // Beside, the ring leads its item — or follows the label, when the
        // label is set to come first.
        // Beside, the ring leads its item: the setting that put the figure
        // there says *right* of the ring, so "above" does not move it left.
        let intoItem = if labelsBeside(on: axis, docked: docked) {
            ringDiameter / 2
        } else if axis == .vertical {
            ringOffsetInItem(on: axis) + ringDiameter / 2
        } else {
            itemLength(on: axis) / 2
        }
        return endPadding(docked: docked) + intoItem
    }
    static func ringStep(on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        itemLength(on: axis, docked: docked) + gap(on: axis, docked: docked)
    }

    /// Rail length with every provider switched on, which is what the panel
    /// has to leave room for. Measured docked, which is the longer of the two —
    /// the window never needs to shrink, only the rail drawn inside it.
    /// Lying across, a free rail with its labels beside the rings is the
    /// longer one, so the window is budgeted for whichever is longer — the
    /// window may grow, never the rail outgrow it.
    static func maximumLength(on axis: PanelEdge.Axis, capacity: Int = PanelMetrics.railCapacity) -> CGFloat {
        max(length(for: capacity, on: axis, docked: true), length(for: capacity, on: axis, docked: false))
    }

    /// Kept for the vertical rail, which is what every existing caller means.
    static func height(for itemCount: Int) -> CGFloat {
        length(for: itemCount, on: .vertical)
    }

    /// What the rail hides down to when the pointer is elsewhere: a sliver
    /// against the screen edge.
    ///
    /// Six points is enough to be seen and — because it is welded to the edge
    /// of the display — trivially easy to hit, since throwing the pointer at
    /// the edge always lands on it. The tracking area around it is wider than
    /// the drawing, so approaching from inside works without having to arrive
    /// exactly.
    static var collapsedWidth: CGFloat { 6 * PanelMetrics.scale }
    static var collapsedHeight: CGFloat { 96 * PanelMetrics.scale }
    static var collapsedHitWidth: CGFloat { 20 * PanelMetrics.scale }

    /// The sliver, laid the way `axis` lays the rail: 6pt of it against the
    /// screen edge and 96pt along it, whichever way round that falls.
    static func collapsedSize(on axis: PanelEdge.Axis) -> CGSize {
        axis == .vertical
            ? CGSize(width: collapsedWidth, height: collapsedHeight)
            : CGSize(width: collapsedHeight, height: collapsedWidth)
    }

    /// The same for the tracking area, which is wider than the drawing.
    static func collapsedHitSize(on axis: PanelEdge.Axis) -> CGSize {
        axis == .vertical
            ? CGSize(width: collapsedHitWidth, height: collapsedHeight)
            : CGSize(width: collapsedHeight, height: collapsedHitWidth)
    }

    /// The tallest the rail gets with what is switched on now. The panel window
    /// is kept at this height while a reading changes the rail — a split
    /// account's second ring is already budgeted for — and resized only when a
    /// setting changes what is shown. See `AppSettings.railSlotCount`.
    static var maximumHeight: CGFloat { height(for: PanelMetrics.railCapacity) }
}

/// A provider's place in the rail: what it reports, and the one window its
/// ring shows. The ring's window is resolved by the caller because the choice
/// is a setting, and the rail shouldn't have to know about settings.
struct RailEntry: Identifiable, Equatable {
    let usage: ProviderUsage
    let headline: UsageWindow?
    /// Whether this provider's CLI is working at this moment, which the ring
    /// shows as a turning mark.
    var isRunning: Bool = false
    /// Whether Pulse is currently fetching a fresh reading for this provider.
    var isRefreshing: Bool = false
    /// A colour chosen for this ring, or nil to colour it by usage.
    var tint: Color?
    /// Which ring this is. An unsplit account's slot keeps the account's own
    /// id, so nothing stored before slots existed stops matching.
    var slot: RailSlot
    /// What the card calls it: the account's label, and the model group after
    /// it where an account has been split into one ring per group.
    var title: String
    /// How much of the headline window's clock to draw in the chosen direction,
    /// or nil to leave the outer arc off — either because the setting is off,
    /// or because this window doesn't report enough to work it out.
    var windowClock: Double?
    /// What to draw in the ring when there is no percentage to draw.
    ///
    /// DeepSeek sells prepaid credit and reports no allowance, so on "balance
    /// only" there is deliberately no window and therefore no fraction — but
    /// there *is* a figure, and a ring showing an em dash beside a perfectly
    /// good balance reads as a provider that failed. Nil everywhere else,
    /// where nothing known really does mean nothing known.
    var figure: String?
    /// The next-fullest limit, when the second ring is switched on and this
    /// provider reports more than one.
    var second: UsageWindow?
    /// Show what is left rather than what is gone — the figure and the arc
    /// together. Carried on the entry like the tint, because the item is built
    /// from this and doesn't otherwise see the settings.
    var showsRemaining: Bool = false
    /// The robot in place of the provider's mark, or nil for the mark.
    var robot: RobotCue?
    /// The account's discovered PNG, shared by its ring and detail card.
    var iconData: Data? = nil

    var id: String { slot.id }
}

/// The rail, in whatever state it is currently in — full, collapsed to a
/// sliver against the screen edge, or somewhere between the two.
///
/// The two states used to be separate views swapped by a transition, which is
/// what made the sliver read as *disappearing* while a rail *appeared* in its
/// place. They are one thing: a single berth whose size and outline are
/// animated, with the rings fading in once it has opened enough to hold them.
struct UsageDockView: View {
    let entries: [RailEntry]
    let selectedSlot: String?
    let edge: PanelEdge
    /// Fused to a screen edge, or standing free on the desktop. Only the
    /// silhouette changes: docked it flares into the edge, floating it closes
    /// itself off into a capsule.
    var isDocked: Bool = true
    /// Open, or wound down to the sliver.
    var isExpanded: Bool = true
    var notchSize: CGSize?
    /// How far the rail is drawn off its edge while it is pulled away or drawn
    /// on, and how thin the neck is on the way on (`DropletTether`).
    var pull: CGFloat = 0
    var thinning: CGFloat = 0
    /// How far a parted neck's pieces have drawn back (`DropletTether`).
    var parted: CGFloat = 0
    /// How hard the hand is pulling, 0 to 1, which thins the neck as well as
    /// how far the rail has got: on a quick pull the rail trails the hand.
    var tension: CGFloat = 0
    /// How much a rail that has just let go of an edge still has its docked
    /// corners (`DockBerthShape.fusion`).
    var fusion: CGFloat = 0
    /// How fast the rail is being carried, in points a second, for the
    /// stretch a quick throw gives it.
    var motion: CGVector = .zero
    /// Colours the sliver when a limit is close enough that hiding the rail
    /// would be hiding something worth seeing.
    var alert: Color?
    /// Liquid Glass instead of flat black.
    var usesGlass: Bool = false
    /// Whether a ring turns while its CLI is working or Pulse is refreshing
    /// it. See `AppSettings.animatesRingActivity`.
    var animatesActivity: Bool = true
    /// Called as the pointer arrives on a provider's ring. The details flyout
    /// follows the pointer rather than a click, so this is what drives
    /// selection. Leaving is handled by `PanelPointerWatcher`, not here.
    let onEnter: (RailEntry) -> Void
    /// The accessibility/default action for a provider ring. Physical clicks
    /// are resolved by `FloatingPanel`, which owns mouse input ahead of SwiftUI.
    var onRefresh: (AccountKey) -> Void = { _ in }
    /// Called as the pointer arrives on the collapsed sliver.
    var onOpen: () -> Void = {}

    private var railSize: CGSize { DockLayout.size(for: entries.count, on: edge.axis, docked: isDocked) }

    /// The pull while it can be seen: docked, open, and not past the edge.
    private var shownPull: CGFloat { isDocked && isExpanded ? max(pull, 0) : 0 }

    /// How much a throw at `motion` stretches the surface: up to 14% at
    /// 2600pt a second along the way it is going, and 35% of that thinner
    /// across. The figures are codenotch's, which the user liked.
    private var stretch: (scale: CGSize, anchor: UnitPoint) {
        // **Docked, only along the edge.** Stretched across it, the neck and
        // its foot were pushed off the edge they are joined to.
        let motion = isDocked
            ? (edge.isVertical ? CGVector(dx: 0, dy: motion.dy) : CGVector(dx: motion.dx, dy: 0))
            : motion
        let speed = hypot(motion.dx, motion.dy)
        let amount = min(speed / 2600, 1) * 0.14
        guard amount > 0.001 else { return (CGSize(width: 1, height: 1), .center) }
        // Screen coordinates run up; SwiftUI's run down.
        if abs(motion.dx) >= abs(motion.dy) {
            return (CGSize(width: 1 + amount, height: 1 - 0.35 * amount), motion.dx > 0 ? .trailing : .leading)
        }
        return (CGSize(width: 1 - 0.35 * amount, height: 1 + amount), motion.dy > 0 ? .top : .bottom)
    }

    /// The pull as a move into the panel, away from the edge.
    private var pullOffset: CGSize {
        let p = shownPull
        return switch edge {
        case .right: CGSize(width: -p, height: 0)
        case .left: CGSize(width: p, height: 0)
        case .top: CGSize(width: 0, height: p)
        case .bottom: CGSize(width: 0, height: -p)
        }
    }
    private var currentSize: CGSize {
        isExpanded ? railSize : DockLayout.collapsedSize(on: edge.axis)
    }

    var body: some View {
        // Laid out at full size whatever it is drawing, so nothing around it
        // moves as it opens and closes.
        ZStack(alignment: edge.stackAlignment) {
            berth
                // A quick throw draws the surface out behind the rings, the
                // front staying with the hand, and thins it a little.
                .scaleEffect(stretch.scale, anchor: stretch.anchor)

            rings
                // Carried with the body as it is pulled off the edge. Never
                // past the edge: a spring settling back overshoots below zero.
                .offset(pullOffset)
                // Still in the tree while collapsed, so nothing moves as it
                // opens; but nothing in it may animate for nobody.
                .opacity(isExpanded ? 1 : 0)
                // Its own timing, overriding the spring the shape rides on:
                // the contents appear once the berth has opened enough to hold
                // them, and are gone before it closes. Without the delay they
                // fade up over a shape that is still a sliver, which is the
                // giveaway that these were ever two separate things.
                .animation(
                    .easeOut(duration: isExpanded ? 0.18 : 0.10)
                        .delay(isExpanded ? 0.12 : 0),
                    value: isExpanded
                )
        }
        .frame(width: railSize.width, height: railSize.height)
        .allowsHitTesting(notchSize == nil || isExpanded)
        .accessibilityHidden(notchSize != nil && !isExpanded)
        // No drag handle lives here any more. A press only reaches a view
        // inside `NSHostingView` if SwiftUI claims it first, so the berth
        // (`PanelSurface`) is deliberately hit-testable: it is what claims
        // the empty black between the rings, which is what lets the panel be
        // dragged from there and not only by its rings. Laying a shape over
        // the handle to claim them once swallowed the press instead of
        // passing it down, and then nothing could be dragged at all.
        //
        // The window takes its own mouse events instead — see `FloatingPanel`
        // in FloatingPanelController.swift — which happens before any of
        // SwiftUI's hit testing and cannot be undone by it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Provider usage selector"))
    }

    @ViewBuilder
    private var berth: some View {
        if let notchSize {
            let surface = PanelHitArea.notchSurface(rail: CGRect(origin: .zero, size: railSize), notchSize: notchSize)
            PanelSurface(
                shape: NotchBerthShape(notchSize: notchSize, openness: isExpanded ? 1 : 0,
                                       pull: shownPull, thinning: max(thinning, tension), parted: parted),
                usesGlass: usesGlass,
                screenEdge: .top
            )
            .overlay {
                // The hardware housing replaces the ordinary collapsed
                // sliver. Keep its one useful signal as a thin line directly
                // under the housing; expanded rings already carry the colour.
                if !isExpanded, let alert {
                    NotchAlertShape(notchSize: notchSize)
                        .fill(alert)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Wider than the surface by the room the fillets sweep into at
            // the screen edge; the shape insets that back off for the body.
            .frame(width: surface.width + DockLayout.flareWidth * 2, height: surface.height)
            .offset(y: surface.minY)
            .frame(width: railSize.width, height: railSize.height, alignment: .top)
        } else {
            ordinaryBerth
        }
    }

    private var ordinaryBerth: some View {
        let shape = DockBerthShape(edge: edge, isDocked: isDocked, openness: isExpanded ? 1 : 0,
                                   pull: shownPull, thinning: max(thinning, tension), parted: parted, fusion: fusion)

        return PanelSurface(
            shape: shape,
            usesGlass: usesGlass,
            // Only the sliver carries the alert colour: expanded, the rings
            // already say which limit is where.
            tint: isExpanded ? nil : alert,
            screenEdge: isDocked ? edge.screenSide : []
        )
            .frame(width: currentSize.width, height: currentSize.height)
            .overlay(alignment: edge.stackAlignment) {
                // Only while collapsed, and only over the sliver: a tracking
                // area on the full band would open the panel from sixty points
                // of empty air.
                if !isExpanded {
                    let hit = DockLayout.collapsedHitSize(on: edge.axis)
                    Color.clear
                        .frame(width: hit.width, height: hit.height)
                        .contentShape(.rect)
                        .background(PointerEntryReporter(onEnter: onOpen))
                        .accessibilityElement()
                        .accessibilityLabel(String.localized("Show usage panel"))
                }
            }
    }

    private var rings: some View {
        // The same items, stacked whichever way the rail runs. `AnyLayout`
        // keeps them one set of views across the change rather than two sets
        // swapped, so a rail that is re-docked from a side to the top carries
        // its rings round with it instead of rebuilding them.
        let spacing = DockLayout.gap(on: edge.axis, docked: isDocked)
        let stack = edge.isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))

        return stack {
            ForEach(entries) { entry in
                UsageDockItem(
                    entry: entry,
                    isSelected: selectedSlot == entry.slot.id,
                    isInteractive: isExpanded,
                    showsPercentage: DockLayout.showsPercentages(on: edge.axis),
                    labelBeside: DockLayout.labelsBeside(on: edge.axis, docked: isDocked),
                    animatesActivity: animatesActivity,
                    onEnter: { onEnter(entry) },
                    onRefresh: { onRefresh(entry.slot.account) }
                )
                // **Every item takes exactly the length it was budgeted.**
                // `DockLayout` decides the rail's size before SwiftUI lays
                // anything out, and the hit testing steps along it in those
                // same units — so an item allowed to take its natural size
                // instead puts every ring after it a little further out than
                // the hit test looks, and the error accumulates down the rail.
                // It reached 12.6pt at eleven rings, which is a third of a
                // ring, purely from a label rendering narrower than its budget.
                .frame(
                    width: edge.isVertical ? nil : DockLayout.itemLength(on: .horizontal, docked: isDocked),
                    height: edge.isVertical ? DockLayout.itemLength(on: .vertical) : nil
                )
            }
        }
        // The padding follows the run too: the generous end padding is what
        // the flare needs room inside, and the flare is at the rail's ends
        // whichever way it is lying.
        .padding(edge.isVertical ? .vertical : .horizontal, DockLayout.endPadding(docked: isDocked))
        .padding(edge.isVertical ? .leading : .top, DockLayout.crossInsets(on: edge.axis, docked: isDocked).leading)
        .padding(edge.isVertical ? .trailing : .bottom, DockLayout.crossInsets(on: edge.axis, docked: isDocked).trailing)
        .frame(width: railSize.width, height: railSize.height)
    }
}

private struct UsageDockItem: View {
    let entry: RailEntry
    let isSelected: Bool
    /// False while the rail is collapsed. The rings are still in the view
    /// tree then, only invisible — and an invisible ring with a live tracking
    /// area would open a card for a provider nobody can see.
    let isInteractive: Bool
    /// False for a rail lying across the top with the labels switched off,
    /// which is the default there — see `AppSettings.topRailShowsPercentages`.
    var showsPercentage: Bool = true
    /// The label beside the ring rather than under it (`DockLayout.labelsBeside`).
    var labelBeside: Bool = false
    /// Whether this ring turns while its CLI is working or being refreshed.
    var animatesActivity: Bool = true
    let onEnter: () -> Void
    let onRefresh: () -> Void

    private var usage: ProviderUsage { entry.usage }
    private var headline: UsageWindow? { entry.headline }

    var body: some View {
        // The label goes above or below on a setting. `ringOffsetInItem` is
        // the same swap expressed as a number, and the hit testing runs on
        // that — the two must not be allowed to disagree.
        let layout = labelBeside
            ? AnyLayout(HStackLayout(spacing: DockLayout.ringToTextSpacing))
            : AnyLayout(VStackLayout(spacing: DockLayout.ringToTextSpacing))
        layout {
            if DockLayout.labelLeads && !labelBeside { sizedLabel }

            ring

            // Beside, always after the ring: the switch that put it there
            // says *right* of the ring (issue #73).
            if !DockLayout.labelLeads || labelBeside { sizedLabel }
        }
        .contentShape(.rect)
        .background {
            if isInteractive { PointerEntryReporter(onEnter: onEnter) }
        }
        .accessibilityElement(children: .ignore)
        // The entry's title, not the provider's name: a split provider draws
        // two rings from one login, and named by the provider alone VoiceOver
        // reads out the same thing twice.
        .accessibilityLabel(String.localized("\(entry.title) usage"))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(String.localized("Activate to refresh usage."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(String.localized("Refresh usage")), onRefresh)
    }

    /// Lifted out of `body` because the initializer has enough arguments that
    /// type-checking it inline exceeded the compiler's budget.
    private var ring: some View {
        UsageRingView(
            provider: usage.provider,
            usedFraction: headline?.usedFraction,
            // A ring showing money instead of a percentage has a reading; only
            // one showing an em dash does not.
            hasReading: headline != nil || entry.figure != nil,
            chosenTint: entry.tint,
            isSpent: UsageTint.isSpent(headline),
            showsRemaining: entry.showsRemaining,
            diameter: DockLayout.ringDiameter,
            lineWidth: DockLayout.ringLineWidth,
            isBusy: entry.isRunning,
            isRefreshing: entry.isRefreshing,
            animatesActivity: animatesActivity,
            highlight: isSelected,
            windowClockFraction: entry.windowClock,
            secondFraction: entry.second?.usedFraction,
            secondIsSpent: UsageTint.isSpent(entry.second),
            robot: entry.robot,
            isLive: isInteractive,
            iconData: entry.iconData
        )
        .scaleEffect(isSelected ? 1.06 : 1)
    }

    /// Beside its ring the label takes exactly its budgeted width, held
    /// against the ring, so a short "0%" does not slide the ring along —
    /// the hit testing steps in budgeted units (`DockLayout.firstRingAlong`).
    @ViewBuilder
    private var sizedLabel: some View {
        if labelBeside {
            percentLabel.frame(width: DockLayout.percentTextWidth, alignment: .leading)
        } else {
            percentLabel
        }
    }

    /// An em dash rather than 0% when nothing is known: a zero would read as
    /// "you've used nothing" — or, flipped, as "you have nothing left", which
    /// is a worse claim still.
    @ViewBuilder
    private var percentLabel: some View {
        if showsPercentage {
            Text(headline?.percentText(remaining: entry.showsRemaining) ?? entry.figure ?? "—")
                .font(.system(size: DockLayout.percentFontSize, weight: .medium, design: .rounded))
                // Money is longer than a percentage and its length is not
                // bounded by anything — "¥9.40" fits where "$1,234.56" does
                // not — so it shrinks to fit rather than being cut off inside
                // the ring.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // A spent limit colours the figure too. At ring size a fourth
                // hue on the stroke alone would read as the third.
                .foregroundStyle(
                    UsageTint.isSpent(headline)
                        ? Color.pulseExhausted
                        : .primary.opacity(headline == nil && entry.figure == nil ? 0.4 : 1)
                )
                .monospacedDigit()
                // Dimmed with the arc, so the whole ring goes quiet together
                // while its reading is fetched, and returns with it.
                .opacity(entry.isRefreshing ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: entry.isRefreshing)
                // Digits change places rather than cutting, so a figure that
                // actually moved is visibly what moved.
                .contentTransition(.numericText())
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.85),
                    value: headline?.percentText(remaining: entry.showsRemaining) ?? entry.figure
                )
        }
    }

    private var accessibilityValue: String {
        let reading = headline.map { window in
            entry.showsRemaining
                ? String.localized("\(window.percentText(remaining: true)) left, \(window.name)")
                : String.localized("\(window.percentText) used, \(window.name)")
        } ?? String.localized("No reading")
        return entry.isRefreshing
            ? "\(reading). \(String.localized("Refreshing…"))"
            : reading
    }
}

/// A vertical "berth" shape for the collapsed rail, in the spirit of a
/// Dynamic Island or the flared root of a browser tab: the rail looks like
/// it grew out of the screen's right edge rather than being parked next to
/// it.
///
/// The right edge runs flush against the screen for the shape's whole
/// height — nothing is rounded there, so no wallpaper ever shows between
/// the rail and the edge. The rail *body* is inset from the top and bottom
/// by `flareHeight`, and each end sweeps out to the screen edge through a
/// concave fillet that leaves the body's flat edge horizontally and meets
/// the screen edge vertically, so both junctions are tangent-continuous.
///
/// The flare lives inside the bounding rect, which is why
/// `DockLayout.verticalPadding` must stay >= `flareHeight`: content laid
/// out above the body's flat top would fall outside the shape and be
/// clipped.
struct DockBerthShape: Shape {
    /// Which screen edge the rail is flush against.
    ///
    /// Drawn once, facing right, then moved into place: mirrored for the left
    /// edge, turned a quarter for the top. The outline carries no text and no
    /// asymmetric detail, so transforming the finished path is exact and
    /// avoids a second copy of the geometry that could drift from this one.
    var edge: PanelEdge = .right
    /// Off the edge there is nothing to fuse with, so the flare gives way to a
    /// capsule with fully round ends. Drawing an edge-hugging silhouette in
    /// the middle of the desktop reads as a rendering fault rather than as a
    /// design.
    var isDocked: Bool = true

    /// How far open the berth is: 0 is the collapsed sliver, 1 the full rail.
    ///
    /// The sliver is not a different shape — it is this one with its flare and
    /// corners wound all the way down, which is what lets the two be animated
    /// between as a single object changing size rather than swapped for one
    /// another. At 0 the flare vanishes and the corner radius equals the whole
    /// width, leaving exactly the rounded-on-one-side sliver.
    var openness: CGFloat = 1

    /// How far a docked rail is drawn off its edge while it is being pulled
    /// away or drawn onto it; the gap is the liquid neck
    /// (`DropletTether`). Drawn outside the frame, into the panel.
    var pull: CGFloat = 0
    /// Extra thinning of that neck while the rail is being drawn on.
    var thinning: CGFloat = 0
    /// The neck's two pieces drawing back after it has parted, 0 to 1.
    var parted: CGFloat = 0
    /// Standing free, how much it still has the docked rail's corners: 1 the
    /// moment it lets go of an edge, easing to 0, the capsule. So the outline
    /// rounds off rather than being swapped for another in one frame.
    var fusion: CGFloat = 0

    /// Lets the outline itself be interpolated, so the silhouette is redrawn
    /// at every step of the animation instead of one shape being faded into
    /// another.
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(openness, AnimatablePair(pull, thinning)) }
        set {
            openness = newValue.first
            pull = newValue.second.first
            thinning = newValue.second.second
        }
    }

    private var flareHeight: CGFloat { DockLayout.flareHeight * openness }
    private var flareWidth: CGFloat { DockLayout.flareWidth * openness }
    private var cornerRadius: CGFloat {
        DockLayout.collapsedWidth
            + (DockLayout.cornerRadius - DockLayout.collapsedWidth) * openness
    }

    func path(in rect: CGRect) -> Path {
        guard isDocked else { return floating(in: rect) }
        let pulled = pull * min(max(openness, 0), 1)
        if pulled > 0.01 { return tethered(in: rect, pull: pulled) }

        switch edge {
        case .right:
            return facingRight(in: rect)

        case .left:
            return facingRight(in: rect).applying(
                CGAffineTransform(translationX: rect.width, y: 0).scaledBy(x: -1, y: 1)
            )

        case .bottom:
            // A quarter turn clockwise, which carries the flare from the
            // right-hand edge to the bottom one — the top dock's drawing
            // turned the other way, so the winding is preserved here too.
            let canonical = CGRect(x: 0, y: 0, width: rect.height, height: rect.width)
            return facingRight(in: canonical).applying(
                CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)
            )

        case .top:
            // A quarter turn anticlockwise, which carries the flare from the
            // right-hand edge to the top one. The canonical rect is this one
            // laid on its side, so the drawing is unchanged and only its
            // placement differs — and because it is a rotation rather than a
            // reflection, the path's winding is preserved.
            let canonical = CGRect(x: 0, y: 0, width: rect.height, height: rect.width)
            return facingRight(in: canonical).applying(
                CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: rect.height)
            )
        }
    }

    /// A true capsule: the ends are half circles, not rounded-off corners.
    ///
    /// Circular, not a squircle. A squircle eases its curvature into the
    /// straight edge either side of it, and at this width the two corners of
    /// an end meet with no straight edge between them at all — so there is
    /// nothing to ease into and the result reads as a flattened lozenge. Fully
    /// round ends are what a free-standing pill is — and while
    /// `AppSettings.usesRoundEnds` is on they are the docked rail's ends too,
    /// less the flare.
    private func floating(in rect: CGRect) -> Path {
        let capsule = min(rect.width, rect.height) / 2
        let docked = min(DockLayout.cornerRadius, capsule)
        let radius = capsule + (docked - capsule) * min(max(fusion, 0), 1)
        return Path(
            roundedRect: rect,
            cornerSize: CGSize(width: radius, height: radius),
            style: .circular
        )
    }

    private func facingRight(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let f = min(flareHeight, h / 2)
        // The convex corners live on the body, which spans y in [f, h - f].
        let r = max(min(cornerRadius, min(w, (h - f * 2) / 2)), 0)
        // The flare must leave room for that corner: if `flareWidth + r`
        // exceeded the width, the body's flat top edge would run backwards
        // and the path would fold in on itself.
        let fw = max(min(flareWidth, w - r), 0)

        var path = Path()

        // Body's flat top edge, left to right.
        path.move(to: CGPoint(x: r, y: f))
        path.addLine(to: CGPoint(x: w - fw, y: f))

        // Concave fillet sweeping up into the screen edge: a turn whose
        // curvature eases in and out, so neither end reads as a corner
        // (`DropletTether.fluidTurn`).
        path.addLines([CGPoint(x: w - fw, y: f)] + DropletTether.fluidTurn(
            from: CGPoint(x: w - fw, y: f), along: CGVector(dx: 1, dy: 0),
            to: CGPoint(x: w, y: 0), then: CGVector(dx: 0, dy: -1)
        ))

        // Flush against the screen for the full height.
        path.addLine(to: CGPoint(x: w, y: h))

        // Mirrored fillet back down into the body's bottom edge.
        for point in DropletTether.fluidTurn(
            from: CGPoint(x: w, y: h), along: CGVector(dx: 0, dy: -1),
            to: CGPoint(x: w - fw, y: h - f), then: CGVector(dx: -1, dy: 0)
        ) {
            path.addLine(to: point)
        }

        // Body's flat bottom edge, right to left.
        path.addLine(to: CGPoint(x: r, y: h - f))

        appendFarEnd(to: &path, width: w, height: h, flare: f, radius: r)

        path.closeSubpath()
        return path
    }

    /// The body's two corners away from the edge and the side between them,
    /// from the bottom edge round to the top one.
    private func appendFarEnd(to path: inout Path, width w: CGFloat, height h: CGFloat, flare f: CGFloat, radius r: CGFloat) {
        // The two convex corners. Round ends draw them as circular arcs —
        // see `DockLayout.cornerRadius` for why not a squircle — each
        // starting at the tangent point the path is already on: bottom edge
        // round to the left edge, then left edge round to the top one.
        // Softened ends sample a superellipse instead, which is the shape
        // Pulse shipped with.
        if PanelMetrics.usesRoundEnds {
            path.addArc(
                tangent1End: CGPoint(x: 0, y: h - f),
                tangent2End: CGPoint(x: 0, y: f),
                radius: r
            )

            // Left edge.
            path.addLine(to: CGPoint(x: 0, y: f + r))

            path.addArc(
                tangent1End: CGPoint(x: 0, y: f),
                tangent2End: CGPoint(x: w, y: f),
                radius: r
            )
        } else {
            // Bottom-left corner: starts directly below the corner's center
            // and ends directly to its left.
            appendCorner(
                to: &path,
                center: CGPoint(x: r, y: h - f - r),
                radius: r,
                from: CGVector(dx: 0, dy: 1),
                to: CGVector(dx: -1, dy: 0)
            )

            // Left edge.
            path.addLine(to: CGPoint(x: 0, y: f + r))

            // Top-left corner: starts to the left of its center, ends above it.
            appendCorner(
                to: &path,
                center: CGPoint(x: r, y: f + r),
                radius: r,
                from: CGVector(dx: -1, dy: 0),
                to: CGVector(dx: 0, dy: -1)
            )
        }
    }

    /// The rail drawn `pull` off its edge, joined to it by the neck.
    ///
    /// Built facing right, like `facingRight`, in a frame `pull` wider: the
    /// body keeps its place at the left and the edge moves out. Each dock
    /// then turns it into place, with the body moved `pull` into the panel
    /// and the edge where the frame's edge always was.
    private func tethered(in rect: CGRect, pull: CGFloat) -> Path {
        let vertical = edge.isVertical
        let w = vertical ? rect.width : rect.height
        let h = vertical ? rect.height : rect.width
        let f = min(flareHeight, h / 2)
        let r = max(min(cornerRadius, min(w, (h - f * 2) / 2)), 0)
        let fw = max(min(flareWidth, w - r), 0)

        let bridge = DropletTether.bridge(.init(
            bodyWidth: w,
            gap: pull,
            pull: pull,
            centre: h / 2,
            contact: (h - f * 2) / 2,
            flareAlong: f,
            flareIn: fw,
            // A broad foot on the edge narrowing to a waist, like the drop
            // that hangs from the notch.
            joinHalf: w * 0.45,
            // Never most of a short rail's length, which read as a slab.
            footHalf: min(w * 0.9, (h - f * 2) / 2 * 0.4),
            thinning: thinning,
            parted: parted
        ))

        // The corners on the edge side round off only where the neck has
        // drawn away from them.
        let rr = max(min(r, (h - f * 2) / 2 - bridge.joinHalf), 0)
        var body = Path()
        body.move(to: CGPoint(x: r, y: f))
        body.addLine(to: CGPoint(x: w - rr, y: f))
        if rr > 0 {
            body.addArc(tangent1End: CGPoint(x: w, y: f), tangent2End: CGPoint(x: w, y: h - f), radius: rr)
        }
        body.addLine(to: CGPoint(x: w, y: h - f - rr))
        if rr > 0 {
            body.addArc(tangent1End: CGPoint(x: w, y: h - f), tangent2End: CGPoint(x: 0, y: h - f), radius: rr)
        }
        body.addLine(to: CGPoint(x: r, y: h - f))
        appendFarEnd(to: &body, width: w, height: h, flare: f, radius: r)
        body.closeSubpath()

        let canonical = body.union(bridge.path)
        let reach = w + pull
        let place: CGAffineTransform = switch edge {
        case .right: CGAffineTransform(translationX: rect.minX - pull, y: rect.minY)
        case .left: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + reach, ty: rect.minY)
        case .top: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.minX, ty: rect.minY + reach)
        case .bottom: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.minX + rect.width, ty: rect.minY - pull)
        }
        return canonical.applying(place)
    }

    /// Appends a quarter of a superellipse — the continuously curved
    /// "squircle" corner macOS uses for its own rounded rectangles — rather
    /// than a circular arc.
    ///
    /// A circular arc jumps from zero curvature along the straight edge to
    /// `1/radius` the instant the corner starts. That discontinuity is what
    /// reads as the edge having been sliced off. A superellipse eases the
    /// curvature in, so the straight edge and the corner belong to the same
    /// stroke. SwiftUI exposes this as `.continuous` for plain rounded
    /// rectangles, but the berth outline has to be drawn by hand, so it is
    /// sampled here instead.
    ///
    /// Only reached while `AppSettings.usesRoundEnds` is off. With it on the
    /// corner is a half circle of half the rail, where there is no straight
    /// edge left for a superellipse to ease into.
    ///
    /// `from` and `to` are unit directions from `center` to the corner's
    /// start and end points; they must be perpendicular and axis-aligned.
    private func appendCorner(
        to path: inout Path,
        center: CGPoint,
        radius: CGFloat,
        from start: CGVector,
        to end: CGVector
    ) {
        guard radius > 0 else { return }

        for step in 1...Self.cornerSampleCount {
            let t = CGFloat(step) / CGFloat(Self.cornerSampleCount) * (.pi / 2)
            // |x/r|^n + |y/r|^n = 1, in its parametric form.
            let along = pow(cos(t), 2 / Self.squircleExponent)
            let across = pow(sin(t), 2 / Self.squircleExponent)

            path.addLine(to: CGPoint(
                x: center.x + radius * (start.dx * along + end.dx * across),
                y: center.y + radius * (start.dy * along + end.dy * across)
            ))
        }
    }

    /// Superellipse exponent. 2 would be a plain circle; 4 lands close to the
    /// squircle Apple uses, keeping the corner full while easing it into the
    /// straight edges.
    private static let squircleExponent: CGFloat = 4
    /// Enough segments that the sampled curve stays sub-pixel smooth at the
    /// sizes this rail is drawn at.
    private static let cornerSampleCount = 48
}

#Preview("Dock") {
    UsageDockView(
        entries: Provider.builtIn.map {
            RailEntry(
                usage: .unavailable($0, reason: .loading),
                headline: nil,
                slot: RailSlot(AccountKey($0)),
                title: $0.displayName
            )
        },
        selectedSlot: RailSlot(AccountKey(.claudeCode)).id,
        edge: .right,
        onEnter: { _ in }
    )
    .frame(height: DockLayout.maximumHeight + 80)
    .padding()
    .background(.gray)
}

private extension PanelEdge {
    /// The side of a docked rail's own frame that lies on the screen's edge.
    var screenSide: Edge.Set {
        switch self {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }
}
