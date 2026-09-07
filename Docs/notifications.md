# Notifications

Owns: when Pulse posts a system notification, what it says, and what it refuses to say. Settings copy and layout: [ui/settings.md](ui/settings.md). Where readings come from: [refresh-and-data.md](refresh-and-data.md).

Source: [`Sources/Pulse/UsageAlerts.swift`](../Sources/Pulse/UsageAlerts.swift). Settings: `AppSettings.alertThreshold` / `alertsOnReset` / `alertsOnFailure`. Entry point: `UsageStore.commit(_:for:)` — **every fetched reading goes through it, and only fetched ones**.

## What can be said

Four things, and nothing else. Each is something you would want to know *while looking at something else*, which is the test for belonging here rather than on the card.

| Alert | Fires when | Gated by |
|---|---|---|
| `approaching(percent:)` | A window's used share reaches the chosen step | `alertThreshold` |
| `spent` | The provider reports the window exhausted, or the share rounds *down* to 100 | `alertThreshold` |
| `reset` | A window that was warned about has unambiguously turned over | `alertsOnReset` + `alertThreshold` |
| `unreadable(_:)` | Three passes in a row produced nothing current, and the figures on screen are over 30 minutes old | `alertsOnFailure` |

All off by default. All ask for the **default sound**; the mute switch is macOS's own per-app "Play sound for notifications".

This was silent first, with a changelog note saying to add a sound in System Settings if you wanted one. **That note was wrong.** A notification with no `sound` is delivered silently, and the system switch cannot put one back — it only takes away one the app asked for. The choice was never quiet versus loud, it was a working off switch in the place people look for it versus no switch at all. `requestAuthorization` therefore asks for `[.alert, .sound]`: without `.sound` in the grant, `soundSetting` is disabled outright and every `content.sound` is dropped whatever the user does with the switch.

One rule for all four rather than sound only for the consequential two. macOS offers one switch per app, so a distinction drawn here would be one nobody could turn off and nobody could discover. And a silent banner on a second display, or behind a full-screen window, is a message that was never delivered — which is the opposite of the test these four had to pass to be here.

## Rules that are not obvious

**A first sighting starts at nothing announced**, so a limit already past the line is said once, immediately — including at the moment the setting is switched on or the threshold lowered, which is what `UsageStore.reconsiderAlerts()` is for. Left to the next pass it was up to half an hour of silence, from a setting somebody had just turned on to check. The other way round was tried and is wrong: someone who switches this on at 93% of their week gets silence and then a wall, which is the feature failing at the only job it has. The burst that rule was guarding against does not exist at the scale it imagined — this is at most one notification per limit, ever, and only for limits already over the chosen line.

The copy is a **status, not an event** — "92% used", never "just passed 90%" — so it stays true whenever it is read, including for a figure that has been true for days.

**100% is the provider's word.** `spent` comes from `UsageWindow.isExhausted`, or from a share that reaches 100 rounding *down* — 99.6% stays 99. Saying "spent" about a limit that still has something in it is the same invention as a made-up percentage, told at the worst possible moment. Same rule as [decisions/reported-figures.md](decisions/reported-figures.md).

**Limits are judged on `.live` readings only.** A `.stale` reading carries whatever the cache last banked, which can be *lower* than the figure already recorded — and a figure that falls is how a reset is detected. Running the cache through these rules announced a reset every time the network hiccuped.

**A reset needs unambiguous evidence.** Two signals: the provider's reset time moved forward by more than a minute, or the share dropped by 40 points or more. A drop of 5 points says nothing — a rolling window (Kimi's week, which can reset anywhere inside it) slides down a few points at a time without anything having reset.

**The announced step is cleared by that same evidence, not by the drop.** Clearing it on any 5-point dip re-armed a window that had not reset: 95% → 89% → 93% announced twice, and went on announcing for as long as the figure wobbled across the line. "At most one notification per limit" was on the tin and was not what it did. `oscillationDoesNotReAnnounce` pins it. A reset is also only announced for a window that was mentioned on the way up: "your 5-hour window reset" about a window that never passed 12% is a notification about nothing. That dependency is why the Settings row is greyed out while the threshold is Off.

**A push route going quiet is never a failure.** Claude Code's status line writes only while a session runs, so its capture is marked stale ten minutes after the last response — which says nobody has used Claude Code since lunch, not that a check failed. Counted as an outage it posted *"the last few checks didn't get through"* over a route where every check got through: an alert about something Pulse did not witness. `UsageSource.reportsOnlyWhenUsed(for:)` is the flag, and `AlertMemory` takes it as `staleMeansFailure`.

**It is a property of the route, not of the provider**, and asking it of the provider was a bug of its own: Claude Code has four routes and only one is a push. `.endpoint` and `.desktopApp` ask a server on every pass, and an **added** account has no status line at all — it is reached over HTTP and nothing else. Spared wholesale, a real outage went unreported for the provider Pulse is most about, while the identical outage on Codex still alerted. Only a primary Claude Code account on `.automatic` or `.tooling` is spared. `.automatic` is the conservative half of the trade: it can be answered by the capture, and nothing in a reading says which route produced it.

**`.stale` on its own is not a failure** for the rest, and this is the trap. `UsageCache.reconciled` hands back a stale reading for a *successful* fetch too: the status-line route calls its capture live for ten minutes, so a good capture can be older than what the endpoint banked a minute ago, and the newer banked one is returned instead — marked stale, every pass, for an account that is working. Counting that would have put "Claude Code can't be read" on screen for the provider most likely to hit it.

The reason is also gone by then: a failed fetch that the cache answers for arrives as `.stale`, with the `Unavailability` swallowed by the fallback. So a stale reading is asked the question it *can* answer, which is also the one the user cares about — **are the figures on the panel getting old**. Over `stalenessBeforeSaying` (30 minutes, the top of the adaptive interval, so at least one missed pass) it counts; under it, nothing.

**Unavailable is not the same as failed.** `AlertMemory.isFailure` is an exhaustive switch, and the question it asks is "did something that was working stop", not "is there anything to show". A credential that went bad or a request that did not get through counts. A setup step nobody has taken (`apiKeyMissing`, `notSignedIn`), an app that is not running (`antigravityNotRunning`), and a complete answer with no numbers in it (`grokBotNotIncluded`, `noLimitsReported`) do not — all of them stay true until somebody does something, and being told on a timer is nagging. A new `Unavailability` case must be classified in that switch; the compiler will insist.

**Three failures, not one.** Against an interval of 2–30 minutes that is six minutes to an hour and a half of silence. One failed pass is not news — these endpoints are undocumented, and a dropped connection answers for itself on the next tick. Reported once per outage: `reportedFailure` is cleared only by a reading that works.

## Memory

`AlertMemory` is persisted to `alerts.json` in [`PulseStorage.directory`](../Sources/Pulse/ModelPrices.swift), keyed by account id, then by window id. It has to be on disk: Pulse starts at login and runs while the Mac sleeps, so "have I already mentioned this" cannot live in memory alone — every relaunch would re-announce everything already over the line, which is what makes people switch notifications off for good.

It is kept up to date **whether or not anything can be posted**, so a build with no bundle, or a grant that was refused, cannot later wake up and announce a fortnight of crossings it slept through.

Every rule on this page is covered by `AlertMemoryTests` ([testing.md](testing.md)). Change one, change that.

`AlertMemory.alerts(for:as:…)` is pure apart from its own `self` — no disk, no notification centre, and the one clock reading it needs is taken at the edge and passed in as `now`. That is what makes these rules arguable.

`UsageAlerts.observe` returns immediately when `AppSettings.wantsAlerts` is false, so nothing is tracked and no file is written for a feature nobody has switched on. Without that guard the memory was written on the first pass of every launch — measured — and failures were counted up against accounts for nothing.

## Permission, and the unbundled build

`UNUserNotificationCenter.current()` does not fail politely without an app bundle: it raises, and takes the process with it. `swift run` produces a bare executable and is the normal way to work on this app, so every entry point is fenced by `UsageAlerts.isSupported` (`Bundle.main.bundleIdentifier != nil`) and the Settings row says why the switches are dead. **Test notifications from `./Scripts/bundle.sh`, never from `swift run`.**

Permission is asked for the moment a switch goes on in Settings — not at launch. A permission dialog at launch, for a feature nobody has switched on, is how an app gets denied for good.

The subtitle reports `UNAuthorizationStatus`, not the switches: a grant can be withdrawn in System Settings long after it was given, and a switch left on while macOS drops everything Pulse posts is a setting that lies. **It is re-read every time the settings window opens** (`refreshAuthorization`) — read once at launch and never again, the row said alerts were on while macOS discarded every one, which is the exact failure the field exists to report.

## Clicking one

Opens the Settings window on whichever pane was last shown. Every alert is about an account and everything you can do about any of them is in that window. Not the account's own pane: the selection is `SettingsView`'s own state, and threading it out through the window controller is not worth it for a feature one click away.

The delegate uses the **completion-handler** spelling of `userNotificationCenter(_:didReceive:withCompletionHandler:)`. These are optional protocol requirements, so a signature that doesn't match the selector is not an error — it is a method that is never called, and a click that does nothing looks exactly like one that was never wired up.
