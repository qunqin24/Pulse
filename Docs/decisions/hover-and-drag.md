# Hover without `.onHover`; drag in `sendEvent`

**Status:** still in force. **Evidence:** code structure plus historical probes that **lied**. Real-input verification is not claimed.

## Why `.onHover` is banned

It tracks only while the app is active. Pulse is an accessory app behind a non-key panel. Enter from `.activeAlways` tracking areas; leave by sampling `NSEvent.mouseLocation` against rail + card.

Closing on **exit events** loops: animation under a stationary pointer fires a spurious exit, the card closes, the pointer is back on a ring, the card opens. Splitting enter/leave makes that structurally impossible.

Related loop: sliver poking outside the rail’s hit area. `PanelHitArea.stripIsContainedInRail()` exists because the assert went uncalled for a while and its comment named a `PanelHitAreaCheck` type that never existed. Its bound was `Provider.allCases.count` until the rail was keyed by account.

Floating → dock with `isHovered` still false snapped the rail shut in the dragging hand. `pointerMoved` must set hover from the same test that hides.

## Why the window owns drag and click

A press only reaches a view inside `NSHostingView` if SwiftUI claims the point. After `PanelSurface` arrived for glass, it was marked `allowsHitTesting(false)` so it could not steal from a SwiftUI handle — so **nothing** claimed the gaps between rings. Rings still worked (tracking areas + `contentShape`). An overlay shape to claim the gaps swallowed the press and killed dragging entirely.

`FloatingPanel.sendEvent` sees the window-server event first. Two rects: `grabArea` vs `railFrame`. Collapsed, placing a sliver as if it were the full rail throws the panel.

Rotating the usage arc as click feedback: at 0% **nothing** for the whole 650ms hold (measured then); at 95% indistinguishable from still; it also takes the gauge away. Travelling mark instead.

## `hitTest` is worthless for this

It reported the old handle reachable at every point of the rail including gaps, and at the full 64pt while collapsed to 20. Both impossible. It lied about Liquid Glass the same way. Geometry (“is this in `grabArea`?”) is worth checking — a missing `railFrame` closure made every press refuse silently. Whether a real click arrives is only answered by a person pressing it.

Current rules: [../ui/input.md](../ui/input.md). Glass overlap: [liquid-glass.md](liquid-glass.md).
