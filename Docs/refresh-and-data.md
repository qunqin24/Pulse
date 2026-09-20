# Refresh, cache, activity, history

Pulse shows **figures the provider reported**. It does not invent a usage percentage from local token counts. If a provider reports no figure, the UI says so. Labelled exceptions only, and each says on screen that it is inferred: the money estimate in Settings; Command Code's monthly plan grant, whose remainder is reported while its size is published only on a pricing page ([providers/command-code.md](providers/command-code.md)); and DeepSeek's ring, where nothing at all is reported but the money ([providers/deepseek.md](providers/deepseek.md)).

Per-provider HTTP, cookies, and login: [providers/README.md](providers/README.md). Why percentages stay reported: [decisions/reported-figures.md](decisions/reported-figures.md).

What Pulse says about these readings unprompted: [notifications.md](notifications.md). What it hands to anything outside the panel: [json-output.md](json-output.md). **Every fetched reading is written through `UsageStore.commit(_:raw:for:)`**, which gives alert rules both the raw result and the reconciled display reading. Seeded placeholders and restored cache do not enter the rules. Explicit notification-setting changes reconsider valid live snapshots after authorization, and request a refresh if current readings are stale or expired.

## Refresh loop

`UsageStore` is `@Observable`. The interval is **adaptive by default** (`AdaptiveRefresh`): **2–30 minutes** (`floor` 120s, `ceiling` 1800s). It is **not** a 60-second repeating timer. (An older comment on `UsageStore` said that; the code schedules a one-shot.)

Monitoring begins only after a non-empty provider choice. Before that, constructing a store creates credential-free placeholders, and `start`, full refresh, per-account refresh and settings changes cannot read or fetch providers. Cache restoration reads only enabled accounts. The chooser and upgrade rules are in [architecture.md](architecture.md#provider-choice-before-monitoring).

Because the wait changes each pass, `scheduleNext` sets `Timer.scheduledTimer(..., repeats: false)` and reschedules after every refresh.

**One timer, but not one cadence.** Under `.automatic` each provider has its own interval and the timer is set for whichever is due soonest; a pass then asks only the accounts that are actually due (`UsageStore.providersToAsk`, paced from `askedAt` — *asked*, not answered, or a provider that refuses every time reads as permanently due and spins the loop). Everything not asked keeps the reading it has, because the commit loop is gated on the same set. A **fixed** interval chosen in Settings applies to everything equally: somebody who picked five minutes meant five minutes.

`UsageStore.currentInterval` stays **the cadence**, not the countdown to the next tick: Settings renders it as "Now: X minutes" and `isOverdue` multiplies it, and both broke when it briefly became the wait — a timer set for the last fifteen seconds of somebody's cycle read as "Now: 0 minutes".

**`refresh(dueOnly:)` is true for exactly one caller — the timer.** Every other route into a pass is *something happening*: a setting changed, a window reset, the display woke, the app server pushed, the pointer arrived at a rail whose figures are older than the cadence allows. Each of those is a reason to look now, whatever the cadence says. Getting it backwards is not a slow refresh but **a control that does nothing**: switching DeepSeek between "since top-up" and "balance only" changes what the reading means, and a pass that skipped the provider because it had been asked a minute ago left the old ring on screen. `providersToAsk` is `nonisolated static` and pure so that rule is pinned by `RefreshPacingTests` rather than by hand.

Signals (every one is a reason to wait **longer**, never shorter):

- CLI transcript metadata (`AgentActivity.lastWrite`) — not a second file scan
- Whether reported `windows` actually moved (`observedAt` is ignored for this comparison or every fetch looks like a change)
- Whether the rail was hovered (`noteLooked`)
- Whether the panel is on screen
- Low power, thermal, display asleep

#### The one asymmetry: providers this Mac cannot watch

Every signal above is local, which is the module's whole advantage — Pulse can see an agent working without asking anyone's server. It also means a provider billed entirely on **its own** servers is invisible to all three activity signals and lands on the ceiling every time. That is circular: it waits half an hour because nothing changed, and nothing appears to have changed because it waited half an hour. For prepaid credit draining towards zero — DeepSeek, Command Code — being half an hour late is the one case where it costs something.

So `AdaptiveRefresh.interval(for:isWatched:)` caps those at `unwatchedCeiling` (300s). `Provider.spendingIsWatchedLocally` is the flag, and it is the inverse of `reportsSpendableBalance`.

The cap **only ever lowers** a wait the ladder already decided, which keeps the module's rule intact: no signal here may make anything wait longer. And it is beaten by the two short-circuits above it — a constrained Mac and a hidden panel — because those are statements about *this machine*, not about the provider.

Manual interval in Settings still exists. The group is named **Refresh**, not Updates (the app has Sparkle now).

### Stalls

The timer is not a promise: `scheduleNext` only runs when a pass **finishes**. A pass that never returns takes the whole schedule with it.

Guards:

- A pass in flight longer than `passCeiling` (180s) is treated as gone (full and per-account paths).
- `noteLooked` refreshes when the newest reading is older than twice the chosen cadence — but **never-read is not overdue** (`observedAt` missing). There is a cooldown: sweeping the rail must not fire one request per ring.
- Observe `NSWorkspace.didWakeNotification` **and** `screensDidWake`; they are different notifications.

Releasing a stalled pass is not ending it. Abandoned work still writes when it answers. Every pass is stamped (`generation` / `currentPass`) and must still be current before writing `usage` or clearing flags.

Disabled providers are not fetched by the loop or by opening their Settings pane. After initial setup, a deliberate refresh can still ask that account by name. Automatic history loading is restricted to enabled primary accounts, and Codex's account-history method checks the primary account is enabled before starting its helper.

`windowSeconds` is not evidence that a length was reported. `UsageWindow.reportsLength` distinguishes a real duration from a sort key. The window-clock arc and burn-rate divide only when the length was actually stated.

## Cache

`UsageCache` keeps the last good reading per account so a refusal can show numbers with a date instead of an empty error. They come back marked `.stale` (the card’s “as of” line).

- A window whose **reset time has passed is dropped**, not aged. If every window has reset, report the error.
- 24h cap for windows that never say when they reset.
- Missing credentials are **not** papered over (`.apiKeyMissing`, `.ollamaSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn`, `.claudeDesktopKeyRefused`).
- **The age rules are not only the read-back path's.** A `.live` reading can still be old: `observedAt` is when the *provider's* figures were taken, not when Pulse asked. `reconciled` now filters a **directly fetched** reading the same way it filters a restored one — a window whose reset has passed is dropped, and a reading past the 24h cap is refused — before it is banked or drawn. Devin is why: its figures come out of a row its own app writes at launch, so a fresh fetch every few minutes keeps returning the same morning-old stamp ([providers/devin.md](providers/devin.md)).
- **A saved plan is banked even when it is stale.** Devin's comes out of the app's own persistent store rather than a request that can be repeated, so `reconciled` keeps it; it is date-stamped, and `--json` — which never fetches — reads only what is banked. Without that the panel would lose the last plan the app wrote once the fresh window passed.
- **Routes that need not be one account — or one organization — do not share a fallback.** Devin's endpoint is organization-scoped while the row its app saved is keyed by a user id only, so even the same user can be two organizations' allowances. `ProviderUsage.requiresScopeMatch` is computed from the provider, and every fallback, every "newer reading wins" and every save agrees on a `UsageScope` of **route, organization and identity**; a missing organization or identity is never a wildcard. There is no hand-set flag for a return path to forget.
- `.live` is not the same as “newest.” A route can mark a capture live for a few minutes while an earlier endpoint reading has a later `observedAt`. `reconciled` prefers the later stamp.
- `UsageStore.start` paints the cache before the first request so the rail is not blank on a cold start. Cache never undoes a fetch that has already landed.

Which unavailability cases a given provider emits: [providers/README.md](providers/README.md).

### Connection diagnostics

`UsageStore.commit` also records a `ConnectionDiagnostic` per account, separately from the reconciled display reading. It retains the latest raw result, completed-check timestamp, route checks and the newest successful reading timestamp. The last of these uses the reading's own `observedAt`: re-reading a status-line capture never advances it to the time the user clicked Retry. Restored cache and seeded placeholders do not manufacture a completed check; the UI says no check has completed since launch.

`ProviderUsage.origin` records the route that produced the figures. Cache entries persist that optional origin; old entries remain unknown. `isCached` is set only by cache restoration, so a stale status-line capture displayed directly is not called a cache replacement. Route attempts are not saved with the figures. Single-route providers are labelled at reconciliation and diagnostic commit; the three multi-route services record their own branches ([providers/README.md](providers/README.md)).

The copied diagnostic report is a fixed allowlist: app version, provider, primary/added account kind, route preference, typed outcomes and timestamps. It omits account ids and labels, plan names, amounts, paths, credentials, headers and response bodies. Tests pass results through the real cache before checking diagnostics. UI and repair controls: [ui/settings.md](ui/settings.md).

## Agent activity

A white arc inside the ring while that provider’s CLI is working (`AgentActivity`), polled every 2s on its **own** clock. Usage moves in percent; a turn starts and finishes in seconds.

“Working” is not “written to recently.” Both CLIs state the answer in the **tail** of live transcripts. Rules of thumb (detail and historical measurements: [providers/README.md](providers/README.md) and [decisions/reported-figures.md](decisions/reported-figures.md)):

- Skip bookkeeping records; an interrupt record ends the turn.
- Grace depends on what the turn is waiting for (model vs tool), from the **record timestamp**, not the file’s mtime.
- Unrecognised tail falls back to “written in the last 30s”.
- All live transcripts, not only the newest.
- Monitor stops when the panel is hidden or the display is asleep. The refresh loop reads `lastWrite` instead of scanning again.

The arc rides the **empty ring** between icon and usage stroke, Core Animation, not `TimelineView`. Reset `spinning` on disappear.

Providers without local transcripts (`keepsLocalTranscripts == false`) omit the mark rather than showing a permanent idle.

**`AppSettings.animatesRingActivity`, on by default, gates both this arc and the coloured mark a refresh draws over the usage arc** (`UsageRingView.isRefreshing`, same idea, the provider's own colour instead of white). Off, `isBusy`/`isRefreshing` are still tracked — nothing about what Pulse knows changes — but the ring draws neither turning mark and stops dimming the usage arc while a reading is fetched. One switch for both, since they are the same kind of cue (something is happening right now) drawn two ways.

## Countdown, rounding, colour

- `showsRemaining` (off by default) counts the same reading down instead of up. The **arc** follows the figure; **colour** still means closeness to the limit. No reading draws an empty track; spent fills the ring either way. Do not invert `usedFraction ?? 0`.
- Word on the card follows the figure (“left” vs “used”). Accessibility too.
- `UsageWindow.percentText`: nothing used → 0%; anything used → at least 1%. Both ends get the rounding rule, so used+left need not sum to 100.
- Colour is usage (`UsageTint`), not brand. Per-account `RingTint` is opt-in; spent colour still wins; convert through sRGB; no opacity.

## Forecast (`BurnRate`)

Off by default (`showsForecast`). One line under a limit: expected to last the window, or a coarse ETA. It is a **projection** and the copy says so.

- Rate = spent share / elapsed share from **one** reading. A trailing window of samples was tried and dropped (historical variance: [decisions/reported-figures.md](decisions/reported-figures.md)).
- Needs a reported percentage, reset, and `reportsLength`. Sort-key lengths fall out on their own.
- Time only when it lands before reset **and** inside two hours; beyond that the verdict is still said, without the time.
- Floor on elapsed share so a barely-open window is not divided into.
- The extra line is in `DetailCardLayout`’s budget.

## Spending history and the estimate (Settings only)

Two sources, and `UsageLedger.Origin` says which. **Local transcripts** (Claude Code, Codex) carry input/output/cache counts, so they can be priced — that is the money estimate. **Provider statistics** (Z.ai, Zhipu) come from the account and cover every machine, but report one token total per model, which cannot be priced: the card shows tokens and no money, and says so. `Provider.providesHistory` is the wider gate; `keepsLocalTranscripts` still gates the estimate. [providers/zai.md](providers/zai.md)

Neither money nor per-day history is reported by providers. Both are reconstructed from CLI transcripts (`UsageLedger`) at published API prices (`ModelPrices`, `models.dev`, cached a day). A model with no published price is left out, never given a plausible rate.

`keepsLocalTranscripts` (Claude Code and Codex today) gates the labelled estimate and the “working right now” mark — both need what only a transcript carries. **History is the wider `providesHistory`**, which Z.ai and Zhipu also answer from their own statistics. Everyone else **omits** those rather than showing zeroes. OpenCode keeps sessions in its own store, not the JSONL the ledger reads, so it stays false for now.

Ledger notes (verify again after changing the counting; historical independent check agreed to the cent on one machine):

- Claude Code `input_tokens` **excludes** cache tokens; Codex **includes** them. Normalise before pricing or the cache read is billed at the input rate.
- Codex reports a **running session total**; difference it. Summing per-turn `last_token_usage` double-counts (measured 6% high on one long session, historical).
- Buckets are quarter-hours. Per-file cache key is size + mtime; **filename carries the bucket format** (`ledger-2-*.json`). Changing the key shape without renaming leaves old entries parsing as nothing.
- Cost is computed after the cache, from tokens-per-model.

`BudgetEstimate` is **the one inferred number in the app**. Labelled wherever it appears, own settings group, provenance underneath. Withheld when inputs cannot carry it (under ~2% used, logs that start after the window opened, a window scoped to one model). Work on another machine is invisible; the caption says so.

`AccountUsageCard` is settings-only (`.task(id: historyKey)` — the pane **and** whether its account is on, so enabling one re-reads; `saveKey` also starts one out of band), not on the panel loop. Grid of money+tokens together. Codex may also show the account’s lifetime total from its own API, which is larger than this Mac’s logs.

The daily history chart has an immediate hover readout: the full plot height and the gaps select the nearest bar, showing its calendar date (including year) and a compact, localized token count (`TokenCount.short`, for example `5.24亿 tokens` or `600万 tokens` in Simplified Chinese). `ChartHoverOverlay` uses the actual bar centres; its guide and label stay inside the plot and leave the card's size unchanged. The guide, label and decorative card border cannot take pointer input. Leaving the plot or changing its data clears the selection. Dates and exact counts remain exposed per bar to VoiceOver. This uses continuous hover in the activating **Settings** window, not the non-key floating panel's input path.

## Resets, witnessed twice

`UsageWindow.hasTurnedOver(since:resetsAt:)` is the one test for "this limit turned over": a reset time that moved forward by more than a minute, or a fraction that dropped forty points, and never for a `balance`. Two things ask it — the reset notification ([notifications.md](notifications.md)) and `ResetWatch`, which the rail's animated mark celebrates from ([ui/rings-and-surface.md](ui/rings-and-surface.md)).

They keep **separate memories on purpose**. The alert rules' own bookkeeping sits behind "notifications are on", and the mark is not a notification: it has to work with every alert off. Sharing the rule and not the record is what stops the two drifting apart while leaving the announcement path untouched. `ResetWatch` takes **live readings only**, for the same reason the alert loop does — a cached reading can be lower than what was banked, and a figure that falls is exactly how a reset is recognised.
