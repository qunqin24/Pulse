# Pointer, drag, clicks

SwiftUI `.onHover` **does not work here**. It tracks only while the app is active. Pulse is `.accessory` behind a non-activating panel that never becomes key, so it is essentially never active.

Do not treat `hitTest` or synthesised `NSEvent`s as proof that a real click arrives. They have reported handles as reachable at widths the rail did not have, and they bypass whatever a material installs. Geometry probes are useful (“is this point in `grabArea`?”). Whether a person can drag the panel is **real input**, which this repo does not currently claim to have re-verified.

Why enter/leave are split, why the window owns the drag, and the Liquid Glass episode: [../decisions/hover-and-drag.md](../decisions/hover-and-drag.md), [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

## Hover (open / close the card)

Two `NSViewRepresentable` backgrounds:

- `PointerEntryReporter` — `.activeAlways` `NSTrackingArea`, reports **only entering** a ring.
- `PanelPointerWatcher` — samples `NSEvent.mouseLocation` on a timer. `FloatingUsagePanelView.isOverContent` tests against the **rail and the card**, not the window frame (the panel is full-size and mostly transparent).

**Do not close on exit events.** Views appearing, moving, or animating under a stationary pointer fire spurious exits; closing reopens; it loops. Enter from tracking areas, leave from sampling the real pointer. That loop is then structurally impossible.

The sliver’s tracking area cannot be the only way `isHovered` gets set: a floating panel dragged onto an edge docks with `isHovered` still false and snaps shut in the hand. `pointerMoved` sets it from the same test that decides when to hide.

`PanelHitArea.stripIsContainedInRail()` asserts the sliver never pokes outside the rail’s hit area (or leave-rail lands on the sliver, which shows the rail, which hides it). Bound is rail capacity / accounts, not `Provider.allCases.count`. Run from `FloatingPanelController.init` once metrics are settled.

## Drag belongs to the window

Two things, different files:

1. Something in the panel must **claim** the point or the window is never handed the press — `PanelSurface`, hit-testable, `contentShape` of the capsule. `allowsHitTesting(false)` killed dragging in the empty black between rings (rings still worked via tracking areas).
2. The press must be **taken** — `FloatingPanel.sendEvent`. A SwiftUI-hosted handle only sees a press if SwiftUI claims the point first. Laying a shape *over* the handle swallows the press. `sendEvent` sees events before SwiftUI hit testing and before anything Liquid Glass installs.

The window is handed **two** rects: `grabArea` (rail, or sliver when collapsed) decides whether a press is taken; `railFrame` (always the rail) is what placement arithmetic runs on. Collapsed, grabbing a 20pt sliver and placing it as a 64pt rail throws the panel across the screen. Both sized to what is drawn, or a press in the transparent band moves the panel instead of passing through.

## Ring click vs ring drag

Same window-level path. `FloatingPanel` records the press, marks a drag only after a real `leftMouseDragged`, reports a click on mouse-up otherwise. `PanelHitArea.provider(at:)` accepts only the visible circle; labels and berth gaps stay drag-only.

Click starts a provider-scoped refresh. `UsageStore.isRefreshing` : the usage arc **dims but does not move**; a short bright segment travels around. Do not rotate the usage arc (at 0% there is no arc; at 95% a rotated arc looks still; it also takes the gauge away). Travelling mark is usage colour, not white (white is the CLI-activity mark). Hold at least 650ms so a local read still registers. Keep the physical click here; `sendEvent` takes the press before SwiftUI. Default accessibility action can still live on the ring.

A click is matched against **displayed** order: `orderedProviders.filter(isEnabled)`, not `Provider.allCases`.

## Settings fields

Click-away ending editing is `SettingsWindow.sendEvent`, geometry vs the field, never `hitTest`. [settings.md](settings.md).
