# Panel geometry

**The panel window does not change size while a details card opens.** `FloatingPanelController.Layout.size(for:)` is card + pointer + gap + rail (or the top-axis equivalent). The card is an **overlay** on the rail, not a stack sibling. Anything that changes the geometry the rail is laid out in animates the rail sideways even though its screen position never moves.

The window **may** resize when the rail is re-docked onto the **other axis** (side ↔ top). Re-docking happens under the pointer with no card open. That is not a contradiction of the rule above.

History and the two bugs that taught this: [../decisions/panel-frame.md](../decisions/panel-frame.md).

## Overlay and height

- Apply the rail’s vertical offset (`.padding(.top, railTop)`) **after** the card overlay, never before. Padding first anchors the card to the panel top and slices it `railTop` too high. That shipped once; it is invisible while the rail is centred.
- The frame must be tall/wide enough for the **tallest card**, not just the rail (`max(DockLayout.maximum…, DetailCardLayout.maximumHeight)`). A card taller than the window is sliced flat against the edge.
- The rail is centred in the panel (`PanelEdge.railAlignment`). `railTop` / `railLeading` convert rail-relative card positions (may be negative) to panel space. The pointer is panel-relative.
- Turning a provider off shortens the **rail**, not the window (`DockLayout.maximumHeight` still). Measure with `FloatingUsagePanelView.railHeight`, not the window height. `settingsChanged()` re-places when shown accounts change, because `railTop` depends on rail length.

`UsageBubbleShape` is the card **and** its pointer as **one path**, same winding (`sweep` when mirrored). Two views in a stack drift apart when height and pointer target change together. `pointerCenterY` is `animatableData`. Check both edges after any change.

On the card, the window’s name has the top row to itself; spent and reset pair on the line below the bar. Sharing the top line fails when a limit is scoped to a model group.

## Dock, float, displays

`PanelPlacement`: `update(dock:)` changes placement **and** asks the window to move (`onChange` → `placePanel`). `record(...)` only stores; drag uses it because the window already moved. Settings picking a position must not use the store-only path (content mirrored, window stayed, rail stranded).

- Drag anywhere; fuse to a side within `dockDistance` **during** the drag, not on mouse-up.
- Floating positions stay at least that far from both sides.
- Any display; remembered by **UUID**, not `CGDirectDisplayID`. Missing display → main. `didChangeScreenParametersNotification` re-places (not during a drag).
- Clamp each frame to the screen under the **pointer**, not the window’s own screen (otherwise a second monitor can never be reached).
- Store the **rail’s** position, never the window’s. The window is much wider than the rail; which side the rail sits on flips at screen mid.

`PanelPlacement.layout(in:panel:rail:)` is the single source of truth for window frame **and** rail offset inside it. Drag handle and `placePanel` both go through it.

## Axis, not a third special case

`PanelEdge.axis`. Stacks, flare, card unfold, which stored ratio is pinned, sliver side — all axis. Both shapes are drawn **once, facing right**, then transformed (mirror left, quarter-turn top). Rotation, not reflection, preserves winding for `UsageBubbleShape`.

**Top dock is the display’s physical edge, above the menu bar** (`FloatingPanel.topEdge(of:)`, `applyLevel(for:)`). `visibleFrame.maxY` is under the menu bar. Reaching the edge needs placement at `frame.maxY` **and** window level `.statusBar` (`.floating` is below the menu bar). Off the top edge, level returns to `.floating`. A notch stops it (`safeAreaInsets.top`): the rail is wider than either strip beside a notch. Take the lower of `frame.maxY - safeAreaInsets.top` and `visibleFrame.maxY`.

Docking to the top is tested against the **pointer**, not the rail (a vertical rail is almost as tall as the display). After an axis change, measure in the **landing** orientation and drop the grab offset (centre under the pointer). Do **not** infer a turn from rail size: floating drops end padding, so the same rail is shorter off the edge; treating `landingRail != rail` as a turn re-centred and snapped. Re-measure grab to the rail **centre** on that size change so rings do not move.

A floating landing works out its **own** side rather than reading `placement.edge` (that property is a frame behind during a drag).

## Flare, sliver, labels, scale

- `DockLayout.endPadding(docked:)`: floating loses the flare’s worth of padding so *visible* breathing room matches docked. Anything measuring the rail (ring centres, `PanelHitArea.account`) must be told docked vs not.
- Auto-collapse to a 6pt sliver (`AppSettings.autoCollapse`, default on) **only while docked**. Off the edge it stays open. The sliver **is** `DockBerthShape` at `openness` 0 (`animatableData`), not a second view. Layout stays at full rail size so the card’s geometry does not change. Rings keep tracking areas only while expanded (`isInteractive`).
- The sliver takes usage colour past the warning threshold.
- `sideRailShowsPercentages` default on; `topRailShowsPercentages` default off. Width stays `DockLayout.width` either way (flare/corners). Both flags live on `PanelMetrics` and in `.id(...)`.
- Left dock mirrors the panel. Floating silhouette is a true capsule with **circular** ends (squircle ends flatten into a lozenge at this width). Asymmetric chrome must handle both edges **and** both dock states.
- `labelAboveRing` (default off) does not change rail size but **does** move the ring inside the item. `DockLayout.ringOffsetInItem(on:)` is the one number drawing and hit testing share.
- `PanelSize` small/standard/large → `PanelMetrics.scale`. All dock and card measurements read it.

Hit-testing geometry (sliver ⊂ rail, clicks on the circle): [input.md](input.md). Constant-as-budget rules: [../development.md](../development.md).
