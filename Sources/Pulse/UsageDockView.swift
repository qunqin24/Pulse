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
    /// `verticalPadding - flareHeight`; budget for both when tuning this, and
    /// never let it drop below `flareHeight` or content gets clipped by the
    /// flare.
    static var verticalPadding: CGFloat { 46 * PanelMetrics.scale }
    static var horizontalPadding: CGFloat { 10 * PanelMetrics.scale }

    static var ringDiameter: CGFloat { 36 * PanelMetrics.scale }
    static var ringLineWidth: CGFloat { 4 * PanelMetrics.scale }
    /// Gap between a ring and the percent label beneath it.
    static var ringToTextSpacing: CGFloat { 6 * PanelMetrics.scale }
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

    /// Reach of the two convex corners on the rail's inner side. They are
    /// drawn as superellipse ("squircle") corners rather than circular arcs —
    /// see `DockBerthShape.appendCorner`. Constrained by
    /// `cornerRadius + flareWidth <= width`, since the corner and the flare
    /// share the rail's top and bottom edges.
    static var cornerRadius: CGFloat { 26 * PanelMetrics.scale }
    /// How far the concave flare rises above the rail body's flat top edge
    /// (and drops below its bottom edge) on its way to the screen edge.
    static var flareHeight: CGFloat { 24 * PanelMetrics.scale }
    /// How far in from the screen edge the flare starts sweeping.
    static var flareWidth: CGFloat { 38 * PanelMetrics.scale }

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
    /// is no flare and the whole padding shows — 46pt against a 30pt gap
    /// between rings, which reads as the ends having been forgotten. Taking
    /// the flare off the number keeps the *visible* breathing room the same on
    /// both, which is what anyone is actually looking at.
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
    static func itemLength(on axis: PanelEdge.Axis) -> CGFloat {
        guard showsPercentages(on: axis) else { return ringDiameter }
        return axis == .vertical ? itemHeight : max(ringDiameter, percentTextWidth)
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
    static func thickness(on axis: PanelEdge.Axis) -> CGFloat {
        guard axis == .horizontal, showsPercentages(on: .horizontal) else { return width }
        return itemHeight + horizontalPadding * 2
    }

    /// Rail length for a given number of providers: the padding at each end +
    /// the items + the gaps between them. Providers can be switched off in
    /// settings, so this is not a constant.
    static func length(for itemCount: Int, on axis: PanelEdge.Axis, docked: Bool = true) -> CGFloat {
        let count = CGFloat(max(itemCount, 1))
        return endPadding(docked: docked) * 2 + itemLength(on: axis) * count + itemSpacing * (count - 1)
    }

    /// The rail's full size, laid the way `edge` lays it.
    static func size(for itemCount: Int, on axis: PanelEdge.Axis, docked: Bool = true) -> CGSize {
        let along = length(for: itemCount, on: axis, docked: docked)
        let across = thickness(on: axis)
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
    static func ringCentreAcross(on axis: PanelEdge.Axis) -> CGFloat {
        let item = axis == .vertical
            ? ringDiameter
            : (showsPercentages(on: axis) ? itemHeight : ringDiameter)
        let lead = axis == .horizontal ? ringOffsetInItem(on: axis) : 0
        return (thickness(on: axis) - item) / 2 + lead + ringDiameter / 2
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
        let intoItem = axis == .vertical
            ? ringOffsetInItem(on: axis) + ringDiameter / 2
            : itemLength(on: axis) / 2
        return endPadding(docked: docked) + intoItem
    }
    static func ringStep(on axis: PanelEdge.Axis) -> CGFloat {
        itemLength(on: axis) + itemSpacing
    }

    /// Rail length with every provider switched on, which is what the panel
    /// has to leave room for. Measured docked, which is the longer of the two —
    /// the window never needs to shrink, only the rail drawn inside it.
    static func maximumLength(on axis: PanelEdge.Axis) -> CGFloat {
        length(for: PanelMetrics.railCapacity, on: axis, docked: true)
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

    /// The tallest the rail ever gets. The panel window is kept at this height
    /// whatever is switched on, so turning a provider off never has to resize
    /// the window — the rail simply draws shorter inside it, and the leftover
    /// space is transparent.
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
    /// How much of the headline window's clock has run, or nil to leave the
    /// outer arc off — either because the setting is off, or because this
    /// window doesn't report enough to work it out.
    var elapsed: Double?

    var id: String { usage.account.id }
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
    let selectedAccount: AccountKey?
    let edge: PanelEdge
    /// Fused to a screen edge, or standing free on the desktop. Only the
    /// silhouette changes: docked it flares into the edge, floating it closes
    /// itself off into a capsule.
    var isDocked: Bool = true
    /// Open, or wound down to the sliver.
    var isExpanded: Bool = true
    /// Colours the sliver when a limit is close enough that hiding the rail
    /// would be hiding something worth seeing.
    var alert: Color?
    /// Liquid Glass instead of flat black.
    var usesGlass: Bool = false
    /// Called as the pointer arrives on a provider's ring. The details flyout
    /// follows the pointer rather than a click, so this is what drives
    /// selection. Leaving is handled by `PanelPointerWatcher`, not here.
    let onEnter: (AccountKey) -> Void
    /// The accessibility/default action for a provider ring. Physical clicks
    /// are resolved by `FloatingPanel`, which owns mouse input ahead of SwiftUI.
    var onRefresh: (AccountKey) -> Void = { _ in }
    /// Called as the pointer arrives on the collapsed sliver.
    var onOpen: () -> Void = {}

    private var railSize: CGSize { DockLayout.size(for: entries.count, on: edge.axis, docked: isDocked) }
    private var currentSize: CGSize {
        isExpanded ? railSize : DockLayout.collapsedSize(on: edge.axis)
    }

    var body: some View {
        // Laid out at full size whatever it is drawing, so nothing around it
        // moves as it opens and closes.
        ZStack(alignment: edge.stackAlignment) {
            berth

            rings
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
        // No drag handle lives here any more. A press only reaches a view
        // inside `NSHostingView` if SwiftUI claims it first, and it would not
        // claim the empty black between the rings: the berth opts out of hit
        // testing and nothing else covers those points, so the panel could be
        // dragged by its rings and nowhere else. Laying a shape over the handle
        // to claim them swallowed the press instead of passing it down, and
        // then nothing could be dragged at all.
        //
        // The window takes its own mouse events instead — see `FloatingPanel`
        // in FloatingPanelController.swift — which happens before any of
        // SwiftUI's hit testing and cannot be undone by it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localized("Provider usage selector"))
    }

    private var berth: some View {
        let shape = DockBerthShape(edge: edge, isDocked: isDocked, openness: isExpanded ? 1 : 0)

        return PanelSurface(
            shape: shape,
            usesGlass: usesGlass,
            // Only the sliver carries the alert colour: expanded, the rings
            // already say which limit is where.
            tint: isExpanded ? nil : alert
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
        let stack = edge.isVertical
            ? AnyLayout(VStackLayout(spacing: DockLayout.itemSpacing))
            : AnyLayout(HStackLayout(spacing: DockLayout.itemSpacing))

        return stack {
            ForEach(entries) { entry in
                UsageDockItem(
                    entry: entry,
                    isSelected: selectedAccount == entry.usage.account,
                    isInteractive: isExpanded,
                    showsPercentage: DockLayout.showsPercentages(on: edge.axis),
                    onEnter: { onEnter(entry.usage.account) },
                    onRefresh: { onRefresh(entry.usage.account) }
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
                    width: edge.isVertical ? nil : DockLayout.itemLength(on: .horizontal),
                    height: edge.isVertical ? DockLayout.itemLength(on: .vertical) : nil
                )
            }
        }
        // The padding follows the run too: the generous end padding is what
        // the flare needs room inside, and the flare is at the rail's ends
        // whichever way it is lying.
        .padding(edge.isVertical ? .vertical : .horizontal, DockLayout.endPadding(docked: isDocked))
        .padding(edge.isVertical ? .horizontal : .vertical, DockLayout.horizontalPadding)
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
    let onEnter: () -> Void
    let onRefresh: () -> Void

    private var usage: ProviderUsage { entry.usage }
    private var headline: UsageWindow? { entry.headline }

    var body: some View {
        // The label goes above or below on a setting. `ringOffsetInItem` is
        // the same swap expressed as a number, and the hit testing runs on
        // that — the two must not be allowed to disagree.
        VStack(spacing: DockLayout.ringToTextSpacing) {
            if DockLayout.labelLeads { percentLabel }

            ring

            if !DockLayout.labelLeads { percentLabel }
        }
        .contentShape(.rect)
        .background {
            if isInteractive { PointerEntryReporter(onEnter: onEnter) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String.localized("\(usage.provider.displayName) usage"))
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
            chosenTint: entry.tint,
            isSpent: UsageTint.isSpent(headline),
            diameter: DockLayout.ringDiameter,
            lineWidth: DockLayout.ringLineWidth,
            isBusy: entry.isRunning,
            isRefreshing: entry.isRefreshing,
            highlight: isSelected,
            elapsedFraction: entry.elapsed
        )
        .scaleEffect(isSelected ? 1.06 : 1)
    }

    /// An em dash rather than 0% when nothing is known: a zero would read as
    /// "you've used nothing", which is a different claim.
    @ViewBuilder
    private var percentLabel: some View {
        if showsPercentage {
            Text(headline?.percentText ?? "—")
                .font(.system(size: DockLayout.percentFontSize, weight: .medium, design: .rounded))
                // A spent limit colours the figure too. At ring size a fourth
                // hue on the stroke alone would read as the third.
                .foregroundStyle(
                    UsageTint.isSpent(headline)
                        ? Color.pulseExhausted
                        : .primary.opacity(headline == nil ? 0.4 : 1)
                )
                .monospacedDigit()
                // Dimmed with the arc, so the whole ring goes quiet together
                // while its reading is fetched, and returns with it.
                .opacity(entry.isRefreshing ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: entry.isRefreshing)
                // Digits change places rather than cutting, so a figure that
                // actually moved is visibly what moved.
                .contentTransition(.numericText())
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: headline?.percentText)
        }
    }

    private var accessibilityValue: String {
        let reading = headline.map { String.localized("\($0.percentText) used, \($0.name)") }
            ?? String.localized("No reading")
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

    /// Lets the outline itself be interpolated, so the silhouette is redrawn
    /// at every step of the animation instead of one shape being faded into
    /// another.
    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    private var flareHeight: CGFloat { DockLayout.flareHeight * openness }
    private var flareWidth: CGFloat { DockLayout.flareWidth * openness }
    private var cornerRadius: CGFloat {
        DockLayout.collapsedWidth
            + (DockLayout.cornerRadius - DockLayout.collapsedWidth) * openness
    }

    func path(in rect: CGRect) -> Path {
        guard isDocked else { return floating(in: rect) }

        switch edge {
        case .right:
            return facingRight(in: rect)

        case .left:
            return facingRight(in: rect).applying(
                CGAffineTransform(translationX: rect.width, y: 0).scaledBy(x: -1, y: 1)
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
    /// Deliberately circular rather than the squircle used everywhere else.
    /// A squircle eases its curvature into the straight edge either side of
    /// it, and at this width the two corners of an end meet with no straight
    /// edge between them at all — so there is nothing to ease into and the
    /// result reads as a flattened lozenge. Fully round ends are what a
    /// free-standing pill is.
    private func floating(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
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

        // Pulls each fillet's control points off its endpoints. 0.55 is the
        // usual circular-arc approximation; it keeps the sweep full instead
        // of flattening it into a sliver.
        let k: CGFloat = 0.55

        var path = Path()

        // Body's flat top edge, left to right.
        path.move(to: CGPoint(x: r, y: f))
        path.addLine(to: CGPoint(x: w - fw, y: f))

        // Concave fillet sweeping up into the screen edge.
        path.addCurve(
            to: CGPoint(x: w, y: 0),
            control1: CGPoint(x: w - fw * (1 - k), y: f),
            control2: CGPoint(x: w, y: f * k)
        )

        // Flush against the screen for the full height.
        path.addLine(to: CGPoint(x: w, y: h))

        // Mirrored fillet back down into the body's bottom edge.
        path.addCurve(
            to: CGPoint(x: w - fw, y: h - f),
            control1: CGPoint(x: w, y: h - f * k),
            control2: CGPoint(x: w - fw * (1 - k), y: h - f)
        )

        // Body's flat bottom edge, right to left.
        path.addLine(to: CGPoint(x: r, y: h - f))

        // Bottom-left corner: starts directly below the corner's center and
        // ends directly to its left.
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

        path.closeSubpath()
        return path
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
        entries: Provider.allCases.map {
            RailEntry(usage: .unavailable($0, reason: .loading), headline: nil)
        },
        selectedAccount: AccountKey(.claudeCode),
        edge: .right,
        onEnter: { _ in }
    )
    .frame(height: DockLayout.maximumHeight + 80)
    .padding()
    .background(.gray)
}
