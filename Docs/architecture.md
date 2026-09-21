# Architecture

Single executable target `Pulse` at `Sources/Pulse`. No internal modules; one SwiftUI view per file. The floating monitor is **not** a SwiftUI `WindowGroup` scene.

Provider routes, credentials, cookies, and extra-account OAuth belong in [providers/README.md](providers/README.md). This file is the AppKit shell and the settings/state that every provider shares.

## App shell

- `PulseApp.swift` — `@main`. Supplies the required SwiftUI scene; the AppKit delegate owns the `NSStatusItem` (Settings, Quit) so `AppSettings.hidesMenuBarIcon` can remove it at runtime. Usage is shown solely in the floating panel; when the icon is hidden, the panel menu and global shortcut remain entry points.
- `AppDelegate.swift` — activation policy `.accessory` (no Dock icon). Owns `AppSettings`, `PanelPlacement`, `FloatingPanelController`, and the settings window. Ignores `SIGPIPE` process-wide so a helper (for example Codex app-server) exiting cannot take Pulse down with it (`Terminated due to signal 13`).
- `FloatingPanelController.swift` — owns a custom `NSPanel` (`FloatingPanel`: borderless, non-activating, `canBecomeKey` / `canBecomeMain` both false) hosting SwiftUI through `NSHostingView`. **The AppKit controller computes and animates the panel frame.** SwiftUI has no say over outer size; expand/collapse is `NSAnimationContext` / `panel.animator()`, not a SwiftUI transition.
- Full-screen Spaces: `AppSettings.hidesInFullScreen` selects `.fullScreenNone` (default) or `.fullScreenAuxiliary`. Both keep `.canJoinAllSpaces` for ordinary desktops. This is public window collection behaviour, not a guessed full-screen detector.

`LSUIElement` must be **true** in the bundled `Info.plist`. Setting `.accessory` in code runs after the Dock has already been told what to show, so without the key a Dock icon flashes at every launch. Shipping detail: [releasing.md](releasing.md).

## Settings window

Hand-rolled `SettingsWindowController`, not SwiftUI’s `Settings` scene: an `.accessory` app must `NSApp.activate` or the window opens behind everything.

- `.fullSizeContentView` so content blurs under the title bar as it scrolls.
- **Title bar stays opaque** (`titlebarAppearsTransparent = false`, `titlebarSeparatorStyle = .automatic`). Transparent plus full-size content drew scrolled rows over “Pulse Settings”.
- No extra top padding: AppKit reports the bar as a ~52pt safe area and the scroll view already insets by it.
- The sidebar does **not** extend behind the traffic lights. That is AppKit’s treatment of an `NSSplitViewController` sidebar; a SwiftUI `NavigationSplitView` in an `NSHostingView` does not get it. Historical measurement (with/without full-size content and a unified `NSToolbar`) is in the old notes, not re-run here.
- Ending text-field editing on click-away is the **window’s** job (`SettingsWindow.sendEvent`). Geometry against the field being edited, never `hitTest` — a hosted SwiftUI tree answers that unreliably. See [ui/settings.md](ui/settings.md).

## Ways into settings

Four, and the menu bar is only one of them — an icon in a full menu bar is not reachable at all ([issue #24](https://github.com/qunqin24/Pulse/issues/24)):

- The AppKit status-item menu (`AppDelegate`), unless the user has hidden its icon.
- A **secondary click on the rail**, which puts up `AppDelegate.panelMenu()`. [ui/input.md](ui/input.md)
- A **global shortcut**, unset until somebody sets one. `GlobalShortcutMonitor`, held by the app delegate for the life of the process and re-applied by the settings pane whenever a combination changes. The panel's own shortcut goes through `settings.isPanelVisible` rather than `FloatingPanelController.toggle()`, so the panel is in the state the switch in settings claims and stays that way across a launch.
- A `pulse://` link, below.

## Settings navigation from other apps

`PulseLink` parses `pulse://settings`, `pulse://integrations`, and `pulse://account/<encoded-id>`. `AppDelegate.application(_:open:)` passes accepted links to `SettingsWindowController`, whose `SettingsNavigation` owns the selected pane shared with SwiftUI. A request id lets a repeated link clear sidebar search and return to the heading, even when the pane is already selected. Account targets must exist in `settings.allAccounts`; links never create a slot or run a repair. `Scripts/bundle.sh` registers the `pulse` URL scheme in `CFBundleURLTypes`. Setup and examples: [integrations.md](integrations.md).

## Panel content (where it lives)

SwiftUI tree inside the panel: `FloatingUsagePanelView` → `UsageDockView` (rail) with `UsageDetailCard` as an **overlay**, not a stack sibling. Geometry, docking, and scale: [ui/panel-geometry.md](ui/panel-geometry.md). Pointer, drag, clicks: [ui/input.md](ui/input.md). Rings, glass, colour: [ui/rings-and-surface.md](ui/rings-and-surface.md).

## Settings and persistence

`AppSettings` is `@Observable`, stored in `UserDefaults`. `onChange` is how AppKit hears about settings that affect the panel or refresh loop. `hidesMenuBarIcon` is the exception: its dedicated callback removes or restores the AppKit status item without refetching providers. It defaults to `false` to preserve the existing menu bar entry point.

- Once monitoring starts the **rail** must not be empty (nothing to hover, nothing to grab). Before the initial choice, an empty account set is valid and the panel is not created. An added account alone is a valid rail; rebuilding from `Provider.allCases` must never overwrite that choice.
- `providerOrder` / `orderedAccounts`: never trust the stored list as written. Drop unknown names; append accounts the list does not mention **in name order** after whatever arrangement is stored. The settings sidebar follows the same order. Reorder does **not** call `onChange` — that path refetches everything.
- **First run and upgrade offers** are resolved by `ProviderSelection.restore`, called from `AppSettings.restored`. First launch enables nothing. An empty or invalid saved set returns to the chooser, never to an everything-on fallback. Discovery suggests providers but enables none; see the startup contract below.
- A provider with nothing fetched yet is **not** seeded `.loading` (`UsageStore.initialState`). Loading that never resolves is a lie on its settings pane.
- Each provider pane has its own refresh control. A switched-off provider is **not** fetched on the timer; a deliberate press on its pane still can.
- Where a provider has more than one route, which one is used is `AppSettings.source(for:)` (`UsageSource`). `.automatic` is the default: take the primary route when it can, fall back when it cannot. Pinning reports failure instead of quietly answering from elsewhere. Which routes exist: [providers/README.md](providers/README.md).
- `networkProxy` is one persisted value rather than four independently firing fields. It configures Pulse's external sessions and supported helper processes, then `onChange` queues a full refresh. Scope and the Sparkle exception: [networking.md](networking.md).
- Colour means usage, not brand (`UsageTint`, optional per-account `RingTint`). Spent colour still wins. Spent comes from the **provider’s flags**, not from crossing 100%. See [ui/rings-and-surface.md](ui/rings-and-surface.md).
- The rail ring shows one window: closest to limit, or a pin (`AppSettings.pinnedWindows`). Resolved at display time.

`AccountKey` is provider plus which account. The primary account’s id is the provider’s `rawValue` so stored prefs and cache files need no migration. Extra accounts: Claude Code, Codex, Grok, Grok Bot only (`supportsMultipleAccounts`). How those logins work: [providers/README.md](providers/README.md).

Keys pasted in Settings live in `keys.dat` (`APIKeyStore`), not `UserDefaults`. Extra-account tokens live in `accounts.dat`. Both are AES-GCM, owner-only, key derived from the Mac.

## Provider choice before monitoring

`ProviderSetupWindowController` hosts the chooser in a regular AppKit window. On first launch it lists all providers, unchecked, with detected installations first. **Done** needs at least one selection. Closing it or choosing **Not now** leaves the rail absent and the menu bar usable; enabling a service in its Settings pane also completes the initial choice. Dismissing an initial chooser is not saved as completion: the next launch asks again.

The startup gate is the resolved account set, `AppSettings.needsProviderSelection`, not whether any window was dismissed. `AppDelegate` creates the panel and starts `UsageStore` only after that set is non-empty. Store construction seeds placeholders without looking for credentials; `start`, both refresh entry points, and settings-driven refresh also refuse an empty selection. Provider panes load credentials and history automatically only for enabled primary accounts; opening Codex's pane while disabled cannot start its helper. Connection, sign-in, diagnostics and usage controls are built only after the initial choice, so even evaluating their contents cannot read a tool's configuration beforehand. The separate Token spend pane keeps its own workflow.

Claude's desktop Keychain request and status-line offer run only after the primary Claude Code account is enabled, including when enabled later through Settings. A new grant's callback checks it is still enabled before refreshing. Per-provider access descriptions and exact discovery paths belong in [providers/README.md](providers/README.md).

Upgrades preserve the saved enabled account ids, including extra-account-only rails. A provider new to `settings.offeredProviders` is **suggested once**, and only if presence-only discovery found it; existing providers continue monitoring while that chooser is open. Dismissal keeps the existing set. Undetected new providers remain available in Settings. All current providers are stamped as offered during restoration, so a declined upgrade offer does not recur.

**Legacy 1.0.0:** it wrote an offered list but no enabled list until the user edited one. Only an **absent** enabled key is restored from that historical offered list. An explicit empty array, malformed value or unknown-only list goes to the chooser. There is no path that enables all current providers as a recovery strategy.

## Login item

`LoginItem.swift` — on by default, decided **once** (own flag; never re-enable on a later launch). Reads the *system* state, not a stored preference.

- Bundled app: `SMAppService.mainApp` (what System Settings lists).
- `swift run`: that API reports `notFound`. A launch agent is written to `~/Library/LaunchAgents` instead. No `KeepAlive`.
- Rebuilding moves the executable; `repairPathIfNeeded` rewrites a stale agent. `LoginItem.adoptBundleIfNeeded` stops a leftover agent and `SMAppService` both launching after an upgrade.

## UserDefaults domain

A bundled app and `swift run Pulse` use **different** defaults domains (bundle id vs process name). `LegacyDefaults` copies the old `Pulse` domain into the bundle domain **once**, only keys the new domain does not already have. After that they diverge on purpose. Details: [decisions/bundle-and-defaults.md](decisions/bundle-and-defaults.md).

## Related

- Refresh / cache / ledger: [refresh-and-data.md](refresh-and-data.md)
- Localization and resources: [development.md](development.md)
