# Architecture

Single executable target `Pulse` at `Sources/Pulse`. No internal modules; one SwiftUI view per file. The floating monitor is **not** a SwiftUI `WindowGroup` scene.

Provider routes, credentials, cookies, and extra-account OAuth belong in [providers/README.md](providers/README.md). This file is the AppKit shell and the settings/state that every provider shares.

## App shell

- `PulseApp.swift` — `@main`. Declares only a `MenuBarExtra` (Settings, Quit). Usage is shown solely in the floating panel.
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

## Panel content (where it lives)

SwiftUI tree inside the panel: `FloatingUsagePanelView` → `UsageDockView` (rail) with `UsageDetailCard` as an **overlay**, not a stack sibling. Geometry, docking, and scale: [ui/panel-geometry.md](ui/panel-geometry.md). Pointer, drag, clicks: [ui/input.md](ui/input.md). Rings, glass, colour: [ui/rings-and-surface.md](ui/rings-and-surface.md).

## Settings and persistence

`AppSettings` is `@Observable`, stored in `UserDefaults`. `onChange` is how AppKit hears about it.

- The **rail** must not be empty (nothing to hover, nothing to grab). That is not the same as “the provider set must not be empty”: an added account is not a provider, and rebuilding from `Provider.allCases` has already overwritten a user’s choice.
- `providerOrder` / `orderedProviders`: never trust the stored list as written. Drop unknown names; append providers that did not exist when the list was saved (declaration order → bottom of the rail). The settings sidebar follows the same order. Reorder does **not** call `onChange` — that path refetches everything.
- **First run and offer-once live here** (`AppSettings.restored`), not in per-provider route pages. A later provider is offered **once** (`Key.offeredProviders` / `Key.hasRun`), and only if `Provider.canReportWithoutSetup`. Stamping offered *before* the union runs makes a new provider permanently invisible. “Has Pulse run here before” cannot be inferred from the enabled set: 1.0.0 computed that set in `init` and never wrote it (`didSet` did not run).
- First run starts from `Provider.installedOnThisMac` (presence of known tool folders/apps, not their contents). If nothing is found, everything is shown so the rail is still grabable. A stored list whose names no longer parse falls back to everything rather than to an empty rail. Which path counts as “installed,” and which providers stay off until a key exists: [providers/README.md](providers/README.md).
- A provider with nothing fetched yet is **not** seeded `.loading` (`UsageStore.initialState`). Loading that never resolves is a lie on its settings pane.
- Each provider pane has its own refresh control. A switched-off provider is **not** fetched on the timer; a deliberate press on its pane still can.
- Where a provider has more than one route, which one is used is `AppSettings.source(for:)` (`UsageSource`). `.automatic` is the default: take the primary route when it can, fall back when it cannot. Pinning reports failure instead of quietly answering from elsewhere. Which routes exist: [providers/README.md](providers/README.md).
- Colour means usage, not brand (`UsageTint`, optional per-account `RingTint`). Spent colour still wins. Spent comes from the **provider’s flags**, not from crossing 100%. See [ui/rings-and-surface.md](ui/rings-and-surface.md).
- The rail ring shows one window: closest to limit, or a pin (`AppSettings.pinnedWindows`). Resolved at display time.

`AccountKey` is provider plus which account. The primary account’s id is the provider’s `rawValue` so stored prefs and cache files need no migration. Extra accounts: Claude Code, Codex, Grok, Grok Bot only (`supportsMultipleAccounts`). How those logins work: [providers/README.md](providers/README.md).

Keys pasted in Settings live in `keys.dat` (`APIKeyStore`), not `UserDefaults`. Extra-account tokens live in `accounts.dat`. Both are AES-GCM, owner-only, key derived from the Mac.

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
