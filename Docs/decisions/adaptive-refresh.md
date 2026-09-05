# Adaptive one-shot refresh, not a 60s loop

**Status:** still in force. **Evidence:** code (`AdaptiveRefresh`, `UsageStore.scheduleNext`); stall story historical (process gone before it was inspected).

A fixed minute spends the same requests at 3am as mid-session. Default wait is 2–30 minutes from signals that only ever lengthen the wait (activity metadata, movement of `windows`, hover, panel visibility, power/thermal/sleep).

The timer is one-shot because the wait changes each pass. An older `UsageStore` comment still said “owns the 60s refresh loop (the interval the Codex CLI itself uses)” — that is **not** what the code does.

## Stalls

`scheduleNext` only runs when a pass finishes. Field report: panel twenty hours stale, revived the moment Claude Code ran in a terminal (the *activity* path called `refresh()` while the timer path lay dead). Exact stall never reproduced.

Guards added to recover *whatever* the cause: `passCeiling`, `noteLooked` when the newest reading is older than twice the cadence, both wake notifications.

**Generation stamps are load-bearing.** Treating a stalled pass as gone without ending it left it writing later. Historical: a ring clicked during a stall showed 90%, six seconds later the ghost put 5% back; three passes, older overwrote newer.

**Never-read is not overdue.** `isOverdue` was true forever with no `observedAt` (nothing configured, or everyone refusing, including rate limits). `noteLooked` on every ring: historical thirteen calls for twelve rings — the opposite of “signals only lengthen the wait.”

Comparing readings must compare `windows` only; `observedAt` moves every successful fetch.

Current rules: [../refresh-and-data.md](../refresh-and-data.md).
