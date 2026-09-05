# CLAUDE.md

AI entry for this repo. Human workflow, evidence rules, and the docs map live in [CONTRIBUTING.md](CONTRIBUTING.md) and [Docs/README.md](Docs/README.md). Change the **authoritative topic doc** in the same patch as the code; do not grow this file.

Pulse is a macOS menu-bar usage monitor. SwiftUI draws the panel; a transparent, non-activating AppKit `NSPanel` owns size, placement, and input. Fourteen providers, no Pulse backend, no Pulse account. Per-provider routes, auth, cookies, and extra logins: [Docs/providers/README.md](Docs/providers/README.md).

## Commands

```bash
swift run Pulse
swift build
./Scripts/bundle.sh
./Scripts/dmg.sh
./Scripts/check-localization.sh
```

**`xcode-select` must point at Xcode, not CommandLineTools.** `#Preview` is expanded by an Xcode plugin; otherwise every build fails with `PreviewsMacros plugin not found`. Check with `xcode-select -p`. One-off: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.

**Never strip `#Preview` blocks to make the build green.** That hides errors inside them and has already shipped a broken build. See [Docs/decisions/never-strip-previews.md](Docs/decisions/never-strip-previews.md).

A clean `swift build` is not the Xcode check. Actor-isolation mistakes can be warnings here and hard errors there (every `View` is `@MainActor`). Before claiming a change builds:

```bash
swift build -Xswiftc -swift-version -Xswiftc 6
```

Treat remaining warnings as failures. macOS 14+, Swift tools 6.0, no test target, no linter. CI and release need the macOS 26 SDK (`glassEffect`).

## Do not violate

- **Panel frame while a card opens:** do not resize the window and do not put card + rail in a shared stack. Axis change (side ↔ top) *may* resize. [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md)
- **Hover:** SwiftUI `.onHover` does not work on this accessory, non-key panel. Enter from tracking areas, leave from sampling the pointer — never exit events. Drag and ring clicks belong to `FloatingPanel.sendEvent`. `hitTest` / synthesised events are not proof of real input. [Docs/ui/input.md](Docs/ui/input.md)
- **Percentages:** Pulse does not invent usage percentages. If a provider reports none, say so. The money estimate is the labelled exception. [Docs/refresh-and-data.md](Docs/refresh-and-data.md)
- **Localization:** only `String.localized(_:)` / `Text(localized:)`. No implicit `Text("…")`. No conditionals inside `localized:`. Interpolate `String`, not `Int` (`%lld` vs `%@`). Run `./Scripts/check-localization.sh`. [Docs/development.md](Docs/development.md)
- **Disabled providers are not fetched.** Shared `Unavailability` copy names no provider.
- **Layout constants are budgets** (`PanelMetrics` computed `var`, never `static let`). Anything new on the panel takes size from them.
- **Do not fetch or document provider auth here.** [Docs/providers/README.md](Docs/providers/README.md)

## Read by task

| Task | Read |
|---|---|
| Shell, settings, login, defaults | [Docs/architecture.md](Docs/architecture.md) |
| Panel size, dock, overlay, scale | [Docs/ui/panel-geometry.md](Docs/ui/panel-geometry.md) |
| Drag, hover, clicks, hit testing | [Docs/ui/input.md](Docs/ui/input.md) |
| Glass, rings, colour, activity mark | [Docs/ui/rings-and-surface.md](Docs/ui/rings-and-surface.md) |
| Settings window copy/layout | [Docs/ui/settings.md](Docs/ui/settings.md) |
| Refresh, cache, activity, ledger | [Docs/refresh-and-data.md](Docs/refresh-and-data.md) |
| Localization, resources, adding UI | [Docs/development.md](Docs/development.md) |
| Bundle, tag, Sparkle, DMG | [Docs/releasing.md](Docs/releasing.md) / [Docs/build-from-source.md](Docs/build-from-source.md) |
| Why / failure lessons | [Docs/decisions/README.md](Docs/decisions/README.md) |
| Provider routes / extra accounts | [Docs/providers/README.md](Docs/providers/README.md) |

## Current facts (verify in code if they matter)

Fourteen `Provider` cases. Extra accounts: Claude Code, Codex, Grok, Grok Bot (`supportsMultipleAccounts`). Adaptive refresh is a **one-shot** timer, **2–30 minutes** (`AdaptiveRefresh.floor` 120s / `ceiling` 1800s) — not a 60s loop. Liquid Glass drag: historical “material swallows input” diagnosis is **uncertain**; current approach is a hit-testable `PanelSurface` plus window `sendEvent`. Real-input verification is not claimed. Settings still say to drag by a ring while glass is on.
