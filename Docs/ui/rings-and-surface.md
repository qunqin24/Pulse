# Rings and surface

The panel's surface (solid, light, Liquid Glass), what ring colour means, and the arcs a ring can carry. The animated mark was removed: [../decisions/bot-mark-removed.md](../decisions/bot-mark-removed.md). Input and hit testing: [input.md](input.md).

## Light panel

Optional, **off by default** (`AppSettings.usesLightPanel`, #74): the solid surface drawn light — `PanelLight.fill` (grey 0.97) with a `PanelLight.edge` hairline (black 0.12) so it keeps an edge on a white page — with dark content. It is a colour scheme, not a second set of views: `FloatingUsagePanelContent.panelScheme` pins `.light` instead of `.dark`, `PanelSurface` picks its fill from `\.colorScheme`, and content drawn in `.primary` follows.

- **The hairline is drawn inside the outline.** The window is exactly card + rail wide, so a line drawn outside is cut off at the window's edge. It strokes the *normalized* path (the card's tail is a separate, overlapping subpath) and leaves out `PanelSurface.screenEdge` — the docked side, or the notch berth's top — where it would be a grey line along the display's own edge.
- **Solid surface only, notch included.** Glass stays pinned dark (below); while glass is on the setting is kept but ignored, and its row is greyed out rather than hidden. At a notch the berth is light too: a surface that silently turned black when docked read as a bug.
- **The usage colours have light twins.** `pulseGood` / `pulseCaution` are about 1.5:1 on a light surface. Each `Color.pulse*` is a dynamic `NSColor` that resolves a deeper twin under an aqua appearance, ≥ 3:1 on `PanelLight.fill` (`UsageTintTests` pins the switch and the ratio). The menu uses the same twins where macOS draws it light. A colour chosen per account (`RingTint`) is the reader's and is not adjusted.

## Liquid Glass

Optional, **off by default** (`AppSettings.usesGlass`, `PanelSurface`); black is the default because the panel sits over the user's work all day. Measurements and history: [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

- **Dim the glass, draw white on it.** With the active-appearance gate open, `.clear` glass is nearly transparent (white over a white page, black over a terminal). So it carries `PanelGlass.dim` — black up to 0.6, set by the **Transparency** slider (`AppSettings.glassTransparency`, default 0.5 → 0.3), passed down as `\.glassTransparency` — and the panel is pinned dark on **both** surfaces with `.environment(\.colorScheme, .dark)`, not `preferredColorScheme` (window-wide). Content still uses `.primary`, not hardcoded white. **Past the default the text follows the slider from white to black** (`PanelGlass.ink`: the label colour up to `inkTurns` 0.5, then `Color(white:)` at 0.85 opacity down to black at 1, applied as the root `.foregroundStyle`), and past `schemeTurns` (0.75) the panel's scheme turns light so hairlines, tracks and the usage colours follow (`PanelGlass.scheme`). The reader asked for this: white text vanished over a light page at the clear end. Black text vanishes over a dark window instead, and Pulse cannot see what is behind the panel without recording the screen; the slider's caption says so. `GlassInkTests`.
- **Liquid, not frosted, depends on `FloatingPanel` overriding the private `_hasActiveAppearanceIgnoringKeyFocus` to return `true`.** Glass in an inactive window is drawn as a flat blur, and this panel is always inactive. Do not make the panel key-eligible instead: that holds only until the app's first deactivation and puts focus at risk. If macOS stops asking the selector, the glass reverts to frosted and nothing else breaks.
- **`Glass.clear`, not `.regular`** (`.regular` measured, historically, as opaque milky white in a transparent panel). Needs macOS 26; older systems get a vibrant blur (`.ultraThinMaterial`).
- **Keep the surface in hit testing.** `allowsHitTesting(false)` is what stopped gap-dragging; the window takes the drag in `sendEvent` before any view sees the event ([input.md](input.md)).
- **Glass needs a pixel under it** (`PanelGlass.claim`, black 0.01). The system composites the glass and its tint, leaving the window's own pixels empty, and the window server hands a press on empty pixels to whatever is behind, so `sendEvent` never sees it (#68: a docked rail draggable only by its rings). Verified by real input after the fill went in. Do not remove it or take it to zero.

## Colour and spent

Colour means **usage**, not identity (`UsageTint`: green / amber / red / spent deep red). `Provider` carries no accent; the icon is the brand. Brand-coloured rings read as a warning (Claude's orange at 3% used).

**Warning threshold.** `AppSettings.warningThreshold` (`WarningThreshold`, 60–90%, default 75) is where amber becomes red, and it bounds that step only: green stays under `UsageTint.cautionThreshold` (0.5), below every offered figure, so the two steps cannot cross. It reaches the panel through `EnvironmentValues.usageWarningThreshold`, set once in `FloatingUsagePanelContent` — one number every ring, bar and figure must agree on, and `UsageRingView`'s initializer is already at the type-checker's budget. It is not a layout input, so it is not in `PanelMetrics`. `UsageTint.color(for:isExhausted:warningAt:)` and `UsageWindow.tint(warningAt:)` take it with **no default**: a default is how one ring comes to disagree with its neighbour.

**Per-account `RingTint`** is opt-in: system colour well, stored as hex, converted through **sRGB**, no opacity (translucent reads as "no reading"). Spent still uses the spent colour; `UsageRingView.isSpent` comes from the **provider**, not the fraction, because a lock can happen well short of 100%.

**Collapsed alert colour.** `FloatingUsagePanelContent.alertTint` finds the worst headline window across the rail and, past `warningThreshold` or exhausted, hands its `UsageTint` colour to `UsageDockView.alert`. An ordinary `PanelSurface` applies it only while collapsed (`isExpanded ? nil : alert`; expanded, the rings already say it). A physical notch has no collapsed surface, so `NotchAlertShape` draws the colour as a 2pt edge directly below the housing. `AppSettings.dockShowsAlertColor` (on by default) gates both inside `alertTint`, so off is the same `nil` an all-green rail produces. It exists because several accounts past the threshold otherwise leave a line coloured for as long as it is watched, which reads as a stuck pixel rather than a warning. [settings.md](settings.md)

**Countdown** (`showsRemaining`): the arc follows the figure; colour still means closeness to the limit. No reading → empty track either way; spent fills the ring. Do not invert `nil` into a full "100% left" circle. [../refresh-and-data.md](../refresh-and-data.md)

## Hover halo

The pointed-at halo hangs on the **progress arc**, not the ring view, and its inward half is **masked**. Not a `.shadow` on the composed view (it draws behind the icon and antialiased edges leak tint), not an opaque disc (invisible on black, a white coin on glass); a mask has no colour to get wrong. Measurements: [../decisions/liquid-glass.md](../decisions/liquid-glass.md).

## Window-clock arc

`showsWindowClock`, default off. Drawn **outside** the usage ring (inside belongs to the activity mark), neutral and low opacity, not a second hue. `windowClockDirection` chooses filling with elapsed time (the default, so existing installs do not reverse) or emptying with time remaining. Either direction needs both the provider-reported reset and duration (`reportsLength` must be true); with either missing it is nil. Applied as an overlay **after** `.frame(width: diameter…)`, never as a ZStack child (a wider child grew the usage ring). Own 60s ticker, not the usage loop.

## Second ring

`showsSecondRing`, default off. `ProviderUsage.secondWindow(preferring:)` returns **the fullest limit in the ring's own model group**, else the fullest of everything else. Nil where the provider reports one limit: an empty second ring reads as a limit at zero, or as a fault.

- **The group comes first because a provider can report independent budgets.** Antigravity reports a five-hour and a weekly for `Gemini` and the same pair for `Claude and GPT`; pairing a Gemini weekly with a Claude five-hour would put two unrelated pools on one mark. Claude Code's five-hour and weekly are unscoped, so they pair with each other and the model-scoped weekly stays on the card. "Fullest" rather than "the weekly one" needs no per-provider table and still works when the ring is pinned. `max(by:)` keeps the first of equals, so untouched windows stay in the provider's order between passes.
- **Inside, not outside.** Outside is the clock arc's, and the limit that matters most stays the outer, bigger, thicker ring, so nothing moves for anyone who leaves this off. Same colour language as the first ring; size and weight tell them apart. Spent fills it, whichever way it counts.
- **Geometry lives in `DockLayout.secondRing…`, not in `PanelMetrics`**: nothing outside the ring changes size. At standard scale the band between the icon disc and the ring's inner edge is 6pt and the activity mark rides its middle; with the second ring on, the mark moves in against the disc and the disc gives up 2pt a side. The ring, the rail's width and the ring centres are unchanged.
- **The percent label follows the outer limit only.** Two figures there would change `DockLayout.percentTextWidth`, a budget the whole rail is measured from.

## One ring per model group

`AppSettings.splitAccounts`, per account, default off, offered only where `Provider.splitsByModelGroup` is true — Antigravity alone, whose plan reports a Gemini allowance and a Claude-and-GPT one as two `scope`s of one login. One ring could only show the busier. Off by default because a second ring costs a slot, and docked, the rail is the whole panel.

- **The rail is slots, not accounts.** `RailSlot.rail(for:isSplit:groups:)` is the one place the order is decided; the panel's `entries` and `PanelHitArea.slot(at:)` both go through it, so a ring is never drawn at one position and refreshed from another. A slot is an account plus an optional group; `id` is `account@group`.
- **A limit never disappears into the split.** `modelGroups(of:)` is all-or-nothing: a reading that mixes scoped and unscoped windows yields no groups. More groups than `modelGroupCount` leaves the account whole rather than dropping the extra group — one ring showing the busiest of three is better than a limit nobody can see.
- **One slot until a reading carries more than one group**: one ring that becomes two beats two empty ones that may never fill. Groups keep the provider's reported order (what Antigravity's own screen shows).
- **Both rings are the same account**: icon, tint, key, refresh. Clicking either refreshes the login. They differ in windows (`windows.filter { $0.scope == group }`) and title, which appends the group so VoiceOver and the card do not repeat themselves.
- **The budget moves with it.** `AppSettings.railSlotCount` counts a split account as `provider.modelGroupCount` (a fixed 2, so the rail does not resize when a reading is one group short) and feeds `PanelMetrics.makeRoom(for:)`.

## What may not be animated

The rail's `railTop` / `railLeading` offsets track the pointer, so they sit **outside** `.animation(_:value:)`, applied after the card's reveal. Inside the card's `value: selectedSlot` spring, the first frame of a drag closed the card and sprang the rail's position too, so the panel slid away from the hand dragging it.

## Activity mark

White arc on the band between the icon disc and the usage stroke — **or just outside the disc while the second ring is on**. Core Animation, not `TimelineView`. Reset `spinning` on disappear. [../refresh-and-data.md](../refresh-and-data.md)

**`AppSettings.animatesRingActivity`** (on by default) is the one switch over this arc and the refresh mark drawn over the usage arc during a fetch. `UsageRingView.isBusy` / `isRefreshing` track the facts either way; off only withholds the cue — no travelling arc, no refresh sweep, no dimming of the usage arc while it fetches. [settings.md](settings.md)

## Icons

`LobeIconView` is a template image with **no colour of its own**. Do not hardcode white there: the settings sidebar needs the ordinary label colour.
