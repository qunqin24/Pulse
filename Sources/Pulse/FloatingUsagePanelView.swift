import SwiftUI

struct FloatingUsagePanelView: View {
    let store: UsageStore
    let settings: AppSettings
    /// Where the panel is docked. Shared with `FloatingPanelController`, and
    /// written by the drag handle, so the content mirrors as the panel moves.
    let placement: PanelPlacement

    @State private var selectedAccount: AccountKey?
    /// The card's real laid-out height. Providers report different numbers of
    /// limits, so the card's height isn't knowable up front — and both the
    /// card's placement and the pointer's aim depend on it.
    @State private var cardHeight: CGFloat = DetailCardLayout.estimatedHeight
    /// Whether the pointer is on the panel. The rail is drawn out only while
    /// it is; the rest of the time a sliver stands in for it.
    @State private var isHovered = false
    /// A moment's grace before hiding, so clipping a corner of the panel on
    /// the way somewhere else doesn't make it flinch.
    @State private var hideAfterDelay: Task<Void, Never>?
    /// What the system is set to, so glass can follow it instead of being
    /// pinned to the panel's own dark.
    @Environment(\.colorScheme) private var colorScheme


    var body: some View {
        // The rail is pinned to the trailing edge of a spacer that fills the
        // panel, as an overlay rather than a stack child: overlays keep their
        // ideal size instead of being squeezed by the space available, so the
        // rail stays welded to the screen edge no matter what.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                // The only thing that closes the card: the pointer moving off
                // the content. Tracking a position rather than enter/exit
                // events means crossing from a ring to the card, or between
                // two rings, never interrupts anything.
                PanelPointerWatcher(onChange: pointerMoved)
            )
            .overlay(alignment: placement.edge.railAlignment) {
                // The card hangs off the rail as an overlay rather than
                // sitting beside it in a stack. In a stack, the container has
                // to grow from the rail's width to the full expanded width
                // when the card appears, and that growth drags the rail along
                // with it — the rail visibly jumps aside every time the card
                // opens. As an overlay the card takes no part in the rail's
                // layout, so the rail cannot be moved by it at all.
                // Both states live in a container pinned to the rail's full
                // size, so collapsing changes nothing about the geometry the
                // card is positioned in — only what is drawn inside it. The
                // alternative, letting the container shrink to the sliver,
                // moves the coordinate space the card is measured against and
                // brings back the sideways lurch this file has already been
                // fixed for twice.
                // One view in both states, not two swapped by a transition:
                // the berth's size and outline are animated, so it visibly
                // grows out of the sliver and back rather than one thing
                // vanishing while another appears in its place.
                UsageDockView(
                    entries: entries,
                    selectedAccount: selectedAccount,
                    edge: placement.edge,
                    isDocked: placement.isDocked,
                    isExpanded: isExpanded,
                    alert: alertTint,
                    usesGlass: settings.usesGlass,
                    onEnter: select,
                    onRefresh: store.refresh,
                    onOpen: show
                )
                .fixedSize()
                .overlay(alignment: placement.edge.cardAlignment) {
                    if let selected = selectedUsage, let index = selectedIndex {
                        UsageDetailCard(
                            usesGlass: settings.usesGlass,
                            usage: selected,
                            title: settings.label(for: selected.account),
                            edge: placement.edge,
                            pointerCenter: pointerCentre(for: index)
                        )
                        .fixedSize()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                                    cardHeight = height
                                }
                            }
                        )
                        .padding(alongEdge, cardPadding(for: index))
                        .offset(cardOffset)
                        .transition(cardReveal(for: index))
                    }
                }
                // Moves the rail to where on screen the user dragged it —
                // **after** the card is hung off it, never before. The card is
                // aligned to the corner of whatever it is an overlay on, so
                // padding first anchors it to the corner of the *panel*
                // instead, and every card is drawn `railTop` too high and
                // sliced off flat against the window's edge.
                .padding(.top, railTop)
                .padding(.leading, railLeading)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedAccount)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
            // The window owns the drag, so this is where the content hears
            // about it: how much of the panel can be grabbed depends on
            // whether the rail is drawn out, which only this side knows.
            .onChange(of: isExpanded, initial: true) { _, expanded in
                placement.isRailExpanded = expanded
            }
            // A card left open under a panel being carried across the screen
            // is noise; the pointer is sweeping the rings, not reading them.
            .onChange(of: placement.isDragging) { _, dragging in
                if dragging { deselect() }
            }
            // Pinned dark only on the black panel, and pinned through the
            // *environment* rather than `preferredColorScheme` — the latter is
            // a window-wide preference, not a view-level override, so it can't
            // express "this subtree is dark".
            //
            // Liquid Glass switches between light and dark itself to stay
            // legible against whatever is behind it, so under glass nothing is
            // pinned: the standard `.primary` colours the panel is drawn in
            // follow the appearance the material settled on. Forcing dark is
            // exactly what leaves white text sitting on bright glass.
            .environment(\.colorScheme, settings.usesGlass ? colorScheme : .dark)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String.localized("Pulse floating usage panel"))
            // Strings and layout constants are both read through plain
            // functions, so SwiftUI has nothing to observe for either; rebuild
            // the tree when the language, the size, or the top rail's labels
            // change. The last one is easy to forget and changes the rail's
            // *thickness*, so leaving it out draws the rings at one size in a
            // berth built for the other.
            .id("\(settings.language.rawValue)-\(settings.panelSize.rawValue)-\(settings.topRailShowsPercentages)")
    }

    /// Whether the rail is drawn out in full.
    ///
    /// Hiding is only for the docked panel. Against the side of the screen the
    /// rail is in the way of whatever is behind it and getting it back is a
    /// flick of the pointer at an edge that cannot be missed; out on the
    /// desktop it is where the user deliberately put it, and a pill sitting in
    /// the middle of the screen is neither out of the way nor easy to find
    /// again. So pulling it off the edge leaves it open.
    ///
    /// Derived rather than stored, so both this and switching auto-hide off in
    /// settings take effect at once rather than at the pointer's next visit.
    private var isExpanded: Bool {
        !settings.autoCollapse || !placement.isDocked || isHovered
    }

    /// The colour of the sliver when a limit is close enough that hiding the
    /// rail would be hiding something worth seeing.
    private var alertTint: Color? {
        let worst = entries.compactMap(\.headline).max { $0.usedFraction < $1.usedFraction }
        guard let worst,
              worst.isExhausted || worst.usedFraction >= UsageTint.warningThreshold
        else { return nil }
        return worst.tint
    }

    /// Only the providers switched on in settings, so the rail shrinks when
    /// one is turned off.
    private var entries: [RailEntry] {
        settings.shownAccounts.map { account in
            let usage = store.usage(for: account)
            return RailEntry(
                usage: usage,
                headline: usage.headlineWindow(preferring: settings.pinnedWindow(for: account)),
                // Activity is per *provider*: a running CLI belongs to whichever
                // account it happens to be signed in to, and the transcripts do
                // not say which. Every account of that provider shows the mark.
                isRunning: store.isRunning(account.provider),
                isRefreshing: store.isRefreshing(account)
            )
        }
    }

    /// The rail's size for what is actually being shown. The panel window
    /// stays at its maximum regardless, so this is what the card's placement
    /// and the pointer test have to measure against — not the window.
    private var railSize: CGSize { DockLayout.size(for: entries.count, on: placement.edge.axis) }

    /// Which way the rail runs, which is the axis the card slides along to
    /// stay level with the ring it belongs to.
    private var alongEdge: Edge.Set { placement.edge.isVertical ? .top : .leading }

    /// The panel's own extent along that axis, which is what the card is
    /// clamped inside.
    private var panelAlong: CGFloat {
        let panel = FloatingPanelController.Layout.size(for: placement.edge)
        return placement.edge.isVertical ? panel.height : panel.width
    }

    /// How far the rail is offset along its own run inside the panel.
    private var railAlong: CGFloat { placement.edge.isVertical ? railTop : railLeading }

    /// Where the rail's top edge sits inside the panel.
    ///
    /// Not centred any more: the panel is taller than the rail and is kept
    /// inside the visible screen so the card always has room, so when the rail
    /// is parked near the top or bottom of the display it has to travel within
    /// the panel for that last stretch. Whoever placed the window worked this
    /// out and left it here.
    private var railTop: CGFloat { placement.railTop }

    /// The same across the panel's other axis, which only a rail lying along
    /// the top ever uses.
    private var railLeading: CGFloat { placement.railLeading }

    private var selectedUsage: ProviderUsage? {
        entries.first { $0.usage.account == selectedAccount }?.usage
    }

    private var selectedIndex: Int? {
        guard let selectedAccount else { return nil }
        return entries.firstIndex { $0.usage.account == selectedAccount }
    }

    /// Where a ring's centre sits **along** the rail, in the coordinate space
    /// the rail and the card share. Centres march from the rail's first-ring
    /// offset, advancing one item plus one gap each time.
    private func ringCentre(for index: Int) -> CGFloat {
        DockLayout.firstRingAlong
            + CGFloat(index) * DockLayout.ringStep(on: placement.edge.axis)
    }

    /// The card's own extent along that same axis: its height beside the rail,
    /// its width below it.
    private var cardAlong: CGFloat {
        placement.edge.isVertical ? cardHeight : DetailCardLayout.width
    }

    /// How far along the rail the card starts, measured from the rail's own
    /// leading corner.
    ///
    /// Clamped against the *panel*, not the rail: the card can be longer than
    /// the rail, and the panel has room past it at both ends, so the card is
    /// allowed into that space — going negative to start before the rail does
    /// — rather than being pushed past the window's edge and cut off square.
    private func cardPadding(for index: Int) -> CGFloat {
        let raw = ringCentre(for: index) - cardAlong / 2
        let first = -railAlong
        let last = max(panelAlong - railAlong - cardAlong, first)
        return min(max(raw, first), last)
    }

    /// Where the pointer sits inside the card: the ring's centre expressed
    /// relative to the card's own leading corner, so the tip keeps aiming at
    /// the ring even when the card has been clamped away from centre. Kept
    /// clear of the card's rounded corners by one corner radius.
    private func pointerCentre(for index: Int) -> CGFloat {
        let raw = ringCentre(for: index) - cardPadding(for: index)
        let inset = DetailCardLayout.cornerRadius + DetailCardLayout.pointerHeight / 2
        let first = min(inset, cardAlong / 2)
        let last = max(cardAlong - inset, first)
        return min(max(raw, first), last)
    }

    /// How far the card sits clear of the rail: beside it, its own width plus
    /// its pointer plus the gap; below it, the rail's thickness plus the gap,
    /// since the pointer is already inside the card's own frame there.
    ///
    /// Computed, and it has to be: a `static let` is worked out once per
    /// process and never again, so changing the panel's size afterwards left
    /// the card offset by the *old* size's width — at Large that is 61pt short,
    /// which parks the card squarely on top of the rail. Rebuilding the view
    /// does not help; nothing rebuilds a `static let`. Every constant derived
    /// from `PanelMetrics` has to be computed on each read.
    private var cardOffset: CGSize {
        switch placement.edge.axis {
        case .vertical:
            let inset = DetailCardLayout.width
                + DetailCardLayout.pointerWidth
                + DetailCardLayout.horizontalGap
            return CGSize(width: inset * placement.edge.cardDirection, height: 0)
        case .horizontal:
            return CGSize(width: 0, height: railSize.height + DetailCardLayout.horizontalGap)
        }
    }

    /// How the card comes and goes: it grows out of the tip of its own
    /// pointer, the way a system popover unfolds from its arrow.
    ///
    /// Sliding it in from the trailing edge instead — the obvious choice,
    /// since that is the side it appears on — reads as the card leaping out
    /// of the display's edge rather than out of the rail, because the trailing
    /// edge of this panel *is* the edge of the screen. Anchoring the growth on
    /// the pointer tip ties the motion to the ring it belongs to.
    private func cardReveal(for index: Int) -> AnyTransition {
        // The tip of the card's own pointer, in the card's unit space.
        let along = cardAlong > 0 ? pointerCentre(for: index) / cardAlong : 0.5
        let across = placement.edge.cardRevealOrigin
        let anchor = placement.edge.isVertical
            ? UnitPoint(x: across, y: along)
            : UnitPoint(x: along, y: across)

        return .modifier(
            active: CardReveal(progress: 0, anchor: anchor, axis: placement.edge.axis, direction: placement.edge.cardDirection),
            identity: CardReveal(progress: 1, anchor: anchor, axis: placement.edge.axis, direction: placement.edge.cardDirection)
        )
    }

    /// Opens a provider's details when the pointer arrives on its ring.
    private func select(_ account: AccountKey) {
        guard !placement.isDragging, selectedAccount != account else { return }
        selectedAccount = account

        // Opening a card is the clearest sign these numbers are being read,
        // which is what the automatic refresh interval paces itself against.
        store.noteLooked()
    }

    /// Draws the rail out. Only ever called from a tracking area's *enter*,
    /// which is what keeps this from looping: a view appearing under a
    /// stationary pointer can fire a spurious exit, but never a spurious
    /// entry into something that was already under it.
    private func show() {
        hideAfterDelay?.cancel()
        hideAfterDelay = nil
        guard !isHovered else { return }
        isHovered = true
    }

    /// Closes the details, and eventually the rail itself, once the pointer is
    /// no longer on either.
    private func pointerMoved(_ point: CGPoint?) {
        if let point, isOverContent(point) {
            hideAfterDelay?.cancel()
            hideAfterDelay = nil

            // The pointer being on the panel is what "hovered" means, however
            // it got there. The sliver's tracking area cannot be the only way
            // in, because while the panel is floating there *is* no sliver —
            // so dragging a floating panel to a screen edge used to dock it
            // with `isHovered` still false, and it snapped shut in the hand
            // that was holding it.
            //
            // This cannot restart the open/close loop the enter-only rule
            // exists to prevent: hiding happens only when this same test says
            // the pointer is off the panel, so the two can never disagree.
            if !isHovered { isHovered = true }
            return
        }

        deselect()
        scheduleHide()
    }

    private func scheduleHide() {
        guard isHovered, hideAfterDelay == nil else { return }

        hideAfterDelay = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            hideAfterDelay = nil
            // Never mid-drag: the pointer is far from the panel by design
            // while it is being carried across the screen.
            guard !placement.isDragging else { return }
            isHovered = false
        }
    }

    /// Whether a point in the panel is on something the panel actually draws.
    ///
    /// Most of the panel is empty, transparent space — the window is kept at
    /// its full size at all times (see `FloatingPanelController.Layout`), so
    /// simply asking whether the pointer is inside the window would hold the
    /// card open across a large blank area well away from it.
    private func isOverContent(_ point: CGPoint) -> Bool {
        let edge = placement.edge

        // Collapsed, only the sliver's own target counts. Testing the rail's
        // full extent would hold the panel open across sixty points of empty
        // space it isn't drawing in.
        if !isExpanded {
            return PanelHitArea
                .strip(edge: edge, railSize: railSize, railTop: railTop, railLeading: railLeading)
                .contains(point)
        }

        let rail = PanelHitArea.rail(edge: edge, railSize: railSize, railTop: railTop, railLeading: railLeading)
        if rail.contains(point) { return true }

        guard let index = selectedIndex else { return false }

        // Runs the full extent of the panel across the card rather than
        // stopping at the card's own edge, so the gap the pointer crosses
        // between the rail and the card is covered too. The slack along it
        // keeps the boundary from feeling like a trip wire at the card's edge.
        let panel = FloatingPanelController.Layout.size(for: edge)
        let start = railAlong + cardPadding(for: index) - PanelHitArea.slack
        let length = cardAlong + PanelHitArea.slack * 2

        let band = edge.isVertical
            ? CGRect(x: 0, y: start, width: panel.width, height: length)
            : CGRect(x: start, y: 0, width: length, height: panel.height)
        return band.contains(point)
    }

    /// Closes the details once the pointer is off the panel entirely.
    private func deselect() {
        guard selectedAccount != nil else { return }
        selectedAccount = nil
    }
}

/// The two areas the pointer test asks about, kept together because the
/// relationship between them is what makes the show/hide cycle safe.
///
/// **The sliver's target must sit entirely inside the rail's.** Hiding only
/// happens when the pointer is outside the *rail*, so if the sliver could
/// stick out beyond it there would be points that hide the rail and then
/// immediately land on the sliver — whose tracking area shows it again, which
/// hides it again. That is the open/close loop this file has already been
/// fixed for twice, in a new costume. `PanelHitAreaCheck` asserts the
/// containment for every provider count and both edges.
enum PanelHitArea {
    /// Forgiveness around the edges before the pointer counts as gone.
    ///
    /// Lives here rather than on the view because the view is `@MainActor`
    /// (every SwiftUI `View` is) while these are plain geometry called from
    /// wherever — reaching across that boundary is a warning under Swift 5's
    /// rules and an error under Swift 6's, which is how it broke in Xcode
    /// while `swift build` stayed happy.
    static let slack: CGFloat = 8

    /// The rail's rectangle inside the panel, in the panel's top-left space.
    static func rail(edge: PanelEdge, railSize: CGSize, railTop: CGFloat, railLeading: CGFloat) -> CGRect {
        let panel = FloatingPanelController.Layout.size(for: edge)
        let x: CGFloat = switch edge {
        case .left, .top: edge == .top ? railLeading : 0
        case .right: panel.width - railSize.width
        }

        return CGRect(x: x, y: railTop, width: railSize.width, height: railSize.height)
    }

    /// The provider ring under a point in the panel's top-left coordinate
    /// space. Only the circle is clickable: the label and the empty berth keep
    /// their existing meaning as drag surface.
    static func account(
        at point: CGPoint,
        edge: PanelEdge,
        accounts: [AccountKey],
        railTop: CGFloat,
        railLeading: CGFloat
    ) -> AccountKey? {
        let size = DockLayout.size(for: accounts.count, on: edge.axis)
        let rail = rail(edge: edge, railSize: size, railTop: railTop, railLeading: railLeading)
        guard rail.contains(point) else { return nil }

        // Includes the selected ring's 1.06 scale and a small amount of pointer
        // forgiveness without reaching the percentage label beneath it.
        let radius = DockLayout.ringDiameter / 2 * 1.08
        let across = DockLayout.ringCentreAcross(on: edge.axis)

        for (index, account) in accounts.enumerated() {
            let along = DockLayout.firstRingAlong
                + CGFloat(index) * DockLayout.ringStep(on: edge.axis)
            let centre = edge.isVertical
                ? CGPoint(x: rail.minX + across, y: rail.minY + along)
                : CGPoint(x: rail.minX + along, y: rail.minY + across)

            let dx = point.x - centre.x
            let dy = point.y - centre.y
            if dx * dx + dy * dy <= radius * radius { return account }
        }

        return nil
    }

    /// The sliver only ever exists docked — off the edge the rail stays open —
    /// so this is always hard against the screen edge.
    static func strip(edge: PanelEdge, railSize: CGSize, railTop: CGFloat, railLeading: CGFloat) -> CGRect {
        let rail = rail(edge: edge, railSize: railSize, railTop: railTop, railLeading: railLeading)
        let hit = DockLayout.collapsedHitSize(on: edge.axis)

        // Centred along the rail's band, which is where it is drawn, and hard
        // against the screen edge across it. The same forgiveness the card's
        // band gets is added along the run, so the sliver isn't a trip wire.
        switch edge {
        case .left:
            return CGRect(x: rail.minX, y: rail.midY - hit.height / 2, width: hit.width, height: hit.height)
                .insetBy(dx: 0, dy: -slack)
        case .right:
            return CGRect(x: rail.maxX - hit.width, y: rail.midY - hit.height / 2, width: hit.width, height: hit.height)
                .insetBy(dx: 0, dy: -slack)
        case .top:
            return CGRect(x: rail.midX - hit.width / 2, y: rail.minY, width: hit.width, height: hit.height)
                .insetBy(dx: -slack, dy: 0)
        }
    }

    /// Whether the sliver is reachable without leaving the rail's area, for
    /// every rail size the app can produce.
    static func stripIsContainedInRail() -> Bool {
        for edge in [PanelEdge.left, .right, .top] {
            for count in 1...Provider.allCases.count {
                let size = DockLayout.size(for: count, on: edge.axis)
                let panel = FloatingPanelController.Layout.size(for: edge)
                // Every offset the rail can take inside the panel, since it is
                // no longer pinned to the middle of it.
                let travel = edge.isVertical
                    ? max(panel.height - size.height, 0)
                    : max(panel.width - size.width, 0)

                for offset in stride(from: 0.0, through: travel, by: 1) {
                    let top = edge.isVertical ? offset : 0
                    let leading = edge.isVertical ? 0 : offset
                    guard rail(edge: edge, railSize: size, railTop: top, railLeading: leading)
                        .contains(strip(edge: edge, railSize: size, railTop: top, railLeading: leading))
                    else { return false }
                }
            }
        }
        return true
    }
}

/// Drives `FloatingUsagePanelView.cardReveal`. Kept deliberately restrained:
/// the panel is only a few hundred points wide, so a large scale or a long
/// slide reads as flailing rather than as unfolding.
private struct CardReveal: ViewModifier {
    /// 0 while the card is absent, 1 once it is fully present.
    let progress: Double
    let anchor: UnitPoint
    /// Which axis the card unfolds across, and which way along it.
    let axis: PanelEdge.Axis
    let direction: CGFloat

    func body(content: Content) -> some View {
        let slide = (1 - progress) * 10 * direction
        return content
            .scaleEffect(0.88 + 0.12 * progress, anchor: anchor)
            .offset(
                x: axis == .vertical ? slide : 0,
                y: axis == .vertical ? 0 : slide
            )
            .opacity(progress)
    }
}

#Preview("Floating panel") {
    FloatingUsagePanelView(store: UsageStore(settings: AppSettings()), settings: AppSettings(), placement: PanelPlacement())
        .frame(
            width: FloatingPanelController.Layout.width,
            height: FloatingPanelController.Layout.height
        )
        .background(Color.gray.opacity(0.2))
}
