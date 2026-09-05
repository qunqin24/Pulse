# Development

Toolchain and local run: [build-from-source.md](build-from-source.md). Shipping: [releasing.md](releasing.md). Process: [../CONTRIBUTING.md](../CONTRIBUTING.md).

## Layout constants are budgets

The AppKit frame is computed from `DockLayout` / `DetailCardLayout` **before** SwiftUI lays anything out, and hit testing steps along the same units. Anything that renders larger than its constant overflows; smaller leaves slack that accumulates down the rail.

- Every measurement is a **computed** `var` on `PanelMetrics` (or those layouts reading it), **never a `static let`**. A `static let` is fixed for the process: `cardInset` once kept Small’s width after the user switched to Large.
- `FloatingUsagePanelView` (and anything else that caches layout) carries size, language, percentage flags, spacing, and label-above-ring in `.id(...)`. SwiftUI cannot observe plain statics.
- Anything new on the panel takes size from `PanelMetrics`, never a literal. The card’s fonts scale with the rail; historically width followed `PanelMetrics` while fonts did not.
- `percentTextHeight` and `itemLength` are measured with the real font and rounded **up**. Every item is pinned to its budgeted length along the rail axis.
- `RailSpacing` (tight/standard/loose) is *not* folded into `PanelSize`: fewer millimetres between rings is a different wish from bigger rings.
- `BurnRate`’s extra line rides on `PanelMetrics` / `DetailCardLayout` because it changes card height. Left out of that budget, a top-docked card was sliced off the window.

Historical matrix and disagreement numbers: [decisions/panel-frame.md](decisions/panel-frame.md). Do not treat those numbers as re-verified.

## Localization

English and Simplified Chinese. Strings in `Sources/Pulse/Resources/en.lproj` and `zh-Hans.lproj`. `Package.swift` sets `defaultLocalization: "en"`.

- Language follows the system unless Settings pins one. Takes effect **without relaunch**: `LocalizationSource` swaps the `.lproj` sub-bundle. Lookups are a function call, so SwiftUI has nothing to observe — views that show copy carry `.id(settings.language)`.
- `UsageWindow.Kind` and `ProviderUsage.Unavailability` are **cases, not stored strings**, so a reading taken in one language is not frozen when the user switches.
- Always `String.localized(_:)` or `Text(localized:)` (`Localization.swift`). Implicit SwiftUI localization (`Text("…")`, `Button("…")`) resolves against `Bundle.main`, which for a SwiftPM executable is the bare binary — silent English forever.
- Keys are the English text. Interpolated keys use **non-positional** `%@` (`"%@ used, %@"`). `%1$@` in the strings file misses and falls back to English.
- Interpolating an `Int` produces `%lld`, not `%@`. Interpolate a `String`: `.localized("\("\(count)") minutes")`.
- A `%` next to a placeholder is a malformed printf conversion. Bake the sign into the value (`"\(count)%"`).
- **No conditional inside `Text(localized:)`.** The key scanner reads the bare tail after `localized:` and can match an unrelated key. Build the string in a property first.
- Dates, times, and money use `LocalizationSource.locale`, not `Locale.autoupdatingCurrent`.
- Large numbers: `TokenCount.short` uses 万 / 亿 when `groupsByTenThousands`. Those unit characters live in code, not the strings file.
- Chinese full stop `。` is full-width and already has trailing space; do not add another (`glassSubtitle`).
- SwiftPM lowercases `zh-Hans.lproj` to `zh-hans.lproj` in the built bundle. `Bundle.preferredLocalizations` is case-insensitive; `path(forResource: "zh-Hans", ofType: "lproj")` returns nil.

`./Scripts/check-localization.sh` compares the two `.strings` files **and** every key the source asks for (`Scripts/localization-keys.py` — a scanner, not a regex, because interpolations nest). Comparing only the two files missed a renamed string literal that fell back to English while both files still agreed.

Why implicit `Text` fails, and the scanner’s blind spots: [decisions/localization.md](decisions/localization.md).

## Resources

`Sources/Pulse/Resources` holds provider marks as SVG (Lobe Icons, monochrome). `LobeIconView` / `LobeIconStore` loads them via `Bundle.module` as **template images with no colour of their own**. `width="1em"` makes `NSImage` report 1×1; the store assigns an explicit size.

The package resource bundle must land in `Contents/Resources` in a real app (`Bundle.module` looks through `Bundle.main.resourceURL`). Leave it out and the app runs, silently in English, with no marks. [releasing.md](releasing.md).

## Adding UI or a provider

- New panel chrome: take size from `PanelMetrics`; keep the card an overlay; do not resize the window while a card opens ([ui/panel-geometry.md](ui/panel-geometry.md)).
- New pointer behaviour: not `.onHover`; not exit events ([ui/input.md](ui/input.md)).
- New settings copy: one-line subtitles. Reasoning belongs in docs, not on screen, except the money card’s provenance ([ui/settings.md](ui/settings.md)).
- New `Provider` case: SVG, service returning `ProviderUsage`, branches in `UsageStore.refresh` / `refresh(_:)`, answers to `keepsLocalTranscripts` / `hasSourceChoice` / `supportsMultipleAccounts` / `canReportWithoutSetup`. `AgentActivity.root(for:)` and `UsageLedger.logFiles(for:)` return optional roots. Routes and auth: [providers/README.md](providers/README.md).

`ImageRenderer` cannot draw `NavigationSplitView` or AppKit-backed controls — check Settings by running the app.
