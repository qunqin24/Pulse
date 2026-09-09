# Testing

Owns: what `swift test` covers, what it deliberately does not, and the two conventions the suite depends on. Toolchain and build flags: [build-from-source.md](build-from-source.md).

```bash
swift test
```

There was no test target until 2026-09-07. What prompted one was not a policy: two real faults were found by reading code in a single afternoon — Antigravity taking the first matching helper and giving up when the one that answers was second, and `.stale` being treated as a failed fetch when a *successful* one produces it too — and the notification rules had shipped with nothing proving them at all.

## What is covered

| Suite | Covers |
|---|---|
| `AlertMemoryTests` | Every notification rule: thresholds, spent, resets, the failure streak, the stale-age gate. [notifications.md](notifications.md) |
| `AlertsThroughTheCacheTests` | The same rules reached the way production reaches them: service → `UsageCache.reconciled` → state machine |
| `NotificationAuthorizationTests` | An injected authorization decision, concurrent requests, no warning consumed while a grant is pending, and the foreground delegate selector; no system permission or notification delivery |
| `UsageCacheTests` | `reconciled` — fallback, "a reading never goes backwards", credentials that must not be papered over, expiry |
| `UsageWindowTests` | The reported figure at both ends, and when the window clock may divide |
| `RailGeometryTests` | Every ring the rail draws is reachable: each centre inside the rail, the last ring whole rather than clipped, each ring hit-testing to its own slot — across left/right/top and docked/floating. Plus the count itself: `shownSlotCount` is called with a reading that really splits, so a window measuring its rects in accounts rather than rings fails a test instead of a click (verified by reintroducing the bug) |
| `RailOffsetTests` | The rail's offsets measured against the frame the window was **granted**, not the one it asked for — the panel is taller than a laptop's usable screen and AppKit refuses that frame. [ui/panel-geometry.md](ui/panel-geometry.md) |
| `ZaiHistoryReadTests` | What a history read found *out*: no key is not a failed request, and a successful reply with no rows is an answer |
| `ActiveDisplayTests` | Following the pointer onto another display: the move keeps dock and both ratios, a held panel refuses and the refusal is *reported* so the display stays on offer, and returning to the display it is already on is quiet rather than a refusal. [ui/panel-geometry.md](ui/panel-geometry.md) |
| `PanelHoldTests` | Nothing re-places the panel while it is held — including the gap between mouse-down and the first movement, where `isDragging` is still false. [ui/input.md](ui/input.md) |
| `RailSlotTests` | The rail's order: when a split account becomes two slots, when it stays one, and that unscoped windows never form a group. [ui/rings-and-surface.md](ui/rings-and-surface.md) |
| `AntigravityParsingTests` | A captured `RetrieveUserQuotaSummary` reply → `[UsageWindow]` |
| `UsageReportTests` | The `--json` shape, which is a contract other people build on. [json-output.md](json-output.md) |
| `VolcengineSignerTests` | Volcengine's request signature, cross-checked against a second implementation |
| `ZaiHistoryTests` | The statistics endpoint's shape → a day-by-day ledger, and what may not be said about it |
| `SecondWindowTests` | Which limit the second ring shows: the fullest in the headline's own model group, and the fallback when that group holds nothing more |
| `ZaiQuotaTests` | The GLM Coding Plan quota reply → windows, including a spend of zero being a reading rather than a gap |
| `ZaiErrorTests` | What the GLM Coding Plan's HTTP-200 refusals mean, from envelopes taken off both live hosts |
| `VolcengineParsingTests` | Ark's three reply shapes, from second-hand fixtures. [providers/volcengine.md](providers/volcengine.md) |
| `VolcengineProcessTests` | The `arkcli` subprocess: a stderr flood, an output flood, a child that ignores SIGTERM, one that closes its pipes and lives, descendant termination after the leader exits (with and without TERM handling), and how a non-zero exit is classified |
| `CommandCodeParsingTests` | Command Code's four replies → windows, from second-hand fixtures. Chiefly **which question the monthly row answers**: a running plan against its inferred, labelled grant; an account without one against the pool it bought; a plan the table cannot size against *nothing* — not zero, not the pool. Plus a subscription lookup that never answered still finding the plan in the credits reply, epoch-millisecond resets, `exceeded` outranking the arithmetic, and equal lengths not shuffling. [providers/command-code.md](providers/command-code.md) |

## What is not, and why

**No UI tests.** The panel is an accessory `NSPanel` whose hover cannot be driven by synthesised events — `hitTest` and synthetic `NSEvent`s both reported a handle as perfectly reachable while real clicks were being dropped, which is the lesson in [ui/input.md](ui/input.md). A UI test here would report the same thing.

**A rule test is not a chain test.** `AlertMemoryTests` hands the state machine readings directly, and two rounds of review missed a defect that lives *between* the service and the machine: the cache swaps a failure for cached figures and the reason is gone with it. Where a rule depends on something upstream, test it through that thing.

**No live provider calls.** Every route needs somebody's real credential and answers differently by plan. Fixtures are captured by hand from a real reply and committed; the capture is recorded in that provider's page.

**A fixture written from another project's parser, or from a vendor's own shipped client, is second-hand**, and has to say so where it lives. Volcengine's are, because nobody here holds that plan; Command Code's are written from the field names in its published npm bundle. A captured one replaces either the moment somebody with an account can produce one. Second-hand is enough to pin a shape against change, and not enough to claim the shape is right.

**A subprocess test really spawns one.** `VolcengineProcessTests` runs `/bin/sh` on purpose: the two failures it covers — a child that fills the stderr pipe, and one that never exits — cannot be produced by a fake, and neither is visible by reading the code. The first version of that runner looked correct and had both; the *second* looked correct and still hung on a child that ignored SIGTERM. Neither was findable by reading. The deadline is a parameter so a test can use one second.

**No network, no clock, no disk in a rule test.** `AlertMemory.alerts` takes `now` as an argument for exactly this reason. `UsageCache.init(file:)` takes a path for exactly this reason. Anything that has to reach for a real one is not a rule test.

## Two conventions

**The executable target is tested directly** (`@testable import Pulse`), not through a library split. Pulse is one app, not a framework with an app on top; carving 63 files into two targets to make them reachable would be a refactor in service of the test runner. SwiftPM has allowed this since Swift 5.5.

**A symbol may be `internal` instead of `private` so a test can hold it**, and when it is, the comment says so and says not to tidy it back. `AntigravityUsageService.Reply` and `windows(from:)` are the first two. Nothing outside the module can see them either way; the difference is only whether the fixture test compiles.

## Fixtures

`Tests/PulseTests/Fixtures/`, copied whole into the test bundle so a schema change diffs readably. Read them with `Bundle.module.url(forResource:withExtension:subdirectory:)`.

Captured payloads carry no account name, email, or token — check before committing one. A quota reply is bucket ids, display names, fractions and reset times, and that is all it should be.
