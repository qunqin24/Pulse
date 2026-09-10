# Settings window

Chrome and why it is AppKit-owned: [../architecture.md](../architecture.md). Localization rules: [../development.md](../development.md).

`SettingsView` / `SettingsRow`: `NavigationSplitView` source list, panes from `SettingsGroup` + `SettingsRow` (title + optional subtitle left, control right). `SettingsPane` includes `.provider(_:)` so each provider has a sidebar row.

The sidebar is `.searchable(placement: .sidebar)` — **not** `.automatic`: this window has no `NSToolbar`, so automatic placement has nowhere to put the field. Accounts match on the provider's name *as well as* the user's label, so a second Claude subscription called "工作" is still found by typing "claude". Matching is `localizedStandardContains` (case- and accent-insensitive, the same comparison Finder searches with). A section with no matches is omitted; nothing matching at all leaves a "No matches" line. The current selection is not cleared by a search that hides it — you keep your place.

## Copy

**Subtitles are one line.** Say what the control does. Reasoning belongs in docs, not on screen. Exceptions: the money card’s provenance and the estimate caption — those exist so an inferred figure is not read as reported.

A joined sentence needs no extra space after a Chinese full stop (`。`). `glassSubtitle` only inserts a separator when the first half does not end in one.

While Liquid Glass is on, the caption still says to drag the panel by a ring. That is current UI. The historical “glass swallows input” diagnosis is uncertain; [rings-and-surface.md](rings-and-surface.md).

Group order in the general pane: **Floating panel → Notifications → Refresh → Order → Application → Language**. The two groups that decide what Pulse does *on its own* sit directly under the panel group, above the housekeeping ones. Notifications was added at the bottom, between Refresh and Language, and that was too far down to find — the panel group alone is fifteen rows.

The usage-interval group is named **Refresh**, not Updates.

An account pane grows a **Notifications** group of its own where `Provider.reportsSpendableBalance` is true — a "warn below" figure in money. Not a row under Connection, which is about credentials and routes, and not in the general pane's Notifications group either: the figure is per account, because the providers that report a balance do not price in the same currency. [../notifications.md](../notifications.md)

The general pane's **Notifications** group's three controls are not independent of each other: the reset toggle is greyed out while the threshold is Off, because a reset is only announced for a window that was warned about, and every control is greyed out in an unbundled build. Its subtitle reports `UNAuthorizationStatus`, not the switches. Rules: [../notifications.md](../notifications.md).

## Controls

SwiftUI `Picker` / `Menu` on macOS **cannot be given a width**. `.frame`, min/max, `fixedSize`, and a fixed-width custom label were measured (historical) and none moved the control. Right-align at `SettingsLayout.controlWidth` as a *ceiling*; long labels truncate. An `NSPopUpButton` wrapper did give a true 180pt box and was removed: short labels floated in empty chrome. Don’t rebuild it without checking that first.

Sidebar column: **min 200, ideal 220, max 320**. Sized to "GitHub Copilot", the longest name in the list at fourteen characters, with "Command Code" and "Ollama Cloud" behind it — at the previous 170/180/220 they truncated to an ellipsis, on a list whose only job is telling seventeen products apart. They are brand names, so the requirement does not move with the language. `min` is the half that matters: AppKit saves the divider position, so `ideal` is read once per install while `min` clamps everyone.

Default window: **920 × 660**, set on the `NSWindow`'s `contentRect`; the view's `minWidth` / `minHeight` (720 × 460) are what it can be dragged down to. It opened at 760 × 500 when the sidebar held four rows — with seventeen providers and a six-group general pane that meant a window that was scrolling in both columns the moment it appeared. The size is not remembered across launches: the window is rebuilt and `center()`ed on each one.

`ImageRenderer` cannot draw this window (split view + AppKit controls). Check by running the app.

## Provider panes

A provider with one route has that route **named**, and the name belongs to the provider (`Provider.soleRoute`). A ternary (Cursor vs else Antigravity) made the next single-route provider inherit Antigravity’s sentence. Exhaustive `Provider` switch; omit the row when nil.

Each pane has its own refresh, with last-reading time. Rail click is not the only way.

The Panel group's rows are per account: show, "Ring shows", ring colour — and, only where `Provider.splitsByModelGroup` is true, **"A ring for each model group"**. Drawn behind that flag rather than always with an explanation, because a switch that promises a second ring it can never draw is worse than no switch. Off by default; it costs a slot on the rail, and the rail is the whole of the panel when docked. [rings-and-surface.md](rings-and-surface.md)

The sidebar's accounts start in **name order**, not in the order `Provider` happens to be written in — seventeen rows arranged by nothing a reader can see is a list you have to scan rather than one you can look in. An arrangement somebody actually made is kept as it is, and anything it does not mention follows it sorted by name; an added account sorts by its own label, because that is what is written on the row. `AppSettings.orderedAccounts`.

Reorder by **dragging a row, or with the arrows** — both, deliberately. It was arrows only, on the reasoning that four rows is not enough to make a drag worth learning and that an arrow which misses does nothing while a drag which misses does something. The first half stopped being true at seventeen providers plus added accounts: bottom to top is sixteen clicks. The arrows stay because they are the precise one-place move, the only keyboard path, and the only one carrying accessibility labels.

A **Reset order** row closes the group, disabled unless `hasCustomOrder` — which compares the accounts, not whether anything is stored, because dragging a row down and back up leaves a full stored list that matches the default exactly. `resetOrder()` clears `providerOrder` rather than writing the default into it, so a provider added in a later version still arrives at the bottom of the rail instead of being pinned by a list written before it existed.

`AppSettings.move(_:onto:)` is "take its place": the dragged row is removed first, so dropping downward lands after the target and upward lands before it — both being what the pointer was pointing at. The payload is the account id as a plain `String`, so a text drag from another app can light a row up as a target; the drop is then rejected (`AccountKey(id:)` fails, or the id names no account Pulse has). A custom `UTType` would stop the highlight too, but only declared in the bundle's `Info.plist`, which would make `swift run` behave differently from the shipped app for a cosmetic case.

A first account that needs a credential Pulse hasn’t got is seeded with the reason, not `.loading`. `loadAPIKeys` rewrites that only over a placeholder.

Extra-account UI is only for `supportsMultipleAccounts` (Claude Code, Codex, Grok, Grok Bot). How sign-in works: [../providers/README.md](../providers/README.md).
