# Settings window

Chrome and why it is AppKit-owned: [../architecture.md](../architecture.md). Localization rules: [../development.md](../development.md).

`SettingsView` / `SettingsRow`: `NavigationSplitView` source list, panes from `SettingsGroup` + `SettingsRow` (title + optional subtitle left, control right). `SettingsPane` includes `.provider(_:)` so each provider has a sidebar row.

## Copy

**Subtitles are one line.** Say what the control does. Reasoning belongs in docs, not on screen. Exceptions: the money card’s provenance and the estimate caption — those exist so an inferred figure is not read as reported.

A joined sentence needs no extra space after a Chinese full stop (`。`). `glassSubtitle` only inserts a separator when the first half does not end in one.

While Liquid Glass is on, the caption still says to drag the panel by a ring. That is current UI. The historical “glass swallows input” diagnosis is uncertain; [rings-and-surface.md](rings-and-surface.md).

The usage-interval group is named **Refresh**, not Updates.

## Controls

SwiftUI `Picker` / `Menu` on macOS **cannot be given a width**. `.frame`, min/max, `fixedSize`, and a fixed-width custom label were measured (historical) and none moved the control. Right-align at `SettingsLayout.controlWidth` as a *ceiling*; long labels truncate. An `NSPopUpButton` wrapper did give a true 180pt box and was removed: short labels floated in empty chrome. Don’t rebuild it without checking that first.

`ImageRenderer` cannot draw this window (split view + AppKit controls). Check by running the app.

## Provider panes

A provider with one route has that route **named**, and the name belongs to the provider (`Provider.soleRoute`). A ternary (Cursor vs else Antigravity) made the next single-route provider inherit Antigravity’s sentence. Exhaustive `Provider` switch; omit the row when nil.

Each pane has its own refresh, with last-reading time. Rail click is not the only way.

Reorder with arrows, not dragging.

A first account that needs a credential Pulse hasn’t got is seeded with the reason, not `.loading`. `loadAPIKeys` rewrites that only over a placeholder.

Extra-account UI is only for `supportsMultipleAccounts` (Claude Code, Codex, Grok, Grok Bot). How sign-in works: [../providers/README.md](../providers/README.md).
