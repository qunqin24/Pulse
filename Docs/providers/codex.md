# Codex

Service: [`CodexUsageService.swift`](../../Sources/Pulse/Providers/CodexUsageService.swift). App-server fallback: [`CodexAppServer.swift`](../../Sources/Pulse/Providers/CodexAppServer.swift). Extra accounts: [authentication.md](authentication.md).

`keepsLocalTranscripts` is true. Extra accounts are supported. Source choice: endpoint vs `codex app-server`.

## Routes (primary)

Default `.automatic`:

1. **HTTP usage endpoint** — read OAuth credentials Codex already stored in `~/.codex/auth.json`, then `GET https://chatgpt.com/backend-api/wham/usage` for account-wide windows plus any per-model limits. Nothing stays running. Works even when the `codex` command is not findable.
2. On missing or refused token (401/403): **`codex app-server`** — Codex’s own documented JSON-RPC protocol. It is signed in on its own terms so it renews credentials itself, and it pushes `account/rateLimits/updated`.
3. Cache, then an unavailable reason.

The HTTP endpoint is **not** a public documented usage API. It is what Codex’s own client calls and can change without notice. The stored token expires; Codex refreshes it while you use Codex, and nothing refreshes it for Pulse on the primary account.

Pinned `.endpoint` reports a dead token rather than falling through. Pinned `.tooling` never tries HTTP.

The two answers have **different field names** (`used_percent` / `limit_window_seconds` / `reset_at` versus `usedPercent` / `windowDurationMins` / `resetsAt`), hence two parsers.

## Windows

Never assume a fixed pair. `primary` / `secondary` are not tied to particular durations; which exist depends on the plan — ChatGPT Pro has no 5-hour limit at all, only the tiers below it do. A window’s kind is derived from its duration. The UI renders however many come back.

Codex reports `limit_reached` / `allowed` per group plus top-level `rate_limit_reached_type` and `spend_control.reached`. Those flags describe a whole group, which may hold both a 5-hour and a weekly window, so spent is pinned to the fullest window rather than smeared across both.

## Limit reset credits

How many one-off credits that clear a rate limit early the account holds. Only `codex app-server` reports them, under `rateLimitResetCredits` in `account/rateLimits/read` (`availableCount`, and `credits[]` with a `status` and `expiresAt`).

- **Settings, always:** the Usage history card leads with the count and the soonest expiry, fetched when that pane opens (`CodexAccountUsageService.fetch`).
- **The panel's card, opt-in:** **Reset credits on the card** in Codex's pane (`AppSettings.showsCodexResetCredits`, off by default; issue #67). The switch asks the store directly rather than through `onChange`, which would refetch every provider for one row. While it is on, every Codex refresh — the full pass or a click on the ring — also asks the app server for `account/rateLimits/read` (`UsageStore.refreshCodexResetCredits`), beside the ring's own fetch rather than inside it, so a slow app server never holds the ring up. Off by default because it starts or asks that process, which somebody reading Codex from its usage endpoint alone would otherwise never run. First account only: the app server reads the login the CLI saved.
- **Never a number Pulse worked out.** A reply without the reset-credit block, or an app server that did not answer, is `CodexResetCredits.unreported`, which the card says as "Not available". No `codex` anywhere Pulse looks is `.codexMissing`, said as "codex not found": the remedy differs, and one message for both left two Macs with several credits guessing which (#67, after 1.5.0).
- **Where `codex` is looked for** (`CodexAppServer.candidates`): `PATH`, Homebrew, `~/.local/bin`, bun, Volta, `~/.npm-global/bin`, pnpm, **the ChatGPT and Codex desktop apps' own `codex`** — `Contents/Resources/codex-cli/bin/codex` since ChatGPT 26.924, `Contents/Resources/codex` before it, both kept (`CodexAppServer.bundled`; the layout moved the day 1.5.1 shipped, #67) — (wherever Launch Services says the app with bundle id `com.openai.codex` is, then `/Applications` and `~/Applications` — somebody who uses Codex only through one of those apps has no other), then nvm, fnm and mise version folders, newest first. A block with no `availableCount` counts the `available` entries it lists. Settings' history card takes its count from the same `resetCredits(in:)`, so the two cannot disagree. When two asks overlap, only the latest may write: an app server timing out must not put "Not available" over a count a later ask brought back. Under the count the card shows when the soonest available credit expires, to the minute and with the year (`UsageDetailCard.resetCreditExpiryText`), because that decides whether to spend one now (#67). No row when there is none to spend or Codex gave no date.

## Plan name

The plan comes back as an internal tier name, not the name on the plan — `prolite` is the 5× Pro tier. `CodexUsageService.planName` maps the ones we know and passes anything else through verbatim rather than blanking it.

## Credit balance

`credits.balance` arrives as a decimal string with ten places (`"2500.0000000000"`), on both routes. `CodexUsageService.creditBalance` shows it as a number in the reader's locale with at most two places — credits, not money, so no currency. A balance that is not a number is passed through; `unlimited: true` is no balance at all.

## App-server / SIGPIPE / PATH

**The folder `codex` was found in leads the helper's `PATH`** (`BoundedProcess.environment(leading:over:)`, which every launcher of another tool's CLI uses — Kiro's ACP client, `arkcli`, Alibaba's `bl` too). An npm install of `codex` is a Node script (`#!/usr/bin/env node`), and a GUI app's `PATH` has no `node` in it, so a `codex` found under `~/.nvm/versions/node/<v>/bin` started and died at once with `env: node: No such file or directory`: nothing only the app server reports — reset credits included — ever arrived, while the rings, read from the endpoint, looked fine (reported under #67; reproduced with `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and fixed: the same probe then read three credits). nvm, Homebrew and Volta put `node` beside the `codex` they installed. The path as found, not the link resolved: nvm's `codex` links into `lib/node_modules`, where there is no `node`.

**SIGPIPE is ignored process-wide** (`AppDelegate`), and it has to be. Writing to a pipe whose far end has closed raises it; default is to kill the process. The helper exiting, being killed with the terminal it was started from, or the user quitting Codex took Pulse down with it (`Terminated due to signal 13`). Ignored, the write returns `EPIPE` and `CodexAppServer.write` drops the helper so the next call starts a fresh one.

**Historical evidence:** reproduced both ways against a process that had already exited — unguarded the probe was killed before it could print a line; guarded it reported “Broken pipe” and carried on.

**The reader has to come off the pipe at EOF, and it has to come off synchronously.** `availableData` returning empty means the far end closed. A descriptor in that state is readable for ever, so a `readabilityHandler` that merely returns is called again straight away — a core at 100% for as long as the app runs, over a helper that has already exited. Shipped in 1.2.0 and reported as [#25](https://github.com/qunqin24/Pulse/issues/25): three spinning threads, 290% CPU, eleven hours, no child process left to blame. The handler clears **itself**, on the queue it is called on; hopping to the actor first leaves exactly the window the loop needs.

Two layers made it worse than one stuck handler. `ensureRunning` returns early while the process lives and starts a replacement when it does not — but it left the dead one's pipe wired up, so every restart added another spinning thread. It now tears the old reader down first, `shutDown` does the same, and EOF fails whatever was still pending instead of making it wait out the twenty-second timeout. A restart installing a new reader while the old one is still closing is fenced by handle identity, so a stale EOF cannot tear down its replacement.

`VolcengineUsageService` has cleared its handler at EOF since it was written; this path simply never learned it. `CodexAppServerTests` drives the reader against a plain `Pipe`, so it needs no `codex` on the machine.

Each pending RPC owns its 20-second timeout. A reply, write failure, EOF or shutdown completes it once and cancels that task. Request IDs continue across helper restarts, so an old callback cannot complete a new request. Closing the reader discards incomplete JSON, and queued data is accepted only from the current pipe. `RPCRequestLifecycleTests` exercises reconnects and deadlines with isolated subprocesses; it does not call a signed-in Codex.

Locating the executable cannot rely on `PATH`: a GUI app inherits almost none of it. `CodexAppServer.locateCodex` checks usual install locations, including versioned Node directories.

## Proxies

The HTTP endpoint uses Pulse's Network setting: macOS's proxy by default (**Follow System**), macOS's proxy and never a direct connection (**System Proxy Only**), no proxy at all (**No Proxy**), or Pulse's own HTTP/SOCKS5 proxy (**Custom Proxy**). On a machine behind a VPN, following the system is usually what you want (the endpoint may only be reachable through it). A tunnel that stumbles surfaces as a Pulse error, typically `-1005 networkConnectionLost`; transient `URLError`s are retried a couple of times.

`codex app-server` is different: it is a child process rather than a `URLSession`. Manual HTTP starts it with `HTTP_PROXY` / `HTTPS_PROXY`, manual SOCKS5 with `ALL_PROXY`, and both with loopback in `NO_PROXY`. Changing the proxy shuts down a running helper; the next request starts it with the new environment. Follow System and System Proxy Only inject nothing and preserves the environment Pulse itself inherited; No Proxy removes every proxy variable it would have inherited. Full boundary: [../networking.md](../networking.md).

## Added accounts

`fetch(account:credentials:)` uses Pulse’s stored tokens. Extra-account sign-in is **device code**, not redirect. Full published scopes, including connector scopes that looked optional and were not. See [authentication.md](authentication.md).

Codex’s usage endpoint wants the account named in a header of its own; `AccountCredentials.accountID` is taken from the token.

Settings can also show the account’s real lifetime total from `account/usage/read`, which is **larger than anything on this Mac**. Without that row the local ledger total reads as simply wrong.

## Ledger

Codex’s `input_tokens` **includes** cached tokens; `cached_input_tokens` is the subset. Session usage is a **running total** — difference it, do not sum per-turn `last_token_usage` (measured 6% high on one long session). Shared ledger rules: [`../refresh-and-data.md`](../refresh-and-data.md).

## Signs of a weaker model

Settings › Codex › **Signs of a weaker model** (`CodexSignals`, `CodexSignalReader`, `CodexSignalsGroup`). Requested 2026-10-03 after community tools claiming to detect a "nerfed" Codex; what each does and why only this much is taken:

| Tool | What it reads | Taken? |
|---|---|---|
| [codex-routing-detector](https://github.com/darkdarkcocoa/codex-routing-detector) | `response.model` from a WebSocket trace of a probe it sends (≈12–16k tokens), or a TLS-intercepting proxy | **No** — sends on the user's behalf, or sits in their traffic |
| [is-gpt-nerfed](https://github.com/kiyoakii/is-gpt-nerfed) + [ModelTrace](https://github.com/xqy2006/ModelTrace) | rollout settings (passive); a random-integer fingerprint from forked probes (active) | The passive half only |
| 516 / `518n−2` ([openai/codex#30364](https://github.com/openai/codex/issues/30364), [codexcomp](https://github.com/dzshzx/codexcomp)) | `reasoning_output_tokens` per response | **Yes** |
| [Codexshitdetector](https://github.com/pikapikaspeedup/Codexshitdetector) | first response of a turn has reasoning > 0 ⇒ "downgraded" | **No** — no evidence offered, and on this Mac 80–100% of every model's turns qualify |

**What cannot be known.** Which model the server ran is never on disk: `codex-rs` reads it from an `openai-model` header and its mismatch warning (`ModelReroute`) is transient in `rollout/src/policy.rs`; `~/.codex/logs_2.sqlite` held none of it either (checked). So the group says **signs**, and the footnote says so.

**Reasoning stopped at fixed points.** Per response: `event_msg` `token_count` → `info.last_token_usage.reasoning_output_tokens`, under the model of the latest `turn_context`. Codex writes the same count more than once; a repeat of `total_token_usage` is dropped. A response is on the lattice when `reasoning ≥ 516` and `(reasoning + 2) % 518 == 0`; chance puts about 1 in 518 there. Per model: the share of responses that reached 516 and stopped on it, **shown as a figure with no verdict**; **Too few to tell** under 20 such responses. Until 2026-10-14 a share of ≥ 5% (25× chance) with at least 5 hits was tagged **Possibly weakened**. That compared each model with chance rather than with itself, and a model that has the lattice at all sits far above chance all the time: measured 2026-10-14 on a Mac with 1,991 sessions, gpt-6-astra 72%, gpt-5.5 65%, gpt-6.1-sol 60%, gpt-5.6-sol 9%; gpt-6-astra stayed within 62–77% and gpt-5.6-sol within 6–13% every week, and neither moved with reasoning effort or hour of day — seven models of ten wore the tag permanently, and it told the reader nothing. The evidence in #30364 is a *change* (gpt-5.5 rising from 0.11% to 53% in four months), and nothing on disk says whether a stop on the lattice is a cut or worse work; the footnote says so. Codex's own reviewer (`codex-auto-review`) is left out. On this Mac, all sessions (2026-10-03, fork copies skipped): gpt-5.5 126/279, gpt-5.6-sol 19/182, gpt-5.4 10/33 on the lattice; every `-codex` model 0 — the issue's finding, reproduced.

**Settings quietly lowered.** From Codex **0.144** every change the user makes is written as `event_msg` `thread_settings_applied` (`thread_settings.model`, `.reasoning_effort`), and it takes effect at the **next** `task_started` — a change made while a turn runs is applied after that turn's `turn_context` (measured: judging against the latest event instead flagged two such turns falsely). A turn is a change when its `turn_context.model` differs from, or its `effort` ranks below (`none < minimal < low < medium < high < xhigh < max < ultra`, the order of `supported_reasoning_levels` in `~/.codex/models_cache.json`), the settings in force at its start (or the previous turn's, where none was applied). A level missing from that list is never compared — until 2026-10-14 the list stopped at `xhigh`, so a turn lowered from `max` or `ultra` passed unseen. Sub-agent turns (`root_turn_id` ≠ `turn_id`) are skipped. **Judged only where the user's changes are on record**: Codex 0.144 or later, at least one `thread_settings_applied`, and not one of Codex's own helpers (`session_meta.source` an object, or a `parent_thread_id` — guardians, sub-agents). Sessions before 0.144 record no change at all, so a `/model` there looks exactly like a silent switch — on this Mac 20 such "changes" in old sessions, all ordinary switches; a newer session with nothing applied is compared turn to turn only, with the same blind spot. The `auto-review` model is never a change in either direction. On the 21 judged sessions here, none. All of this is what Codex *asked for*, not what the server ran.

**The context window is not judged.** `token_count`'s `info.model_context_window` is computed by Codex, not reported by the server: the configured window (`model_context_window` in `~/.codex/config.toml`, else the model's `context_window` in `models_cache.json`) times its `effective_context_window_percent`. Checked 2026-10-14 on a Mac with 1,991 sessions: every value seen was 95% of a round window (272,000, 300,000, 372,000, or 872,000 — the model's `max_context_window`), and the October changes followed edits to `config.toml`, not the service tier or the model. Until then a shrink under the same model was listed as "context cut"; three of the four on that Mac came from such an edit, and the fourth was not traced.

**Forks copy their parent first.** A session with `forked_from_id` begins with the parent's lines — `turn_context`, `token_count`, `task_started` with placeholder ids — all stamped with the fork's own moment (measured: 1,690 copied responses, every one within 2 s of the fork's header; the fork's own work after). Lines within `replayWindow` (2 s) of the header are skipped, or a month-old response would be counted twice and dated today: before this, gpt-5.6-sol read 30/270.

**Reading.** `~/.codex/sessions` and `~/.codex/archived_sessions`, `rollout-*.jsonl`, files older than the period skipped by modification time; only lines naming one of five event types are decoded. Each file's facts are kept in memory against its size and modification time — **never from a cancelled read**: a cancelled task stops `LogLines` yielding, and the part read would have stood for the whole file until it changed (switching the period or leaving the pane cancels). Measured here: 318 files, 454 MB, 1.4 s for all, 0.03 s for 30 days. `CodexSignalsTests` uses synthetic sessions.

## Service status

Settings › Codex › **Service status** (`ServiceStatus`, `ServiceStatusGroup`, `StatusPage.openAI`): one row per component of the **Codex** group on status.openai.com — Codex Web, Codex API, CLI, VS Code extension as of 2026-10-04 — each with the state now, a bar a day for 91 days, and the page's uptime figure, drawn the way the page draws them; then a row that opens the page. Requested 2026-10-04, after CodexBar's status rows; the layout is status.claude.com's (bars, then "90 days ago — uptime — Today"), with each page's own colours. Claude Code's twin: [claude-code.md](claude-code.md#service-status).

**The feeds are the page's own, under `/proxy/status.openai.com`.** The page is hosted on incident.io; its Statuspage-compatible `/api/v2/summary.json` has no Codex group at all (checked 2026-10-04: only "Codex in ChatGPT Desktop", under ChatGPT). The proxy summary is what the page is drawn from: `summary.structure.items[].group` holds the groups and their components (`hidden` ones skipped), and `summary.affected_components[]` lists `{component_id, status}` for each one not operational. **Not listed means operational** — that is how the feed says it. States: `degraded_performance`, `partial_outage`, `full_outage` (and Statuspage's `major_outage`), `under_maintenance`; anything else is shown as unrecognised, never as operational. The incident shape comes from CodexBar's parser and tests (MIT), as none has been seen live.

**History: `component_impacts?start_at=…&end_at=…`**, the request the page makes — from the start of the local day 90 days back to the end of today, 91 days. It returns `component_impacts[]` (`component_id`, `status`, `start_at`, `end_at`, null while ongoing) and `component_uptimes[]` (`uptime` as a string, `data_available_since`). **That list also holds each group's own figure, with `status_page_component_group_id` and no `component_id`** — requiring the id dropped the whole history in the app while a fixture trimmed to Codex passed, so entries are decoded one by one and an odd one is skipped, and the fixture keeps every uptime entry. **A day takes the worst impact overlapping it**; a day that ended before `data_available_since` has no record and is drawn faint. Checked 2026-10-04 against the page, all four Codex rows, bar for bar, in UTC+8 — that comparison is `ServiceStatusTests`. The page's **group** row aggregates differently (two days where one component was degraded drew green there), so Pulse draws components only. The uptime is the page's figure, passed through, never computed; without one the line has no figure.

**Colours are the page's** (read off it 2026-10-04): operational `#24C19A`, degraded `#FBBF24`, partial `#F5785C`, full `#F87171`, rounded bars. Maintenance was not on the page; `#60A5FA` is a guess. Hovering a bar names its day and state.

**The pane reads when it opens and every five minutes while it stays open** (`ServiceStatus.checkInterval`); leaving it stops that, and a later read that fails shows "couldn't read" rather than leaving old rows to pass for current. Both feeds at once, through `NetworkSession` like every other request ([../networking.md](../networking.md)). The only background read is the outage notification's, which is off by default, reads the current state alone, and only for a provider switched on ([../notifications.md](../notifications.md)). Shown on every enabled Codex account's pane, since it is about the service; a disabled one fetches nothing. A summary that can't be fetched, doesn't parse, or has no Codex group is **no reading**: the group says it couldn't read the page, rather than leaving rows to read as healthy. A history that fails leaves the current states without bars.

## First run

Presence of `~/.codex`, never its contents.
