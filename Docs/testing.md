# Testing

Owns: what `swift test` covers, what it deliberately does not, and the conventions the suite depends on. Toolchain and build flags: [build-from-source.md](build-from-source.md).

```bash
swift test
```

The test target dates from 2026-09-07. It followed two faults found by reading code — Antigravity giving up when the helper that answers was second, and `.stale` treated as a failed fetch although a successful one produces it too — and notification rules that had shipped unproven.

## What is covered

Every suite is a synthetic check of production code — no live provider, no real credential, no whole-app profiling, no real pointer input. Rows name what each suite pins; the cases themselves are in the suite. Suites sharing a row share a file or a topic.

### Notifications, cache and refresh

| Suite | Pins |
|---|---|
| `AlertMemoryTests` | Every notification rule: thresholds, spent, resets, the failure streak, the stale-age gate, and the low-balance line (said once, re-armed by a top-up, never from a stale reading or a balance with no figure). [notifications.md](notifications.md) |
| `AlertsThroughTheCacheTests` | The same rules through the production path: service → `UsageCache.reconciled` → state machine. |
| `OutageMemoryTests` | Status-page notifications: an outage said at once and once, worse said again, recovery only for one announced, maintenance and unknown never; Claude Code hears only about Claude Code and the API. [notifications.md](notifications.md) |
| `NotificationAuthorizationTests` | An injected authorization decision, concurrent requests, no warning consumed while a grant is pending, the foreground delegate selector. No system permission or delivery. |
| `UsageCacheTests` | `reconciled`: a reading never goes backwards; credential failures are not papered over; a gateway's or Qoder site's banked reading stands in only for the same server or site and credential; expiry. A live reading with a balance and no limits is an **answer** (DeepSeek's "balance only"); one carrying nothing is not. |
| `CacheConfirmedAnswersTests` | A confirmed "no plan" (Z.ai, Xiaomi MiMo, Grok Bot, Qoder, StepFun) drops banked figures now and after relaunch; a failed request still falls back. |
| `QoderCacheTests` | A confirmed empty allowance removes old figures from memory, disk and JSON without touching another account; failures keep the cache; a spent allowance and a team-only pool remain readings. [providers/qoder.md](providers/qoder.md) |
| `ConnectionDiagnosticTests` | Failures through real cache reconciliation: persisted origin, legacy unknown sources, capture freshness, allowlisted diagnostic copy, account-specific repair choices, credential failures at pinned service boundaries. |
| `UsageStoreSchedulingTests` | Scheduling through the `UsageServiceFactory` seam with fake services and a test clock: a pass asks only rail accounts; switched-off accounts are never asked; added accounts wait for primaries; an in-flight request is queued once; a pass past `passCeiling` is abandoned and its late answer writes nothing; only the timer (`dueOnly`) honours cadence; the timer is one-shot within 2–30 minutes. [refresh-and-data.md](refresh-and-data.md#one-path-from-an-account-to-its-fetch) |
| `RefreshPacingTests` | Automatic cadence, the unwatched-spend cap, the timer as the only caller that skips providers not yet due; timestamps alone and an empty batch are not usage changes (Devin and every represented provider). [refresh-and-data.md](refresh-and-data.md) |
| `RefreshTimerTests` | The timer's wait: added-only rails keep the chosen interval, Automatic with nothing primary uses the adaptive one, the soonest primary account sets it, never under fifteen seconds. |
| `AgentActivityTests` | Only selected transcript providers are scanned, enabled and added accounts included; no local provider, no scan; held readers cover cancellation and late results; cached tail grace and changed/new/deleted files. [refresh-and-data.md](refresh-and-data.md) |
| `ElsewhereWatchTests` | A limit spent where this Mac's logs cannot see (two points gone, nothing spent here) loses its value estimate; a rise this Mac paid for or a one-point tick does not. |
| `ZaiHistoryReadTests` | No key is not a failed request; a successful reply with no rows is an answer. |

### Panel, rail and input

Geometry checks, not real input; see [ui/panel-geometry.md](ui/panel-geometry.md) and [ui/input.md](ui/input.md).

| Suite | Pins |
|---|---|
| `RailGeometryTests` | Every ring is reachable on every edge, docked or floating: centre inside the rail, last ring whole, each ring hit-testing to its own slot. `shownSlotCount` gets a reading that really splits, so a window counting accounts instead of rings fails (verified by reintroducing the bug). |
| `FreeLyingRailProportionTests` | A free-lying rail's spacing with figures under or beside it, docked rails untouched, and extra edge room for the time arc. |
| `NotchGeometryTests` | Notch docking: public screen area on offset displays, physical-top placement with controls below the housing, the warning edge inside it, minimum housing width, and padding/card/window budgets across every scale, top-label setting and end style; non-notch placement unchanged. |
| `FreeAcrossTests` | The rail lying across: its card opens down in the top half and up in the bottom (`PanelEdge.bottom`), the frame stays on screen for both ratios, and free placements are distinct docks. |
| `DropletTetherTests` | Liquid docking: the drawn pull starts at the grip's share of the hand's speed and meets the pointer, at its speed, at the break; fluid turns leave and arrive along their lines; a pulled rail stays joined to its edge and is drawn `pull` into the panel; a parted neck that has drawn back leaves nothing on the edge. |
| `BottomDockTests`, `CardRoomTests` | A bottom-docked rail stands on the screen's own bottom below the visible frame, its berth the top one upside down; a card's room beyond a rail lying across runs to the visible edge, less the gap. |
| `PanelPlacementMigrationTests` | `PanelPlacement.restored(from:)`: a free placement stored before `panel.floatingAxis` existed, or with an unknown axis, comes back upright; docked placements ignore the axis. |
| `RailOffsetTests` | Offsets are measured against the frame the window was **granted**: the panel is taller than a laptop's usable screen and AppKit refuses the requested frame. |
| `ActiveDisplayTests` | Following the pointer to another display keeps dock and ratios; a held panel refuses and the refusal is *reported* so the display stays on offer; returning to the current display is quiet. |
| `PanelIntentTests` | The notch's dwell target is the physical housing above the rings for every rail length; a press within `PanelIntent.ringClickGuard` of the rail opening is not a ring click; the dwell sits between a brisk crossing and a noticeable wait. The timing itself needs real input. |
| `PanelHoldTests` | Nothing re-places a held panel, including between mouse-down and the first movement while `isDragging` is still false. |
| `GlobalShortcutTests` | A binding needs a real modifier (not ⇧ alone); unparseable storage reads as *no* shortcut, not another key. |
| `RailSlotTests` | Rail order is by name until someone arranges it, and an arrangement is never re-sorted when a split account gains or loses slots; unscoped windows never form a group. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `ShownOrderTests` | The Order group's arrows and drops move only shown accounts, never a hidden one. [ui/settings.md](ui/settings.md) |
| `SecondWindowTests` | The second ring shows the fullest limit in the headline's own model group, with a fallback when that group holds nothing more. |
| `UsageWindowTests`, `WindowClockDirectionPreferenceTests` | The reported figure at both ends, when the window clock may divide, clock boundaries, and the stored clock direction (default elapsed, invalid values fall back). |
| `UsageTintTests` | The configurable amber→red boundary at exact equality, the fixed green boundary, spent overriding the setting. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `MoneyTests`, `ExchangeRatesTests` | "$" and never "US$" in every language, "HK$"/"NT$" kept; no rate leaves an estimate in dollars; a typed rate wins, and is read whole — a sign, a letter or a stray separator refuses it; yen and won whole; the open access reply parsed (offered currencies, the source's own update times; an error or another base is nothing); not asked before the next update nor twice in an hour. Each test converts with its own `Money.Conversion`, never the app's. [refresh-and-data.md](refresh-and-data.md#currency) |
| `MiniMaxSiteScopeTests` | The two MiniMax sites never stand in for each other: a failed read on one site does not fall back to the other's figures, the scope names the site and a key fingerprint and never the key, and a forgotten account's reading is gone. [providers/minimax.md](providers/minimax.md) |
| `RailMoneyTests` | Money on a ring: abbreviated past a thousand, truncated not rounded up, no early rollover at 999,999, narrow currency symbol — every form measured against the rail's real room. [providers/deepseek.md](providers/deepseek.md) |
| `ProviderMarkTests` | Every mark **puts ink down** at rail size, not merely loads: `LobeIconStore.image(named:)` accepts a blank-rendering SVG. Floor 8% coverage; the bundled set runs 22.4–52.7%. Verified by blanking a mark. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `IconPathTests` | Bundled marks spell arc flags out: CoreSVG (used by `NSImage`) stops at a flag run into the next number and draws part of the mark (Gemini's star was a sliver). Marks from Lobe Icons need re-spacing. |

### App, settings and output

| Suite | Pins |
|---|---|
| `AppSettingsLayoutTests` | Layout-only settings (`panelSize`, `railSpacing`, rail switches, glass, `autoCollapse`, …) fire `onLayoutChange` once and **never** `onChange`, so none refreshes a provider; fetch-changing settings still fire `onChange`. [architecture.md](architecture.md#settings-and-persistence) |
| `AppSettingsPersistenceTests` | Every setting's stored key is spelled out (a rename would reset everyone's choice); building settings writes nothing; `restoredSettings(from:)` reads every one back; nothing stored gives shipped defaults. |
| `AppSettingsRemoveAccountTests` | Removing an added account clears every per-account store keyed by its id, and only that account's. [architecture.md](architecture.md) |
| `ProviderSelectionTests` | Fresh installs and dismissed setup stay empty whatever is detected; newly supported detected services are suggested once, never auto-enabled; empty-selection guards on startup, refresh and Codex history; disabled providers refuse per-account refresh. No Keychain access. [architecture.md](architecture.md#provider-choice-before-monitoring) |
| `HandWrittenProviderCoverageTests` | Every `Provider` case is answered by exactly one of `handWritten` and `profile`. [development.md](development.md) |
| `BillingTests` | `Provider.billing` sorts per-call money as an API account and a plan as a subscription even with a balance; every profile reporting a spendable balance answers `reportsSpendableBalance`, so its low-balance row is offered. [providers/README.md](providers/README.md#subscriptions-and-api-accounts) |
| `MenuBarIconSettingTests` | Persistence callbacks, menu rebuilding, and the entry-point rule: with the panel hidden and no shortcut accepted by the window server, the menu bar icon remains. [architecture.md](architecture.md#ways-into-settings) |
| `MenuBarReadingTests` | Which ring the menu bar speaks for: the fullest headline (ties in rail order) or a chosen account while it is on the rail; unavailable is a dash, not zero; `estimate` rings show money; the split style takes at most two account-wide timed limits, shortest first; red from the warning line or the provider's spent flag. [ui/settings.md](ui/settings.md) |
| `UsagePagesTests` | Usage-page links are https with a host, cover the four most-used providers, and exclude extensions. [ui/settings.md](ui/settings.md) |
| `MyriadUnitsTests` | Which languages count by 10⁴/10⁸ and in whose characters (亿 / 億 / 억), with region-only `zh_TW` as traditional — a silent failure otherwise. [development.md](development.md) |
| `NetworkProxyTests` | System as the upgrade-safe default; No Proxy as an empty dictionary, not nil; `ProxyGuard` first in every session; what System Proxy Only refuses, loopback never; `.systemProxyOff` only for an unreachable reading and neutral to alerts; exact direct/HTTP/SOCKS helper environments. [networking.md](networking.md) |
| `WindowPrimerTests` | The window starter: due only after the reset and its grace, inside the hours, not once a later reset shows use; only Claude Code's five hours and Codex's five hours and week; arguments that save nothing and run nothing else; the cheapest Codex model; where `claude` is looked for. [window-starter.md](window-starter.md) |
| `PulseLinkTests` | Encoded added-account ids, malformed or action-bearing URLs rejected, existing-account navigation, repeated links. |
| `AppUpdateFeedTests` | GitHub when its probe answers, else the mirror; a failed check retried once on the other host, never a third time; one-language update copy. The Worker: `node --test Scripts/update-mirror/worker.test.mjs`. [update-mirror.md](update-mirror.md) |
| `APIKeyStoreTests` | `keys.dat` in a temporary folder: sixteen concurrent saves keep all sixteen (without the lock fifteen were lost); a renewal replaces only the credential it renewed. |
| `AccountRenewalTests` | A late renewal never overwrites a login removed, renewed more recently, or signed in again meanwhile; legacy logins still renew. Never the real `accounts.dat`. |
| `UsageReportTests` | The `--json` shape, a contract others build on. [json-output.md](json-output.md) |
| `ExtensionCatalogTests`, `ExtensionReportTests`, `ExtensionRunTests`, `ExtensionAccountTests` | Manifests accepted or refused (including a program reached by `..` or a link out of its folder); what a report may not invent; a balance needs a number and a currency code and never takes limits down; real shell-script runs (exit, time limit, deleted program, an environment without Pulse's own); a switch survives only while the folder exists. [extensions.md](extensions.md) |

### Providers

Fixtures are captured unless marked second-hand or reconstructed; see [What is not, and why](#what-is-not-and-why).

| Suite | Pins |
|---|---|
| One suite per profiled provider (`ClinePassTests` … `XAIAPITests`), and `ProfileCookieTests` | Each reply from a **second-hand** fixture (CodexBar's code and tests, said in each suite); refusing a missing or negative figure, a guessed length, or a health flag as a percentage; credentials; `ProfileHTTP` status mapping. `ProfileCookieTests`: exact names, `*` prefixes, `\|` alternatives. [providers/README.md](providers/README.md#profiled-providers) |
| `ZhipuProviderTests` | Both GLM storefronts share the `zai` mark. |
| `ClaudeCodeSeverityTests` | Warning severities leave room; locked reasons and unknown severities mark the limit spent. [providers/claude-code.md](providers/claude-code.md) |
| `AntigravityParsingTests` | A captured `RetrieveUserQuotaSummary` reply → `[UsageWindow]`. |
| `AntigravityCLITests` | The `agy -p "/usage"` reply → the same `[UsageWindow]` through the same mapping; an error envelope or an agent turn's output is not read as limits; the version gate that keeps `/usage` from reaching the model on `agy` older than 1.1.11; and the CLI's answer weighed against the language server's. [providers/antigravity.md](providers/antigravity.md#the-agy-cli) |
| `CodexHelperEnvironmentTests` | The folder `codex` was found in leads the helper's `PATH`, so an npm-installed `codex` finds `node` from a GUI app. [providers/codex.md](providers/codex.md#app-server--sigpipe--path) |
| `CodexLocatorTests`, `CodexLocatorAppTests` | Where `codex` is looked for: the app Launch Services names first, ChatGPT 26.924's layout before the old one ([#67](https://github.com/qunqin24/Pulse/issues/67)), newest managed version first; a missing `codex` is worded apart from Codex reporting none. |
| `CodexResetCreditsTests` | The stated count, else a count of entries, and "not reported" — never zero — when the block is missing. [providers/codex.md](providers/codex.md#limit-reset-credits) |
| `CodexCreditBalanceTests` | Codex's ten-place decimal balance shown with at most two places; unlimited is no balance. |
| `CodexAppServerTests` | A `readabilityHandler` left on a closed pipe is a busy loop (290% CPU for eleven hours, [#25](https://github.com/qunqin24/Pulse/issues/25)): it removes itself at EOF, `shutDown` clears it, and a stale pipe's EOF spares its replacement. Plain `Pipe`, no `codex` needed. [providers/codex.md](providers/codex.md) |
| `RPCRequestLifecycleTests` | Codex and Kiro reconnect after errors, partial JSON and shutdown; a new helper gets its own deadline; completed requests release their client early. Isolated `/bin/sh` helpers, injected short deadline. [providers/codex.md](providers/codex.md), [providers/kiro.md](providers/kiro.md) |
| `KiroUsageTests` | Captured ACP usage mapping, malformed pools refused, window identities stable across a reorder. [providers/kiro.md](providers/kiro.md) |
| `ZaiQuotaTests`, `ZaiErrorTests`, `ZaiHistoryTests` | GLM Coding Plan quota → windows, a zero spend being a reading; HTTP-200 refusals from both live hosts; the statistics endpoint → a daily ledger and what may not be said about it. |
| `VolcengineParsingTests`, `VolcengineSignerTests` | Ark's three reply shapes (second-hand); the request signature cross-checked against a second implementation. [providers/volcengine.md](providers/volcengine.md) |
| `VolcengineProcessTests` | The `arkcli` subprocess under stderr and output floods, a child ignoring SIGTERM, one that closes its pipes and lives, descendants outliving the leader, and non-zero exit classification. |
| `ResponseLogTests` | Server replies in the connection diagnostics: recorded only while a check runs, never a header or a query; the request's own credentials masked wherever a reply echoes them; credential-named values masked at any depth, random-looking runs and known key prefixes masked (an all-lowercase `sk-` hex key included), counts, model names and UUIDs kept; failures recorded with their error; bodies cut. [refresh-and-data.md](refresh-and-data.md#connection-diagnostics) |
| `StatusFeedTests` | Every other status platform from replies in its real shape: Better Stack (sections, days, not-monitored is no reading), Instatus (a group's own row left out), Upptime, Gatus (a 2xx failing a condition is degraded), UptimeRobot (grey days, HTML entities), OpenCode, DeepInfra, IBM Bob (one row per name), Google Cloud (an open incident is the state, incidents are the days); incident.io rows outside groups and `chart_only`; the catalogue — https, the provider's own, two providers on one feed never showing the same row, MiniMax by site, no stand-in pages. [providers/README.md](providers/README.md#service-status) |
| `ServiceStatusTests` | status.openai.com (Codex group, captured 2026-10-04, **every bar of all four components equal to the page**), status.claude.com (six components, uptimes, bar colours), status.cursor.com (eight components; IDE, CLI and Cloud Agents notify; two components' ninety days, trimmed from a 2026-10-15 capture) and status.deepseek.com (embedded data, five components, every bar equal to the browser's in UTC+8). A missing group or a page that is not the feed is **no reading**, not all clear. [providers/codex.md](providers/codex.md#service-status), [providers/claude-code.md](providers/claude-code.md#service-status), [providers/deepseek.md](providers/deepseek.md#service-status) |
| `CommandCodeParsingTests` | Four replies (second-hand). Which question the monthly row answers: a running plan against its inferred, labelled grant, an account without one against its pool, an unsizable plan against *nothing*. Absence is never read as empty wallet, nothing spent, failed lookup, or a limit reached. [providers/command-code.md](providers/command-code.md) |
| `DeepSeekParsingTests` | The denominator when none is reported: the watched mark advances only on a rise; a zero peak or no budget draws nothing; absent money stays distinct from zero; only `is_available` may say spent. [providers/deepseek.md](providers/deepseek.md) |
| `DeepSeekConsoleTests` | The console: a refused token is HTTP 200 with a 400xx code (signed out); the last 30 whole local days become ledger days; no money in the reply is tokens only, never a zero bill; wallets per currency. |
| `BalanceRingTests`, `BalanceRingSpentTests` | DeepSeek's three ring modes as every API account's rule: one watched mark per account **and currency**; an invalid budget draws the balance alone; a reading with limits, or none, is left as it came. A zero or negative balance fills the ring but is not spent. [providers/deepseek.md](providers/deepseek.md#there-is-no-allowance-so-the-ring-has-no-denominator) |
| `GatewayAddressTests` | **Where a key may go**: a bare host becomes https; plain http only on a private host (RFC 1918 edges); user info, fragments and queries refused; a typed suffix trimmed exactly once. [providers/sub2api.md](providers/sub2api.md), [providers/newapi.md](providers/newapi.md) |
| `Sub2APIParsingTests` | A wallet draws money, not a percentage; missing or zero limits draw nothing, not a full ring; only rolling windows state a length. [providers/sub2api.md](providers/sub2api.md) |
| `NewAPIParsingTests` | Fields that do not mean their names: "limit" is `remaining + used`; "usage" is in hundredths (read as units it is a hundred times too large — a red ring and a false spent alert); `_usd` is the operator's unit, so non-currency units report **no money**. The unlimited sentinel only when all three fields agree; no `/v1/v1`. [providers/newapi.md](providers/newapi.md) |
| `V2EXParsingTests` | A five-hour window that **has not started**: `period_end` zero is not a date, `reportsLength` is false so no elapsed arc; the top-up pack is its own window, never a reset. [providers/v2ex.md](providers/v2ex.md) |
| `QoderParsingTests`, `QoderPartsPinTests` | The cookie filter; both key casings; a team pool as a **second ring never summed** with the account's; a zero allowance draws nothing, not 100%; spent follows Qoder's own remainder. A pin to the total is cleared when the parts are turned on. Sanitized fixtures from other readers' shapes. [providers/qoder.md](providers/qoder.md) |
| `StepFunParsingTests` | The cookie allow list (`Oasis-Token` required); `oasis-webid` from the cookie or the token's `device_id`; a **real** Token Plan reply as one credits ring with no reset and the pool's end as `nextExpiry`; a zeroed reply as no plan, not 0%; refusals inside a 200. [providers/stepfun.md](providers/stepfun.md) |
| `XiaomiMiMoTests` | The cookie filter keeps the console's four names, refuses control characters (header injection); an empty `items` list is **no plan**, not 0%; an expired plan is not an allowance; a `code` 401 inside a 200 is not an answer. [providers/xiaomi-coding-plan.md](providers/xiaomi-coding-plan.md) |
| `CursorParsingTests` | Pools are percentages of 100, not fractions; the plan-money fallback only without pools; on-demand only once turned on; a team's `pooled` / `onDemand`. Reconstructed. [providers/cursor.md](providers/cursor.md) |
| `CursorEnterpriseOverallTests` | An Enterprise account's `individualUsage.overall` becomes the monthly money window and balance, with cents converted to dollars and both figures written with a currency symbol and two decimals. Synthetic fixture. [providers/cursor.md](providers/cursor.md) |
| `CursorAppLoginTests` | A plaintext JWT passes through untouched; a `cursor-safe-storage:v1:` cell unwraps with a known Chromium key; a sealed cell with no key is `.keychainRefused`, with the wrong key `.unreadable`; `session(from:)` accepts an integer `exp`; `CursorKeychain` reads once, holds back after a refusal until `allowAsking`, and reads again after `forget`. Synthetic ciphertext only. [providers/cursor.md](providers/cursor.md) |
| `CopilotParsingTests` | The `percent_remaining` inversion; `has_quota: false` dropped, not drawn at 100%; spent kept apart from `overage_permitted`. Reconstructed. [providers/copilot.md](providers/copilot.md) |
| `KimiCodeParsingTests` | Timed `limits[]` ahead of the lengthless weekly allowance; unknown time units dropped, not guessed; `used = limit − remaining`. Reconstructed. [providers/kimi-code.md](providers/kimi-code.md) |
| `OpenCodeGoParsingTests` | `rolling` is the five-hour kind; a `status` other than `ok` is spent; missing windows draw nothing. Reconstructed. [providers/opencode-go.md](providers/opencode-go.md) |
| `OpenCodeConsoleTests`, `OpenCodeConsolePagingTests`, `OpenCodeConsoleHistoryTests` | The console's request log and limits from made-up replies: only sign-in cookies kept, pages followed to the end and a short walk said so, the key's three windows; adaptive pagination with bounded concurrency and a global page budget; temporary caches that repair failed intervals without declaring overlap complete and keep workspaces apart. [providers/opencode-go.md](providers/opencode-go.md) |
| `GrokParsingTests` | One window with its kind from the period's length; an omitted percentage is zero only inside a running period; the freshest unexpired entry in `~/.grok/auth.json`; at or past 100% is spent. Reconstructed. [providers/grok.md](providers/grok.md) |
| `GrokBotParsingTests` | The opposite presence rule: an absent `usagePercent` draws nothing; no Grok Bot is "not included", not 0%; seven days sorts but is never a length; no invented reset. Reconstructed. [providers/grok-bot.md](providers/grok-bot.md) |
| `MiniMaxParsingTests` | The remaining-percent inversion; each site's host and key slot; an unissued lane dropped, not 0%; which `base_resp` statuses blame the key. Reconstructed. [providers/minimax.md](providers/minimax.md) |
| `MiniMaxMergeTests` | MiniMax CN folded into MiniMax once: its key moved sealed to the minimaxi.com slot; its ring settings MiniMax's only where it was the one switched on, otherwise filling only what MiniMax lacked; a pinned limit's window id renamed; run once. [providers/minimax.md](providers/minimax.md) |
| `MiniMaxCodeSessionReaderTests` | MiniMax Code's own log: assistant lines with their own model, user/zero-usage/unreadable lines and subagent transcripts left out; a copied `message_id` once; captures unread once the log has files, and the origin says so; MiniMax's card history is MiniMax Code's. [token-spend-sources.md](token-spend-sources.md) |
| `UsageBarTests` | The segmented bar's ticks: as many as fit with their gaps, lit in proportion, at least one once touched and all only when spent; taller than the continuous bar. [ui/panel-geometry.md](ui/panel-geometry.md) |
| `OllamaCloudParsingTests` | Two required windows, failing closed on a changed page; HTTP mapping through `OllamaCloudClient.validate`. Fixtures use `<div>`/`<span>` because `XMLDocument` drops HTML5 elements. [ollama-cloud.md](ollama-cloud.md) |
| `DevinParsingTests` | A file another app wrote: `used = 100 − remaining`; `-1` counters are absent, not minus one; `hideDailyQuota` drops a row; the launch stamp from the log directory. The endpoint's percentages are **spent** where the saved plan's are **left**. [providers/devin.md](providers/devin.md) |
| `DevinSnapshotTests` | Saved-plan freshness, expiry and launch stamps; age/reset limits on the direct-fetch cache; an idle app-cache route is not an outage. [providers/devin.md](providers/devin.md) |
| `DevinAccountMixingTests` | Different users or organizations never borrow readings; endpoint failures never reach the saved plan; scope checks survive expiry and restart. [providers/devin.md](providers/devin.md) |
| `ChromiumLocalStorageTests` | The LevelDB reader: ordering, deletions, encodings, Snappy, fragments (including a zero-length FIRST), and malformed lengths, handles and batches through the real parsers. Synthetic stores. [providers/devin.md](providers/devin.md) |
| `DurationOverflowTests` | An overflowing stated duration drops the window rather than trapping (Kimi, Z.ai, LiteLLM, JetBrains). |

### Token spend and the detailed card

Synthetic stores, fixed clocks and UTC calendars; not live-client validation. [token-spend.md](token-spend.md), [token-spend-sources.md](token-spend-sources.md).

| Suite | Pins |
|---|---|
| `ModelPriceLookupTests` | Alias/vendor precedence and price-snapshot isolation. |
| `ModelPriceCacheTests` | Price-table expiry, retry after offline fallback (including version 4), an offline first run, failures keeping the original timestamp, one shared download. [token-spend.md](token-spend.md#caching) |
| `ModelPriceAliasTests` | One model, several spellings (Grok Build's `-build`, `k3-256k`, Kimi, Devin, MiniMax); an unpublished id stays unpriced, never billed at a near model's rate. |
| `VendorPriceTests` | A plan vendor's price only for that vendor, first-party rates winning; unknown models unpriced; OpenCode/Kilo dispatch; a pre-vendor cache only as offline fallback. |
| `ContextTierPricingTests` | models.dev long-context tiers (272001 means over 272,000): a request over the threshold priced wholly at the tier, never early. |
| `CacheWritePricingTests` / `OpenCodeReasoningTests` | A one-hour cache write at twice input; Claude Code's `cache_creation` share; OpenCode reasoning counted once. |
| `SessionPricingTests` | Unknown, mixed and published zero prices through records, transcripts, cache reloads and Today; missing cache coverage rejected. |
| `LedgerCacheWriteTests` | Unchanged repricing does not rewrite the raw cache; edits and deletions persist, a deletion into the archive. |
| `TranscriptCacheCodecTests` | The transcript cache's bytes read back as exactly the `FileCache` written (every optional both ways, bands, non-ASCII); a damaged or trailing file is no cache; the JSON cache is read once, written out as bytes even when a scan changed nothing, and removed. [token-spend.md](token-spend.md) |
| `SpendSummaryTests` | Calendar spans, priced totals without provider statistics, ranking, streaks, peak hours, exact integer sorting; broken categories cannot cancel; cross-midnight and resumed sessions count only in-span buckets. |
| `SpendSummaryCacheTests` | Scope/snapshot/calendar-window invalidation and cancellation; the activity series ignores the span and follows the agent. |
| `SpendSpanPreferenceTests` | The pane opens on a week by default; spans round-trip; an unoffered stored value falls back to the week. |
| `TokenActivityTests`, `TokenActivityPreferenceTests` | The year-long series: at most 53 week columns (never 54 in a leap year); after today undrawn, before the first record an `unrecorded` placeholder, never a count; a DST start (Cairo) keeps day keys; colour steps are quartiles of working days; the view round-trips, unknown opens Daily. [token-spend.md](token-spend.md#token-activity) |
| `SpendReadingTests` | Default-off; streaming boundaries; JSONL/SQLite cancellation and restart; WorkBuddy binary exclusions; disk-cache revalidation; Codex forks count only their own work. |
| `SpendReadStateTests` | Snapshot reuse, retention, release when disabled, rescan, retry, and fences against stale task completion. |
| `KeptSpendScanTests` | The last finished scan is kept until forgotten. |
| `LogLinesTests` | Exact streaming bytes across 1-byte to 64 KiB chunks, odd encodings, unterminated lines, slices and line lifetime. [token-spend.md](token-spend.md#read-memory-and-workbuddy) |
| `SpendReadPerformanceTests` | Opt-in (`PULSE_SPEND_BENCHMARK=1`) WorkBuddy and Codex reads with exact tallies and peak RSS; `PULSE_SPEND_BENCHMARK_LARGE=1` grows fixtures from about 138 MB to about 1.1 GB. One process per test for memory comparisons. [token-spend.md](token-spend.md#read-memory-and-workbuddy) |
| `ModelSpendSummaryTests` | One model's drill-down via `UsageLedgerReader.price` → `ModelSpendSummary.of`. Hours reconcile **per agent, per day, per raw id**, so no overcount cancels missing detail; money is priced **per raw id**, never merging two rates under one name; a part-priced name shows a subtotal beside `unpricedTokens`; a real zero rate is `$0`, not nil; missing metadata is counted, never invented. |
| `ModelSpendSummarySortingTests` | Missing values sort last both ways; token columns compare as exact `Int` (above 2^53), costs as `Double`. |
| `SpendFormatTests` | USD in English and Chinese with an explicit locale: true zero, a visible under-one-cent label, precise hover values. |
| `AgentStoreTests` | Non-Claude stores built in their measured shape: OpenCode priced from `ModelPrices`, never its own `cost`; Grok's per-model `modelUsage`; Kimi's `input_other` as fresh input; Kimi Code's request counted once from its `usage.record` with the endpoint prefix dropped, and once across the two Kimi stores; a missing store is absent, not empty. |
| `AgentCacheTests` | Change detection across nested and **hidden** logs, SQLite WAL (a real writer held open), price fingerprints and **multi-root** stamps; per-model detail survives `save`/`load`; old `agent-1`–`agent-3` shapes, pre-fix versions and missing session-day metadata refuse to decode. |
| `AgentSessionTests` | OpenCode, Grok, Devin CLI and Kimi sessions (priced and unpriced) over two days: buckets match reader totals, Today keeps only today, Devin's sibling nodes count once. |
| `UsageArchiveTests` | History survives a tool deleting records: deleted Claude Code transcripts, resumed copies counted once, a linked `~/.claude`, Codex forks and `archived_sessions`, a rollout in both folders counted once, WorkBuddy through `AgentLedgers`, time-zone changes; `archive-*` never superseded. [token-spend.md](token-spend.md#history-the-tools-have-deleted) |
| `DevinSpendReconciliationTests` | A session in both the native database and ACP mirrors counts once; empty or undated messages cannot suppress captures. |
| `SpendDataQualityTests` | Subagent transcripts folded into the parent's row; Codex titles skip injected context; titles cleaned of links; `SessionLabel` never falls back to a file name; scratch folders are no project; `PulseStorage.isSuperseded` picks only old `agent-<n>-` / `ledger-<n>-` names. |
| `SessionTitleTests` | Title trimming, envelope rejection, directory fallback; a later rename wins without disturbing token counts. |
| `ProjectIdentityTests` | Same-name directories, repeated paths across agents, Claude fallback folders, worktrees folding into their repository. |
| `AgentUsageRecordTests` | The normalized boundary: a bare total is never split into kinds or priced; partial and broken splits labelled apart; `isPartial` reaches `hasPartialCounts`; provider statistics stay out of summaries; aggregate timing lands on a calendar day, never an hour. |
| `AgentLogIOTests` | A count is whole, finite and in range, never a boolean or fraction; malformed JSON is a skipped line; file walks include hidden logs and exclude `-shm`; a missing database is opened read-only, not created. |
| `SessionLogReadersTests`, `SessionLogReadersParsingTests` | Group A: catalogue and dispatch, the Pi-shaped parser, Gemini, Qwen, Amp, Droid and OpenClaw. |
| `EditorLogReadersCatalogTests`, `VSCodeTaskLogReaderTests`, `ClineCLIReaderTests`, `EditorReaderChainTests`, `CommandCodeReaderTests`, `OpenCodeReviewReaderTests`, `ZCodeReaderTests`, `CherryStudioReaderTests`, `TencentBuddyReaderTests` | Group B: editor and standalone readers through to the summaries; Command Code rewind keeps consumption with branch-local attribution and replay deduplication. |
| `DatabaseLogReadersTests`, `AntigravityRootsTests` | Group C: database and event-log stores (Hermes, Goose, Zed, Kiro, Crush, Unsloth, Antigravity CLI, Micode, Devin Desktop); the Antigravity CLI and IDE read disjoint roots, both moved by `GEMINI_CLI_HOME`. |
| `StructuredLogReadersTests` | Group D: JSON/JSONL stores, cumulative snapshots split into increments, ambiguous reasoning omitted and marked partial. |
| `CapturedUsageReadersTests` | Group E: export/capture readers and the `UsageImports/<client>` drop folder; Warp's tokens-are-zero contract; cross-file reconciliation with `isPartial`; a cross-day Cursor CSV session never borrows yesterday's usage. |
| `CopilotLogReaderTests` | OTEL → Desktop → VS Code filtering so one call is not counted three times; a request without a timestamp is skipped, not dated at the epoch. |
| `SpendAgentCatalogTests`, `AgentIconTests` | Seven verified readers plus forty-seven added clients in six disjoint families; legacy readers keep their paths and `rawValue`; "recognised" never reads as "counted"; every named icon loads, a provider-backed agent reuses the provider's file. |
| `CardHistoryTests` | Which providers the card shows history for and from where, and that the settings pane has one wherever the card does; several agents add day by day with quarter-hours in order; no value estimate where the provider states the allowance. |
| `BudgetEstimateTests` | A limit's worth is in-window spend up to the reading over its percentage; too little use, an earlier reading or a lengthless window gives none. |
| `CacheHitRateTests` | Cache reads over every input token; withheld where records cannot vouch for their split; per model, raw ids of one model on one line. |
| `PromptCacheLapseTests` | Claude Code's cache lapses a tier after the last request (a tool result counts), not the answer's end; subagent lines are not the session. |
| `CodexPromptCacheTests` | Codex's thirty-minute floor on GPT-5.6 and later, from the last request touching the cache; earlier models untimed. |
| `ReplyTimingTests` | Speed and first-token wait: a reply copied into a resumed session counts once; five timed replies per model within a day required; implausible values not timed. |
| `CodexSignalsTests` | Signs of a weaker model: reasoning on the 516, 1034, 1552 … lattice; model or effort changes mid-turn; Codex before 0.144 not judged; fork copies skipped. |

### Recap

| Suite | Pins |
|---|---|
| `RecapTests` | Period bounds (a month holds its own days only; the previous period aligned, clamped, nil when empty); every nil case; the 04:59/05:00 edge; cache savings; the hit rate agreeing with `UsageLedger.cacheHitRate`; `SpendSummary.of(_:from:until:)` cutting sessions at both edges; streaks never longer than the period; the poster's cost line withheld by one unpriced day; `--recap` JSON omitting a missing figure. [token-spend.md](token-spend.md#the-recap-and---recap) |
| `RecapInsightsTests`, `RecapVendorMarkTests` | What the redesigned cards read off a recap (weekdays, weeks, runs, hours, dearest day, bars withheld when one working day is unpriced) and which bundled mark a model gets, else a monogram. [recap.md](recap.md#the-four-redesigned-cards) |
| `RecapDeckTests` | Which cards a deck has — a card is left out when its figure is missing — and payback charging a running month or year by the days gone. |
| `RecapScoreDataTests` | The score card's bars (days to come drawn as future, not quiet), cost line, sessions per active day and change against the period before, a missing figure left out rather than drawn as zero. |
| `RecapDayWeekTests` | Day and week bounds (midnight to midnight; 23- and 25-hour days; Chile's skipped midnight; February 30 refused, a leap day kept), the period before across a year, a week starting on the first weekday asked for, offered and default days and weeks, switching kind on the last day so far, `--recap` keys, a running week against the same days of the week before, payback by day, and which cards a day and a week get. [recap.md](recap.md#days-and-weeks) |
| `RecapFormatTests` | Numbers, money, times, weekdays and months in each language's own units and names, agreeing with `TokenCount.short`. |
| `RecapWindowTests` | Offered periods and the opening one (the month just ended during days 1–7, the running one from the 8th); typed prices (nothing and 0 are no price; over 10,000 refused); `RecapPeriods.earliest` clamped to 2020; a late cancelled read never replaces a newer one. **The notification rule**: on the 1st with records last month, once per month, never for a month without tokens or before a scan, only in the first three days and about the month before. [recap.md](recap.md#the-window), [notifications.md](notifications.md#the-monthly-recap) |

### The animated mark

Tested where it fails silently: a mark reading `idle` about a signed-out provider, or a black body on a black disc, crashes nothing. What the animation *looks like* is a screenshot question and is not tested; motion a screenshot cannot show is measured off the frames. Local engine frames, not real panel input. [ui/rings-and-surface.md](ui/rings-and-surface.md#animated-marks)

| Suite | Pins |
|---|---|
| `BotMarkTests` | Mood and persona rules (no state contradicting the reading), neighbouring rings never within 30° of hue, contrast against the disc, a whole table (18 shapes of 96 points, 25 eye pairs, 39 states). Working pumps harder than idle and throws ribbons within thirty seconds — both failed when written, because a spring swallowed the rotation emphasis. The original animation may run past the viewBox, so there is no position bound. |
| `BotMarkRestTests` | Through `BotMarkProgramme.forMood`, sleeping, powering-down and bored never appear and drowsy only for sleepy, in every mood and context; two-minute simulations allow no resting frames for other personas and keep sleepy's night idle accent under a quarter. |
| `BotMarkContinuityTests` | Ninety seconds of seeded switching per persona: no frame at 30fps moves more than 30 units or 30°. Before `BotMarkEngine.render` carried the difference across a state change, interrupted turns reached 144° and 108 units; ordinary motion peaks near 15° and 16. Fails against the unfixed engine. |
| `BotMarkAttentionTests` | The largest one-frame eye step as the pointer arrives (median of twenty-one runs, playful left out): before `attention` was eased, 30–60 units; after, 1–5. |
| `BotMarkChoreographyTests` | Personalities stay distinct (eight idle signatures; everyday states disjoint from **every** persona's work states); no idle ribbons; event particles stop with playback; every beat visited in order within the rail's movement budget. |

### Rendered for review

These write PNGs for a person to read and assert nothing about pixels; each runs only when its variable is set.

| Suite | Run |
|---|---|
| `BotMarkChoreographyTests` (contact sheet via `drawBotMark` and `ImageRenderer`) | `PULSE_BOT_PREVIEW=/path/to/existing/folder/bot-personalities.png swift test --filter renderContactSheet` |
| `RecapRenderTests` (every card of the day, week, month and year decks, every language) | `PULSE_RECAP_PREVIEW=/tmp/recap swift test --filter RecapRenderTests` |
| `RecapWindowRenderTests` (window chrome in five states, AppKit controls via `cacheDisplay`) | `PULSE_RECAP_WINDOW_PREVIEW=/tmp/recap-window` |
| `TokenActivityRenderTests` (three views, light/dark, zh-Hans/en, 460 and 900pt) | `PULSE_ACTIVITY_PREVIEW=/tmp/activity` |
| `TokenKindRenderTests` (model detail and day table, all six languages, 480 and 900pt) | `PULSE_TOKEN_KINDS_PREVIEW=/tmp/token-kinds swift test --filter TokenKindRenderTests` |

## What is not, and why

**No UI tests.** Synthesised events cannot drive the accessory `NSPanel`'s hover: `hitTest` and synthetic `NSEvent`s reported a handle reachable while real clicks were dropped ([ui/input.md](ui/input.md)).

**A rule test is not a chain test.** `AlertMemoryTests` feeds the state machine directly, and review twice missed a defect between service and machine: the cache swapped a failure for cached figures and lost the reason. Test a rule through whatever it depends on upstream.

**No network, no clock, no disk in a rule test.** That is why `AlertMemory.alerts` takes `now` and `UsageCache.init(file:)` takes a path.

**No live provider calls.** Every route needs a real credential and answers differently by plan. Fixtures are captured by hand from a real reply and committed; the provider's page records the capture.

**A second-hand fixture says so where it lives.** One written from another project's parser or a vendor's shipped client is second-hand: Volcengine's (nobody here holds that plan) and Command Code's (field names from its published npm bundle). It pins a shape against change, not that the shape is right; a captured one replaces it when someone with an account can produce one.

**The added agent readers are spec evidence, not machine evidence.** Their suites read hand-built stores in the documented shape through the production reader; no one's transcripts are committed, and no reader written from a second-hand format spec has run against the product that writes it. A reader reporting `notes` (a transcript it could not decode) is validated no further than the suite's store. Each source's evidence is marked in [token-spend-sources.md](token-spend-sources.md).

**A subprocess test really spawns one.** `VolcengineProcessTests` runs `/bin/sh` because a child that fills the stderr pipe or never exits cannot be faked and is invisible to reading: two versions of the runner looked correct and hung. The deadline is a parameter so a test can use one second.

**A kill is timed from the child's side, not by the `await`.** The runner enforces its deadline on a global queue, but the caller learns of it only when its task resumes on a cooperative thread, and Swift Testing runs synchronous tests on that same pool. On a three-core CI runner a few long ones held it for about 19 seconds, so every test started meanwhile reported 18–19 seconds — pure parsing ones too — and children killed at three seconds were measured at twenty-two, failing `< 20` on main from 1.12.1 (2026-10-16) until 2026-10-18. Saturating the pool locally reproduces it: the child dies on time, the caller resumes when the pool frees. `ProcessDeathWatch` reads the pid the script writes to a file, polls `kill(pid, 0)` on a thread of its own, and kills a survivor after thirty seconds. `VolcengineProcessTests` and `ExtensionRunTests` assert death within ten seconds of a one-second deadline (deadline, the two-second exit wait, the two-second SIGTERM grace, five of margin), and the return only well below the child's own five-minute life. Both still fail at once with the kill disabled, and pass under a 50-second pool stall.

**Integrations are tested outside `swift test`.** In `Integrations/raycast`, `npm ci` then `npm test` runs `tests/report.mjs` against the TypeScript consumer and the real shell formatter (gaps, balance-only accounts, estimates, account selection, tmux escaping); `npm run build` and `npm run typecheck` check the extension. Real Raycast/sketchybar UI and macOS URL delivery need the host apps and a bundled Pulse. [integrations.md](integrations.md)

## CI compiles the tests with an older Swift

A local pass does not prove CI will compile. The `macos-26` runner's Swift is older and stricter: it would not convert a `CGFloat` into a `Double` tuple element on assignment, which local Swift 6.4 accepts, and that line in `BotMarkContinuityTests` failed the 1.4.0 release (measured then). Write `CGFloat` ↔ `Double` conversions out in tests, as the app code does.

## Conventions

**The executable target is tested directly** (`@testable import Pulse`, allowed since Swift 5.5). Pulse is one app; splitting it into two targets for the test runner would be a refactor for its own sake.

**A symbol may be `internal` instead of `private` so a test can reach it**; its comment says so and says not to tidy it back (`AntigravityUsageService.Reply`, `windows(from:)`).

**A suite that reads or writes `PanelMetrics`, or measures `DockLayout`, is nested in `PanelGlobalsSuite`** (`extension PanelGlobalsSuite { @Suite struct … }`), which is `.serialized`. `PanelMetrics` is process-wide and Swift Testing runs top-level suites in parallel, so `.serialized` on one suite alone let another change the globals mid-measurement and `FreeAcrossTests` failed intermittently. Nested there: `RailGeometryTests`, `PanelHoldTests`, `RailOffsetTests`, `FreeLyingRailProportionTests`, `NotchGeometryTests`, `PanelIntentTests`, `FreeAcrossTests`, `BottomDockTests`, `CardRoomTests`, `RailMoneyTests`, `DropletTetherTests`.

**Nothing outside `PanelGlobalsSuite` may move the globals either, and `AppSettings.restored()` does**: it rewrites every metric, the ring budget and the language from the runner's defaults domain (`swiftpm-testing-helper`, which other tests write to) and never puts them back. A real `AppDelegate()` restores, so when `MenuBarIconSettingTests` built one, `FreeAcrossTests` failed whenever it ran after it — about one full run in several (2026-10-13). A test that needs a delegate builds `AppDelegate(settings:)` on isolated defaults.

**Resolve a SwiftUI `Color` on the main actor.** A colour backed by an `NSColor` provider (the usage colours, `Color.pulse*`) syncs onto the main thread to resolve; two tests doing it at once from the cooperative pool deadlocked the run (2026-10-09). `UsageTintTests` is `@MainActor` for this.

## Fixtures

`Tests/PulseTests/Fixtures/` is copied whole into the test bundle so a schema change diffs readably; read with `Bundle.module.url(forResource:withExtension:subdirectory:)`. Captured payloads carry no account name, email or token — check before committing. A quota reply should be bucket ids, display names, fractions and reset times, nothing more.

**A temporary fixture removes only the root it created.** Never `deletingLastPathComponent()` from a fixture path: above a file in the system temporary directory is the system temporary directory. `AgentStoreTests`' `temporary(_:)` returns the owned root, and each test defers a `removeItem` on exactly that URL.

**A throwaway defaults suite comes from `TestDefaults.make(_:)`, never `UserDefaults(suiteName:)` with a plain name.** A named suite is a plist in `~/Library/Preferences` that cfprefsd writes back even after `removePersistentDomain` and deletion (2,331 had piled up by 2026-10-09). The helper names the suite by an absolute path in its own temporary directory and removes that directory.
