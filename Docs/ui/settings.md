# Settings window

Chrome and why it is AppKit-owned: [../architecture.md](../architecture.md). Localization rules: [../development.md](../development.md).

`SettingsView` / `SettingsRow`: `NavigationSplitView` source list, panes from `SettingsGroup` + `SettingsRow` (title + optional subtitle left, control right). `SettingsPane` includes `.account(AccountKey)`, so every account — each provider’s first, plus any added login — has a sidebar row.

The sidebar is `.searchable(placement: .sidebar)` — **not** `.automatic`: this window has no `NSToolbar`, so automatic placement has nowhere to put the field. Accounts match on the provider's name *as well as* the user's label, so a second Claude subscription called "工作" is still found by typing "claude". Matching is `localizedStandardContains` (case- and accent-insensitive, the same comparison Finder searches with). A section with no matches is omitted; nothing matching at all leaves a "No matches" line. The current selection is not cleared by a search that hides it — you keep your place.

## Provider chooser

`ProviderSetupView` is shared by initial setup and upgrade suggestions. Each provider is a native checkbox with its name, a presence-only **Detected on this Mac** hint, and the access description from `ProviderAccess`. Detected rows come first, names sort within each group, and every checkbox starts off. **Select detected services** is an explicit action. The list scrolls while the explanation and buttons stay visible. These access descriptions may wrap: they must be readable before a service is selected.

On initial setup, **Done** is disabled until at least one is selected; closing the window leaves monitoring stopped. On an upgrade, the chooser only contains newly supported detected providers and may be completed with none selected. Existing choices continue to run. Restoration and dismissal rules: [../architecture.md](../architecture.md#provider-choice-before-monitoring).

Settings stays reachable after dismissing the initial chooser. General points to the provider panes; a disabled primary provider displays the same access description above **Show in panel**. Enabling it starts monitoring. Connection, sign-in, diagnostics and usage controls appear after the initial choice. Merely opening a disabled pane does not preload its saved key, read its history, or start Codex's app server.

## Copy

**Subtitles are one line.** Say what the control does. Reasoning belongs in docs, not on screen. Exceptions: the money card’s provenance and the estimate caption — those exist so an inferred figure is not read as reported.

A joined sentence needs no extra space after a Chinese full stop (`。`). `glassSubtitle` only inserts a separator when the first half does not end in one.

While Liquid Glass is on, the caption still says to drag the panel by a ring. That is current UI. The historical “glass swallows input” diagnosis is uncertain; [rings-and-surface.md](rings-and-surface.md).

Group order in the general pane: **Floating panel → Notifications → Refresh → Network → Order → Application → Shortcuts → Language**. The groups that decide what Pulse does *on its own* sit directly under the panel group, above the housekeeping ones. Notifications was added at the bottom, between Refresh and Language, and that was too far down to find — the panel group alone is sixteen rows. Network follows Refresh because both decide how Pulse gets a new reading. [../networking.md](../networking.md)

**Turn red at** lives at the foot of that group: `AppSettings.warningThreshold`, a picker of 60–90%. It moves only the amber→red step; spent is the provider's word and is red whatever the picker says, which is what its subtitle is for. The picker keeps its localized title for accessibility even though its visible label is supplied by the row. [rings-and-surface.md](rings-and-surface.md)

**Alert colour when docked** follows it: `AppSettings.dockShowsAlertColor`, on by default. It only gates `FloatingUsagePanelView.alertTint`, the colour the *collapsed sliver* takes on — the rings are unaffected, and are not switched by this row. A rail where several accounts sit past the threshold at once otherwise leaves the sliver coloured for as long as it is watched, which against a screen edge reads as a fault rather than a warning; off locks the sliver to its normal, alert-free colour. [rings-and-surface.md](rings-and-surface.md)

The usage-interval group is named **Refresh**, not Updates.

**Shortcuts** sits with Application because both are about the app rather than about a reading, and above Language because Language is the last thing anybody looks for. Two rows, both empty until set, each a `ShortcutField`: click it, press the combination, ⎋ leaves it alone and ⌫ takes it away. The subtitle is the row's own line **unless** the window server refused the combination, in which case the clash takes the line over — that is the only thing the monitor knows and the pane does not. Setting one writes the setting and calls `GlobalShortcutMonitor.apply` there and then; shortcuts deliberately do **not** go through `AppSettings.onChange`, which refetches every provider. Rules and why hot keys rather than an event tap: [input.md](input.md).

An account pane grows a **Notifications** group of its own where `Provider.reportsSpendableBalance` is true — a "warn below" figure in money. Not a row under Connection, which is about credentials and routes, and not in the general pane's Notifications group either: the figure is per account, because the providers that report a balance do not price in the same currency. [../notifications.md](../notifications.md)

The general pane's **Notifications** group's three controls are not independent of each other: the reset toggle is greyed out while the threshold is Off, because a reset is only announced for a window that was warned about, and every control is greyed out in an unbundled build. Its subtitle reports `UNAuthorizationStatus`, not the switches. Rules: [../notifications.md](../notifications.md).

## Controls

The **Token spend** pane starts with **Read local usage records**, off by default on both fresh installs and upgrades. While off it shows only that control and its scan explanation. Enabling shows the normal span/results UI and starts a read; progress names the current source and its index. Sidebar round trips keep and immediately display the last completed result without checking files again; **Rescan** updates it. Leaving cancels an unfinished read, which is retried on return. Turning reading off or closing Settings releases the snapshot and derived summaries, including when another pane is selected at close. Account-history cards are independent. Reader checkpoints, cache behaviour and memory measurements: [../token-spend.md](../token-spend.md).

Card borders are decorative and ignore hit testing, so they cannot cover the controls or the charts' full-height hover targets. Chart readouts: [../token-spend.md](../token-spend.md), [../refresh-and-data.md](../refresh-and-data.md).

The manual proxy host and port are view-local text while they are being edited. Return or leaving either field tries the pair; only a non-empty host and a whole port from 1 through 65535 replace the saved endpoint. Invalid text stays visible with the explanation on its own row, and never refetches on each keystroke.

SwiftUI `Picker` / `Menu` on macOS **cannot be given a width**. `.frame`, min/max, `fixedSize`, and a fixed-width custom label were measured (historical) and none moved the control. Right-align at `SettingsLayout.controlWidth` as a *ceiling*; long labels truncate. An `NSPopUpButton` wrapper did give a true 180pt box and was removed: short labels floated in empty chrome. Don’t rebuild it without checking that first.

Sidebar column: **min 200, ideal 240, max 320**. Sized to "Xiaomi Coding Plan", the longest name in the list at eighteen characters, with "GitHub Copilot" behind it — at the original 170/180/220 the long ones truncated to an ellipsis, on a list whose only job is telling nineteen products apart. `ideal` went 200 → 240 when the eighteen-character name arrived; it is scaled from the fourteen-character one that fit rather than measured against a render, so a name longer than this wants checking in the running app rather than arithmetic. They are brand names, so the requirement does not move with the language. `min` is the half that matters: AppKit saves the divider position, so `ideal` is read once per install while `min` clamps everyone.

Default window: **920 × 660**, set on the `NSWindow`'s `contentRect`; the view's `minWidth` / `minHeight` (720 × 460) are what it can be dragged down to. It opened at 760 × 500 when the sidebar held four rows — with nineteen providers and a six-group general pane that meant a window that was scrolling in both columns the moment it appeared. The size is not remembered across launches: the window is rebuilt and `center()`ed on each one.

`ImageRenderer` cannot draw this window (split view + AppKit controls). Check by running the app.

## About

Two groups. The first is the app: version and update state, where the usage figures come from, and the **source address** — the URL itself as the subtitle rather than a sentence about it, because half the people reading that row will want to type it rather than click it.

The second is **Credits**, and anything shipped here that somebody else made belongs in it: the design it was built from, the provider marks, and the animated marks' geometry ([../decisions/bot-mark-geometry.md](../decisions/bot-mark-geometry.md)). Crediting the icons and not the vendored artwork beside them would be the inconsistency, not the extra row.

## Provider panes

A provider with one route has that route **named**, and the name belongs to the provider (`Provider.soleRoute`). A ternary (Cursor vs else Antigravity) made the next single-route provider inherit Antigravity’s sentence. Exhaustive `Provider` switch; omit the row when nil.

Each pane has its own refresh, with last-reading time. Rail click is not the only way.

Per-account rows live here rather than on the Panel pane, because they are choices about *one ring*: ring colour, the animated mark, and that mark's personality, colour and shape ([rings-and-surface.md](rings-and-surface.md)). All four are stored keyed by account id, and all four store "off" / "automatic" / "round" as an absent key rather than as a value. The personality and shape rows appear only while that account's mark is on — controls over something invisible otherwise, the same rule the colour well follows.

Each account also has a **Connection diagnostics** group immediately after Connection: latest check, check time, last successful reading, actual source of displayed figures, explicit cache use, and expandable route checks. A failed check stays visible even when the card displays cached figures. Retry asks only that account; diagnostic copy contains allowlisted metadata ([../refresh-and-data.md](../refresh-and-data.md)). The contextual next step focuses the credential field, reconnects the status line, starts the existing sign-in, reads the chosen browser, opens the relevant app, copies a login command, or opens setup help. Provider-specific action mappings live in [../providers/README.md](../providers/README.md).

Added accounts have a **Sign in again** control; successful reauthentication replaces credentials in the selected slot, preserving its name and display preferences. They do not show ambient CLI source controls that their fetch ignores. A cancelled sign-in or an account removed while sign-in is pending is not written back. One extra-account sign-in runs at a time, and its **Cancel**, device code and error rows appear only on the panes of the provider it was started for; other multi-account panes show a disabled **Sign in…** until it finishes. Provider-specific flows are documented in [../providers/authentication.md](../providers/authentication.md).

The sidebar's Application section includes **Developer integrations**. It copies the actual executable's `--json` command with shell quoting, exports the bundled developer kit into a new `Pulse Integrations` folder, and copies links or `open` commands for any configured account. Exports refuse an existing destination and exclude dependency/build folders. Install instructions: [../integrations.md](../integrations.md).

The Panel group's rows are per account: show, "Ring shows", ring colour — and, only where `Provider.splitsByModelGroup` is true, **"A ring for each model group"**. Drawn behind that flag rather than always with an explanation, because a switch that promises a second ring it can never draw is worse than no switch. Off by default; it costs a slot on the rail, and the rail is the whole of the panel when docked. [rings-and-surface.md](rings-and-surface.md)

The sidebar's accounts start in **name order**, not in the order `Provider` happens to be written in — nineteen rows arranged by nothing a reader can see is a list you have to scan rather than one you can look in. An arrangement somebody actually made is kept as it is, and anything it does not mention follows it sorted by name; an added account sorts by its own label, because that is what is written on the row. `AppSettings.orderedAccounts`.

Reorder by **dragging a row, or with the arrows** — both, deliberately. It was arrows only, on the reasoning that four rows is not enough to make a drag worth learning and that an arrow which misses does nothing while a drag which misses does something. The first half stopped being true at nineteen providers plus added accounts: bottom to top is eighteen clicks. The arrows stay because they are the precise one-place move, the only keyboard path, and the only one carrying accessibility labels.

A **Reset order** row closes the group, disabled unless `hasCustomOrder` — which compares the accounts, not whether anything is stored, because dragging a row down and back up leaves a full stored list that matches the default exactly. `resetOrder()` clears `providerOrder` rather than writing the default into it, so a provider added in a later version still arrives at the bottom of the rail instead of being pinned by a list written before it existed.

`AppSettings.move(_:onto:)` is "take its place": the dragged row is removed first, so dropping downward lands after the target and upward lands before it — both being what the pointer was pointing at. The payload is the account id as a plain `String`, so a text drag from another app can light a row up as a target; the drop is then rejected (`AccountKey(id:)` fails, or the id names no account Pulse has). A custom `UTType` would stop the highlight too, but only declared in the bundle's `Info.plist`, which would make `swift run` behave differently from the shipped app for a cosmetic case.

A first account that needs a credential Pulse hasn’t got is seeded with the reason, not `.loading`. `loadAPIKeys` rewrites that only over a placeholder.

Extra-account UI is only for `supportsMultipleAccounts` (Claude Code, Codex, Grok, Grok Bot). How sign-in works: [../providers/README.md](../providers/README.md).
