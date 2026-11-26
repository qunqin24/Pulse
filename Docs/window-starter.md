# Window starter

Pulse can start a Claude Code or Codex usage window after a reset or while its countdown is idle. Sources: `Sources/Pulse/Usage/WindowPrimer.swift` (when) and `Sources/Pulse/Providers/WindowStarter.swift` (what is sent). Pinned by `Tests/PulseTests/WindowPrimerTests.swift`.

## Why

Claude Code's five-hour window and Codex's windows start at the **first message after a reset**, not at the reset. Somebody who comes back three hours after a reset starts a fresh window then, and if they run dry waits all of it out, where a window started at the reset would already be three hours through. The starter sends one "hi" to start the countdown.

Claude Code's weekly limit resets at a fixed hour whatever anybody does, so only its five hours are started. Codex's five hours and week both wait for a first message, so both are. Only reported, account-wide limits qualify. Scoped and estimated windows are excluded.

## It is not the providers' feature

Off by default, per provider, in the account's pane (**Start windows automatically**). Switching it on shows a confirmation that says, in every language Pulse ships, that this is not a feature of Anthropic or OpenAI, may be treated as getting around usage limits, could get the account restricted or suspended, and that Pulse is not responsible for what happens to the account. It turns on only from that confirmation's **I understand the risk, turn it on**.

It is also the one place Pulse acts rather than reads. It holds no credential for it: it runs the provider's own command-line tool, which sends as whoever that tool is signed in as — hence the first account of each provider only.

## When (`WindowPrimer`)

The switch and the first account must both be enabled. A single message can start all the account's idle windows. An idle Codex five-hour window can trigger that message while the weekly window continues counting down on its original clock.

- **A reset seen coming.** When a reading shows a future reset, Pulse sets a one-shot timer for one minute after that reset. A newer countdown updates the deadline. Once armed, this clock can still fire if the row disappears from a later reading.
- **An idle window.** Pulse also checks the rows in the latest raw live fetch, before display reconciliation drops expired windows. A timestamp at least a minute in the past qualifies immediately, including Codex’s Unix timestamp of zero. When a row has no reset timestamp, Pulse waits one minute from the first continuous live sighting. A future countdown during that minute replaces the idle wake. Missing rows, stale or unavailable readings, and the cache shown at launch cannot establish an idle window.
- **After a successful send.** Pulse refreshes the account. If the window still looks idle, no further idle start is scheduled. A future reset observed for that window after the send allows a subsequent idle reading to start it again, once that reset and its minute of grace have passed: a reading that contradicts a countdown still running (a row without its reset, from a fallback route) does not start it. Pulse keeps the reset and when it saw it across relaunch, so it can recognize the cycle even if it was closed over the reset. Restoring that evidence alone schedules no send.
- **After a failed send.** A missing tool, failed command, or timeout ends the attempt. Pulse records the result and requests one failure notification. The window can start again only after a later reset that Pulse observed in advance has passed its minute of grace. Refreshing or relaunching with the same idle window leaves it stopped. **Turning the switch back on** (through the risk confirmation) lets an idle window be tried once more: an attempt from before it was turned on no longer decides (`AppSettings.governingPrimerRun`); Last started still shows it.
- **An attempt is stamped with when it began**, not when it ended. A sibling window that resets during a two-minute attempt is a later reset and is started in its turn.

**Allowed hours** use the Mac's clock and are shared by both providers. The default is 07:00–23:00. An overnight range is valid, and equal start and end times allow the whole day. A start that would fall outside the selected hours waits until they open. Turning off the starter or account discards its pending wakes and reset evidence (`WindowPrimer.kept`). Kept, a passed reset made the timer come due every five seconds for as long as Pulse ran, only for `fire` to skip it.

## What is sent (`WindowStarter`)

The cheapest thing that counts, and nothing kept:

| | Claude Code | Codex |
|---|---|---|
| Tool | `claude` (`CommandLocator`: `PATH`, `~/.claude/local`, then the usual installer and version-manager folders) | `codex` (`CodexAppServer.locateCodex`, including the ChatGPT and Codex apps' own) |
| Model | `--model haiku` | The cheapest in Codex's own `model/list`: one named Luna, else one described as fast, efficient or mini, else the default (`cheapestCodexModel`). Read each time, because OpenAI renames these. |
| Nothing saved | `--no-session-persistence` | `exec --ephemeral` |
| Nothing else run | `--tools ""`, `--strict-mcp-config`, `--setting-sources project` (the empty folder's settings, so none of the user's hooks — sounds, notifications, Pulse's own status line) | `-s read-only`, `model_reasoning_effort="low"` |
| Where | `~/Library/Application Support/Pulse/Window starter`, empty and Pulse's own, so no project's settings or instructions are picked up | same |

Claude Code makes a project folder for that directory under `~/.claude/projects` even with persistence off — empty, but listed with the user's own. It is removed afterwards when it holds no file (`removeEmptyClaudeProject`); anything with a file in it is left alone.

Measured 2026-09-27: Codex answered in about eight seconds on `gpt-5.6-luna` at low effort, 7,876 tokens (mostly Codex's own instructions), and wrote no session file (136 before and after). Claude Code's run failed with "OAuth session expired and could not be refreshed" — the CLI's login on that Mac had lapsed while the desktop app's had not — which is reported in the pane rather than retried.

## What the pane shows

**Last started**: the time of the last attempt and, when it did not go through, why — the tool not found, not signed in or failing, or not answering within two minutes (`WindowStarter.deadline`). Stored in `AppSettings.primerRunTimes` / `primerRunOutcomes`. The pane keeps this record even if macOS denies notification permission. [Window starter notifications](notifications.md#window-starter-failures)
