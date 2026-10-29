# Notifications

Owns: when Pulse posts a system notification, what it says, and what it refuses to say. Settings copy and layout: [ui/settings.md](ui/settings.md). Where readings come from: [refresh-and-data.md](refresh-and-data.md).

Source: [`Sources/Pulse/Usage/UsageAlerts.swift`](../Sources/Pulse/Usage/UsageAlerts.swift). Settings: `AppSettings.alertThreshold` / `alertsOnReset` / `alertsOnFailure` / `lowBalanceAlerts` / `alertsOnOutage` / `alertsOnRecap`. Every fetch goes through `UsageStore.commit(_:raw:for:)`, which passes both the raw result and the reconciled display reading. An explicit notification-setting change also calls `reconsiderAlerts()` after authorization succeeds. Limit alerts use `ProviderUsage.current(at:)` to omit windows whose reset or whole-bucket expiry has passed; reconsidering such a reading also requests a refresh.

## What can be said

Seven things, and nothing else — each something you would want to know *while looking at something else*.

| Alert | Fires when | Gated by |
|---|---|---|
| `approaching(percent:)` | A window's used share reaches the chosen step | `alertThreshold` |
| `spent` | The provider reports the window exhausted, or the share rounds *down* to 100 | `alertThreshold` |
| `reset` | A window that was warned about has unambiguously turned over | `alertsOnReset` + `alertThreshold` |
| `unreadable(_:)` | Three eligible failures; cached figures remain protected for their first 30 minutes, while a failure with no usable figures counts immediately | `alertsOnFailure` |
| `lowBalance(remaining:)` | A prepaid balance falls under the figure set for that account | `lowBalanceAlerts[account]` |
| Service outage (`OutageMemory`) | A provider's own status page (44 have one) reports a component its account runs on down, worse, or back | `alertsOnOutage`, and the provider switched on |
| Recap ready (`RecapNoticeRule`) | In the first three days of a month, last month had records in the scan Pulse already holds, and that month has not been announced | `alertsOnRecap`, and Token spend reading on |

**All off by default. All use the default sound; muting is macOS's own per-app "Play sound for notifications".** A notification with no `sound` is silent and the system switch cannot add one back (it only removes a sound the app asked for), so a silent notification leaves no working off switch and a banner on another display goes unseen. One rule for all, since macOS has one switch per app. `requestAuthorization` asks for `[.alert, .sound]`: without `.sound` in the grant, `soundSetting` is disabled and every `content.sound` is dropped.

### A `balance` window is not a limit, and neither is a `topUp` one

Guarded on the kind, pinned by `AlertMemoryTests`:

- **`Kind.balance` (prepaid credit) never resets.** `resetsAt` is nil, so `movedOn` is never true, and the forty-point fall is not evidence (on DeepSeek that fraction is a setting).
- **Only `isExhausted` may call a `balance` spent**, not the step rule clamping against a denominator Pulse observed or the reader typed.
- **`Kind.topUp` follows both rules.** V2EX's 加油包 is bought on top of the window's allowance, with no expiry or clock ([providers/v2ex.md](providers/v2ex.md)); a second pack drops the fraction over forty points with nothing turned over. Only V2EX's `remaining_tokens` may say the pack is gone.
- **`Kind.credits`, `Kind.sharedCredits` and Qoder's parts (`planCredits`, `dedicatedCredits`) reset only when `nextResetAt` moves forward**, never on the forty-point fall: a bought pack raises the limit ([providers/qoder.md](providers/qoder.md)). A team pool states no reset and is never announced as reset. StepFun's Token Plan is the same kind ([providers/stepfun.md](providers/stepfun.md)): a monthly plan states no refill date, so its renewal is not announced.

A provider may report a grant identity as `UsageWindow.cycleID` independently of its stable row `id`. Alert memory persists that identity; a change between two known identities clears the announced threshold without announcing a reset. DimAgent uses its reported bucket ID so a new subscription grant can warn once again while a pinned plan-credit row stays pinned. Missing identity (including old saved state) is not evidence of a new grant; the first known identity is adopted without clearing the prior threshold. Cache windows and alert memory decode older records without this optional field.

### Low balance is about money, not a share of anything

Prepaid providers (DeepSeek first) report **no allowance**, so `alertThreshold` has nothing to act on; the warning is about the money.

- **It asks for permission like the others.** Entering a figure calls `requestAuthorizationIfNeeded`, then reconsiders current readings, so a balance already under the line is announced once. (Without it, `observe` bailed on `.notDetermined` forever on a fresh install.)
- **Per account**, because providers price in different currencies. `Provider.reportsSpendableBalance` lists the providers that hand over `ProviderUsage.creditRemaining` (a number *and* a currency), unlike the display string `creditBalance`, which for Codex can be "Unlimited".
- **Live readings only**, as for limits: the account may have been topped up since the cache banked its figure.
- **Once.** The memory records the figure warned about, so **moving the line warns again**; climbing back over re-arms it.
- **Nothing is said when it comes back.** Only the reader refills it.

### A service outage is the provider's word about its service

Requested 2026-10-04, after the status rows on the Codex, Claude Code and DeepSeek panes; Cursor's joined on 2026-10-15, and the same day every provider with a page Pulse can read (44, [providers/README.md](providers/README.md#service-status)). One switch, **When a service is down**, off by default; its subtitle names no provider. Pinned by `OutageMemoryTests`.

- **Only for a provider switched on.** `UsageAlerts.checkServices` reads the pages of providers among `shownAccounts` only.
- **Only about what the tool runs on** (`StatusPage.notifiesAbout`: the rows the pane shows, narrowed by the page's `notifies`). Claude: of the six status.claude.com components the pane shows, only **Claude Code** and **Claude API**, by id. Codex: its Codex group, all four. DeepSeek: rows whose name contains "API" ([providers/deepseek.md](providers/deepseek.md#service-status)). Cursor: the IDE, the CLI and Cloud Agents, by id ([providers/cursor.md](providers/cursor.md#service-status)). Every other provider's: the table in [providers/README.md](providers/README.md#service-status).
- **Down means the page says so**: degraded performance, partial or full outage. Maintenance and unreadable values are not outages; an unreadable page changes nothing.
- **Once per outage.** Said when a component first goes down, again only when worse (degraded → full), and once when operational again — only if it was announced. Better-but-still-down is recorded silently. An outage already under way when the switch goes on is said at once: the switch calls `checkServices` itself (not `reconsiderAlerts`, which would refetch every provider), and so does launch, right after the grant is read.
- **Only what is still watched is remembered.** Memory is per page. A component no longer listed (a Statuspage row shown only while degraded) and a page no longer watched (switch or provider off) are forgotten silently; kept, they silenced the next outage and later said "back to normal" about one that ended unwatched.
- **One odd entry is skipped, not fatal.** Component lists decode entry by entry; a null name on an unrelated component once failed the whole page.
- **One notification per provider**, every component in one sentence ("OpenAI reports CLI (Partial outage) and Codex API (Degraded performance)."), identifier `service-status-<provider>`, so a newer one replaces the last.
- **Every five minutes, on its own clock** (`ServiceStatus.checkInterval`, a loop `UsageAlerts.start` begins), not the refresh pass, which stretches to 30 minutes when idle. Not more often: status pages are written by people minutes into an incident. A tick returns at once unless the switch is on and a provider with a page is in use. The sleep is on the continuous clock, so a tick due during sleep runs right after waking. Each check reads only the current state, one request per feed — a company's page shared by two providers (Cursor and Grok Bot) is read once; one check at a time, its feeds concurrently.
- **Its own file**, `status-alerts.json`, not a field on `AlertMemory`: that type decodes as a whole, and a key old files lack would discard every limit already warned about. This switch alone writes no `alerts.json`.

### The monthly recap

"Your September recap is ready", about the month that just ended. Off by default; **When a recap is ready** in the Notifications pane, greyed out in an unbundled build and, to turn it on, while Token spend reading is off (a switch already on stays operable). Opens [the recap window](recap.md#the-window). Rule: `RecapNoticeRule` (pure, `Usage/RecapPeriods.swift`); clock: `RecapNotice` (`Usage/RecapNotice.swift`). Pinned by `RecapWindowTests`.

- **Only what Pulse witnessed.** It reads **only the scan `SpendWarmer` already keeps** (`AgentLedgers.keptSnapshot`), never a read of its own, and only while Token spend reading is on. Last month's tokens come from `SpendSummary.of`, off the main actor. No kept scan yet is "not known": nothing is said or remembered, and the next check asks again (`RecapNotice.launchDelay` 90 seconds after launch, then every 30 minutes, `checkInterval`).
- **Only when the month had records.** Zero tokens is never announced.
- **At most once per month.** `AppSettings.recapAnnouncedMonth` ("2026-09") is written **before** the notification is handed to the system, shown or not, so a relaunch, a second check, toggling the setting or a refused grant says nothing more.
- **The first three days only.** The 1st, or the 2nd and 3rd for a Mac shut or asleep on the 1st. Switching on inside those days announces at once (the limits' "already past the line" rule); outside them it waits for next month.
- **Default sound**, as [above](#what-can-be-said).
- **Clicking opens the recap window on that month**, not Settings: `NotificationTapHandler` reads the month from the identifier `recap-ready-<yyyy>-<mm>`.
- **Months only.** Day and week recaps ([recap.md](recap.md#the-window)) say nothing: a daily notice would come every morning about something the reader can open at any time, and a weekly one is the same at a lower rate.
- **Not a usage alert.** `wantsUsageAlerts` excludes it (no `alerts.json` entry); `wantsAlerts`, which decides whether permission is worth asking for, includes it. `AppSettings.onRecapAlertChange` asks for permission, not the view.

## Rules that are not obvious

**A first sighting starts at nothing announced**, so a limit already past the line is said once, immediately — including when the setting is switched on or the threshold lowered (`UsageStore.reconsiderAlerts()`). Otherwise someone who switches it on at 93% gets silence and then a wall; the cost is at most one notification per limit.

**Copy is a status, not an event** — "92% used", never "just passed 90%" — so it stays true whenever read.

**100% is the provider's word.** `spent` comes from `UsageWindow.isExhausted`, or a share reaching 100 rounding *down* (99.6% stays 99). See [decisions/reported-figures.md](decisions/reported-figures.md).

**Limits are judged on `.live` readings only.** A `.stale` reading can carry a cached figure *lower* than the recorded one, and a falling figure is how a reset is detected; the cache once announced a reset on every network hiccup.

**A live snapshot is not live forever.** Limit rules need a dated reading no older than the cache's 24-hour maximum and skip windows whose reset time has passed. Reconsidering applies the same guards and requests a refresh when a displayed reading is stale, undated, too old or has an expired window; valid windows can still warn at once.

**A reset needs unambiguous evidence**: the reset time moved forward by more than a minute, or the share dropped 40 points or more (`UsageWindow.hasTurnedOver(since:resetsAt:)`, [refresh-and-data.md](refresh-and-data.md)). A 5-point drop says nothing; a rolling window (Kimi's week) slides a few points at a time.

**The announced step is cleared by that same evidence, not by any drop.** Clearing on a 5-point dip re-announced 95% → 89% → 93% (`oscillationDoesNotReAnnounce`). A reset is only announced for a window warned about on the way up, which is why the reset row is greyed out while the threshold is Off.

**A push route going quiet is never a failure.** Claude Code's status line writes only while a session runs, so its capture goes stale ten minutes after the last response; that means nobody used Claude Code. `UsageSource.reportsOnlyWhenUsed(for:)` is the flag; `AlertMemory` takes it as `staleMeansFailure`.

**A reading from an app's own saved state is spared too.** Devin's figures are written when its app launches, so stale means not relaunched. `UsageAlerts.staleMeansFailure(route:raw:for:)` spares `UsageRoute.appCache` (by the raw reading's recorded origin) as well as the push route. The *origin* is spared, not the provider: an `.endpoint` failure on Devin still counts.

**The push exemption belongs to the route, not the provider.** Of Claude Code's four routes only one is a push; `.endpoint` and `.desktopApp` ask a server every pass, and an **added** account has no status line. The exemption covers only the primary Claude Code account on `.automatic` or `.tooling` (conservatively, by configured route, since a capture remains eligible to answer). Neither exemption excuses an endpoint failure.

**`.stale` alone is not a failure** for the rest. `UsageCache.reconciled` returns a stale reading for a *successful* fetch too, when a newer banked reading beats a capture the status-line route still calls live.

**Classification uses the raw fetch, not the cached replacement.** A closed Antigravity's raw `.antigravityNotRunning` stays neutral however old its cached figures. A genuine failure behind the cache counts only after `stalenessBeforeSaying` (30 minutes). A raw live answer clears the streak even if reconciliation shows a newer cached reading. A service's own raw `.stale` is judged by age and the push-route exemption.

**Unavailable is not failed.** `AlertMemory.standing(of:)` exhaustively sorts results into:

- **Failure:** a credential that went bad, a request that did not get through.
- **Answered** (clears the failure streak and the reported-outage mark): complete answers without numbers — `grokBotNotIncluded`, `noLimitsReported`, `zaiNoCodingPlan` (a working key with no plan).
- **Neutral:** setup steps (`apiKeyMissing`, `notSignedIn`, `volcengineSignInRequired`), an app not running, and `systemProxyOff` (Pulse chose not to ask; [networking.md](networking.md#holding-back)). Ark CLI's generic sign-in response cannot tell never-configured from expired, so it is not evidence of an outage.

**Three failures, not one** — six minutes to an hour and a half at the 2–30 minute interval. These endpoints are undocumented; one dropped connection is not news. Reported once per outage: `reportedFailure` is cleared only by a working reading.

## Memory

`AlertMemory` is persisted to `alerts.json` in [`PulseStorage.directory`](../Sources/Pulse/Usage/ModelPrices.swift), keyed by account id, then window id — except `lowBalanceWarnedFor`, per account. It must be on disk, or every relaunch (Pulse starts at login) would re-announce everything over the line.

It is updated even when a grant was refused or the build is unbundled, so neither later announces a backlog. **An unresolved authorization is different:** readings are not consumed while authorization is unknown in a bundled app or a request is in flight; they stay eligible for the evaluation after a grant.

`AlertMemory.alerts(for:as:…)` is pure apart from `self`; the clock is passed in as `now`. Every rule here is covered by `AlertMemoryTests` ([testing.md](testing.md)); change one, change that.

`UsageAlerts.observe` returns at once when `AppSettings.wantsUsageAlerts` is false (`wantsAlerts` adds the outage and recap switches, for permission only), so nothing is tracked or written for a feature nobody switched on.

## Test notification

**Test notification → Send**, at the foot of the Notifications pane, posts one notification now (`UsageAlerts.sendTest`) so the reader can see that notifications reach them. It is the one notification about nothing Pulse saw — the reader asked for exactly that, and its text says it is a test. It asks for permission whatever is switched on (pressing the button is the request), is remembered nowhere, and uses the default sound. The row then says what came of it: sent (with where to look if no banner appeared: Focus, System Settings › Notifications), turned off for Pulse in System Settings, or not yet allowed (the prompt closed without an answer; pressing again asks again). Greyed out in an unbundled build.

## Permission, and the unbundled build

`UNUserNotificationCenter.current()` raises without an app bundle and kills the process. `swift run` builds a bare executable, so every entry point is guarded by `UsageAlerts.isSupported` (`Bundle.main.bundleIdentifier != nil`) and the Settings row says why the switches are dead. **Test notifications from `./Scripts/bundle.sh`, never from `swift run`.**

Permission is asked when a switch goes on in Settings, never at launch (a prompt for a feature nobody switched on gets denied for good). The request is awaited before reconsidering readings; concurrent changes share one in-flight request. Refreshes finishing while the prompt is open update the display but cannot mark warnings announced. A refused request triggers no reconsideration; the completion re-checks that alerts are still wanted.

The delegate implements the completion-handler `willPresent` and requests banner, list and sound even while Settings is active; otherwise enabling a warning in Settings could consume it while macOS suppressed it. System notification and sound settings still apply. Tests verify authorization ordering and the delegate selector, not real banner delivery.

The subtitle reports `UNAuthorizationStatus`, not the switches, since a grant can be withdrawn later. **It is re-read every time the settings window opens** (`refreshAuthorization`); read once at launch, it showed alerts on while macOS discarded them.

## Clicking one

Opens the Settings window on the last-shown pane (except the recap notification, above). Not the account's own pane: the selection is `SettingsView`'s state, and threading it out is not worth it.

The delegate uses the **completion-handler** spelling of `userNotificationCenter(_:didReceive:withCompletionHandler:)`. These are optional protocol requirements, so a mismatched signature compiles and is never called.
