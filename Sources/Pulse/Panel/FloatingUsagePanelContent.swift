// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import SwiftUI

/// Pointer and card state live below the reading builder, so pointer samples
/// reuse the rail entries instead of reconstructing them for every hit test.
struct FloatingUsagePanelContent: View {
    let store: UsageStore
    let settings: AppSettings
    let entries: [RailEntry]
    /// Where the panel is docked. Shared with `FloatingPanelController`, and
    /// written by the drag handle, so the content mirrors as the panel moves.
    let placement: PanelPlacement

    /// Which **ring** the card belongs to, not which account: one account
     /// can now own two of them. `RailSlot.id` is the account's own id for
     /// everything that has not been split, so nothing stored before slots
     /// existed stops matching.
     @State private var selectedSlot: String?
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
    /// The pointer has arrived on a collapsed notch's housing and the rail
    /// opens if it is still there when this finishes (`PanelIntent.notchDwell`).
    @State private var notchDwell: Task<Void, Never>?
    /// Where the pointer is right now, for the end of that wait.
    @State private var pointerProbe = PointerProbe()

    /// This Mac's records for the detailed card, read as its cards open.
    @State private var cardLedgers = CardLedgers()


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
                PanelPointerWatcher(onChange: pointerMoved, probe: pointerProbe)
            )
            .overlay(alignment: .topLeading) {
                if let target = notchTarget {
                    Color.clear
                        .frame(width: target.width, height: target.height)
                        .background(PointerEntryReporter(onEnter: armNotch))
                        .allowsHitTesting(false)
                        .offset(x: target.minX, y: target.minY)
                }
            }
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
                    selectedSlot: selectedSlot,
                    edge: placement.edge,
                    isDocked: placement.isDocked,
                    isExpanded: isExpanded,
                    notchSize: placement.notch?.size,
                    pull: placement.pull,
                    thinning: placement.thinning,
                    parted: placement.parted,
                    tension: placement.tension,
                    fusion: placement.fusion,
                    motion: placement.motion,
                    alert: alertTint,
                    usesGlass: settings.usesGlass,
                    animatesActivity: settings.animatesRingActivity,
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
                            title: selectedTitle ?? "",
                            preferredWindowID: entries[index].headline?.id,
                            edge: placement.edge,
                            showsRemaining: settings.showsRemaining,
                            showsForecast: settings.showsForecast,
                            showsAmounts: selected.account.provider == .qoder && settings.qoderShowsAmounts,
                            resetCredits: selected.account == AccountKey(.codex) ? store.codexResetCredits : nil,
                            isDetailed: settings.showsDetailedCard(for: selected.account),
                            spend: showsSpend(for: selected.account)
                                ? cardLedgers.spend(for: selected.account.provider) : nil,
                            qoderCredits: selected.provider == .qoder ? cardLedgers.qoderCredits : nil,
                            promptCache: showsSpend(for: selected.account)
                                ? cardLedgers.promptCache[selected.account.provider] : nil,
                            usedElsewhere: Set(selected.windows.filter {
                                store.usedElsewhere($0, account: selected.account)
                            }.map(\.id)),
                            pointerCenter: pointerCentre(for: index),
                            maxHeight: placement.cardRoom
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
                        .transition(cardReveal(for: index))
                        .offset(cardOffset)
                    }
                }
                // **Inside the card's animation, before the rail is moved.**
                // `.animation(_:value:)` animates everything animatable in its
                // subtree whenever that value changes — so with the offsets
                // below inside it, closing a card sprang the rail's *position*
                // too. Which is exactly what happens on the first frame of a
                // drag: the card closes, and the rail then chases the pointer
                // on a spring instead of staying under it. The panel appears
                // to slide away from the hand carrying it.
                .animation(.spring(response: 0.28, dampingFraction: 0.84), value: selectedSlot)
                // The berth growing out of the sliver and back. **Here, on the
                // thing that actually changes size** — not on the container
                // outside, which is where it was and which also holds the
                // offsets below. `isExpanded` flips mid-drag, every time: the
                // rail comes off its edge (`isDocked`) or the pointer crosses
                // the content (`isHovered`). Animating from out there took the
                // rail's *position* with it, so the panel drifted away from
                // the pointer on a spring the moment it was carried off an
                // edge. Nothing outside this needs to animate: both states
                // live in a container pinned to the rail's full size.
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
                // Moves the rail to where on screen the user dragged it.
                //
                // **After the card is hung off it, never before.** The card is
                // aligned to the corner of whatever it is an overlay on, so
                // padding first anchors it to the corner of the *panel*
                // instead, and every card is drawn `railTop` too high and
                // sliced off flat against the window's edge. And **outside**
                // the animation above, never inside: this tracks a pointer.
                .padding(.top, railTop)
                .padding(.leading, railLeading)
            }
            // The window's own rects are measured from the rail's length, and
            // that sum is only redone when something asks for it. A reading
            // that splits an account into two rings changes the length with no
            // setting behind it, so it has to ask.
            .onChange(of: entries.count) { placement.railLengthChanged() }
            // The window owns the drag, so this is where the content hears
            // about it: how much of the panel can be grabbed depends on
            // whether the rail is drawn out, which only this side knows.
            .onChange(of: isExpanded, initial: true) { _, expanded in
                placement.isRailExpanded = expanded
                placement.railOpenedAt = expanded ? Date() : nil
                if expanded { cancelNotchDwell() }
            }
            // A card left open under a panel being carried across the screen
            // is noise; the pointer is sweeping the rings, not reading them.
            .onChange(of: placement.isDragging) { _, dragging in
                if dragging { deselect() } else { pointerProbe.reportAgain() }
            }
            // While the menu is up nothing hides (`scheduleHide`); a pointer
            // that stays where it closed the menu must still be asked about.
            .onChange(of: placement.isMenuOpen) { _, open in
                if !open { pointerProbe.reportAgain() }
            }
            // The detailed card's history, read when a card that shows it opens.
            .onChange(of: selectedSlot) {
                if let account = selectedUsage?.account, showsSpend(for: account),
                   let source = account.provider.cardHistory {
                    cardLedgers.read(account.provider, from: source)
                    if source.readsThisMac { cardLedgers.readPromptCache(account.provider) }
                }
                // Qoder's month, from its records: asked as its detailed card
                // opens, never on the refresh timer (issue #88).
                if let account = selectedUsage?.account, account.provider == .qoder,
                   settings.showsDetailedCard(for: account),
                   let cookie = APIKeyStore.key(for: .qoder) {
                    cardLedgers.readQoderCredits(cookie: cookie, site: settings.qoderSite)
                }
            }
            .onChange(of: isNotchHeld) { _, held in
                if !held && placement.notch != nil { pointerMoved(pointerPoint) }
            }
            .onDisappear {
                hideAfterDelay?.cancel()
                hideAfterDelay = nil
                cancelNotchDwell()
            }
            // Pinned dark on both surfaces, and pinned through the
            // *environment* rather than `preferredColorScheme` — the latter is
            // a window-wide preference, not a view-level override, so it can't
            // express "this subtree is dark".
            //
            // Under glass too, now that the glass is really clear (see
            // `FloatingPanel`'s active-appearance override). Clear glass takes
            // on whatever is behind it — white over a white page, black over a
            // terminal — so no single text colour survives on it alone; white
            // over `PanelGlass.dim` does, which is Apple's own answer for the clear
            // variant. Following the system scheme instead left dark text
            // vanishing over dark windows.
            //
            // The light panel (#74) is the one exception, and only on the
            // solid surface: `panelScheme`.
            // On glass the text follows the Transparency slider from white
            // to black (`PanelGlass.ink`), and past `schemeTurns` the scheme
            // follows it. Always an `AnyShapeStyle`, so switching it never
            // changes the tree's identity.
            .foregroundStyle(panelInk)
            .environment(\.colorScheme, panelScheme)
            .environment(\.glassTransparency, settings.glassTransparency)
            // Where red begins, for every ring, bar and figure below here at
            // once. Read off `settings` in one place so they cannot disagree.
            .environment(\.usageWarningThreshold, settings.warningThreshold.fraction)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String.localized("Pulse floating usage panel"))
            // Strings and layout constants are both read through plain
            // functions, so SwiftUI has nothing to observe for either; rebuild
            // the tree when the language, the size, or the top rail's labels
            // change. The last one is easy to forget and changes the rail's
            // *thickness*, so leaving it out draws the rings at one size in a
            // berth built for the other.
            .id("\(settings.language.rawValue)-\(settings.panelSize.rawValue)-\(settings.topRailShowsPercentages)-\(settings.sideRailShowsPercentages)-\(settings.railSpacing.rawValue)-\(settings.labelAboveRing)-\(settings.freeAcrossFiguresBeside)-\(settings.showsWindowClock)-\(settings.showsForecast)-\(settings.detailedCards.isEmpty)-\(settings.usesRoundEnds)-\(settings.usageBarStyle.rawValue)-\(settings.moneyIdentity)")
    }

    /// Light only for the solid surface, notch included; dark under glass,
    /// for the reasons on `AppSettings.usesLightPanel`. `PanelSurface`
    /// reads its fill off this, and the usage colours deepen with it, so the
    /// surface and everything drawn on it change together.
    private var panelScheme: ColorScheme {
        if settings.usesGlass { return PanelGlass.scheme(transparency: settings.glassTransparency) }
        return settings.usesLightPanel ? .light : .dark
    }

    private var panelInk: AnyShapeStyle {
        guard settings.usesGlass, let ink = PanelGlass.ink(transparency: settings.glassTransparency) else {
            return AnyShapeStyle(.primary)
        }
        return AnyShapeStyle(ink)
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
        !settings.autoCollapse || !placement.isDocked || isHovered || isNotchHeld
    }

    private var isNotchHeld: Bool {
        placement.notch != nil && (placement.isPressed || placement.isDragging || placement.isMenuOpen)
    }

    /// The hardware target in the watcher's flipped, panel-local coordinates.
    private var notchTarget: CGRect? {
        placement.notch.map {
            PanelIntent.notchHousing(
                rail: CGRect(x: railLeading, y: railTop, width: railSize.width, height: railSize.height),
                notchSize: $0.size
            )
        }
    }

    /// The colour of the sliver when a limit is close enough that hiding the
    /// rail would be hiding something worth seeing.
    ///
    /// `dockShowsAlertColor` off means never: some rails stay past the
    /// threshold for as long as they are watched, and a permanently coloured
    /// line welded to the screen edge is worse than the thing it is warning
    /// about.
    private var alertTint: Color? {
        guard settings.dockShowsAlertColor else { return nil }
        let worst = entries.compactMap(\.headline).max { $0.usedFraction < $1.usedFraction }
        guard let worst,
              worst.isExhausted || worst.usedFraction >= settings.warningThreshold.fraction
        else { return nil }
        return worst.tint(warningAt: settings.warningThreshold.fraction)
    }

    /// The rail's size for what is actually being shown. The panel window
    /// stays at its maximum regardless, so this is what the card's placement
    /// and the pointer test have to measure against — not the window.
    private var railSize: CGSize { DockLayout.size(for: entries.count, on: placement.edge.axis, docked: placement.isDocked) }

    /// Which way the rail runs, which is the axis the card slides along to
    /// stay level with the ring it belongs to.
    private var alongEdge: Edge.Set { placement.edge.isVertical ? .top : .leading }

    /// Use the granted window geometry for both placement and pointer bands.
    /// The default is only needed before the controller's first placement.
    private var panelSize: CGSize {
        placement.panelSize ?? FloatingPanelController.Layout.size(
            for: placement.edge, notchSize: placement.notch?.size, docked: placement.isDocked
        )
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

    /// Whether the card shows this account's recent usage: its detailed card,
    /// for a provider with a history (`cardHistory`), on the first account —
    /// the one the records belong to. This Mac's records need Token spend on;
    /// a provider's own statistics are asked as its settings pane asks them.
    private func showsSpend(for account: AccountKey) -> Bool {
        guard settings.showsDetailedCard(for: account), account.isPrimary,
              let source = account.provider.cardHistory
        else { return false }
        return !source.readsThisMac || settings.readsTokenSpend
    }

    private var selectedUsage: ProviderUsage? {
        entries.first { $0.id == selectedSlot }?.usage
    }

    /// The card's heading. A split account's rings each name their group, so
    /// two cards of one provider are told apart.
    private var selectedTitle: String? {
        entries.first { $0.id == selectedSlot }?.title
    }

    private var selectedIndex: Int? {
        guard let selectedSlot else { return nil }
        return entries.firstIndex { $0.id == selectedSlot }
    }

    /// Where a ring's centre sits **along** the rail, in the coordinate space
    /// the rail and the card share. Centres march from the rail's first-ring
    /// offset, advancing one item plus one gap each time.
    private func ringCentre(for index: Int) -> CGFloat {
        DockLayout.firstRingAlong(docked: placement.isDocked, on: placement.edge.axis)
            + CGFloat(index) * DockLayout.ringStep(on: placement.edge.axis, docked: placement.isDocked)
    }

    /// The card's own extent along that same axis: its height beside the rail,
    /// its width below it.
    private var cardAlong: CGFloat {
        placement.edge.isVertical ? cardHeight : DetailCardLayout.width
    }

    /// Clamp in the visible part of the actual panel, retaining its origin
    /// when the window extends above or beside the owning display.
    private func cardAnchor(for index: Int) -> DetailCardAnchor {
        let bounds = placement.cardPlacementBounds ?? CGRect(origin: .zero, size: panelSize)
        return DetailCardAnchor(
            ring: railAlong + ringCentre(for: index), length: cardAlong,
            lowerBound: placement.edge.isVertical ? bounds.minY : bounds.minX,
            upperBound: placement.edge.isVertical ? bounds.maxY : bounds.maxX,
            panelLength: placement.edge.isVertical ? panelSize.height : panelSize.width
        )
    }

    /// The overlay starts in the rail's coordinates, so convert back once.
    private func cardPadding(for index: Int) -> CGFloat {
        cardAnchor(for: index).origin - railAlong
    }

    /// The pointer, in the panel's own coordinates. See `pointerMoved`.
    @State private var pointerPoint: CGPoint?

    /// Only the base avoids the corners; the tip stays aligned with the ring.
    private func pointerCentre(for index: Int) -> CGFloat {
        cardAnchor(for: index).pointer
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
            let bottom = placement.notch.map {
                PanelHitArea.notchSurface(rail: CGRect(origin: .zero, size: railSize), notchSize: $0.size).maxY
            } ?? railSize.height
            // Above a free rail in the lower half: the card is bottom-aligned
            // to the rail (`cardAlignment`), so it is lifted by the same.
            return CGSize(width: 0, height: (bottom + DetailCardLayout.horizontalGap) * placement.edge.cardDirection)
        }
    }

    /// How the card comes and goes: it grows out of the side the rail is on,
    /// the way a system popover unfolds from its arrow.
    ///
    /// Sliding it in from the trailing edge instead — the obvious choice,
    /// since that is the side it appears on — reads as the card leaping out
    /// of the display's edge rather than out of the rail, because the trailing
    /// edge of this panel *is* the edge of the screen. Anchoring the growth on
    /// the rail's side ties the motion to the ring it belongs to.
    ///
    /// **The anchor is in the padded box's space, not the card's.** A
    /// transition applies to the whole view that is inserted or removed —
    /// where `.transition` sits in the modifier chain does not change that —
    /// and the view removed here is the card *plus* the gap that holds it
    /// beside its ring. Scaling that box about its own centre therefore drags
    /// the card along the rail by a fraction of the gap: measured at 28 points
    /// for a gap of 466, and nothing at all for the first ring, whose gap is
    /// negative. Which is exactly what "every card but the first slides up"
    /// looks like.
    ///
    /// So the along-axis anchor is the card's own centre expressed in that
    /// box's unit space. The scale then pivots on the card wherever the gap
    /// has put it, and the box does not move.
    private func cardReveal(for index: Int) -> AnyTransition {
        let gap = cardPadding(for: index)
        let box = gap + cardAlong
        let along = box > 0 ? min(max((gap + cardAlong / 2) / box, 0), 1) : 0.5
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
    ///
    /// An enter that arrives after the pointer has gone again — queued
    /// behind a busy main thread — opens nothing: the pointer is read
    /// **now**. Refusing to open closes nothing, so this cannot start the
    /// open/close loop the enter-only rule prevents. A card that does open
    /// asks the sampler for a fresh report (`PointerProbe.reportAgain`), so a
    /// pointer that leaves before the next sample still closes it.
    private func select(_ entry: RailEntry) {
        guard !placement.isDragging, selectedSlot != entry.id else { return }
        guard let point = pointerProbe.current(), isOverContent(point) else { return }
        selectedSlot = entry.id
        pointerProbe.reportAgain()

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
        // The same late enter can draw the rail out after the pointer left.
        pointerProbe.reportAgain()
    }

    /// The pointer arrived on a collapsed notch's housing: open if it is
    /// still there once `PanelIntent.notchDwell` has passed.
    ///
    /// Armed by the housing's tracking area and by the sampler alike, so a
    /// pointer that was already there when the area was installed still
    /// counts. Checked against the pointer **now** (`pointerProbe`), not the
    /// last sample, or a pointer that crossed and left would still read as
    /// inside. A pointer that is gone simply leaves the rail as it was:
    /// nothing here ever closes anything, so it cannot start the open/close
    /// loop the enter-only rule exists to prevent.
    private func armNotch() {
        guard placement.notch != nil, !isExpanded, notchDwell == nil else { return }
        notchDwell = Task { @MainActor in
            try? await Task.sleep(for: PanelIntent.notchDwell)
            guard !Task.isCancelled else { return }
            notchDwell = nil
            guard let point = pointerProbe.current(), notchTarget?.contains(point) == true else { return }
            show()
        }
    }

    private func cancelNotchDwell() {
        notchDwell?.cancel()
        notchDwell = nil
    }

    /// Closes the details, and eventually the rail itself, once the pointer is
    /// no longer on either.
    private func pointerMoved(_ point: CGPoint?) {
        // Kept whatever it is over: a mark whose eyes follow the pointer
        // should follow it across the gaps between rings too. `nil` is the
        // pointer leaving the panel altogether.
        if pointerPoint != point { pointerPoint = point }

        // Collapsed at a notch, the housing is not content yet: the pointer
        // being there only starts the wait (`armNotch`), and leaving it
        // calls the wait off.
        if placement.notch != nil, !isExpanded {
            if let point, notchTarget?.contains(point) == true { armNotch() } else { cancelNotchDwell() }
        }

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
            // while it is being carried across the screen. Nor while the
            // panel's own menu is up, for the same reason — the pointer is on
            // the menu, which is not the panel. Both re-arm: `hideAfterDelay`
            // is already nil here, and the end of either asks the sampler to
            // report again, since a pointer that has not moved is otherwise
            // never reported twice.
            guard !placement.isDragging, !placement.isMenuOpen, !isNotchHeld else { return }
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
            if placement.notch != nil { return false }
            return PanelHitArea
                .strip(edge: edge, railSize: railSize, railTop: railTop, railLeading: railLeading)
                .contains(point)
        }

        // Open, the housing holds the rail as the rest of its surface does.
        if notchTarget?.contains(point) == true { return true }
        let rail = PanelHitArea.rail(edge: edge, railSize: railSize, railTop: railTop, railLeading: railLeading)
        if let notch = placement.notch {
            let surface = PanelHitArea.notchSurface(rail: rail, notchSize: notch.size)
            if NotchBerthShape(notchSize: notch.size)
                .path(in: surface.insetBy(dx: -DockLayout.flareWidth, dy: 0)).contains(point) { return true }
        } else if rail.contains(point) {
            // Not at a notch: there the rail's ends reach past the drawn
            // surface (`notchSurface`), and empty air must not hold it open.
            return true
        }

        guard let index = selectedIndex else { return false }

        // Runs the full extent of the panel across the card rather than
        // stopping at the card's own edge, so the gap the pointer crosses
        // between the rail and the card is covered too. The slack along it
        // keeps the boundary from feeling like a trip wire at the card's edge.
        let panel = panelSize
        let start = railAlong + cardPadding(for: index) - PanelHitArea.slack
        let length = cardAlong + PanelHitArea.slack * 2

        let band = edge.isVertical
            ? CGRect(x: 0, y: start, width: panel.width, height: length)
            : CGRect(x: start, y: 0, width: length, height: panel.height)
        return band.contains(point)
    }

    /// Closes the details once the pointer is off the panel entirely.
    private func deselect() {
        guard selectedSlot != nil else { return }
        selectedSlot = nil
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
/// fixed for twice, in a new costume. `stripIsContainedInRail()` asserts the
/// containment for every rail length and every edge, and is run on every debug
/// launch from `FloatingPanelController`.
enum PanelHitArea {
    /// Forgiveness around the edges before the pointer counts as gone.
    ///
    /// Lives here rather than on the view because the view is `@MainActor`
    /// (every SwiftUI `View` is) while these are plain geometry called from
    /// wherever — reaching across that boundary is a warning under Swift 5's
    /// rules and an error under Swift 6's, which is how it broke in Xcode
    /// while `swift build` stayed happy.
    static let slack: CGFloat = 8

    /// The surface extends up to the physical screen top and is at least as
    /// wide as the housing, even when the rail only has one ring.
    ///
    /// No padding is added under the rail. The housing above the rings is the
    /// screen's own bezel, not room this panel chose, and matching it would
    /// mean 38pt of black under a 36pt ring: the rail keeps the symmetric
    /// padding it has everywhere else and the housing simply sits on top.
    ///
    /// The body alone — `NotchBerthShape` sweeps `DockLayout.flareWidth`
    /// further out at the screen edge, and the grab area deliberately does not
    /// follow it there.
    ///
    /// **As long as the free rail, not the docked one.** A docked rail's ends
    /// carry the room its own flares sweep into (`DockLayout.endPadding`), and
    /// the notch's fillets are drawn *outside* this body, so taking the
    /// docked length as well spent that room twice: a notch rail visibly
    /// wider than the same rings standing free.
    static func notchSurface(rail: CGRect, notchSize: CGSize) -> CGRect {
        let flareRoom = DockLayout.endPadding(docked: true) - DockLayout.endPadding(docked: false)
        let width = max(rail.width - flareRoom * 2, notchSize.width)
        return CGRect(x: rail.midX - width / 2, y: rail.minY - notchSize.height,
                      width: width, height: rail.height + notchSize.height)
    }

    /// The rail's rectangle inside the panel, in the panel's top-left space.
    static func rail(edge: PanelEdge, railSize: CGSize, railTop: CGFloat, railLeading: CGFloat) -> CGRect {
        let panel = FloatingPanelController.Layout.size(for: edge)
        let x: CGFloat = switch edge {
        case .left: 0
        case .top, .bottom: railLeading
        case .right: panel.width - railSize.width
        }

        return CGRect(x: x, y: railTop, width: railSize.width, height: railSize.height)
    }

    /// The provider ring under a point in the panel's top-left coordinate
    /// space. Only the circle is clickable: the label and the empty berth keep
    /// their existing meaning as drag surface.
    static func slot(
        at point: CGPoint,
        edge: PanelEdge,
        slots: [RailSlot],
        railTop: CGFloat,
        railLeading: CGFloat,
        docked: Bool
    ) -> RailSlot? {
        let size = DockLayout.size(for: slots.count, on: edge.axis, docked: docked)
        let rail = rail(edge: edge, railSize: size, railTop: railTop, railLeading: railLeading)
        guard rail.contains(point) else { return nil }

        // Includes the selected ring's 1.06 scale and a small amount of pointer
        // forgiveness without reaching the percentage label beneath it.
        let radius = DockLayout.ringDiameter / 2 * 1.08
        let across = DockLayout.ringCentreAcross(on: edge.axis, docked: docked)

        for (index, slot) in slots.enumerated() {
            let along = DockLayout.firstRingAlong(docked: docked, on: edge.axis)
                + CGFloat(index) * DockLayout.ringStep(on: edge.axis, docked: docked)
            let centre = edge.isVertical
                ? CGPoint(x: rail.minX + across, y: rail.minY + along)
                : CGPoint(x: rail.minX + along, y: rail.minY + across)

            let dx = point.x - centre.x
            let dy = point.y - centre.y
            if dx * dx + dy * dy <= radius * radius { return slot }
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
        // Docked to the bottom: the sliver lies along the screen's bottom
        // edge, the rail's own lower edge.
        case .bottom:
            return CGRect(x: rail.midX - hit.width / 2, y: rail.maxY - hit.height, width: hit.width, height: hit.height)
                .insetBy(dx: -slack, dy: 0)
        }
    }

    /// Whether the sliver is reachable without leaving the rail's area, for
    /// every rail length the app can produce.
    ///
    /// Measured against the metrics currently in force — panel size, ring
    /// spacing and both label flags all change the rail, and all of them can
    /// change while the app runs, so the assertion is worth its cost on every
    /// launch rather than once against one arbitrary combination.
    ///
    /// The bound is the rail's **capacity**, not the number of providers: the
    /// rail is keyed by account now, and a second Codex login makes it longer
    /// than `Provider.allCases` ever describes.
    static func stripIsContainedInRail() -> Bool {
        for edge in [PanelEdge.left, .right, .top] {
            for count in 1...max(PanelMetrics.railCapacity, 1) {
                // Docked is the only state the sliver exists in — off the edge
                // the rail stays open — but it is measured here in both so a
                // change to the floating length cannot quietly break it.
                let size = DockLayout.size(for: count, on: edge.axis, docked: true)
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
