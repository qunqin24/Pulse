# Pointer, drag, clicks

SwiftUI `.onHover` **does not work here**. It tracks only while the app is active. Pulse is `.accessory` behind a non-activating panel that never becomes key, so it is essentially never active.

Do not treat `hitTest` or synthesised `NSEvent`s as proof that a real click arrives. They have reported handles as reachable at widths the rail did not have, and they bypass whatever a material installs. Geometry probes are useful (“is this point in `grabArea`?”). Whether a person can drag the panel is **real input**, which this repo does not currently claim to have re-verified.

Why enter/leave are split, why the window owns the drag, and the Liquid Glass episode: [../decisions/hover-and-drag.md](../decisions/hover-and-drag.md), [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

## Hover (open / close the card)

Two `NSViewRepresentable` backgrounds:

- `PointerEntryReporter` — `.activeAlways` `NSTrackingArea`, reports **only entering** a ring.
- `PanelPointerWatcher` — samples `NSEvent.mouseLocation` on a timer. `FloatingUsagePanelView.isOverContent` tests against the **rail and the card**, not the window frame (the panel is full-size and mostly transparent).

For a top-docked notch rail, an unpainted `PointerEntryReporter` covers exactly the physical housing rectangle and calls the existing `show()` method on entry. It does not claim clicks. The same rectangle is included in `isOverContent`, so the ordinary 150ms sampler can also open and retain the rail. There is no separate dwell timer. The hidden rail has no sliver or grab target. Once expanded, the full surface from the screen top through the added bottom padding counts as content. One derived `isNotchHeld` state covers a press, drag, or open menu; releasing the last of these re-evaluates the pointer so a stationary pointer cannot leave it stuck open.

**Do not close on exit events.** Views appearing, moving, or animating under a stationary pointer fire spurious exits; closing reopens; it loops. Enter from tracking areas, leave from sampling the real pointer. That loop is then structurally impossible.

The sliver’s tracking area cannot be the only way `isHovered` gets set: a floating panel dragged onto an edge docks with `isHovered` still false and snaps shut in the hand. `pointerMoved` sets it from the same test that decides when to hide.

`PanelHitArea.stripIsContainedInRail()` asserts the sliver never pokes outside the rail’s hit area (or leave-rail lands on the sliver, which shows the rail, which hides it). Bound is rail capacity / slots, not `Provider.allCases.count`. Run from `FloatingPanelController.init` once metrics are settled.

## Drag belongs to the window

Two things, different files:

1. Something in the panel must **claim** the point or the window is never handed the press — `PanelSurface`, hit-testable, `contentShape` of the capsule. `allowsHitTesting(false)` killed dragging in the empty black between rings (rings still worked via tracking areas).
2. The press must be **taken** — `FloatingPanel.sendEvent`. A SwiftUI-hosted handle only sees a press if SwiftUI claims the point first. Laying a shape *over* the handle swallows the press. `sendEvent` sees events before SwiftUI hit testing and before anything Liquid Glass installs.

The window is handed **two** rects: `grabArea` (rail, or sliver when collapsed) decides whether a press is taken; `railFrame` (always the rail) is what placement arithmetic runs on. Collapsed, grabbing a 20pt sliver and placing it as a 64pt rail throws the panel across the screen. Both sized to what is drawn, or a press in the transparent band moves the panel instead of passing through.

## Ring click vs ring drag

Same window-level path. `FloatingPanel` records the press, marks a drag only after a real `leftMouseDragged`, reports a click on mouse-up otherwise. The press also sets `placement.isPressed`, and **nothing may move the panel while that is set** — not merely while `isDragging` is. The grab offset is measured at mouse-down, so a re-place in the gap before the first movement does not slide the panel, it makes it jump by that much on the frame the pointer first travels. `PanelHoldTests` pins it. `PanelHitArea.slot(at:)` accepts only the visible circle; labels and berth gaps stay drag-only. It indexes **slots**, not accounts — a split provider draws two rings from one login, so counting accounts aims every click after the split at the wrong ring. The controller builds the same list the panel draws from, through `RailSlot.rail(for:isSplit:groups:)`.

Click starts a provider-scoped refresh. `UsageStore.isRefreshing` : the usage arc **dims but does not move**; a short bright segment travels around. Do not rotate the usage arc (at 0% there is no arc; at 95% a rotated arc looks still; it also takes the gauge away). Travelling mark is usage colour, not white (white is the CLI-activity mark). Hold at least 650ms so a local read still registers. Keep the physical click here; `sendEvent` takes the press before SwiftUI. Default accessibility action can still live on the ring.

A click is matched against the **displayed slots** the controller builds through `RailSlot.rail(for:isSplit:groups:)`, not `Provider.allCases`.

## Secondary click opens the panel's menu

`FloatingPanel.sendEvent` also takes `.rightMouseDown`, and `.leftMouseDown` **with control held** — a control-click is a right click on macOS, and letting it fall through to `begin(_:)` starts carrying the panel instead. Same geometry as the drag (`grabArea`), so what can be picked up can be right-clicked, **the sliver included** — the rail is wound down most of the time, and a menu reachable only after hovering is one more thing to know.

Taken in `sendEvent` rather than with SwiftUI's `.contextMenu`, for the reason every other press is: this is a non-key accessory panel and SwiftUI's own input handling is not reliable on it.

`AppDelegate.panelMenu()` builds it — settings, quit, and an available update — and builds it **fresh on every click**, so an update found since the last one is on it. The menu exists because a full menu bar is where Pulse's icon stops being reachable ([issue #24](https://github.com/qunqin24/Pulse/issues/24)).

`placement.isMenuOpen` is set for the span of `popUp`, which runs its own tracking loop. Without it the pointer is on the menu — off the panel by every test `pointerMoved` makes — and the rail winds down to its sliver the moment the menu appears beside it. `scheduleHide` guards on it exactly as it guards on `isDragging`, and re-arms the same way.

## Global shortcuts

`GlobalShortcut` / `GlobalShortcutMonitor` (App/). `RegisterEventHotKey`, **not** an event tap: a tap that sees other apps' keystrokes needs Accessibility permission, and that is not a trade worth offering to open a settings window. Two actions, both **unset until somebody sets one** — a default combination is a key taken out of every other app's hands on behalf of someone who never asked.

A combination needs ⌘, ⌥ or ⌃ in it; ⇧ alone is refused, and so is a bare key, function keys included. `⇧P` would take the letter P away from every text field on the Mac. A registration the window server refuses (another app holds the keys — or Pulse's own other shortcut does) lands in `unavailable`, and settings says so: a shortcut that quietly does nothing is worse than none, because the reader blames the feature. Recording is a **local event monitor**, installed only while recording and swallowing what it sees, which is what lets ⌘Q be recorded rather than quitting the app. [settings.md](settings.md)

## Settings fields

Click-away ending editing is `SettingsWindow.sendEvent`, geometry vs the field, never `hitTest`. [settings.md](settings.md).
