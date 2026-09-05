# Liquid Glass: diagnosis uncertain

**Status:** current implementation is hit-testable `PanelSurface` + `FloatingPanel.sendEvent`. **Evidence:** historical measurements of materials; drag diagnosis **uncertain**; real input **not** re-verified.

## What we still believe

Black default: the panel sits over work all day. No scrim: Apple’s guidance is that the material manages legibility; a black tint barely moved luminance (historical). `.primary` on content; dark scheme pinned only when glass is off, via environment, not `preferredColorScheme`.

`Glass.clear` not `.regular`. Historical: five variants in a transparent panel over a bright busy backdrop — SwiftUI `.regular` opaque milky white; `NSVisualEffectView` worse; `.clear` and `NSGlassEffectView` kept content visible. All five *did* sample behind the window, so a transparent `NSPanel` was not the problem. `NSGlassEffectView` was pixel-for-pixel the same material but only knows a corner radius; the modifier takes the morphing shape.

Halo: opaque disc over blur is invisible on black and a white coin on glass. Historical checkerboard: clearing 213/205/212 with the disc vs 193/128/181 with a mask. Shadow on the composed view leaked usage colour through the icon’s antialiased edge (green cast +16 over neutral on a 35% ring, +0 unhovered).

## What we no longer assert

The first write-up treated rings-only drag with glass on as a **system** bug: macOS 26 material implementing interactivity outside SwiftUI’s hit-testing chain (developer.apple.com/forums/thread/816366). `.allowsHitTesting(false)`, `.disabled(true)`, opaque ink above and below were tried; none helped. `hitTest` and synthesised events reported the handle reachable throughout.

**Suspect that was never a glass bug.** The same symptom (“only the rings can be dragged”) is exactly what the SwiftUI-hosted handle produced on the **black** panel once the berth stopped claiming presses. Window-owned events give the material no say. If dragging works on glass, the settings caption (“Drag it by a ring while this is on.”) and this suspicion should be revisited — **after real input**, not after another probe.

This cannot be reproduced in a harness: probes bypass whatever the material installs. When a symptom survives every local probe, that is not evidence it is glass.

Current rules: [../ui/rings-and-surface.md](../ui/rings-and-surface.md), [../ui/input.md](../ui/input.md).
