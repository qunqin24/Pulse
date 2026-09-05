# Rings and surface

## Liquid Glass

Optional, **off by default** (`AppSettings.usesGlass`, `PanelSurface`). Black stays default because the panel sits over the user’s work all day.

- Do **not** scrim the glass. `Glass.tint` is a hue, not a darkening. Content uses `.primary`, not hardcoded white. Pin dark appearance **only** when glass is off, via `.environment(\.colorScheme, .dark)` — not `preferredColorScheme` (window-wide).
- Do **not** take the surface out of hit testing. `allowsHitTesting(false)` is what stopped gap-dragging. The window takes the drag in `sendEvent` before any view sees the event. [input.md](input.md)
- Use `Glass.clear`, not `.regular`. `.regular` was measured (historical) as opaque milky white in a transparent panel. Needs macOS 26; `#available` with a vibrant blur behind it.

**Historical diagnosis is uncertain.** An older note blamed macOS 26 glass for swallowing input outside SwiftUI’s hit-testing chain (rings-only drag; forums thread 816366). The same symptom then appeared on the black panel once the berth stopped claiming presses. Current code claims the surface and takes events in `sendEvent`. **Do not claim real-input verification** for glass or black. Settings still add “Drag it by a ring while this is on.” when glass is enabled — that caption is current UI, not proof of the old diagnosis.

[../decisions/liquid-glass.md](../decisions/liquid-glass.md)

## Colour and spent

Colour means **usage**, not identity (`UsageTint`: green / amber / red / spent deep red). `Provider` carries no accent; the icon is the brand. Brand-coloured rings read as a warning (Claude’s orange at 3% used).

Per-account `RingTint` is opt-in. Spent still uses the spent colour (`UsageRingView.isSpent` from the **provider**, not from the fraction — a lock can happen well short of 100%). System colour well, stored as hex, converted through **sRGB**. No opacity (translucent reads as “no reading”).

Countdown (`showsRemaining`): arc follows the figure; colour still means closeness to the limit. No reading → empty track either way; spent fills the ring. Do not invert `nil` to a full “100% left” circle. [../refresh-and-data.md](../refresh-and-data.md)

## Hover halo

The pointed-at halo hangs on the **progress arc**, not the ring view. Its inward half is **masked**, not covered with a disc. A `.shadow` on the composed view draws behind the icon (antialiased edges leak tint). An opaque disc is invisible on black and a white coin on glass. A mask has no colour to get wrong.

## Window-clock arc

`showsWindowClock`, default off. **Outside** the usage ring (inside is the activity mark). Neutral, low opacity, not a second hue. Applied as an overlay **after** `.frame(width: diameter…)`, never a ZStack child (a wider child grew the usage ring). Nil when the provider gives `resetsAt` or length without the other; `reportsLength` must be true. Own 60s ticker, not the usage loop.

## Activity mark

White arc on the empty ring between icon disc and usage stroke. Core Animation, not `TimelineView`. Reset `spinning` on disappear. [../refresh-and-data.md](../refresh-and-data.md)

## Icons

`LobeIconView` is a template image with **no colour of its own**. Do not hardcode white there — settings sidebar needs the ordinary label colour.
