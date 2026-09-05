# Panel frame: cards overlay, axis may resize

**Status:** still in force. **Evidence:** mixed — bugs that shipped or were fixed in-tree (code), plus historical layout matrices that have not been re-run.

## Do not grow the window when a card opens

Widening the panel moves its left edge, which moves the coordinate space SwiftUI lays out in. The rail’s position *in that space* jumps by the card’s width even though its position on screen never changes, and the open animation dutifully animates the jump. Two separate versions of that bug were fixed by **removing the movement** rather than animating around it: fixed window size, card as overlay not stack child.

Re-docking **side ↔ top** *does* resize (`Layout.size(for:)`). That happens under the pointer with no card open. Inferring a “turn” from rail size was wrong once end padding started dropping off-edge (same rail 48pt shorter floating): every dock↔float counted as a turn, re-centred for one frame, snapped back (~252 then ~276pt, historical). Grab is re-measured to the rail **centre** on that size change. Historical: ring centre 332.0pt unchanged across the transition after the fix.

## Overlay order and height

Applying `.padding(.top, railTop)` *before* the card overlay anchored every card to the panel top and sliced it. Shipped once; invisible while the rail was centred.

The window has to be tall enough for the tallest card. When Codex grew a third limit, the card was sliced flat against the edge and read as a drawing bug.

## Constants as budgets

Historical verification (not re-run): `percentTextHeight` 15 vs rendered 15.6–16.0 drifted ring centres up to ~6pt; top-rail `itemLength` assumed the label narrower than the ring, but `"100%"` was wider (~1.0–1.5pt) and labels rendered as `"10…"`. After measuring fonts, rounding up, and pinning item length: matrix of edges × dock × account counts × sizes × spacings × percentage flags × label above/below — **8,640** rings, worst disagreement **0.72pt**. `labelAboveRing` hit-test vs drawn centre: 168 rings, worst **0.0000pt**. Window-clock overlay vs ZStack child: child grew the ring 36→52pt; as overlay, 168 clicks still landed, margins 6.6 / 8.0 / 9.8pt at three sizes.

`static let` on a `PanelMetrics`-derived value (`cardInset`) froze Small’s inset after switching to Large (~61pt short on a 78pt rail).

Forecast line left out of `DetailCardLayout`: top-docked card with five limits ran ~84pt past the window.

Current rules: [../ui/panel-geometry.md](../ui/panel-geometry.md), [../development.md](../development.md).
