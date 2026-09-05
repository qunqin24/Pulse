# Refresh, cache, activity, history

Pulse shows **figures the provider reported**. It does not invent a usage percentage from local token counts. If a provider reports no figure, the UI says so. The money estimate in Settings is the labelled exception.

Per-provider HTTP, cookies, and login: [providers/README.md](providers/README.md). Why percentages stay reported: [decisions/reported-figures.md](decisions/reported-figures.md).

## Refresh loop

`UsageStore` is `@Observable`. The interval is **adaptive by default** (`AdaptiveRefresh`): **2–30 minutes** (`floor` 120s, `ceiling` 1800s). It is **not** a 60-second repeating timer. (An older comment on `UsageStore` said that; the code schedules a one-shot.)

Because the wait changes each pass, `scheduleNext` sets `Timer.scheduledTimer(..., repeats: false)` and reschedules after every refresh.

Signals (every one is a reason to wait **longer**, never shorter):

- CLI transcript metadata (`AgentActivity.lastWrite`) — not a second file scan
- Whether reported `windows` actually moved (`observedAt` is ignored for this comparison or every fetch looks like a change)
- Whether the rail was hovered (`noteLooked`)
- Whether the panel is on screen
- Low power, thermal, display asleep

Manual interval in Settings still exists. The group is named **Refresh**, not Updates (the app has Sparkle now).

### Stalls

The timer is not a promise: `scheduleNext` only runs when a pass **finishes**. A pass that never returns takes the whole schedule with it.

Guards:

- A pass in flight longer than `passCeiling` (180s) is treated as gone (full and per-account paths).
- `noteLooked` refreshes when the newest reading is older than twice the chosen cadence — but **never-read is not overdue** (`observedAt` missing). There is a cooldown: sweeping the rail must not fire one request per ring.
- Observe `NSWorkspace.didWakeNotification` **and** `screensDidWake`; they are different notifications.

Releasing a stalled pass is not ending it. Abandoned work still writes when it answers. Every pass is stamped (`generation` / `currentPass`) and must still be current before writing `usage` or clearing flags.

Disabled providers are not fetched. A provider pane can still refresh that account by name.

`windowSeconds` is not evidence that a length was reported. `UsageWindow.reportsLength` distinguishes a real duration from a sort key. The window-clock arc and burn-rate divide only when the length was actually stated.

## Cache

`UsageCache` keeps the last **`.live`** reading per account so a refusal can show numbers with a date instead of an empty error. They come back marked `.stale` (the card’s “as of” line).

- A window whose **reset time has passed is dropped**, not aged. If every window has reset, report the error.
- 24h cap for windows that never say when they reset.
- Missing credentials are **not** papered over (`.apiKeyMissing`, `.ollamaSessionMissing`, `.signedOut`, `.claudeDesktopNotSignedIn`, `.claudeDesktopKeyRefused`).
- `.live` is not the same as “newest.” A route can mark a capture live for a few minutes while an earlier endpoint reading has a later `observedAt`. `reconciled` prefers the later stamp.
- `UsageStore.start` paints the cache before the first request so the rail is not blank on a cold start. Cache never undoes a fetch that has already landed.

Which unavailability cases a given provider emits: [providers/README.md](providers/README.md).

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

Neither money nor per-day history is reported by providers. Both are reconstructed from CLI transcripts (`UsageLedger`) at published API prices (`ModelPrices`, `models.dev`, cached a day). A model with no published price is left out, never given a plausible rate.

Only providers with `keepsLocalTranscripts` (Claude Code and Codex today) get history, the labelled estimate, and the “working right now” mark. Everyone else **omits** those rather than showing zeroes. OpenCode keeps sessions in its own store, not the JSONL the ledger reads, so it stays false for now.

Ledger notes (verify again after changing the counting; historical independent check agreed to the cent on one machine):

- Claude Code `input_tokens` **excludes** cache tokens; Codex **includes** them. Normalise before pricing or the cache read is billed at the input rate.
- Codex reports a **running session total**; difference it. Summing per-turn `last_token_usage` double-counts (measured 6% high on one long session, historical).
- Buckets are quarter-hours. Per-file cache key is size + mtime; **filename carries the bucket format** (`ledger-2-*.json`). Changing the key shape without renaming leaves old entries parsing as nothing.
- Cost is computed after the cache, from tokens-per-model.

`BudgetEstimate` is **the one inferred number in the app**. Labelled wherever it appears, own settings group, provenance underneath. Withheld when inputs cannot carry it (under ~2% used, logs that start after the window opened, a window scoped to one model). Work on another machine is invisible; the caption says so.

`AccountUsageCard` is settings-only (`.task(id: pane)`), not on the panel loop. Grid of money+tokens together. Codex may also show the account’s lifetime total from its own API, which is larger than this Mac’s logs.
