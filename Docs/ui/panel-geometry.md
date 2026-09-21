# Panel geometry

**The panel window does not change size while a details card opens.** `FloatingPanelController.Layout.size(for:)` is card + pointer + gap + rail (or the top-axis equivalent). The card is an **overlay** on the rail, not a stack sibling. Anything that changes the geometry the rail is laid out in animates the rail sideways even though its screen position never moves.

The window **may** resize when the rail is re-docked onto the **other axis** (side ↔ top). Re-docking happens under the pointer with no card open. That is not a contradiction of the rule above.

History and the two bugs that taught this: [../decisions/panel-frame.md](../decisions/panel-frame.md).

## Overlay and height

- Apply the rail’s vertical offset (`.padding(.top, railTop)`) **after** the card overlay, never before. Padding first anchors the card to the panel top and slices it `railTop` too high. That shipped once; it is invisible while the rail is centred.
- The frame must be tall/wide enough for the **tallest card**, not just the rail (`max(DockLayout.maximum…, DetailCardLayout.maximumHeight)`). A card taller than the window is sliced flat against the edge.
- The rail is centred in the panel (`PanelEdge.railAlignment`). `railTop` / `railLeading` convert rail-relative card positions (may be negative) to panel space. The pointer is panel-relative.
- Turning a provider off shortens the **rail**, not the window (`DockLayout.maximumHeight` still). Measure with `FloatingUsagePanelView.railHeight`, not the window height. `settingsChanged()` re-places when shown accounts change, and `PanelPlacement.railLengthChanged()` when a *reading* changes the rail's length — a split account draws one ring until its first answer carries both groups, so the length now moves with no setting behind it. Both land in `placePanel()`; miss one and the window's rects stay measured against a rail that is no longer that long. The frame's **size** is `Layout.size(for: edge)` either way, a function of the edge alone, so neither path can resize the window.

`UsageBubbleShape` is the card **and** its pointer as **one path**, same winding (`sweep` when mirrored). Two views in a stack drift apart when height and pointer target change together. `pointerCenterY` is `animatableData`. Check both edges after any change. With `usesRoundEnds` on, the tail's flanks leave the card **along its edge** (first control point on the edge) and bend out to a ~50° tip, the way the flare leaves the screen edge; off they leave at an angle and crease where they meet the card, which is the shipped tail.

On the card, the window’s name has the top row to itself; spent and reset pair on the line below the bar. Sharing the top line fails when a limit is scoped to a model group.

## Dock, float, displays

`PanelPlacement`: `update(dock:)` changes placement **and** asks the window to move (`onChange` → `placePanel`). `record(...)` only stores; drag uses it because the window already moved. Settings picking a position must not use the store-only path (content mirrored, window stayed, rail stranded).

- Drag anywhere; fuse to a side within `dockDistance` **during** the drag, not on mouse-up.
- Floating positions stay at least that far from both sides.
- Any display; remembered by **UUID**, not `CGDirectDisplayID`. Missing display → main. `didChangeScreenParametersNotification` re-places (not during a drag).
- Clamp each frame to the screen under the **pointer**, not the window’s own screen (otherwise a second monitor can never be reached).
- Store the **rail’s** position, never the window’s. The window is much wider than the rail; which side the rail sits on flips at screen mid.

`PanelPlacement.layout(in:panel:rail:)` is the single source of truth for window frame **and** rail offset inside it. Drag handle and `placePanel` both go through it.

### A frame is not granted until the window is on screen

`placePanel` measures the rail's offset against the frame the window was **granted**, not the one it asked for — that is the lesson `RailOffsetTests` pins, because the panel is taller than a laptop's usable area and `constrainFrameRect` pulls it down.

But a window that has never been ordered in **is not being constrained yet**. `setFrame` stores the request, `frame` reads it back unchanged, and an offset measured there is against a position the window is about to lose. So `show()` places, orders front, and **places again**: the first call puts the window roughly right so it does not appear at the origin and slide into place, the second measures against what it actually got.

Measured on a 1800×1169 display: asked for y=76, granted y=0, so the rail was drawn **76pt too low** from the moment the panel first appeared — and stayed wrong until anything re-placed it, at which point it jumped. Any settings change does that, which is how it was found: switching a provider's display mode appeared to move the whole rail.

Verified by driving a real `FloatingPanelController` and reading `railTop` after `show()` against a re-place; there is no test for it, because pinning it needs a real window on a real screen and that is not a thing to put in `swift test`.

### Follow the active display

`AppSettings.followsActiveDisplay` (off by default) + `ActiveDisplayFollower` + `PanelPlacement.move(toDisplay:)`. Issue [#16](https://github.com/qunqin24/Pulse/issues/16).

- **Active = the display holding the pointer**, and only that. Not the key window, not the frontmost app's frame — an app can be focused on one display while the person works on another, and reading window positions would need Accessibility permission to be wrong more expensively.
- **One panel, moved.** Nothing here creates a second one; the move is a change of `display` alone, both ratios carried across unchanged, so the rail keeps its place *on* a display whatever the two displays' sizes.
- **Sampled on a 0.25s timer**, for the same reason `PanelPointerWatcher` samples: a global mouse-moved monitor stops firing over this app's own windows, and a pointer that crosses and comes to rest emits nothing further. Fires once per crossing, not once per frame. The timer runs only while the panel is visible **and** the setting is on, and each tick bails immediately on one display.
- **Refusal is reported, not swallowed.** `move(toDisplay:)` returns `false` while the panel is held (`isPressed` / `isDragging`, the same rule as `railLengthChanged`), and the follower then keeps that display on offer for the next tick rather than remembering it as handled. Returning to the *same* display is `true` and does nothing — otherwise every tick would re-offer it forever.
- The move is **recorded** like a drag, so switching the setting back off leaves the panel on the display it was last carried to rather than throwing it back across the desk.
- `didChangeScreenParametersNotification` calls `forgetLastDisplay()`: unplugging the monitor the panel was on leaves the pointer where it was, which would otherwise read as "nothing to do" while the panel sits on a fallback screen nobody chose.

## Axis, not a third special case

`PanelEdge.axis`. Stacks, flare, card unfold, which stored ratio is pinned, sliver side — all axis. Both shapes are drawn **once, facing right**, then transformed (mirror left, quarter-turn top). Rotation, not reflection, preserves winding for `UsageBubbleShape`.

**Top dock on a non-notch display is the physical edge, above the menu bar** (`FloatingPanel.topEdge(of:)`, `applyLevel(for:)`). Placement uses `frame.maxY` and window level `.statusBar`; off the top edge the level returns to `.floating`. Its existing flare and sliver are unchanged.

**On a notch display, top docking attaches to the physical housing.** `PanelScreen.notch` reads `safeAreaInsets.top` and the gap between `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, in global screen coordinates. No hardcoded model dimensions or private APIs. The rail centres beneath that rectangle without rewriting the remembered horizontal ratio; other displays still use the remembered position. Missing housing geometry keeps the ordinary top-dock path.

With auto-collapse on, the notch rail draws **nothing** at rest: no sliver, tint, enlarged black housing, or invisible grab target. Entering the hardware rectangle uses the same `PointerEntryReporter` and immediate show path as the ordinary sliver, with the existing 150ms pointer sampler also checking the target; there is no notch-specific dwell timer; leaving uses the existing 320ms grace period. Switching auto-collapse off still keeps it expanded. Dragging, a held press, and the panel menu keep it open. `PanelPointerWatcher` is unchanged; it samples the same window, which now reaches the physical screen top. No second window, global event monitor, or additional permission is needed.

`NotchBerthShape` is the housing continued downwards: continuous rounded bottom corners, and at the screen's top edge the same concave fillet `DockBerthShape` sweeps into an edge anywhere else (`DockLayout.flareWidth` / `flareHeight`, control points at 0.55). Without it the two top corners are square against the top of the screen, which is the one thing the docked rail has never looked like — `NotchGeometryTests` pins it, because losing it fails nothing. Expanded width is the larger of the rail and housing widths, so even a one-ring rail extends the whole housing. Rings start immediately below the housing, in the unchanged rail layout.

**Nothing is added under the rail to answer the housing.** The black above the rings is the screen's own bezel, not room this panel chose, and matching its 38pt would put that much black under a 36pt ring. The rail keeps the symmetric padding it has everywhere else and the housing sits on top: the surface is exactly the housing plus the rail. `PanelHitArea.notchSurface` is that body, and the fillets sweep `flareWidth` further out on each side — the drawing frame allows for it, the grab area deliberately does not follow it there. The card begins after the body. The window budget includes the actual housing height on a notch display, whether open or closed, and the surface's minimum width. Hover and card opening never resize it; changing display geometry may. Non-notch displays use the original window budget. Display changes and dragging refresh the transient notch rectangle through the same placement paths as the rail.

Docking to the top is tested against the **pointer**, not the rail (a vertical rail is almost as tall as the display). After an axis change, measure in the **landing** orientation and drop the grab offset (centre under the pointer). Do **not** infer a turn from rail size: floating drops end padding, so the same rail is shorter off the edge; treating `landingRail != rail` as a turn re-centred and snapped. Re-measure grab to the rail **centre** on that size change so rings do not move.

A floating landing works out its **own** side rather than reading `placement.edge` (that property is a frame behind during a drag).

## Flare, sliver, labels, scale

- `DockLayout.endPadding(docked:)`: floating loses the flare’s worth of padding so *visible* breathing room matches docked. Anything measuring the rail (ring centres, `PanelHitArea.slot`) must be told docked vs not.
- Auto-collapse to a 6pt sliver (`AppSettings.autoCollapse`, default on) **only while docked**, except at a physical notch where the collapsed drawing is empty. Off the edge it stays open. The sliver **is** `DockBerthShape` at `openness` 0 (`animatableData`), not a second view. Layout stays at full rail size so the card’s geometry does not change. Rings keep tracking areas only while expanded (`isInteractive`).
- The sliver takes usage colour past the warning threshold.
- `sideRailShowsPercentages` default on; `topRailShowsPercentages` default off. Width stays `DockLayout.width` either way (flare/corners). Both flags live on `PanelMetrics` and in `.id(...)`.
- Left dock mirrors the panel. Floating silhouette is a true capsule with **circular** ends (squircle ends flatten into a lozenge at this width). Asymmetric chrome must handle both edges **and** both dock states.
- **`AppSettings.usesRoundEnds` (default off) picks between two sets of curves for the rail's ends and the card's tail.** One switch over all of it: split up, a round end could sit on the softened style's written 46pt padding, which puts the first ring hard against the curve it is meant to be centred in. Off is the shipped rail — 26pt fourth-order superellipse corners (`DockBerthShape.appendCorner`) with a 24 × 38 flare, `verticalPadding` 46, `endRingOffset` 0, and a tail whose flanks leave the card at an angle. On: **one circle sets every curve: a ring's outer edge** (20pt at standard). The card's corners are that radius (`DetailCardLayout.cornerRadius`). The rail's ends are half-circles of half the rail (`DockLayout.cornerRadius`, 32pt = the ring plus the 12pt band beside it), on the end ring's centre line. The flare is the same circle turned inside out (`flareHeight` = `flareWidth` = `cornerRadius`), so corner and flare meet on the centre line as one S-curve. The end ring sits `endRingOffset` (8pt) further in than the end's centre — 20pt of black over it, 12pt beside it; concentric (12pt all round) was built first and read cramped beside the reference, and 0 / 8 / 12 were reviewed side by side. `verticalPadding` is derived from all of these (54pt); floating end padding (22pt) puts the ring at the same place in the capsule's round end. Round ends move the rail 16pt longer, so the setting goes through `onChange?()` and the flag rides on `PanelMetrics` — the AppKit frame is worked out from `DockLayout` before SwiftUI lays anything out. Either way `cornerRadius + flareWidth` is exactly `width`, and `verticalPadding` clears `flareHeight` by 22pt.
- `labelAboveRing` (default off) does not change rail size but **does** move the ring inside the item. `DockLayout.ringOffsetInItem(on:)` is the one number drawing and hit testing share.
- `PanelSize` small/standard/large → `PanelMetrics.scale`. All dock and card measurements read it.
- `showsSecondRing` (default off) changes nothing outside the ring's own circle — it moves the activity mark and shrinks the icon disc, both budgets. [rings-and-surface.md](rings-and-surface.md)

Hit-testing geometry (sliver ⊂ rail, clicks on the circle): [input.md](input.md). Constant-as-budget rules: [../development.md](../development.md).
