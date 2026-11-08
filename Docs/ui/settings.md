# Settings window

Chrome and why it is AppKit-owned: [../architecture.md](../architecture.md). Localization rules: [../development.md](../development.md).

`SettingsView` / `SettingsRow`: a `NavigationSplitView` source list, panes built from `SettingsGroup` + `SettingsRow` (title and optional subtitle on the left, control on the right; `controlBelow: true` puts the control under the label). **A choice in a settings row is a pop-up menu** (`.pickerStyle(.menu)`), as in System Settings, never a segmented control: one control everywhere, and a menu fits beside its label however many options it has (Position's six segments had to move under the label to fit). Segmented controls are kept for switching what a view shows — Token activity's view, the recap's Month / Year. `SettingsPane` includes `.account(AccountKey)`, so every account — each provider's first, plus any added login — has a sidebar row.

## Where the code lives

All of it is in `Sources/Pulse/Settings`. `SettingsView.swift` is the shell only: the split view, the window's title and back/forward toolbar (the pane's name is the title — no heading is drawn in the pane), the switch that picks a pane, the search text, and the three models below. A pane is a view that draws rows; what a pane edits through a button is in a model.

| File | Holds |
|---|---|
| `SettingsView.swift` | Shell. Owns `search`, `SpendPaneModel`, `AccountHistoryModel`, `AccountFlows`; sets the sidebar column's width and search field (properties of that column); runs the three tasks below. |
| `SettingsSidebar.swift` | The source list: sections, the search match, the "No matches" line. |
| `SettingsPane.swift` | `SettingsPane` (title, symbol, search terms, the sidebar's fixed sections) and `Provider.Billing.sectionTitle`. |
| `AppearancePane.swift`, `RingsPane.swift`, `PlacementPane.swift`, `GeneralPane.swift`, `NotificationsPane.swift`, `NetworkPane.swift`, `AboutPane.swift` | One fixed pane each, with its own state (the order list's drag target, the login-item nudge, the proxy text fields). |
| `TokenSpendPane.swift`, `SpendPaneModel.swift` | The Token spend pane (switch, recap buttons, `TokenSpendView`) and its reading: combined and per-agent figures, scan progress, the drilled-in agent and model. |
| `AccountPane.swift` | One account's pane: the cards in order, and the seed of the typed fields when the account or its switch changes. |
| `AccountPanelGroup.swift` | Panel card: show in panel, ring window, split, Codex reset credits, detailed card (`detailedCardSubtitle`), ring colour, robot in the ring. |
| `WindowStarterGroup.swift` | Claude Code / Codex window starter and its risk confirmation. |
| `AccountConnectionGroup.swift`, `AccountConnectionRows.swift` | Connection card: route picker, Copilot sign-in, key field, browser read, and the single rows it draws (site, server address, balance basis, full tank, warn below). Scrolls and focuses itself when a remedy names a field. |
| `AccountsGroup.swift` | Another subscription of the same provider: sign in, rename, remove. |
| `ClaudeCodeStatusLineRow.swift`, `AccountLiveUsageGroup.swift` | The status-line switch, and the Current usage card. |
| `AccountHistoryGroup.swift`, `EstimatedValueGroup.swift`, `AccountHistoryModel.swift` | Usage history, the money estimate, and the ledgers and read results behind them. |
| `AccountFlows.swift` | Builds and wires the four models below. |
| `ProviderCredentialModel.swift` | The key field, reveal, saved key; save, browser read (cookie or local storage), what the read said. |
| `ProviderSignInModel.swift` | Added-account sign-in (browser or device code) and Copilot's GitHub device flow, with their prompts, errors and cancellation. Also `SettingsClipboard`. |
| `ConnectionRepairModel.swift` | What each diagnostics remedy does, the line it leaves, the scroll-and-focus requests, the status-line nudge. |
| `AccountEntryFields.swift` | Server address, full-tank figure and warn-below figure, as text committed on Save; `hasBalanceRing` / `reportsBalance`. |

**A model is the shell's when its state must outlive the pane** — a device-code sign-in polls for fifteen minutes, a browser read may wait on a keychain dialog, the ledgers are kept while the window is open — so switching panes neither discards it nor orphans the task writing to it. A pane's own state stays in the pane and resets with it.

**Three tasks stay on the shell's scroll view** — history (`AccountHistoryModel.key`), Token spend reading (`SpendPaneModel.loadKey`) and its summary (`summaryRequest`). Their keys include the selected pane and the window's visibility, and the release path (leave the pane, switch reading off, close the window) runs only if a task is still alive to see the key change. Moving one into a pane view would silently drop that path.

**A new pane** is a view in its own file, a `SettingsPane` case (`title`, `symbol`, `searchTerms`), and one line in the shell's `switch`.

**Search.** The sidebar is `.searchable(placement: .sidebar)`, **not** `.automatic`: the field belongs at the top of the list, under the traffic lights, as in System Settings; automatic would put it in the window's toolbar, which carries only the title. Accounts match on the provider's name *as well as* the user's label (a second Claude subscription called "工作" is found by typing "claude"); a pane matches by its title **or** any of its rows' titles (`SettingsPane.searchTerms` — keep it in step when a row moves or is added). Matching is `localizedStandardContains` (case- and accent-insensitive, as Finder searches). A section with no matches is omitted; nothing matching leaves a "No matches" line. A search that hides the current selection does not clear it.

**Accounts start in name order** (`AppSettings.orderedAccounts`), not declaration order, so seventy-odd rows can be looked up rather than scanned. An arrangement somebody made is kept, with unmentioned accounts after it by name; an added account sorts by its own label.

## Provider chooser

`ProviderSetupView` is shared by initial setup and upgrade suggestions. Each provider is a native checkbox with its name, a presence-only **Detected on this Mac** hint, and its access description (`Provider.monitoringAccessDescription`, in `ProviderAccess.swift`). Providers are listed in the sidebar's two groups, subscriptions first, each group detected-first then by name; every checkbox starts off, and **Select detected services** is an explicit action. The list scrolls while the explanation and buttons stay visible. Access descriptions may wrap: they must be readable before a service is selected.

On initial setup, **Done** is disabled until at least one is selected; closing the window leaves monitoring stopped. On an upgrade, the chooser lists only newly supported detected providers and may be completed with none selected; existing choices keep running. Restoration and dismissal: [../architecture.md](../architecture.md#provider-choice-before-monitoring).

Settings stays reachable after dismissing the initial chooser; Appearance points to the provider panes. A disabled primary provider's pane shows the same access description above **Show in panel**; enabling it starts monitoring. Its connection, sign-in, diagnostics and usage controls appear after the initial choice, but Current usage says **Not shown** and Retry is unavailable while it is off. Opening a disabled pane does not preload its saved key, read its history, or start any provider request or Codex's app server.

## Copy

**Subtitles are one line.** Say what the control does; reasoning belongs in docs. Exceptions: the money card's provenance and the estimate caption, which exist so an inferred figure is not read as reported.

**A joined sentence needs no extra space after a Chinese full stop (`。`).** `UsageAlerts.joined` inserts a separator only when the first half does not end in one.

## Panes

The former single General pane is split by subject (`SettingsPane`). Panel and Application sit **above** the accounts because they are what Settings is opened for (under twenty-odd provider rows they were below the fold); Integrations and About are rarely visited and stay below. The window opens on **Appearance**, the first row (`SettingsNavigation.pane`, and the `pulse://settings` link).

| Sidebar section | Pane | Holds |
|---|---|---|
| Panel | **Appearance** | Size, Spacing, Round ends, Progress bars (Continuous / Segmented, `UsageBarStyle`; the card's and the menu's limit bars), Panel colour, Liquid Glass (+ Transparency), Ring activity animation |
| Panel | **Rings and figures** | *Figures*: percentages at the side / across (*Percentages across*: any rail lying across — docked to the top or bottom, or free), figures beside the rings (free across only, off by default; needs percentages across), figure above the ring, show what's left, forecast. *Rings*: second limit inside the ring, time until reset, time ring direction, turn red at, alert colour when docked |
| Panel | **Position and behavior** | Show floating panel, hide in full screen, hide from screenshots, hide until pointed at, position (Left, Top, Bottom, Free across, Free upright, Right), snap to screen edges, follow the active display; **Order** |
| Panel | Token spend | Below |
| Application | **General** | *Application*: open at login, show Dock icon, hide menu bar icon, show usage in the menu bar (+ menu bar shows, menu bar style), usage panel in the menu. *Shortcuts*. *Language* |
| Application | **Notifications** | Warn at, when a limit comes back, when a reading stops arriving, when a service is down, when a recap is ready |
| Application | **Network and refresh** | Check every; proxy ([../networking.md](../networking.md)) |
| Application | **Experimental** | Liquid docking (off by default; [panel-geometry.md](panel-geometry.md#liquid-docking-experimental)); a line saying these may change or go |
| Enabled | every account switched on, both kinds, in rail order | What somebody opens Settings for, first. An enabled account is not listed again below — two rows with one selection tag highlight together |
| Subscriptions | one per subscription account not switched on | Split from API accounts by `Provider.Billing`: a plan with limits that turn over on a clock |
| API and pay-as-you-go | one per API account not switched on | Money put in and drawn down by the call — DeepSeek, the gateways, the API platforms. A provider with both is filed under the one its buyers mostly pay for |
| Extensions | **Manage extensions**, then one per extension found | The folder, **Look again**, what was found, and every folder that couldn't be used with the reason. An extension's own pane is an account pane plus an **Extension** group: program, time limit, id. Once it has reported a balance, it also gets **Ring measures** (with no limits beside it) and **Warn below**, as an API account does. [../extensions.md](../extensions.md) |
| (untitled, last) | Developer integrations, About | Below |

**Extensions have a section of their own** because they are programs somebody added, not services Pulse ships. A switched-off extension's pane shows its access description above **Show in panel**, like a disabled provider's. **Manage extensions** rescans the folder when it opens, which runs nothing.

### Appearance

- **Round ends** (`AppSettings.usesRoundEnds`, **off** by default; off is the rail Pulse shipped with) sits with Size and Spacing because it changes what the rail measures. It is one switch over the rail's ends, the flare into the screen edge, the end padding and the card's tail: split, a round end could sit on the other style's padding, the first ring hard against the curve it should be centred in. [panel-geometry.md](panel-geometry.md)
- **Panel colour** (Black / Light, `usesLightPanel`, #74) sits above Liquid Glass and is always shown, greyed out while glass is on because glass is always drawn dark.
- **Liquid Glass** is the name in every language (zh-Hans 液态玻璃); it was briefly 毛玻璃 while the glass rendered inactive and really was frosted ([../decisions/liquid-glass.md](../decisions/liquid-glass.md)). While it is on, a **Transparency** slider appears under it (`glassTransparency`, 0–1, default 0.5): right is clearer, left dims the glass. It sets no `onChange`, which refetches every provider, because a slider fires continuously.
- **Ring activity animation** (`AppSettings.animatesRingActivity`, on by default) closes the pane. It gates the two turning marks — white for a working CLI, the usage colour for a fetch — not whether Pulse tracks either fact. [rings-and-surface.md](rings-and-surface.md#activity-mark)

### Rings and figures

- **Time ring direction** follows **Time until reset** and is disabled while the clock is off: a two-way menu, elapsed (the default, so existing installations do not reverse) or remaining (starts full, empties toward reset). It changes only the neutral outer arc, independently of **Show what's left**, which controls the coloured ring and its figure. [rings-and-surface.md](rings-and-surface.md#window-clock-arc)
- **Turn red at** (`AppSettings.warningThreshold`, 60–90%) moves only the amber→red step; spent is the provider's word and red whatever the picker says, which its subtitle states. The picker keeps its localized title for accessibility although the row supplies the visible label.
- **Alert colour when docked** (`AppSettings.dockShowsAlertColor`, on by default) closes the Rings group. It gates only `FloatingUsagePanelContent.alertTint` — the collapsed sliver's colour, or at a physical notch the thin edge below the housing; the rings are unaffected. [rings-and-surface.md](rings-and-surface.md#colour-and-spent)

### Position and behavior: Order

- **The Order group lists only the accounts switched on** — listing every provider, the rest marked "Not shown", buried the few being arranged. Moves reorder the shown ones (`AppSettings.move`); switched-off accounts keep their order behind them, so one switched on later arrives at the end of the rail.
- **Reorder by dragging a row or with the arrows.** Dragging is needed at seventy-odd providers (bottom to top was already twenty-four clicks at twenty-five); the arrows stay as the precise one-place move, the only keyboard path, and the only one with accessibility labels.
- **`AppSettings.move(_:onto:)` is "take its place"**: the dragged row is removed first, so dropping downward lands after the target and upward before it. The payload is the account id as a plain `String`, so a text drag from another app can highlight a row, and the drop is then rejected (`AccountKey(id:)` fails, or the id names no account). A custom `UTType` would stop the highlight but must be declared in the bundle's `Info.plist`, making `swift run` differ from the shipped app for a cosmetic case.
- **Reset order** closes the group, disabled unless `hasCustomOrder` — which compares the accounts, not whether anything is stored, since dragging a row down and back up stores a list equal to the default. `resetOrder()` clears `providerOrder` rather than writing the default into it, so a provider added in a later version still arrives at the bottom of the rail.

### General

**Application group:**

- **Open at login.**
- **Show Dock icon while Settings or a recap is open** (`AppSettings.showsDockIconInSettings`, **on by default**): Pulse is a regular app while either window is open and a menu bar app again when the last closes, through `DockPresence`.
- **Hide menu bar icon** (`AppSettings.hidesMenuBarIcon`, off by default) removes only the AppKit status item; the floating panel's secondary-click menu or a successfully registered global shortcut still opens Settings. If neither remains, hiding the icon shows the panel first; before the initial provider choice, where there is no panel, the request is refused. Hiding that panel later, clearing the last shortcut, a registration conflict, or restoring an unsafe saved combination brings the icon back. Changing it does not refresh provider data.
- **Show usage in the menu bar** (`AppSettings.showsUsageInMenuBar`, off by default; greyed out while the icon is hidden): the status item shows the fullest ring's mark and figure (following **used / left**), red past the warning line, with the account and limit in its tooltip. While on, two rows follow. **Menu bar shows**: the fullest ring, or one account on the rail (`menuBarAccount`; an account switched off or removed falls back to the fullest). **Menu bar style** (`menuBarStyle`): **Figure**; a small **Ring** beside the mark; or **Split** — the account-wide timed limits side by side with short names, shortest first, at most two (`5h/9%  周/15%`), each red on its own past the warning line. Scoped limits (one model's week) are not split; an account with fewer than two falls back to the figure, and the ring needs a limit, so money and "no reading" stay text.
- **Usage panel in the menu** (`AppSettings.showsMenuDashboard`, **off by default**, the group's last row, greyed out while the icon is hidden): the menu bar item opens on a **dashboard** (`MenuDashboard`, a SwiftUI view hosted in the menu's first item), independently of **Show usage in the menu bar**. Off, the menu opens on **Refresh** and the plain items. Always on in 1.6.0; a switch since, as the largest thing Pulse puts on screen unasked.

**The menu dashboard:**

- **Tabs**: **Overview** and one per account on the rail, labelled while there are five or fewer, marks only past that; the menu remembers the tab (`MenuDashboardModel`).
- **Overview** lists every account: mark, name and figure, and beneath them the limit and its reset, red past the warning line, "No reading" rather than a zero. A row opens that account's tab.
- **An account's tab** shows its plan and how long ago it was read; every limit with a bar, its reset and used/left figure; Codex's reset credits; and what is left of a balance or of Codex's credits where reported (a **Credits** or **Balance** heading over "2500 remaining", with no bar, because no provider states the total — CodexBar's bar divides by a figure OpenAI does not report). Only with **Token spend** on, for the primary account of a provider that keeps local transcripts, it adds the four figures of the account's usage history in Settings (today, the last 31 days, the busiest day, all time; each estimated cost over tokens) and a daily token chart, labelled as an estimate at API prices. That ledger is read incrementally when the tab opens, and again when it opens more than five minutes later so "Today" stays today's (`MenuDashboardModel.ledgerLifetime`).
- **Below the dashboard**: **Open <provider> usage page** while an account's tab is open and `Provider.usagePage` knows one (a table in `UsagePages.swift`, pages only, never an API or Referer address), then **Refresh** (⌘R, a full pass), which stays with the dashboard off. Figures end on the edge the key equivalents do (`MenuDashboard.trailing`). The rail's own right-click menu has none of this.
- **Both menus carry Show floating panel**, checked while the rail is on screen (the Settings → Position switch). Hiding the panel when it and the icon were the last way back brings the icon back (`settingsChanged`). Reopening Pulse while it runs (Applications, Spotlight) opens Settings, or the chooser before a service is chosen (`applicationShouldHandleReopen`), so no combination is a dead end.

**Currency**, below Language (`CurrencySettingsGroup`): **Show estimates in** picks the currency of every estimate (`AppSettings.displayCurrency`, dollars by default); its subtitle says what is converted and that a service's own balances and charges are not. For any currency but the dollar, two more rows: **Exchange rate** ("1 USD = [field] CNY", the field's placeholder the day's rate; the subtitle says whose rate is used and when it was updated, or that estimates stay in dollars until there is one; a typed rate that is not a positive number is refused and the field goes back to the kept one) and **Rate source**, the "Rates By Exchange Rate API" link the source's terms ask for — a credit, written the same in every language. Rules: [../refresh-and-data.md](../refresh-and-data.md#currency).

**Shortcuts**, above Language: two rows, empty until set, each a `ShortcutField` — click, press the combination; ⎋ leaves it alone, ⌫ clears it. The subtitle is the row's own line **unless** the window server refused the combination, which then replaces it. Setting one writes the setting and calls `GlobalShortcutMonitor.apply` at once; after both actions are applied, its registration callback rechecks the app-entry rule above. Shortcuts deliberately do **not** go through `AppSettings.onChange`, which refetches every provider. Rules, and why hot keys rather than an event tap: [input.md](input.md).

### Notifications

Every control is greyed out in an unbundled build, and the reset toggle while the threshold is Off (a reset is announced only for a window that was warned about). **When a service is down** reads the providers' own status pages; its subtitle names no provider — any of the 44 with a page, switched-on ones only, and only what their accounts run on. **When a recap is ready** (`AppSettings.alertsOnRecap`, off by default) cannot be turned on while Token spend reading is off, since the month is known only from records Pulse has read (its subtitle says so); once on, it stays operable so it can be turned off. Switching it on does not call `reconsiderAlerts`: `AppSettings.onRecapAlertChange` asks for permission and checks the month. The first subtitle reports `UNAuthorizationStatus`, not the switches. Rules: [../notifications.md](../notifications.md).

An account pane gets a **Notifications** group of its own where `Provider.reportsSpendableBalance` is true: a "warn below" figure in money. It is per account, not in the Notifications pane, because providers that report a balance do not share a currency; and not under Connection, which is about credentials and routes. [../notifications.md](../notifications.md)

### Network and refresh

The usage-interval group is named **Refresh**, not Updates. The manual proxy host and port are view-local text while edited. Return or leaving either field tries the pair; only a non-empty host and a whole port from 1 through 65535 replace the saved endpoint. Invalid text stays visible with the explanation on its own row, and nothing refetches on each keystroke.

### Experimental

Features still being tuned, each off until switched on here, under a line saying they may change or be removed. A feature leaves this pane when it is settled: its switch moves to the pane its subject belongs to, or goes. **Liquid docking** (`AppSettings.liquidDocking`) is the only one so far.

### Token spend

The pane starts with **Read local usage records**, off by default on fresh installs and upgrades. While off it shows only that control and its scan explanation. Enabling it shows the span/results UI and starts a read; progress names the current source and its index. Returning from another pane shows the last completed result at once without checking files; **Rescan** updates it. Leaving cancels an unfinished read, retried on return. Turning reading off or closing Settings (whichever pane is selected) releases the snapshot and derived summaries. Account-history cards are independent. Under the headline total, a **Token activity** section shows the last twelve months as a daily grid, weekly bars or a running total (segmented control at its top right, kept in `AppSettings.spendActivityView`), whatever the span says; it is not drawn with no record in the year ([../token-spend.md](../token-spend.md#token-activity)). Reader checkpoints, cache behaviour and memory measurements: [../token-spend.md](../token-spend.md).

Once reading is on, the first group gains a **Usage recaps** row (zh-Hans 用量报告) with one **Open** button, which opens the recap window on the period it would open on by itself (`RecapPeriods.defaultMonth`). One button rather than one per period: the window switches between day, week, month and year itself, and a button for each repeated that control. The window's own controls (period, monthly price, hide project names, export) are in [../recap.md](../recap.md#the-window), next to the card they change.

### Developer integrations

In the sidebar's last, untitled section. It copies the actual executable's `--json` command with shell quoting, exports the bundled developer kit into a new `Pulse Integrations` folder, and copies links or `open` commands for any configured account. Exports refuse an existing destination and exclude dependency/build folders. Install instructions: [../integrations.md](../integrations.md).

## Controls

**Card borders are decorative and ignore hit testing**, so they cannot cover the controls or the charts' full-height hover targets. Chart readouts: [../token-spend.md](../token-spend.md), [../refresh-and-data.md](../refresh-and-data.md).

**SwiftUI `Picker` / `Menu` on macOS cannot be given a width.** `.frame`, min/max, `fixedSize` and a fixed-width custom label were measured (historical) and none moved the control. Right-align at `SettingsLayout.controlWidth` (180) as a *ceiling*; long labels truncate. An `NSPopUpButton` wrapper gave a true 180pt box and was removed because short labels floated in empty chrome; do not rebuild it without checking that first.

**The sidebar cannot be hidden** (`NavigationSplitView(columnVisibility: .constant(.all))`, `.toolbar(removing: .sidebarToggle)`). With SwiftUI's toggle, collapsing it and drawing it back at a width that could not hold sidebar and pane side by side overflowed both ways — the list past the left edge, the pane past the right — and the title bar showed an overflow "»". The sidebar is how the window is navigated, as in System Settings.

**Sidebar column: min 220, ideal 240, max 320**, sized to "Alibaba Coding Plan", the longest (brand) name (121.4pt of text at 13pt; "Xiaomi Coding Plan" 117.3), with the scroller always showing; at 200 it read "Alibaba Coding Pl…". `ideal` was scaled from a fourteen-character name that fit, not measured, so check a longer name in the running app. `min` matters most: AppKit saves the divider position, so `ideal` is read once per install while `min` clamps everyone.

**Bundled sidebar icons are the text's colour** (`SidebarRowLabelStyle` in `SettingsSidebar.swift`): black, white in dark mode. An extension's optional PNG retains its original colours. A source list tints its icons with the accent colour, and two dozen blue marks down the list read as links rather than as places. The row lays out its own icon and title rather than recolouring the sidebar's: a `.foregroundStyle` on the icon did not override the tint, and `.listItemTint(.fixed(.primary))` held only for the rows on screen when the window opened — rows scrolled into view later were blue again (both checked in the running app).

**Default window: 920 × 660**, set on the `NSWindow`'s `contentRect`; the view's `minWidth` / `minHeight` (720 × 460) are the drag-down limit. The former 760 × 500 scrolled in both columns on opening. The size is not remembered: the window is rebuilt and `center()`ed on each launch.

**`ImageRenderer` cannot draw this window** (split view + AppKit controls). Check by running the app.

## About

Two groups. The first is the app: version and update state, where the usage figures come from, the **source address**, with the URL itself as the subtitle so it can be typed, and **Star on GitHub**, always there whether or not the star request below was shown.

**Opening the pane checks for an update** (`AppUpdate.probe`, Sparkle's `checkForUpdateInformation`), unless a check or update is already running: no Sparkle window, only the Version subtitle changes ("Checking…", then the answer), so "up to date" is current. It runs **even with Check automatically off** — that switch covers Pulse's own schedule; opening About is the reader asking. **Check now** still puts up Sparkle's window.

The second group is **Credits**: anything shipped here that somebody else made — the design it was built from, the provider marks, and the robot (CX ArtLab's Agent Robot Avatar, said to be a port of an original character under the MIT License, with **Open** for its repository).

## Star request

**Once, as a banner at the top of the settings window** (`StarRequest`, `StarRequestBanner`): a sentence, **Star on GitHub**, and a close button. Never a window of its own and never a notification; the user asked for neither, and a window that appears by itself interrupts whatever they were doing.

- **Due after use, not after installation.** At least 14 days since the first day counted, and Pulse ran on at least 7 separate days since. A day is counted at launch, at midnight (`NSCalendarDayChanged`) and on waking, so a Mac left running counts each day. A copy installed and forgotten is never asked.
- **Counted from the first launch of a version that counts**, for existing users too, so nobody is asked on the day they update.
- **Spent when shown.** It is claimed as the settings window opens (not on a window already in front), stays for as long as that window is open, and is gone after the window closes, the button is pressed or it is closed. Pulse cannot tell whether a star was given and does not try to.
- `StarRequestTests`.

## Provider panes

**A provider with more than one route offers the choice, automatic by default; one with one route has that route named**, and the name belongs to the provider (`Provider.soleRoute`, an exhaustive `Provider` switch; omit the row when nil). A ternary (Cursor vs else Antigravity) once made the next single-route provider inherit Antigravity's sentence.

**Each pane has its own refresh**, with the last reading's time; a rail click is not the only way.

**The credential field** (API key, session cookie, access keys) is masked, with an eye button between it and **Save** that shows what is typed. It hides again whenever the pane changes account. A first account that needs a credential Pulse has not got is seeded with the reason, not `.loading`; `loadAPIKeys` rewrites that only over a placeholder.

**Connection diagnostics** follows Connection on every account: latest check, check time, last successful reading, actual source of the displayed figures, explicit cache use, expandable route checks (the whole row toggles them: on macOS a disclosure group's title alone does nothing), and, when the check made web requests, expandable **Server replies**: each request's status, method and address, time, type and size, and the redacted body in a selectable monospaced box, with **Copy replies** ([../refresh-and-data.md](../refresh-and-data.md#connection-diagnostics)). A failed check stays visible even when the card shows cached figures. Retry asks only that account; diagnostic copy contains allowlisted metadata ([../refresh-and-data.md](../refresh-and-data.md)). The contextual next step focuses the credential field, reconnects the status line, starts the existing sign-in, reads the chosen browser, opens the relevant app, copies a login command, or opens setup help. Provider-specific mappings: [../providers/README.md](../providers/README.md).

**Added accounts** exist only for `supportsMultipleAccounts` (Claude Code, Codex, Grok, Grok Bot) and have **Sign in again**: successful reauthentication replaces the credentials in that slot, keeping its name and display preferences. They do not show ambient CLI source controls their fetch ignores. A cancelled sign-in, or an account removed while sign-in is pending, is not written back. One extra-account sign-in runs at a time; its **Cancel**, device code and error rows appear only on the panes of the provider it was started for, and other multi-account panes show a disabled **Sign in…** until it finishes. Flows: [../providers/authentication.md](../providers/authentication.md), [../providers/README.md](../providers/README.md).

### Panel group

Per-account choices about *one ring* live here rather than on the Panel panes ([rings-and-surface.md](rings-and-surface.md)):

- **Show in panel**, **Ring shows**, **Ring colour**.
- **A ring for each model group**, only where `Provider.splitsByModelGroup` is true — a switch promising a second ring it can never draw is worse than none. Off by default: it costs a slot, and docked, the rail is the whole panel. While on, a **Ring for <group>** switch per group the reading carries ("Shown on the panel." / "Not shown on the panel."), the last shown one disabled (#106; [rings-and-surface.md](rings-and-surface.md#one-ring-per-model-group)).
- **Detailed card** on every account (`AppSettings.detailedCards`, account ids; off by default) — per account, because it is worth its height only on an account somebody watches closely. The subtitle says what the card adds and which history it will carry (`AccountPanelGroup.detailedCardSubtitle`): none, the account's month from the provider (Z.ai, Zhipu), or this Mac's recent activity with Token spend on. The card: [panel-geometry.md](panel-geometry.md#detailed-card).
- **Reset credits on the card**, Codex's first account only: off by default; on, its hover card says how many limit reset credits Codex reports, or "Not available" ([../providers/codex.md](../providers/codex.md#limit-reset-credits)).
- **Show each part of the credits**, Qoder only (`AppSettings.qoderShowsParts`, off by default): the plan's credits, a top-up pack and dedicated credits each get a row after the total, so the ring's automatic choice can follow the part closest to spent ([../providers/qoder.md](../providers/qoder.md#the-parts-issue-76)).
- **Usage history**, Qoder only (`QoderCreditsGroup`): the account's credits used and charged today, over 7 and 31 days, and the month as bars, from Qoder's own usage records, read when the pane opens and on Refresh ([../providers/qoder.md](../providers/qoder.md#credit-history-issue-88)). The same figures are on Qoder's detailed card.
- **Robot in the ring** on every account (`AppSettings.robotAccounts`, account ids; off by default), last in the group: CX ArtLab's robot in place of the provider's mark, showing what the account is doing ([rings-and-surface.md](rings-and-surface.md#robot)). Its subtitle names the robot and CX ArtLab, because the switch is where somebody first meets the character. **Only while it is on**, three rows follow it, because choices about something not drawn read as settings that do nothing:
  - **Robot colour**: Automatic or Custom, with a **Colour** well under Custom, as the ring colour has. The subtitle says which: the provider's own colour or, without one, a colour that differs from its neighbours; or that the ring keeps its own colour. Custom starts from the colour Automatic gives a lone robot of that provider, so switching changes nothing until a colour is picked. Rules: [rings-and-surface.md](rings-and-surface.md#robot).
  - **Robot personality**: Automatic, Calm, Curious, Lively; the subtitle describes the one chosen (`AccountPanelGroup.personalitySubtitle`).
  - **Robot shape**: Original, Squarer, Rounder.

  All four are cleared with the account (`removeAccount`), each in its own store (`robotAccounts`, `robotColours`, `robotPersonalities`, `robotShapes`); the defaults are stored as nothing.
- **Show credit amounts**, Qoder only (`AppSettings.qoderShowsAmounts`, off by default): each row on the card also shows its credits, "5,843 / 6,000", the same way round as its percentage; the rail keeps its percentages ([../providers/qoder.md](../providers/qoder.md#the-credits-themselves-issue-88)).

### Provider-specific groups

- **Usage history** appears exactly where the detailed card has one (`Provider.providesHistory` is `cardHistory != nil`) and is read from the same source (`AccountHistoryModel.load` switches on `cardHistory`): Claude Code's and Codex's transcripts, Z.ai's and Zhipu's statistics, OpenCode Go's and DeepSeek's consoles once their sign-in is kept, and the Token spend agents that borrow a provider's mark — MiniMax Code for MiniMax, the Kimi CLI for Kimi Code and the rest ([panel-geometry.md](panel-geometry.md#detailed-card)), added up by `UsageLedger.reading`, which the card shares. The agents' records wait for Token spend reading, as the card's do. While it is off the group says **Token spend reading is off** and offers **Open Token spend**, rather than "No history yet", which would claim the agent had logged nothing. Until 2026-10-15 the pane asked a narrower question of its own, so MiniMax's card showed MiniMax Code's history and its pane showed none (`CardHistoryTests`).
- **OpenCode Go's history** shows saved figures while updating and progressively fills an initial read, with a small **Reading…** indicator in the history header. Partial counts are labelled; a read id and the pane's history key stop an older read from updating a replacement. Console paging, shared warm-up and cache: [../providers/opencode-go.md](../providers/opencode-go.md#console-routes).
- **Prompt cache** (Claude Code and Codex, ahead of the estimate and history, while the account is on): every conversation still holding a cache (for Codex, still inside OpenAI's guaranteed 30 minutes, worded "at least"), soonest to lapse first, each with its time left ([panel-geometry.md](panel-geometry.md#detailed-card)). **Its read is keyed by provider** (`.task(id: provider)`, and a reading from another provider dropped): SwiftUI keeps the group in place across panes, and with a bare `.task` Codex's pane listed Claude Code's conversations.
- **Signs of a weaker model** ends Codex's pane while the primary account is on (`CodexSignalsGroup`): a **Period** menu (last 30 days, last 90 days, all sessions; not saved), then **Reasoning stopped at fixed points** — one row per model with the share of long replies whose reasoning stopped on 516 / 1,034 / 1,552…, as a figure with no verdict, "Too few to tell" under 20 long replies — and **Settings quietly lowered**, the turns that ran on a different model or lower reasoning than was set when they started (eight listed, the rest counted, plus how many sessions were too old to check). Read from this Mac's Codex sessions, nothing sent; the footnote says these are signs and that Codex never records the model the server ran. Rules: [../providers/codex.md](../providers/codex.md#signs-of-a-weaker-model).
