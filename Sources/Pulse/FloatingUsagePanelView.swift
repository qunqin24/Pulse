import SwiftUI

struct FloatingUsagePanelView: View {
    let store: UsageStore
    let settings: AppSettings
    /// Where the panel is docked. Shared with `FloatingPanelController`, and
    /// written by the drag handle, so the content mirrors as the panel moves.
    let placement: PanelPlacement

    @State private var selectedProvider: Provider?
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
                    selectedProvider: selectedProvider,
                    edge: placement.edge,
                    isDocked: placement.isDocked,
                    isExpanded: isExpanded,
                    alert: alertTint,
                    usesGlass: settings.usesGlass,
                    onEnter: select,
                    onOpen: show
                )
                .fixedSize()
                .overlay(alignment: placement.edge.cardAlignment) {
                    if let selected = selectedUsage, let index = selectedIndex {
                        UsageDetailCard(
                            usesGlass: settings.usesGlass,
                            usage: selected,
                            edge: placement.edge,
                            pointerCenterY: pointerCenterY(for: index)
                        )
                        .fixedSize()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                                    cardHeight = height
                                }
                            }
                        )
                        .padding(.top, cardTopPadding(for: index))
                        .offset(x: Self.cardInset * placement.edge.cardDirection)
                        .transition(cardReveal(for: index))
                    }
                }
                // Lowers the rail to the height on screen the user dragged it
                // to — **after** the card is hung off it, never before. The
                // card is aligned to the top of whatever it is an overlay on,
                // so padding first anchors it to the top of the *panel*
                // instead of the top of the rail, and every card is drawn
                // `railTop` too high and sliced off against the window's edge.
                .padding(.top, railTop)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedProvider)
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
            // functions, so SwiftUI has nothing to observe for either;
            // rebuild the tree when the language or the size changes.
            .id("\(settings.language.rawValue)-\(settings.panelSize.rawValue)")
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
        Provider.allCases
            .filter(settings.isEnabled)
            .map { provider in
                let usage = store.usage(for: provider)
                return RailEntry(
                    usage: usage,
                    headline: usage.headlineWindow(preferring: settings.pinnedWindow(for: provider)),
                    isRunning: store.isRunning(provider)
                )
            }
    }

    /// The rail's height for what is actually being shown. The panel window
    /// stays at its maximum height regardless, so this is what the card's
    /// placement and the pointer test have to measure against — not the
    /// window.
    private var railHeight: CGFloat { DockLayout.height(for: entries.count) }

    /// Where the rail's top edge sits inside the panel.
    ///
    /// Not centred any more: the panel is taller than the rail and is kept
    /// inside the visible screen so the card always has room, so when the rail
    /// is parked near the top or bottom of the display it has to travel within
    /// the panel for that last stretch. Whoever placed the window worked this
    /// out and left it here.
    private var railTop: CGFloat { placement.railTop }

    private var selectedUsage: ProviderUsage? {
        entries.first { $0.usage.provider == selectedProvider }?.usage
    }

    private var selectedIndex: Int? {
        guard let selectedProvider else { return nil }
        return entries.firstIndex { $0.usage.provider == selectedProvider }
    }

    /// Vertical center of a ring in the dock rail, in the outer `HStack`'s
    /// top-aligned coordinate space (which the card shares). Centers march
    /// down the rail from `DockLayout.verticalPadding + ringRadius`,
    /// advancing one item height plus one gap each time.
    private func ringCenterY(for index: Int) -> CGFloat {
        DockLayout.verticalPadding
            + CGFloat(index) * (DockLayout.itemHeight + DockLayout.itemSpacing)
            + DockLayout.ringDiameter / 2
    }

    /// Top padding above the detail card. The card wants to be centered on
    /// the selected ring, but is clamped so it never runs past the panel's
    /// top or bottom edge — which is exactly why the pointer needs its own
    /// placement below rather than riding at the card's center.
    /// Top padding above the card, measured from the rail's top edge.
    ///
    /// Clamped against the *panel*, not the rail: the card can be taller than
    /// the rail, and the panel has room above and below it, so the card is
    /// allowed into that space — going negative to sit higher than the rail —
    /// rather than being pushed past the window's edge and cut off square.
    private func cardTopPadding(for index: Int) -> CGFloat {
        let rawTop = ringCenterY(for: index) - cardHeight / 2
        let highest = -railTop
        let lowest = max(FloatingPanelController.Layout.height - railTop - cardHeight, highest)
        return min(max(rawTop, highest), lowest)
    }

    /// Where the pointer sits inside the card: the ring's center expressed
    /// relative to the card's own top edge, so the tip keeps aiming at the
    /// ring even when the card above has been clamped away from center.
    /// Kept clear of the card's rounded corners by one corner radius.
    private func pointerCenterY(for index: Int) -> CGFloat {
        let raw = ringCenterY(for: index) - cardTopPadding(for: index)
        let inset = DetailCardLayout.cornerRadius + DetailCardLayout.pointerHeight / 2
        let highest = min(inset, cardHeight / 2)
        let lowest = max(cardHeight - inset, highest)
        return min(max(raw, highest), lowest)
    }

    /// How far left of the rail's leading edge the card sits: its own width,
    /// its pointer, and the gap between the pointer's tip and the rail. Same
    /// three pieces `FloatingPanelController.Layout.expandedWidth` adds to the
    /// rail's width, which is why the card lands exactly inside the widened
    /// panel.
    private static let cardInset = DetailCardLayout.width
        + DetailCardLayout.pointerWidth
        + DetailCardLayout.horizontalGap

    /// How the card comes and goes: it grows out of the tip of its own
    /// pointer, the way a system popover unfolds from its arrow.
    ///
    /// Sliding it in from the trailing edge instead — the obvious choice,
    /// since that is the side it appears on — reads as the card leaping out
    /// of the display's edge rather than out of the rail, because the trailing
    /// edge of this panel *is* the edge of the screen. Anchoring the growth on
    /// the pointer tip ties the motion to the ring it belongs to.
    private func cardReveal(for index: Int) -> AnyTransition {
        let anchor = UnitPoint(
            x: placement.edge.isLeft ? 0 : 1,
            y: cardHeight > 0 ? pointerCenterY(for: index) / cardHeight : 0.5
        )

        let direction = placement.edge.cardDirection

        return .modifier(
            active: CardReveal(progress: 0, anchor: anchor, direction: direction),
            identity: CardReveal(progress: 1, anchor: anchor, direction: direction)
        )
    }

    /// Opens a provider's details when the pointer arrives on its ring.
    private func select(_ provider: Provider) {
        guard !placement.isDragging, selectedProvider != provider else { return }
        selectedProvider = provider

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
        let panelWidth = FloatingPanelController.Layout.width

        // Collapsed, only the sliver's own target counts. Testing the rail's
        // full width would hold the panel open across sixty points of empty
        // space it isn't drawing in.
        if !isExpanded {
            return PanelHitArea
                .strip(edge: placement.edge, railHeight: railHeight, railTop: railTop)
                .contains(point)
        }

        let rail = PanelHitArea.rail(edge: placement.edge, railHeight: railHeight, railTop: railTop)
        if rail.contains(point) { return true }

        guard let index = selectedIndex else { return false }

        // Runs the full width of the panel rather than stopping at the card's
        // own edge, so the gap the pointer crosses between the rail and the
        // card is covered too. The vertical slack keeps the boundary from
        // feeling like a trip wire right at the card's edge.
        let cardBand = CGRect(
            x: 0,
            // Card positions are rail-relative; the pointer's is panel-relative.
            y: railTop + cardTopPadding(for: index) - PanelHitArea.slack,
            width: panelWidth,
            height: cardHeight + PanelHitArea.slack * 2
        )
        return cardBand.contains(point)
    }



    /// Closes the details once the pointer is off the panel entirely.
    private func deselect() {
        guard selectedProvider != nil else { return }
        selectedProvider = nil
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

    static func rail(edge: PanelEdge, railHeight: CGFloat, railTop: CGFloat) -> CGRect {
        CGRect(
            x: edge.isLeft ? 0 : FloatingPanelController.Layout.width - DockLayout.width,
            y: railTop,
            width: DockLayout.width,
            height: railHeight
        )
    }

    /// The sliver only ever exists docked — off the edge the rail stays open —
    /// so this is always hard against the screen edge.
    static func strip(edge: PanelEdge, railHeight: CGFloat, railTop: CGFloat) -> CGRect {
        CGRect(
            x: edge.isLeft ? 0 : FloatingPanelController.Layout.width - DockLayout.collapsedHitWidth,
            // Centred on the rail's band, which is where it is drawn.
            y: railTop + (railHeight - DockLayout.collapsedHeight) / 2,
            width: DockLayout.collapsedHitWidth,
            height: DockLayout.collapsedHeight
        )
        // The same forgiveness the card's band gets, so the sliver isn't a
        // trip wire either.
        .insetBy(dx: 0, dy: -slack)
    }

    /// Whether the sliver is reachable without leaving the rail's area, for
    /// every rail height the app can produce.
    static func stripIsContainedInRail() -> Bool {
        for edge in [PanelEdge.left, .right] {
            for count in 1...Provider.allCases.count {
                let height = DockLayout.height(for: count)
                // Every offset the rail can take inside the panel, since it is
                // no longer pinned to the middle of it.
                for top in stride(from: 0.0, through: max(FloatingPanelController.Layout.height - height, 0), by: 1) {
                    guard rail(edge: edge, railHeight: height, railTop: top)
                        .contains(strip(edge: edge, railHeight: height, railTop: top))
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
    /// Which way the card eases out from the rail.
    let direction: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.88 + 0.12 * progress, anchor: anchor)
            .offset(x: (1 - progress) * 10 * direction)
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
